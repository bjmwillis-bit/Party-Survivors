extends Control
## The cursor: where the player's eyes are, so it carries what they need.
##
##   - A dot where you aim.
##   - The attack ring: fills as the leader's next basic attack charges, and
##     pulses when it fires, so the rhythm is visible.
##   - Health arcs: one per hero, always in the same place, emptying as
##     they're hurt. The fill uses the same health colours as the rings on the
##     ground (green, amber, red); a thin edge in the hero's own colour says
##     who it is (gold for the leader). An arc flashes white when that hero is
##     hit, and pulses red when they're low.
##   - "Kheiron is down!" under the cursor, with an arrow pointing to them.
##
## It sits at the aim point, so it follows the mouse, or the right stick on a
## gamepad. The system cursor is hidden during a night.

const LOW := 0.3
const GOLD := Color(1.0, 0.85, 0.3)
const ARC_RADIUS := 38.0
const RING_RADIUS := 18.0
const SEGMENT := deg_to_rad(104.0) # each hero's arc; the rest is gaps

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

	# The health arcs, one per hero, always in the same place.
	var heroes: Array = Game.party.heroes
	var downed_list: Array = []
	for i in heroes.size():
		var h = heroes[i]
		var mid := -PI * 0.5 + i * TAU / heroes.size()
		var a0 := mid - SEGMENT * 0.5
		var lead: bool = h.is_leader
		var width := 9.0 if lead else 6.5
		var r := ARC_RADIUS + (1.0 if lead else 0.0)
		# The track.
		draw_arc(at, r, a0, a0 + SEGMENT, 24, Color(0, 0, 0, 0.5), width + 3.0, true)
		if h.downed:
			draw_arc(at, r, a0, a0 + SEGMENT, 24, Color(0.35, 0.05, 0.05, 0.9), width, true)
			downed_list.append(h)
			continue
		var frac := clampf(h.hp / h.max_hp, 0.0, 1.0)
		var col := Color(0.35, 0.9, 0.4)
		if frac < 0.6:
			col = Color(1.0, 0.72, 0.2).lerp(Color(0.35, 0.9, 0.4), (frac - LOW) / (0.6 - LOW))
		if frac < LOW:
			var beat := 0.5 + 0.5 * sin(now * 0.012)
			col = Color(0.95, 0.15, 0.1).lerp(Color(1.0, 0.55, 0.45), beat)
		if now - h.hit_at_ms < 140:
			col = Color.WHITE
		if frac > 0.0:
			draw_arc(at, r, a0, a0 + SEGMENT * frac, 24, col, width, true)
		var edge: Color = GOLD if lead else (h.accent as Color).lerp(Color.WHITE, 0.2)
		draw_arc(at, r + width * 0.5 + 2.5, a0, a0 + SEGMENT, 24, edge, 2.5 if lead else 2.0, true)

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
