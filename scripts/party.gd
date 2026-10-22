extends Node3D
## The party of three: moving and aiming the leader, the followers' AI
## (hunting enemies, or healing), the leash, swapping who leads, shared
## damage and reviving fallen heroes.

const HeroScript := preload("res://scripts/hero.gd")

const SWAP_COOLDOWN := 1.0
const REVIVE_RANGE := 1.8
## How far followers may roam from the leader, in metres
## (about 10 hero widths, or two-thirds of the way to the screen edge).
const LEASH := 8.0
## A healer goes to an ally once their health drops below this fraction.
const HEAL_SEEK_BELOW := 0.9
## Below this health fraction a follower stops hunting and falls back.
const RETREAT_BELOW := 0.35

var heroes: Array = []
var leader_index := 0
var swap_timer := 0.0

# Numbers that upgrades can change.
var speed := 6.2
var speed_mult := 1.0
var haste := 1.0 # multiplies every hero's attack speed
var lead_bonus := 1.2 # the leader deals 20% more damage
var revive_time := 3.0

var aim_point := Vector3.ZERO # where the leader is aiming, on the ground

# Groves: healing circles on the ground (Kheiron's E, and some cards).
# Each is {pos, radius, time, heal (fraction of max health per second),
# slow (enemy slow inside, 0 = none), disc, mat}.
var groves: Array = []
## Bond cards in play this run (id -> true). See upgrades.gd.
var bonds := {}

var _form_yaw := 0.0 # direction of the resting formation; turns smoothly
var _wiped := false
var _using_stick := false # true after the right stick was last used to aim
var _reticle: MeshInstance3D
var _leash_ring: MeshInstance3D


func _ready() -> void:
	for kind in ["solenne", "cenhelm", "kheiron"]:
		var h = HeroScript.new()
		h.setup(kind)
		add_child(h)
		heroes.append(h)
	heroes[1].position = Vector3(-1.0, 0.0, -1.4)
	heroes[2].position = Vector3(1.0, 0.0, -1.4)
	_set_leader(0, false)
	swap_timer = 0.0
	_reticle = _ground_ring(0.3, 0.42, Color(1.0, 0.9, 0.5, 0.9))
	_leash_ring = _ground_ring(LEASH - 0.08, LEASH, Color(1.0, 1.0, 1.0, 0.12))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_using_stick = false


func _process(delta: float) -> void:
	if _wiped:
		return
	swap_timer = maxf(0.0, swap_timer - delta)
	if Input.is_action_just_pressed("swap"):
		swap()
	if Input.is_action_just_pressed("skill_1"):
		leader().cast("q")
	if Input.is_action_just_pressed("skill_2"):
		leader().cast("e")
	if Input.is_action_just_pressed("ultimate"):
		leader().cast("r")
	_tick_grove(delta)
	_move_leader(delta)
	_aim_leader()
	_move_followers(delta)
	_separate_heroes()
	_tick_revive(delta)
	var l = leader()
	_leash_ring.position = Vector3(l.position.x, 0.04, l.position.z)


# --- Lookups -----------------------------------------------------------------

func leader():
	if heroes.is_empty():
		return null
	return heroes[leader_index]


func hero(hero_name: String):
	for h in heroes:
		if h.hero_name == hero_name:
			return h
	return null


func alive_heroes() -> Array:
	var out: Array = []
	for h in heroes:
		if not h.downed:
			out.append(h)
	return out


## The living ally with the lowest health (as a fraction), not counting
## `exclude`, and only if they're below `below`. Returns null if nobody is.
func lowest_health_ally(exclude, below := 1.0):
	var best = null
	var best_frac := below
	for h in heroes:
		if h == exclude or h.downed:
			continue
		var frac: float = h.hp / h.max_hp
		if frac < best_frac:
			best_frac = frac
			best = h
	return best


# --- Leader: moving and aiming -----------------------------------------------

func _move_leader(delta: float) -> void:
	var l = leader()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	if Game.main.autopilot:
		dir = Game.main.autopilot_dir
	if dir.length() > 1.0:
		dir = dir.normalized()
	l.moving = dir.length() > 0.1 and not l.dashing
	l.move_dir = dir
	if not l.moving:
		return
	# Crisp: full speed instantly, no momentum or sliding.
	l.position += dir * speed * speed_mult * delta
	var a: float = Game.main.ARENA_HALF
	l.position.x = clampf(l.position.x, -a, a)
	l.position.z = clampf(l.position.z, -a, a)
	_form_yaw = lerp_angle(_form_yaw, atan2(dir.x, dir.z), 1.0 - exp(-7.0 * delta))


## The leader always faces where the player aims: the mouse, or the right
## stick on a gamepad. Their basic attack fires that way too.
func _aim_leader() -> void:
	var l = leader()
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.3:
		_using_stick = true
	var target = null
	if Game.main.autopilot:
		# The test bot "aims" at the nearest enemy.
		var e: int = Game.enemies.nearest(Vector2(l.position.x, l.position.z), 30.0)
		if e >= 0:
			target = Vector3(Game.enemies.pos[e].x, 0.0, Game.enemies.pos[e].y)
	elif _using_stick:
		if stick.length() > 0.3:
			target = l.position + Vector3(stick.x, 0.0, stick.y).normalized() * 4.0
		else:
			target = aim_point if aim_point != Vector3.ZERO else null
	else:
		target = _mouse_on_ground()
	if target == null:
		# No aim yet: face the way we're walking.
		target = l.position + (l.move_dir if l.moving else Vector3(sin(l.facing), 0.0, cos(l.facing)))
	aim_point = target
	var to: Vector3 = aim_point - l.position
	to.y = 0.0
	if to.length() > 0.05:
		l.aim_dir = Vector2(to.x, to.z).normalized()
		l.facing = atan2(to.x, to.z)
	_reticle.visible = not Game.main.autopilot and not l.downed
	_reticle.position = Vector3(aim_point.x, 0.05, aim_point.z)


func _mouse_on_ground():
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, dir)


# --- Followers ---------------------------------------------------------------
# Fighters hunt the nearest enemy inside the leash. Healers go to the ally
# with the lowest health percentage, and otherwise stay back (they attack
# from range). Badly hurt followers fall back behind the leader. With
# nothing to do, followers rest in formation. Anyone past the leash runs
# back first.

func _move_followers(delta: float) -> void:
	var l = leader()
	var lxz := Vector2(l.position.x, l.position.z)
	var forward := Vector3(sin(_form_yaw), 0.0, cos(_form_yaw))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var slots := [
		l.position - forward * 1.4 + right * 1.0,
		l.position - forward * 1.4 - right * 1.0,
	]
	var slot_i := 0
	for h in heroes:
		if h == l:
			continue
		var slot: Vector3 = slots[slot_i]
		slot_i += 1
		if h.downed or h.dashing:
			h.moving = false
			continue
		var hxz := Vector2(h.position.x, h.position.z)
		var from_leader := hxz.distance_to(lxz)
		if from_leader > LEASH:
			h.returning = true
		elif from_leader < LEASH * 0.6:
			h.returning = false

		var goal := slot
		var stop := 0.06
		var spd: float = speed * speed_mult * 1.1
		var low: bool = h.hp / h.max_hp < RETREAT_BELOW
		if h.returning:
			spd *= 1.4
		elif not groves.is_empty():
			# A grove is down: fight enemies inside it, otherwise stand in it.
			var g: Dictionary = _nearest_grove(h.position)
			var gxz := Vector2(g["pos"].x, g["pos"].z)
			var gr: float = g["radius"]
			var e := -1
			if not low and not h.is_healer():
				e = Game.enemies.nearest_in_two_circles(hxz, lxz, LEASH, gxz, gr)
			if e >= 0:
				goal = Vector3(Game.enemies.pos[e].x, 0.0, Game.enemies.pos[e].y)
				stop = h.engage_range()
			elif hxz.distance_to(gxz) > gr * 0.85:
				goal = _grove_spot_near_leader(l, g)
				stop = 0.5
			else:
				goal = h.position
		elif h.is_healer():
			var hurt = lowest_health_ally(h, HEAL_SEEK_BELOW)
			if hurt != null:
				goal = hurt.position
				stop = 2.0
		elif low:
			pass # fall back to the formation slot behind the leader
		else:
			var e := _hunt(hxz, lxz)
			if e >= 0:
				goal = Vector3(Game.enemies.pos[e].x, 0.0, Game.enemies.pos[e].y)
				stop = h.engage_range()

		var to: Vector3 = goal - h.position
		to.y = 0.0
		var d := to.length()
		if d <= stop:
			h.moving = false
			h.move_dir = Vector3.ZERO
			continue
		# Resting in formation: catch up fast and settle crisply.
		if goal == slot and not h.returning:
			spd = maxf(spd, d * 9.0)
		var step := minf(d - stop, spd * delta)
		h.position += to / d * step
		h.moving = step > speed * 0.25 * delta
		h.move_dir = to / d
		if h.face_lock <= 0.0 and h.moving:
			h.facing = atan2(to.x, to.z)


## A spot inside the grove that is also inside the leash.
func _grove_spot_near_leader(l, g: Dictionary) -> Vector3:
	var gp: Vector3 = g["pos"]
	var to: Vector3 = gp - l.position
	to.y = 0.0
	if to.length() <= LEASH * 0.7:
		return gp
	return l.position + to.normalized() * LEASH * 0.7


func _nearest_grove(p: Vector3) -> Dictionary:
	var best: Dictionary = groves[0]
	var best_d := INF
	for g in groves:
		var d: float = p.distance_to(g["pos"])
		if d < best_d:
			best_d = d
			best = g
	return best


## Index of the enemy nearest to the follower, among enemies inside the leash.
func _hunt(from: Vector2, leash_center: Vector2) -> int:
	return Game.enemies.best_target_in_circle(from, leash_center, LEASH)


## Stops heroes standing inside each other.
func _separate_heroes() -> void:
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			var a = heroes[i]
			var b = heroes[j]
			if a.downed or b.downed:
				continue
			var d: Vector3 = b.position - a.position
			d.y = 0.0
			var l := d.length()
			if l < 0.9 and l > 0.001:
				var push := d / l * (0.9 - l) * 0.5
				if not a.is_leader:
					a.position -= push
				if not b.is_leader:
					b.position += push


# --- Swapping ----------------------------------------------------------------

func swap() -> void:
	if swap_timer > 0.0 or _wiped:
		return
	var next := _next_alive(leader_index)
	if next < 0 or next == leader_index:
		return
	_set_leader(next, true)


func _next_alive(from: int) -> int:
	for k in range(1, heroes.size() + 1):
		var j := (from + k) % heroes.size()
		if not heroes[j].downed:
			return j
	return -1


func _set_leader(index: int, entrance: bool) -> void:
	for h in heroes:
		h.is_leader = false
		h.returning = false
	leader_index = index
	var l = heroes[index]
	l.is_leader = true
	swap_timer = SWAP_COOLDOWN
	if not entrance:
		return
	# A small entrance burst. The full "ultimate on swap-in" comes in milestone 2.
	var me := Vector2(l.position.x, l.position.z)
	for e in Game.enemies.query(me, 3.5):
		var rel: Vector2 = Game.enemies.pos[e] - me
		var push := rel.normalized() if rel.length() > 0.01 else Vector2.UP
		Game.enemies.damage(e, 6.0, push, 14.0)
	Game.fx.ring(l.position, 3.5, Color(1.0, 0.85, 0.4), 0.25)
	Game.hitstop(0.07)
	Game.add_shake(0.25)


# --- Damage and reviving -----------------------------------------------------

## Called by the enemies for each blow. Cenhelm takes part of any blow
## aimed at someone else.
func apply_hit(target, amount: float, enemy_index: int) -> void:
	var c = hero("Cenhelm")
	if c != null and not c.downed and target != c:
		c.take_damage(amount * c.intercept_share)
		target.take_hit(amount * (1.0 - c.intercept_share), enemy_index)
	else:
		target.take_hit(amount, enemy_index)


func on_hero_downed(h) -> void:
	if alive_heroes().is_empty():
		_wiped = true
		Game.main.on_party_wiped()
		return
	if h.is_leader:
		_set_leader(_next_alive(leader_index), false)
		swap_timer = 0.0


func _tick_revive(delta: float) -> void:
	var l = leader()
	for h in heroes:
		if not h.downed:
			continue
		if l.position.distance_to(h.position) < REVIVE_RANGE:
			h.revive_progress += delta
			if h.revive_progress >= revive_time:
				h.revive()
				Game.fx.ring(h.position, 1.6, Color(0.6, 1.0, 0.6), 0.35)
		else:
			h.revive_progress = maxf(0.0, h.revive_progress - delta * 0.5)


# --- Kheiron's grove ---------------------------------------------------------

func place_grove(at: Vector3, radius: float, seconds: float, heal_per_second: float, slow := 0.0) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48
	disc.rings = 1
	var mat := Game.effect_material(Color(0.4, 0.9, 0.4, 0.22))
	var node := MeshInstance3D.new()
	node.mesh = disc
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pos := Vector3(at.x, 0.0, at.z)
	node.position = Vector3(pos.x, 0.03 + groves.size() * 0.002, pos.z)
	node.scale = Vector3(radius, 1.0, radius)
	add_child(node)
	groves.append({"pos": pos, "radius": radius, "time": seconds, "heal": heal_per_second, "slow": slow, "disc": node, "mat": mat})
	Game.fx.ring(pos, radius, Color(0.55, 0.95, 0.55), 0.4)


func in_grove(p: Vector3) -> bool:
	for g in groves:
		if Vector2(p.x, p.z).distance_to(Vector2(g["pos"].x, g["pos"].z)) <= g["radius"]:
			return true
	return false


func _tick_grove(delta: float) -> void:
	var i := groves.size() - 1
	while i >= 0:
		var g: Dictionary = groves[i]
		g["time"] -= delta
		var gp: Vector3 = g["pos"]
		var gxz := Vector2(gp.x, gp.z)
		for h in heroes:
			if Vector2(h.position.x, h.position.z).distance_to(gxz) <= g["radius"]:
				h.heal(h.max_hp * g["heal"] * delta)
		if g["slow"] > 0.0:
			Game.enemies.slow_in_radius(gxz, g["radius"], g["slow"], 0.25)
		# Fade out over the last half second.
		g["mat"].albedo_color.a = 0.22 * clampf(g["time"] / 0.5, 0.0, 1.0)
		if g["time"] <= 0.0:
			g["disc"].queue_free()
			groves.remove_at(i)
		i -= 1


# --- Helpers -----------------------------------------------------------------

func _ground_ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var ring := TorusMesh.new()
	ring.inner_radius = inner
	ring.outer_radius = outer
	ring.rings = 48
	ring.ring_segments = 3
	var m := MeshInstance3D.new()
	m.mesh = ring
	m.material_override = Game.effect_material(color)
	m.scale = Vector3(1.0, 0.05, 1.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m
