extends Control
## The kill counter, drawn as a tally.
## - The number pulses as it climbs, and grows hotter in colour the higher it gets.
## - Each mini-boss killed scratches a bloody claw mark behind it (up to 4).
## - Killing the final boss strikes through the lot, like the fifth stroke of
##   a tally, and locks the score.

var kills := 0
var claws := 0
var struck := false

var _shown := 0
var _pulse := 0.0
var _strike_t := 0.0
var _claw_t: Array = [] # time since each claw appeared (for its scratch-in)


func _init() -> void:
	custom_minimum_size = Vector2(360, 110)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func add_claw() -> void:
	claws = mini(claws + 1, 4)
	_claw_t.append(0.0)


func strike() -> void:
	struck = true
	_strike_t = 0.0


func _process(delta: float) -> void:
	if kills > _shown:
		# Pulse on new kills, but not every single frame in a big crowd.
		if _pulse < 0.3:
			_pulse = 1.0
		_shown = kills
	_pulse = maxf(0.0, _pulse - delta * 5.0)
	for i in _claw_t.size():
		_claw_t[i] += delta
	if struck:
		_strike_t += delta
	queue_redraw()


func _heat() -> Color:
	# White, then gold, orange and blood red as the count climbs.
	if _shown < 300:
		return Color(1, 1, 1)
	if _shown < 1000:
		return Color(1.0, 0.85, 0.4)
	if _shown < 2500:
		return Color(1.0, 0.55, 0.2)
	return Color(1.0, 0.2, 0.15)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var center := size * 0.5

	# Claw marks behind the number: three slanted scratches each.
	for c in claws:
		var appear: float = clampf(_claw_t[c] / 0.25, 0.0, 1.0)
		var x0 := 40.0 + c * 70.0
		for s in 3:
			var top := Vector2(x0 + s * 14.0 + 22.0, 8.0)
			var bottom := Vector2(x0 + s * 14.0 - 6.0, size.y - 8.0)
			draw_line(top, top.lerp(bottom, appear), Color(0.55, 0.02, 0.02, 0.85), 7.0)
			draw_line(top, top.lerp(bottom, appear), Color(0.85, 0.08, 0.05, 0.9), 3.0)
		# A drip of blood under each mark.
		if appear >= 1.0:
			draw_circle(Vector2(x0 + 4.0, size.y - 4.0), 3.5, Color(0.6, 0.02, 0.02, 0.9))

	# The number.
	var digits := str(_shown).length()
	var font_size := int(46 + mini(digits, 5) * 3 + _pulse * 10.0)
	var text := str(_shown)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(center.x - w * 0.5, center.y + font_size * 0.35)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _heat())
	draw_string_outline(font, Vector2(center.x - 22, size.y - 2), "KILLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color.BLACK)
	draw_string(font, Vector2(center.x - 22, size.y - 2), "KILLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))

	# The final stroke: a slash through everything.
	if struck:
		var p := clampf(_strike_t / 0.3, 0.0, 1.0)
		var a := Vector2(10.0, size.y * 0.8)
		var b := Vector2(size.x - 10.0, size.y * 0.2)
		draw_line(a, a.lerp(b, p), Color(0.5, 0.0, 0.0), 12.0)
		draw_line(a, a.lerp(b, p), Color(0.95, 0.1, 0.05), 5.0)
