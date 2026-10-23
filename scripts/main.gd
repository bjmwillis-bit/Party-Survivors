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

# The shape of a run.
const RUN_LENGTH := 720.0 # 12 minutes: the final boss arrives, and the timer becomes ∞
const ELITE_EVERY := 90.0
const MINIBOSS_TIMES := [150.0, 300.0, 450.0, 600.0]
const SWARM_EVERY_KILLS := 500
const SWARM_TIME := 60.0
const GOBLIN_EVERY_CHESTS := 3
const ARENA_HALF := 60.0 # The arena is 120 x 120 metres.
const CAM_PITCH := 55.0 # How steeply the camera looks down (degrees).
const CAM_DISTANCE := 24.0

var camera: Camera3D
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


func _process(delta: float) -> void:
	_flicker(delta)
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
	Game.hitstop(0.25)
	Game.add_shake(0.8)
	_victory_delay = 2.5


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
	Game.hud.show_end(victory, Game.time_alive, locked_kills if locked_kills >= 0 else Game.kills, level, Game.gold)


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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.45, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA_HALF * 2.0 + 40.0, ARENA_HALF * 2.0 + 40.0)
	ground.mesh = plane
	ground.material_override = Game.material(Color(0.33, 0.3, 0.25))
	add_child(ground)

	# Scattered props give the eye something to measure movement against.
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 3
	_scatter(Game.flat_mesh(rock), Color(0.46, 0.45, 0.43), 170, 0.4, 1.4, 0.6, 11)
	var tuft := PrismMesh.new()
	tuft.size = Vector3(0.35, 0.5, 0.12)
	_scatter(tuft, Color(0.38, 0.42, 0.25), 900, 0.6, 1.3, 1.0, 22)
	_build_ruins()
	_build_boundary()


# --- Ruins -------------------------------------------------------------------
# Placeholder dressing from the KayKit Dungeon pack (CC0, Kay Lousberg):
# broken walls, pillars, braziers and the leavings of old camps, scattered in
# small clusters. Walls, pillars and rubble are solid.

const DUNGEON := "res://assets/kaykit/dungeon/"
const PROP_SCALE := 0.8
## Each piece: [model, offset x, offset z, turn (degrees), solid radius (0 = walk-through)]
const RUIN_SITES := [
	[["wall_broken", 0.0, 0.0, 0.0, 0.0], ["pillar", -2.0, 0.0, 0.0, 0.7], ["rubble_half", 0.6, 2.2, 15.0, 0.0], ["banner_patternA_red", 0.9, 0.05, 0.0, 0.0]],
	[["wall_cracked", 0.0, 0.0, 0.0, 0.0], ["wall_broken", 3.2, 0.0, 0.0, 0.0], ["pillar_decorated", 1.6, 0.0, 0.0, 0.8], ["sword_shield_broken", 1.0, 2.0, 30.0, 0.0]],
	[["pillar", 0.0, 0.0, 0.0, 0.7], ["pillar", 4.0, 0.0, 0.0, 0.7], ["pillar", 0.0, 4.0, 0.0, 0.7], ["rubble_half", 3.0, 3.0, 200.0, 0.0]],
	[["rubble_large", 0.0, 0.0, 0.0, 0.0], ["column", 3.8, 1.5, 0.0, 0.4], ["sword_shield_broken", -2.0, 2.0, -40.0, 0.0]],
	[["barrel_large", 0.0, 0.0, 0.0, 0.8], ["crates_stacked", 2.0, 0.4, 20.0, 1.0], ["barrel_large", 0.4, 1.8, 0.0, 0.8], ["sword_shield_broken", 2.2, 2.4, 70.0, 0.0]],
]
## Braziers: a column with a lit torch on top, throwing warm light.
const BRAZIERS := 6


func _build_ruins() -> void:
	Game.clear_obstacles()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 22 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(-ARENA_HALF + 6.0, ARENA_HALF - 6.0), rng.randf_range(-ARENA_HALF + 6.0, ARENA_HALF - 6.0))
		if p.length() < 12.0 or _too_close(p, placed, 14.0):
			continue
		placed.append(p)
		var site: Array = RUIN_SITES[rng.randi() % RUIN_SITES.size()]
		var turn := rng.randf() * TAU
		for piece in site:
			_place_piece(piece, p, turn)
	# Braziers light the way, a little apart from the ruins.
	var lit := 0
	tries = 0
	while lit < BRAZIERS and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(-ARENA_HALF + 8.0, ARENA_HALF - 8.0), rng.randf_range(-ARENA_HALF + 8.0, ARENA_HALF - 8.0))
		if _too_close(p, placed, 6.0) or (lit > 0 and p.length() < 10.0):
			continue
		if lit == 0:
			p = Vector2(5.0, -5.0) # one near the start, so it's seen at once
		placed.append(p)
		_brazier(p)
		lit += 1
	# Patches of rocky earth break up the flat ground.
	for i in 40:
		var p := Vector2(rng.randf_range(-ARENA_HALF, ARENA_HALF), rng.randf_range(-ARENA_HALF, ARENA_HALF))
		var floor_patch := Game.model(DUNGEON + "floor_dirt_large_rocky.gltf")
		if floor_patch == null:
			break
		floor_patch.position = Vector3(p.x, 0.0, p.y)
		floor_patch.rotation.y = rng.randi_range(0, 3) * PI * 0.5
		floor_patch.scale = Vector3(1.0, 0.4, 1.0) * PROP_SCALE
		add_child(floor_patch)


func _too_close(p: Vector2, others: Array[Vector2], dist: float) -> bool:
	for o in others:
		if o.distance_to(p) < dist:
			return true
	return false


func _place_piece(piece: Array, at: Vector2, turn: float) -> void:
	var node := Game.model(DUNGEON + str(piece[0]) + ".gltf")
	if node == null:
		return
	var off := Vector2(float(piece[1]), float(piece[2])).rotated(-turn) * PROP_SCALE
	var p := at + off
	node.position = Vector3(p.x, 0.0, p.y)
	node.rotation.y = turn + deg_to_rad(float(piece[3]))
	node.scale = Vector3.ONE * PROP_SCALE
	add_child(node)
	var r: float = float(piece[4]) * PROP_SCALE
	if r > 0.0:
		Game.add_obstacle(p, r)
	# Walls and rubble are long: block them with a row of circles.
	var name_s := str(piece[0])
	var half_len := 0.0
	var rad := 0.0
	if name_s.begins_with("wall"):
		half_len = 1.6
		rad = 0.55
	elif name_s == "rubble_large":
		half_len = 3.0
		rad = 1.1
	elif name_s == "rubble_half":
		half_len = 1.2
		rad = 1.0
	if half_len > 0.0:
		var along := Vector2(cos(-node.rotation.y), sin(-node.rotation.y))
		var centre := p
		if name_s == "rubble_half": # this piece starts at its origin and runs one way
			centre = p + along * 1.6
		var k := -half_len
		while k <= half_len + 0.01:
			Game.add_obstacle(centre + along * k, rad)
			k += rad * 1.2


func _brazier(p: Vector2) -> void:
	var column := Game.model(DUNGEON + "column.gltf")
	var torch := Game.model(DUNGEON + "torch_lit.gltf")
	if column == null or torch == null:
		return
	column.position = Vector3(p.x, 0.0, p.y)
	column.scale = Vector3.ONE * PROP_SCALE
	add_child(column)
	torch.position = Vector3(p.x, 1.4 * PROP_SCALE + 0.35, p.y)
	torch.scale = Vector3.ONE * PROP_SCALE
	add_child(torch)
	Game.add_obstacle(p, 0.45)
	var light := OmniLight3D.new()
	light.position = Vector3(p.x, 2.4, p.y)
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 2.2
	light.omni_range = 8.0
	light.shadow_enabled = false
	add_child(light)
	_flames.append(light)


var _flames: Array[OmniLight3D] = []
var _flame_t := 0.0


## Makes the brazier lights flicker.
func _flicker(delta: float) -> void:
	_flame_t += delta
	for i in _flames.size():
		var f := _flames[i]
		f.light_energy = 2.0 + 0.35 * sin(_flame_t * 9.0 + i * 1.7) + 0.2 * sin(_flame_t * 23.0 + i)


func _scatter(mesh: Mesh, color: Color, count: int, scale_min: float, scale_max: float, height_scale: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var spread := ARENA_HALF + 15.0
	for i in count:
		var p := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		if p.length() < 5.0:
			p.x += 10.0 # keep the starting spot clear
		var s := rng.randf_range(scale_min, scale_max)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * height_scale, s))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Game.material(color)
	add_child(mmi)


## A ring of standing stones marks the edge of the arena.
func _build_boundary() -> void:
	var stone := BoxMesh.new()
	stone.size = Vector3(1.2, 3.0, 0.8)
	var spots: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var step := 3.0
	var edge := ARENA_HALF + 1.0
	var x := -edge
	while x <= edge:
		for z in [-edge, edge]:
			spots.append(_stone_at(Vector3(x, 1.0, z), rng))
			spots.append(_stone_at(Vector3(z, 1.0, x), rng))
		x += step
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stone
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Game.material(Color(0.5, 0.48, 0.46))
	add_child(mmi)


func _stone_at(p: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var s := rng.randf_range(0.7, 1.3)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.5), s))
	return Transform3D(b, p)
