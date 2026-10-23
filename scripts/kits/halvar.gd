extends "res://scripts/kits/kit.gd"
## Halvar. Basic: throws his axes (two) at the nearest enemy, 0.3 s apart.
##   They land; 0.2 s after the last lands, they fly back to his hands,
##   hitting again on the way. Every hit bleeds: 15% of his attack each
##   second for 4 s.
## Q Reaving Rush: dashes forward through a line, then spins (×0.8 each, bleeding).
## E Hall of Axes: +50% attack speed for 8 s, and the axes come back faster.

const RANGE := 7.0
const THROW_GAP := 0.3
const RECALL_DELAY := 0.2
const FLY_SPEED := 16.0
const RETURN_SPEED := 18.0
const HIT_RADIUS := 0.7
const BLEED := 0.15 # of his attack, each second
const RUSH := 5.0
const SPIN := 3.0
const ULT_TIME := 8.0
const ULT_SPEED := 0.5

## Each axe: {node, pos (Vector2), to (Vector2), state "out"/"down"/"back", hit {}}
var _axes: Array = []
var _thrown := 0 # axes still to leave his hands this volley
var _ult_t := 0.0
var _spin_t := 0.0


func attack() -> bool:
	if not _axes.is_empty() or _thrown > 0:
		return false
	var t: int = Game.enemies.nearest(me(), RANGE)
	if t < 0:
		return false
	var n: int = h.instances() + (2 if _ult_t > 0.0 and h.has_mod("hal_u_more") else 0)
	_thrown = n
	for k in n:
		after(THROW_GAP * k * _haste(), _throw_one)
	return true


func _haste() -> float:
	return 1.0 / (1.0 + h.buff_rate)


func _throw_one() -> void:
	_thrown = maxi(0, _thrown - 1)
	var dir := aim(RANGE)
	if dir == Vector2.ZERO:
		dir = Vector2(sin(h.facing), cos(h.facing))
	var dist := RANGE * 0.8
	var t: int = Game.enemies.nearest(me(), RANGE)
	if t >= 0 and not h.is_leader:
		dist = minf(RANGE, me().distance_to(Game.enemies.pos[t]) + 1.0)
	elif t >= 0:
		dist = clampf(me().distance_to(Game.enemies.pos[t]) + 1.0, 3.0, RANGE)
	var node := make_prop("weapons/axe_1handed.gltf", 0.9, Color(0.6, 0.6, 0.65))
	node.position = h.position + Vector3(0.0, 1.0, 0.0)
	_axes.append({"node": node, "pos": me(), "to": me() + dir * dist, "state": "out", "hit": {}})
	h.face(dir)
	h.lunge(0.5)
	h.twist(0.3 if _axes.size() % 2 == 0 else -0.3)


func tick(delta: float) -> void:
	_ult_t = maxf(0.0, _ult_t - delta)
	h.buff_rate = ULT_SPEED if _ult_t > 0.0 else 0.0
	if _ult_t > 0.0 and h.has_mod("hal_u_spin"):
		_spin_t -= delta
		if _spin_t <= 0.0:
			_spin_t = 2.0
			_spin()
	_tick_axes(delta)


func _tick_axes(delta: float) -> void:
	var all_down := _thrown == 0 and not _axes.is_empty()
	var i := _axes.size() - 1
	while i >= 0:
		var a: Dictionary = _axes[i]
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			_axes.remove_at(i)
			i -= 1
			continue
		var p: Vector2 = a["pos"]
		match a["state"]:
			"out":
				all_down = false
				var to: Vector2 = a["to"]
				var step := FLY_SPEED * (1.0 + h.buff_rate * 0.6) * delta
				var d := p.distance_to(to)
				p = to if d <= step else p + (to - p) / d * step
				_cut(a, p)
				node.rotation.x += delta * 25.0
				if p == to:
					a["state"] = "down"
					a["down_t"] = 0.0
				node.position = Vector3(p.x, 0.25 + 0.75 * minf(1.0, p.distance_to(to) / 3.0), p.y)
			"down":
				a["down_t"] += delta
				node.rotation.x = lerpf(node.rotation.x, -1.3, 0.3)
			"back":
				all_down = false
				var home := me()
				var speed := RETURN_SPEED * (1.6 if _ult_t > 0.0 else 1.0)
				var d := p.distance_to(home)
				if d <= speed * delta + 0.4:
					node.queue_free()
					_axes.remove_at(i)
					i -= 1
					continue
				p += (home - p) / d * speed * delta
				_cut(a, p)
				node.rotation.x -= delta * 25.0
				node.position = Vector3(p.x, 1.0, p.y)
		a["pos"] = p
		i -= 1
	# Once every axe of the volley has landed, call them back.
	if all_down:
		var newest := INF
		for a in _axes:
			newest = minf(newest, float(a.get("down_t", 0.0)))
		if newest >= RECALL_DELAY * _haste():
			for a in _axes:
				a["state"] = "back"
				a["hit"] = {}


## An axe cutting through whatever it passes.
func _cut(a: Dictionary, p: Vector2) -> void:
	for e in Game.enemies.query(p, HIT_RADIUS):
		if a["hit"].has(e):
			continue
		a["hit"][e] = true
		var dmg := h.power()
		var rel: Vector2 = Game.enemies.pos[e] - p
		Game.enemies.damage(e, dmg, rel.normalized() if rel.length() > 0.05 else Vector2.UP, 3.0)
		bleed(e, dmg * BLEED)
		if _ult_t > 0.0 and h.has_mod("hal_u_feast"):
			h.heal(dmg * BLEED * 4.0 * 0.2)


func busy() -> bool:
	return not _axes.is_empty() or _thrown > 0


func skill() -> bool:
	var dir := aim(RUSH + 3.0)
	if dir == Vector2.ZERO:
		dir = Vector2(sin(h.facing), cos(h.facing))
	var from := me()
	var hit := {}
	var dmg := h.skill_power(0.8)
	h.start_motion(at3(from + dir * RUSH), 0.25, 0.2, func() -> void:
		hit_line(from, me(), 1.0, dmg, 6.0, hit, func(i: int) -> void: bleed(i, h.power() * BLEED)),
		_spin)
	return true


func _spin() -> void:
	var r := SPIN * h.area()
	hit_circle(me(), r, h.skill_power(0.8), 7.0, func(i: int) -> void: bleed(i, h.power() * BLEED))
	Game.fx.slash(h.position, h.facing, r, PI, h.accent)
	Game.fx.slash(h.position, h.facing + PI, r, PI, h.accent)
	h.twist(1.2)
	shake(0.2)


func skill_worth() -> bool:
	return Game.enemies.query(me(), RUSH).size() >= 4


func ult() -> bool:
	_ult_t = 12.0 if h.has_mod("hal_u_long") else ULT_TIME
	_spin_t = 0.0
	Game.fx.ring(h.position, 3.0, h.accent, 0.4)
	Game.fx.ring(h.position, 1.5, Color.WHITE, 0.25)
	shake(0.25)
	return true


func on_downed() -> void:
	super.on_downed()
	_thrown = 0
	_ult_t = 0.0
	for a in _axes:
		if is_instance_valid(a["node"]):
			a["node"].queue_free()
	_axes.clear()
