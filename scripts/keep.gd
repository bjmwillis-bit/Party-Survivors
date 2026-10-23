extends Node3D
## The Keep: a ruined square fort in the middle of the arena, with the camp
## fire in its courtyard. Look reference: docs/reference/keep-mockup.jpg.
##
## - Walls: chunky low-poly stone blocks, broken to different heights (lower
##   at the front so the courtyard stays readable), moss on top, rubble at the
##   foot. Corner piers, and a square tower at the back.
## - Three gates: front (facing the camera), left and right. The back is shut.
## - Every wall blocks heroes and enemies. Enemies and followers find their
##   way round corners and through the gates using a handful of waypoints
##   (see next_point): cheap enough for hundreds of enemies.
## - See-through: a tall stretch of wall fades while it stands between the
##   camera and a hero.
## - Guards: heroes not in the party stand on the gates and the tower. Basic
##   attacks only, half damage, no cards; they can't be hurt and the horde
##   ignores them (story-draft-v1, "Guard posts").
##
## Placeholder art: boxes and faceted rocks built in code.

const HeroScript := preload("res://scripts/hero.gd")
const HeroData := preload("res://scripts/hero_data.gd")

const HALF := 12.0 # half the Keep's width, to the outside of the walls
const THICK := 1.2 # wall thickness
const MID := HALF - THICK * 0.5 # the walls' centre line
const GATE_HALF := 2.0 # half a gate's width
const COURSE := 0.5 # height of one course of stone blocks
const TOWER_HALF := 2.5
const TOWER_HEIGHT := 8.5
const TOWER_Z := -MID
const GATE_TOP := 4.0 # height of a gate's lintel top, where its guard stands

## Gates: where each one's opening is, and which way is out.
const GATES := [
	{"mid": Vector2(0.0, MID), "out": Vector2(0.0, 1.0)}, # front
	{"mid": Vector2(-MID, 0.0), "out": Vector2(-1.0, 0.0)}, # left
	{"mid": Vector2(MID, 0.0), "out": Vector2(1.0, 0.0)}, # right
]
## Guard posts, in the order benched heroes fill them: the three gates, then
## the tower. [position, facing (radians)]
const POSTS := [
	[Vector3(0.0, GATE_TOP, MID), 0.0],
	[Vector3(-MID, GATE_TOP, 0.0), -PI * 0.5],
	[Vector3(MID, GATE_TOP, 0.0), PI * 0.5],
	[Vector3(0.0, TOWER_HEIGHT, TOWER_Z), PI],
]
## Wall runs along each side: [from, to, lowest height, highest height].
## Front walls are low so the courtyard reads from the battle camera.
const RUNS := [
	[Vector2(-HALF + 1.0, MID), Vector2(-GATE_HALF - 1.0, MID), 1.0, 2.4],
	[Vector2(GATE_HALF + 1.0, MID), Vector2(HALF - 1.0, MID), 1.0, 2.4],
	[Vector2(-HALF + 1.0, -MID), Vector2(-TOWER_HALF, -MID), 2.4, 3.8],
	[Vector2(TOWER_HALF, -MID), Vector2(HALF - 1.0, -MID), 2.4, 3.8],
	[Vector2(-MID, -HALF + 1.0), Vector2(-MID, -GATE_HALF - 1.0), 2.0, 3.5],
	[Vector2(-MID, GATE_HALF + 1.0), Vector2(-MID, HALF - 1.0), 1.4, 3.0],
	[Vector2(MID, -HALF + 1.0), Vector2(MID, -GATE_HALF - 1.0), 2.0, 3.5],
	[Vector2(MID, GATE_HALF + 1.0), Vector2(MID, HALF - 1.0), 1.4, 3.0],
]

const STONE := Color(0.36, 0.36, 0.37)
const MOSS := Color(0.24, 0.3, 0.14)
const FADE_TO := 0.28 # how see-through a wall gets in front of a hero
const ROUTE_PAD := 0.6 # how wide a berth routes give the walls

## Solid boxes on the ground (x, z): what blocks movement.
var boxes: Array[Rect2] = []
## Boxes that routes steer round (the walls' outline, without small details).
var _route_boxes: Array[Rect2] = []
var _route_bounds := Rect2()
## Waypoints round the Keep and through its gates, and which see which.
var nodes := PackedVector2Array()
var _links: Array = [] # per node: [[other node, distance], ...]
## Route costs to each party hero, refreshed a few times a second (enemies
## read these instead of working out a route each).
var hero_costs: Array = []
var _cost_t := 0.0

## Wall pieces that can fade: {mesh, mat, rect (x, z), height, alpha}.
var _pieces: Array = []
var guards: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2026
	Game.keep = self
	_build_ground()
	_build_walls()
	_build_corners()
	_build_gates()
	_build_tower()
	_build_rubble()
	_build_routes()
	refresh_guards()


func _process(delta: float) -> void:
	_cost_t -= delta
	if _cost_t <= 0.0 and Game.party != null:
		_cost_t = 0.2
		hero_costs.clear()
		for h in Game.party.heroes:
			hero_costs.append(costs_to(Vector2(h.position.x, h.position.z)))
	_update_fade(delta)


# --- Building -------------------------------------------------------------------

func _build_ground() -> void:
	# The courtyard: a grassier floor inside the walls.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(HALF * 2.0 - THICK, HALF * 2.0 - THICK)
	var m := MeshInstance3D.new()
	m.mesh = floor_mesh
	m.material_override = Game.material(Color(0.31, 0.32, 0.24))
	m.position.y = 0.008
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _build_walls() -> void:
	for run in RUNS:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var length := a.distance_to(b)
		var along := (b - a) / length
		# Solid along its whole length, whatever its height.
		_add_box(_rect_along(a, b, THICK))
		# Split into stretches of 2.4-3.6 m, each with its own broken top.
		var done := 0.0
		while done < length - 0.01:
			var seg := minf(_rng.randf_range(2.4, 3.6), length - done)
			if length - done - seg < 1.2:
				seg = length - done
			var height := _rng.randf_range(float(run[2]), float(run[3]))
			# Some stretches slope down in steps, like the mockup's ruins.
			var end_height := height
			var roll := _rng.randf()
			if roll < 0.3:
				end_height = maxf(0.6, height * _rng.randf_range(0.3, 0.6))
			elif roll < 0.5:
				end_height = minf(float(run[3]) + 0.4, height * _rng.randf_range(1.2, 1.5))
			if _rng.randf() < 0.5:
				var tmp := height
				height = end_height
				end_height = tmp
			var from := a + along * done
			var to := a + along * (done + seg)
			_piece(_masonry(seg, THICK, height, end_height), from, to, maxf(height, end_height))
			done += seg


## The four corners: thick square piers, a little taller than the walls.
func _build_corners() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector2(sx * (HALF - 1.0), sz * (HALF - 1.0))
			var h := _rng.randf_range(2.6, 3.4) if sz > 0.0 else _rng.randf_range(3.6, 4.4)
			var st := _begin()
			_block_column(st, Vector3.ZERO, Vector2(2.2, 2.2), h, h)
			_piece(st.commit(), c - Vector2(0.0, 0.0), c, h, Vector2(2.2, 2.2))
			_add_box(Rect2(c - Vector2(1.1, 1.1), Vector2(2.2, 2.2)))


## Gates: a pier either side and a lintel across the top.
func _build_gates() -> void:
	for g in GATES:
		var mid: Vector2 = g["mid"]
		var out: Vector2 = g["out"]
		var side := Vector2(out.y, -out.x) # along the wall
		for s in [-1.0, 1.0]:
			var c: Vector2 = mid + side * s * (GATE_HALF + 0.5)
			var st := _begin()
			_block_column(st, Vector3.ZERO, _oriented(Vector2(1.0, 1.6), side), GATE_TOP - 0.7, GATE_TOP - 0.7)
			_piece(st.commit(), c, c, GATE_TOP, _oriented(Vector2(1.0, 1.6), side))
			_add_box(Rect2(c - _oriented(Vector2(1.0, 1.6), side) * 0.5, _oriented(Vector2(1.0, 1.6), side)))
		# The lintel: three big blocks, a little moss.
		var st := _begin()
		var span := GATE_HALF * 2.0 + 2.0
		var size := _oriented(Vector2(span, 1.6), side)
		for k in 3:
			var off := side * ((k - 1) * span / 3.0)
			var col := _stone()
			var bsize := _oriented(Vector2(span / 3.0 - 0.04, 1.6), side)
			_box(st, Vector3(off.x, GATE_TOP - 0.35, off.y), Vector3(bsize.x, 0.7, bsize.y), col, _moss_or(col, 0.3))
		_piece(st.commit(), mid, mid, GATE_TOP, size, true)


func _build_tower() -> void:
	var st := _begin()
	var w := TOWER_HALF * 2.0
	_block_column(st, Vector3.ZERO, Vector2(w, w), TOWER_HEIGHT, TOWER_HEIGHT, false)
	# Crenellations round the top.
	var n := 4
	for k in n:
		var t := (k + 0.5) / n * w - TOWER_HALF
		for e in [[Vector2(t, -TOWER_HALF + 0.3)], [Vector2(t, TOWER_HALF - 0.3)], [Vector2(-TOWER_HALF + 0.3, t)], [Vector2(TOWER_HALF - 0.3, t)]]:
			var p: Vector2 = e[0]
			_box(st, Vector3(p.x, TOWER_HEIGHT + 0.35, p.y), Vector3(0.65, 0.7, 0.6), STONE, STONE.lerp(MOSS, 0.4))
	# Two arrow slits on the face toward the courtyard.
	for x in [-0.8, 0.8]:
		_box(st, Vector3(x, TOWER_HEIGHT - 2.4, TOWER_HALF + 0.01), Vector3(0.22, 1.1, 0.04), Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06))
	var c := Vector2(0.0, TOWER_Z)
	_piece(st.commit(), c, c, TOWER_HEIGHT, Vector2(w, w))
	_add_box(Rect2(c - Vector2(TOWER_HALF, TOWER_HALF), Vector2(w, w)))


## Loose rocks along the foot of the walls, inside and out (not in the gates).
func _build_rubble() -> void:
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 3
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < 110 and tries < 600:
		tries += 1
		var t := _rng.randf_range(-HALF, HALF)
		var off := (THICK * 0.5 + _rng.randf_range(0.1, 1.6)) * (1.0 if _rng.randf() < 0.55 else -1.0)
		var p: Vector2
		match _rng.randi() % 4:
			0: p = Vector2(t, MID + off)
			1: p = Vector2(t, -MID + off)
			2: p = Vector2(-MID + off, t)
			_: p = Vector2(MID + off, t)
		if _in_gateway(p) or p.length() < 4.0:
			continue
		var s := _rng.randf_range(0.25, 0.75)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * _rng.randf_range(0.9, 1.4), s * 0.7, s))
		transforms.append(Transform3D(b, Vector3(p.x, s * 0.2, p.y)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Game.flat_mesh(rock)
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Game.material(STONE.darkened(0.1))
	add_child(mmi)


func _in_gateway(p: Vector2) -> bool:
	for g in GATES:
		var mid: Vector2 = g["mid"]
		var out: Vector2 = g["out"]
		var side := Vector2(out.y, -out.x)
		if absf((p - mid).dot(side)) < GATE_HALF + 1.2 and absf((p - mid).dot(out)) < 3.5:
			return true
	return false


# --- Masonry ---------------------------------------------------------------------

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## A stretch of wall `length` long (along local x), its top stepping from
## `h0` at one end to `h1` at the other. Courses of blocks, staggered.
func _masonry(length: float, depth: float, h0: float, h1: float) -> ArrayMesh:
	var st := _begin()
	var courses := int(ceil(maxf(h0, h1) / COURSE))
	for c in courses:
		var y := c * COURSE
		var x := -length * 0.5 - (0.0 if c % 2 == 0 else _rng.randf_range(0.3, 0.5))
		while x < length * 0.5 - 0.05:
			var bl := _rng.randf_range(0.6, 1.25)
			var x0 := maxf(x, -length * 0.5)
			var x1 := minf(x + bl, length * 0.5)
			x += bl
			if x1 - x0 < 0.15:
				continue
			var mid := (x0 + x1) * 0.5
			var top := lerpf(h0, h1, (mid + length * 0.5) / length)
			# Round the top to whole courses, give or take one: stepped ruins.
			if y + COURSE > top + COURSE * 0.35:
				continue
			var is_top := y + COURSE * 2.0 > top + COURSE * 0.35
			var col := _stone()
			var top_col := _moss_or(col, 0.25) if is_top else col
			var inset := _rng.randf_range(-0.05, 0.05)
			_box(st, Vector3(mid, y + COURSE * 0.5, inset), Vector3(x1 - x0 - 0.03, COURSE - 0.03, depth + _rng.randf_range(-0.08, 0.04)), col, top_col)
	return st.commit()


## A solid column of blocks (piers, the tower) of footprint `size`.
func _block_column(st: SurfaceTool, at: Vector3, size: Vector2, h0: float, _h1: float, mossy := true) -> void:
	var courses := int(ceil(h0 / COURSE))
	for c in courses:
		var y := c * COURSE
		var top_course := c == courses - 1
		var col := _stone()
		var top_col := _moss_or(col, 0.3) if top_course and mossy else col
		# Each course is two or three blocks, so joins show.
		var split := 2 + (c % 2)
		var along_x := (c % 2) == 0
		for k in split:
			var f0 := float(k) / split
			var f1 := float(k + 1) / split
			var cx := at.x
			var cz := at.z
			var sx := size.x
			var sz := size.y
			if along_x:
				cx = at.x - size.x * 0.5 + size.x * (f0 + f1) * 0.5
				sx = size.x * (f1 - f0) - 0.03
			else:
				cz = at.z - size.y * 0.5 + size.y * (f0 + f1) * 0.5
				sz = size.y * (f1 - f0) - 0.03
			var jitter := _rng.randf_range(-0.03, 0.03)
			_box(st, Vector3(cx + jitter, y + COURSE * 0.5, cz - jitter), Vector3(sx, COURSE - 0.03, sz), col, top_col if k % 2 == 0 else _moss_or(col, 0.2) if top_course and mossy else col)


## A stone block's colour: grey, a little lighter or darker each time.
func _stone() -> Color:
	var shade := _rng.randf_range(-0.07, 0.06)
	return STONE.lightened(shade) if shade > 0.0 else STONE.darkened(-shade)


## Mossy now and then (a patch of green on a block's top), otherwise `col`.
func _moss_or(col: Color, chance: float) -> Color:
	if _rng.randf() < chance:
		return MOSS.lerp(col, _rng.randf_range(0.2, 0.5))
	return col


## A box with flat faces (no bottom): sides in `side_col`, top in `top_col`.
func _box(st: SurfaceTool, c: Vector3, s: Vector3, side_col: Color, top_col: Color) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	_quad(st, p[4], p[5], p[6], p[7], c, top_col) # top
	_quad(st, p[0], p[1], p[5], p[4], c, side_col)
	_quad(st, p[1], p[2], p[6], p[5], c, side_col)
	_quad(st, p[2], p[3], p[7], p[6], c, side_col)
	_quad(st, p[3], p[0], p[4], p[7], c, side_col)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Color) -> void:
	var out := (a + b + c + d) * 0.25 - inside
	_tri(st, a, b, c, out, col)
	_tri(st, a, c, d, out, col)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(out) > 0.0: # Godot draws the clockwise side, seen from outside
		var tmp := b
		b = c
		c = tmp
		n = -n
	st.set_color(col)
	st.set_normal(-n.normalized())
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(-n.normalized())
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(-n.normalized())
	st.add_vertex(c)


## A size given as (along the wall, across it), turned to world x/z.
func _oriented(size: Vector2, along: Vector2) -> Vector2:
	return size if absf(along.x) > 0.5 else Vector2(size.y, size.x)


func _rect_along(a: Vector2, b: Vector2, depth: float) -> Rect2:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	if absf(a.x - b.x) > absf(a.y - b.y):
		return Rect2(lo.x, lo.y - depth * 0.5, hi.x - lo.x, depth)
	return Rect2(lo.x - depth * 0.5, lo.y, depth, hi.y - lo.y)


## Places a built piece between `from` and `to` (or at a point), with its own
## material so it can fade. `size` is its footprint for a point piece.
func _piece(mesh: ArrayMesh, from: Vector2, to: Vector2, height: float, size := Vector2.ZERO, already_world := false) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	var c := (from + to) * 0.5
	mi.position = Vector3(c.x, 0.0, c.y)
	var rect: Rect2
	if from != to:
		var along := (to - from).normalized()
		mi.rotation.y = -atan2(along.y, along.x)
		rect = _rect_along(from, to, THICK)
	else:
		rect = Rect2(c - size * 0.5, size)
	if already_world:
		mi.rotation.y = 0.0
	add_child(mi)
	_pieces.append({"mesh": mi, "mat": mat, "rect": rect, "height": height, "alpha": 1.0})


func _add_box(r: Rect2) -> void:
	boxes.append(r)
	Game.add_box(r)


# --- See-through walls -------------------------------------------------------------

## A wall hides a hero standing just behind it (further from the camera). The
## camera looks down at 55 degrees from the front, so a wall `h` high hides a
## hero's chest up to about (h - 1) / tan(55) metres behind it.
func _update_fade(delta: float) -> void:
	if Game.party == null or Game.main == null:
		return
	var slope := tan(deg_to_rad(Game.main.CAM_PITCH))
	var camp: bool = Game.main.state == Game.main.CAMP
	for piece in _pieces:
		var r: Rect2 = piece["rect"]
		var h: float = piece["height"]
		var hide := false
		if not camp and h > 1.6:
			var reach := (h - 1.0) / slope + 0.6
			for hero in Game.party.heroes:
				var x: float = hero.position.x
				var z: float = hero.position.z
				if x > r.position.x - 0.7 and x < r.end.x + 0.7 and z < r.end.y and z > r.position.y - reach:
					hide = true
					break
		var target := FADE_TO if hide else 1.0
		var a: float = move_toward(piece["alpha"], target, delta * 4.0)
		if a == piece["alpha"]:
			continue
		piece["alpha"] = a
		var mat: StandardMaterial3D = piece["mat"]
		mat.albedo_color.a = a
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
		var mi: MeshInstance3D = piece["mesh"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if a > 0.999 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Routes ------------------------------------------------------------------------
# A few waypoints sit outside each gate, inside each gate, off each outside
# corner and round the tower. A route is: straight there if nothing's in the
# way, otherwise to the waypoint that's in sight and leads there shortest.

func _build_routes() -> void:
	var p := PackedVector2Array()
	for g in GATES:
		var mid: Vector2 = g["mid"]
		var out: Vector2 = g["out"]
		p.append(mid + out * 2.4)
		p.append(mid - out * 2.4)
	var c := HALF + 2.2
	p.append(Vector2(-c, -c))
	p.append(Vector2(c, -c))
	p.append(Vector2(-c, c))
	p.append(Vector2(c, c))
	var tw := TOWER_HALF + 1.4
	p.append(Vector2(-tw, TOWER_Z - TOWER_HALF - 1.4))
	p.append(Vector2(tw, TOWER_Z - TOWER_HALF - 1.4))
	p.append(Vector2(-tw, TOWER_Z + TOWER_HALF + 1.4))
	p.append(Vector2(tw, TOWER_Z + TOWER_HALF + 1.4))
	nodes = p
	# The walls' outline: each side as one box (gaps at the gates), corners
	# and the tower.
	for b in boxes:
		_route_boxes.append(b)
	_route_bounds = Rect2(-HALF - 0.5, TOWER_Z - TOWER_HALF - 0.5, HALF * 2.0 + 1.0, HALF - TOWER_Z + TOWER_HALF + 1.0)
	_links.clear()
	for i in nodes.size():
		var links: Array = []
		for j in nodes.size():
			if i != j and clear(nodes[i], nodes[j]):
				links.append([j, nodes[i].distance_to(nodes[j])])
		_links.append(links)


## True if a body can walk straight from `a` to `b` without touching a wall.
func clear(a: Vector2, b: Vector2, pad := ROUTE_PAD) -> bool:
	var bounds := _route_bounds.grow(pad)
	# Most journeys are nowhere near the Keep.
	if maxf(a.x, b.x) < bounds.position.x or minf(a.x, b.x) > bounds.end.x \
			or maxf(a.y, b.y) < bounds.position.y or minf(a.y, b.y) > bounds.end.y:
		return true
	a = _unpad(a, pad)
	b = _unpad(b, pad)
	for r in _route_boxes:
		if _segment_hits(a, b, r.grow(pad)):
			return false
	return true


## A point hugging a wall counts from just outside the berth, on its own side.
func _unpad(p: Vector2, pad: float) -> Vector2:
	for r in _route_boxes:
		var g := r.grow(pad)
		if g.has_point(p):
			var left := p.x - g.position.x
			var right := g.end.x - p.x
			var top := p.y - g.position.y
			var bottom := g.end.y - p.y
			var m := minf(minf(left, right), minf(top, bottom))
			if m == left:
				p.x = g.position.x - 0.01
			elif m == right:
				p.x = g.end.x + 0.01
			elif m == top:
				p.y = g.position.y - 0.01
			else:
				p.y = g.end.y + 0.01
	return p


func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var dx := b.x - a.x
	if absf(dx) < 0.000001:
		if a.x < r.position.x or a.x > r.end.x:
			return false
	else:
		var ta := (r.position.x - a.x) / dx
		var tb := (r.end.x - a.x) / dx
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	var dy := b.y - a.y
	if absf(dy) < 0.000001:
		if a.y < r.position.y or a.y > r.end.y:
			return false
	else:
		var ta := (r.position.y - a.y) / dy
		var tb := (r.end.y - a.y) / dy
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


## How far each waypoint is from `target`, walking (INF if it can't get there).
func costs_to(target: Vector2) -> PackedFloat32Array:
	var n := nodes.size()
	var c := PackedFloat32Array()
	c.resize(n)
	for i in n:
		c[i] = nodes[i].distance_to(target) if clear(nodes[i], target) else INF
	for _pass in n:
		var changed := false
		for i in n:
			for l in _links[i]:
				var via: float = c[l[0]] + l[1]
				if via < c[i]:
					c[i] = via
					changed = true
		if not changed:
			break
	return c


## Where to head next on the way from `from` to `to`: `to` itself if the way
## is clear, otherwise the best waypoint in sight. Pass `costs` (from
## costs_to(to)) when many bodies head for the same target.
func next_point(from: Vector2, to: Vector2, costs := PackedFloat32Array()) -> Vector2:
	if clear(from, to):
		return to
	if costs.is_empty():
		costs = costs_to(to)
	# Try waypoints from the most promising down until one is in sight. Most
	# journeys find one in the first try or two; behind the tower it can take
	# several (the promising ones are inside the walls).
	var tried := PackedByteArray()
	tried.resize(nodes.size())
	for attempt in nodes.size():
		var best := -1
		var best_est := INF
		for i in nodes.size():
			if tried[i] == 1 or costs[i] == INF:
				continue
			var d := from.distance_to(nodes[i])
			if d < 0.9:
				tried[i] = 1 # already here: look past it
				continue
			var est := d + costs[i]
			if est < best_est:
				best_est = est
				best = i
		if best < 0:
			break
		tried[best] = 1
		if clear(from, nodes[best]):
			return nodes[best]
	return to


## The furthest point along a dash from `from` toward `to` that stays clear
## of the walls (so dashes stop at a wall instead of passing through).
func clip(from: Vector2, to: Vector2, radius := 0.4) -> Vector2:
	if clear(from, to, radius):
		return to
	var lo := 0.0
	var hi := 1.0
	for _k in 8:
		var m := (lo + hi) * 0.5
		if clear(from, from.lerp(to, m), radius):
			lo = m
		else:
			hi = m
	return from.lerp(to, lo)


# --- Guards ---------------------------------------------------------------------------

## Heroes not in the party stand guard: the gates first, then the tower.
func refresh_guards() -> void:
	for g in guards:
		g.queue_free()
	guards.clear()
	var party: Array = Game.party_kinds()
	var bench: Array = []
	for kind in HeroData.ORDER:
		if not party.has(kind):
			bench.append(kind)
	for k in mini(bench.size(), POSTS.size()):
		var g = HeroScript.new()
		g.guard = true
		g.setup(bench[k])
		g.position = POSTS[k][0]
		g.facing = POSTS[k][1]
		g.rotation.y = g.facing
		add_child(g)
		guards.append(g)
