extends Node3D
## Short-lived visual effects: slashes, rings, dust, death puffs and
## Kheiron's bolts. Everything fades and removes itself.

const BOLT_SPEED := 20.0
const MAX_PUFFS_PER_FRAME := 10

var _bolts: Array = []
var _zones: Array = []
var _sector_cache := {}
var _box: BoxMesh
var _ring: TorusMesh
var _bolt_mesh: Mesh
var _bolt_mats := {}
var _puffs_this_frame := 0
var _numbers := 0 # damage numbers on screen right now
const MAX_NUMBERS := 14


func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3(0.2, 0.2, 0.2)
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.86
	_ring.outer_radius = 1.0
	_ring.rings = 32
	_ring.ring_segments = 3
	var orb := SphereMesh.new()
	orb.radius = 0.15
	orb.height = 0.3
	orb.radial_segments = 5
	orb.rings = 3
	_bolt_mesh = Game.flat_mesh(orb)


func _process(delta: float) -> void:
	_puffs_this_frame = 0
	_update_bolts(delta)
	_update_zones(delta)


# --- Effects -----------------------------------------------------------------

## A flat arc that flashes and fades: Solenne's cut.
func slash(origin: Vector3, yaw: float, radius: float, half_angle: float, color: Color) -> void:
	var key := "%d_%d" % [int(radius * 10.0), int(half_angle * 100.0)]
	var mesh = _sector_cache.get(key)
	if mesh == null:
		mesh = _make_sector(radius, half_angle)
		_sector_cache[key] = mesh
	var n := _temp(mesh, Color(color.r, color.g, color.b, 0.85), origin + Vector3(0.0, 0.6, 0.0), 0.14,
		Vector3(0.85, 1.0, 0.85), Vector3(1.05, 1.0, 1.05), 0.0)
	n.rotation.y = yaw


## An expanding ring on the ground: slams, heals, swaps.
func ring(origin: Vector3, radius: float, color: Color, life: float) -> void:
	var from := Vector3(radius * 0.2, 0.2, radius * 0.2)
	var to := Vector3(radius, 0.2, radius)
	_temp(_ring, Color(color.r, color.g, color.b, 0.8), Vector3(origin.x, 0.08, origin.z), life, from, to, 0.0)


## A long, thin flash straight ahead: Solenne's counter skewer.
func thrust(origin: Vector3, yaw: float, length: float, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.08, length)
	var n := _temp(box, Color(color.r, color.g, color.b, 0.9), origin + Vector3(0.0, 0.9, 0.0), 0.16,
		Vector3(1.0, 1.0, 0.6), Vector3(0.4, 1.0, 1.0), 0.0)
	n.rotation.y = yaw
	# Shift forward so the thrust starts at her and extends outwards.
	n.position += Vector3(sin(yaw), 0.0, cos(yaw)) * length * 0.5


## A floating damage number (big hits only; can be turned off in settings).
func damage_number(at: Vector3, amount: float) -> void:
	if not Game.settings.get("damage_numbers", true) or _numbers >= MAX_NUMBERS:
		return
	var col := Color(1.0, 0.95, 0.8)
	if amount >= 150.0:
		col = Color(1.0, 0.55, 0.15)
	if amount >= 400.0:
		col = Color(1.0, 0.2, 0.15)
	var size := 1.0 + clampf(amount / 300.0, 0.0, 1.0)
	float_text(at + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)), str(int(amount)), col, size)


## Text that floats up and fades (damage numbers, "+25 gold").
func float_text(at: Vector3, text: String, color: Color, size := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = int(56 * size)
	l.outline_size = int(14 * size)
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 1)
	l.pixel_size = 0.01
	l.position = at
	add_child(l)
	_numbers += 1
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y + 1.2, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(func() -> void:
		_numbers -= 1
		l.queue_free())


func dust(origin: Vector3) -> void:
	if _puffs_this_frame >= MAX_PUFFS_PER_FRAME:
		return
	_puffs_this_frame += 1
	var p := Vector3(origin.x + randf_range(-0.15, 0.15), 0.1, origin.z + randf_range(-0.15, 0.15))
	_temp(_box, Color(0.75, 0.7, 0.6, 0.6), p, 0.3, Vector3.ONE, Vector3.ONE * 0.3, 0.35)


func death_puff(origin: Vector3, color: Color) -> void:
	if _puffs_this_frame >= MAX_PUFFS_PER_FRAME:
		return
	_puffs_this_frame += 1
	_temp(_box, Color(color.r, color.g, color.b, 0.9), origin, 0.25, Vector3.ONE * 1.5, Vector3.ONE * 3.0, 0.5)


## A projectile (Kheiron's bolts, Solenne's flame waves). Flies straight and
## damages enemies it touches, passing through `pierce` of them.
func bolt(start: Vector3, dir: Vector2, dmg: float, pierce: int, color: Color, speed := BOLT_SPEED, size := 1.0, life := 1.0) -> void:
	var mat = _bolt_mats.get(color)
	if mat == null:
		mat = Game.material(color, 2.0)
		_bolt_mats[color] = mat
	var n := MeshInstance3D.new()
	n.mesh = _bolt_mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = start
	n.scale = Vector3.ONE * size
	add_child(n)
	_bolts.append({
		"node": n, "pos": Vector2(start.x, start.z), "dir": dir, "speed": speed, "radius": 0.55 * size,
		"dmg": dmg, "pierce": pierce, "life": life, "hit": {}, "y": start.y,
	})


## Burning ground along a line (Solenne's Scorched Path). Damages enemies
## standing on it a few times a second.
func fire_line(a: Vector3, b: Vector3, width: float, seconds: float, dps: float) -> void:
	var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	if length < 0.1:
		return
	var box := BoxMesh.new()
	box.size = Vector3(width * 2.0, 0.05, length)
	var mat := Game.effect_material(Color(1.0, 0.45, 0.1, 0.55))
	var n := MeshInstance3D.new()
	n.mesh = box
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	n.position = Vector3(mid.x, 0.05, mid.z)
	n.rotation.y = atan2(b.x - a.x, b.z - a.z)
	add_child(n)
	_zones.append({"node": n, "mat": mat, "a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z),
		"width": width, "time": seconds, "dps": dps, "tick": 0.0})


func _update_bolts(delta: float) -> void:
	var i := _bolts.size() - 1
	while i >= 0:
		var b: Dictionary = _bolts[i]
		b["life"] -= delta
		var p: Vector2 = b["pos"] + b["dir"] * b["speed"] * delta
		b["pos"] = p
		var n: MeshInstance3D = b["node"]
		n.position = Vector3(p.x, b["y"], p.y)
		var done: bool = b["life"] <= 0.0
		if not done:
			for e in Game.enemies.query(p, b["radius"]):
				if b["hit"].has(e):
					continue
				b["hit"][e] = true
				Game.enemies.damage(e, b["dmg"], b["dir"], 4.0)
				b["pierce"] -= 1
				if b["pierce"] < 0:
					done = true
					break
		if done:
			n.queue_free()
			_bolts.remove_at(i)
		i -= 1


func _update_zones(delta: float) -> void:
	var i := _zones.size() - 1
	while i >= 0:
		var z: Dictionary = _zones[i]
		z["time"] -= delta
		z["tick"] += delta
		if z["tick"] >= 0.25:
			z["tick"] -= 0.25
			var a: Vector2 = z["a"]
			var b: Vector2 = z["b"]
			var mid := (a + b) * 0.5
			var width: float = z["width"]
			var reach: float = a.distance_to(b) * 0.5 + width
			for e in Game.enemies.query(mid, reach):
				var p: Vector2 = Game.enemies.pos[e]
				if _distance_to_segment(p, a, b) <= width:
					Game.enemies.damage(e, z["dps"] * 0.25, Vector2.ZERO, 0.0)
		var flicker := 0.45 + 0.15 * sin(Time.get_ticks_msec() * 0.02 + i)
		z["mat"].albedo_color.a = flicker * clampf(z["time"] / 0.5, 0.0, 1.0)
		if z["time"] <= 0.0:
			z["node"].queue_free()
			_zones.remove_at(i)
		i -= 1


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Helpers -----------------------------------------------------------------

## Spawns a mesh that scales, rises and fades out over `life` seconds, then frees itself.
func _temp(mesh: Mesh, color: Color, at: Vector3, life: float, scale_from: Vector3, scale_to: Vector3, rise: float) -> MeshInstance3D:
	var mat := Game.effect_material(color)
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = at
	n.scale = scale_from
	add_child(n)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", scale_to, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	if rise != 0.0:
		tw.tween_property(n, "position:y", at.y + rise, life)
	tw.chain().tween_callback(n.queue_free)
	return n


## A flat crescent band facing forward (+Z), used for slashes.
func _make_sector(radius: float, half_angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	var inner := radius * 0.45
	for s in steps:
		var a0 := -half_angle + (2.0 * half_angle) * float(s) / steps
		var a1 := -half_angle + (2.0 * half_angle) * float(s + 1) / steps
		var o0 := Vector3(sin(a0), 0.0, cos(a0))
		var o1 := Vector3(sin(a1), 0.0, cos(a1))
		st.add_vertex(o0 * inner)
		st.add_vertex(o0 * radius)
		st.add_vertex(o1 * radius)
		st.add_vertex(o0 * inner)
		st.add_vertex(o1 * radius)
		st.add_vertex(o1 * inner)
	st.generate_normals()
	return st.commit()
