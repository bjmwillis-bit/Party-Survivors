extends Node3D
## The horde. Enemies are plain data in arrays (not individual nodes) and are
## drawn in one batch with a MultiMesh, so hundreds can be on screen at once.
##
## A spatial grid (buckets of nearby enemies) keeps "who is near this point?"
## questions fast, for attacks and for enemies pushing each other apart.

const MAX_ENEMIES := 650
const CELL := 0.8 # about the size of one enemy, so neighbour checks stay small

# Enemy types. Each list below has one entry per type, in this order.
enum { SHAMBLER, RUNNER, SWARMLING, ELITE, MINIBOSS, FINAL_BOSS, GOBLIN }
const HP := [18.0, 9.0, 5.0, 220.0, 650.0, 3200.0, 150.0]
const SPEED := [2.5, 4.3, 4.8, 2.3, 2.0, 1.8, 5.5]
const SCALE := [1.0, 0.75, 0.55, 1.6, 2.3, 3.3, 0.8]
const KNOCK_TAKEN := [1.0, 1.4, 1.6, 0.4, 0.15, 0.05, 1.0]
const STUN_TAKEN := [1.0, 1.0, 1.0, 0.6, 0.3, 0.0, 1.0] # how much of a stun sticks
const HIT_MULT := [1.0, 0.8, 0.35, 2.0, 3.0, 4.0, 0.0] # blow damage (goblins don't fight)
const XP_DROP := [1, 1, 1, 10, 30, 0, 0]
const COLORS := [
	Color(0.36, 0.22, 0.2), Color(0.58, 0.44, 0.24), Color(0.72, 0.64, 0.46),
	Color(0.55, 0.15, 0.5), Color(0.5, 0.05, 0.05), Color(0.16, 0.02, 0.02),
	Color(1.0, 0.82, 0.2),
]
const GOBLIN_LIFE := 20.0 # seconds before an uncaught goblin escapes
const BIG_HIT := 40.0 # hits at least this big show a damage number
const HIT_DAMAGE := 6.0 # per blow, before the toughness ramp
const HIT_INTERVAL := 1.0 # each enemy in reach strikes once a second
const HIT_WINDUP := 0.45 # delay before the first blow after reaching a hero
const STUN_TINT := Color(0.6, 0.72, 1.0)
const SLOW_TINT := Color(0.55, 0.45, 0.75)

var count := 0
var pos := PackedVector2Array() # x and z on the ground
var knock := PackedVector2Array()
var hp := PackedFloat32Array()
var flash := PackedFloat32Array()
var kind := PackedByteArray()
var yaw := PackedFloat32Array()
var sep := PackedVector2Array() # last push-apart force (recomputed every other frame)
var stun_t := PackedFloat32Array() # seconds left stunned
var taunt_t := PackedFloat32Array() # seconds left taunted
var taunt_hero := PackedByteArray() # which hero (index in the party) taunted them
var atk_cd := PackedFloat32Array() # seconds until this enemy's next blow
var slow_t := PackedFloat32Array() # seconds left slowed
var slow_amt := PackedFloat32Array() # how much slower (0.5 = half speed)
var dot_t := PackedFloat32Array() # seconds left taking damage over time
var dot_dmg := PackedFloat32Array() # damage per second-tick
var dot_acc := PackedFloat32Array()
var age := PackedFloat32Array() # seconds since spawning

## A swarm event doubles spawning, mostly tiny swarmlings.
var swarm_active := false

## How long the horde took last frame, in milliseconds (for tuning).
var cost_ms := 0.0

var _grid := {}
var _spawn_acc := 0.0
var _time := 0.0
var _mm: MultiMesh
var _buffer := PackedFloat32Array() # 16 numbers per enemy: 12 for position/rotation/size, 4 for colour
var _frame := 0


func _ready() -> void:
	pos.resize(MAX_ENEMIES)
	knock.resize(MAX_ENEMIES)
	hp.resize(MAX_ENEMIES)
	flash.resize(MAX_ENEMIES)
	kind.resize(MAX_ENEMIES)
	yaw.resize(MAX_ENEMIES)
	sep.resize(MAX_ENEMIES)
	stun_t.resize(MAX_ENEMIES)
	taunt_t.resize(MAX_ENEMIES)
	taunt_hero.resize(MAX_ENEMIES)
	atk_cd.resize(MAX_ENEMIES)
	slow_t.resize(MAX_ENEMIES)
	slow_amt.resize(MAX_ENEMIES)
	age.resize(MAX_ENEMIES)
	dot_t.resize(MAX_ENEMIES)
	dot_dmg.resize(MAX_ENEMIES)
	dot_acc.resize(MAX_ENEMIES)
	_buffer.resize(MAX_ENEMIES * 16)

	var body := CapsuleMesh.new()
	body.radius = 0.38
	body.height = 1.3
	body.radial_segments = 6
	body.rings = 1
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = Game.flat_mesh(body)
	_mm.instance_count = MAX_ENEMIES
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var mat := Game.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mmi.material_override = mat
	add_child(mmi)


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_time += delta
	_frame += 1
	_remove_dead()
	_spawn(delta)
	_rebuild_grid()
	_move(delta)
	_render()
	cost_ms = (Time.get_ticks_usec() - start) / 1000.0


# --- Questions other systems ask ---------------------------------------------

## Indices of living enemies within radius `r` of `center`.
func query(center: Vector2, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := r * r
	var c0 := Vector2i(floori((center.x - r) / CELL), floori((center.y - r) / CELL))
	var c1 := Vector2i(floori((center.x + r) / CELL), floori((center.y + r) / CELL))
	for gx in range(c0.x, c1.x + 1):
		for gy in range(c0.y, c1.y + 1):
			var cell = _grid.get(Vector2i(gx, gy))
			if cell == null:
				continue
			for j in cell:
				if j < count and hp[j] > 0.0 and center.distance_squared_to(pos[j]) <= r2:
					out.append(j)
	return out


## Index of the nearest living enemy within `max_r`, or -1.
func nearest(center: Vector2, max_r: float) -> int:
	var best := -1
	var best_d := max_r * max_r
	for i in count:
		if hp[i] <= 0.0:
			continue
		var d := center.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## Index of the living enemy nearest to `from`, counting only enemies within
## `radius` of `center` (used for followers on a leash), or -1.
func nearest_in_circle(from: Vector2, center: Vector2, radius: float) -> int:
	var best := -1
	var best_d := INF
	var r2 := radius * radius
	for i in count:
		if hp[i] <= 0.0 or center.distance_squared_to(pos[i]) > r2:
			continue
		var d := from.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## The most important target inside the leash: the nearest boss, elite or
## goblin if there is one, otherwise the nearest enemy.
func best_target_in_circle(from: Vector2, center: Vector2, radius: float) -> int:
	var best := -1
	var best_d := INF
	var r2 := radius * radius
	for i in count:
		if hp[i] <= 0.0 or kind[i] < ELITE or center.distance_squared_to(pos[i]) > r2:
			continue
		var d := from.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return best
	return nearest_in_circle(from, center, radius)


## Like nearest_in_circle, but the enemy must also be inside a second circle
## (used when followers want to fight inside Kheiron's grove).
func nearest_in_two_circles(from: Vector2, c1: Vector2, r1: float, c2: Vector2, r2: float) -> int:
	var best := -1
	var best_d := INF
	var r1s := r1 * r1
	var r2s := r2 * r2
	for i in count:
		if hp[i] <= 0.0 or c1.distance_squared_to(pos[i]) > r1s or c2.distance_squared_to(pos[i]) > r2s:
			continue
		var d := from.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func stun(i: int, seconds: float) -> void:
	if i >= 0 and i < count:
		var s: float = seconds * STUN_TAKEN[kind[i]]
		if s > 0.0:
			stun_t[i] = maxf(stun_t[i], s)


## Makes every enemy within `r` of `center` go after one hero for a while.
func taunt_in_radius(center: Vector2, r: float, hero_index: int, seconds: float) -> void:
	for i in query(center, r):
		taunt_hero[i] = hero_index
		taunt_t[i] = seconds


## Slows enemies by `amount` (0.5 = half speed) for `seconds`.
func slow(i: int, amount: float, seconds: float) -> void:
	if i < 0 or i >= count:
		return
	if slow_t[i] <= 0.0 or amount >= slow_amt[i]:
		slow_amt[i] = amount
	slow_t[i] = maxf(slow_t[i], seconds)


func slow_in_radius(center: Vector2, r: float, amount: float, seconds: float) -> void:
	for i in query(center, r):
		slow(i, amount, seconds)


## Drags enemies within `r` toward `center`.
func pull(center: Vector2, r: float, strength: float) -> void:
	for i in query(center, r):
		var to: Vector2 = center - pos[i]
		if to.length() > 0.8:
			knock[i] += to.normalized() * strength


## Cenhelm's horn: slows everything in range, hurts them once a second,
## and nudges them away from `center`.
func horn(center: Vector2, r: float, seconds: float, tick_damage: float, push: float, slow_amount := 0.5) -> void:
	for i in query(center, r):
		slow(i, slow_amount, seconds)
		dot_t[i] = seconds
		dot_dmg[i] = tick_damage
		dot_acc[i] = 0.0
		var rel: Vector2 = pos[i] - center
		if rel.length() > 0.05:
			knock[i] += rel.normalized() * push


func damage(i: int, amount: float, dir: Vector2, force: float) -> void:
	if i < 0 or i >= count or hp[i] <= 0.0:
		return
	var k := kind[i]
	hp[i] -= amount
	flash[i] = 0.1
	knock[i] += dir * force * KNOCK_TAKEN[k]
	# Damage numbers only for big hits, and on elites and bosses.
	if amount >= BIG_HIT or (k >= ELITE and k != GOBLIN and amount >= 5.0):
		var s: float = SCALE[k]
		Game.fx.damage_number(Vector3(pos[i].x, 1.4 * s + 0.4, pos[i].y), amount)
	if hp[i] <= 0.0:
		Game.kills += 1
		var p: Vector2 = pos[i]
		if XP_DROP[k] > 0:
			Game.xp.drop(p, XP_DROP[k])
		Game.fx.death_puff(Vector3(p.x, 0.5, p.y), COLORS[k])
		match k:
			ELITE:
				Game.main.on_elite_killed(p)
			MINIBOSS:
				Game.main.on_miniboss_killed(p)
			FINAL_BOSS:
				Game.main.on_final_boss_killed(p)
			GOBLIN:
				Game.main.on_goblin_caught(p)


# --- Each frame --------------------------------------------------------------

func _remove_dead() -> void:
	var i := count - 1
	while i >= 0:
		if hp[i] <= 0.0:
			var last := count - 1
			pos[i] = pos[last]
			knock[i] = knock[last]
			hp[i] = hp[last]
			flash[i] = flash[last]
			kind[i] = kind[last]
			yaw[i] = yaw[last]
			sep[i] = sep[last]
			stun_t[i] = stun_t[last]
			taunt_t[i] = taunt_t[last]
			taunt_hero[i] = taunt_hero[last]
			atk_cd[i] = atk_cd[last]
			slow_t[i] = slow_t[last]
			slow_amt[i] = slow_amt[last]
			age[i] = age[last]
			dot_t[i] = dot_t[last]
			dot_dmg[i] = dot_dmg[last]
			dot_acc[i] = dot_acc[last]
			count -= 1
		i -= 1


func _spawn(delta: float) -> void:
	var t: float = Game.time_alive
	var rate := 1.6 + t * 0.045 + pow(t / 60.0, 2.0) * 0.12 # enemies per second
	if swarm_active:
		rate *= 2.0
	_spawn_acc += rate * delta
	# Keep a little room so bosses and elites can always appear.
	while _spawn_acc >= 1.0 and count < MAX_ENEMIES - 20:
		_spawn_acc -= 1.0
		var k := SHAMBLER
		if swarm_active and randf() < 0.7:
			k = SWARMLING
		elif t > 75.0 and randf() < 0.3:
			k = RUNNER
		spawn_near_leader(k)
	if count >= MAX_ENEMIES - 20:
		_spawn_acc = 0.0


## Spawns an enemy in a ring just off screen around the leader. Returns its index.
func spawn_near_leader(k: int, dist_min := 19.0, dist_max := 24.0) -> int:
	var l = Game.party.leader()
	if l == null:
		return -1
	var ang := randf() * TAU
	var p := Vector2(l.position.x, l.position.z) + Vector2(cos(ang), sin(ang)) * randf_range(dist_min, dist_max)
	return spawn(k, p)


func spawn(k: int, p: Vector2) -> int:
	if count >= MAX_ENEMIES:
		return -1
	var a: float = Game.main.ARENA_HALF
	p.x = clampf(p.x, -a, a)
	p.y = clampf(p.y, -a, a)
	var i := count
	pos[i] = p
	knock[i] = Vector2.ZERO
	hp[i] = HP[k] * (1.0 + Game.time_alive / 140.0)
	flash[i] = 0.0
	kind[i] = k
	yaw[i] = 0.0
	sep[i] = Vector2.ZERO
	stun_t[i] = 0.0
	taunt_t[i] = 0.0
	taunt_hero[i] = 0
	atk_cd[i] = HIT_WINDUP
	slow_t[i] = 0.0
	slow_amt[i] = 0.0
	dot_t[i] = 0.0
	dot_dmg[i] = 0.0
	dot_acc[i] = 0.0
	age[i] = 0.0
	count += 1
	return i


## Index of the first living enemy of a type, or -1.
func find_kind(k: int) -> int:
	for i in count:
		if kind[i] == k and hp[i] > 0.0:
			return i
	return -1


func _rebuild_grid() -> void:
	_grid.clear()
	for i in count:
		var c := Vector2i(floori(pos[i].x / CELL), floori(pos[i].y / CELL))
		var cell = _grid.get(c)
		if cell == null:
			_grid[c] = [i]
		else:
			cell.append(i)


func _move(delta: float) -> void:
	var heroes: Array = Game.party.heroes
	var alive: Array[bool] = []
	var hero_xz: Array[Vector2] = []
	var any_alive := false
	for h in heroes:
		alive.append(not h.downed)
		hero_xz.append(Vector2(h.position.x, h.position.z))
		any_alive = any_alive or not h.downed
	if not any_alive:
		return
	var hits: Array = [] # [hero index, enemy index] for every blow this frame
	var decay := exp(-7.0 * delta)

	for i in count:
		var p: Vector2 = pos[i]
		# Head for the hero who taunted us, otherwise the nearest living hero.
		var best := -1
		var best_d := INF
		if taunt_t[i] > 0.0:
			taunt_t[i] -= delta
			var th := int(taunt_hero[i])
			if th < heroes.size() and alive[th]:
				best = th
				best_d = p.distance_squared_to(hero_xz[th])
		if best < 0:
			for h in hero_xz.size():
				if not alive[h]:
					continue
				var dd := p.distance_squared_to(hero_xz[h])
				if dd < best_d:
					best_d = dd
					best = h
		var dist := sqrt(best_d)
		var v := Vector2.ZERO
		var stunned := stun_t[i] > 0.0
		var k := kind[i]
		age[i] += delta
		if stunned:
			stun_t[i] -= delta
		elif k == GOBLIN:
			# The goblin runs away from the party, and escapes after a while.
			v = (p - hero_xz[best]) / maxf(dist, 0.01) * SPEED[k]
			if age[i] > GOBLIN_LIFE:
				hp[i] = -1.0 # gone, no reward
		elif dist > 0.6 + 0.4 * (SCALE[k] - 1.0):
			v = (hero_xz[best] - p) / dist * SPEED[k]
			if slow_t[i] > 0.0:
				v *= 1.0 - slow_amt[i]
		if slow_t[i] > 0.0:
			slow_t[i] -= delta
		if dot_t[i] > 0.0:
			dot_t[i] -= delta
			dot_acc[i] += delta
			if dot_acc[i] >= 1.0:
				dot_acc[i] -= 1.0
				damage(i, dot_dmg[i], Vector2.ZERO, 0.0)
		# Push away from neighbours so the horde spreads instead of stacking.
		# Half the horde recalculates each frame; the rest reuse last frame's push.
		if (i + _frame) % 2 == 0:
			var push := Vector2.ZERO
			var cx := floori(p.x / CELL)
			var cy := floori(p.y / CELL)
			for gx in range(cx - 1, cx + 2):
				for gy in range(cy - 1, cy + 2):
					var cell = _grid.get(Vector2i(gx, gy))
					if cell == null:
						continue
					for j in cell:
						if j == i:
							continue
						var d: Vector2 = p - pos[j]
						var l2 := d.length_squared()
						if l2 < 0.5 and l2 > 0.0001:
							var l := sqrt(l2)
							push += d / l * (0.71 - l)
			sep[i] = push
		knock[i] = knock[i] * decay
		var np := p + (v + sep[i] * 6.0 + knock[i]) * delta
		# Ruins block the way: slide round them instead of sticking behind.
		var body_r: float = 0.35 * SCALE[k]
		var out: Vector2 = Game.push_out(np, body_r)
		if out != np:
			var n: Vector2 = (out - np).normalized()
			var tang := Vector2(-n.y, n.x)
			if tang.dot(v) < 0.0:
				tang = -tang
			np = Game.push_out(out + tang * v.length() * delta, body_r)
		var a: float = Game.main.ARENA_HALF
		np.x = clampf(np.x, -a, a)
		np.y = clampf(np.y, -a, a)
		pos[i] = np
		if v.length_squared() > 0.01:
			yaw[i] = atan2(v.x, v.y)
		flash[i] = maxf(0.0, flash[i] - delta)
		# Blows: an enemy in reach strikes once a second, after a short wind-up.
		var reach: float = 0.9 + 0.45 * (SCALE[k] - 1.0)
		if dist < reach and not stunned and hp[i] > 0.0 and HIT_MULT[k] > 0.0:
			atk_cd[i] -= delta
			if atk_cd[i] <= 0.0:
				atk_cd[i] = HIT_INTERVAL
				hits.append([best, i, HIT_MULT[k]])
		else:
			atk_cd[i] = HIT_WINDUP

	# Only so many enemies fit around a hero, which naturally limits how
	# hard a crowd can hit.
	var dmg := HIT_DAMAGE * (1.0 + Game.time_alive / 400.0)
	for h in hits:
		var hero = heroes[h[0]]
		if not hero.downed:
			Game.party.apply_hit(hero, dmg * h[2], h[1])


func _render() -> void:
	# Fill one big array and hand it over in a single call. Much faster than
	# setting each enemy separately. Layout per enemy: the 3x4 transform
	# row by row (basis.x.x, basis.y.x, basis.z.x, origin.x, ...), then RGBA.
	for i in count:
		var k := kind[i]
		var s: float = SCALE[k]
		var c := cos(yaw[i]) * s
		var sn := sin(yaw[i]) * s
		var y := 0.65 * s + absf(sin(_time * 9.0 + float(i))) * 0.08
		var col: Color = COLORS[k]
		if flash[i] > 0.0:
			col = Color.WHITE
		elif stun_t[i] > 0.0:
			col = STUN_TINT
		elif slow_t[i] > 0.0:
			col = col.lerp(SLOW_TINT, 0.6)
		var o := i * 16
		_buffer[o] = c
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = sn
		_buffer[o + 3] = pos[i].x
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = s
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = y
		_buffer[o + 8] = -sn
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = c
		_buffer[o + 11] = pos[i].y
		_buffer[o + 12] = col.r
		_buffer[o + 13] = col.g
		_buffer[o + 14] = col.b
		_buffer[o + 15] = 1.0
	_mm.buffer = _buffer
	_mm.visible_instance_count = count
