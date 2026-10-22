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

var time_alive := 0.0
var kills := 0
var shake := 0.0

## Tests raise this to play faster than real time.
var base_time_scale := 1.0
## Tests turn this off: the freeze is timed in real seconds, which a
## sped-up headless run would stretch across hundreds of frames.
var hitstop_enabled := true

var _hitstop_end_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()


func _process(_delta: float) -> void:
	if _hitstop_end_ms > 0 and Time.get_ticks_msec() >= _hitstop_end_ms:
		_hitstop_end_ms = 0
		Engine.time_scale = base_time_scale


# --- Game feel ---------------------------------------------------------------

## Nearly freezes the action for a split second so a big hit feels heavy.
func hitstop(duration: float) -> void:
	if not hitstop_enabled:
		return
	_hitstop_end_ms = maxi(_hitstop_end_ms, Time.get_ticks_msec() + int(duration * 1000.0))
	Engine.time_scale = base_time_scale * 0.05


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


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
# Keyboard: WASD or arrows to move, Space or Shift to swap.
# Gamepad: left stick to move, A or right bumper to swap.

func _setup_input() -> void:
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("move_up", [KEY_W, KEY_UP])
	_bind_keys("move_down", [KEY_S, KEY_DOWN])
	_bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_keys("swap", [KEY_SPACE, KEY_SHIFT])
	_bind_button("swap", JOY_BUTTON_A)
	_bind_button("swap", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_keys("pick_1", [KEY_1])
	_bind_keys("pick_2", [KEY_2])
	_bind_keys("pick_3", [KEY_3])
	_bind_button("pick_1", JOY_BUTTON_X)
	_bind_button("pick_2", JOY_BUTTON_Y)
	_bind_button("pick_3", JOY_BUTTON_B)
	_bind_keys("restart", [KEY_R])
	_bind_button("restart", JOY_BUTTON_START)


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
