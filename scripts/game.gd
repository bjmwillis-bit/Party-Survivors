extends Node
## Global helper, loaded automatically as "Game".
##
## Holds references to the systems of the current run, the game-feel tools
## (hitstop and screen shake), the input setup, and small helpers for making
## low-poly meshes and materials.

# Systems of the current run. main.gd fills these in when a run starts.
var main
var party
var enemies
var xp
var fx
var hud
var barks
var keep # the Keep in the middle of the arena (keep.gd): walls, routing, guards

var time_alive := 0.0
var kills := 0
var gold := 0
var shake := 0.0
var chests

## Player settings, edited on the campfire's Settings panel and saved.
var settings := {"damage_numbers": true, "captions": true, "hold_to_attack": false}

## What carries over between runs. Saved to user://save.json.
const SAVE_PATH := "user://save.json"
var progress := {"gold": 0, "nights_survived": 0, "runs": 0, "best_kills": 0, "party": ["solenne", "cenhelm", "kheiron"]}
## Tests switch this off so they never touch the player's save.
var saving_enabled := true

## The results screen. It lives here, outside any scene, so it can stay up
## while the battle behind it turns into the campfire.
var results
## The night that just ended (what the campfire reacts to).
var last_run := {}
## Tests set this to start straight in a night, skipping the campfire.
var skip_camp := false

## Tests raise this to play faster than real time.
var base_time_scale := 1.0
## Tests turn this off: the freeze is timed in real seconds, which a
## sped-up headless run would stretch across hundreds of frames.
var hitstop_enabled := true

var _hitstop_end_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_game()
	results = preload("res://scripts/results.gd").new()
	add_child(results)


func _process(_delta: float) -> void:
	if _hitstop_end_ms > 0 and Time.get_ticks_msec() >= _hitstop_end_ms:
		_hitstop_end_ms = 0
		Engine.time_scale = base_time_scale


# --- Saving ------------------------------------------------------------------

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		push_warning("Save file unreadable; starting fresh.")
		return
	# Merge, so a save from an older version still loads.
	for k in progress:
		if data.get("progress", {}).has(k):
			var v = data["progress"][k]
			progress[k] = v if v is Array else int(v)
	for k in settings:
		if data.get("settings", {}).has(k):
			settings[k] = bool(data["settings"][k])


func save_game() -> void:
	if not saving_enabled:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write the save file.")
		return
	f.store_string(JSON.stringify({"version": 1, "progress": progress, "settings": settings}, "\t"))


## The three heroes in the party (picked at the campfire). Tests can set
## `party_override`.
var party_override: Array = []


func party_kinds() -> Array:
	var HeroData = preload("res://scripts/hero_data.gd")
	var picked: Array = party_override if not party_override.is_empty() else progress.get("party", [])
	var out: Array = []
	for k in picked:
		if HeroData.HEROES.has(k) and not out.has(k):
			out.append(k)
	for k in HeroData.ORDER:
		if out.size() >= 3:
			break
		if not out.has(k):
			out.append(k)
	return out.slice(0, 3)


## A run is over: bank its gold and count the night.
func bank_run(run_gold: int, survived: bool, run_kills: int) -> void:
	progress["gold"] += run_gold
	progress["runs"] += 1
	if survived:
		progress["nights_survived"] += 1
	progress["best_kills"] = maxi(progress["best_kills"], run_kills)
	save_game()


# --- Game feel ---------------------------------------------------------------

## Nearly freezes the action for a split second so a big hit feels heavy.
func hitstop(duration: float) -> void:
	if not hitstop_enabled:
		return
	_hitstop_end_ms = maxi(_hitstop_end_ms, Time.get_ticks_msec() + int(duration * 1000.0))
	Engine.time_scale = base_time_scale * 0.05


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


# --- The arena ---------------------------------------------------------------

## The runestone ring: everything stays inside this circle.
const ARENA_RADIUS := 58.0


func clamp_arena(p: Vector2, margin := 0.0) -> Vector2:
	var r := ARENA_RADIUS - margin
	if p.length_squared() > r * r:
		return p.normalized() * r
	return p


# --- Models and obstacles ----------------------------------------------------

var _scene_cache := {}

## Loads and instances a model (a .glb or .gltf), or returns null if it is
## missing, so callers can fall back to grey-box shapes.
func model(path: String) -> Node3D:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
	var scene = _scene_cache[path]
	if scene == null:
		return null
	return scene.instantiate() as Node3D


## Solid round obstacles (pillars, walls, rubble), kept in a coarse grid so
## every enemy can check the ones near it cheaply. Each is Vector3(x, z, radius).
const OBSTACLE_CELL := 4.0
var _obstacles := {}


## Solid boxes (the Keep's walls), Rect2 on the ground (x, z), in the same grid.
var _boxes := {}


func clear_obstacles() -> void:
	_obstacles.clear()
	_boxes.clear()


func add_box(r: Rect2) -> void:
	var lo := Vector2i(floori((r.position.x - 1.5) / OBSTACLE_CELL), floori((r.position.y - 1.5) / OBSTACLE_CELL))
	var hi := Vector2i(floori((r.end.x + 1.5) / OBSTACLE_CELL), floori((r.end.y + 1.5) / OBSTACLE_CELL))
	for gx in range(lo.x, hi.x + 1):
		for gy in range(lo.y, hi.y + 1):
			var key := Vector2i(gx, gy)
			if not _boxes.has(key):
				_boxes[key] = []
			_boxes[key].append(r)


func add_obstacle(at: Vector2, radius: float) -> void:
	var lo := Vector2i(floori((at.x - radius - 1.5) / OBSTACLE_CELL), floori((at.y - radius - 1.5) / OBSTACLE_CELL))
	var hi := Vector2i(floori((at.x + radius + 1.5) / OBSTACLE_CELL), floori((at.y + radius + 1.5) / OBSTACLE_CELL))
	for gx in range(lo.x, hi.x + 1):
		for gy in range(lo.y, hi.y + 1):
			var key := Vector2i(gx, gy)
			if not _obstacles.has(key):
				_obstacles[key] = []
			_obstacles[key].append(Vector3(at.x, at.y, radius))


## Moves a point of the given radius out of any obstacle it overlaps.
func push_out(p: Vector2, radius: float) -> Vector2:
	var key := Vector2i(floori(p.x / OBSTACLE_CELL), floori(p.y / OBSTACLE_CELL))
	var boxes = _boxes.get(key)
	if boxes != null:
		for r: Rect2 in boxes:
			p = _push_out_box(p, radius, r)
	var cell = _obstacles.get(key)
	if cell == null:
		return p
	for o in cell:
		var c := Vector2(o.x, o.y)
		var d := p - c
		var min_d: float = o.z + radius
		var l2 := d.length_squared()
		if l2 < min_d * min_d:
			var l := sqrt(l2)
			p = c + (d / l if l > 0.001 else Vector2.RIGHT) * min_d
	return p


## Out of a box: to the nearest point `radius` clear of it.
func _push_out_box(p: Vector2, radius: float, r: Rect2) -> Vector2:
	var cx := clampf(p.x, r.position.x, r.end.x)
	var cy := clampf(p.y, r.position.y, r.end.y)
	var d := Vector2(p.x - cx, p.y - cy)
	var l2 := d.length_squared()
	if l2 >= radius * radius:
		return p
	if l2 > 0.000001:
		return Vector2(cx, cy) + d / sqrt(l2) * radius
	# Inside the box: out through the nearest side.
	var left := p.x - r.position.x
	var right := r.end.x - p.x
	var top := p.y - r.position.y
	var bottom := r.end.y - p.y
	var m := minf(minf(left, right), minf(top, bottom))
	if m == left:
		return Vector2(r.position.x - radius, p.y)
	if m == right:
		return Vector2(r.end.x + radius, p.y)
	if m == top:
		return Vector2(p.x, r.position.y - radius)
	return Vector2(p.x, r.end.y + radius)


func blocked(p: Vector2, radius: float) -> bool:
	return push_out(p, radius) != p


# --- Low-poly helpers --------------------------------------------------------

## Turns a smooth primitive (capsule, sphere...) into a faceted low-poly mesh
## by giving every triangle its own flat normal.
func flat_mesh(source: Mesh) -> ArrayMesh:
	var arrays: Array = source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := 0
	while t + 2 < indices.size():
		var a: Vector3 = verts[indices[t]]
		var b: Vector3 = verts[indices[t + 1]]
		var c: Vector3 = verts[indices[t + 2]]
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			t += 3
			continue
		n = n.normalized()
		var smooth: Vector3 = normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]]
		if n.dot(smooth) < 0.0:
			n = -n
		for k in 3:
			st.set_normal(n)
			st.add_vertex(verts[indices[t + k]])
		t += 3
	return st.commit()


func material(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## A flat, see-through material for effects (slashes, rings, dust).
func effect_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


# --- Input -------------------------------------------------------------------
# Controls are set up in code so they work without touching Project Settings.
# Keyboard and mouse: WASD or arrows to move, mouse to aim, Q and E for the
# leader's skills, R for their ultimate, Space or Shift to swap.
# Gamepad: left stick to move, right stick to aim, left bumper and left
# trigger for skills, right trigger for the ultimate, A or right bumper to swap.

func _setup_input() -> void:
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("move_up", [KEY_W, KEY_UP])
	_bind_keys("move_down", [KEY_S, KEY_DOWN])
	_bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	_bind_keys("skill_1", [KEY_Q])
	_bind_button("skill_1", JOY_BUTTON_LEFT_SHOULDER)
	_bind_keys("ultimate", [KEY_E])
	_bind_axis("ultimate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_axis("ultimate", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_bind_keys("swap", [KEY_SPACE, KEY_SHIFT])
	_bind_button("swap", JOY_BUTTON_A)
	_bind_button("swap", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_keys("pick_1", [KEY_1])
	_bind_keys("pick_2", [KEY_2])
	_bind_keys("pick_3", [KEY_3])
	_bind_button("pick_1", JOY_BUTTON_X)
	_bind_button("pick_2", JOY_BUTTON_Y)
	_bind_button("pick_3", JOY_BUTTON_B)
	_bind_keys("restart", [KEY_ENTER, KEY_KP_ENTER])
	_bind_keys("reroll", [KEY_F])
	_bind_keys("banish", [KEY_B])
	_ensure_action("attack") # hold-to-attack (a setting): left mouse, or X
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", click)
	_bind_button("attack", JOY_BUTTON_X)
	_bind_keys("pause", [KEY_ESCAPE, KEY_P])
	_bind_button("pause", JOY_BUTTON_START)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _bind_keys(action: String, keys: Array) -> void:
	_ensure_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _bind_axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure_action(action)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)


func _bind_button(action: String, button: JoyButton) -> void:
	_ensure_action(action)
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)
