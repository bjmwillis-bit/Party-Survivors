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
## Ranged kiting (see _kite).
const KITE_STEP := 2.5 # how far apart the spots it considers are
const KITE_CROWD_RADIUS := 3.5 # enemies within this of a spot count against it
const KITE_KEEP_RANGE := 0.75 # stay within this fraction of shooting range
const KITE_RETHINK := 0.3 # seconds between choosing a new spot
## A healer stays within this of the ally who needs them.
const HEALER_STAY_NEAR := 5.0
## Melee followers (see _melee).
const MELEE_RETHINK := 0.3 # seconds between choosing a target and a side
const MELEE_SEEK := 6.0 # how far round them they look for a target
const MELEE_SAMPLES := 16 # at most this many candidate targets are judged
const MELEE_CROWD := 2.5 # enemies within this of a spot count against it
const BREAK_TIME := 1.2 # seconds spent breaking away from a crowd

var heroes: Array = []
var leader_index := 0
var swap_timer := 0.0

# Numbers that upgrades can change.
var speed := 6.2
var speed_mult := 1.0
var haste := 1.0 # multiplies every hero's attack speed
var might := 1.0 # multiplies every hero's damage
var reach := 1.0 # multiplies every hero's area
var focus := 1.0 # multiplies every hero's cooldowns
var echo := 0 # extra instances for every hero's basic attack
var lead_bonus := 1.2 # the leader deals 20% more damage
var revive_time := 3.0

var aim_point := Vector3.ZERO # where the leader is aiming, on the ground

# Groves: healing circles on the ground (Kheiron's E, and some cards).
# Each is {pos, radius, time, heal (fraction of max health per second),
# slow (enemy slow inside, 0 = none), disc, mat}.
var groves: Array = []
## Bond cards in play this run (id -> true). See upgrades.gd.
var bonds := {}
## Bram's anvils: {pos, radius, time, bonus, node}.
var anvils: Array = []
## The melee follower AI from 23 Oct. False restores the old "walk up and
## stand there" behaviour (tests compare the two).
var melee_ai := true

var _form_yaw := 0.0 # direction of the resting formation; turns smoothly
var _wiped := false
var _using_stick := false # true after the right stick was last used to aim
var _reticle: MeshInstance3D
var _leash_ring: MeshInstance3D


func _ready() -> void:
	for kind in Game.party_kinds():
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
	if not Game.main.is_night():
		# At the fire, setting out or walking home: main.gd directs the party.
		_move_directed(delta)
		_separate_heroes()
		_reticle.visible = false
		_leash_ring.visible = false
		return
	_leash_ring.visible = true
	swap_timer = maxf(0.0, swap_timer - delta)
	if Input.is_action_just_pressed("swap"):
		swap()
	if Input.is_action_just_pressed("skill_1"):
		leader().cast("q")
	if Input.is_action_just_pressed("ultimate"):
		leader().cast("e")
	_tick_grove(delta)
	_tick_anvils(delta)
	_move_leader(delta)
	_aim_leader()
	_move_followers(delta)
	_separate_heroes()
	_tick_revive(delta)
	var l = leader()
	_leash_ring.position = Vector3(l.position.x, 0.04, l.position.z)


# --- Directed movement (camp, setting out, walking home) ----------------------

## hero -> {"to": Vector3, "face": float (radians), "speed": float}
var directed := {}


func direct(h, to: Vector3, face: float, run_speed := 5.5) -> void:
	directed[h] = {"to": to, "face": face, "speed": run_speed}


func arrived(h) -> bool:
	if not directed.has(h):
		return true
	var to: Vector3 = directed[h]["to"]
	return Vector2(h.position.x - to.x, h.position.z - to.z).length() < 0.12


func _move_directed(delta: float) -> void:
	for h in heroes:
		if not directed.has(h) or h.downed or h.sit > 0.05:
			h.moving = false # (still getting up off the log)
			continue
		var d: Dictionary = directed[h]
		var to: Vector3 = d["to"] - h.position
		to.y = 0.0
		var dist := to.length()
		# Home through the Keep's gates, not through its walls.
		if Game.keep != null and dist >= 0.12:
			var hxz := Vector2(h.position.x, h.position.z)
			var dest := Vector2(d["to"].x, d["to"].z)
			var nxt: Vector2 = Game.keep.next_point(hxz, dest)
			if nxt != dest:
				to = Vector3(nxt.x - hxz.x, 0.0, nxt.y - hxz.y)
				dist = maxf(0.13, to.length())
		if dist < 0.12:
			h.moving = false
			h.move_dir = Vector3.ZERO
			h.facing = d["face"]
			continue
		var step := minf(dist, float(d["speed"]) * delta)
		h.position += to / dist * step
		# Round the fire and the ruins rather than through them.
		var hp2 := Vector2(h.position.x, h.position.z)
		var out: Vector2 = Game.push_out(hp2, 0.4)
		if out != hp2:
			var n: Vector2 = (out - hp2).normalized()
			var tang := Vector2(-n.y, n.x)
			if tang.dot(Vector2(to.x, to.z)) < 0.0:
				tang = -tang
			out = Game.push_out(out + tang * step, 0.4)
			h.position.x = out.x
			h.position.z = out.y
		h.moving = true
		h.move_dir = to / dist
		h.facing = atan2(to.x, to.z)


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
	l.position += dir * speed * speed_mult * l.speed_mult * delta
	var lp: Vector2 = Game.clamp_arena(Vector2(l.position.x, l.position.z))
	l.position.x = lp.x
	l.position.z = lp.y
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
	# The aim is shown by the cursor widget (cursor_hud.gd) now.
	_reticle.visible = false


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
		var spd: float = speed * speed_mult * h.speed_mult * 1.1
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
			elif h.is_ranged() and not low and _hunt(hxz, lxz) >= 0:
				# Ranged heroes keep kiting, but inside the grove.
				var k = _kite(h, _hunt(hxz, lxz), lxz, null, delta, gxz, gr * 0.8)
				goal = k[0]
				stop = k[1]
			else:
				goal = h.position
		elif low:
			# Hurt: go to the healer if there is one, otherwise fall back to the
			# formation slot behind the leader.
			var medic = _healer_for(h)
			if medic != null:
				goal = medic.position
				stop = 1.8
		elif h.is_ranged():
			var hurt = lowest_health_ally(h, HEAL_SEEK_BELOW) if h.is_healer() else null
			if hurt != null and h.position.distance_to(hurt.position) > HEALER_STAY_NEAR:
				goal = hurt.position # a healer keeps close to whoever is hurt
				stop = HEALER_STAY_NEAR - 1.0
			else:
				var e := _hunt(hxz, lxz)
				if e >= 0:
					var k = _kite(h, e, lxz, hurt, delta)
					goal = k[0]
					stop = k[1]
		elif melee_ai:
			var m := _melee(h, lxz, delta)
			if not m.is_empty():
				goal = m[0]
				stop = m[1]
		else:
			var e := _hunt(hxz, lxz)
			if e >= 0:
				goal = Vector3(Game.enemies.pos[e].x, 0.0, Game.enemies.pos[e].y)
				stop = h.engage_range()

		# Round the Keep's walls and through its gates.
		if Game.keep != null:
			var gxz: Vector2 = Game.push_out(Vector2(goal.x, goal.z), 0.45)
			var nxt: Vector2 = Game.keep.next_point(hxz, gxz)
			if nxt != gxz:
				goal = Vector3(nxt.x, 0.0, nxt.y)
				stop = 0.3
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
		# Walk round ruins rather than into them.
		var hp2 := Vector2(h.position.x, h.position.z)
		var out: Vector2 = Game.push_out(hp2, 0.4)
		if out != hp2:
			var n: Vector2 = (out - hp2).normalized()
			var tang := Vector2(-n.y, n.x)
			if tang.dot(Vector2(to.x, to.z)) < 0.0:
				tang = -tang
			out = Game.push_out(out + tang * step, 0.4)
			h.position.x = out.x
			h.position.z = out.y
		h.moving = step > speed * 0.25 * delta
		h.move_dir = to / d
		if h.face_lock <= 0.0 and h.moving:
			h.facing = atan2(to.x, to.z)


## Melee followers keep moving while they fight. They pick a target on the
## edge of the crowd (few enemies round it, not far away), then stand on its
## quietest side, just inside their reach, re-judging a few times a second.
## If they're losing health faster than their nerve allows, they break away
## toward thinner ground near the group for a moment (firing their skill if
## it helps), then go back to fighting from the edge. Everything is judged
## relative to what's around, so it works the same with 20 enemies or 2,000.
## Returns [goal, stop distance], or [] when there's nothing to fight.
func _melee(h, lxz: Vector2, delta: float) -> Array:
	var hxz := Vector2(h.position.x, h.position.z)
	if h.breaking <= 0.0 and h.hurt_rate > h.nerve():
		h.breaking = BREAK_TIME
		var spot := _escape_spot(hxz, lxz)
		h.kite_spot = Vector3(spot.x, 0.0, spot.y)
		h.melee_target = -1
		if spot.distance_to(hxz) > 0.1:
			h.escape_skill((spot - hxz).normalized())
	if h.breaking > 0.0:
		return [h.kite_spot, 0.15]

	var E = Game.enemies
	var t: int = h.melee_target
	var valid: bool = t >= 0 and t < E.count and E.hp[t] > 0.0 and E.pos[t].distance_to(lxz) <= LEASH + 1.0
	h.kite_timer -= delta
	if h.kite_timer <= 0.0 or not valid:
		h.kite_timer = MELEE_RETHINK
		t = _edge_target(hxz, lxz, t if valid else -1)
		h.melee_target = t
		if t >= 0:
			h.melee_side = _quiet_side(h, hxz, E.pos[t], lxz)
	if t < 0:
		return []
	var txz: Vector2 = E.pos[t]
	# Big enemies are wider, so stand a little further out from their middle.
	var body: float = 0.35 * (E.SCALE[E.kind[t]] - 1.0)
	var at: Vector2 = txz + h.melee_side * (_stand_off(h) + body)
	return [Vector3(at.x, 0.0, at.y), 0.15]


## How far from its target a melee hero stands: well inside its reach, and
## outside Cael's dead zone.
func _stand_off(h) -> float:
	return maxf(h.engage_range() * 0.75, h.min_reach() + 0.8)


## A target on the edge of the crowd: near the hero, with few others round it.
## Elites, bosses and goblins in the leash still come first.
func _edge_target(hxz: Vector2, lxz: Vector2, current: int) -> int:
	var E = Game.enemies
	var big: int = E.best_target_in_circle(hxz, lxz, LEASH)
	if big >= 0 and E.kind[big] >= E.ELITE:
		return big
	var near: Array = E.query(hxz, MELEE_SEEK)
	if near.is_empty():
		return _hunt(hxz, lxz)
	var stride := maxi(1, near.size() / MELEE_SAMPLES)
	var best := -1
	var best_score := INF
	for n in range(0, near.size(), stride):
		var i: int = near[n]
		var p: Vector2 = E.pos[i]
		if p.distance_to(lxz) > LEASH or not _reachable(hxz, p):
			continue
		var score: float = hxz.distance_to(p) + 0.6 * float(E.query(p, MELEE_CROWD).size())
		if i == current:
			score -= 1.0 # don't flit between targets
		if score < best_score:
			best_score = score
			best = i
	if best < 0 and current >= 0:
		return current
	return best if best >= 0 else _hunt(hxz, lxz)


## Which side of the target to stand on: the one with the fewest enemies,
## inside the leash, not too far to walk. Keeps to the current side unless
## another is clearly quieter.
func _quiet_side(h, hxz: Vector2, txz: Vector2, lxz: Vector2) -> Vector2:
	var stand := _stand_off(h)
	var now := hxz - txz
	var current := now / now.length() if now.length() > 0.05 else Vector2.UP
	var best := current
	var best_score := INF
	for k in 9:
		var dir: Vector2 = current if k == 8 else Vector2.from_angle(k * TAU / 8.0)
		var p := txz + dir * stand
		if p.distance_to(lxz) > LEASH * 0.95 or Game.blocked(p, 0.4) or Game.clamp_arena(p) != p or not _reachable(txz, p):
			continue
		var score: float = float(Game.enemies.query(p, MELEE_CROWD).size()) + 0.15 * p.distance_to(hxz)
		if k == 8:
			score -= 0.75
		if score < best_score:
			best_score = score
			best = dir
	return best


## Where to break away to: the thinnest ground within a few metres, leaning
## toward the leader.
func _escape_spot(hxz: Vector2, lxz: Vector2) -> Vector2:
	var best := lxz
	var best_score := INF
	for ring in [3.0, 5.0]:
		for k in 8:
			var p: Vector2 = hxz + Vector2.from_angle(k * TAU / 8.0) * ring
			if p.distance_to(lxz) > LEASH * 0.9 or Game.blocked(p, 0.4) or Game.clamp_arena(p) != p or not _reachable(hxz, p):
				continue
			var score: float = float(Game.enemies.query(p, 3.0).size()) + 0.3 * p.distance_to(lxz)
			if score < best_score:
				best_score = score
				best = p
	return best


## True if a hero can walk straight from `a` to `b` (no Keep wall between).
func _reachable(a: Vector2, b: Vector2) -> bool:
	return Game.keep == null or Game.keep.clear(a, b, 0.3)


## The living healer a hurt hero should run to (not themselves).
func _healer_for(h):
	for a in heroes:
		if a != h and a.is_healer() and not a.downed:
			return a
	return null


## Ranged followers kite. When their shot is ready they close to shooting
## range and fire; while it reloads they slip to the nearby spot with the
## fewest enemies around it, as long as the target stays in range and the
## spot is inside the leash. Returns [goal, stop distance].
func _kite(h, target: int, lxz: Vector2, near_ally, delta: float, zone := Vector2.ZERO, zone_r := 0.0) -> Array:
	var txz: Vector2 = Game.enemies.pos[target]
	var hxz := Vector2(h.position.x, h.position.z)
	var keep: float = h.shot_range() * KITE_KEEP_RANGE
	if h.attack_ready():
		h.kite_timer = 0.0
		if hxz.distance_to(txz) > keep and zone_r <= 0.0:
			return [Vector3(txz.x, 0.0, txz.y), keep * 0.9]
		return [h.position, 0.06] # in range: stand and fire
	h.kite_timer -= delta
	if h.kite_timer <= 0.0:
		h.kite_timer = KITE_RETHINK
		h.kite_spot = _quietest_spot(hxz, txz, keep, lxz, near_ally, zone, zone_r)
	return [h.kite_spot, 0.15]


func _quietest_spot(from: Vector2, target: Vector2, keep: float, lxz: Vector2, near_ally, zone: Vector2, zone_r: float) -> Vector3:
	var best := from
	var best_score := INF
	for ring in [0.0, KITE_STEP, KITE_STEP * 2.0]:
		var dirs := 1 if ring == 0.0 else 8
		for k in dirs:
			var p: Vector2 = from + Vector2.from_angle(k * TAU / 8.0) * ring
			if p.distance_to(lxz) > LEASH * 0.9 or p.distance_to(target) > keep:
				continue
			if near_ally != null and p.distance_to(Vector2(near_ally.position.x, near_ally.position.z)) > HEALER_STAY_NEAR:
				continue
			if zone_r > 0.0 and p.distance_to(zone) > zone_r:
				continue
			if Game.blocked(p, 0.4) or Game.clamp_arena(p) != p or not _reachable(from, p):
				continue
			# Fewest enemies close by; break ties by not walking far.
			var score: float = float(Game.enemies.query(p, KITE_CROWD_RADIUS).size()) + ring * 0.05
			if score < best_score:
				best_score = score
				best = p
	return Vector3(best.x, 0.0, best.y)


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


## Stops heroes standing inside each other, or inside the ruins.
func _separate_heroes() -> void:
	for h in heroes:
		var p := Vector2(h.position.x, h.position.z)
		var out: Vector2 = Game.push_out(p, 0.4)
		if out != p:
			h.position.x = out.x
			h.position.z = out.y
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

## Called by the enemies for each blow.
func apply_hit(target, amount: float, enemy_index: int) -> void:
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


# --- Bram's anvils ---------------------------------------------------------------

## An anvil on the ground: heroes within `radius` attack faster and hit
## harder by `bonus` (0.15 = +15%) for `seconds`.
func place_anvil(at: Vector3, radius: float, seconds: float, bonus: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, 0.0, at.z)
	add_child(root)
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.45, 0.5)
	block.mesh = box
	block.material_override = Game.material(Color(0.25, 0.27, 0.3))
	block.position.y = 0.55
	root.add_child(block)
	var base := MeshInstance3D.new()
	var foot := BoxMesh.new()
	foot.size = Vector3(0.45, 0.4, 0.4)
	base.mesh = foot
	base.material_override = Game.material(Color(0.2, 0.2, 0.22))
	base.position.y = 0.2
	root.add_child(base)
	var ring := _ground_ring(radius - 0.12, radius, Color(0.25, 0.8, 0.75, 0.35))
	ring.reparent(root, false)
	ring.position = Vector3(0.0, 0.05, 0.0)
	anvils.append({"pos": root.position, "radius": radius, "time": seconds, "bonus": bonus, "node": root})
	Game.fx.ring(root.position, radius, Color(0.25, 0.8, 0.75), 0.4)


## The best anvil bonus at a spot (0 if none).
func anvil_bonus(p: Vector3) -> float:
	var best := 0.0
	for a in anvils:
		if Vector2(p.x - a["pos"].x, p.z - a["pos"].z).length() <= a["radius"]:
			best = maxf(best, a["bonus"])
	return best


func _tick_anvils(delta: float) -> void:
	var i := anvils.size() - 1
	while i >= 0:
		anvils[i]["time"] -= delta
		if anvils[i]["time"] <= 0.0:
			anvils[i]["node"].queue_free()
			anvils.remove_at(i)
		i -= 1
