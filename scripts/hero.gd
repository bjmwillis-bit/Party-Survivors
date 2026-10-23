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
## Effects switched on by epic and ultimate cards (card id -> value).
var mods := {}
var ult_cards := 0 # ultimate cards taken for this hero (bonds need one)
var cd_mult := {"q": 1.0, "e": 1.0, "r": 1.0}
var damage_buff_t := 0.0 # Shared Sky: +20% damage while > 0

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
var _ult_start := Vector3.ZERO
var _ult_mult := 1.0
var _ult_returning := false
var _swing_count := 0
var _punch_count := 0
var _freca := 0 # punches left at double damage
var _counter_boost_t := 0.0 # Back to Back: doubled counter chance while > 0
var _contempt_hit_cd := 0.0
var _contempt_decay := 0.0
var _flash := 0.0
var _hurt_flash_cd := 0.0
var _bob := 0.0
var _step_timer := 0.0
var _lunge := 0.0
var _body: Node3D
var _mat: StandardMaterial3D
var _hp_ring: MeshInstance3D # health on the ground: a ring that empties as they're hurt
var _hp_mat: ShaderMaterial
var _hp_shown := 1.0
## Ranged kiting: where this follower is heading between shots.
var kite_spot := Vector3.ZERO
var kite_timer := 0.0
var _revive_ring: MeshInstance3D
var _taunt_ring: MeshInstance3D
var _model: Node3D # the KayKit placeholder model, if it loaded
var _anim: AnimationPlayer
var _anim_state := ""
var _meshes: Array[MeshInstance3D] = []
var _skel: Skeleton3D
## Sitting by the fire: 0 standing, 1 seated on a log (blends while getting up).
var sit := 0.0
var seat_raise := 0.0 # how far the model lifts to sit on the log
var _tint := -1


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
	_build_hp_ring()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_hurt_flash_cd = maxf(0.0, _hurt_flash_cd - delta)
	face_lock = maxf(0.0, face_lock - delta)
	_taunt_time = maxf(0.0, _taunt_time - delta)
	damage_buff_t = maxf(0.0, damage_buff_t - delta)
	_counter_boost_t = maxf(0.0, _counter_boost_t - delta)
	for slot in cooldown:
		cooldown[slot] = maxf(0.0, cooldown[slot] - delta)
	if _model != null:
		_set_tint(2 if _flash > 0.0 else (1 if downed else 0))
		_update_anim()
		# The animation plays first, then the legs fold over the log if seated.
		_anim.advance(delta)
		if sit > 0.0:
			fold_legs(_skel, sit)
		_model.position.y = sit * seat_raise
	elif _flash > 0.0:
		_mat.albedo_color = Color.WHITE
	elif downed:
		_mat.albedo_color = color.darkened(0.55)
	else:
		_mat.albedo_color = color
	_update_hp_ring(delta)
	_revive_ring.visible = downed
	_taunt_ring.visible = _taunt_time > 0.0 and not downed

	if downed:
		dashing = false
		var frac: float = revive_progress / Game.party.revive_time
		_revive_ring.scale = Vector3.ONE * (0.4 + frac * 1.2)
		if _model == null: # the model plays its death animation instead
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
		if _model == null: # the model's run cycle has its own bounce
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
	if damage_buff_t > 0.0:
		p *= 1.2
	return p


func has_mod(id: String) -> bool:
	return bool(mods.get(id, false))


func _my_xz() -> Vector2:
	return Vector2(position.x, position.z)


func is_healer() -> bool:
	return kind == "kheiron"


## Ranged heroes kite as followers: shoot when ready, reposition between shots.
func is_ranged() -> bool:
	return kind == "kheiron"


## How far a ranged hero can shoot.
func shot_range() -> float:
	return 13.0


## True when the next basic attack is (nearly) ready to fire.
func attack_ready() -> bool:
	return _attack_timer <= 0.12


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
	_swing_count += 1
	_slash(me, dir, reach, half, dmg)
	# Wasn't Looking: every third slash also cuts the arc behind her.
	if has_mod("sol_third") and _swing_count % 3 == 0:
		_slash(me, -dir, reach, half, dmg)
	facing = yaw
	face_lock = 0.15
	_lunge = 1.0
	return true


func _slash(me: Vector2, dir: Vector2, reach: float, half: float, dmg: float) -> void:
	for i in Game.enemies.query(me, reach):
		var rel: Vector2 = Game.enemies.pos[i] - me
		if rel.length() > 0.001 and absf(dir.angle_to(rel)) > half:
			continue
		Game.enemies.damage(i, dmg, rel.normalized(), 6.0)
	Game.fx.slash(position, atan2(dir.x, dir.y), reach, half, accent)


## Left, right, left, right: each punch splashes where it lands.
func _attack_cenhelm() -> bool:
	var splash := FIST_SPLASH * area_mult
	var me := _my_xz()
	var dir := _attack_dir(me, FIST_REACH + splash, deg_to_rad(60.0))
	if dir == Vector2.ZERO:
		return false
	_punch_side = -_punch_side
	_punch_count += 1
	var side := Vector2(-dir.y, dir.x)
	var impact := me + dir * FIST_REACH * 0.8 + side * 0.3 * _punch_side
	var dmg := _power()
	var knock := 5.0
	# First Blow: every 4th punch is an uppercut.
	var uppercut := has_mod("cen_uppercut") and _punch_count % 4 == 0
	if uppercut:
		dmg *= 2.0
		splash *= 1.8
		knock = 12.0
	# Freca: punches after the Horn hit twice as hard.
	if _freca > 0:
		dmg *= 2.0
		_freca -= 1
	for i in Game.enemies.query(impact, splash):
		var rel: Vector2 = Game.enemies.pos[i] - impact
		var push := rel.normalized() if rel.length() > 0.05 else dir
		Game.enemies.damage(i, dmg, push, knock)
	Game.fx.ring(Vector3(impact.x, 0.0, impact.y), splash, accent, 0.15)
	if uppercut:
		Game.fx.ring(Vector3(impact.x, 0.0, impact.y), splash * 0.6, Color.WHITE, 0.15)
		if is_leader:
			Game.add_shake(0.15)
	facing = atan2(dir.x, dir.y)
	face_lock = 0.15
	_lunge = 0.7
	_twist = 0.35 * _punch_side
	# Every punch brings The Gate closer.
	cooldown["q"] = maxf(0.0, cooldown["q"] - (1.5 if has_mod("cen_gate_cdr") else 1.0))
	return true


func _attack_kheiron() -> bool:
	var me := _my_xz()
	var target: int = Game.enemies.nearest(me, shot_range())
	if target < 0:
		return false
	var to: Vector2 = (Game.enemies.pos[target] - me).normalized()
	if is_leader and aim_dir != Vector2.ZERO:
		to = aim_dir # leading: fire where the player aims
	var count := 1 + extra_bolts
	for b in count:
		var spread := (b - (count - 1) * 0.5) * 0.18
		Game.fx.bolt(position + Vector3(0.0, 1.0, 0.0), to.rotated(spread), _power(), 2 if has_mod("khe_pierce") else 0, accent)
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
	if not Game.main.is_night():
		return false # no skills at the fire or on the walk home
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
		cooldown[slot] = DATA[kind][slot]["cd"] * cd_mult[slot]
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
	if has_mod("sol_pull"):
		Game.enemies.pull(_my_xz(), TAUNT_RADIUS, 9.0)
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
		if has_mod("cen_gate_stun"):
			Game.enemies.stun(i, 1.0)
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
		# Face The Fist: enemies around the landing turn on him.
		if has_mod("cen_walk_taunt"):
			Game.enemies.taunt_in_radius(me, 3.5, Game.party.heroes.find(self), 3.0)
		# Walk Out Together (bond): a small grove where he lands.
		if Game.party.bonds.has("bond_together"):
			var k = Game.party.hero("Kheiron")
			var hm: float = k.heal_mult if k != null else 1.0
			Game.party.place_grove(position, 3.0, 3.0, GROVE_HEAL * hm)
		if is_leader:
			Game.add_shake(0.25)


## Kheiron Q: heal the most hurt ally.
func _lesson() -> bool:
	var targets := _hurt_allies(2 if has_mod("khe_lesson_two") else 1)
	if targets.is_empty():
		return false
	for t in targets:
		t.heal(t.max_hp * LESSON_HEAL * heal_mult)
		Game.fx.ring(t.position, 1.2, accent, 0.35)
	Game.fx.ring(position, 0.8, accent, 0.2)
	_lunge = 0.5
	# The Wound: a volley at the enemy nearest the healed ally.
	if has_mod("khe_volley"):
		var t0 = targets[0]
		var e: int = Game.enemies.nearest(Vector2(t0.position.x, t0.position.z), 8.0)
		if e >= 0:
			var to: Vector2 = (Game.enemies.pos[e] - _my_xz()).normalized()
			for k in 3:
				Game.fx.bolt(position + Vector3(0.0, 1.0, 0.0), to.rotated((k - 1) * 0.12), _power(), 0, accent)
	return true


## The `n` living allies (not himself) with the lowest health percentage,
## counting only those who are missing health.
func _hurt_allies(n: int) -> Array:
	var list: Array = []
	for h in Game.party.heroes:
		if h == self or h.downed or h.hp >= h.max_hp:
			continue
		list.append(h)
	list.sort_custom(func(a, b): return a.hp / a.max_hp < b.hp / b.max_hp)
	return list.slice(0, n)


## Kheiron E: a grove at his feet that heals allies standing in it.
func _the_grove() -> bool:
	var seconds := GROVE_TIME + float(mods.get("grove_time", 0.0))
	var slow := 0.3 if has_mod("khe_grove_slow") else 0.0
	Game.party.place_grove(position, Game.party.LEASH, seconds, GROVE_HEAL * heal_mult, slow)
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
	# Even Blind: the backstep slash fires three flame waves.
	if has_mod("sol_u_flames"):
		for k in 3:
			Game.fx.bolt(position + Vector3(0.0, 0.7, 0.0), _ult_dir.rotated((k - 1) * 0.2), _power() * 1.5, 99,
				Color(1.0, 0.45, 0.1), 15.0, 2.2, 0.8)
	# Contempt Unbound: spend all Contempt for a heavier lunge.
	_ult_mult = 1.0
	if has_mod("sol_u_contempt"):
		_ult_mult += 0.1 * contempt
		contempt = 0
	facing = yaw
	face_lock = 0.6
	_ult_start = position
	_ult_returning = false
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
	if _ult_phase == 1:
		# Backstep, then a beat before the lunge.
		position = _ult_from.lerp(_ult_to, minf(1.0, _ult_t / 0.12))
		if _ult_t >= 0.22:
			_ult_phase = 2
			_ult_t = 0.0
			_ult_from = position
			var end := position + Vector3(_ult_dir.x, 0.0, _ult_dir.y) * ULTRIX_LUNGE
			var e2: Vector2 = Game.clamp_arena(Vector2(end.x, end.z))
			end.x = e2.x
			end.z = e2.y
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
	var dmg := _power() * ULTRIX_LUNGE_MULT * _ult_mult
	var lunge_dir: Vector2 = Vector2(_ult_to.x - _ult_from.x, _ult_to.z - _ult_from.z).normalized()
	for i in Game.enemies.query(me, 1.3):
		if _ult_hit.has(i):
			continue
		_ult_hit[i] = true
		Game.enemies.damage(i, dmg, lunge_dir, 10.0)
	_lunge = 1.0
	if t >= 1.0:
		Game.fx.ring(position, 2.0, Color(1.0, 0.15, 0.1), 0.2)
		# Scorched Path: the lunge leaves burning ground.
		if has_mod("sol_u_scorch"):
			Game.fx.fire_line(_ult_from, _ult_to, 1.0, 4.0, _power() * 0.8)
		# Twice Blind: lunge back the way she came.
		if has_mod("sol_u_twice") and not _ult_returning:
			_ult_returning = true
			_ult_t = 0.0
			_ult_hit = {}
			_ult_from = position
			_ult_to = _ult_start
			facing = atan2(_ult_to.x - _ult_from.x, _ult_to.z - _ult_from.z)
			Game.fx.thrust(position, facing, _ult_from.distance_to(_ult_to), Color(1.0, 0.15, 0.1))
			return
		_ult_phase = 0
		dashing = false
		invulnerable = false


## Cenhelm R: blows the horn.
func _the_horn() -> bool:
	var tick := (base_damage * damage_mult + max_hp * 0.035) * HORN_TICK_MULT
	var me := _my_xz()
	var long := has_mod("cen_u_long")
	Game.enemies.horn(me, HORN_RADIUS, 10.0 if long else HORN_TIME, tick, HORN_PUSH, 0.65 if long else 0.5)
	# Last Man: everything is stunned before the slow takes over.
	if has_mod("cen_u_stun"):
		for i in Game.enemies.query(me, HORN_RADIUS):
			Game.enemies.stun(i, 1.5)
	# The Warhorn: heals every ally.
	if has_mod("cen_u_heal"):
		for h in Game.party.heroes:
			h.heal(h.max_hp * 0.15)
	# Freca: the next 10 punches hit twice as hard.
	if has_mod("cen_u_freca"):
		_freca = 10
	# Back to Back (bond): everything in range turns on Solenne, and her
	# counters come twice as often for a while.
	var sol = Game.party.hero("Solenne")
	if Game.party.bonds.has("bond_back") and sol != null and not sol.downed:
		Game.enemies.taunt_in_radius(me, HORN_RADIUS, Game.party.heroes.find(sol), 6.0)
		sol._counter_boost_t = 6.0
		Game.fx.ring(sol.position, 2.5, sol.accent, 0.4)
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
	var cost := 0.1 if has_mod("khe_u_light") else SKY_COST
	hp = maxf(1.0, hp - max_hp * cost)
	_flash = 0.12
	for h in Game.party.heroes:
		if h == self:
			continue
		h.cooldown["r"] = 0.0
		if has_mod("khe_u_open"):
			h.cooldown["q"] = 0.0
			h.cooldown["e"] = 0.0
		if h.downed:
			continue
		Game.fx.ring(h.position, 1.4, accent, 0.4)
		if has_mod("khe_u_grove"):
			Game.party.place_grove(h.position, 4.0, GROVE_TIME, GROVE_HEAL * heal_mult)
		if has_mod("khe_u_shared"):
			h.damage_buff_t = 8.0
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
	var strikes := 2 if has_mod("sol_counter_twice") else 1
	for s in strikes:
		for k in mini(line.size(), COUNTER_MAX_TARGETS):
			Game.enemies.damage(line[k][1], dmg, dir, 8.0)
	stats["counter"] += 1
	# Penance (bond): each counter heals the lowest-health ally a little.
	if Game.party.bonds.has("bond_penance"):
		var low = Game.party.lowest_health_ally(null, 1.0)
		if low != null:
			low.heal(low.max_hp * 0.01)
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
	if kind == "solenne" and not downed and randf() < counter_chance():
		_counter(attacker)


func counter_chance() -> float:
	var c := 0.45 if has_mod("sol_counter_chance") else COUNTER_CHANCE
	if _counter_boost_t > 0.0:
		c *= 2.0
	return minf(c, 1.0)


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
# Placeholder models from KayKit Adventurers (CC0, Kay Lousberg) until the
# real heroes arrive. If a model is missing, the grey-box shapes below are
# used instead.

const KAYKIT := "res://assets/kaykit/"
const MODELS := {
	"solenne": {"file": "characters/Knight.glb", "scale": 0.8,
		"hide": ["Knight_Helmet", "Knight_HelmetVisor"], # no helmet: she shows her face
		"right": "weapons/sword_1handed.gltf"},
	"cenhelm": {"file": "characters/Barbarian.glb", "scale": 0.95, "hide": [], "right": ""}, # bare hands
	"kheiron": {"file": "characters/Mage.glb", "scale": 0.78, "hide": [], "right": "weapons/staff.gltf"},
}
const ANIM_FILES := ["animations/Rig_Medium_General.glb", "animations/Rig_Medium_MovementBasic.glb"]
const LOOPING := ["Idle_A", "Idle_B", "Running_A", "Running_B", "Walking_A", "Walking_B", "Walking_C", "Death_A_Pose"]

static var _anim_lib: AnimationLibrary


## Every animation from the shared Rig_Medium files, in one library that any
## KayKit character can play (they all share the same skeleton).
static func _animations() -> AnimationLibrary:
	if _anim_lib != null:
		return _anim_lib
	_anim_lib = AnimationLibrary.new()
	for f in ANIM_FILES:
		var src = Game.model(KAYKIT + f)
		if src == null:
			continue
		var ap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null:
			for n in ap.get_animation_list():
				if not _anim_lib.has_animation(n):
					var a: Animation = ap.get_animation(n).duplicate()
					if n in LOOPING:
						a.loop_mode = Animation.LOOP_LINEAR
					_anim_lib.add_animation(n, a)
		src.free()
	return _anim_lib


## A hero's placeholder model, dressed and with every Rig_Medium animation
## in an AnimationPlayer named "Anim". Null if the files are missing.
## Also used by the campfire screen.
static func create_model(hero_kind: String) -> Node3D:
	var m: Dictionary = MODELS.get(hero_kind, {})
	if m.is_empty():
		return null
	var model := Game.model(KAYKIT + str(m["file"]))
	if model == null:
		return null
	model.scale = Vector3.ONE * float(m["scale"])
	for n in m["hide"]:
		var part := model.find_child(n, true, false) as Node3D
		if part != null:
			part.visible = false
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel != null and str(m["right"]) != "":
		var weapon := Game.model(KAYKIT + str(m["right"]))
		if weapon != null:
			var hand := BoneAttachment3D.new()
			hand.bone_name = "handslot.r"
			skel.add_child(hand)
			hand.add_child(weapon)
	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.add_animation_library("", _animations())
	return model


func _build_model() -> bool:
	_model = create_model(kind)
	if _model == null:
		return false
	_body.add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	_anim = _model.get_node("Anim")
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skel = _model.find_child("Skeleton3D", true, false)
	seat_raise = preload("res://scripts/camp.gd").seat_raise(_model.scale.y)
	_update_anim()
	return true


## Bends the thighs forward and the shins down: a seated pose made from the
## standing rig (the free pack has no sitting animation). `amount` 1 = seated,
## 0 = standing, so getting up is a blend between the two.
static func fold_legs(skel: Skeleton3D, amount: float) -> void:
	if skel == null:
		return
	for side in ["l", "r"]:
		var up := skel.find_bone("upperleg." + side)
		var low := skel.find_bone("lowerleg." + side)
		if up < 0 or low < 0:
			continue
		var splay := 0.12 if side == "l" else -0.12
		var up_bend := Quaternion(Vector3.RIGHT, -1.5) * Quaternion(Vector3.FORWARD, splay)
		var low_bend := Quaternion(Vector3.RIGHT, 1.45)
		skel.set_bone_pose_rotation(up, skel.get_bone_rest(up).basis.get_rotation_quaternion() * Quaternion.IDENTITY.slerp(up_bend, amount))
		skel.set_bone_pose_rotation(low, skel.get_bone_rest(low).basis.get_rotation_quaternion() * Quaternion.IDENTITY.slerp(low_bend, amount))


## Everything needed to put a fresh copy of this hero exactly where this one
## is, mid-step (used when a new night starts without a cut).
func snapshot() -> Dictionary:
	var d := {"position": position, "rotation": rotation.y, "facing": facing, "sit": sit,
		"moving": moving, "move_dir": move_dir, "anim": "", "anim_pos": 0.0}
	if _anim != null:
		d["anim"] = _anim.current_animation
		d["anim_pos"] = _anim.current_animation_position if _anim.current_animation != "" else 0.0
	return d


func restore(d: Dictionary) -> void:
	position = d["position"]
	rotation.y = d["rotation"]
	facing = d["facing"]
	sit = d["sit"]
	moving = d["moving"]
	move_dir = d["move_dir"]
	if _anim != null and d["anim"] != "" and _anim.has_animation(d["anim"]):
		_anim_state = d["anim"]
		_anim.play(d["anim"])
		_anim.seek(d["anim_pos"], true)


## Picks the animation for what the hero is doing right now.
func _update_anim() -> void:
	var want := "Idle_A"
	var speed_scale := 1.0
	if sit > 0.0:
		pass # seated (or getting up): breathe
	elif downed:
		want = "Death_A"
	elif dashing:
		want = "Running_A"
		speed_scale = 1.6
	elif moving:
		want = "Running_A"
		speed_scale = 1.15
	if want != _anim_state and _anim.has_animation(want):
		_anim_state = want
		_anim.play(want, 0.12)
	_anim.speed_scale = speed_scale


## Hit flash and the dimmed look when down, drawn as an overlay on the
## model's own textures. 0 normal, 1 down, 2 flash.
func _set_tint(state: int) -> void:
	if state == _tint:
		return
	_tint = state
	var overlay: Material = null
	if state > 0:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		o.albedo_color = Color(1.0, 1.0, 1.0, 0.75) if state == 2 else Color(0.05, 0.05, 0.1, 0.5)
		overlay = o
	for mi in _meshes:
		mi.material_overlay = overlay


func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	_mat = Game.material(color)
	if _build_model():
		_revive_ring = _flat_ring(0.85, 1.0, Color(0.5, 1.0, 0.5, 0.8))
		_revive_ring.visible = false
		return
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


# --- Health ring -------------------------------------------------------------
# A ring on the ground under each hero that empties clockwise as they lose
# health: green, then amber, then red. The leader's has a gold rim, and
# flashes red when they're low.

const HP_RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float fill = 1.0;
uniform vec4 hp_color : source_color = vec4(0.35, 0.9, 0.4, 1.0);
uniform float leader = 0.0;
uniform float flash = 0.0;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float aa = max(fwidth(r), 0.002);
	float t = fract(atan(p.x, -p.y) / 6.2831853);
	float band = smoothstep(0.33 - aa, 0.33, r) * (1.0 - smoothstep(0.42, 0.42 + aa, r));
	float filled = step(t, fill);
	vec3 col = mix(vec3(0.05), hp_color.rgb, filled);
	float alpha = band * mix(0.35, 0.95, filled);
	float rim = leader * smoothstep(0.435 - aa, 0.435, r) * (1.0 - smoothstep(0.48, 0.48 + aa, r));
	col = mix(col, vec3(1.0, 0.8, 0.3), rim);
	alpha = max(alpha, rim * 0.95);
	col = mix(col, vec3(1.0, 0.12, 0.06), flash * max(band, rim));
	ALBEDO = col;
	ALPHA = alpha;
}
"""
const HP_LOW := 0.3 # below this the ring turns red (and the leader's flashes)

static var _hp_shader: Shader


func _build_hp_ring() -> void:
	if _hp_shader == null:
		_hp_shader = Shader.new()
		_hp_shader.code = HP_RING_SHADER
	_hp_mat = ShaderMaterial.new()
	_hp_mat.shader = _hp_shader
	var quad := PlaneMesh.new()
	var size := 2.3 if kind == "cenhelm" else 2.0
	quad.size = Vector2(size, size)
	_hp_ring = MeshInstance3D.new()
	_hp_ring.mesh = quad
	_hp_ring.material_override = _hp_mat
	_hp_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_ring.top_level = true # stays upright: it shouldn't spin as the hero turns
	add_child(_hp_ring)


func _update_hp_ring(delta: float) -> void:
	_hp_ring.visible = not downed and Game.main.is_night()
	if not _hp_ring.visible:
		return
	_hp_ring.global_position = Vector3(global_position.x, 0.06, global_position.z)
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	_hp_shown = move_toward(_hp_shown, frac, delta * 1.5) # drains smoothly, never lags far
	if absf(_hp_shown - frac) > 0.25:
		_hp_shown = frac + 0.25 * signf(_hp_shown - frac)
	var col := Color(0.35, 0.9, 0.4)
	if frac < 0.6:
		col = Color(1.0, 0.72, 0.2).lerp(Color(0.35, 0.9, 0.4), (frac - HP_LOW) / (0.6 - HP_LOW)) if frac >= HP_LOW else Color(0.95, 0.2, 0.12)
	_hp_mat.set_shader_parameter("fill", _hp_shown)
	_hp_mat.set_shader_parameter("hp_color", col)
	_hp_mat.set_shader_parameter("leader", 1.0 if is_leader else 0.0)
	var flash := 0.0
	if is_leader and frac < HP_LOW:
		flash = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	_hp_mat.set_shader_parameter("flash", flash)
