extends Control
## The cursor: where the player's eyes are.
##
##   - A dot where you aim.
##   - The attack ring: fills as the leader's next basic attack charges, and
##     pulses when it fires, so the rhythm is visible.
##   - "Kheiron is down!" under the cursor, with an arrow pointing to them.
##
## It sits at the aim point, so it follows the mouse, or the right stick on a
## gamepad. The system cursor is hidden during a night.

const LOW := 0.3
const GOLD := Color(1.0, 0.85, 0.3)
const ARC_RADIUS := 20.0 # where the downed notice and its arrow sit
const RING_RADIUS := 18.0

var _font: Font
var _was_hidden := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func _process(_delta: float) -> void:
	_update_system_cursor()
	queue_redraw()


func _exit_tree() -> void:
	if _was_hidden:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Hide the system cursor only while actually fighting (menus need it).
func _update_system_cursor() -> void:
	var m = Game.main
	var hide: bool = m != null and m.is_night() and not m.ended and not m.choosing and not get_tree().paused and not m.autopilot
	if hide != _was_hidden:
		_was_hidden = hide
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if hide else Input.MOUSE_MODE_VISIBLE


func _draw() -> void:
	var m = Game.main
	if m == null or Game.party == null or not m.is_night() or m.ended:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at: Vector2 = cam.unproject_position(Game.party.aim_point)
	var now := Time.get_ticks_msec()
	var leader = Game.party.leader()

	# The dot.
	draw_circle(at, 3.5, Color(0, 0, 0, 0.6))
	draw_circle(at, 2.2, Color.WHITE)

	# The attack ring.
	if leader != null and not leader.downed:
		var charge: float = leader.attack_charge()
		var since: float = float(now - leader.attacked_at_ms)
		var pulse := exp(-since / 90.0)
		var r := RING_RADIUS * (1.0 + 0.35 * pulse)
		draw_arc(at, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 4.0, true)
		var ring_col := Color(1, 1, 1, 0.55).lerp(Color(1, 1, 1, 1), pulse)
		if charge >= 1.0:
			ring_col = Color(1, 1, 1, 0.9)
		if charge > 0.0:
			draw_arc(at, r, -PI * 0.5, -PI * 0.5 + TAU * charge, 40, ring_col, 2.5, true)

	# Who's down (health itself lives on the rings under the heroes).
	var downed_list: Array = []
	for h in Game.party.heroes:
		if h.downed:
			downed_list.append(h)

	# Someone is down: say who, and point the way.
	var line := 0
	for h in downed_list:
		var col: Color = (h.accent as Color).lerp(Color.WHITE, 0.35)
		var text := "%s is down!" % h.hero_name
		var size := 22
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var p := at + Vector2(-w * 0.5, ARC_RADIUS + 32.0 + line * 26.0)
		draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.85))
		draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		line += 1
		# The arrow, on the outside of the arcs.
		var where: Vector2 = cam.unproject_position(h.global_position + Vector3(0.0, 0.5, 0.0))
		var dir := where - at
		if dir.length() > ARC_RADIUS + 20.0:
			dir = dir.normalized()
			var tip := at + dir * (ARC_RADIUS + 22.0)
			var side := Vector2(-dir.y, dir.x)
			var beat := 0.6 + 0.4 * sin(now * 0.015)
			draw_colored_polygon(PackedVector2Array([tip + dir * 9.0, tip - dir * 4.0 + side * 7.0, tip - dir * 4.0 - side * 7.0]),
				Color(col.r, col.g, col.b, beat))
