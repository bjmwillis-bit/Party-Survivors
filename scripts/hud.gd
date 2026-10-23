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
var _danger: ColorRect
var _cursor: Control
const CursorScript := preload("res://scripts/cursor_hud.gd")
const DANGER_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.6, 1.0);
	float edge = smoothstep(0.42, 0.9, length(d));
	COLOR = vec4(0.8, 0.03, 0.03, edge * strength);
}
"""
var _pause: Control # the pause menu (Esc / Start)
var _pause_resume: Button
var _hint: Label
var _levelup_shown_ms := 0 # when the cards appeared (for the input guard)
const LEVELUP_GUARD_MS := 300
const UiKit := preload("res://scripts/ui_kit.gd")
var _gold_label: Label
var _kills
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _banner: Label
var _banner_t := 0.0
var _caption: RichTextLabel
var _caption_t := 0.0
var _caption_queue: Array = []

const KillCounterScript := preload("res://scripts/kill_counter.gd")


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

	# Boss health bar, under the timer while a boss is alive.
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.offset_left = -360
	_boss_box.offset_right = 360
	_boss_box.offset_top = 112
	_boss_box.offset_bottom = 170
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = _label(22)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = _bar(Color(0.8, 0.1, 0.08), Vector2(720, 22))
	_boss_box.add_child(_boss_bar)

	# Event banner (swarm, hunters, goblin, the beast).
	_banner = _label(48)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -700
	_banner.offset_right = 700
	_banner.offset_top = 190
	_banner.offset_bottom = 260
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	# Captions: who is speaking, and what they say (voice comes later).
	_caption = RichTextLabel.new()
	_caption.bbcode_enabled = true
	_caption.fit_content = true
	_caption.scroll_active = false
	_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.offset_left = -700
	_caption.offset_right = 700
	_caption.offset_top = -190
	_caption.offset_bottom = -136
	_caption.add_theme_font_size_override("normal_font_size", 28)
	_caption.add_theme_font_size_override("bold_font_size", 28)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.modulate.a = 0.0
	root.add_child(_caption)

	# Kill counter (top right) and gold (top left).
	_kills = KillCounterScript.new()
	_kills.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kills.offset_left = -390
	_kills.offset_right = -24
	_kills.offset_top = 24
	_kills.offset_bottom = 134
	root.add_child(_kills)
	_gold_label = _label(30)
	_gold_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_gold_label.offset_left = 28
	_gold_label.offset_top = 28
	_gold_label.offset_right = 400
	_gold_label.offset_bottom = 70
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	root.add_child(_gold_label)

	var party_box := VBoxContainer.new()
	party_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	party_box.offset_left = 24
	party_box.offset_top = -200
	party_box.offset_right = 640
	party_box.offset_bottom = -24
	party_box.alignment = BoxContainer.ALIGNMENT_END
	party_box.add_theme_constant_override("separation", 4)
	party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(party_box)
	for h in Game.party.heroes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		# A small reference panel now: the cursor carries health during play.
		var name_label := _label(19)
		name_label.text = h.hero_name
		name_label.custom_minimum_size = Vector2(100, 0)
		name_label.add_theme_color_override("font_color", h.accent.lerp(Color.WHITE, 0.3))
		var bar := _bar(Color(0.3, 0.8, 0.35), Vector2(150, 12))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var status := _label(16)
		row.add_child(name_label)
		row.add_child(bar)
		row.add_child(status)
		party_box.add_child(row)
		_rows.append({"hero": h, "bar": bar, "status": status})
	_swap_label = _label(18)
	party_box.add_child(_swap_label)

	var hint := _label(18)
	_hint = hint
	hint.text = "Move: WASD     Aim: mouse     Skills: Q / E     Ultimate: R     Swap leader: Space     Revive: stand next to a fallen hero"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -900
	hint.offset_top = -48
	hint.offset_right = -24
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate = Color(1, 1, 1, 0.7)
	root.add_child(hint)

	# Red at the screen's edge when anyone is badly hurt.
	_danger = ColorRect.new()
	_danger.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	var ds := Shader.new()
	ds.code = DANGER_SHADER
	dm.shader = ds
	_danger.material = dm
	root.add_child(_danger)
	root.move_child(_danger, 0)

	_build_skill_bar(root)
	_cursor = CursorScript.new()
	root.add_child(_cursor)
	_build_levelup(root)
	_build_pause(root)


func _process(_delta: float) -> void:
	var main = Game.main
	var t: float = Game.time_alive
	if main.final_spawned:
		_timer_label.text = "∞"
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	else:
		_timer_label.text = "%02d:%02d" % [int(t) / 60, int(t) % 60]
	var swarm := "     SWARM %ds" % ceili(main.swarm_time) if main.swarm_time > 0.0 else ""
	_info_label.text = "Level %d%s" % [main.level, swarm]
	_kills.kills = main.locked_kills if main.locked_kills >= 0 else Game.kills
	_gold_label.text = "Gold  %d" % Game.gold
	_update_boss_bar()
	if _banner_t > 0.0:
		_banner_t -= _delta
		_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	_tick_caption(_delta)
	_update_danger()
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
				for slot in ["q", "e", "r"]:
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
				_on_card_picked(k)
				break
		if Input.is_action_just_pressed("reroll"):
			main.reroll_cards()
		if Input.is_action_just_pressed("banish"):
			_toggle_banish()
	if Input.is_action_just_pressed("pause") and main.is_night() and not main.ended and not main.choosing:
		set_paused(not _pause.visible)
	# The controls hint steps aside after the first minute.
	if Game.time_alive > 60.0 and _hint.modulate.a > 0.0:
		_hint.modulate.a = maxf(0.0, _hint.modulate.a - _delta * 0.5)


# --- Bosses, banners and the tally --------------------------------------------

func _update_boss_bar() -> void:
	var E = Game.enemies
	var i: int = E.find_kind(E.FINAL_BOSS)
	var title := "THE BEAST"
	if i < 0:
		i = E.find_kind(E.MINIBOSS)
		title = "HUNTER"
	_boss_box.visible = i >= 0
	if i >= 0:
		_boss_name.text = title
		_boss_bar.value = clampf(E.hp[i] / maxf(Game.main.boss_max_hp, 1.0), 0.0, 1.0)


func banner(text: String, color := Color.WHITE, seconds := 2.0) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_t = seconds
	_banner.modulate.a = 1.0


## Shows a spoken line at the bottom of the screen. Lines queue up, so a
## reply waits for the line before it.
func caption(speaker: String, text: String, color: Color, seconds := 2.6) -> void:
	if not Game.settings.get("captions", true):
		return
	_caption_queue.append([speaker, text, color, seconds])


func _tick_caption(delta: float) -> void:
	if _caption_t > 0.0:
		_caption_t -= delta
		_caption.modulate.a = clampf(_caption_t / 0.35, 0.0, 1.0)
		return
	if _caption_queue.is_empty():
		return
	var c: Array = _caption_queue.pop_front()
	var col: Color = c[2]
	_caption.text = "[center][b][color=#%s]%s:[/color][/b]  %s[/center]" % [col.lerp(Color.WHITE, 0.4).to_html(false), c[0], c[1]]
	_caption_t = c[3]
	_caption.modulate.a = 1.0


func add_claw() -> void:
	_kills.add_claw()


func strike_tally() -> void:
	_kills.strike()


# --- Leader's skill bar ------------------------------------------------------

func _build_skill_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -420
	bar.offset_right = 420
	bar.offset_top = -120
	bar.offset_bottom = -24
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	for slot in ["q", "e", "r"]:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(260, 90)
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

const CardScript := preload("res://scripts/card_view.gd")

var _row: HBoxContainer
var _reroll_btn: Button
var _banish_btn: Button
var _levelup_hint: Label
var _banish_mode := false


func show_levelup(level: int, choices: Array, ult_level: bool) -> void:
	if ult_level:
		_levelup_title.text = "Level %d  —  ULTIMATE UPGRADE" % level
		_levelup_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		_levelup_title.text = "Level %d  —  choose one" % level
		_levelup_title.add_theme_color_override("font_color", Color.WHITE)
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for i in choices.size():
		_add_card(i, choices[i])
	_banish_mode = false
	_update_levelup_buttons()
	_levelup.visible = true
	_levelup_shown_ms = Time.get_ticks_msec()


## Swaps one card for a new one (after a banish), replaying its reveal.
func replace_card(i: int, card) -> void:
	if i < 0 or i >= _cards.size():
		return
	if card == null:
		_cards[i].visible = false
		return
	_cards[i].setup(i, card)
	_banish_mode = false
	_update_levelup_buttons()


func card_ready(i: int) -> bool:
	return i >= 0 and i < _cards.size() and _cards[i].visible and _cards[i].revealed


func hide_levelup() -> void:
	_levelup.visible = false


func _add_card(i: int, data: Dictionary) -> void:
	var c = CardScript.new()
	_row.add_child(c)
	c.setup(i, data)
	c.picked.connect(_on_card_picked)
	_cards.append(c)


func _on_card_picked(i: int) -> void:
	# A short guard, so a held key or a stray click can't pick by accident.
	if Time.get_ticks_msec() - _levelup_shown_ms < LEVELUP_GUARD_MS and not Game.main.autopilot:
		return
	if _banish_mode:
		Game.main.banish_card(i)
	else:
		Game.main.choose_upgrade(i)


func _update_levelup_buttons() -> void:
	var u = Game.main.upgrades
	_reroll_btn.text = "Reroll  (%d)  [F]" % u.rerolls_left
	_reroll_btn.disabled = u.rerolls_left <= 0
	_banish_btn.text = ("Click a card to banish it" if _banish_mode else "Banish  (%d)  [B]" % u.banishes_left)
	_banish_btn.disabled = u.banishes_left <= 0
	_levelup_hint.text = "Banished cards won't appear again this run." if _banish_mode else ""


func _build_levelup(root: Control) -> void:
	_levelup = _overlay(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 26)
	_levelup.get_child(1).add_child(box)
	_levelup_title = _label(40)
	_levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_levelup_title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 30)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(260, 52)
	_reroll_btn.add_theme_font_size_override("font_size", 22)
	_reroll_btn.pressed.connect(func() -> void: Game.main.reroll_cards())
	buttons.add_child(_reroll_btn)
	_banish_btn = Button.new()
	_banish_btn.custom_minimum_size = Vector2(300, 52)
	_banish_btn.add_theme_font_size_override("font_size", 22)
	_banish_btn.pressed.connect(_toggle_banish)
	buttons.add_child(_banish_btn)
	_levelup_hint = _label(18)
	_levelup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_levelup_hint)


func _toggle_banish() -> void:
	if Game.main.upgrades.banishes_left <= 0:
		return
	_banish_mode = not _banish_mode
	_update_levelup_buttons()


# --- End of run --------------------------------------------------------------

## The screen's edge reddens when anyone drops below 30%, pulsing harder the
## lower they are.
func _update_danger() -> void:
	var lowest := 1.0
	for h in Game.party.heroes:
		if not h.downed:
			lowest = minf(lowest, h.hp / h.max_hp)
	var s := 0.0
	if lowest < 0.3 and Game.main.is_night() and not Game.main.ended:
		var depth := (0.3 - lowest) / 0.3
		var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() * (0.006 + 0.008 * depth))
		s = (0.25 + 0.45 * depth) * (0.6 + 0.4 * beat)
	(_danger.material as ShaderMaterial).set_shader_parameter("strength", s)


## Fades the whole HUD (it's a CanvasLayer, so its root Control fades).
func fade_to(alpha: float, seconds: float, from := -1.0) -> void:
	var r: Control = get_child(0)
	if from >= 0.0:
		r.modulate.a = from
	create_tween().tween_property(r, "modulate:a", alpha, seconds)


# --- Pause menu --------------------------------------------------------------

func set_paused(on: bool) -> void:
	_pause.visible = on
	get_tree().paused = on
	if on:
		UiKit.pop_in(_pause.get_child(0).get_child(0))
		_pause_resume.grab_focus()


func _build_pause(root: Control) -> void:
	var m: Array = UiKit.modal(root, 0.55)
	_pause = m[0]
	var box: VBoxContainer = m[1]
	var title := UiKit.label("Paused", 46, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_pause_resume = UiKit.button("RESUME", true, Vector2(380, 66))
	_pause_resume.pressed.connect(func() -> void: set_paused(false))
	box.add_child(_pause_resume)
	box.add_child(HSeparator.new())
	UiKit.settings_box(box)
	box.add_child(HSeparator.new())
	var leave := UiKit.button("RETURN TO THE KEEP", false, Vector2(380, 62))
	leave.tooltip_text = "Ends this night. The gold you've found is kept."
	leave.pressed.connect(func() -> void:
		_pause.visible = false
		Game.main.withdraw())
	box.add_child(leave)
	var note := UiKit.label("Ends this night; you keep the gold found so far.", 18, UiKit.DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)


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
