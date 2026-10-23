extends "res://scripts/kits/kit.gd"
## Bram. Basic: hammers nails at the nearest enemy; they pierce 2 and fly 6 m.
## Q Anvil: drops an anvil between the party: for 8 s, heroes within 6 m
##   attack 15% faster and deal 15% more damage.
## E Temper: a 4.5 s channel (it carries on if he's swapped out). He strikes
##   an anvil four times, in rings of 2, 4, 6 and 8 m (×1.5 each); enemies
##   caught are slowed 40% for the rest of the channel.

const NAIL_SPEED := 22.0
const PIERCE := 2
const ANVIL_RADIUS := 6.0
const ANVIL_TIME := 8.0
const ANVIL_BONUS := 0.15
const CHANNEL := 4.5
const STRIKES := [[1.5, 2.0], [2.5, 4.0], [3.5, 6.0], [4.5, 8.0]] # [time, radius]
const MOLTEN := Color(1.0, 0.45, 0.1)

var _prop: Node3D # the anvil he strikes during Temper


func attack() -> bool:
	var range_m := h.shot_range()
	var target: int = Game.enemies.nearest(me(), range_m)
	if target < 0:
		return false
	var to: Vector2 = (Game.enemies.pos[target] - me()).normalized()
	if h.is_leader and h.aim_dir != Vector2.ZERO:
		to = h.aim_dir
	var count := h.instances()
	for b in count:
		var spread := (b - (count - 1) * 0.5) * 0.14
		Game.fx.bolt(h.position + Vector3(0.0, 0.9, 0.0), to.rotated(spread), h.power(), PIERCE + h.pierce_bonus,
			Color(0.75, 0.8, 0.85), NAIL_SPEED, 0.55, range_m / NAIL_SPEED)
	h.face(to, 0.1)
	h.lunge(0.35)
	h.twist(0.25)
	return true


func skill() -> bool:
	# The middle of the living party.
	var sum := Vector3.ZERO
	var n := 0
	for a in Game.party.heroes:
		if not a.downed:
			sum += a.position
			n += 1
	var at := sum / maxf(1.0, n)
	var bonus := ANVIL_BONUS * (2.0 if h.has_mod("bra_u_tempered") else 1.0)
	Game.party.place_anvil(at, ANVIL_RADIUS * h.area(), ANVIL_TIME, bonus)
	shake(0.15)
	return true


func skill_worth() -> bool:
	return Game.party.anvils.is_empty() and Game.enemies.query(leash_center(), 9.0).size() >= 3


func ult() -> bool:
	h.hold_still(CHANNEL)
	var front := h.position + Vector3(sin(h.facing), 0.0, cos(h.facing)) * 0.9
	if h.has_mod("bra_u_twin"):
		var bonus := ANVIL_BONUS * (2.0 if h.has_mod("bra_u_tempered") else 1.0)
		Game.party.place_anvil(h.position, ANVIL_RADIUS * h.area(), ANVIL_TIME, bonus)
	after(0.5, func() -> void:
		_prop = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.45, 0.45)
		_prop.mesh = box
		_prop.material_override = Game.material(Color(0.3, 0.3, 0.33))
		_prop.position = front + Vector3(0.0, 0.3, 0.0)
		Game.fx.add_child(_prop))
	var centre := me()
	for k in STRIKES.size():
		var s: Array = STRIKES[k]
		var last: bool = k == STRIKES.size() - 1
		after(s[0], func() -> void: _strike(centre, s[1] * h.area(), CHANNEL - s[0] + 0.5, last))
	after(CHANNEL + 0.1, func() -> void:
		if is_instance_valid(_prop):
			_prop.queue_free())
	return true


func _strike(centre: Vector2, r: float, slow_for: float, last: bool) -> void:
	var stun: bool = last and h.has_mod("bra_u_down")
	hit_circle(centre, r, h.ult_power(1.5), 5.0, func(i: int) -> void:
		Game.enemies.slow(i, 0.4, slow_for)
		if stun:
			Game.enemies.stun(i, 2.0))
	Game.fx.ring(at3(centre), r, MOLTEN, 0.4)
	Game.fx.ring(at3(centre), r * 0.7, Color(1.0, 0.75, 0.3), 0.3)
	if h.has_mod("bra_u_molten"):
		for k in 8:
			var a0 := TAU * k / 8.0
			var a1 := TAU * (k + 1) / 8.0
			Game.fx.fire_line(at3(centre + Vector2.from_angle(a0) * r), at3(centre + Vector2.from_angle(a1) * r), 0.6, 4.0, h.ult_power(0.5))
	h.lunge(1.0)
	h.twist(0.4)
	shake(0.2 + r * 0.03, 0.03)


func on_downed() -> void:
	super.on_downed()
	if is_instance_valid(_prop):
		_prop.queue_free()
