extends RefCounted
## Shared look and feel for menus: buttons, labels, panels and small motions,
## so every screen matches (campfire, results, pause, settings).
##
## Motion follows the research notes (claude/ui-research.md): quick ease-out
## on the way in, hover = slightly bigger with a gold edge, press = a little
## squash, nothing longer than about 0.4 s.

const GOLD := Color(1.0, 0.85, 0.3)
const TEXT := Color(0.95, 0.9, 0.82)
const DIM := Color(0.55, 0.52, 0.5)
const PANEL_BG := Color(0.07, 0.045, 0.045, 0.94)
const EDGE := Color(0.75, 0.6, 0.4, 0.8)


static func label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A menu button. Primary buttons are bigger, with a gold edge even at rest.
static func button(text: String, primary := false, min_size := Vector2(250, 72)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size * (1.12 if primary else 1.0)
	b.add_theme_font_size_override("font_size", 32 if primary else 26)
	b.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.03, 0.03, 0.85 if state in ["hover", "focus"] else 0.72)
		var lit: bool = state in ["hover", "focus", "pressed"]
		st.border_color = GOLD if lit or primary else EDGE
		if state == "disabled":
			st.border_color = Color(0.4, 0.38, 0.36, 0.5)
			st.bg_color = Color(0.05, 0.03, 0.03, 0.5)
		st.set_border_width_all((4 if primary else 3) if lit else 2)
		st.set_corner_radius_all(6)
		st.content_margin_left = 18
		st.content_margin_right = 18
		b.add_theme_stylebox_override(state, st)
	b.add_theme_color_override("font_color", GOLD if primary else TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", DIM)
	juice(b)
	return b


## Hover and focus grow the button a touch; pressing squashes it.
static func juice(c: Control) -> void:
	var centre := func() -> void: c.pivot_offset = c.size * 0.5
	c.resized.connect(centre)
	var to := func(s: float, t: float) -> void:
		if not c.is_inside_tree():
			return
		var tw := c.create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(c, "scale", Vector2.ONE * s, t)
	var lift := func() -> void:
		if not (c is BaseButton and c.disabled):
			to.call(1.04, 0.1)
	var rest := func() -> void:
		to.call(1.04 if c.has_focus() else 1.0, 0.1)
	c.mouse_entered.connect(lift)
	c.mouse_exited.connect(rest)
	c.focus_entered.connect(lift)
	c.focus_exited.connect(func() -> void: to.call(1.0, 0.1))
	if c is BaseButton:
		c.button_down.connect(func() -> void: to.call(0.95, 0.06))
		c.button_up.connect(lift)


static func panel_style(edge := GOLD) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL_BG
	st.border_color = edge
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(32)
	return st


## A screen-filling dimmer with a centred panel; the panel is child 0 of the
## CenterContainer, returned as [dimmer, panel_content_vbox].
static func modal(parent: Control, dim := 0.6) -> Array:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.visible = false
	parent.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	return [shade, box]


## Fades and lifts a control into view (ease-out, ~0.2 s).
static func pop_in(c: Control, delay := 0.0) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)


## The settings toggles, saved the moment they change.
static func settings_box(box: VBoxContainer) -> Array[Control]:
	var made: Array[Control] = []
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
		made.append(c)
	return made


## Rolls a number up on a label, like a counter ticking over (Balatro-style).
static func roll(l: Label, from: int, to: int, fmt: String, seconds := 1.0, delay := 0.0) -> void:
	l.text = fmt % from
	var tw := l.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void: l.text = fmt % int(round(v)), float(from), float(to), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# A little pop when it lands.
	tw.tween_callback(func() -> void: l.pivot_offset = l.size * 0.5)
	tw.tween_property(l, "scale", Vector2.ONE * 1.18, 0.08)
	tw.tween_property(l, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_OUT)
