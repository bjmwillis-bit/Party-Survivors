extends SceneTree
## Switches on every card in the pool (all epics, ultimate upgrades and
## bonds), then plays two minutes with a bot that swaps and casts constantly.
## Any broken card effect shows up as a SCRIPT ERROR in the output.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/all_cards_test.gd

var _frames := 0
var _applied := false


func _initialize() -> void:
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
	if game.party == null:
		return false
	game.hitstop_enabled = false
	game.saving_enabled = false
	if not _applied:
		_applied = true
		for card in main.upgrades.pool:
			for k in int(card["max"]):
				main.upgrades.apply(card)
		print("Applied %d cards. Bonds: %s" % [main.upgrades.pool.size(), game.party.bonds.keys()])
		# Jump the clock so the first hunter turns up straight away.
		game.time_alive = 145.0
		main.next_elite = 146.0
	# Later, skip ahead to the final boss.
	if _frames == 60 * 40:
		game.time_alive = 715.0
		main.minis_spawned = 4
	var t: float = game.time_alive
	main.autopilot = true
	main.autopilot_dir = Vector3(cos(t * 0.5), 0.0, sin(t * 0.5)) if fmod(t, 3.0) < 1.5 else Vector3.ZERO
	if main.choosing:
		main.choose_upgrade(0)
	if _frames % 90 == 0:
		game.party.swap()
	# Force some blows and damage so counters and heals get exercised too.
	if _frames % 20 == 0:
		var sol = game.party.hero("Solenne")
		if sol != null and not sol.downed:
			var e: int = game.enemies.nearest(Vector2(sol.position.x, sol.position.z), 30.0)
			sol.take_hit(2.0, e)
		for h in game.party.heroes:
			if not h.downed and h.hp > h.max_hp * 0.5:
				h.take_damage(h.max_hp * 0.03)
	var l = game.party.leader()
	if l != null:
		for slot in ["q", "e", "r"]:
			l.cast(slot)
		# Keep ultimates flowing so every upgrade gets exercised.
		if _frames % 600 == 0:
			for h in game.party.heroes:
				h.cooldown["r"] = 0.0
	# Head for the boss when one is up (a player would).
	var boss: int = game.enemies.find_kind(game.enemies.FINAL_BOSS)
	if boss >= 0 and l != null:
		var bp: Vector2 = game.enemies.pos[boss]
		var tob: Vector3 = Vector3(bp.x, 0.0, bp.y) - l.position
		main.autopilot_dir = tob.normalized() if tob.length() > 3.0 else Vector3.ZERO
	# Walk the leader onto any chest so chests open in the test.
	if game.chests._chests.size() > 0:
		var c = game.chests._chests[0]["root"]
		var to: Vector3 = c.position - l.position
		to.y = 0.0
		main.autopilot_dir = to.normalized() if to.length() > 0.5 else Vector3.ZERO
	if (t > 840.0) or main.ended or _frames > 60 * 60 * 6:
		for h in game.party.heroes:
			print("SKILLS %s: Q x%d, E x%d, R x%d, counters x%d, hp %d/%d" % [h.hero_name, h.stats["q"], h.stats["e"], h.stats["r"], h.stats["counter"], int(h.hp), int(h.max_hp)])
		print("RESULT: %s at %ds, kills %d (locked %d), hunters killed %d, final boss %s, chests %d, gold %d" % [
			"VICTORY" if main.final_killed else ("ended" if main.ended else "ran"), int(t), game.kills, main.locked_kills,
			main.minis_killed, "killed" if main.final_killed else ("alive" if main.final_spawned else "not spawned"),
			game.chests.opened, game.gold])
		return true
	return false
