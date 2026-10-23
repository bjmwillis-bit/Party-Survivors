extends Node3D
## Runs one session: builds the world and camera, starts every system,
## and handles the run timer, levelling up and the end screens.

const PartyScript := preload("res://scripts/party.gd")
const EnemyScript := preload("res://scripts/enemy_manager.gd")
const XpScript := preload("res://scripts/xp_manager.gd")
const FxScript := preload("res://scripts/effects.gd")
const HudScript := preload("res://scripts/hud.gd")
const UpgradesScript := preload("res://scripts/upgrades.gd")
const ChestsScript := preload("res://scripts/chests.gd")
const ArenaScript := preload("res://scripts/arena.gd")
const BarksScript := preload("res://scripts/barks.gd")

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


func _ready() -> void:
	Engine.time_scale = Game.base_time_scale
	get_tree().paused = false
	Game.main = self
	Game.time_alive = 0.0
	Game.kills = 0
	Game.gold = 0
	Game.shake = 0.0
	upgrades = UpgradesScript.new()
	_build_world()
	_build_camera()
	# Order matters: later systems read from earlier ones.
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
	Game.barks = BarksScript.new()
	add_child(Game.barks)


func _process(delta: float) -> void:
	if ended:
		return
	Game.time_alive += delta
	_run_timeline(delta)
	if _victory_delay >= 0.0:
		_victory_delay -= delta
		if _victory_delay < 0.0:
			_end_run(true)
	_update_camera(delta)


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
	if ended:
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


func _end_run(victory: bool) -> void:
	if ended:
		return
	ended = true
	get_tree().paused = true
	var score: int = locked_kills if locked_kills >= 0 else Game.kills
	Game.bank_run(Game.gold, victory, score)
	Game.hud.show_end(victory, Game.time_alive, score, level, Game.gold)


## Back to the campfire between runs.
func to_campfire() -> void:
	get_tree().paused = false
	Engine.time_scale = Game.base_time_scale
	get_tree().change_scene_to_file("res://scenes/campfire.tscn")


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


func _update_camera(delta: float) -> void:
	var leader = Game.party.leader()
	if leader == null:
		return
	# Follow tightly, and look a little ahead of where the leader is going.
	var target: Vector3 = leader.position + leader.move_dir * 1.5
	_cam_focus = _cam_focus.lerp(target, 1.0 - exp(-10.0 * delta))
	var shake_offset := Vector3.ZERO
	if Game.shake > 0.0:
		shake_offset = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * Game.shake
		Game.shake = maxf(0.0, Game.shake - delta * 2.5)
	camera.position = _cam_focus + _cam_offset + shake_offset


# --- World -------------------------------------------------------------------

func _build_world() -> void:
	arena = ArenaScript.new()
	add_child(arena)
