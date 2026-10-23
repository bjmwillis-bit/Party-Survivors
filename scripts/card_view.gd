extends Control
## One level-up card, drawn in code, with a reveal that depends on rarity:
## - common: already there
## - rare: appears after 0.5 s with a gentle blue glow
## - epic: 1 s of crackling build-up, then a purple lightning bolt strikes
##   and the card materialises
## - legendary: burns into place over 1.5 s (a reverse burn-away), and the
##   flames stay on the card
## - bond: like legendary plus lightning, on a card split diagonally into the
##   two heroes' colours
## Placeholder visuals until proper animations are made in Blender.

signal picked(index: int)

const SIZE := Vector2(340, 230)
const HeroData := preload("res://scripts/hero_data.gd")
const PARTY_COLOR := Color(0.55, 0.6, 0.7)


## A card's colour comes from its hero (by name), or grey for the party.
static func hero_color(hero_name: String) -> Color:
	for k in HeroData.HEROES:
		if HeroData.HEROES[k]["name"] == hero_name:
			return HeroData.HEROES[k]["accent"]
	return PARTY_COLOR
const RARITY_COLORS := {
	"common": Color(0.78, 0.78, 0.78),
	"rare": Color(0.3, 0.6, 1.0),
	"epic": Color(0.72, 0.32, 1.0),
	"legendary": Color(1.0, 0.75, 0.2),
	"bond": Color(1.0, 0.8, 0.25),
}
const REVEAL_DELAY := {"common": 0.0, "rare": 0.5, "epic": 1.0, "legendary": 1.5, "bond": 1.5}

var index := 0
var card: Dictionary = {}
var revealed := false # clickable once true

var _t := 0.0
var _delay := 0.0
var _front: Control # draws over the text (burn cover, lightning, flames)
var _labels: Array = []
var _hover := false


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(card_index: int, data: Dictionary) -> void:
	index = card_index
	card = data
	_t = 0.0
	_delay = REVEAL_DELAY.get(rarity(), 0.0)
	revealed = _delay <= 0.0
	for l in _labels:
		l.queue_free()
	_labels.clear()
	if _front != null:
		_front.queue_free()

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 14
	box.offset_bottom = -12
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_labels.append(box)

	var lv := "   ·   Lv %d/%d" % [int(card.get("level", 1)), int(card["max"])] if int(card["max"]) > 1 else ""
	var top := _label("[%d]   %s%s" % [index + 1, String(card["hero"]).to_upper(), lv], 18)
	top.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	box.add_child(top)
	var title := _label(card["title"], 28)
	title.add_theme_color_override("font_color", RARITY_COLORS.get(rarity(), Color.WHITE).lerp(Color.WHITE, 0.35))
	box.add_child(title)
	var desc := _label(card["desc"], 19)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	var tag := _label(rarity().to_upper(), 15)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.add_theme_color_override("font_color", RARITY_COLORS.get(rarity(), Color.WHITE))
	box.add_child(tag)

	_front = Control.new()
	_front.set_anchors_preset(Control.PRESET_FULL_RECT)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)
	queue_redraw()


func rarity() -> String:
	return String(card.get("rarity", "common"))


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_t += delta
	if not revealed and _t >= _delay:
		revealed = true
	# Hide the text until the card has (mostly) arrived.
	var text_alpha := 1.0
	match rarity():
		"rare":
			text_alpha = clampf((_t - _delay) / 0.25, 0.0, 1.0)
		"epic":
			text_alpha = 1.0 if _t >= _delay else 0.0
	for l in _labels:
		l.modulate.a = text_alpha
	# A little pop in size as epics land.
	var s := 1.0
	if rarity() == "epic" and _t >= _delay:
		s = 1.0 + 0.12 * maxf(0.0, 1.0 - (_t - _delay) / 0.2)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * s
	queue_redraw()
	if _front != null:
		_front.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if revealed:
			picked.emit(index)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false


# --- Drawing: the card itself (under the text) ------------------------------

func _draw() -> void:
	var r := rarity()
	var rect := Rect2(Vector2.ZERO, size)
	var rc: Color = RARITY_COLORS.get(r, Color.WHITE)
	var shown := _shown_amount()
	if shown <= 0.0 and r in ["rare", "epic"]:
		_draw_buildup(rect, rc)
		return

	# Glow behind the card (rare and up), gently pulsing.
	if r != "common":
		var pulse := 0.6 + 0.4 * sin(_t * 3.0)
		var layers := 6 if r in ["legendary", "bond"] else 4
		for k in layers:
			var grow := 4.0 + k * 5.0
			var a := (0.16 - k * 0.022) * pulse * shown
			draw_rect(rect.grow(grow), Color(rc.r, rc.g, rc.b, maxf(a, 0.0)))

	# Body: hero colour, or two heroes split diagonally for bonds.
	if r == "bond":
		var a: Color = hero_color(card["heroes"][0]).darkened(0.45)
		var b: Color = hero_color(card["heroes"][1]).darkened(0.45)
		var tl := Vector2.ZERO
		var tr := Vector2(size.x, 0)
		var bl := Vector2(0, size.y)
		var br := size
		draw_colored_polygon(PackedVector2Array([tl, tr, bl]), Color(a.r, a.g, a.b, shown))
		draw_colored_polygon(PackedVector2Array([tr, br, bl]), Color(b.r, b.g, b.b, shown))
		draw_line(tr, bl, Color(1, 0.9, 0.6, shown), 3.0)
	else:
		var hc: Color = hero_color(card["hero"]).darkened(0.55)
		draw_rect(rect, Color(hc.r, hc.g, hc.b, 0.95 * shown))

	# Rarity border.
	var width := 3.0
	if r in ["epic", "legendary", "bond"]:
		width = 5.0
	if _hover and revealed:
		width += 2.0
	draw_rect(rect, Color(rc.r, rc.g, rc.b, shown), false, width)


## How visible the card body is (0 to 1) at this moment of the reveal.
func _shown_amount() -> float:
	match rarity():
		"rare":
			return clampf((_t - _delay) / 0.25, 0.0, 1.0)
		"epic":
			return 1.0 if _t >= _delay else 0.0
	return 1.0


## Before a rare or epic arrives: a faint outline, and crackles for epics.
func _draw_buildup(rect: Rect2, rc: Color) -> void:
	var a := 0.15 + 0.1 * sin(_t * 10.0)
	draw_rect(rect, Color(rc.r, rc.g, rc.b, a), false, 2.0)
	if rarity() == "epic":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_t * 20.0) + index * 97
		var sparks := int(2 + 10 * clampf(_t / _delay, 0.0, 1.0))
		for k in sparks:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var q := p + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
			draw_line(p, q, Color(0.85, 0.6, 1.0, 0.8), 2.0)


# --- Drawing: effects over the text ------------------------------------------

func _draw_front() -> void:
	var r := rarity()
	var f := _front
	if r == "epic" or r == "bond":
		# The strike: a jagged bolt from above, right as the card lands.
		var since := _t - (_delay - 0.12 if r == "epic" else _delay * 0.55)
		if since >= 0.0 and since < 0.25:
			var col := Color(0.85, 0.6, 1.0) if r == "epic" else Color(1.0, 0.95, 0.7)
			_bolt(f, Vector2(size.x * 0.5, -700.0), size * 0.5, col, 1.0 - since / 0.25)
			if since < 0.08:
				f.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.6))
	if r == "legendary" or r == "bond":
		var burn := clampf(_t / _delay, 0.0, 1.0)
		# Unburnt part on top, shrinking upward: the card is revealed from the
		# bottom, like a burn-away played in reverse.
		var edge := size.y * (1.0 - burn)
		if burn < 1.0:
			f.draw_rect(Rect2(0, 0, size.x, edge), Color(0.05, 0.04, 0.03, 1.0))
			_flame_row(f, edge, 1.0, 26)
		# The flames stay along the bottom and sides once revealed.
		if burn >= 1.0:
			_flame_row(f, size.y, 0.8, 18)
			_flame_side(f, 0.0)
			_flame_side(f, size.x)


func _bolt(f: Control, from: Vector2, to: Vector2, col: Color, alpha: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = index * 13 + int(_t * 30.0)
	var pts := PackedVector2Array()
	var steps := 10
	for k in steps + 1:
		var t := float(k) / steps
		var p := from.lerp(to, t)
		if k > 0 and k < steps:
			p.x += rng.randf_range(-40.0, 40.0)
		pts.append(p)
	f.draw_polyline(pts, Color(col.r, col.g, col.b, alpha), 7.0)
	f.draw_polyline(pts, Color(1, 1, 1, alpha), 2.5)


## A row of flickering flames along a horizontal line at height `y`.
func _flame_row(f: Control, y: float, strength: float, count: int) -> void:
	for k in count:
		var x := (k + 0.5) * size.x / count
		var h := (10.0 + 14.0 * absf(sin(_t * 9.0 + k * 1.7))) * strength
		var w := size.x / count * 0.9
		f.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, y), Vector2(x + w * 0.5, y), Vector2(x, y - h)]),
			Color(1.0, 0.45, 0.05, 0.85))
		f.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.25, y), Vector2(x + w * 0.25, y), Vector2(x, y - h * 0.55)]),
			Color(1.0, 0.9, 0.3, 0.9))


func _flame_side(f: Control, x: float) -> void:
	var count := 8
	for k in count:
		var y := (k + 0.5) * size.y / count
		var h := 6.0 + 8.0 * absf(sin(_t * 8.0 + k * 2.3 + x))
		var dir := -1.0 if x <= 0.0 else 1.0
		f.draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - 9), Vector2(x, y + 9), Vector2(x + dir * h, y)]),
			Color(1.0, 0.5, 0.1, 0.8))
