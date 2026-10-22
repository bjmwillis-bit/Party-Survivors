extends CanvasLayer
## On-screen information: run timer, level and XP, the party's health,
## swap readiness, the level-up cards and the end-of-run screen.
## Built in code for the prototype; a styled UI comes later.

var _timer_label: Label
var _info_label: Label
var _xp_bar: ProgressBar
var _swap_label: Label
var _skill_slots: Array = [] # the leader's Q and E boxes
var _rows: Array = []
var _levelup: Control
var _levelup_title: Label
var _cards: Array = []
var _end: Control
var _end_title: Label
var _end_stats: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps working while the game is paused
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_xp_bar = _bar(Color(0.4, 0.85, 1.0), Vector2(0, 14))
	_xp_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_xp_bar.offset_bottom = 14
	root.add_child(_xp_bar)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 22
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_timer_label = _label(44)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_timer_label)
	_info_label = _label(22)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_info_label)

	var party_box := VBoxContainer.new()
	party_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	party_box.offset_left = 24
	party_box.offset_top = -200
	party_box.offset_right = 640
	party_box.offset_bottom = -24
	party_box.alignment = BoxContainer.ALIGNMENT_END
	party_box.add_theme_constant_override("separation", 8)
	party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(party_box)
	for h in Game.party.heroes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := _label(24)
		name_label.text = h.hero_name
		name_label.custom_minimum_size = Vector2(130, 0)
		name_label.add_theme_color_override("font_color", h.accent.lerp(Color.WHITE, 0.3))
		var bar := _bar(Color(0.3, 0.8, 0.35), Vector2(220, 20))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var status := _label(20)
		row.add_child(name_label)
		row.add_child(bar)
		row.add_child(status)
		party_box.add_child(row)
		_rows.append({"hero": h, "bar": bar, "status": status})
	_swap_label = _label(22)
	party_box.add_child(_swap_label)

	var hint := _label(18)
	hint.text = "Move: WASD     Aim: mouse     Skills: Q / E     Swap leader: Space     Revive: stand next to a fallen hero"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -900
	hint.offset_top = -48
	hint.offset_right = -24
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate = Color(1, 1, 1, 0.7)
	root.add_child(hint)

	_build_skill_bar(root)
	_build_levelup(root)
	_build_end(root)


func _process(_delta: float) -> void:
	var main = Game.main
	var t: float = Game.time_alive
	_timer_label.text = "%02d:%02d" % [int(t) / 60, int(t) % 60]
	_info_label.text = "Level %d     Kills %d" % [main.level, Game.kills]
	_xp_bar.value = float(main.xp_have) / float(main.xp_need)

	for r in _rows:
		var h = r["hero"]
		r["bar"].value = h.hp / h.max_hp
		var bits := PackedStringArray()
		if h.downed:
			bits.append("DOWN — stand close to revive (%d%%)" % int(100.0 * h.revive_progress / Game.party.revive_time))
		else:
			if h.is_leader:
				bits.append("LEADING")
			if h.kind == "solenne" and h.contempt > 0:
				bits.append("Contempt %d" % h.contempt)
			if not h.is_leader:
				for slot in ["q", "e"]:
					if not h.skill_is_passive(slot):
						var left: float = h.cooldown[slot]
						bits.append("%s %s" % [slot.to_upper(), "ready" if left <= 0.0 else "%ds" % ceili(left)])
		r["status"].text = "   ".join(bits)
		r["bar"].modulate = Color(1, 1, 1, 0.35) if h.downed else Color.WHITE

	var cd: float = Game.party.swap_timer
	_swap_label.text = "Swap ready" if cd <= 0.0 else "Swap in %.1fs" % cd
	_swap_label.modulate = Color(1.0, 0.85, 0.4) if cd <= 0.0 else Color(1, 1, 1, 0.5)
	_update_skill_bar()

	if _levelup.visible:
		for k in 3:
			if Input.is_action_just_pressed("pick_%d" % (k + 1)):
				main.choose_upgrade(k)
				break
	elif _end.visible and Input.is_action_just_pressed("restart"):
		main.restart()


# --- Leader's skill bar ------------------------------------------------------

func _build_skill_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -330
	bar.offset_right = 330
	bar.offset_top = -120
	bar.offset_bottom = -24
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	for slot in ["q", "e"]:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(300, 90)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
		style.border_color = Color(1.0, 0.85, 0.4)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.content_margin_left = 12
		style.content_margin_right = 12
		panel.add_theme_stylebox_override("panel", style)
		var label := _label(22)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(label)
		bar.add_child(panel)
		_skill_slots.append({"slot": slot, "panel": panel, "style": style, "label": label})


func _update_skill_bar() -> void:
	var l = Game.party.leader()
	if l == null:
		return
	for s in _skill_slots:
		var slot: String = s["slot"]
		var name: String = l.skill_name(slot)
		var style: StyleBoxFlat = s["style"]
		if l.skill_is_passive(slot):
			s["label"].text = "[%s]  %s\n(passive)" % [slot.to_upper(), name]
			s["panel"].modulate = Color(1, 1, 1, 0.6)
			style.border_color = Color(0.6, 0.6, 0.6)
			continue
		var left: float = l.cooldown[slot]
		if left <= 0.0:
			s["label"].text = "[%s]  %s\nready" % [slot.to_upper(), name]
			s["panel"].modulate = Color.WHITE
			style.border_color = Color(1.0, 0.85, 0.4)
		else:
			s["label"].text = "[%s]  %s\n%.1fs" % [slot.to_upper(), name, left]
			s["panel"].modulate = Color(1, 1, 1, 0.55)
			style.border_color = Color(0.4, 0.4, 0.4)


# --- Level up ----------------------------------------------------------------

func show_levelup(level: int, choices: Array) -> void:
	_levelup_title.text = "Level %d — choose one" % level
	for i in _cards.size():
		var b: Button = _cards[i]
		if i < choices.size():
			var c: Dictionary = choices[i]
			b.text = "[%d]  %s\n%s\n\n%s" % [i + 1, c["hero"], c["title"], c["desc"]]
			b.visible = true
		else:
			b.visible = false
	_levelup.visible = true
	_cards[0].grab_focus()


func hide_levelup() -> void:
	_levelup.visible = false


func _build_levelup(root: Control) -> void:
	_levelup = _overlay(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	_levelup.get_child(1).add_child(box)
	_levelup_title = _label(40)
	_levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_levelup_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(340, 200)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_card_pressed.bind(i))
		row.add_child(b)
		_cards.append(b)


func _on_card_pressed(i: int) -> void:
	Game.main.choose_upgrade(i)


# --- End of run --------------------------------------------------------------

func show_end(victory: bool, time_alive: float, kills: int, level: int) -> void:
	_end_title.text = "You held the line!" if victory else "The party fell"
	var subtitle := "The boss arrives here in milestone 2." if victory else "Try swapping Cenhelm to the front when the crowd closes in."
	_end_stats.text = "Survived %02d:%02d     Kills %d     Level %d\n\n%s" % [int(time_alive) / 60, int(time_alive) % 60, kills, level, subtitle]
	_levelup.visible = false
	_end.visible = true


func _build_end(root: Control) -> void:
	_end = _overlay(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	_end.get_child(1).add_child(box)
	_end_title = _label(56)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_stats = _label(26)
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_stats)
	var again := Button.new()
	again.text = "Run again  [R]"
	again.custom_minimum_size = Vector2(320, 64)
	again.add_theme_font_size_override("font_size", 26)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func() -> void: Game.main.restart())
	box.add_child(again)


# --- Helpers -----------------------------------------------------------------

## A dimmed full-screen layer with a centred container (child index 1).
func _overlay(root: Control) -> Control:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	root.add_child(o)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(center)
	return o


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(fill: Color, min_size: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = min_size
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b
