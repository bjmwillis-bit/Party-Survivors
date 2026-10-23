extends Node3D
## The campfire: the screen between runs.
##
## A low shot of the party round a fire inside the ruined Keep at sundown.
## Kheiron and Cenhelm sit on logs, Solenne stands. Along the bottom: Fight,
## Heroes, Talents and Settings. Banked gold and nights survived sit in the
## top corners. Hover over a hero to see their name.
##
## Placeholder art: KayKit models and simple shapes until the real ones arrive.

const HeroScript := preload("res://scripts/hero.gd")
const DUNGEON := "res://assets/kaykit/dungeon/"

## Where everyone is. Logs: [position, turn (degrees), length].
const LOGS := [
	[Vector3(0.0, 0.0, -2.3), 0.0, 2.6], # Cenhelm's, behind the fire
	[Vector3(-2.2, 0.0, -0.3), 62.0, 2.4], # Kheiron's, on the left
	[Vector3(2.3, 0.0, -0.4), -58.0, 2.4], # Solenne's, on the right
]
const LOG_RADIUS := 0.24
## Hero spots: [kind, position, facing (degrees), sitting]
const SEATS := [
	["cenhelm", Vector3(0.0, 0.0, -2.3), 0.0, true],
	["kheiron", Vector3(-2.05, 0.0, -0.55), 62.0, true],
	["solenne", Vector3(2.55, 0.0, -1.1), -50.0, false],
]

var camera: Camera3D
var _fire_light: OmniLight3D
var _flames: Array[Node3D] = []
var _sitters: Array = [] # [AnimationPlayer, Skeleton3D] for heroes on logs
var _heroes: Array = [] # {kind, node} for hover names
var _t := 0.0
var _leaving := false

# Interface
var _ui: Control
var _fade: ColorRect
var _settings: Control
var _hover_label: Label
var _settings_close: Button
var _buttons := {}


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = Game.base_time_scale
	_build_world()
	_build_fire()
	_build_party()
	_build_camera()
	_build_ui()


func _process(delta: float) -> void:
	_t += delta
	# The camera drifts slowly in toward the fire.
	var push := 1.0 - exp(-_t * 0.35)
	camera.position = Vector3(sin(_t * 0.15) * 0.25, 2.9 - 0.35 * push, 9.4 - 1.4 * push)
	camera.look_at(Vector3(0.0, 0.6, -0.9))
	# Firelight flickers; the flames dance.
	_fire_light.light_energy = 3.2 + 0.5 * sin(_t * 11.0) + 0.3 * sin(_t * 23.0 + 1.0)
	for i in _flames.size():
		var f := _flames[i]
		var s := 1.0 + 0.22 * sin(_t * (9.0 + i * 2.3) + i) + 0.1 * sin(_t * 17.0 + i * 3.0)
		f.scale = Vector3(1.0 / sqrt(s), s, 1.0 / sqrt(s))
		var tilt: Vector3 = f.get_meta("tilt")
		f.rotation.x = tilt.x + 0.12 * sin(_t * 5.0 + i * 1.3)
		f.rotation.z = tilt.z + 0.12 * cos(_t * 4.3 + i * 0.7)
	# Sitting: play the idle (breathing, arms), then fold the legs over the log.
	for s in _sitters:
		s[0].advance(delta)
		_fold_legs(s[1])
	_update_hover()
	if _fade.modulate.a > 0.0 and not _leaving:
		_fade.modulate.a = maxf(0.0, _fade.modulate.a - delta * 1.2)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if _settings.visible:
		if event.is_action_pressed("ui_cancel"):
			_close_settings()
		return
	if event.is_action_pressed("restart"): # Enter: fight
		_fight()


# --- The world -----------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.035, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.32, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# The last of the sun, low and red, from behind the ruin.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-12.0, 150.0, 0.0)
	sun.light_color = Color(1.0, 0.42, 0.3)
	sun.light_energy = 0.35
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	ground.material_override = Game.material(Color(0.24, 0.21, 0.19))
	add_child(ground)

	# The Keep's broken walls behind the fire.
	var pieces := [
		["wall_broken", Vector3(-6.5, 0, -8.0), 8.0],
		["wall_cracked", Vector3(-3.0, 0, -9.0), 0.0],
		["pillar", Vector3(-1.0, 0, -9.0), 0.0],
		["wall_broken", Vector3(3.6, 0, -9.0), 180.0],
		["pillar_decorated", Vector3(6.2, 0, -8.6), 0.0],
		["wall_cracked", Vector3(8.6, 0, -7.0), -35.0],
		["banner_patternA_red", Vector3(-3.0, 0, -9.05), 0.0],
		["rubble_half", Vector3(0.6, 0, -7.6), 160.0],
		["barrel_large", Vector3(-5.2, 0, -4.8), 0.0],
		["crates_stacked", Vector3(5.6, 0, -4.4), -20.0],
		["sword_shield_broken", Vector3(3.6, 0, 0.9), 40.0],
	]
	for p in pieces:
		var n := Game.model(DUNGEON + str(p[0]) + ".gltf")
		if n == null:
			continue
		n.position = p[1]
		n.rotation_degrees.y = p[2]
		n.scale = Vector3.ONE * 0.8
		add_child(n)
	# Scattered stones on the ground.
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 3
	var rock_mesh := Game.flat_mesh(rock)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var r := MeshInstance3D.new()
		r.mesh = rock_mesh
		r.material_override = Game.material(Color(0.36, 0.34, 0.33))
		var a := rng.randf() * TAU
		var d := rng.randf_range(3.5, 14.0)
		r.position = Vector3(cos(a) * d, 0.0, sin(a) * d - 2.0)
		var s := rng.randf_range(0.15, 0.5)
		r.scale = Vector3(s, s * 0.6, s)
		add_child(r)


func _build_fire() -> void:
	# A ring of stones.
	var stone := SphereMesh.new()
	stone.radial_segments = 6
	stone.rings = 3
	var stone_mesh := Game.flat_mesh(stone)
	for i in 9:
		var a := i * TAU / 9.0
		var s := MeshInstance3D.new()
		s.mesh = stone_mesh
		s.material_override = Game.material(Color(0.4, 0.38, 0.37))
		s.position = Vector3(cos(a) * 0.75, 0.05, sin(a) * 0.75)
		s.scale = Vector3(0.26, 0.18, 0.22)
		add_child(s)
	# Firewood, leaning together.
	var wood := CylinderMesh.new()
	wood.top_radius = 0.07
	wood.bottom_radius = 0.09
	wood.height = 0.85
	wood.radial_segments = 6
	var wood_mesh := Game.flat_mesh(wood)
	for i in 5:
		var w := MeshInstance3D.new()
		w.mesh = wood_mesh
		w.material_override = Game.material(Color(0.3, 0.18, 0.1))
		var a := i * TAU / 5.0
		w.position = Vector3(cos(a) * 0.24, 0.26, sin(a) * 0.24)
		w.rotation = Vector3(0.0, -a, 0.0)
		w.rotate_object_local(Vector3.FORWARD, -0.5)
		add_child(w)
	# Flames: thin glowing tongues that flicker and sway.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 9:
		var inner := k >= 6
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(0.1, 0.15) if inner else rng.randf_range(0.13, 0.22)
		cone.height = rng.randf_range(0.7, 1.0) if inner else rng.randf_range(0.9, 1.6)
		cone.radial_segments = 4
		cone.rings = 1
		var m := MeshInstance3D.new()
		m.mesh = Game.flat_mesh(cone)
		var col := Color(1.0, 0.85, 0.4) if inner else Color(1.0, rng.randf_range(0.35, 0.55), 0.1)
		var mat := Game.material(col, 4.0 if inner else 2.6)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position.y = cone.height * 0.5
		var holder := Node3D.new()
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.08) if inner else rng.randf_range(0.05, 0.2)
		holder.position = Vector3(cos(a) * r, 0.1, sin(a) * r)
		holder.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		holder.set_meta("base", 1.0)
		holder.set_meta("tilt", holder.rotation)
		holder.add_child(m)
		add_child(holder)
		_flames.append(holder)
	# Embers drifting up.
	var embers := CPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 2.2
	embers.position = Vector3(0.0, 0.4, 0.0)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.3
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.gravity = Vector3(0.0, 0.6, 0.0)
	embers.initial_velocity_min = 0.4
	embers.initial_velocity_max = 1.0
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.0
	var ember := BoxMesh.new()
	ember.size = Vector3(0.035, 0.035, 0.035)
	embers.mesh = ember
	embers.material_override = Game.material(Color(1.0, 0.55, 0.15), 4.0)
	add_child(embers)
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0.0, 1.0, 0.0)
	_fire_light.light_color = Color(1.0, 0.6, 0.32)
	_fire_light.omni_range = 11.0
	_fire_light.omni_attenuation = 1.4
	_fire_light.shadow_enabled = true
	add_child(_fire_light)


# --- The party -----------------------------------------------------------------

func _build_party() -> void:
	var bark := Game.material(Color(0.32, 0.22, 0.15))
	for l in LOGS:
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = LOG_RADIUS
		log_mesh.bottom_radius = LOG_RADIUS
		log_mesh.height = l[2]
		log_mesh.radial_segments = 7
		var m := MeshInstance3D.new()
		m.mesh = Game.flat_mesh(log_mesh)
		m.material_override = bark
		m.position = l[0] + Vector3(0.0, LOG_RADIUS, 0.0)
		m.rotation_degrees = Vector3(0.0, l[1], 90.0)
		add_child(m)
	for seat in SEATS:
		var model := HeroScript.create_model(seat[0])
		if model == null:
			continue
		var holder := Node3D.new()
		holder.position = seat[1]
		holder.rotation_degrees.y = seat[2]
		add_child(holder)
		holder.add_child(model)
		var anim: AnimationPlayer = model.get_node("Anim")
		if seat[3]:
			# Hips on top of the log, legs folded over it (see _fold_legs).
			model.position.y = LOG_RADIUS * 2.0 - 0.3 * model.scale.y
			anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			anim.play("Idle_A")
			anim.seek(randf() * 2.0, true)
			_sitters.append([anim, model.find_child("Skeleton3D", true, false)])
		else:
			anim.play("Idle_B" if anim.has_animation("Idle_B") else "Idle_A")
		_heroes.append({"kind": seat[0], "node": holder, "height": 2.0 if seat[3] else 2.3})


## Bends the thighs forward and the shins down: a seated pose made from the
## standing rig (the free pack has no sitting animation).
func _fold_legs(skel: Skeleton3D) -> void:
	if skel == null:
		return
	for side in ["l", "r"]:
		var up := skel.find_bone("upperleg." + side)
		var low := skel.find_bone("lowerleg." + side)
		if up < 0 or low < 0:
			continue
		var splay := 0.12 if side == "l" else -0.12
		skel.set_bone_pose_rotation(up, skel.get_bone_rest(up).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, -1.5) * Quaternion(Vector3.FORWARD, splay))
		skel.set_bone_pose_rotation(low, skel.get_bone_rest(low).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, 1.45))


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.current = true
	camera.position = Vector3(0.0, 2.9, 9.4)
	camera.look_at(Vector3(0.0, 0.6, -0.9))


# --- Interface ---------------------------------------------------------------------

const GOLD := Color(1.0, 0.85, 0.3)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)

	var p: Dictionary = Game.progress
	var gold := _label("Gold  %d" % p["gold"], 34, GOLD)
	gold.set_anchors_preset(Control.PRESET_TOP_LEFT)
	gold.position = Vector2(32, 26)
	_ui.add_child(gold)
	var nights := _label("Nights survived  %d" % p["nights_survived"], 30, Color(0.85, 0.8, 1.0))
	nights.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nights.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nights.offset_left = -500
	nights.offset_right = -32
	nights.offset_top = 26
	_ui.add_child(nights)
	if p["runs"] > 0:
		var best := _label("Best kills  %d" % p["best_kills"], 22, Color(1, 1, 1, 0.7))
		best.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		best.offset_left = -500
		best.offset_right = -32
		best.offset_top = 70
		_ui.add_child(best)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -640
	row.offset_right = 640
	row.offset_top = -130
	row.offset_bottom = -40
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	_ui.add_child(row)
	_buttons["fight"] = _button(row, "FIGHT", true, _fight)
	_buttons["heroes"] = _button(row, "HEROES", false, Callable())
	_buttons["talents"] = _button(row, "TALENTS", false, Callable())
	_buttons["settings"] = _button(row, "SETTINGS", true, _open_settings)
	_buttons["fight"].grab_focus()

	_hover_label = _label("", 30, Color.WHITE)
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.size = Vector2(400, 50)
	_hover_label.visible = false
	_ui.add_child(_hover_label)

	_build_settings()

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)


func _button(row: Control, text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(250, 76)
	b.add_theme_font_size_override("font_size", 30)
	b.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.03, 0.03, 0.72 if state != "hover" else 0.85)
		st.border_color = GOLD if state in ["hover", "focus", "pressed"] else Color(0.75, 0.6, 0.4, 0.8)
		if state == "disabled":
			st.border_color = Color(0.4, 0.38, 0.36, 0.5)
		st.set_border_width_all(3 if state in ["hover", "focus"] else 2)
		st.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, st)
	b.add_theme_color_override("font_color", Color(0.95, 0.9, 0.82))
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.48, 0.46))
	b.disabled = not enabled
	if not enabled:
		b.tooltip_text = "Coming soon"
	elif action.is_valid():
		b.pressed.connect(action)
	row.add_child(b)
	return b


func _build_settings() -> void:
	_settings = ColorRect.new()
	(_settings as ColorRect).color = Color(0, 0, 0, 0.6)
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.visible = false
	_ui.add_child(_settings)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.05, 0.05, 0.95)
	st.border_color = GOLD
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(_label("Settings", 40, GOLD))
	for opt in [["damage_numbers", "Damage numbers"], ["captions", "Captions (spoken lines)"]]:
		var c := CheckButton.new()
		c.text = opt[1]
		c.add_theme_font_size_override("font_size", 26)
		c.button_pressed = bool(Game.settings.get(opt[0], true))
		var key: String = opt[0]
		c.toggled.connect(func(on: bool) -> void:
			Game.settings[key] = on
			Game.save_game())
		box.add_child(c)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.add_theme_font_size_override("font_size", 24)
	close.custom_minimum_size = Vector2(0, 54)
	close.pressed.connect(_close_settings)
	box.add_child(close)
	_settings_close = close


func _open_settings() -> void:
	_settings.visible = true
	_settings_close.grab_focus()


func _close_settings() -> void:
	_settings.visible = false
	_buttons["settings"].grab_focus()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Shows a hero's name when the mouse is over them.
func _update_hover() -> void:
	var mouse := get_viewport().get_mouse_position()
	var best = null
	var best_d := 90.0
	for h in _heroes:
		var node: Node3D = h["node"]
		var top: Vector3 = node.global_position + Vector3(0.0, h["height"] * 0.55, 0.0)
		var sp := camera.unproject_position(top)
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = h
	if best == null or _settings.visible:
		_hover_label.visible = false
		return
	var hero_data: Dictionary = HeroScript.DATA[best["kind"]]
	var head := camera.unproject_position(best["node"].global_position + Vector3(0.0, best["height"], 0.0))
	_hover_label.text = hero_data["name"]
	_hover_label.add_theme_color_override("font_color", (hero_data["accent"] as Color).lerp(Color.WHITE, 0.35))
	_hover_label.position = head - Vector2(200, 56)
	_hover_label.visible = true


func _fight() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.6)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
