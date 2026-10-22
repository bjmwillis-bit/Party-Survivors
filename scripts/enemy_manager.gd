extends Node3D
## The horde. Enemies are plain data in arrays (not individual nodes) and are
## drawn in one batch with a MultiMesh, so hundreds can be on screen at once.
##
## A spatial grid (buckets of nearby enemies) keeps "who is near this point?"
## questions fast, for attacks and for enemies pushing each other apart.

const MAX_ENEMIES := 650
const CELL := 0.8 # about the size of one enemy, so neighbour checks stay small

# Per enemy type: 0 = shambler, 1 = runner (appears after 75 seconds).
const HP := [18.0, 9.0]
const SPEED := [2.5, 4.3]
const SCALE := [1.0, 0.75]
const KNOCK_TAKEN := [1.0, 1.4]
const COLORS := [Color(0.36, 0.22, 0.2), Color(0.58, 0.44, 0.24)]
const CONTACT_DPS := 9.0

var count := 0
var pos := PackedVector2Array() # x and z on the ground
var knock := PackedVector2Array()
var hp := PackedFloat32Array()
var flash := PackedFloat32Array()
var kind := PackedByteArray()
var yaw := PackedFloat32Array()
var sep := PackedVector2Array() # last push-apart force (recomputed every other frame)

## How long the horde took last frame, in milliseconds (for tuning).
var cost_ms := 0.0

var _grid := {}
var _spawn_acc := 0.0
var _time := 0.0
var _mm: MultiMesh
var _buffer := PackedFloat32Array() # 16 numbers per enemy: 12 for position/rotation/size, 4 for colour
var _frame := 0


func _ready() -> void:
	pos.resize(MAX_ENEMIES)
	knock.resize(MAX_ENEMIES)
	hp.resize(MAX_ENEMIES)
	flash.resize(MAX_ENEMIES)
	kind.resize(MAX_ENEMIES)
	yaw.resize(MAX_ENEMIES)
	sep.resize(MAX_ENEMIES)
	_buffer.resize(MAX_ENEMIES * 16)

	var body := CapsuleMesh.new()
	body.radius = 0.38
	body.height = 1.3
	body.radial_segments = 6
	body.rings = 1
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = Game.flat_mesh(body)
	_mm.instance_count = MAX_ENEMIES
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var mat := Game.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mmi.material_override = mat
	add_child(mmi)


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_time += delta
	_frame += 1
	_remove_dead()
	_spawn(delta)
	_rebuild_grid()
	_move(delta)
	_render()
	cost_ms = (Time.get_ticks_usec() - start) / 1000.0


# --- Questions other systems ask ---------------------------------------------

## Indices of living enemies within radius `r` of `center`.
func query(center: Vector2, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := r * r
	var c0 := Vector2i(floori((center.x - r) / CELL), floori((center.y - r) / CELL))
	var c1 := Vector2i(floori((center.x + r) / CELL), floori((center.y + r) / CELL))
	for gx in range(c0.x, c1.x + 1):
		for gy in range(c0.y, c1.y + 1):
			var cell = _grid.get(Vector2i(gx, gy))
			if cell == null:
				continue
			for j in cell:
				if j < count and hp[j] > 0.0 and center.distance_squared_to(pos[j]) <= r2:
					out.append(j)
	return out


## Index of the nearest living enemy within `max_r`, or -1.
func nearest(center: Vector2, max_r: float) -> int:
	var best := -1
	var best_d := max_r * max_r
	for i in count:
		if hp[i] <= 0.0:
			continue
		var d := center.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## Index of the living enemy nearest to `from`, counting only enemies within
## `radius` of `center` (used for followers on a leash), or -1.
func nearest_in_circle(from: Vector2, center: Vector2, radius: float) -> int:
	var best := -1
	var best_d := INF
	var r2 := radius * radius
	for i in count:
		if hp[i] <= 0.0 or center.distance_squared_to(pos[i]) > r2:
			continue
		var d := from.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func damage(i: int, amount: float, dir: Vector2, force: float) -> void:
	if i < 0 or i >= count or hp[i] <= 0.0:
		return
	hp[i] -= amount
	flash[i] = 0.1
	knock[i] += dir * force * KNOCK_TAKEN[kind[i]]
	if hp[i] <= 0.0:
		Game.kills += 1
		Game.xp.drop(pos[i], 1)
		Game.fx.death_puff(Vector3(pos[i].x, 0.5, pos[i].y), COLORS[kind[i]])


# --- Each frame --------------------------------------------------------------

func _remove_dead() -> void:
	var i := count - 1
	while i >= 0:
		if hp[i] <= 0.0:
			var last := count - 1
			pos[i] = pos[last]
			knock[i] = knock[last]
			hp[i] = hp[last]
			flash[i] = flash[last]
			kind[i] = kind[last]
			yaw[i] = yaw[last]
			sep[i] = sep[last]
			count -= 1
		i -= 1


func _spawn(delta: float) -> void:
	var t: float = Game.time_alive
	var rate := 1.6 + t * 0.045 + pow(t / 60.0, 2.0) * 0.12 # enemies per second
	_spawn_acc += rate * delta
	var l = Game.party.leader()
	if l == null:
		return
	var center := Vector2(l.position.x, l.position.z)
	var a: float = Game.main.ARENA_HALF
	var toughness := 1.0 + t / 140.0
	while _spawn_acc >= 1.0 and count < MAX_ENEMIES:
		_spawn_acc -= 1.0
		var k := 0
		if t > 75.0 and randf() < 0.3:
			k = 1
		# Appear in a ring just off screen.
		var ang := randf() * TAU
		var p := center + Vector2(cos(ang), sin(ang)) * randf_range(19.0, 24.0)
		p.x = clampf(p.x, -a, a)
		p.y = clampf(p.y, -a, a)
		pos[count] = p
		knock[count] = Vector2.ZERO
		hp[count] = HP[k] * toughness
		flash[count] = 0.0
		kind[count] = k
		yaw[count] = 0.0
		sep[count] = Vector2.ZERO
		count += 1
	if count >= MAX_ENEMIES:
		_spawn_acc = 0.0


func _rebuild_grid() -> void:
	_grid.clear()
	for i in count:
		var c := Vector2i(floori(pos[i].x / CELL), floori(pos[i].y / CELL))
		var cell = _grid.get(c)
		if cell == null:
			_grid[c] = [i]
		else:
			cell.append(i)


func _move(delta: float) -> void:
	var targets: Array = Game.party.alive_heroes()
	if targets.is_empty():
		return
	var target_xz: Array[Vector2] = []
	for h in targets:
		target_xz.append(Vector2(h.position.x, h.position.z))
	var touching := PackedInt32Array()
	touching.resize(targets.size())
	var decay := exp(-7.0 * delta)

	for i in count:
		var p: Vector2 = pos[i]
		# Head for the nearest living hero.
		var best := 0
		var best_d := INF
		for h in target_xz.size():
			var dd := p.distance_squared_to(target_xz[h])
			if dd < best_d:
				best_d = dd
				best = h
		var dist := sqrt(best_d)
		var v := Vector2.ZERO
		if dist > 0.6:
			v = (target_xz[best] - p) / dist * SPEED[kind[i]]
		# Push away from neighbours so the horde spreads instead of stacking.
		# Half the horde recalculates each frame; the rest reuse last frame's push.
		if (i + _frame) % 2 == 0:
			var push := Vector2.ZERO
			var cx := floori(p.x / CELL)
			var cy := floori(p.y / CELL)
			for gx in range(cx - 1, cx + 2):
				for gy in range(cy - 1, cy + 2):
					var cell = _grid.get(Vector2i(gx, gy))
					if cell == null:
						continue
					for j in cell:
						if j == i:
							continue
						var d: Vector2 = p - pos[j]
						var l2 := d.length_squared()
						if l2 < 0.5 and l2 > 0.0001:
							var l := sqrt(l2)
							push += d / l * (0.71 - l)
			sep[i] = push
		knock[i] = knock[i] * decay
		pos[i] = p + (v + sep[i] * 6.0 + knock[i]) * delta
		if v.length_squared() > 0.01:
			yaw[i] = atan2(v.x, v.y)
		flash[i] = maxf(0.0, flash[i] - delta)
		if dist < 0.9:
			touching[best] += 1

	# Contact damage grows with the crowd, but not linearly, so being
	# surrounded is dangerous without being instant death.
	var toughness := 1.0 + Game.time_alive / 400.0
	for h in targets.size():
		if touching[h] > 0:
			var crowd := pow(float(mini(touching[h], 5)), 0.7)
			Game.party.apply_contact_damage(targets[h], CONTACT_DPS * crowd * toughness * delta)


func _render() -> void:
	# Fill one big array and hand it over in a single call. Much faster than
	# setting each enemy separately. Layout per enemy: the 3x4 transform
	# row by row (basis.x.x, basis.y.x, basis.z.x, origin.x, ...), then RGBA.
	for i in count:
		var k := kind[i]
		var s: float = SCALE[k]
		var c := cos(yaw[i]) * s
		var sn := sin(yaw[i]) * s
		var y := 0.65 * s + absf(sin(_time * 9.0 + float(i))) * 0.08
		var col: Color = Color.WHITE if flash[i] > 0.0 else COLORS[k]
		var o := i * 16
		_buffer[o] = c
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = sn
		_buffer[o + 3] = pos[i].x
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = s
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = y
		_buffer[o + 8] = -sn
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = c
		_buffer[o + 11] = pos[i].y
		_buffer[o + 12] = col.r
		_buffer[o + 13] = col.g
		_buffer[o + 14] = col.b
		_buffer[o + 15] = 1.0
	_mm.buffer = _buffer
	_mm.visible_instance_count = count
