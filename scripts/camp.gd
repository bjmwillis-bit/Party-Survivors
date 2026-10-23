extends Node3D
## The party's camp at the centre of the arena: a fire, three logs, and the
## broken walls of the Keep behind it. Between nights the party sits here,
## and the camera settles into a low shot of the fire. Nights start and end
## here, in one continuous shot (main.gd directs it).
##
## Placeholder art: simple shapes and KayKit Dungeon pieces (CC0).

const DUNGEON := "res://assets/kaykit/dungeon/"

## Logs: [position, turn (degrees), length].
const LOGS := [
	[Vector3(0.0, 0.0, -2.3), 0.0, 2.6], # Cenhelm's, behind the fire
	[Vector3(-2.2, 0.0, -0.3), 62.0, 2.4], # Kheiron's, on the left
	[Vector3(2.3, 0.0, -0.4), -58.0, 2.4], # Solenne's, on the right
]
const LOG_RADIUS := 0.24
## Where each hero rests: position, facing (degrees), and whether they sit.
const SEATS := {
	"cenhelm": {"pos": Vector3(0.0, 0.0, -2.3), "face": 0.0, "sit": true},
	"kheiron": {"pos": Vector3(-2.05, 0.0, -0.55), "face": 62.0, "sit": true},
	"solenne": {"pos": Vector3(2.55, 0.0, -1.1), "face": -50.0, "sit": false},
}
## Where the party gathers when they set out (in front of the fire).
const SET_OUT := [Vector3(0.0, 0.0, 4.6), Vector3(-1.0, 0.0, 3.2), Vector3(1.0, 0.0, 3.2)]
const FIRE_BLOCK := 0.95 # nobody walks through the fire

var _fire_light: OmniLight3D
var _flames: Array[Node3D] = []
var _t := 0.0


func _ready() -> void:
	_build_fire()
	_build_logs()
	_build_ruin()
	Game.add_obstacle(Vector2.ZERO, FIRE_BLOCK)


func _process(delta: float) -> void:
	_t += delta
	_fire_light.light_energy = 3.0 + 0.5 * sin(_t * 11.0) + 0.3 * sin(_t * 23.0 + 1.0)
	for i in _flames.size():
		var f := _flames[i]
		var s := 1.0 + 0.22 * sin(_t * (9.0 + i * 2.3) + i) + 0.1 * sin(_t * 17.0 + i * 3.0)
		f.scale = Vector3(1.0 / sqrt(s), s, 1.0 / sqrt(s))
		var tilt: Vector3 = f.get_meta("tilt")
		f.rotation.x = tilt.x + 0.12 * sin(_t * 5.0 + i * 1.3)
		f.rotation.z = tilt.z + 0.12 * cos(_t * 4.3 + i * 0.7)


## How high a seated hero's model sits so their hips rest on the log.
static func seat_raise(model_scale: float) -> float:
	return LOG_RADIUS * 2.0 - 0.3 * model_scale


## The camp shot: low, in front of the fire, drifting slowly.
func camera_transform() -> Transform3D:
	var p := global_position + Vector3(sin(_t * 0.15) * 0.25, 2.55, 8.0)
	var t := Transform3D(Basis.IDENTITY, p)
	return t.looking_at(global_position + Vector3(0.0, 0.6, -0.9), Vector3.UP)


func _build_fire() -> void:
	var stone := SphereMesh.new()
	stone.radial_segments = 6
	stone.rings = 3
	var stone_mesh := Game.flat_mesh(stone)
	for i in 9:
		var a := i * TAU / 9.0
		var s := MeshInstance3D.new()
		s.mesh = stone_mesh
		s.material_override = Game.material(Color(0.4, 0.38, 0.37))
		s.position = Vector3(cos(a) * 0.75, 0.05, sin(a) * 0.75)
		s.scale = Vector3(0.26, 0.18, 0.22)
		add_child(s)
	var wood := CylinderMesh.new()
	wood.top_radius = 0.07
	wood.bottom_radius = 0.09
	wood.height = 0.85
	wood.radial_segments = 6
	var wood_mesh := Game.flat_mesh(wood)
	for i in 5:
		var w := MeshInstance3D.new()
		w.mesh = wood_mesh
		w.material_override = Game.material(Color(0.3, 0.18, 0.1))
		var a := i * TAU / 5.0
		w.position = Vector3(cos(a) * 0.24, 0.26, sin(a) * 0.24)
		w.rotation = Vector3(0.0, -a, 0.0)
		w.rotate_object_local(Vector3.FORWARD, -0.5)
		add_child(w)
	# Flames: thin glowing tongues that flicker and sway.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 9:
		var inner := k >= 6
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(0.1, 0.15) if inner else rng.randf_range(0.13, 0.22)
		cone.height = rng.randf_range(0.7, 1.0) if inner else rng.randf_range(0.9, 1.6)
		cone.radial_segments = 4
		cone.rings = 1
		var m := MeshInstance3D.new()
		m.mesh = Game.flat_mesh(cone)
		var col := Color(1.0, 0.85, 0.4) if inner else Color(1.0, rng.randf_range(0.35, 0.55), 0.1)
		var mat := Game.material(col, 4.0 if inner else 2.6)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position.y = cone.height * 0.5
		var holder := Node3D.new()
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.08) if inner else rng.randf_range(0.05, 0.2)
		holder.position = Vector3(cos(a) * r, 0.1, sin(a) * r)
		holder.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		holder.set_meta("tilt", holder.rotation)
		holder.add_child(m)
		add_child(holder)
		_flames.append(holder)
	var embers := CPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 2.2
	embers.position = Vector3(0.0, 0.4, 0.0)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.3
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.gravity = Vector3(0.0, 0.6, 0.0)
	embers.initial_velocity_min = 0.4
	embers.initial_velocity_max = 1.0
	var ember := BoxMesh.new()
	ember.size = Vector3(0.035, 0.035, 0.035)
	embers.mesh = ember
	embers.material_override = Game.material(Color(1.0, 0.55, 0.15), 4.0)
	add_child(embers)
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0.0, 1.0, 0.0)
	_fire_light.light_color = Color(1.0, 0.6, 0.32)
	_fire_light.omni_range = 11.0
	_fire_light.omni_attenuation = 1.4
	_fire_light.shadow_enabled = true
	add_child(_fire_light)


func _build_logs() -> void:
	var bark := Game.material(Color(0.32, 0.22, 0.15))
	for l in LOGS:
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = LOG_RADIUS
		log_mesh.bottom_radius = LOG_RADIUS
		log_mesh.height = l[2]
		log_mesh.radial_segments = 7
		var m := MeshInstance3D.new()
		m.mesh = Game.flat_mesh(log_mesh)
		m.material_override = bark
		m.position = l[0] + Vector3(0.0, LOG_RADIUS, 0.0)
		m.rotation_degrees = Vector3(0.0, l[1], 90.0)
		add_child(m)


## The Keep's broken walls behind the fire (the Keep proper comes later).
func _build_ruin() -> void:
	var pieces := [
		["wall_broken", Vector3(-6.5, 0, -8.0), 8.0, true],
		["wall_cracked", Vector3(-3.0, 0, -9.0), 0.0, true],
		["pillar", Vector3(-1.0, 0, -9.0), 0.0, true],
		["wall_broken", Vector3(3.6, 0, -9.0), 180.0, true],
		["pillar_decorated", Vector3(6.2, 0, -8.6), 0.0, true],
		["wall_cracked", Vector3(8.6, 0, -7.0), -35.0, true],
		["banner_patternA_red", Vector3(-3.0, 0, -9.05), 0.0, false],
		["rubble_half", Vector3(0.6, 0, -7.6), 160.0, false],
		["barrel_large", Vector3(-5.2, 0, -4.8), 0.0, true],
		["crates_stacked", Vector3(5.6, 0, -4.4), -20.0, true],
		["sword_shield_broken", Vector3(3.6, 0, 0.9), 40.0, false],
	]
	for p in pieces:
		var n := Game.model(DUNGEON + str(p[0]) + ".gltf")
		if n == null:
			continue
		n.position = p[1]
		n.rotation_degrees.y = p[2]
		n.scale = Vector3.ONE * 0.8
		add_child(n)
		if not p[3]:
			continue
		var name_s := str(p[0])
		var at := Vector2(p[1].x, p[1].z)
		if name_s.begins_with("wall"):
			var along := Vector2.from_angle(-deg_to_rad(p[2]))
			var k := -1.6
			while k <= 1.61:
				Game.add_obstacle(at + along * k, 0.55)
				k += 0.66
		else:
			Game.add_obstacle(at, 0.8)
