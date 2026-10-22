extends Node3D
## Runs one session: builds the world and camera, starts every system,
## and handles the run timer, levelling up and the end screens.

const PartyScript := preload("res://scripts/party.gd")
const EnemyScript := preload("res://scripts/enemy_manager.gd")
const XpScript := preload("res://scripts/xp_manager.gd")
const FxScript := preload("res://scripts/effects.gd")
const HudScript := preload("res://scripts/hud.gd")
const UpgradesScript := preload("res://scripts/upgrades.gd")

const RUN_LENGTH := 720.0 # 12 minutes. The boss arrives here in milestone 2.
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
var ended := false
var upgrades

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
	Game.hud = HudScript.new()
	add_child(Game.hud)


func _process(delta: float) -> void:
	if ended:
		return
	Game.time_alive += delta
	if Game.time_alive >= RUN_LENGTH:
		_end_run(true)
	_update_camera(delta)


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
	current_choices = upgrades.roll(3)
	if current_choices.is_empty():
		pending_levels = 0
		return
	choosing = true
	get_tree().paused = true
	Game.hud.show_levelup(level, current_choices)


func choose_upgrade(index: int) -> void:
	if not choosing or index < 0 or index >= current_choices.size():
		return
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
	Game.hud.show_end(victory, Game.time_alive, Game.kills, level)


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
	var pillar := BoxMesh.new()
	pillar.size = Vector3(0.9, 3.5, 0.9)
	_scatter(pillar, Color(0.55, 0.53, 0.5), 30, 0.6, 1.3, 1.0, 33)
	_build_boundary()


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
