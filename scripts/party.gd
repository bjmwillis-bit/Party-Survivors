extends Node3D
## The party of three: moving the leader, keeping followers in formation,
## swapping who leads, sharing damage and reviving fallen heroes.

const HeroScript := preload("res://scripts/hero.gd")

const SWAP_COOLDOWN := 1.0
const REVIVE_RANGE := 1.8

var heroes: Array = []
var leader_index := 0
var swap_timer := 0.0

# Numbers that upgrades can change.
var speed := 6.2
var speed_mult := 1.0
var haste := 1.0 # multiplies every hero's attack speed
var lead_bonus := 1.2 # the leader deals 20% more damage
var revive_time := 3.0

var _form_yaw := 0.0 # the direction the formation faces; turns smoothly
var _wiped := false


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


func _process(delta: float) -> void:
	if _wiped:
		return
	swap_timer = maxf(0.0, swap_timer - delta)
	if Input.is_action_just_pressed("swap"):
		swap()
	_move_leader(delta)
	_move_followers(delta)
	_tick_revive(delta)


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


## The living ally with the lowest health (as a fraction), not counting `exclude`.
func lowest_health_ally(exclude):
	var best = null
	var best_frac := 1.0
	for h in heroes:
		if h == exclude or h.downed:
			continue
		var frac: float = h.hp / h.max_hp
		if frac < best_frac:
			best_frac = frac
			best = h
	return best


# --- Movement ----------------------------------------------------------------

func _move_leader(delta: float) -> void:
	var l = leader()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	if Game.main.autopilot:
		dir = Game.main.autopilot_dir
	if dir.length() > 1.0:
		dir = dir.normalized()
	l.moving = dir.length() > 0.1
	l.move_dir = dir
	if not l.moving:
		return
	# Crisp: full speed instantly, no momentum or sliding.
	l.position += dir * speed * speed_mult * delta
	var a: float = Game.main.ARENA_HALF
	l.position.x = clampf(l.position.x, -a, a)
	l.position.z = clampf(l.position.z, -a, a)
	var yaw := atan2(dir.x, dir.z)
	if l.face_lock <= 0.0:
		l.facing = yaw
	_form_yaw = lerp_angle(_form_yaw, yaw, 1.0 - exp(-7.0 * delta))


func _move_followers(delta: float) -> void:
	var l = leader()
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
		if h.downed:
			h.moving = false
			continue
		var to: Vector3 = slot - h.position
		to.y = 0.0
		var d := to.length()
		if d < 0.06:
			h.moving = false
			h.move_dir = Vector3.ZERO
			continue
		# Followers catch up fast and settle, instead of floating on elastic.
		var spd := maxf(speed * speed_mult * 1.15, d * 9.0)
		var step := minf(d, spd * delta)
		h.position += to / d * step
		h.moving = step > speed * 0.25 * delta
		h.move_dir = to / d
		if h.face_lock <= 0.0 and h.moving:
			h.facing = atan2(to.x, to.z)


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

## Called by the enemies. Cenhelm takes part of any hit aimed at someone else.
func apply_contact_damage(target, amount: float) -> void:
	var c = hero("Cenhelm")
	if c != null and not c.downed and target != c:
		c.take_damage(amount * c.intercept_share)
		target.take_damage(amount * (1.0 - c.intercept_share))
	else:
		target.take_damage(amount)


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
