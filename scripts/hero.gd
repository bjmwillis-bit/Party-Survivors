extends Node3D
## One party member: stats, health, moving and the look. What they actually
## do in a fight lives in their kit (scripts/kits/<hero>.gd): a basic attack
## that fires on its own, a skill (Q) and an ultimate (E).
##
## The leader's Q and E are cast by the player. Followers cast their skill
## the moment it would do something; only the leader can use an ultimate.
## Numbers and words for every hero are in hero_data.gd.

const HeroData := preload("res://scripts/hero_data.gd")

const ULT_START_CHARGE := 0.5 # ultimates start each night half charged
const ATTACK_BUFFER := 0.25 # hold-to-attack: how early a press still counts
const HEALING_ON_HEALER := 0.5 # the healer heals himself at half strength

var kind := ""
var hero_name := ""
var color := Color(0.75, 0.75, 0.75)
var accent := Color.WHITE
var data: Dictionary = {}
var kit # this hero's kit (scripts/kits/)
var max_hp := 100.0
var hp := 100.0
var downed := false
var is_leader := false
var revive_progress := 0.0

# --- Numbers the cards change ------------------------------------------------
var base_damage := 10.0
var attack_interval := 1.0
var damage_mult := 1.0 # all of this hero's damage
var rate_mult := 1.0 # attack speed
var area_mult := 1.0
var skill_mult := 1.0 # skill (Q) damage
var ult_mult := 1.0 # ultimate (E) damage
var heal_mult := 1.0
var extra_instances := 0 # +1 swipe / axe / bolt...
var pierce_bonus := 0
var cd_mult := {"q": 1.0, "e": 1.0}
## Ultimate upgrade cards in play (card id -> true).
var mods := {}
var ult_cards := 0 # ultimate cards taken for this hero (bonds need one)

# --- Short-lived boosts, set by kits -----------------------------------------
var buff_rate := 0.0 # extra attack speed (Halvar's ult, Rhian's stacks)
var damage_buff_t := 0.0 # Shared Sky: +20% damage while > 0
var speed_mult := 1.0 # how fast this hero runs (Levana's vanish)
var untargetable := false # the horde ignores them (in the air, invisible)
var ghost := false # drawn as a shadow (Levana's vanish)
var lift_override := -1.0 # when >= 0, how high the body floats (Cael's Skyfall)

# --- State -------------------------------------------------------------------
var facing := 0.0 # where the hero wants to face (radians)
var face_lock := 0.0 # while > 0, the hero keeps facing their attack
var move_dir := Vector3.ZERO
var moving := false
var aim_dir := Vector2.ZERO # where the player aims (used while leading)
var returning := false # a follower running back inside the leash
var dashing := false # moving under a skill's control (a dash, a leap)
var invulnerable := false
var cooldown := {"q": 0.0, "e": 0.0} # seconds left
## How often each ability went off this night (for tuning and tests).
var stats := {"q": 0, "e": 0, "counter": 0}

var _attack_timer := 0.4
var _attack_buffer := 0.0
var _flash := 0.0
var _hurt_flash_cd := 0.0
var _bob := 0.0
var _step_timer := 0.0
var _lunge := 0.0
var _twist := 0.0
var _lift := 0.0 # how high off the ground (leaps)

# A move under a skill's control: from, to, over seconds, with a hop.
var _mv_from := Vector3.ZERO
var _mv_to := Vector3.ZERO
var _mv_t := 0.0
var _mv_time := 0.0
var _mv_hop := 0.0
var _mv_step := Callable()
var _mv_end := Callable()

## For the cursor widget: when this hero last swung, and last got hit.
var attacked_at_ms := -100000
var hit_at_ms := -100000
## Ranged kiting: where this follower is heading between shots.
var kite_spot := Vector3.ZERO
var kite_timer := 0.0
## Melee follower AI (see party.gd _melee).
const HURT_WINDOW := 1.5 # seconds that health loss is averaged over
## How fast this hero is losing health, as a fraction of max health per
## second, averaged over the last second and a half. Healing counts against it.
var hurt_rate := 0.0
var breaking := 0.0 # seconds left of breaking away from a crowd
var ai_aim := Vector2.ZERO # when set, a follower's next skill goes this way
var melee_target := -1
var melee_side := Vector2.ZERO # which side of its target a follower stands on
## Sitting by the fire: 0 standing, 1 seated on a log (blends while getting up).
var sit := 0.0
var seat_raise := 0.0 # how far the model lifts to sit on the log

var _body: Node3D
var _mat: StandardMaterial3D
var _hp_ring: MeshInstance3D
var _hp_mat: ShaderMaterial
var _hp_shown := 1.0
var _revive_ring: MeshInstance3D
var _taunt_ring: MeshInstance3D
var taunt_time := 0.0 # shows the taunt ring while > 0
var _model: Node3D
var _anim: AnimationPlayer
var _anim_state := ""
var _meshes: Array[MeshInstance3D] = []
var _skel: Skeleton3D
var _xray: StandardMaterial3D
var _tint := -1


func setup(hero_kind: String) -> void:
	kind = hero_kind
	data = HeroData.get_hero(kind)
	hero_name = data["name"]
	accent = data["accent"]
	max_hp = data["hp"]
	hp = max_hp
	base_damage = data["damage"]
	attack_interval = data["interval"]
	cooldown["e"] = data["ult"]["cd"] * ULT_START_CHARGE
	var script = load("res://scripts/kits/%s.gd" % kind)
	kit = script.new()
	kit.setup(self)
	_build_visual()
	_taunt_ring = _flat_ring(0.95, 1.1, Color(accent.r, accent.g, accent.b, 0.7))
	_taunt_ring.visible = false
	_build_hp_ring()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_hurt_flash_cd = maxf(0.0, _hurt_flash_cd - delta)
	face_lock = maxf(0.0, face_lock - delta)
	hurt_rate *= exp(-delta / HURT_WINDOW)
	breaking = maxf(0.0, breaking - delta)
	taunt_time = maxf(0.0, taunt_time - delta)
	damage_buff_t = maxf(0.0, damage_buff_t - delta)
	for slot in cooldown:
		cooldown[slot] = maxf(0.0, cooldown[slot] - delta)
	if _model != null:
		_occluded = _check_occluded()
		_set_tint(2 if _flash > 0.0 else (1 if downed else (3 if ghost else 0)))
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
	_taunt_ring.visible = taunt_time > 0.0 and not downed

	if downed:
		dashing = false
		var frac: float = revive_progress / Game.party.revive_time
		_revive_ring.scale = Vector3.ONE * (0.4 + frac * 1.2)
		if _model == null: # the model plays its death animation instead
			_body.rotation.x = lerpf(_body.rotation.x, -1.45, 1.0 - exp(-12.0 * delta))
			_body.position.y = 0.2
		return
	_body.rotation.x = lerpf(_body.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))

	if Game.main.is_night():
		kit.run_timers(delta)
		kit.tick(delta)
	_tick_motion(delta)

	# Snap to face the new direction almost instantly.
	rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-30.0 * delta))

	# Stepping: a quick bob and sway, with a puff of dust on each footfall.
	if moving:
		_bob += delta * 14.0
		if _model == null:
			_body.position.y = absf(sin(_bob)) * 0.12
			_body.rotation.z = sin(_bob) * 0.06
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = PI / 14.0
			Game.fx.dust(position)
	else:
		_bob = 0.0
		if _model == null:
			_body.position.y = move_toward(_body.position.y, 0.0, delta * 2.0)
		_body.rotation.z = 0.0

	# A short lunge forward when attacking, a twist on punches, a hop on leaps.
	_lunge = maxf(0.0, _lunge - delta * 6.0)
	_body.position.z = _lunge * 0.35
	if _model != null:
		_body.position.y = _lift
	_twist = move_toward(_twist, 0.0, delta * 3.0)
	_body.rotation.y = _twist

	if Game.main.is_night():
		_tick_attack(delta)
		if not is_leader:
			_ai_cast()


# --- What kits use -------------------------------------------------------------

## Basic-attack damage with every bonus applied, times `mult`.
func power(mult := 1.0) -> float:
	var p: float = base_damage * damage_mult * Game.party.might * mult
	if is_leader:
		p *= Game.party.lead_bonus
	if damage_buff_t > 0.0:
		p *= 1.2
	p *= 1.0 + Game.party.anvil_bonus(position)
	return p


func skill_power(mult := 1.0) -> float:
	return power(mult) * skill_mult


func ult_power(mult := 1.0) -> float:
	return power(mult) * ult_mult


func area() -> float:
	return area_mult * Game.party.reach


## How many swipes, axes, bolts... per basic attack.
func instances() -> int:
	return int(data.get("instances", 1)) + extra_instances + Game.party.echo


func has_mod(id: String) -> bool:
	return bool(mods.get(id, false))


## Faces a direction and keeps facing it for a moment (an attack).
func face(dir: Vector2, lock := 0.15) -> void:
	if dir == Vector2.ZERO:
		return
	facing = atan2(dir.x, dir.y)
	face_lock = lock


func lunge(amount := 1.0) -> void:
	_lunge = maxf(_lunge, amount)


func twist(amount: float) -> void:
	_twist = amount


func flash(seconds := 0.12) -> void:
	_flash = seconds


## Moves the hero under a skill's control: to `to` over `seconds`, with a hop
## `hop` metres high. `on_step` runs every frame of the move, `on_end` when
## it lands. No basic attacks or walking meanwhile.
func start_motion(to: Vector3, seconds: float, hop := 0.0, on_step := Callable(), on_end := Callable()) -> void:
	var t2: Vector2 = Game.clamp_arena(Vector2(to.x, to.z))
	_mv_from = position
	_mv_to = Vector3(t2.x, 0.0, t2.y)
	_mv_t = 0.0
	_mv_time = maxf(0.01, seconds)
	_mv_hop = hop
	_mv_step = on_step
	_mv_end = on_end
	dashing = true
	var d := Vector2(_mv_to.x - position.x, _mv_to.z - position.z)
	if d.length() > 0.05:
		face(d.normalized(), seconds + 0.1)


func _tick_motion(delta: float) -> void:
	if lift_override >= 0.0:
		_lift = lerpf(_lift, lift_override, 1.0 - exp(-10.0 * delta))
		return
	if not dashing or _mv_time <= 0.0:
		_lift = move_toward(_lift, 0.0, delta * 6.0)
		return
	_mv_t += delta
	var t := minf(1.0, _mv_t / _mv_time)
	position = _mv_from.lerp(_mv_to, t)
	_lift = sin(t * PI) * _mv_hop
	if _mv_step.is_valid():
		_mv_step.call()
	if t >= 1.0:
		dashing = false
		_mv_time = 0.0
		_lift = 0.0
		var end := _mv_end
		_mv_step = Callable()
		_mv_end = Callable()
		if end.is_valid():
			end.call()


## Stands still under a skill's control for `seconds` (channels, wind-ups).
func hold_still(seconds: float, on_end := Callable()) -> void:
	start_motion(position, seconds, 0.0, Callable(), on_end)


func cancel_motion() -> void:
	dashing = false
	_mv_time = 0.0
	_mv_step = Callable()
	_mv_end = Callable()


# --- Basic attacks -------------------------------------------------------------

func attack_rate() -> float:
	return rate_mult * Game.party.haste * (1.0 + buff_rate) * (1.0 + Game.party.anvil_bonus(position))


func _tick_attack(delta: float) -> void:
	if dashing or kit.busy():
		return
	_attack_timer -= delta * attack_rate()
	# Hold-to-attack (a setting): the leader only swings while the button is
	# held, or if it was pressed just before the swing was ready.
	var manual: bool = is_leader and bool(Game.settings.get("hold_to_attack", false)) and not Game.main.autopilot
	if manual:
		_attack_buffer = maxf(0.0, _attack_buffer - delta)
		if Input.is_action_just_pressed("attack"):
			_attack_buffer = ATTACK_BUFFER
	if _attack_timer > 0.0:
		return
	if manual and not Input.is_action_pressed("attack") and _attack_buffer <= 0.0:
		_attack_timer = 0.0
		return
	var attacked: bool = kit.attack()
	# No target in range: check again shortly.
	_attack_timer = attack_interval if attacked else 0.1
	if attacked:
		attacked_at_ms = Time.get_ticks_msec()
		_attack_buffer = 0.0


## How charged the next basic attack is, 0 to 1 (for the cursor's timer ring).
func attack_charge() -> float:
	return clampf(1.0 - _attack_timer / maxf(0.05, attack_interval), 0.0, 1.0)


## True when the next basic attack is (nearly) ready to fire.
func attack_ready() -> bool:
	return _attack_timer <= 0.12 and not kit.busy()


func is_healer() -> bool:
	return bool(data.get("healer", false))


## Ranged heroes kite as followers: shoot when ready, reposition between shots.
func is_ranged() -> bool:
	return bool(data.get("ranged", false))


func shot_range() -> float:
	return float(data.get("range", 6.0))


## How close a follower gets to its target before stopping to fight.
func engage_range() -> float:
	return float(data.get("engage", 2.0))


## How close is too close (Cael's sweeps miss the near 3 m).
func min_reach() -> float:
	return float(data.get("min_reach", 0.0)) * area()


## A follower breaks away once it's losing health faster than this
## (fraction of max health per second).
func nerve() -> float:
	return float(data.get("nerve", 0.06))


## Followers fire their skill as they break away, if it helps them get out.
## `away` points the way out.
func escape_skill(away: Vector2) -> void:
	var how: String = data.get("escape", "")
	if how == "" or cooldown["q"] > 0.0 or dashing:
		return
	if how == "toward":
		ai_aim = away
	elif how == "back":
		ai_aim = -away
	cast("q")
	ai_aim = Vector2.ZERO


# --- Skill (Q) and ultimate (E) -----------------------------------------------

func skill_name(slot: String) -> String:
	return data["skill" if slot == "q" else "ult"]["name"]


func skill_cooldown(slot: String) -> float:
	return float(data["skill" if slot == "q" else "ult"]["cd"]) * cd_mult[slot] * Game.party.focus


## Try to use the skill ("q") or ultimate ("e"). Returns true if it went off.
func cast(slot: String) -> bool:
	if downed or not Game.main.is_night():
		return false
	if slot == "e" and not is_leader:
		return false # only the leader can use an ultimate
	if slot == "e" and cooldown["e"] > 0.0 and kit.ult_pressed_again():
		return true
	if dashing or cooldown[slot] > 0.0:
		return false
	var done: bool = kit.skill() if slot == "q" else kit.ult()
	if done:
		cooldown[slot] = skill_cooldown(slot)
		stats[slot] += 1
	return done


## Followers use their skill the moment it would do something.
func _ai_cast() -> void:
	if cooldown["q"] <= 0.0 and not dashing and kit.skill_worth():
		cast("q")


# --- Health --------------------------------------------------------------------

## A blow from an enemy.
func take_hit(amount: float, attacker: int) -> void:
	if downed or invulnerable or untargetable:
		return
	take_damage(amount)
	if not downed:
		kit.on_struck(attacker)


func take_damage(amount: float) -> void:
	if downed or invulnerable:
		return
	hp -= amount
	hurt_rate += amount / max_hp / HURT_WINDOW
	hit_at_ms = Time.get_ticks_msec()
	if _hurt_flash_cd <= 0.0:
		_flash = 0.08
		_hurt_flash_cd = 0.3
	if hp <= 0.0:
		hp = 0.0
		downed = true
		revive_progress = 0.0
		moving = false
		taunt_time = 0.0
		untargetable = false
		ghost = false
		lift_override = -1.0
		buff_rate = 0.0
		speed_mult = 1.0
		cancel_motion()
		invulnerable = false
		kit.on_downed()
		Game.party.on_hero_downed(self)


func heal(amount: float) -> void:
	if downed:
		return
	if is_healer():
		amount *= HEALING_ON_HEALER
	var before := hp
	hp = minf(max_hp, hp + amount)
	hurt_rate = maxf(0.0, hurt_rate - (hp - before) / max_hp / HURT_WINDOW)


func revive() -> void:
	downed = false
	revive_progress = 0.0
	hp = max_hp * 0.35


# --- Look --------------------------------------------------------------------
# Placeholder models from KayKit Adventurers (CC0, Kay Lousberg) until the
# real heroes arrive. If a model is missing, the grey-box shapes below are
# used instead.

const KAYKIT := "res://assets/kaykit/"
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
	var m: Dictionary = HeroData.get_hero(hero_kind).get("model", {})
	if m.is_empty():
		return null
	var model := Game.model(KAYKIT + str(m["file"]))
	if model == null:
		return null
	model.scale = Vector3.ONE * float(m["scale"])
	for n in m.get("hide", []):
		var part := model.find_child(n, true, false) as Node3D
		if part != null:
			part.visible = false
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	for side in [["right", "handslot.r"], ["left", "handslot.l"]]:
		var file := str(m.get(side[0], ""))
		if skel == null or file == "":
			continue
		var weapon := Game.model(KAYKIT + file)
		if weapon != null:
			var hand := BoneAttachment3D.new()
			hand.bone_name = side[1]
			skel.add_child(hand)
			hand.add_child(weapon)
	# Heroes who share a placeholder body get a tint so they read apart.
	if m.has("tint"):
		var tint: Color = m["tint"]
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_i := mi as MeshInstance3D
			for k in mesh_i.get_surface_override_material_count():
				var base := mesh_i.get_active_material(k)
				if base is StandardMaterial3D:
					var dup: StandardMaterial3D = base.duplicate()
					dup.albedo_color = dup.albedo_color * tint
					mesh_i.set_surface_override_material(k, dup)
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
	_xray = _xray_material()
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
	var key := state * 2 + (1 if _occluded else 0)
	if key == _tint:
		return
	_tint = key
	var overlay: Material = _xray if _occluded else null
	if state > 0:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		o.albedo_color = Color(1.0, 1.0, 1.0, 0.75) if state == 2 else (Color(0.08, 0.05, 0.15, 0.75) if state == 3 else Color(0.05, 0.05, 0.1, 0.5))
		if _occluded:
			o.next_pass = _xray
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
	# Grey-box fallback: a capsule, a head and a band across the eyes in the
	# hero's colour (shows which way they face).
	var accent_mat := Game.material(accent, 0.5)
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.36
	torso_mesh.height = 1.5
	torso_mesh.radial_segments = 8
	torso_mesh.rings = 2
	_part(Game.flat_mesh(torso_mesh), _mat, Vector3(0.0, 0.75, 0.0))
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head_mesh.radial_segments = 6
	head_mesh.rings = 3
	_part(Game.flat_mesh(head_mesh), _mat, Vector3(0.0, 1.62, 0.0))
	var eyes := BoxMesh.new()
	eyes.size = Vector3(0.26, 0.07, 0.08)
	_part(eyes, accent_mat, Vector3(0.0, 1.64, 0.19))

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
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;
uniform float fill = 1.0;
uniform vec4 hp_color : source_color = vec4(0.35, 0.9, 0.4, 1.0);
uniform float leader = 0.0;
uniform float flash = 0.0;
const float SPAN = 0.6; // the arc covers 60% of the circle, open behind the hero
const float INNER = 0.33;
const float OUTER = 0.42;
const float LINE = 0.022; // the black outline
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float aa = max(fwidth(r), 0.002);
	// Angle measured from the front (toward the camera), 0..1 around.
	float a = fract(atan(p.x, p.y) / 6.2831853 + 0.5);
	// Position along the arc: 0 at its left end, 1 at its right end.
	float along = (a - (0.5 - SPAN * 0.5)) / SPAN;
	float on_arc = step(0.0, along) * step(along, 1.0);
	float band = smoothstep(INNER - aa, INNER, r) * (1.0 - smoothstep(OUTER, OUTER + aa, r));
	float outline = smoothstep(INNER - LINE - aa, INNER - LINE, r) * (1.0 - smoothstep(OUTER + LINE, OUTER + LINE + aa, r));
	float ends = step(-LINE * 1.6, along) * step(along, 1.0 + LINE * 1.6);
	float filled = step(along, fill);
	vec3 rim = mix(vec3(0.0), vec3(1.0, 0.8, 0.3), leader);
	vec3 col = mix(vec3(0.08), hp_color.rgb, filled);
	col = mix(rim, col, band * on_arc);
	col = mix(col, vec3(1.0, 0.12, 0.06), flash * band * on_arc);
	float alpha = max(outline * ends * 0.9, band * on_arc * mix(0.55, 0.95, filled));
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
	_hp_mat.render_priority = 10 # drawn over the horde, so it never gets lost
	var quad := PlaneMesh.new()
	var size := (2.3 if kind == "cenhelm" else 2.0) * 0.6 # 40% smaller than before
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


# --- Seen through the crowd --------------------------------------------------
# When an enemy stands between the camera and a hero, the hero is drawn on
# top as a see-through silhouette in their colour, so they never get lost in
# the horde. The check is done here (not on the graphics card), so it works
# the same on every renderer.

var _occluded := false


func _xray_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 5
	m.albedo_color = Color(accent.r, accent.g, accent.b, 0.55).lerp(Color(1, 1, 1, 0.55), 0.15)
	return m


## Is an enemy between the camera and this hero's body?
func _check_occluded() -> bool:
	if downed or not Game.main.is_night():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var eye := cam.global_position
	var chest := global_position + Vector3(0.0, 0.9, 0.0)
	var ray := chest - eye
	var length := ray.length()
	ray /= length
	var E = Game.enemies
	for i in E.query(Vector2(chest.x, chest.z), 3.5):
		var s: float = E.SCALE[E.kind[i]]
		var c := Vector3(E.pos[i].x, 0.65 * s, E.pos[i].y)
		var t := (c - eye).dot(ray)
		if t <= 0.0 or t >= length - 0.3:
			continue # behind the hero, or level with them
		if (eye + ray * t).distance_to(c) < 0.5 * s:
			return true
	return false
