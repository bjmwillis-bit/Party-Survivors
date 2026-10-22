extends Node3D
## Treasure chests dropped by elites and bosses.
##
## Walk the leader onto a chest to open it: it charges up for 2 seconds,
## glowing in its rarity colour so you can guess what's coming, then pops.
## For now every chest holds gold; relics come later.

const CHARGE_TIME := 2.0
const OPEN_RANGE := 1.6
const TIERS := {
	"common": {"gold": 10, "color": Color(0.85, 0.85, 0.85)},
	"rare": {"gold": 25, "color": Color(0.3, 0.6, 1.0)},
	"epic": {"gold": 50, "color": Color(0.72, 0.32, 1.0)},
	"legendary": {"gold": 100, "color": Color(1.0, 0.75, 0.2)},
}

var opened := 0
var _chests: Array = []


func spawn(at: Vector2, tier: String) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, 0.0, at.y)
	add_child(root)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.55, 0.6)
	body.mesh = box
	body.material_override = Game.material(Color(0.42, 0.28, 0.16))
	body.position.y = 0.3
	root.add_child(body)
	var lid := MeshInstance3D.new()
	var lid_box := BoxMesh.new()
	lid_box.size = Vector3(0.95, 0.18, 0.65)
	lid.mesh = lid_box
	var col: Color = TIERS[tier]["color"]
	var glow := Game.material(col, 0.6)
	lid.material_override = glow
	lid.position.y = 0.66
	root.add_child(lid)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.9
	ring.mesh = torus
	ring.material_override = Game.effect_material(Color(col.r, col.g, col.b, 0.6))
	ring.scale = Vector3(1.0, 0.1, 1.0)
	ring.position.y = 0.05
	root.add_child(ring)
	_chests.append({"root": root, "lid": lid, "glow": glow, "tier": tier, "charging": false, "t": 0.0})
	Game.fx.ring(root.position, 1.5, col, 0.3)


## Picks a tier for an elite's chest: mostly common, sometimes better.
static func roll_tier() -> String:
	var r := randf()
	if r < 0.06:
		return "legendary"
	if r < 0.2:
		return "epic"
	if r < 0.5:
		return "rare"
	return "common"


func _process(delta: float) -> void:
	var l = Game.party.leader()
	var i := _chests.size() - 1
	while i >= 0:
		var c: Dictionary = _chests[i]
		var root: Node3D = c["root"]
		if not c["charging"]:
			root.rotation.y += delta * 0.8
			if l != null and Vector2(l.position.x, l.position.z).distance_to(Vector2(root.position.x, root.position.z)) < OPEN_RANGE:
				c["charging"] = true
		else:
			c["t"] += delta
			var p: float = c["t"] / CHARGE_TIME
			# Rising, shaking and glowing harder as it charges.
			root.position.y = 0.4 * p
			root.rotation.y += delta * (2.0 + 14.0 * p)
			root.scale = Vector3.ONE * (1.0 + 0.15 * sin(c["t"] * 30.0) * p)
			c["glow"].emission_energy_multiplier = 0.6 + 4.0 * p
			if c["t"] >= CHARGE_TIME:
				_pop(c)
				_chests.remove_at(i)
		i -= 1


func _pop(c: Dictionary) -> void:
	var root: Node3D = c["root"]
	var tier: String = c["tier"]
	var col: Color = TIERS[tier]["color"]
	var gold: int = TIERS[tier]["gold"]
	var at := Vector3(root.position.x, 0.0, root.position.z)
	Game.fx.ring(at, 3.0, col, 0.35)
	Game.fx.ring(at, 1.5, Color.WHITE, 0.2)
	for k in 6:
		Game.fx.death_puff(at + Vector3(randf_range(-0.6, 0.6), 0.8, randf_range(-0.6, 0.6)), col)
	Game.fx.float_text(at + Vector3(0.0, 1.5, 0.0), "+%d gold" % gold, Color(1.0, 0.85, 0.3), 1.4)
	Game.add_shake(0.2)
	Game.main.add_gold(gold)
	opened += 1
	root.queue_free()
	Game.main.on_chest_opened(opened)
