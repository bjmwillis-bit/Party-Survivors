extends SceneTree
## Compares the melee follower AI with the old "walk up and stand there"
## behaviour. The first hero in PARTY leads for the whole run (no swaps), so
## the other two are followers the whole time. A simple bot walks in circles
## and takes the first card at each level-up, as in the smoke test.
##
##   PARTY=kheiron,halvar,rhian MELEE_AI=new SECONDS=240 \
##     godot --headless --fixed-fps 60 --path . --script res://tests/follower_test.gd
##
## MELEE_AI=old turns the new behaviour off. Prints, per follower: when
## they first went down, damage taken, times downed, seconds spent downed,
## and how many enemies were touching them on average.

var _frames := 0
var _prev_hp := {}
var _was_down := {}
var _taken := {}
var _downs := {}
var _down_time := {}
var _touching := {}
var _first_down := {}
var _samples := 0


func _initialize() -> void:
	var game = root.get_node("Game")
	game.skip_camp = true
	var picked := OS.get_environment("PARTY")
	if picked != "":
		game.party_override = Array(picked.split(","))
	change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> bool:
	_frames += 1
	var main = current_scene
	if main == null or not main.has_method("choose_upgrade"):
		if _frames > 300:
			print("RESULT: FAILED - the main scene did not load")
			return true
		return false
	var game = root.get_node("Game")
	if game.party == null:
		return false
	game.hitstop_enabled = false
	game.saving_enabled = false
	game.party.melee_ai = OS.get_environment("MELEE_AI") != "old"
	var t: float = game.time_alive
	main.autopilot = true
	if fmod(t, 4.0) < 2.5:
		main.autopilot_dir = Vector3(cos(t * 0.35), 0.0, sin(t * 0.35))
	else:
		main.autopilot_dir = Vector3.ZERO
	if main.choosing:
		main.choose_upgrade(0)
	var leader = game.party.leader()
	if leader != null:
		leader.cast("q")
		leader.cast("e")

	for h in game.party.heroes:
		var n: String = h.hero_name
		if not _taken.has(n):
			_taken[n] = 0.0
			_downs[n] = 0
			_down_time[n] = 0.0
			_touching[n] = 0
			_prev_hp[n] = h.hp
			_was_down[n] = false
		if h.downed:
			_down_time[n] += 1.0 / 60.0
			if not _was_down[n]:
				_downs[n] += 1
				if not _first_down.has(n):
					_first_down[n] = t
				_taken[n] += _prev_hp[n]
		else:
			_taken[n] += maxf(0.0, _prev_hp[n] - h.hp)
		_was_down[n] = h.downed
		_prev_hp[n] = h.hp
		if _frames % 30 == 0 and not h.downed:
			_touching[n] += game.enemies.query(Vector2(h.position.x, h.position.z), 1.3).size()
	if _frames % 30 == 0:
		_samples += 1

	var seconds := float(OS.get_environment("SECONDS")) if OS.has_environment("SECONDS") else 240.0
	if main.ended or t >= seconds or _frames > int(seconds * 60.0) + 600:
		var mode := "new" if game.party.melee_ai else "old"
		print("RESULT %s party=%s survived=%ds kills=%d level=%d%s" % [mode, OS.get_environment("PARTY"), int(t), game.kills, main.level, " WIPED" if main.ended else ""])
		for h in game.party.heroes:
			if h == game.party.heroes[0]:
				continue
			var n: String = h.hero_name
			var first: String = ("%ds" % int(_first_down[n])) if _first_down.has(n) else "never"
			print("  %-8s first down=%5s taken=%6d downs=%d downed=%4ds touching=%.1f" % [n, first, int(_taken[n]), _downs[n], int(_down_time[n]), float(_touching[n]) / maxf(1, _samples)])
		return true
	return false
