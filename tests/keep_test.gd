extends SceneTree
## Checks the Keep: that enemies come in through the gates instead of piling
## up against the walls, and that followers keep up through the gates.
##
##   MODE=camp  godot --headless --fixed-fps 60 --path . --script res://tests/keep_test.gd
##   MODE=roam  ...
##
## camp: the leader stands by the fire all night. Every 10 s it prints how
##   many enemies are inside the walls, how many are stuck (against the
##   outside of a wall away from the gates, not attacking, not moving), and
##   the party's health.
## roam: the leader walks out of the front gate and circles the Keep, then
##   walks back in. Prints how often a follower was left far behind (more
##   than the leash plus 3 m), and whether anyone got stuck on a wall.

var _frames := 0
var _mode := "camp"
var _stuck_samples := 0
var _stuck_total := 0
var _inside_total := 0
var _samples := 0
var _far := {}
var _last_pos := {}
var _still_far := {}
var _prev_pos := PackedVector2Array()
var _prev_age := PackedFloat32Array()
var _stuck_now := 0
var _stuck_peak := 0
var _stuck_where: Array = [] # positions of the stuck ones at the last check (STUCK_LOG=1 prints them)


func _initialize() -> void:
	var game = root.get_node("Game")
	game.skip_camp = true
	_mode = OS.get_environment("MODE") if OS.has_environment("MODE") else "camp"
	var picked := OS.get_environment("PARTY")
	if picked != "":
		game.party_override = Array(picked.split(","))
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	var main = current_scene
	if main == null or not main.has_method("choose_upgrade"):
		if _frames > 300:
			print("RESULT: FAILED - the main scene did not load")
			return true
		return false
	var game = root.get_node("Game")
	if game.party == null or game.keep == null:
		return false
	game.hitstop_enabled = false
	game.saving_enabled = false
	main.autopilot = true
	if main.choosing:
		main.choose_upgrade(0)
	var t: float = game.time_alive
	var leader = game.party.leader()
	var keep = game.keep
	var lxz := Vector2(leader.position.x, leader.position.z)

	if _mode == "camp":
		main.autopilot_dir = Vector3.ZERO
	else:
		# Out of the front gate, round the Keep twice, then back in to the fire.
		var goal: Vector2
		if t < 60.0:
			goal = Vector2(0.0, 18.0) if lxz.y < 16.0 else Vector2(18.0, 18.0)
		elif t < 140.0:
			var a := (t - 60.0) / 40.0 * TAU + PI * 0.25
			goal = Vector2(sin(a), cos(a)) * 21.0
		else:
			goal = Vector2(0.0, 2.0)
		var nxt: Vector2 = keep.next_point(lxz, goal)
		var d := nxt - lxz
		main.autopilot_dir = Vector3(d.x, 0.0, d.y).normalized() if d.length() > 0.5 else Vector3.ZERO
		leader.cast("q")

	# Every half second: count enemies inside, and stuck against the walls.
	if _frames % 30 == 0:
		_samples += 1
		var inside := 0
		var stuck := 0
		var E = game.enemies
		for i in E.count:
			var p: Vector2 = E.pos[i]
			if absf(p.x) < keep.HALF - keep.THICK and absf(p.y) < keep.HALF - keep.THICK:
				inside += 1
			elif _against_wall(keep, p) and E.kind[i] != E.GOBLIN:
				stuck += 1
		# Really stuck: by a wall, not attacking anyone, and hardly moved in the
		# last half second (the same enemy: its age went up by half a second).
		stuck = 0
		_stuck_where.clear()
		var heroes: Array = game.party.heroes
		for i in E.count:
			if i < _prev_age.size() and absf(E.age[i] - _prev_age[i] - 0.5) < 0.02 and E.stun_t[i] <= 0.0 and E.kind[i] != E.GOBLIN:
				var p: Vector2 = E.pos[i]
				if p.distance_to(_prev_pos[i]) < 0.25 and _against_wall(keep, p):
					var near := INF
					for h in heroes:
						near = minf(near, p.distance_to(Vector2(h.position.x, h.position.z)))
					if near > 2.5:
						stuck += 1
						_stuck_where.append("(%.1f,%.1f)%s" % [p.x, p.y, E.kind[i]])
		_prev_pos = E.pos.duplicate()
		_prev_age = E.age.duplicate()
		_stuck_now = stuck
		_stuck_peak = maxi(_stuck_peak, stuck)
		_inside_total += inside
		_stuck_total += stuck
		if stuck > 0:
			_stuck_samples += 1
		for h in game.party.heroes:
			if h == leader or h.downed:
				continue
			var n: String = h.hero_name
			var hp2 := Vector2(h.position.x, h.position.z)
			if hp2.distance_to(lxz) > game.party.LEASH + 3.0:
				_far[n] = _far.get(n, 0) + 1
				# Far behind and not moving for 2 s: stuck on a wall.
				if _last_pos.has(n) and hp2.distance_to(_last_pos[n]) < 0.3:
					_still_far[n] = _still_far.get(n, 0) + 1
			_last_pos[n] = hp2
	if _frames % 600 == 0:
		var hps := []
		for h in game.party.heroes:
			hps.append("%s %d%s" % [h.hero_name, int(h.hp), " DOWN" if h.downed else ""])
		var E = game.enemies
		var inside := 0
		for i in E.count:
			var p: Vector2 = E.pos[i]
			if absf(p.x) < keep.HALF - keep.THICK and absf(p.y) < keep.HALF - keep.THICK:
				inside += 1
		print("t=%4ds leader=(%5.1f,%5.1f) enemies=%3d inside=%3d stuck=%2d kills=%4d | %s" % [int(t), lxz.x, lxz.y, E.count, inside, _stuck_now, game.kills, ", ".join(hps)])
		if OS.get_environment("STUCK_LOG") == "1" and not _stuck_where.is_empty():
			print("    stuck at: ", " ".join(_stuck_where))

	var seconds := 180.0 if _mode == "roam" else 240.0
	if main.ended or t >= seconds:
		print("RESULT %s survived=%ds kills=%d%s" % [_mode, int(t), game.kills, " WIPED" if main.ended else ""])
		print("  enemies inside on average: %.1f; stuck on a wall on average: %.2f (most at once: %d), in %d%% of checks" % [
			float(_inside_total) / maxf(1, _samples), float(_stuck_total) / maxf(1, _samples), _stuck_peak, int(100.0 * _stuck_samples / maxf(1, _samples))])
		for n in _far:
			print("  %s far behind the leader in %d%% of checks, of which not moving %d" % [n, int(100.0 * _far[n] / maxf(1, _samples)), _still_far.get(n, 0)])
		if _far.is_empty():
			print("  followers never fell far behind")
		return true
	return false


## Outside the walls, within 0.9 m of one, and not near a gate.
func _against_wall(keep, p: Vector2) -> bool:
	for g in keep.GATES:
		if p.distance_to(g["mid"]) < keep.GATE_HALF + 2.5:
			return false
	for r in keep.boxes:
		var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if p.distance_to(c) < 0.9 + 0.35:
			# Only the outside face counts (enemies inside are fine).
			return absf(p.x) >= keep.HALF - 0.1 or absf(p.y) >= keep.HALF - 0.1 or p.y < keep.TOWER_Z
	return false
