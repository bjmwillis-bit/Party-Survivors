extends CanvasLayer
## The campfire's interface (from the user's sketch): banked gold and nights
## survived in the top corners, and Fight, Heroes, Talents and Settings along
## the bottom. Hover over a hero at the fire to see their name; click to open
## their sheet. Lines spoken at the fire show as captions.

const HeroScript := preload("res://scripts/hero.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

signal fight

const HeroData := preload("res://scripts/hero_data.gd")

var shown := false
var _root: Control
var _settings: Control
var _settings_close: Button
var _sheet: Control
var _sheet_box: VBoxContainer
var _sheet_tabs := {}
var _hover_label: Label
var _caption: Label
var _gold_label: Label
var _nights_label: Label
var _best_label: Label
var _talents_hint: Label
var _buttons := {}
var _fade: ColorRect


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_gold_label = UiKit.label("", 34, UiKit.GOLD)
	_gold_label.position = Vector2(32, 26)
	_root.add_child(_gold_label)
	_nights_label = _corner_label(30, Color(0.85, 0.8, 1.0), 26)
	_best_label = _corner_label(22, Color(1, 1, 1, 0.7), 70)

	_caption = UiKit.label("", 28)
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.offset_left = -700
	_caption.offset_right = 700
	_caption.offset_top = -215
	_caption.offset_bottom = -165
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0
	_root.add_child(_caption)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -700
	row.offset_right = 700
	row.offset_top = -150
	row.offset_bottom = -30
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	_root.add_child(row)
	_buttons["fight"] = _add_button(row, UiKit.button("FIGHT", true), func() -> void: fight.emit())
	_buttons["heroes"] = _add_button(row, UiKit.button("HEROES"), func() -> void: _open_sheet("solenne"))
	_buttons["talents"] = _add_button(row, UiKit.button("TALENTS"), Callable())
	_talents_hint = _buttons["talents"].get_parent().get_child(1)
	_buttons["settings"] = _add_button(row, UiKit.button("SETTINGS"), _open_settings)

	_hover_label = UiKit.label("", 30)
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.size = Vector2(400, 50)
	_hover_label.visible = false
	_root.add_child(_hover_label)

	_build_settings()
	_build_sheet()

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	add_child(_fade)
	_root.visible = false


func _corner_label(size: int, color: Color, top: float) -> Label:
	var l := UiKit.label("", size, color)
	l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.offset_left = -500
	l.offset_right = -32
	l.offset_top = top
	_root.add_child(l)
	return l


## Brings the interface up. `payoff`: just back from a night, so the totals
## pop and the heroes may say something.
func show_ui(payoff := false) -> void:
	var p: Dictionary = Game.progress
	_gold_label.text = "Gold  %d" % p["gold"]
	_nights_label.text = "Nights survived  %d" % p["nights_survived"]
	_best_label.text = "Best kills  %d" % p["best_kills"] if p["runs"] > 0 else ""
	_talents_hint.text = "Survive a night to unlock" if p["nights_survived"] == 0 else "Coming soon"
	shown = true
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.3)
	_buttons["fight"].grab_focus()
	if payoff:
		_pop(_gold_label)
		if Game.last_run.get("victory", false):
			_pop(_nights_label)
		if Game.last_run.get("beast_teased", false):
			say([["Kheiron", "What was he talking about?", "kheiron"], ["", "Cenhelm shrugs.", "cenhelm"]], 0.8)


func hide_ui() -> void:
	shown = false
	_settings.visible = false
	_sheet.visible = false
	_hover_label.visible = false
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void: _root.visible = shown)


## Black, then fading up (the very first time the game opens).
func fade_from_black(seconds := 1.2) -> void:
	_fade.modulate.a = 1.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, seconds)


func modal_open() -> bool:
	return _settings.visible or _sheet.visible


func _process(_delta: float) -> void:
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if not shown:
		return
	if modal_open():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_close_modals()
			get_viewport().set_input_as_handled()
		return
	# Click a hero at the fire to open their sheet.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h = _hero_under_mouse()
		if h != null:
			_open_sheet(h.kind)
			get_viewport().set_input_as_handled()


## Adds a button to the bottom row, with a small line under it for hints.
func _add_button(row: Control, b: Button, action: Callable) -> Button:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(col)
	col.add_child(b)
	if action.is_valid():
		b.pressed.connect(action)
	else:
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
	var hint := UiKit.label("", 18, UiKit.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	return b


func _build_settings() -> void:
	var m: Array = UiKit.modal(_root)
	_settings = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UiKit.label("Settings", 40, UiKit.GOLD))
	UiKit.settings_box(box)
	_settings_close = UiKit.button("CLOSE", false, Vector2(300, 58))
	_settings_close.pressed.connect(_close_modals)
	box.add_child(_settings_close)
	box.add_child(UiKit.label("Esc to close", 18, UiKit.DIM))


func _open_settings() -> void:
	_settings.visible = true
	UiKit.pop_in(_settings.get_child(0).get_child(0))
	_settings_close.grab_focus()


func _close_modals() -> void:
	var was_sheet := _sheet.visible
	_settings.visible = false
	_sheet.visible = false
	if shown:
		_buttons["heroes" if was_sheet else "settings"].grab_focus()


func _build_sheet() -> void:
	var m: Array = UiKit.modal(_root)
	_sheet = m[0]
	var outer: VBoxContainer = m[1]
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	outer.add_child(tabs)
	for kind in HeroData.ORDER:
		var b := UiKit.button(HeroData.HEROES[kind]["name"], false, Vector2(150, 50))
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", (HeroData.HEROES[kind]["accent"] as Color).lerp(Color.WHITE, 0.35))
		var k: String = kind
		b.pressed.connect(func() -> void: _show_sheet(k))
		tabs.add_child(b)
		_sheet_tabs[kind] = b
	_sheet_box = VBoxContainer.new()
	_sheet_box.add_theme_constant_override("separation", 10)
	_sheet_box.custom_minimum_size = Vector2(820, 0)
	outer.add_child(_sheet_box)
	var close := UiKit.button("CLOSE", false, Vector2(300, 58))
	close.pressed.connect(_close_modals)
	var c := CenterContainer.new()
	c.add_child(close)
	outer.add_child(c)


func _open_sheet(kind: String) -> void:
	_sheet.visible = true
	UiKit.pop_in(_sheet.get_child(0).get_child(0))
	_show_sheet(kind)
	_sheet_tabs[kind].grab_focus()


func _show_sheet(kind: String) -> void:
	for c in _sheet_box.get_children():
		c.queue_free()
	var d: Dictionary = HeroData.get_hero(kind)
	var accent: Color = (d["accent"] as Color).lerp(Color.WHITE, 0.3)
	_sheet_box.add_child(UiKit.label(d["name"], 46, accent))
	_sheet_box.add_child(UiKit.label("%s   ·   %d health" % [d["sect"], int(d["hp"])], 22, UiKit.DIM))
	_sheet_box.add_child(UiKit.label(d["line"], 22, UiKit.TEXT.darkened(0.15)))
	var role := UiKit.label(d["role"], 24)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_box.add_child(role)
	_sheet_box.add_child(HSeparator.new())
	if d.has("passive"):
		var pas := UiKit.label(d["passive"], 22, UiKit.TEXT.darkened(0.1))
		pas.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sheet_box.add_child(pas)
	for sk in [["Q", "skill"], ["E", "ult"]]:
		var a: Dictionary = d[sk[1]]
		_sheet_box.add_child(UiKit.label("[%s]  %s   (%d s)" % [sk[0], a["name"], int(a["cd"])], 26, accent))
		var body := UiKit.label(a["desc"], 22)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sheet_box.add_child(body)
	_sheet_box.add_child(UiKit.label("Talents: coming soon", 20, UiKit.DIM))


## A label grows and settles, to show its number just changed.
func _pop(l: Label) -> void:
	l.pivot_offset = l.size * 0.5
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(l, "scale", Vector2.ONE * 1.25, 0.1)
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT)


## Spoken lines one after another: [speaker, text, hero kind]. An empty
## speaker shows the text as a stage direction.
func say(lines: Array, delay := 0.0) -> void:
	if not Game.settings.get("captions", true):
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	for ln in lines:
		var col: Color = (HeroData.HEROES[ln[2]]["accent"] as Color).lerp(Color.WHITE, 0.4)
		var text: String = ("%s:  %s" % [ln[0], ln[1]]) if ln[0] != "" else "(%s)" % ln[1]
		var stage: bool = ln[0] == ""
		tw.tween_callback(func() -> void:
			_caption.text = text
			_caption.add_theme_color_override("font_color", UiKit.DIM if stage else col))
		tw.tween_property(_caption, "modulate:a", 1.0, 0.15)
		tw.tween_interval(2.2)
		tw.tween_property(_caption, "modulate:a", 0.0, 0.3)


func _hero_under_mouse():
	var cam := get_viewport().get_camera_3d()
	if cam == null or Game.party == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var best = null
	var best_d := 90.0
	for h in Game.party.heroes:
		var sp := cam.unproject_position(h.global_position + Vector3(0.0, 1.1, 0.0))
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = h
	return best


## Shows a hero's name when the mouse is over them.
func _update_hover() -> void:
	var h = null
	if shown and not modal_open():
		h = _hero_under_mouse()
	if h == null:
		_hover_label.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	var head := cam.unproject_position(h.global_position + Vector3(0.0, 2.1, 0.0))
	_hover_label.text = h.hero_name
	_hover_label.add_theme_color_override("font_color", h.accent.lerp(Color.WHITE, 0.35))
	_hover_label.position = head - Vector2(200, 56)
	_hover_label.visible = true
