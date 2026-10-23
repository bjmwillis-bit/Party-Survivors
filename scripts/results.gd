extends CanvasLayer
## The end-of-night results.
##
## A win (or withdrawing): the results sit over the live scene while the
## heroes walk back to the fire behind them, and the buttons work at once.
## A fall: the scene behind the results goes black; behind the black the
## camp is set up again, and the choice fades it back in.
## (main.gd directs what happens behind the panel.)

const UiKit := preload("res://scripts/ui_kit.gd")

signal chosen(keep_fighting: bool)
signal blacked_out # a fall: the screen behind the results is now black

var active := false # results are showing (the campfire waits for a choice)
var data := {}

var _root: Control
var _backdrop: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _fight_btn: Button
var _keep_btn: Button
var _choosing := false # buttons are live
var _tween: Tween


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.color = Color.BLACK
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.modulate.a = 0.0
	_root.add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_panel.add_child(_box)
	visible = false


## Shows the results for the night that just ended. `d` holds: victory,
## withdrew, night, time, kills, level, hunters, gold, bank_before,
## bank_after, nights_after. `to_black`: fade the scene behind to black.
func show_results(d: Dictionary, to_black: bool) -> void:
	data = d
	active = true
	_choosing = false
	visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_fill()
	UiKit.pop_in(_panel)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_backdrop, "modulate:a", 0.35, 0.25)
	if to_black:
		_tween.tween_interval(1.1)
		_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.45)
		_tween.tween_callback(func() -> void: blacked_out.emit())
		_tween.tween_interval(0.2)
	else:
		_tween.tween_interval(0.5)
	_tween.tween_callback(_open_choice)


func _open_choice() -> void:
	_choosing = true
	_fight_btn.disabled = false
	_keep_btn.disabled = false
	_fight_btn.grab_focus()


func _input(event: InputEvent) -> void:
	if not active or not _choosing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_choose(false)


func _choose(keep_fighting: bool) -> void:
	if not _choosing:
		return
	_choosing = false
	active = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.2)
	_tween.tween_property(_backdrop, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN_OUT)
	_tween.chain().tween_callback(func() -> void: visible = false)
	chosen.emit(keep_fighting)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _fill() -> void:
	for c in _box.get_children():
		c.queue_free()
	var d := data
	var title := "THE BEAST IS DEAD" if d["victory"] else ("You withdrew" if d.get("withdrew", false) else "The party fell")
	var t := UiKit.label(title, 58, UiKit.GOLD if d["victory"] else Color(0.95, 0.85, 0.82))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(t)
	var sub := UiKit.label("Night %d" % d["night"], 24, UiKit.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 46)
	grid.add_theme_constant_override("v_separation", 4)
	var center := CenterContainer.new()
	center.add_child(grid)
	_box.add_child(center)
	var tm: float = d["time"]
	for pair in [["Survived", "%02d:%02d" % [int(tm) / 60, int(tm) % 60]], ["Kills", str(d["kills"])],
			["Level", str(d["level"])], ["Hunters", "%d / 4" % d["hunters"]]]:
		var cell := VBoxContainer.new()
		var k := UiKit.label(pair[0], 20, UiKit.DIM)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var v := UiKit.label(pair[1], 34)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(k)
		cell.add_child(v)
		grid.add_child(cell)

	_box.add_child(HSeparator.new())
	# The payoff: gold earned rolls up, then pours into the bank.
	var earned := UiKit.label("", 36, UiKit.GOLD)
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(earned)
	UiKit.roll(earned, 0, d["gold"], "Gold earned  +%d", 0.8, 0.3)
	var bank := UiKit.label("", 26, UiKit.GOLD.lerp(Color.WHITE, 0.3))
	bank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(bank)
	UiKit.roll(bank, d["bank_before"], d["bank_after"], "Banked  %d", 0.8, 1.2)
	if d["victory"]:
		var n := UiKit.label("", 26, Color(0.82, 0.74, 1.0))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(n)
		UiKit.roll(n, d["nights_after"] - 1, d["nights_after"], "Nights survived  %d", 0.3, 2.0)
	var unlock := UiKit.label("Next unlock: a new hero  (coming soon)", 20, UiKit.DIM)
	unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(unlock)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	_box.add_child(row)
	var won: bool = d["victory"] or d.get("withdrew", false)
	_fight_btn = UiKit.button("KEEP FIGHTING" if won else "TRY AGAIN", true, Vector2(300, 72))
	_fight_btn.pressed.connect(func() -> void: _choose(true))
	_fight_btn.disabled = true
	row.add_child(_fight_btn)
	_keep_btn = UiKit.button("RETURN TO THE KEEP", false, Vector2(330, 72))
	_keep_btn.pressed.connect(func() -> void: _choose(false))
	_keep_btn.disabled = true
	row.add_child(_keep_btn)
	var keys := UiKit.label("Enter: %s      Esc: return to the Keep" % ("keep fighting" if won else "try again"), 18, UiKit.DIM)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(keys)
