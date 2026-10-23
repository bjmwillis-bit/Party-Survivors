extends Node3D
## Runs the game: builds the world and camera, starts every system, and
## directs the cycle of nights in one continuous shot:
##   CAMP        the party sits at the fire; the campfire interface is up.
##   SETTING_OUT they get up and walk out; the camera rises to the battle view.
##   NIGHT       the fight: timer, horde, levelling up.
##   HOMEWARD    after a win (or withdrawing): the horde crumbles, the party
##               walks back and sits down while the results show.
## After a fall the screen behind the results goes black and the camp is set
## up again behind it. Each new night gets fresh systems (party, horde...),
## with the heroes put back exactly where they stood, so there is no cut.

const PartyScript := preload("res://scripts/party.gd")
const EnemyScript := preload("res://scripts/enemy_manager.gd")
const XpScript := preload("res://scripts/xp_manager.gd")
const FxScript := preload("res://scripts/effects.gd")
const HudScript := preload("res://scripts/hud.gd")
const UpgradesScript := preload("res://scripts/upgrades.gd")
const ChestsScript := preload("res://scripts/chests.gd")
const ArenaScript := preload("res://scripts/arena.gd")
const BarksScript := preload("res://scripts/barks.gd")
const CampScript := preload("res://scripts/camp.gd")
const KeepScript := preload("res://scripts/keep.gd")
const CampUiScript := preload("res://scripts/camp_ui.gd")

enum { CAMP, SETTING_OUT, NIGHT, HOMEWARD }

# The shape of a run.
const RUN_LENGTH := 720.0 # 12 minutes: the final boss arrives, and the timer becomes ∞
const ELITE_EVERY := 90.0
const MINIBOSS_TIMES := [150.0, 300.0, 450.0, 600.0]
const SWARM_EVERY_KILLS := 500
const SWARM_TIME := 60.0
const GOBLIN_EVERY_CHESTS := 3
const CAM_PITCH := 55.0 # How steeply the camera looks down (degrees).
const CAM_DISTANCE := 24.0

var camera: Camera3D
var arena
var camp
var keep
var camp_ui
var state := CAMP
var level := 1
var xp_have := 0
var xp_need := 5
var pending_levels := 0
var choosing := false
var current_choices: Array = []
var choice_level := 0 # the level the current cards are for
var ended := false
var upgrades

var next_elite := ELITE_EVERY
var minis_spawned := 0
var minis_killed := 0
var final_spawned := false
var final_killed := false
var locked_kills := -1 # the score, once the final boss falls
var swarm_time := 0.0 # seconds left in the current swarm
var next_swarm_kills := SWARM_EVERY_KILLS
var boss_max_hp := 1.0
var _victory_delay := -1.0
var _beast_teased := false

## Tests drive the leader with these instead of the keyboard.
var autopilot := false
var autopilot_dir := Vector3.ZERO

var _cam_focus := Vector3.ZERO
var _cam_offset := Vector3.ZERO
## 0 = the battle view following the leader, 1 = the low shot of the camp.
var _cam_camp := 1.0
var _cam_tween: Tween
var _setting_out_t := 0.0
var _results_choice := 0 # while walking home: 0 none yet, 1 keep fighting, 2 return
var _seated := false


func _ready() -> void:
	Engine.time_scale = Game.base_time_scale
	get_tree().paused = false
	Game.main = self
	_reset_run_vars()
	_build_world()
	_build_camera()
	_start_systems()
	camp_ui = CampUiScript.new()
	add_child(camp_ui)
	camp_ui.fight.connect(set_out)
	camp_ui.party_changed.connect(_on_party_changed)
	Game.results.chosen.connect(_on_results_chosen)
	Game.results.blacked_out.connect(_on_blacked_out)
	if Game.skip_camp:
		# Tests: straight into a night.
		state = NIGHT
		_cam_camp = 0.0
		Game.hud.visible = true
		for k in Game.party.heroes.size():
			Game.party.heroes[k].position = camp.SET_OUT[mini(k, camp.SET_OUT.size() - 1)]
		return
	_seat_party(true)
	camp_ui.show_ui()
	camp_ui.fade_from_black()


func is_night() -> bool:
	return state == NIGHT


func _reset_run_vars() -> void:
	Game.time_alive = 0.0
	Game.kills = 0
	Game.gold = 0
	Game.shake = 0.0
	upgrades = UpgradesScript.new()
	level = 1
	xp_have = 0
	xp_need = 5
	pending_levels = 0
	choosing = false
	current_choices = []
	choice_level = 0
	ended = false
	next_elite = ELITE_EVERY
	minis_spawned = 0
	minis_killed = 0
	final_spawned = false
	final_killed = false
	locked_kills = -1
	swarm_time = 0.0
	next_swarm_kills = SWARM_EVERY_KILLS
	boss_max_hp = 1.0
	_victory_delay = -1.0
	_beast_teased = false


## Order matters: later systems read from earlier ones.
func _start_systems() -> void:
	Game.fx = FxScript.new()
	add_child(Game.fx)
	Game.enemies = EnemyScript.new()
	add_child(Game.enemies)
	Game.xp = XpScript.new()
	add_child(Game.xp)
	Game.party = PartyScript.new()
	add_child(Game.party)
	Game.chests = ChestsScript.new()
	add_child(Game.chests)
	Game.hud = HudScript.new()
	add_child(Game.hud)
	Game.hud.visible = false
	Game.barks = BarksScript.new()
	add_child(Game.barks)


## A clean slate for the next night: every system is rebuilt, and each hero
## is put back exactly where (and how) they were, so nothing visibly jumps.
func _fresh_night() -> void:
	var snaps := {}
	for h in Game.party.heroes:
		snaps[h.kind] = h.snapshot()
	for sys in [Game.barks, Game.hud, Game.chests, Game.party, Game.xp, Game.enemies, Game.fx]:
		remove_child(sys)
		sys.queue_free()
	_reset_run_vars()
	_start_systems()
	for h in Game.party.heroes:
		if snaps.has(h.kind):
			h.restore(snaps[h.kind])


func _process(delta: float) -> void:
	_update_camera(delta)
	match state:
		NIGHT:
			if ended:
				return
			Game.time_alive += delta
			_run_timeline(delta)
			if _victory_delay >= 0.0:
				_victory_delay -= delta
				if _victory_delay < 0.0:
					_end_run(true)
		SETTING_OUT:
			_tick_setting_out(delta)
		HOMEWARD:
			_tick_homeward(delta)


# --- Camp, setting out and coming home ---------------------------------------

## Puts everyone at their places by the fire. `instant`: no walking.
func _seat_party(instant: bool) -> void:
	state = CAMP
	_seated = instant
	for h in Game.party.heroes:
		var seat: Dictionary = camp.seat_for(Game.party.heroes.find(h))
		var face := deg_to_rad(seat["face"])
		if instant:
			h.position = seat["pos"]
			h.rotation.y = face
			h.facing = face
			h.sit = 1.0 if seat["sit"] else 0.0
			h.moving = false
		Game.party.direct(h, seat["pos"], face)
	if instant:
		_blend_camera(1.0, 0.0)


## FIGHT (or Keep Fighting): everyone stands, walks out in front of the fire,
## and the camera rises into the battle view. The night starts as it lands.
func set_out() -> void:
	if state == SETTING_OUT or state == NIGHT:
		return
	if ended:
		_fresh_night() # the last night is over: clean slate, nothing moves
	camp_ui.hide_ui()
	state = SETTING_OUT
	_setting_out_t = 0.0
	var spots: Array = camp.SET_OUT
	var order: Array = [Game.party.leader()]
	for h in Game.party.heroes:
		if h != Game.party.leader():
			order.append(h)
	for k in order.size():
		var h = order[k]
		h.invulnerable = false
		if h.sit > 0.0:
			var tw := create_tween()
			tw.tween_property(h, "sit", 0.0, 0.45).set_ease(Tween.EASE_IN_OUT)
		Game.party.direct(h, spots[mini(k, spots.size() - 1)], 0.0, 4.5)
	_blend_camera(0.0, 2.0, 0.35)


func _tick_setting_out(delta: float) -> void:
	_setting_out_t += delta
	var all_there := true
	for h in Game.party.heroes:
		all_there = all_there and Game.party.arrived(h)
	if (all_there and _setting_out_t > 1.2) or _setting_out_t > 2.6:
		Game.party.directed.clear()
		state = NIGHT
		Game.hud.visible = true
		Game.hud.fade_to(1.0, 0.4, 0.0)


## A win (or withdrawing): the horde crumbles and the party heads home.
func _go_home() -> void:
	state = HOMEWARD
	_results_choice = 0
	_seated = false
	var far := 0.0
	for h in Game.party.heroes:
		if h.downed:
			h.revive()
		h.invulnerable = true
		h.dashing = false
		far = maxf(far, Vector2(h.position.x, h.position.z).length())
	_seat_party(false)
	state = HOMEWARD
	# The camera settles into the camp shot as they arrive.
	_blend_camera(1.0, clampf(far / 5.5 + 0.8, 2.0, 9.0), 0.4)


func _tick_homeward(_delta: float) -> void:
	Game.enemies.dissolve(25)
	for h in Game.party.heroes:
		var seat: Dictionary = camp.seat_for(Game.party.heroes.find(h))
		if Game.party.arrived(h) and seat.get("sit", false) and h.sit == 0.0 and not h.has_meta("sitting_down"):
			h.set_meta("sitting_down", true)
			var tw := create_tween()
			tw.tween_property(h, "sit", 1.0, 0.45).set_ease(Tween.EASE_IN_OUT)
			tw.tween_callback(func() -> void: h.remove_meta("sitting_down"))
	if not _seated:
		var all_home := true
		for h in Game.party.heroes:
			var seat: Dictionary = camp.seat_for(Game.party.heroes.find(h))
			all_home = all_home and Game.party.arrived(h) and (h.sit >= 1.0 or not seat.get("sit", false))
		if all_home:
			_seated = true
			if _results_choice == 2:
				_arrive_at_camp()


func _arrive_at_camp() -> void:
	state = CAMP
	camp_ui.show_ui(true)


func _on_results_chosen(keep_fighting: bool) -> void:
	if state == HOMEWARD:
		if keep_fighting:
			set_out()
		else:
			_results_choice = 2
			if _seated:
				_arrive_at_camp()
		return
	# After a fall the camp is already set behind the black.
	if keep_fighting:
		set_out()
	else:
		camp_ui.show_ui(true)


## A different trio was picked at the fire: rebuild the party in their seats.
func _on_party_changed() -> void:
	if state != CAMP:
		return
	_fresh_night()
	_seat_party(true)
	keep.refresh_guards() # whoever left the party takes their post


## A fall: behind the black, a fresh night and the party back at the fire.
func _on_blacked_out() -> void:
	_fresh_night()
	_seat_party(true)
	arena.snap_sky()


# --- The run's timeline ------------------------------------------------------

func _run_timeline(delta: float) -> void:
	var t: float = Game.time_alive
	var E = Game.enemies
	if t >= next_elite and not final_killed:
		next_elite += ELITE_EVERY
		E.spawn_near_leader(E.ELITE)
	while minis_spawned < MINIBOSS_TIMES.size() and t >= MINIBOSS_TIMES[minis_spawned]:
		minis_spawned += 1
		var i: int = E.spawn_near_leader(E.MINIBOSS, 15.0, 18.0)
		if i >= 0:
			boss_max_hp = E.hp[i]
		Game.hud.banner("A hunter approaches  (%d/4)" % minis_spawned, Color(0.9, 0.2, 0.15))
	if not final_spawned and t >= RUN_LENGTH:
		final_spawned = true
		var i: int = E.spawn_near_leader(E.FINAL_BOSS, 15.0, 18.0)
		if i >= 0:
			boss_max_hp = E.hp[i]
		Game.hud.banner("THE BEAST ARRIVES", Color(1.0, 0.15, 0.1), 3.0)
		Game.add_shake(0.5)
	# The Beast's taunt, once, when it is down to half health.
	if final_spawned and not final_killed and not _beast_teased:
		var b: int = E.find_kind(E.FINAL_BOSS)
		if b >= 0 and E.hp[b] < boss_max_hp * 0.5:
			_beast_teased = true
			Game.barks.say_as("beast", "beast_tease")
	# Swarms: every 500 kills, a minute of double spawning.
	if swarm_time > 0.0:
		swarm_time -= delta
		if swarm_time <= 0.0:
			E.swarm_active = false
			next_swarm_kills = Game.kills + SWARM_EVERY_KILLS
	elif Game.kills >= next_swarm_kills and not final_killed:
		swarm_time = SWARM_TIME
		E.swarm_active = true
		Game.hud.banner("SWARM!", Color(1.0, 0.75, 0.2))


func on_elite_killed(p: Vector2) -> void:
	Game.chests.spawn(p, ChestsScript.roll_tier())


func on_miniboss_killed(p: Vector2) -> void:
	minis_killed += 1
	Game.chests.spawn(p, "epic")
	Game.hud.add_claw()
	Game.hud.banner("Hunter slain  (%d/4)" % minis_killed, Color(0.9, 0.2, 0.15))
	Game.hitstop(0.12)
	Game.add_shake(0.4)


func on_final_boss_killed(p: Vector2) -> void:
	final_killed = true
	locked_kills = Game.kills
	add_gold(100)
	Game.fx.float_text(Vector3(p.x, 3.0, p.y), "+100 gold", Color(1.0, 0.85, 0.3), 2.0)
	Game.hud.strike_tally()
	Game.hud.banner("THE BEAST IS DEAD", Color(1.0, 0.85, 0.3), 3.0)
	Game.barks.beast_slain()
	Game.hitstop(0.25)
	Game.add_shake(0.8)
	_victory_delay = 5.5 # time for the last words before the end screen


func on_goblin_caught(p: Vector2) -> void:
	add_gold(60)
	Game.fx.float_text(Vector3(p.x, 1.5, p.y), "+60 gold", Color(1.0, 0.85, 0.3), 1.6)
	Game.fx.ring(Vector3(p.x, 0.0, p.y), 2.5, Color(1.0, 0.82, 0.2), 0.3)


func on_chest_opened(total: int) -> void:
	if total % GOBLIN_EVERY_CHESTS == 0:
		Game.enemies.spawn_near_leader(Game.enemies.GOBLIN, 10.0, 13.0)
		Game.hud.banner("A treasure goblin!", Color(1.0, 0.82, 0.2))


func add_gold(amount: int) -> void:
	Game.gold += amount


# --- Levelling ---------------------------------------------------------------

func gain_xp(amount: int) -> void:
	if ended or not is_night():
		return
	xp_have += amount
	while xp_have >= xp_need:
		xp_have -= xp_need
		level += 1
		xp_need = 5 + int(level * 3.5 + pow(level, 1.4))
		pending_levels += 1
	if pending_levels > 0 and not choosing:
		_open_levelup()


func _open_levelup() -> void:
	choice_level = level - pending_levels + 1
	current_choices = upgrades.roll(3, choice_level)
	if current_choices.is_empty():
		pending_levels = 0
		return
	choosing = true
	get_tree().paused = true
	Game.hud.show_levelup(choice_level, current_choices, upgrades.is_ult_level(choice_level))


func reroll_cards() -> void:
	if not choosing or upgrades.rerolls_left <= 0:
		return
	var fresh: Array = upgrades.roll(3, choice_level, _choice_ids())
	if fresh.is_empty():
		return
	upgrades.rerolls_left -= 1
	current_choices = fresh
	Game.hud.show_levelup(choice_level, current_choices, upgrades.is_ult_level(choice_level))


## Removes a card from this run for good, and deals a new one in its place.
func banish_card(index: int) -> void:
	if not choosing or upgrades.banishes_left <= 0 or index < 0 or index >= current_choices.size():
		return
	if current_choices[index] == null:
		return
	upgrades.banish(current_choices[index])
	var fresh: Array = upgrades.roll(1, choice_level, _choice_ids())
	current_choices[index] = fresh[0] if not fresh.is_empty() else null
	Game.hud.replace_card(index, current_choices[index])


func _choice_ids() -> Array:
	var ids: Array = []
	for c in current_choices:
		if c != null:
			ids.append(c["id"])
	return ids


func choose_upgrade(index: int) -> void:
	if not choosing or index < 0 or index >= current_choices.size():
		return
	if current_choices[index] == null:
		return
	if not autopilot and not Game.hud.card_ready(index):
		return # wait for the card's reveal to finish
	upgrades.apply(current_choices[index])
	pending_levels -= 1
	choosing = false
	Game.hud.hide_levelup()
	if pending_levels > 0:
		_open_levelup()
	else:
		get_tree().paused = false


# --- Ending ------------------------------------------------------------------

func on_party_wiped() -> void:
	_end_run(false)


## Leaving mid-night from the pause menu: the gold so far is still banked.
func withdraw() -> void:
	_end_run(false, true)


func _end_run(victory: bool, withdrew := false) -> void:
	if ended:
		return
	ended = true
	choosing = false
	get_tree().paused = false
	var score: int = locked_kills if locked_kills >= 0 else Game.kills
	var bank_before: int = Game.progress["gold"]
	Game.bank_run(Game.gold, victory, score)
	Game.last_run = {
		"victory": victory, "withdrew": withdrew, "time": Game.time_alive, "kills": score,
		"level": level, "hunters": minis_killed, "gold": Game.gold,
		"bank_before": bank_before, "bank_after": Game.progress["gold"],
		"nights_after": Game.progress["nights_survived"], "night": Game.progress["runs"],
		"beast_teased": _beast_teased,
	}
	Game.hud.fade_to(0.0, 0.3)
	if Game.skip_camp:
		return # tests stop here
	var fell := not victory and not withdrew
	Game.results.show_results(Game.last_run, fell)
	if fell:
		Game.party.directed.clear()
		state = HOMEWARD # nothing moves until the black comes down
		for h in Game.party.heroes:
			h.invulnerable = true
	else:
		_go_home()


func restart() -> void:
	get_tree().paused = false
	Engine.time_scale = Game.base_time_scale
	get_tree().reload_current_scene()


# --- Camera ------------------------------------------------------------------

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.rotation_degrees = Vector3(-CAM_PITCH, 0.0, 0.0)
	var p := deg_to_rad(CAM_PITCH)
	_cam_offset = Vector3(0.0, sin(p), cos(p)) * CAM_DISTANCE
	add_child(camera)
	camera.current = true
	camera.position = _cam_offset
	_cam_focus = Vector3(0.0, 0.0, 4.6)


## Moves the camera between the battle view and the camp shot.
func _blend_camera(to: float, seconds: float, delay := 0.0) -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	if seconds <= 0.0:
		_cam_camp = to
		return
	_cam_tween = create_tween()
	_cam_tween.tween_interval(delay)
	_cam_tween.tween_property(self, "_cam_camp", to, seconds).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _update_camera(delta: float) -> void:
	var leader = Game.party.leader()
	if leader == null:
		return
	# Battle view: follow tightly, looking a little ahead of the leader.
	var target: Vector3 = leader.position + leader.move_dir * 1.5
	_cam_focus = _cam_focus.lerp(target, 1.0 - exp(-10.0 * delta))
	var shake_offset := Vector3.ZERO
	if Game.shake > 0.0:
		shake_offset = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * Game.shake
		Game.shake = maxf(0.0, Game.shake - delta * 2.5)
	var battle := Transform3D(Basis.from_euler(Vector3(-deg_to_rad(CAM_PITCH), 0.0, 0.0)), _cam_focus + _cam_offset + shake_offset)
	if _cam_camp <= 0.0 or camp == null:
		camera.global_transform = battle
		return
	camera.global_transform = battle.interpolate_with(camp.camera_transform(), _cam_camp)


# --- World -------------------------------------------------------------------

func _build_world() -> void:
	arena = ArenaScript.new()
	add_child(arena)
	camp = CampScript.new() # after the arena: it adds its own obstacles
	add_child(camp)
	keep = KeepScript.new() # the walls round the camp, and their guards
	add_child(keep)
