extends Node3D
## XP shards dropped by enemies. Like enemies, they're plain data drawn in one
## batch. Shards near the leader pop up, then fly in and are collected.

const MAX_SHARDS := 1200

var count := 0
var pos := PackedVector2Array()
var value := PackedInt32Array()
var flying := PackedByteArray()
var speed := PackedFloat32Array()

var magnet := 2.6 # pickup range; upgrades raise it

var _time := 0.0
var _mm: MultiMesh
var _buffer := PackedFloat32Array()


func _ready() -> void:
	pos.resize(MAX_SHARDS)
	value.resize(MAX_SHARDS)
	flying.resize(MAX_SHARDS)
	speed.resize(MAX_SHARDS)
	_buffer.resize(MAX_SHARDS * 12)
	var gem := SphereMesh.new()
	gem.radius = 0.14
	gem.height = 0.3
	gem.radial_segments = 4
	gem.rings = 2
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = Game.flat_mesh(gem)
	_mm.instance_count = MAX_SHARDS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = Game.material(Color(0.4, 0.85, 1.0), 1.2)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func drop(p: Vector2, v: int) -> void:
	if count >= MAX_SHARDS:
		# Too many on the ground: fold the value into an existing shard.
		value[randi() % count] += v
		return
	pos[count] = p
	value[count] = v
	flying[count] = 0
	speed[count] = 0.0
	count += 1


func _process(delta: float) -> void:
	_time += delta
	var l = Game.party.leader()
	if l == null:
		return
	var lp := Vector2(l.position.x, l.position.z)
	var m2 := magnet * magnet
	var i := 0
	while i < count:
		var to: Vector2 = lp - pos[i]
		var d2 := to.length_squared()
		if flying[i] == 0 and d2 < m2:
			flying[i] = 1
			speed[i] = -4.0 # a little pop away before flying in
		if flying[i] == 1:
			var d := sqrt(d2)
			if d < 0.5:
				var v := value[i]
				_remove(i)
				Game.main.gain_xp(v)
				continue
			speed[i] += 45.0 * delta
			pos[i] += to / d * speed[i] * delta
		i += 1
	_render()


func _remove(i: int) -> void:
	var last := count - 1
	pos[i] = pos[last]
	value[i] = value[last]
	flying[i] = flying[last]
	speed[i] = speed[last]
	count -= 1


func _render() -> void:
	# Same single-array trick as the enemies: 12 numbers per shard.
	for i in count:
		var a := _time * 2.5 + float(i)
		var c := cos(a)
		var sn := sin(a)
		var o := i * 12
		_buffer[o] = c
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = sn
		_buffer[o + 3] = pos[i].x
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = 1.0
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = 0.35 + sin(_time * 3.0 + float(i)) * 0.06
		_buffer[o + 8] = -sn
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = c
		_buffer[o + 11] = pos[i].y
	_mm.buffer = _buffer
	_mm.visible_instance_count = count
