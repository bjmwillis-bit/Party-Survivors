extends "res://scripts/kits/kit.gd"
## Levana. Basic: throws daggers at the nearest enemy within 5 m, every 0.6 s.
##   Each passes through 2 enemies and stays where it lands (10 at most).
## Q Vanish: recalls her 10 newest daggers (they hit on the way back); she's
##   invisible with +30% speed for 3 s and can't attack meanwhile.
## E Smoke and Poison: two smoke bombs at the furthest enemies in the leash:
##   5 m clouds for 6 s, slowing 20% and dealing 30% of her attack a second.

const FLY := 5.0
const SPEED := 20.0
const PIERCE := 2
const HIT_RADIUS := 0.55
const MAX_ON_GROUND := 10
const VANISH_TIME := 3.0
const VANISH_SPEED := 1.3
const CLOUD_RADIUS := 5.0
const CLOUD_TIME := 6.0
const CLOUD_DPS := 0.3

## Flying daggers: {node, pos, dir, left, pierce, hit, back}
var _flying: Array = []
## Daggers on the ground, oldest first: {node, pos}
var _ground: Array = []
## Clouds: {node, mat, pos, time, tick}
var _clouds: Array = []
var _vanish := 0.0


func attack() -> bool:
	if _vanish > 0.0:
		return false
	var t: int = Game.enemies.nearest(me(), h.shot_range())
	if t < 0:
		return false
	var dir: Vector2 = (Game.enemies.pos[t] - me()).normalized()
	if h.is_leader and h.aim_dir != Vector2.ZERO:
		dir = h.aim_dir
	var n := h.instances()
	for k in n:
		var spread := (k - (n - 1) * 0.5) * 0.16
		_throw(dir.rotated(spread))
	h.face(dir, 0.1)
	h.lunge(0.4)
	h.twist(0.3)
	return true


func _throw(dir: Vector2) -> void:
	var node := make_prop("weapons/dagger.gltf", 0.8, Color(0.8, 0.8, 0.85))
	node.position = h.position + Vector3(0.0, 1.0, 0.0)
	node.rotation.y = atan2(dir.x, dir.y)
	_flying.append({"node": node, "pos": me(), "dir": dir, "left": FLY, "pierce": PIERCE + h.pierce_bonus, "hit": {}, "back": false})


func tick(delta: float) -> void:
	if _vanish > 0.0:
		_vanish -= delta
		if _vanish <= 0.0:
			_end_vanish()
	_tick_flying(delta)
	_tick_clouds(delta)


func _tick_flying(delta: float) -> void:
	var i := _flying.size() - 1
	while i >= 0:
		var f: Dictionary = _flying[i]
		var node: Node3D = f["node"]
		if not is_instance_valid(node):
			_flying.remove_at(i)
			i -= 1
			continue
		var p: Vector2 = f["pos"]
		var done := false
		if f["back"]:
			var home := me()
			var d := p.distance_to(home)
			if d <= SPEED * delta + 0.4:
				node.queue_free()
				_flying.remove_at(i)
				i -= 1
				continue
			f["dir"] = (home - p) / d
		var step := SPEED * delta
		p += f["dir"] * step
		f["left"] -= step
		for e in Game.enemies.query(p, HIT_RADIUS):
			if f["hit"].has(e):
				continue
			f["hit"][e] = true
			Game.enemies.damage(e, h.power(), f["dir"], 3.0)
			if not f["back"]:
				f["pierce"] -= 1
				if f["pierce"] < 0:
					done = true
					break
		node.position = Vector3(p.x, 1.0 if f["back"] else 0.9, p.y)
		node.rotation.y = atan2(f["dir"].x, f["dir"].y)
		f["pos"] = p
		if not f["back"] and (done or f["left"] <= 0.0):
			_land(node, p)
			_flying.remove_at(i)
		i -= 1


## A dagger comes to rest on the ground, ready to be called back.
func _land(node: Node3D, p: Vector2) -> void:
	node.position = Vector3(p.x, 0.12, p.y)
	node.rotation.x = PI * 0.5
	_ground.append({"node": node, "pos": p})
	while _ground.size() > MAX_ON_GROUND:
		var old: Dictionary = _ground.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()


func busy() -> bool:
	return _vanish > 0.0


func skill() -> bool:
	# The newest ten daggers fly home, cutting through whatever's in the way.
	for g in _ground:
		if is_instance_valid(g["node"]):
			_flying.append({"node": g["node"], "pos": g["pos"], "dir": Vector2.ZERO, "left": 99.0, "pierce": 99, "hit": {}, "back": true})
	_ground.clear()
	_start_vanish()
	return true


func _start_vanish() -> void:
	_vanish = VANISH_TIME
	h.untargetable = true
	h.ghost = true
	h.speed_mult = VANISH_SPEED
	Game.fx.ring(h.position, 2.0, Color(0.3, 0.25, 0.35), 0.35)


func _end_vanish() -> void:
	h.untargetable = false
	h.ghost = false
	h.speed_mult = 1.0


func skill_worth() -> bool:
	return (_ground.size() >= 6 and Game.enemies.query(me(), 6.0).size() >= 3) or (h.hp < h.max_hp * 0.4 and Game.enemies.query(me(), 3.0).size() >= 2)


func ult() -> bool:
	var count := 3 if h.has_mod("lev_u_three") else 2
	var spots: Array = []
	var centre := leash_center()
	# The furthest enemies in the leash, never two clouds within 5 m.
	var candidates: Array = []
	for i in Game.enemies.query(centre, Game.party.LEASH):
		candidates.append([me().distance_squared_to(Game.enemies.pos[i]), Game.enemies.pos[i]])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	for c in candidates:
		var p: Vector2 = c[1]
		var clear := true
		for s in spots:
			clear = clear and p.distance_to(s) >= CLOUD_RADIUS
		if clear:
			spots.append(p)
		if spots.size() >= count:
			break
	if spots.is_empty():
		return false
	for s in spots:
		_bomb(s)
	if h.has_mod("lev_u_veil"):
		_start_vanish()
	h.twist(0.5)
	return true


func _bomb(at: Vector2) -> void:
	var node := make_prop("weapons/smokebomb.gltf", 1.0, Color(0.3, 0.3, 0.3))
	node.position = h.position + Vector3(0.0, 1.0, 0.0)
	var tw := node.create_tween()
	tw.tween_property(node, "position", at3(at, 0.2), 0.35).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		node.queue_free()
		_cloud(at))


func _cloud(at: Vector2) -> void:
	var r := CLOUD_RADIUS * h.area()
	var d := make_disc(r, Color(0.55, 0.65, 0.3, 0.32))
	d[0].position = at3(at, 0.06)
	var secs := 10.0 if h.has_mod("lev_u_linger") else CLOUD_TIME
	_clouds.append({"node": d[0], "mat": d[1], "pos": at, "time": secs, "tick": 0.0, "r": r})
	Game.fx.ring(at3(at), r, Color(0.6, 0.7, 0.3), 0.4)


func _tick_clouds(delta: float) -> void:
	var slow := 0.4 if h.has_mod("lev_u_choke") else 0.2
	var i := _clouds.size() - 1
	while i >= 0:
		var c: Dictionary = _clouds[i]
		c["time"] -= delta
		c["tick"] += delta
		if c["tick"] >= 1.0:
			c["tick"] -= 1.0
			var dmg := h.ult_power(CLOUD_DPS)
			for e in Game.enemies.query(c["pos"], c["r"]):
				Game.enemies.slow(e, slow, 1.2)
				Game.enemies.damage(e, dmg, Vector2.ZERO, 0.0)
		if is_instance_valid(c["node"]):
			c["mat"].albedo_color.a = 0.32 * clampf(c["time"] / 0.6, 0.0, 1.0)
		if c["time"] <= 0.0:
			if is_instance_valid(c["node"]):
				c["node"].queue_free()
			_clouds.remove_at(i)
		i -= 1


func on_downed() -> void:
	super.on_downed()
	_vanish = 0.0
	for f in _flying:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	_flying.clear()
