extends "res://scripts/kits/kit.gd"
## Cael. Basic: a fast double sweep (0.2 s apart). It reaches 6 m but only
##   the far 3 m hits.
## Q Claim: throws his spear at the thickest crowd within 8 m (×0.8 in 2 m),
##   then leaps to it, untouchable: ×1.5 in 4 m when he lands.
## E Skyfall: leaps into the air, untouchable. A faint blue target drifts
##   toward the cursor at 1 m/s; after 4 s (or pressing E again) he lands:
##   ×3 within 2 m, ×1.5 out to 6 m.

const REACH := 6.0
const INNER := 3.0
const HALF := deg_to_rad(45.0)
const SWEEP_GAP := 0.2
const CLAIM_RANGE := 8.0
const CLAIM_LOOK := 12.0 # how far he looks when judging a crowd
const CROWD := 3.0
const SKY_TIME := 4.0
const SKY_DRIFT := 1.0 # metres per second
const SKY_HEIGHT := 7.0
const SKY_BLUE := Color(0.35, 0.6, 1.0)

var _sky := 0.0 # seconds left in the air
var _marker: Node3D
var _marker_mat: StandardMaterial3D


func attack() -> bool:
	var reach := REACH * h.area()
	var dir := aim(reach)
	if dir == Vector2.ZERO or (h.is_leader and not leader_has_target(dir, reach, HALF)):
		return false
	for k in h.instances():
		after(SWEEP_GAP * k, func() -> void:
			var d := aim(reach)
			_sweep(d if d != Vector2.ZERO else dir, k))
	return true


func _sweep(dir: Vector2, k: int) -> void:
	var reach := REACH * h.area()
	var inner := INNER * h.area()
	var centre := dir.rotated(0.18 if k % 2 == 0 else -0.18)
	hit_arc(me(), centre, reach, HALF, h.power(), 5.0, inner)
	Game.fx.slash(h.position, atan2(centre.x, centre.y), reach, HALF, h.accent)
	h.face(dir)
	h.twist(0.4 if k % 2 == 0 else -0.4)


func skill() -> bool:
	var at := _crowd_spot()
	if at == Vector2.INF:
		return false
	var spear := make_prop("weapons/staff.gltf", 1.0, Color(0.6, 0.5, 0.4))
	spear.position = h.position + Vector3(0.0, 1.2, 0.0)
	var dir := (at - me()).normalized()
	spear.rotation = Vector3(PI * 0.5, atan2(dir.x, dir.y), 0.0)
	h.face(dir, 0.5)
	var tw := spear.create_tween()
	tw.tween_property(spear, "position", at3(at, 0.4), 0.22)
	tw.tween_callback(func() -> void:
		hit_circle(at, 2.0 * h.area(), h.skill_power(0.8), 4.0)
		Game.fx.ring(at3(at), 2.0 * h.area(), h.accent, 0.2)
		if h.downed:
			spear.queue_free()
			return
		h.untargetable = true
		h.start_motion(at3(at), 0.35, 1.8, Callable(), func() -> void:
			h.untargetable = false
			spear.queue_free()
			var r := 4.0 * h.area()
			hit_circle(me(), r, h.skill_power(1.5), 9.0)
			Game.fx.ring(h.position, r, h.accent, 0.25)
			Game.fx.ring(h.position, r * 0.5, Color.WHITE, 0.15)
			shake(0.3, 0.05)))
	return true


## The enemy within 8 m with the most others around it (looking 12 m out).
func _crowd_spot() -> Vector2:
	var E = Game.enemies
	var best := Vector2.INF
	var best_n := 0
	for i in E.query(me(), CLAIM_LOOK):
		var p: Vector2 = E.pos[i]
		if me().distance_to(p) > CLAIM_RANGE:
			continue
		var n: int = E.query(p, CROWD).size()
		if n > best_n:
			best_n = n
			best = p
	return best


func skill_worth() -> bool:
	return Game.enemies.query(me(), CLAIM_RANGE).size() >= 5


func ult() -> bool:
	_sky = 6.0 if h.has_mod("cae_u_long") else SKY_TIME
	h.untargetable = true
	h.dashing = true
	h.lift_override = SKY_HEIGHT
	if not is_instance_valid(_marker):
		var d := make_disc(1.0, Color(SKY_BLUE.r, SKY_BLUE.g, SKY_BLUE.b, 0.35))
		_marker = d[0]
		_marker_mat = d[1]
	_marker.visible = true
	_marker.position = at3(me(), 0.06)
	shake(0.2)
	return true


func ult_pressed_again() -> bool:
	if _sky <= 0.0:
		return false
	_land()
	return true


func busy() -> bool:
	return _sky > 0.0


func tick(delta: float) -> void:
	if _sky <= 0.0:
		return
	_sky -= delta
	# The target drifts toward where the leader aims (he stays over it).
	var drift := SKY_DRIFT * (3.0 if h.has_mod("cae_u_hawk") else 1.0)
	var goal := Vector2(Game.party.aim_point.x, Game.party.aim_point.z)
	var p := me()
	var to := goal - p
	if to.length() > 0.05:
		p += to.normalized() * minf(to.length(), drift * delta)
	p = Game.clamp_arena(p)
	h.position = at3(p)
	_marker.position = at3(p, 0.06)
	_marker_mat.albedo_color.a = 0.25 + 0.15 * sin(Time.get_ticks_msec() * 0.01)
	if _sky <= 0.0 or not h.is_leader:
		_land()


func _land() -> void:
	_sky = 0.0
	h.lift_override = -1.0
	h.dashing = false
	h.untargetable = false
	if is_instance_valid(_marker):
		_marker.visible = false
	var inner := 2.0 * h.area()
	var outer := (8.0 if h.has_mod("cae_u_long") else 6.0) * h.area()
	var stun := h.has_mod("cae_u_comet")
	for i in Game.enemies.query(me(), outer):
		var rel: Vector2 = Game.enemies.pos[i] - me()
		var mult := 3.0 if rel.length() <= inner else 1.5
		Game.enemies.damage(i, h.ult_power(mult), rel.normalized() if rel.length() > 0.05 else Vector2.UP, 10.0)
		if stun:
			Game.enemies.stun(i, 1.5)
	if h.has_mod("cae_u_claim"):
		h.cooldown["q"] = 0.0
	Game.fx.ring(h.position, outer, SKY_BLUE, 0.35)
	Game.fx.ring(h.position, inner, Color.WHITE, 0.25)
	shake(0.5, 0.08)


func on_downed() -> void:
	super.on_downed()
	_sky = 0.0
	if is_instance_valid(_marker):
		_marker.visible = false
