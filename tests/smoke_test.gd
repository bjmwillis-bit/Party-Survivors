extends SceneTree
## Headless smoke test: a simple bot plays a full run with no window.
## It walks in circles, swaps leader every few seconds and always picks the
## first level-up card, then prints how the run went and how long frames took.
##
## Run from a terminal:
##   godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd

var _frames := 0
var _last_us := 0
var _frame_ms: Array[float] = []
var _peak_enemies := 0
var _levelups := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_frame_ms.append((now - _last_us) / 1000.0)
	_last_us = now

	var main = current_scene
	if main == null or not main.has_method("choose_upgrade"):
		if _frames > 300:
			print("RESULT: FAILED - the main scene did not load (see script errors above)")
			return true
		return false
	var game = root.get_node("Game")
	if game.party == null:
		return false
	game.hitstop_enabled = false
	var t: float = game.time_alive
	main.autopilot = true
	# Walk for 2.5 seconds, then stand and fight for 1.5, like a player would.
	if fmod(t, 4.0) < 2.5:
		main.autopilot_dir = Vector3(cos(t * 0.35), 0.0, sin(t * 0.35))
	else:
		main.autopilot_dir = Vector3.ZERO
	if main.choosing:
		_levelups += 1
		# Exercise reroll and banish now and then.
		if _levelups % 7 == 0:
			main.reroll_cards()
		if _levelups % 9 == 0:
			main.banish_card(1)
		main.choose_upgrade(0)
	if _frames % 240 == 0:
		game.party.swap()
	# The bot casts the leader's skills whenever they're ready.
	var leader = game.party.leader()
	if leader != null:
		leader.cast("q")
		leader.cast("e")
		leader.cast("r")
	_peak_enemies = maxi(_peak_enemies, game.enemies.count)
	if _frames % int(OS.get_environment("SMOKE_EVERY") if OS.has_environment("SMOKE_EVERY") else "3600") == 0:
		var hps := []
		for h in game.party.heroes:
			hps.append("%s %d/%d%s" % [h.hero_name, int(h.hp), int(h.max_hp), " DOWN" if h.downed else ""])
		print("t=%4ds enemies=%3d (%.1f ms) kills=%5d level=%2d | %s" % [int(t), game.enemies.count, game.enemies.cost_ms, game.kills, main.level, ", ".join(hps)])
	var max_frames := int(OS.get_environment("SMOKE_FRAMES")) if OS.has_environment("SMOKE_FRAMES") else 60 * 60 * 14
	if main.ended or _frames > max_frames:
		_report(main, game)
		return true
	return false


func _report(main, game) -> void:
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var avg := 0.0
	for v in sorted:
		avg += v
	avg /= maxf(1.0, sorted.size())
	var p99: float = sorted[int(sorted.size() * 0.99)] if sorted.size() > 0 else 0.0
	print("RESULT: %s at %ds, kills %d, level %d, peak enemies %d" % [
		"victory" if game.time_alive >= main.RUN_LENGTH else ("party fell" if main.ended else "stopped early"),
		int(game.time_alive), game.kills, main.level, _peak_enemies])
	for h in game.party.heroes:
		print("SKILLS %s: Q x%d, E x%d, R x%d, counters x%d" % [h.hero_name, h.stats["q"], h.stats["e"], h.stats["r"], h.stats["counter"]])
	var u = main.upgrades
	var picks: Array = []
	for id in u.taken:
		picks.append("%s x%d" % [id, u.taken[id]])
	print("CARDS: ", ", ".join(picks))
	print("BONDS: ", game.party.bonds.keys(), "  banished: ", u.banished.keys(), "  rerolls left: ", u.rerolls_left, "  banishes left: ", u.banishes_left)
	print("FRAME (script cost, no rendering): avg %.2f ms, 99th percentile %.2f ms" % [avg, p99])
