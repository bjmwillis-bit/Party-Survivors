extends "res://scripts/kits/kit.gd"
## Solenne. Basic: a sword swipe in an arc.
## Q Face Me: taunts enemies within 6 m for 8 s; while taunting, every blow
##   she takes has a 30% chance to counter with a straight 6 m stab.
## E Ultrix: a slash across, then a slash forwards, ×3 each.

const REACH := 3.0
const HALF := deg_to_rad(65.0)
const TAUNT_RADIUS := 6.0
const TAUNT_TIME := 8.0
const COUNTER_CHANCE := 0.3
const COUNTER_REACH := 6.0
const ULT_ACROSS := 4.0
const ULT_FORWARD := 6.0

var taunting := 0.0 # counters only happen while this is > 0
var counter_boost := 0.0 # Back to Back (bond): doubled counter chance


func attack() -> bool:
	var reach := REACH * h.area()
	var dir := aim(reach)
	if dir == Vector2.ZERO or (h.is_leader and not leader_has_target(dir, reach, HALF)):
		return false
	_swipe(dir)
	for k in range(1, h.instances()):
		after(0.13 * k, func() -> void:
			var d := aim(reach)
			_swipe(d if d != Vector2.ZERO else dir))
	return true


func _swipe(dir: Vector2) -> void:
	var reach := REACH * h.area()
	hit_arc(me(), dir, reach, HALF, h.power())
	Game.fx.slash(h.position, atan2(dir.x, dir.y), reach, HALF, h.accent)
	h.face(dir)
	h.lunge(1.0)


func skill() -> bool:
	var r := TAUNT_RADIUS * h.area()
	Game.enemies.taunt_in_radius(me(), r, Game.party.heroes.find(h), TAUNT_TIME)
	taunting = TAUNT_TIME
	h.taunt_time = TAUNT_TIME
	Game.fx.ring(h.position, r, h.accent, 0.35)
	shake(0.15)
	return true


func skill_worth() -> bool:
	return Game.enemies.query(me(), TAUNT_RADIUS).size() >= 3


func tick(delta: float) -> void:
	taunting = maxf(0.0, taunting - delta)
	counter_boost = maxf(0.0, counter_boost - delta)


func on_struck(attacker: int) -> void:
	if taunting > 0.0 and randf() < counter_chance():
		counter(attacker)


func counter_chance() -> float:
	return minf(1.0, COUNTER_CHANCE * (2.0 if counter_boost > 0.0 else 1.0))


## A straight stab at whoever struck her, through everything in the way.
func counter(attacker: int) -> void:
	var E = Game.enemies
	var target := attacker
	if target < 0 or target >= E.count or E.hp[target] <= 0.0:
		target = E.nearest(me(), COUNTER_REACH)
	if target < 0:
		return
	var rel: Vector2 = E.pos[target] - me()
	var dir: Vector2 = rel.normalized() if rel.length() > 0.01 else Vector2(sin(h.facing), cos(h.facing))
	var reach := COUNTER_REACH * h.area()
	hit_line(me(), me() + dir * reach, 0.7, h.skill_power(), 8.0)
	h.stats["counter"] += 1
	# Penance (bond): each counter heals the most hurt ally a little.
	if Game.party.bonds.has("bond_penance"):
		var low = Game.party.lowest_health_ally(null, 1.0)
		if low != null:
			low.heal(low.max_hp * 0.01)
	Game.fx.thrust(h.position, atan2(dir.x, dir.y), reach, h.accent)
	h.face(dir)
	h.lunge(1.0)


func ult() -> bool:
	var dir: Vector2 = h.aim_dir if h.aim_dir != Vector2.ZERO else Vector2(sin(h.facing), cos(h.facing))
	_ultrix(dir, 0)
	return true


func _ultrix(dir: Vector2, round_n: int) -> void:
	h.hold_still(0.6)
	# Across: a wide cut in front of her.
	var across := ULT_ACROSS * h.area()
	var half := deg_to_rad(90.0)
	hit_arc(me(), dir, across, half, h.ult_power(3.0), 9.0)
	Game.fx.slash(h.position, atan2(dir.x, dir.y), across, half, Color(1.0, 0.2, 0.15))
	h.face(dir, 0.7)
	h.lunge(1.0)
	shake(0.25)
	after(0.28, func() -> void:
		# Forwards: a long straight cut.
		var reach := ULT_FORWARD * h.area()
		var a := me()
		var b := a + dir * reach
		hit_line(a, b, 1.1, h.ult_power(3.0), 12.0)
		Game.fx.thrust(h.position, atan2(dir.x, dir.y), reach, Color(1.0, 0.15, 0.1))
		h.lunge(1.0)
		shake(0.35, 0.05)
		if h.has_mod("sol_u_flames"):
			for k in 3:
				Game.fx.bolt(h.position + Vector3(0.0, 0.7, 0.0), dir.rotated((k - 1) * 0.2), h.ult_power(1.5), 99,
					Color(1.0, 0.45, 0.1), 15.0, 2.2, 0.8)
		if h.has_mod("sol_u_scorch"):
			Game.fx.fire_line(at3(a), at3(b), 1.0, 4.0, h.ult_power(0.8))
		if h.has_mod("sol_u_unbowed") and round_n == 0:
			Game.enemies.taunt_in_radius(me(), 8.0, Game.party.heroes.find(h), 4.0)
			taunting = maxf(taunting, 4.0)
			h.taunt_time = maxf(h.taunt_time, 4.0)
			Game.fx.ring(h.position, 8.0, h.accent, 0.35)
		if h.has_mod("sol_u_twice") and round_n == 0:
			after(0.3, func() -> void: _ultrix(dir, 1)))
