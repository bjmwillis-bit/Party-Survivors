extends Node3D
## One party member: stats, basic attack, two skills (Q and E), health,
## and the crisp grey-box look (step bob, dust, hit flash, attack lunge).
##
## The leader's Q, E and R (ultimate) are cast by the player. Followers cast
## Q and E the moment they'd do something; only the leader can use an ultimate.
##
## Grey-box kits:
## - Solenne: slashes in an arc. Gains Contempt when struck (+5% damage each).
##   Q (passive) I'll Give You My Back: every blow she takes has a 30% chance
##   to trigger a counter-skewer at the attacker, piercing up to 4 enemies.
##   E Face Me: taunts enemies within 6 m for 6 s and takes 40% less damage.
##   R Ultrix: a backstep slash, then an 8 m lunge. Untouchable throughout.
## - Cenhelm: left-right punches, each with a small splash where it lands.
##   Damage scales with max HP. Takes 25% of hits aimed at allies.
##   Q The Gate: ground slam around him. Each punch takes 1 s off its cooldown.
##   E Walk Out: dashes to the lowest-health ally, stunning enemies on the way
##   and where he lands.
##   R The Horn: everything within 16 m is slowed by half for 6 s, takes a
##   little damage each second, and is pushed back slightly.
## - Kheiron: fires bolts.
##   Q Lesson: heals the lowest-health ally (never himself) for 5% max health.
##   E The Grove: a healing grove at his feet, the size of the leash, for 4 s.
##   R Give the Sky: pays 20% of his max health to reset the other heroes'
##   ultimates.

const DATA := {
	"solenne": {
		"name": "Solenne", "hp": 120.0, "interval": 0.75, "damage": 14.0,
		"color": Color(0.92, 0.9, 0.86), "accent": Color(0.78, 0.12, 0.12),
		"q": {"name": "I'll Give You My Back", "cd": 0.0, "passive": true},
		"e": {"name": "Face Me", "cd": 16.0},
		"r": {"name": "Ultrix", "cd": 45.0},
	},
	"cenhelm": {
		"name": "Cenhelm", "hp": 190.0, "interval": 0.55, "damage": 5.0,
		"color": Color(0.45, 0.36, 0.28), "accent": Color(0.95, 0.6, 0.15),
		"q": {"name": "The Gate", "cd": 10.0},
		"e": {"name": "Walk Out", "cd": 12.0},
		"r": {"name": "The Horn", "cd": 40.0},
	},
	"kheiron": {
		"name": "Kheiron", "hp": 95.0, "interval": 0.9, "damage": 9.0,
		"color": Color(0.32, 0.42, 0.3), "accent": Color(0.55, 0.95, 0.55),
		"q": {"name": "Lesson", "cd": 4.0},
		"e": {"name": "The Grove", "cd": 14.0},
		"r": {"name": "Give the Sky", "cd": 60.0},
	},
}

# Skill numbers (easy to tune).
const COUNTER_CHANCE := 0.3 # rolled separately for every blow she takes
const COUNTER_MAX_TARGETS := 4
const TAUNT_RADIUS := 6.0
const TAUNT_TIME := 6.0
const TAUNT_DAMAGE_TAKEN := 0.6 # 40% damage reduction
const FIST_REACH := 1.9
const FIST_SPLASH := 1.1
const SLAM_RADIUS := 3.5
const DASH_TIME := 0.22
const DASH_STUN := 1.5
const DASH_LAND_RADIUS := 2.0
const LESSON_HEAL := 0.05 # fraction of the target's max health
const GROVE_TIME := 4.0
const GROVE_HEAL := 0.015 # fraction of max health per second
const ULTRIX_BACKSTEP := 1.0
const ULTRIX_LUNGE := 8.0
const ULTRIX_SLASH_MULT := 1.0 # times her basic attack damage
const ULTRIX_LUNGE_MULT := 3.0
const HORN_RADIUS := 16.0 # twice the leash
const HORN_TIME := 6.0
const HORN_TICK_MULT := 0.25 # damage each second, times his punch damage
const HORN_PUSH := 3.0
const SKY_COST := 0.2 # fraction of his max health
const ULT_START_CHARGE := 0.5 # ultimates start the run half charged

var kind := ""
var hero_name := ""
var color := Color.WHITE
var accent := Color.WHITE
var max_hp := 100.0
var hp := 100.0
var downed := false
var is_leader := false
var revive_progress := 0.0

# Numbers that upgrades can change.
var base_damage := 10.0
var attack_interval := 1.0
var damage_mult := 1.0
var area_mult := 1.0
var rate_mult := 1.0
var heal_mult := 1.0
var extra_bolts := 0
var contempt_cap := 10
var intercept_share := 0.25

var contempt := 0
var facing := 0.0 # where the hero wants to face (radians)
var face_lock := 0.0 # while > 0, the hero keeps facing their attack
var move_dir := Vector3.ZERO
var moving := false
var aim_dir := Vector2.ZERO # where the player aims (used while leading)
var returning := false # a follower running back inside the leash
var dashing := false # busy moving under a skill's control (dash, lunge)
var invulnerable := false
var cooldown := {"q": 0.0, "e": 0.0, "r": 0.0} # seconds left
## How often each skill went off this run (for tuning and tests).
var stats := {"q": 0, "e": 0, "r": 0, "counter": 0}

var _attack_timer := 0.4
var _taunt_time := 0.0
var _punch_side := 1.0
var _twist := 0.0
var _dash_from := Vector3.ZERO
var _dash_to := Vector3.ZERO
var _dash_t := 0.0
var _dash_hit := {}
var _ult_phase := 0 # Ultrix: 0 idle, 1 backstep, 2 lunge
var _ult_t := 0.0
var _ult_dir := Vector2.ZERO
var _ult_from := Vector3.ZERO
var _ult_to := Vector3.ZERO
var _ult_hit := {}
var _contempt_hit_cd := 0.0
var _contempt_decay := 0.0
var _flash := 0.0
var _hurt_flash_cd := 0.0
var _bob := 0.0
var _step_timer := 0.0
var _lunge := 0.0
var _body: Node3D
var _mat: StandardMaterial3D
var _lead_ring: MeshInstance3D
var _revive_ring: MeshInstance3D
var _taunt_ring: MeshInstance3D


func setup(hero_kind: String) -> void:
	kind = hero_kind
	var d: Dictionary = DATA[kind]
	hero_name = d["name"]
	color = d["color"]
	accent = d["accent"]
	max_hp = d["hp"]
	hp = max_hp
	base_damage = d["damage"]
	attack_interval = d["interval"]
	cooldown["r"] = d["r"]["cd"] * ULT_START_CHARGE
	_build_visual()
	_taunt_ring = _flat_ring(0.95, 1.1, Color(accent.r, accent.g, accent.b, 0.7))
	_taunt_ring.visible = false


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_hurt_flash_cd = maxf(0.0, _hurt_flash_cd - delta)
	face_lock = maxf(0.0, face_lock - delta)
	_taunt_time = maxf(0.0, _taunt_time - delta)
	for slot in cooldown:
		cooldown[slot] = maxf(0.0, cooldown[slot] - delta)
	if _flash > 0.0:
		_mat.albedo_color = Color.WHITE
	elif downed:
		_mat.albedo_color = color.darkened(0.55)
	else:
		_mat.albedo_color = color
	_lead_ring.visible = is_leader and not downed
	_revive_ring.visible = downed
	_taunt_ring.visible = _taunt_time > 0.0 and not downed

	if downed:
		dashing = false
		var frac: float = revive_progress / Game.party.revive_time
		_revive_ring.scale = Vector3.ONE * (0.4 + frac * 1.2)
		_body.rotation.x = lerpf(_body.rotation.x, -1.45, 1.0 - exp(-12.0 * delta))
		_body.position.y = 0.2
		return
	_body.rotation.x = lerpf(_body.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))

	if _ult_phase > 0:
		_tick_ultrix(delta)
	elif dashing:
		_tick_dash(delta)

	# Snap to face the new direction almost instantly.
	rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-30.0 * delta))

	# Stepping: a quick bob and sway, with a puff of dust on each footfall.
	if moving:
		_bob += delta * 14.0
		_body.position.y = absf(sin(_bob)) * 0.12
		_body.rotation.z = sin(_bob) * 0.06
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = PI / 14.0
			Game.fx.dust(position)
	else:
		_bob = 0.0
		_body.position.y = move_toward(_body.position.y, 0.0, delta * 2.0)
		_body.rotation.z = 0.0

	# A short lunge forward when attacking, and a shoulder twist on punches.
	_lunge = maxf(0.0, _lunge - delta * 6.0)
	_body.position.z = _lunge * 0.35
	_twist = move_toward(_twist, 0.0, delta * 3.0)
	_body.rotation.y = _twist

	_tick_attack(delta)
	_tick_passives(delta)
	if not is_leader:
		_ai_cast()


# --- Basic attacks -----------------------------------------------------------

func _tick_attack(delta: float) -> void:
	if dashing:
		return
	_attack_timer -= delta * rate_mult * Game.party.haste
	if _attack_timer > 0.0:
		return
	var attacked := false
	match kind:
		"solenne":
			attacked = _attack_solenne()
		"cenhelm":
			attacked = _attack_cenhelm()
		"kheiron":
			attacked = _attack_kheiron()
	# No target in range: check again shortly.
	_attack_timer = attack_interval if attacked else 0.1


func _power() -> float:
	var p := base_damage * damage_mult
	if kind == "cenhelm":
		p += max_hp * 0.035 # "Scales with his max HP."
	if kind == "solenne":
		p *= 1.0 + 0.05 * contempt
	if is_leader:
		p *= Game.party.lead_bonus
	return p


func _my_xz() -> Vector2:
	return Vector2(position.x, position.z)


func is_healer() -> bool:
	return kind == "kheiron"


## How close a follower gets to its target before stopping to fight.
func engage_range() -> float:
	match kind:
		"solenne":
			return 1.8
		"cenhelm":
			return 1.5
		"kheiron":
			return 7.0
	return 2.0


## Is any enemy inside a cone of `reach` and `half` angle around `dir`?
func _enemy_in_arc(me: Vector2, dir: Vector2, reach: float, half: float) -> bool:
	for i in Game.enemies.query(me, reach):
		var rel: Vector2 = Game.enemies.pos[i] - me
		if rel.length() < 0.001 or absf(dir.angle_to(rel)) <= half:
			return true
	return false


## The direction to attack in: where the player aims (when leading and
## something is there), otherwise toward the nearest enemy in reach.
## Returns Vector2.ZERO if there is nothing to hit.
func _attack_dir(me: Vector2, reach: float, half: float) -> Vector2:
	if is_leader and aim_dir != Vector2.ZERO:
		return aim_dir if _enemy_in_arc(me, aim_dir, reach, half) else Vector2.ZERO
	var target: int = Game.enemies.nearest(me, reach)
	if target < 0:
		return Vector2.ZERO
	return (Game.enemies.pos[target] - me).normalized()


func _attack_solenne() -> bool:
	var reach := 3.0 * area_mult
	var me := _my_xz()
	var half := deg_to_rad(65.0)
	var dir := _attack_dir(me, reach, half)
	if dir == Vector2.ZERO:
		return false
	var yaw := atan2(dir.x, dir.y)
	var dmg := _power()
	for i in Game.enemies.query(me, reach):
		var rel: Vector2 = Game.enemies.pos[i] - me
		if rel.length() > 0.001 and absf(dir.angle_to(rel)) > half:
			continue
		Game.enemies.damage(i, dmg, rel.normalized(), 6.0)
	Game.fx.slash(position, yaw, reach, half, accent)
	facing = yaw
	face_lock = 0.15
	_lunge = 1.0
	return true


## Left, right, left, right: each punch splashes where it lands.
func _attack_cenhelm() -> bool:
	var splash := FIST_SPLASH * area_mult
	var me := _my_xz()
	var dir := _attack_dir(me, FIST_REACH + splash, deg_to_rad(60.0))
	if dir == Vector2.ZERO:
		return false
	_punch_side = -_punch_side
	var side := Vector2(-dir.y, dir.x)
	var impact := me + dir * FIST_REACH * 0.8 + side * 0.3 * _punch_side
	var dmg := _power()
	for i in Game.enemies.query(impact, splash):
		var rel: Vector2 = Game.enemies.pos[i] - impact
		var push := rel.normalized() if rel.length() > 0.05 else dir
		Game.enemies.damage(i, dmg, push, 5.0)
	Game.fx.ring(Vector3(impact.x, 0.0, impact.y), splash, accent, 0.15)
	facing = atan2(dir.x, dir.y)
	face_lock = 0.15
	_lunge = 0.7
	_twist = 0.35 * _punch_side
	# Every punch brings The Gate closer.
	cooldown["q"] = maxf(0.0, cooldown["q"] - 1.0)
	return true


func _attack_kheiron() -> bool:
	var me := _my_xz()
	var target: int = Game.enemies.nearest(me, 13.0)
	if target < 0:
		return false
	var to: Vector2 = (Game.enemies.pos[target] - me).normalized()
	if is_leader and aim_dir != Vector2.ZERO:
		to = aim_dir # leading: fire where the player aims
	var count := 1 + extra_bolts
	for b in count:
		var spread := (b - (count - 1) * 0.5) * 0.18
		Game.fx.bolt(position + Vector3(0.0, 1.0, 0.0), to.rotated(spread), _power(), 0, accent)
	facing = atan2(to.x, to.y)
	face_lock = 0.12
	_lunge = 0.4
	return true


# --- Skills (Q and E) --------------------------------------------------------

func skill_name(slot: String) -> String:
	return DATA[kind][slot]["name"]


func skill_is_passive(slot: String) -> bool:
	return bool(DATA[kind][slot].get("passive", false))


## Try to use a skill. Returns true if it went off.
func cast(slot: String) -> bool:
	if downed or dashing or skill_is_passive(slot) or cooldown[slot] > 0.0:
		return false
	if slot == "r" and not is_leader:
		return false # only the leader can use an ultimate
	var done := false
	match kind + "_" + slot:
		"solenne_e":
			done = _face_me()
		"cenhelm_q":
			done = _the_gate()
		"cenhelm_e":
			done = _walk_out()
		"kheiron_q":
			done = _lesson()
		"kheiron_e":
			done = _the_grove()
		"solenne_r":
			done = _ultrix()
		"cenhelm_r":
			done = _the_horn()
		"kheiron_r":
			done = _give_the_sky()
	if done:
		cooldown[slot] = DATA[kind][slot]["cd"]
		stats[slot] += 1
	return done


## Followers fire skills the moment they're ready and would do something.
func _ai_cast() -> void:
	for slot in ["q", "e"]:
		if cooldown[slot] <= 0.0 and not skill_is_passive(slot) and _worth_casting(slot):
			cast(slot)


func _worth_casting(slot: String) -> bool:
	var me := _my_xz()
	match kind + "_" + slot:
		"solenne_e":
			return Game.enemies.nearest(me, TAUNT_RADIUS) >= 0
		"cenhelm_q":
			return Game.enemies.nearest(me, SLAM_RADIUS * area_mult) >= 0
		"cenhelm_e":
			return _dash_target() != null
		"kheiron_q", "kheiron_e":
			return Game.party.lowest_health_ally(self, 1.0) != null
	return false


## Solenne E: taunt nearby enemies and harden.
func _face_me() -> bool:
	Game.enemies.taunt_in_radius(_my_xz(), TAUNT_RADIUS, Game.party.heroes.find(self), TAUNT_TIME)
	_taunt_time = TAUNT_TIME
	Game.fx.ring(position, TAUNT_RADIUS, accent, 0.35)
	if is_leader:
		Game.add_shake(0.15)
	return true


## Cenhelm Q: ground slam.
func _the_gate() -> bool:
	var me := _my_xz()
	var r := SLAM_RADIUS * area_mult
	var dmg := _power() * 2.0
	for i in Game.enemies.query(me, r):
		var rel: Vector2 = Game.enemies.pos[i] - me
		var push := rel.normalized() if rel.length() > 0.05 else Vector2.RIGHT
		Game.enemies.damage(i, dmg, push, 12.0)
	Game.fx.ring(position, r, accent, 0.25)
	Game.fx.ring(position, r * 0.6, Color.WHITE, 0.18)
	_lunge = 0.8
	if is_leader:
		Game.add_shake(0.3)
		Game.hitstop(0.05)
	return true


## Cenhelm E: dash to the lowest-health ally, stunning enemies on the way
## and around where he lands. Even a short hop is worth it for the landing.
func _walk_out() -> bool:
	var ally = _dash_target()
	if ally == null:
		return false
	var to: Vector3 = ally.position - position
	to.y = 0.0
	var d := to.length()
	_dash_from = position
	_dash_to = position
	if d > 0.01:
		_dash_to = position + to / d * maxf(0.0, d - 1.0)
		facing = atan2(to.x, to.z)
	_dash_t = 0.0
	_dash_hit = {}
	dashing = true
	face_lock = DASH_TIME + 0.1
	return true


## Who Cenhelm dashes to: the living ally with the lowest health percentage
## inside the leash. Ties go to the nearest.
func _dash_target():
	var best = null
	var best_frac := INF
	var best_d := INF
	var l = Game.party.leader()
	for h in Game.party.heroes:
		if h == self or h.downed:
			continue
		if l != null and h.position.distance_to(l.position) > Game.party.LEASH:
			continue
		var frac: float = h.hp / h.max_hp
		var d: float = position.distance_to(h.position)
		if frac < best_frac - 0.001 or (absf(frac - best_frac) <= 0.001 and d < best_d):
			best_frac = frac
			best_d = d
			best = h
	return best


func _tick_dash(delta: float) -> void:
	_dash_t += delta
	var t := minf(1.0, _dash_t / DASH_TIME)
	position = _dash_from.lerp(_dash_to, t)
	var me := _my_xz()
	var dmg := _power() * 1.2
	for i in Game.enemies.query(me, 1.4):
		if _dash_hit.has(i):
			continue
		_dash_hit[i] = true
		Game.enemies.stun(i, DASH_STUN)
		var rel: Vector2 = Game.enemies.pos[i] - me
		var push := rel.normalized() if rel.length() > 0.05 else Vector2.UP
		Game.enemies.damage(i, dmg, push, 7.0)
	Game.fx.dust(position)
	if t >= 1.0:
		dashing = false
		# The landing: same damage and stun in a small circle.
		var land := DASH_LAND_RADIUS * area_mult
		for i in Game.enemies.query(me, land):
			Game.enemies.stun(i, DASH_STUN)
			var rel: Vector2 = Game.enemies.pos[i] - me
			var push := rel.normalized() if rel.length() > 0.05 else Vector2.UP
			Game.enemies.damage(i, dmg, push, 7.0)
		Game.fx.ring(position, land, accent, 0.22)
		Game.fx.ring(position, land * 0.5, Color.WHITE, 0.15)
		if is_leader:
			Game.add_shake(0.25)


## Kheiron Q: heal the most hurt ally.
func _lesson() -> bool:
	var t = Game.party.lowest_health_ally(self, 1.0)
	if t == null:
		return false
	t.heal(t.max_hp * LESSON_HEAL * heal_mult)
	Game.fx.ring(t.position, 1.2, accent, 0.35)
	Game.fx.ring(position, 0.8, accent, 0.2)
	_lunge = 0.5
	return true


## Kheiron E: a grove at his feet that heals allies standing in it.
func _the_grove() -> bool:
	Game.party.place_grove(position, Game.party.LEASH, GROVE_TIME, GROVE_HEAL * heal_mult)
	return true


# --- Ultimates (R, leader only) ----------------------------------------------

## Solenne R: a slash as she steps back, then a long lunge where you aim.
func _ultrix() -> bool:
	_ult_dir = aim_dir if aim_dir != Vector2.ZERO else Vector2(sin(facing), cos(facing))
	var me := _my_xz()
	var half := deg_to_rad(65.0)
	var reach := 3.0 * area_mult
	var dmg := _power() * ULTRIX_SLASH_MULT
	for i in Game.enemies.query(me, reach):
		var rel: Vector2 = Game.enemies.pos[i] - me
		if rel.length() > 0.001 and absf(_ult_dir.angle_to(rel)) > half:
			continue
		Game.enemies.damage(i, dmg, rel.normalized(), 8.0)
	var yaw := atan2(_ult_dir.x, _ult_dir.y)
	Game.fx.slash(position, yaw, reach, half, accent)
	facing = yaw
	face_lock = 0.6
	_ult_from = position
	_ult_to = position - Vector3(_ult_dir.x, 0.0, _ult_dir.y) * ULTRIX_BACKSTEP
	_ult_phase = 1
	_ult_t = 0.0
	_ult_hit = {}
	dashing = true
	invulnerable = true
	return true


func _tick_ultrix(delta: float) -> void:
	_ult_t += delta
	var a: float = Game.main.ARENA_HALF
	if _ult_phase == 1:
		# Backstep, then a beat before the lunge.
		position = _ult_from.lerp(_ult_to, minf(1.0, _ult_t / 0.12))
		if _ult_t >= 0.22:
			_ult_phase = 2
			_ult_t = 0.0
			_ult_from = position
			var end := position + Vector3(_ult_dir.x, 0.0, _ult_dir.y) * ULTRIX_LUNGE
			end.x = clampf(end.x, -a, a)
			end.z = clampf(end.z, -a, a)
			_ult_to = end
			Game.fx.thrust(position, facing, ULTRIX_LUNGE, Color(1.0, 0.15, 0.1))
			if is_leader:
				Game.hitstop(0.05)
				Game.add_shake(0.35)
		return
	# Lunge: everything she passes through takes the heavy hit.
	var t := minf(1.0, _ult_t / 0.18)
	position = _ult_from.lerp(_ult_to, t)
	var me := _my_xz()
	var dmg := _power() * ULTRIX_LUNGE_MULT
	for i in Game.enemies.query(me, 1.3):
		if _ult_hit.has(i):
			continue
		_ult_hit[i] = true
		Game.enemies.damage(i, dmg, _ult_dir, 10.0)
	_lunge = 1.0
	if t >= 1.0:
		_ult_phase = 0
		dashing = false
		invulnerable = false
		Game.fx.ring(position, 2.0, Color(1.0, 0.15, 0.1), 0.2)


## Cenhelm R: blows the horn.
func _the_horn() -> bool:
	var tick := (base_damage * damage_mult + max_hp * 0.035) * HORN_TICK_MULT
	Game.enemies.horn(_my_xz(), HORN_RADIUS, HORN_TIME, tick, HORN_PUSH)
	Game.fx.ring(position, HORN_RADIUS, accent, 0.6)
	Game.fx.ring(position, HORN_RADIUS * 0.5, accent, 0.45)
	Game.fx.ring(position, 3.0, Color.WHITE, 0.3)
	_lunge = 0.8
	if is_leader:
		Game.add_shake(0.4)
		Game.hitstop(0.06)
	return true


## Kheiron R: pays health to reset the other heroes' ultimates.
func _give_the_sky() -> bool:
	hp = maxf(1.0, hp - max_hp * SKY_COST)
	_flash = 0.12
	for h in Game.party.heroes:
		if h == self:
			continue
		h.cooldown["r"] = 0.0
		if not h.downed:
			Game.fx.ring(h.position, 1.4, accent, 0.4)
	Game.fx.ring(position, 2.5, accent, 0.45)
	if is_leader:
		Game.add_shake(0.2)
	return true


# --- Passives ----------------------------------------------------------------

func _tick_passives(delta: float) -> void:
	if kind == "solenne":
		_contempt_hit_cd = maxf(0.0, _contempt_hit_cd - delta)
		if contempt > 0:
			_contempt_decay -= delta
			if _contempt_decay <= 0.0:
				contempt -= 1
				_contempt_decay = 3.0


## Solenne's counter: a straight skewer at the enemy who struck her,
## piercing up to a few enemies in a line. Same reach and damage as her cut.
func _counter(attacker: int) -> void:
	var me := _my_xz()
	var reach := 3.0 * area_mult
	var target := attacker
	if target < 0 or target >= Game.enemies.count or Game.enemies.hp[target] <= 0.0:
		target = Game.enemies.nearest(me, reach + 1.0)
	if target < 0:
		return
	var rel_t: Vector2 = Game.enemies.pos[target] - me
	var dir: Vector2 = rel_t.normalized() if rel_t.length() > 0.01 else Vector2(sin(facing), cos(facing))
	var line: Array = []
	for i in Game.enemies.query(me, reach):
		var rel: Vector2 = Game.enemies.pos[i] - me
		var along := rel.dot(dir)
		if along > 0.0 and absf(rel.cross(dir)) < 0.7:
			line.append([along, i])
	line.sort_custom(func(a, b): return a[0] < b[0])
	var dmg := _power()
	for k in mini(line.size(), COUNTER_MAX_TARGETS):
		Game.enemies.damage(line[k][1], dmg, dir, 8.0)
	stats["counter"] += 1
	var yaw := atan2(dir.x, dir.y)
	Game.fx.thrust(position, yaw, reach, accent)
	facing = yaw
	face_lock = 0.15
	_lunge = 1.0


# --- Health ------------------------------------------------------------------

## A blow from an enemy. For Solenne, every blow rolls its own counter.
func take_hit(amount: float, attacker: int) -> void:
	if downed or invulnerable:
		return
	take_damage(amount)
	if kind == "solenne" and not downed and randf() < COUNTER_CHANCE:
		_counter(attacker)


func take_damage(amount: float) -> void:
	if downed or invulnerable:
		return
	if _taunt_time > 0.0:
		amount *= TAUNT_DAMAGE_TAKEN
	hp -= amount
	if _hurt_flash_cd <= 0.0:
		_flash = 0.08
		_hurt_flash_cd = 0.3
	if kind == "solenne":
		if _contempt_hit_cd <= 0.0:
			contempt = mini(contempt + 1, contempt_cap)
			_contempt_hit_cd = 0.4
			_contempt_decay = 3.0
	if hp <= 0.0:
		hp = 0.0
		downed = true
		revive_progress = 0.0
		moving = false
		_taunt_time = 0.0
		_ult_phase = 0
		dashing = false
		invulnerable = false
		Game.party.on_hero_downed(self)


func heal(amount: float) -> void:
	if downed:
		return
	hp = minf(max_hp, hp + amount)


func revive() -> void:
	downed = false
	revive_progress = 0.0
	hp = max_hp * 0.35


# --- Look --------------------------------------------------------------------
# Grey-box shapes: a faceted body, a head, and one signature prop in the
# hero's accent colour, so each reads at a distance. Real models replace this.

func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	_mat = Game.material(color)
	var accent_mat := Game.material(accent, 0.5)
	var size := 1.0
	if kind == "cenhelm":
		size = 1.25
	elif kind == "kheiron":
		size = 0.95

	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.36 * size
	torso_mesh.height = 1.5 * size
	torso_mesh.radial_segments = 8
	torso_mesh.rings = 2
	_part(Game.flat_mesh(torso_mesh), _mat, Vector3(0.0, torso_mesh.height * 0.5, 0.0))

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22 * size
	head_mesh.height = 0.44 * size
	head_mesh.radial_segments = 6
	head_mesh.rings = 3
	var head_y := torso_mesh.height + 0.12 * size
	_part(Game.flat_mesh(head_mesh), _mat, Vector3(0.0, head_y, 0.0))

	# A band across the eyes shows which way the hero faces.
	var eyes := BoxMesh.new()
	eyes.size = Vector3(0.26 * size, 0.07, 0.08)
	_part(eyes, accent_mat, Vector3(0.0, head_y + 0.02, 0.19 * size))

	match kind:
		"solenne":
			var cape := BoxMesh.new()
			cape.size = Vector3(0.62, 1.05, 0.08)
			_part(cape, accent_mat, Vector3(0.0, 1.0, -0.38))
			var sword := BoxMesh.new()
			sword.size = Vector3(0.07, 1.25, 0.07)
			var s := _part(sword, Game.material(Color(0.95, 0.95, 1.0), 0.2), Vector3(0.42, 0.9, 0.22))
			s.rotation_degrees = Vector3(35.0, 0.0, 0.0)
		"cenhelm":
			var shoulders := BoxMesh.new()
			shoulders.size = Vector3(1.15, 0.3, 0.55)
			_part(shoulders, Game.material(color.darkened(0.25)), Vector3(0.0, 1.6, 0.0))
			var horn := CylinderMesh.new()
			horn.top_radius = 0.03
			horn.bottom_radius = 0.13
			horn.height = 0.6
			horn.radial_segments = 6
			var h := _part(Game.flat_mesh(horn), accent_mat, Vector3(0.62, 1.25, 0.0))
			h.rotation_degrees = Vector3(0.0, 0.0, -70.0)
		"kheiron":
			var staff := CylinderMesh.new()
			staff.top_radius = 0.04
			staff.bottom_radius = 0.05
			staff.height = 2.0
			staff.radial_segments = 5
			_part(staff, Game.material(Color(0.4, 0.3, 0.2)), Vector3(0.42, 1.0, 0.15))
			var tip := SphereMesh.new()
			tip.radius = 0.12
			tip.height = 0.24
			tip.radial_segments = 5
			tip.rings = 2
			_part(Game.flat_mesh(tip), Game.material(accent, 1.5), Vector3(0.42, 2.05, 0.15))

	_lead_ring = _flat_ring(0.62, 0.78, Color(1.0, 0.82, 0.3, 0.9))
	_revive_ring = _flat_ring(0.85, 1.0, Color(0.5, 1.0, 0.5, 0.8))
	_revive_ring.visible = false


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	_body.add_child(m)
	return m


func _flat_ring(inner: float, outer: float, ring_color: Color) -> MeshInstance3D:
	var ring := TorusMesh.new()
	ring.inner_radius = inner
	ring.outer_radius = outer
	ring.rings = 24
	ring.ring_segments = 3
	var m := MeshInstance3D.new()
	m.mesh = ring
	m.material_override = Game.effect_material(ring_color)
	m.scale = Vector3(1.0, 0.15, 1.0)
	m.position.y = 0.05
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m
