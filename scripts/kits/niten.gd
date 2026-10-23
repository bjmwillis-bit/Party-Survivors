extends "res://scripts/kits/kit.gd"
## Niten. Basic (slow, heavy): a 135° swing, from 45° on his left round to
##   90° on his right, then a straight stab.
## Q Twin Wind: two slices 0.6 s apart, each sending a 90° wave 8 m forward
##   (×1.5). He hops back 1 m with each.
## E Heaven Strike: after 0.5 s, lightning strikes the toughest enemy in
##   sight (bosses first): ×3 within 4 m.

const REACH := 3.2
const STAB := 4.0
const SWING_HALF := deg_to_rad(67.5)
const SWING_TURN := deg_to_rad(22.5) # the swing's centre sits right of straight ahead
const WAVE_LENGTH := 8.0
const WAVE_HALF := deg_to_rad(45.0)
const STRIKE_RADIUS := 4.0
const SIGHT := 18.0


func attack() -> bool:
	var reach := REACH * h.area()
	var dir := aim(STAB * h.area())
	if dir == Vector2.ZERO or (h.is_leader and not leader_has_target(dir, STAB * h.area(), SWING_HALF + SWING_TURN)):
		return false
	_combo(dir, 1.0)
	for k in range(1, h.instances()):
		after(0.5 * k, func() -> void:
			var d := aim(STAB * h.area())
			_combo(d if d != Vector2.ZERO else dir, -1.0 if k % 2 == 1 else 1.0))
	return true


## The swing, then the stab. `side` mirrors the swing for extra cuts.
func _combo(dir: Vector2, side: float) -> void:
	var reach := REACH * h.area()
	var centre := dir.rotated(SWING_TURN * side)
	hit_arc(me(), centre, reach, SWING_HALF, h.power(), 7.0)
	Game.fx.slash(h.position, atan2(centre.x, centre.y), reach, SWING_HALF, h.accent)
	h.face(dir, 0.4)
	h.twist(-0.5 * side)
	after(0.22, func() -> void:
		var length := STAB * h.area()
		hit_line(me(), me() + dir * length, 0.6, h.power(), 8.0)
		Game.fx.thrust(h.position, atan2(dir.x, dir.y), length, h.accent)
		h.lunge(1.0))


func skill() -> bool:
	var dir := aim(WAVE_LENGTH)
	if dir == Vector2.ZERO:
		dir = Vector2(sin(h.facing), cos(h.facing))
	_wave(dir)
	after(0.6, func() -> void: _wave(dir))
	return true


## A crescent that sweeps forward 8 m, hitting each enemy once.
func _wave(dir: Vector2) -> void:
	var origin := me()
	var hit := {}
	var length := WAVE_LENGTH * h.area()
	var dmg := h.skill_power(1.5)
	var steps := 5
	for s in steps:
		var r0 := length * float(s) / steps
		var r1 := length * float(s + 1) / steps
		after(0.06 * s, func() -> void:
			for i in Game.enemies.query(origin, r1):
				if hit.has(i):
					continue
				var rel: Vector2 = Game.enemies.pos[i] - origin
				if rel.length() < r0 - 0.5 or absf(dir.angle_to(rel)) > WAVE_HALF:
					continue
				hit[i] = true
				Game.enemies.damage(i, dmg, dir, 6.0)
			Game.fx.slash(at3(origin), atan2(dir.x, dir.y), r1, WAVE_HALF, h.accent.lerp(Color.WHITE, 0.3)))
	h.face(dir, 0.5)
	h.start_motion(h.position - at3(dir) * 1.0, 0.14, 0.35)
	shake(0.12)


func skill_worth() -> bool:
	return Game.enemies.query(me(), WAVE_LENGTH * 0.7).size() >= 3


func ult() -> bool:
	if _toughest(me(), SIGHT, []) < 0:
		return false
	h.hold_still(0.5, func() -> void: _strike_round(0))
	Game.fx.ring(h.position, 1.2, h.accent, 0.5)
	return true


func _strike_round(n: int) -> void:
	var t := _toughest(me(), SIGHT, [])
	if t < 0:
		return
	var hit: Array = [t]
	_strike(Game.enemies.pos[t], 3.0)
	if h.has_mod("nit_u_chain"):
		var from: Vector2 = Game.enemies.pos[t]
		for k in 2:
			var nxt := _toughest(from, 10.0, hit)
			if nxt < 0:
				break
			hit.append(nxt)
			var at: Vector2 = Game.enemies.pos[nxt]
			after(0.12 * (k + 1), func() -> void: _strike(at, 1.5))
			from = at
	if h.has_mod("nit_u_draw"):
		h.cooldown["q"] = 0.0
	if h.has_mod("nit_u_twice") and n == 0:
		after(0.45, func() -> void: _strike_round(1))


func _strike(at: Vector2, mult: float) -> void:
	var r := STRIKE_RADIUS * h.area()
	var stun := h.has_mod("nit_u_stun")
	hit_circle(at, r, h.ult_power(mult), 10.0, func(i: int) -> void:
		if stun:
			Game.enemies.stun(i, 1.5))
	# The bolt: a tall bright column, then rings.
	var bolt := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 14.0, 0.35)
	bolt.mesh = box
	var mat := Game.effect_material(Color(0.85, 0.8, 1.0, 0.95))
	bolt.material_override = mat
	bolt.position = at3(at, 7.0)
	Game.fx.add_child(bolt)
	var tw := bolt.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(bolt.queue_free)
	Game.fx.ring(at3(at), r, h.accent, 0.35)
	Game.fx.ring(at3(at), r * 0.5, Color.WHITE, 0.25)
	shake(0.35, 0.06)


## The enemy with the highest max health within `r` of `from` (bosses first),
## leaving out `skip`. Ties go to the nearest.
func _toughest(from: Vector2, r: float, skip: Array) -> int:
	var E = Game.enemies
	var best := -1
	var best_hp := -1.0
	var best_d := INF
	for i in E.query(from, r):
		if skip.has(i):
			continue
		var top: float = E.HP[E.kind[i]]
		var d: float = from.distance_squared_to(E.pos[i])
		if top > best_hp or (top == best_hp and d < best_d):
			best_hp = top
			best_d = d
			best = i
	return best
