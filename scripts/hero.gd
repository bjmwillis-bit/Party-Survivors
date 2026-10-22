extends Node3D
## One party member: their stats, auto attack, passive, health,
## and the crisp grey-box look (step bob, dust, hit flash, attack lunge).
##
## Grey-box kits, simplified from Heroes Final:
## - Solenne: cuts in an arc. Gains Contempt when struck (+5% damage per stack).
## - Cenhelm: slams everything around him; damage scales with his max HP.
##   Takes part of every hit aimed at his allies.
## - Kheiron: fires bolts and heals the most hurt ally. He cannot be healed.

const DATA := {
	"solenne": {
		"name": "Solenne", "hp": 120.0, "interval": 0.75, "damage": 14.0,
		"color": Color(0.92, 0.9, 0.86), "accent": Color(0.78, 0.12, 0.12),
	},
	"cenhelm": {
		"name": "Cenhelm", "hp": 190.0, "interval": 1.5, "damage": 8.0,
		"color": Color(0.45, 0.36, 0.28), "accent": Color(0.95, 0.6, 0.15),
	},
	"kheiron": {
		"name": "Kheiron", "hp": 95.0, "interval": 0.9, "damage": 9.0,
		"color": Color(0.32, 0.42, 0.3), "accent": Color(0.55, 0.95, 0.55),
	},
}

var kind := ""
var hero_name := ""
var color := Color.WHITE
var accent := Color.WHITE
var max_hp := 100.0
var hp := 100.0
var downed := false
var is_leader := false
var revive_progress := 0.0

# Numbers that upgrades can change.
var base_damage := 10.0
var attack_interval := 1.0
var damage_mult := 1.0
var area_mult := 1.0
var rate_mult := 1.0
var heal_mult := 1.0
var extra_bolts := 0
var contempt_cap := 10
var intercept_share := 0.25

var contempt := 0
var facing := 0.0 # where the hero wants to face (radians)
var face_lock := 0.0 # while > 0, the hero keeps facing their attack
var move_dir := Vector3.ZERO
var moving := false

var _attack_timer := 0.4
var _heal_timer := 2.0
var _contempt_hit_cd := 0.0
var _contempt_decay := 0.0
var _flash := 0.0
var _hurt_flash_cd := 0.0
var _bob := 0.0
var _step_timer := 0.0
var _lunge := 0.0
var _body: Node3D
var _mat: StandardMaterial3D
var _lead_ring: MeshInstance3D
var _revive_ring: MeshInstance3D


func setup(hero_kind: String) -> void:
	kind = hero_kind
	var d: Dictionary = DATA[kind]
	hero_name = d["name"]
	color = d["color"]
	accent = d["accent"]
	max_hp = d["hp"]
	hp = max_hp
	base_damage = d["damage"]
	attack_interval = d["interval"]
	_build_visual()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_hurt_flash_cd = maxf(0.0, _hurt_flash_cd - delta)
	face_lock = maxf(0.0, face_lock - delta)
	if _flash > 0.0:
		_mat.albedo_color = Color.WHITE
	elif downed:
		_mat.albedo_color = color.darkened(0.55)
	else:
		_mat.albedo_color = color
	_lead_ring.visible = is_leader and not downed
	_revive_ring.visible = downed

	if downed:
		var frac: float = revive_progress / Game.party.revive_time
		_revive_ring.scale = Vector3.ONE * (0.4 + frac * 1.2)
		_body.rotation.x = lerpf(_body.rotation.x, -1.45, 1.0 - exp(-12.0 * delta))
		_body.position.y = 0.2
		return
	_body.rotation.x = lerpf(_body.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))

	# Snap to face the new direction almost instantly.
	rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-30.0 * delta))

	# Stepping: a quick bob and sway, with a puff of dust on each footfall.
	if moving:
		_bob += delta * 14.0
		_body.position.y = absf(sin(_bob)) * 0.12
		_body.rotation.z = sin(_bob) * 0.06
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = PI / 14.0
			Game.fx.dust(position)
	else:
		_bob = 0.0
		_body.position.y = move_toward(_body.position.y, 0.0, delta * 2.0)
		_body.rotation.z = 0.0

	# A short lunge forward when attacking.
	_lunge = maxf(0.0, _lunge - delta * 6.0)
	_body.position.z = _lunge * 0.35

	_tick_attack(delta)
	_tick_passives(delta)


# --- Attacks -----------------------------------------------------------------

func _tick_attack(delta: float) -> void:
	_attack_timer -= delta * rate_mult * Game.party.haste
	if _attack_timer > 0.0:
		return
	var attacked := false
	match kind:
		"solenne":
			attacked = _attack_solenne()
		"cenhelm":
			attacked = _attack_cenhelm()
		"kheiron":
			attacked = _attack_kheiron()
	# No target in range: check again shortly.
	_attack_timer = attack_interval if attacked else 0.1


func _power() -> float:
	var p := base_damage * damage_mult
	if kind == "cenhelm":
		p += max_hp * 0.04 # "Scales with his max HP."
	if kind == "solenne":
		p *= 1.0 + 0.05 * contempt
	if is_leader:
		p *= Game.party.lead_bonus
	return p


func _my_xz() -> Vector2:
	return Vector2(position.x, position.z)


func _attack_solenne() -> bool:
	var reach := 3.0 * area_mult
	var me := _my_xz()
	var target: int = Game.enemies.nearest(me, reach + 0.6)
	if target < 0:
		return false
	var to: Vector2 = Game.enemies.pos[target] - me
	var dir := to.normalized()
	var yaw := atan2(to.x, to.y)
	var half := deg_to_rad(65.0)
	var dmg := _power()
	for i in Game.enemies.query(me, reach):
		var rel: Vector2 = Game.enemies.pos[i] - me
		if rel.length() > 0.001 and absf(dir.angle_to(rel)) > half:
			continue
		Game.enemies.damage(i, dmg, rel.normalized(), 6.0)
	Game.fx.slash(position, yaw, reach, half, accent)
	facing = yaw
	face_lock = 0.15
	_lunge = 1.0
	return true


func _attack_cenhelm() -> bool:
	var reach := 3.2 * area_mult
	var me := _my_xz()
	if Game.enemies.nearest(me, reach + 0.5) < 0:
		return false
	var dmg := _power()
	for i in Game.enemies.query(me, reach):
		var rel: Vector2 = Game.enemies.pos[i] - me
		var push := rel.normalized() if rel.length() > 0.01 else Vector2.RIGHT
		Game.enemies.damage(i, dmg, push, 11.0)
	Game.fx.ring(position, reach, accent, 0.22)
	if is_leader:
		Game.add_shake(0.12)
	_lunge = 0.6
	return true


func _attack_kheiron() -> bool:
	var me := _my_xz()
	var target: int = Game.enemies.nearest(me, 13.0)
	if target < 0:
		return false
	var to: Vector2 = (Game.enemies.pos[target] - me).normalized()
	var count := 1 + extra_bolts
	for b in count:
		var spread := (b - (count - 1) * 0.5) * 0.18
		Game.fx.bolt(position + Vector3(0.0, 1.0, 0.0), to.rotated(spread), _power(), 0, accent)
	facing = atan2(to.x, to.y)
	face_lock = 0.12
	_lunge = 0.4
	return true


# --- Passives ----------------------------------------------------------------

func _tick_passives(delta: float) -> void:
	if kind == "kheiron":
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = 2.5
			var t = Game.party.lowest_health_ally(self)
			if t != null:
				t.heal(7.0 * heal_mult)
				Game.fx.ring(t.position, 0.9, accent, 0.3)
	if kind == "solenne":
		_contempt_hit_cd = maxf(0.0, _contempt_hit_cd - delta)
		if contempt > 0:
			_contempt_decay -= delta
			if _contempt_decay <= 0.0:
				contempt -= 1
				_contempt_decay = 3.0


# --- Health ------------------------------------------------------------------

func take_damage(amount: float) -> void:
	if downed:
		return
	hp -= amount
	if _hurt_flash_cd <= 0.0:
		_flash = 0.08
		_hurt_flash_cd = 0.3
	if kind == "solenne" and _contempt_hit_cd <= 0.0:
		contempt = mini(contempt + 1, contempt_cap)
		_contempt_hit_cd = 0.4
		_contempt_decay = 3.0
	if hp <= 0.0:
		hp = 0.0
		downed = true
		revive_progress = 0.0
		moving = false
		Game.party.on_hero_downed(self)


func heal(amount: float) -> void:
	if downed or kind == "kheiron": # Kheiron is Incurable.
		return
	hp = minf(max_hp, hp + amount)


func revive() -> void:
	downed = false
	revive_progress = 0.0
	hp = max_hp * 0.35


# --- Look --------------------------------------------------------------------
# Grey-box shapes: a faceted body, a head, and one signature prop in the
# hero's accent colour, so each reads at a distance. Real models replace this.

func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	_mat = Game.material(color)
	var accent_mat := Game.material(accent, 0.5)
	var size := 1.0
	if kind == "cenhelm":
		size = 1.25
	elif kind == "kheiron":
		size = 0.95

	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.36 * size
	torso_mesh.height = 1.5 * size
	torso_mesh.radial_segments = 8
	torso_mesh.rings = 2
	_part(Game.flat_mesh(torso_mesh), _mat, Vector3(0.0, torso_mesh.height * 0.5, 0.0))

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22 * size
	head_mesh.height = 0.44 * size
	head_mesh.radial_segments = 6
	head_mesh.rings = 3
	var head_y := torso_mesh.height + 0.12 * size
	_part(Game.flat_mesh(head_mesh), _mat, Vector3(0.0, head_y, 0.0))

	# A band across the eyes shows which way the hero faces.
	var eyes := BoxMesh.new()
	eyes.size = Vector3(0.26 * size, 0.07, 0.08)
	_part(eyes, accent_mat, Vector3(0.0, head_y + 0.02, 0.19 * size))

	match kind:
		"solenne":
			var cape := BoxMesh.new()
			cape.size = Vector3(0.62, 1.05, 0.08)
			_part(cape, accent_mat, Vector3(0.0, 1.0, -0.38))
			var sword := BoxMesh.new()
			sword.size = Vector3(0.07, 1.25, 0.07)
			var s := _part(sword, Game.material(Color(0.95, 0.95, 1.0), 0.2), Vector3(0.42, 0.9, 0.22))
			s.rotation_degrees = Vector3(35.0, 0.0, 0.0)
		"cenhelm":
			var shoulders := BoxMesh.new()
			shoulders.size = Vector3(1.15, 0.3, 0.55)
			_part(shoulders, Game.material(color.darkened(0.25)), Vector3(0.0, 1.6, 0.0))
			var horn := CylinderMesh.new()
			horn.top_radius = 0.03
			horn.bottom_radius = 0.13
			horn.height = 0.6
			horn.radial_segments = 6
			var h := _part(Game.flat_mesh(horn), accent_mat, Vector3(0.62, 1.25, 0.0))
			h.rotation_degrees = Vector3(0.0, 0.0, -70.0)
		"kheiron":
			var staff := CylinderMesh.new()
			staff.top_radius = 0.04
			staff.bottom_radius = 0.05
			staff.height = 2.0
			staff.radial_segments = 5
			_part(staff, Game.material(Color(0.4, 0.3, 0.2)), Vector3(0.42, 1.0, 0.15))
			var tip := SphereMesh.new()
			tip.radius = 0.12
			tip.height = 0.24
			tip.radial_segments = 5
			tip.rings = 2
			_part(Game.flat_mesh(tip), Game.material(accent, 1.5), Vector3(0.42, 2.05, 0.15))

	_lead_ring = _flat_ring(0.62, 0.78, Color(1.0, 0.82, 0.3, 0.9))
	_revive_ring = _flat_ring(0.85, 1.0, Color(0.5, 1.0, 0.5, 0.8))
	_revive_ring.visible = false


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	_body.add_child(m)
	return m


func _flat_ring(inner: float, outer: float, ring_color: Color) -> MeshInstance3D:
	var ring := TorusMesh.new()
	ring.inner_radius = inner
	ring.outer_radius = outer
	ring.rings = 24
	ring.ring_segments = 3
	var m := MeshInstance3D.new()
	m.mesh = ring
	m.material_override = Game.effect_material(ring_color)
	m.scale = Vector3(1.0, 0.15, 1.0)
	m.position.y = 0.05
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m
