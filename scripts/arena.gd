extends Node3D
## The arena: the ground, the ring of runestones that traps the party, the
## ruins inside it, and the night.
##
## The night: each run starts at sundown. Over the first couple of minutes the
## light sinks into a steady, reddish, fire-lit dark (never black: the runes
## glow brighter as the sun goes, so the edge is always visible). When the
## Beast arrives at 12:00, a faint sunrise begins.

const NIGHTFALL := 150.0 # seconds from sundown to full night
const DAWN_TIME := 45.0 # seconds for the faint sunrise once the Beast arrives
const RING_GAP := 1.6 # metres between the edge of play and the stones' centres
const STONE_SPACING := 2.7

## The light at sundown, at night, and at the first hint of dawn.
const SKY := {
	"background": [Color(0.3, 0.22, 0.22), Color(0.045, 0.03, 0.055), Color(0.22, 0.19, 0.24)],
	"ambient": [Color(0.72, 0.64, 0.64), Color(0.44, 0.4, 0.58), Color(0.66, 0.62, 0.7)],
	"ambient_energy": [0.62, 0.5, 0.56],
	"sun": [Color(1.0, 0.74, 0.54), Color(1.0, 0.5, 0.34), Color(1.0, 0.84, 0.7)],
	"sun_energy": [1.0, 0.5, 0.85],
	"sun_pitch": [-28.0, -52.0, -26.0],
	"runes": [0.5, 3.0, 1.4], # glow of the runestones
	"fire": [0.6, 1.5, 0.9], # brazier brightness
	"party": [0.0, 1.2, 0.35], # the warm glow around the party
}

var env: Environment
var sun: DirectionalLight3D
var _rune_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _party_light: OmniLight3D
var _flames: Array[OmniLight3D] = []
var _flame_t := 0.0


func _ready() -> void:
	Game.clear_obstacles()
	_build_light()
	_build_ground()
	_build_ring()
	_build_ruins()
	_update_sky(0.0)


func _process(delta: float) -> void:
	_update_sky(delta)


# --- Light and the night -------------------------------------------------------

func _build_light() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true # runes and fire bloom softly
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	_party_light = OmniLight3D.new()
	_party_light.light_color = Color(1.0, 0.66, 0.42)
	_party_light.omni_range = 11.0
	_party_light.shadow_enabled = false
	add_child(_party_light)


func _sky(key: String, n: float, d: float) -> Variant:
	var k: Array = SKY[key]
	if k[0] is Color:
		return (k[0] as Color).lerp(k[1], n).lerp(k[2], d)
	return lerpf(lerpf(k[0], k[1], n), k[2], d)


func _update_sky(delta: float) -> void:
	var t: float = Game.time_alive
	var n := smoothstep(0.0, NIGHTFALL, t)
	var run_length: float = Game.main.RUN_LENGTH if Game.main != null else 720.0
	var d := smoothstep(run_length, run_length + DAWN_TIME, t)
	env.background_color = _sky("background", n, d)
	env.ambient_light_color = _sky("ambient", n, d)
	env.ambient_light_energy = _sky("ambient_energy", n, d)
	sun.light_color = _sky("sun", n, d)
	sun.light_energy = _sky("sun_energy", n, d)
	sun.rotation_degrees = Vector3(_sky("sun_pitch", n, d), -35.0, 0.0)
	var runes: float = _sky("runes", n, d)
	_rune_mat.emission_energy_multiplier = runes
	_edge_mat.albedo_color.a = 0.02 + 0.018 * runes
	# Braziers flicker; the party carries a warm glow through the dark.
	_flame_t += delta
	var fire: float = _sky("fire", n, d)
	for i in _flames.size():
		_flames[i].light_energy = fire * (1.5 + 0.25 * sin(_flame_t * 9.0 + i * 1.7) + 0.15 * sin(_flame_t * 23.0 + i))
	var l = Game.party.leader() if Game.party != null else null
	if l != null:
		_party_light.position = l.position + Vector3(0.0, 3.4, 0.0)
	_party_light.light_energy = _sky("party", n, d)


# --- Ground ----------------------------------------------------------------------

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	ground.mesh = plane
	ground.material_override = Game.material(Color(0.3, 0.29, 0.26))
	add_child(ground)
	# Beyond the stones the land is darker: nothing out there is for you.
	var outside := MeshInstance3D.new()
	outside.mesh = _annulus(Game.ARENA_RADIUS + RING_GAP + 1.2, 130.0, 96)
	outside.material_override = Game.material(Color(0.13, 0.11, 0.11))
	outside.position.y = 0.01
	add_child(outside)

	# Scattered rocks and grass give the eye something to measure movement by.
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 3
	_scatter(Game.flat_mesh(rock), Color(0.46, 0.45, 0.43), 170, 0.4, 1.4, 0.6, 11)
	var tuft := PrismMesh.new()
	tuft.size = Vector3(0.35, 0.5, 0.12)
	_scatter(tuft, Color(0.38, 0.42, 0.25), 900, 0.6, 1.3, 1.0, 22)


func _scatter(mesh: Mesh, color: Color, count: int, scale_min: float, scale_max: float, height_scale: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var spread := Game.ARENA_RADIUS + 15.0
	for i in count:
		var p := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		if p.length() < 5.0:
			p.x += 10.0 # keep the starting spot clear
		var s := rng.randf_range(scale_min, scale_max)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * height_scale, s))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Game.material(color)
	add_child(mmi)


# --- The runestone ring ------------------------------------------------------------
# Placeholder megaliths: tall, rough standing stones, each carved with faintly
# glowing purple runes on the side facing in. Now and then two stones carry a
# lintel across their tops.

## Rune shapes, as strokes from point to point (in metres on the stone's face).
const GLYPHS := [
	[[Vector2(0, -0.4), Vector2(0, 0.4)], [Vector2(0, 0.15), Vector2(0.25, 0.35)], [Vector2(0, -0.1), Vector2(0.25, 0.1)]],
	[[Vector2(-0.2, -0.32), Vector2(0.2, 0.32)], [Vector2(-0.2, 0.32), Vector2(0.2, -0.32)]],
	[[Vector2(0, 0.36), Vector2(0.2, 0)], [Vector2(0.2, 0), Vector2(0, -0.36)], [Vector2(0, -0.36), Vector2(-0.2, 0)], [Vector2(-0.2, 0), Vector2(0, 0.36)]],
	[[Vector2(0, -0.4), Vector2(0, 0.4)], [Vector2(0, 0.4), Vector2(-0.22, 0.16)], [Vector2(0, 0.4), Vector2(0.22, 0.16)]],
	[[Vector2(-0.12, -0.4), Vector2(-0.12, 0.4)], [Vector2(0.12, -0.4), Vector2(0.12, 0.4)], [Vector2(-0.12, 0.3), Vector2(0.12, 0.05)]],
]


func _build_ring() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var radius := Game.ARENA_RADIUS + RING_GAP
	var count := int(TAU * radius / STONE_SPACING)
	var stones: Array[Transform3D] = []
	var lintels: Array[Transform3D] = []
	var glyphs: Array = []
	for g in GLYPHS.size():
		glyphs.append([])
	var heights: Array[float] = []
	for i in count:
		heights.append(rng.randf_range(0.7, 1.05))
	# Trilithons: every so often two neighbours share a height and a lintel.
	var trilithon := {}
	var i := 3
	while i < count - 1:
		trilithon[i] = true
		heights[i + 1] = heights[i]
		i += rng.randi_range(7, 12)

	for k in count:
		var ang := (float(k) + rng.randf_range(-0.15, 0.15)) / count * TAU
		var p := Vector3(cos(ang), 0.0, sin(ang)) * radius
		var yaw := atan2(-p.x, -p.z) # its carved face looks into the arena
		var w := rng.randf_range(0.85, 1.2)
		var b := Basis(Vector3.UP, yaw)
		if not trilithon.has(k) and not trilithon.has(k - 1):
			b = b * Basis(Vector3.FORWARD, rng.randf_range(-0.06, 0.06)) * Basis(Vector3.RIGHT, rng.randf_range(-0.04, 0.04))
		var stone := Transform3D(b.scaled_local(Vector3(w, heights[k], w)), p)
		stones.append(stone)
		# One or two runes on the inward face.
		var marks := 1 if rng.randf() < 0.5 else 2
		for m in marks:
			var y := 1.5 + m * 1.05 + rng.randf_range(-0.1, 0.1)
			var face_z := 0.42 - 0.12 * (y / 4.0) + 0.02
			var local := Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.12, 0.12), y, face_z))
			glyphs[rng.randi() % GLYPHS.size()].append(stone * local)
		if trilithon.has(k):
			var ang2 := float(k + 1) / count * TAU
			var p2 := Vector3(cos(ang2), 0.0, sin(ang2)) * radius
			var mid := (p + p2) * 0.5
			mid.y = 3.75 * heights[k] + 0.2
			var along := (p2 - p).normalized()
			var lb := Basis(along, Vector3.UP, along.cross(Vector3.UP).normalized())
			lintels.append(Transform3D(lb.scaled_local(Vector3(p.distance_to(p2) + 1.1, 1.0, 1.0)), mid))

	var stone_mat := Game.material(Color(0.4, 0.39, 0.42))
	_multimesh(_megalith_mesh(), stone_mat, stones)
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(1.0, 0.5, 0.75)
	_multimesh(lintel_mesh, stone_mat, lintels)
	_rune_mat = Game.material(Color(0.62, 0.36, 1.0), 1.0)
	_rune_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for g in GLYPHS.size():
		_multimesh(_glyph_mesh(GLYPHS[g]), _rune_mat, glyphs[g])
	# A faint purple wash on the ground along the stones.
	var edge := MeshInstance3D.new()
	edge.mesh = _annulus(Game.ARENA_RADIUS - 1.0, radius + 0.6, 128)
	_edge_mat = Game.effect_material(Color(0.6, 0.35, 1.0, 0.15))
	edge.material_override = _edge_mat
	edge.position.y = 0.02
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge)


func _multimesh(mesh: Mesh, mat: Material, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## A rough standing stone: wider at the base, its top cut on a slant.
func _megalith_mesh() -> ArrayMesh:
	var b := [Vector3(-0.7, 0, -0.42), Vector3(0.7, 0, -0.42), Vector3(0.7, 0, 0.42), Vector3(-0.7, 0, 0.42)]
	var t := [Vector3(-0.5, 4.0, -0.3), Vector3(0.54, 3.7, -0.3), Vector3(0.54, 3.7, 0.3), Vector3(-0.5, 4.0, 0.3)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0.0, 2.0, 0.0)
	for k in 4:
		var k2 := (k + 1) % 4
		_quad(st, b[k], b[k2], t[k2], t[k], centre)
	_quad(st, t[0], t[1], t[2], t[3], centre)
	return st.commit()


## A rune: thin strokes on a flat plane, facing +Z.
func _glyph_mesh(strokes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.035
	for s in strokes:
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var dir := (c - a).normalized()
		a -= dir * w # square-ish ends that overlap at the joins
		c += dir * w
		var side := Vector2(-dir.y, dir.x) * w
		_quad(st, Vector3(a.x + side.x, a.y + side.y, 0), Vector3(c.x + side.x, c.y + side.y, 0),
			Vector3(c.x - side.x, c.y - side.y, 0), Vector3(a.x - side.x, a.y - side.y, 0), Vector3(0, 0, -1))
	return st.commit()


## A flat ring lying on the ground.
func _annulus(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in segments:
		var a0 := float(k) / segments * TAU
		var a1 := float(k + 1) / segments * TAU
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, d0 * inner, d1 * inner, d1 * outer, d0 * outer, Vector3(0, -1, 0))
	return st.commit()


## Adds a four-sided face with a flat normal pointing away from `inside`.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	var out := ((a + b + c + d) * 0.25 - inside)
	_tri(st, a, b, c, out)
	_tri(st, a, c, d, out)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(out) > 0.0: # Godot draws the clockwise side, seen from outside
		var tmp := b
		b = c
		c = tmp
		n = -n
	st.set_normal(-n.normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# --- Ruins -------------------------------------------------------------------
# Placeholder dressing from the KayKit Dungeon pack (CC0, Kay Lousberg):
# broken walls, pillars, braziers and the leavings of old camps, scattered in
# small clusters. Walls, pillars and rubble are solid.

const DUNGEON := "res://assets/kaykit/dungeon/"
const PROP_SCALE := 0.8
## Each piece: [model, offset x, offset z, turn (degrees), solid radius (0 = walk-through)]
const RUIN_SITES := [
	[["wall_broken", 0.0, 0.0, 0.0, 0.0], ["pillar", -2.0, 0.0, 0.0, 0.7], ["rubble_half", 0.6, 2.2, 15.0, 0.0], ["banner_patternA_red", 0.9, 0.05, 0.0, 0.0]],
	[["wall_cracked", 0.0, 0.0, 0.0, 0.0], ["wall_broken", 3.2, 0.0, 0.0, 0.0], ["pillar_decorated", 1.6, 0.0, 0.0, 0.8], ["sword_shield_broken", 1.0, 2.0, 30.0, 0.0]],
	[["pillar", 0.0, 0.0, 0.0, 0.7], ["pillar", 4.0, 0.0, 0.0, 0.7], ["pillar", 0.0, 4.0, 0.0, 0.7], ["rubble_half", 3.0, 3.0, 200.0, 0.0]],
	[["rubble_large", 0.0, 0.0, 0.0, 0.0], ["column", 3.8, 1.5, 0.0, 0.4], ["sword_shield_broken", -2.0, 2.0, -40.0, 0.0]],
	[["barrel_large", 0.0, 0.0, 0.0, 0.8], ["crates_stacked", 2.0, 0.4, 20.0, 1.0], ["barrel_large", 0.4, 1.8, 0.0, 0.8], ["sword_shield_broken", 2.2, 2.4, 70.0, 0.0]],
]
## Braziers: a column with a lit torch on top, throwing warm light.
const BRAZIERS := 6


func _build_ruins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 22 and tries < 400:
		tries += 1
		var p := _random_spot(rng, Game.ARENA_RADIUS - 7.0)
		if p.length() < 12.0 or _too_close(p, placed, 14.0):
			continue
		placed.append(p)
		var site: Array = RUIN_SITES[rng.randi() % RUIN_SITES.size()]
		var turn := rng.randf() * TAU
		for piece in site:
			_place_piece(piece, p, turn)
	# Braziers light the way, a little apart from the ruins.
	var lit := 0
	tries = 0
	while lit < BRAZIERS and tries < 400:
		tries += 1
		var p := _random_spot(rng, Game.ARENA_RADIUS - 8.0)
		if _too_close(p, placed, 6.0) or (lit > 0 and p.length() < 10.0):
			continue
		if lit == 0:
			p = Vector2(5.0, -5.0) # one near the start, so it's seen at once
		placed.append(p)
		_brazier(p)
		lit += 1


func _too_close(p: Vector2, others: Array[Vector2], dist: float) -> bool:
	for o in others:
		if o.distance_to(p) < dist:
			return true
	return false


func _place_piece(piece: Array, at: Vector2, turn: float) -> void:
	var node := Game.model(DUNGEON + str(piece[0]) + ".gltf")
	if node == null:
		return
	var off := Vector2(float(piece[1]), float(piece[2])).rotated(-turn) * PROP_SCALE
	var p := at + off
	node.position = Vector3(p.x, 0.0, p.y)
	node.rotation.y = turn + deg_to_rad(float(piece[3]))
	node.scale = Vector3.ONE * PROP_SCALE
	add_child(node)
	var r: float = float(piece[4]) * PROP_SCALE
	if r > 0.0:
		Game.add_obstacle(p, r)
	# Walls and rubble are long: block them with a row of circles.
	var name_s := str(piece[0])
	var half_len := 0.0
	var rad := 0.0
	if name_s.begins_with("wall"):
		half_len = 1.6
		rad = 0.55
	elif name_s == "rubble_large":
		half_len = 3.0
		rad = 1.1
	elif name_s == "rubble_half":
		half_len = 1.2
		rad = 1.0
	if half_len > 0.0:
		var along := Vector2(cos(-node.rotation.y), sin(-node.rotation.y))
		var centre := p
		if name_s == "rubble_half": # this piece starts at its origin and runs one way
			centre = p + along * 1.6
		var k := -half_len
		while k <= half_len + 0.01:
			Game.add_obstacle(centre + along * k, rad)
			k += rad * 1.2


func _brazier(p: Vector2) -> void:
	var column := Game.model(DUNGEON + "column.gltf")
	var torch := Game.model(DUNGEON + "torch_lit.gltf")
	if column == null or torch == null:
		return
	column.position = Vector3(p.x, 0.0, p.y)
	column.scale = Vector3.ONE * PROP_SCALE
	add_child(column)
	torch.position = Vector3(p.x, 1.4 * PROP_SCALE + 0.35, p.y)
	torch.scale = Vector3.ONE * PROP_SCALE
	add_child(torch)
	Game.add_obstacle(p, 0.45)
	var light := OmniLight3D.new()
	light.position = Vector3(p.x, 2.4, p.y)
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 2.2
	light.omni_range = 8.0
	light.shadow_enabled = false
	add_child(light)
	_flames.append(light)


func _random_spot(rng: RandomNumberGenerator, radius: float) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
