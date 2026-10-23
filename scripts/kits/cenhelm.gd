extends "res://scripts/kits/kit.gd"
## Cenhelm. Basic: one-two punches, each splashing where it lands.
## Q Walk Out: leaps to the furthest enemy within 8 m; ×1.5 in 4 m on landing.
## E The Horn: after a 0.5 s wind-up, everything on screen is slowed 40% for
##   6 s, takes ×0.5 each second and is pushed 0.5 m away each tick.

const FIST_REACH := 1.9
const SPLASH := 1.1
const LEAP_RANGE := 8.0
const LEAP_RADIUS := 4.0
const HORN_RADIUS := 22.0 # the whole screen
const HORN_TIME := 6.0
const HORN_SLOW := 0.4
const HORN_PUSH := 3.5 # a knock that carries an enemy about 0.5 m

var _side := 1.0
var _freca := 0 # punches left at double damage


func attack() -> bool:
	var splash := SPLASH * h.area()
	var dir := aim(FIST_REACH + splash)
	if dir == Vector2.ZERO or (h.is_leader and not leader_has_target(dir, FIST_REACH + splash, deg_to_rad(60.0))):
		return false
	_punch(dir)
	for k in range(1, h.instances()):
		after(0.1 * k, func() -> void: _punch(dir))
	return true


func _punch(dir: Vector2) -> void:
	_side = -_side
	var splash := SPLASH * h.area()
	var side := Vector2(-dir.y, dir.x)
	var impact := me() + dir * FIST_REACH * 0.8 + side * 0.3 * _side
	var dmg := h.power()
	if _freca > 0:
		dmg *= 2.0
		_freca -= 1
	for i in Game.enemies.query(impact, splash):
		var rel: Vector2 = Game.enemies.pos[i] - impact
		Game.enemies.damage(i, dmg, rel.normalized() if rel.length() > 0.05 else dir, 5.0)
	Game.fx.ring(at3(impact), splash, h.accent, 0.15)
	h.face(dir)
	h.lunge(0.7)
	h.twist(0.35 * _side)


func skill() -> bool:
	var t := furthest_in(me(), LEAP_RANGE, me())
	if t < 0:
		return false
	var to: Vector2 = Game.enemies.pos[t]
	var d := to - me()
	if d.length() > 1.0:
		to -= d.normalized() * 0.8
	h.untargetable = true
	h.start_motion(at3(to), 0.45, 1.8, Callable(), _land)
	return true


func _land() -> void:
	h.untargetable = false
	var r := LEAP_RADIUS * h.area()
	hit_circle(me(), r, h.skill_power(1.5), 10.0)
	Game.fx.ring(h.position, r, h.accent, 0.25)
	Game.fx.ring(h.position, r * 0.5, Color.WHITE, 0.18)
	shake(0.3, 0.05)
	# Walk Out Together (bond): a small grove grows where he lands.
	if Game.party.bonds.has("bond_together"):
		var k = Game.party.hero("Kheiron")
		var hm: float = k.heal_mult if k != null else 1.0
		Game.party.place_grove(h.position, 3.0, 3.0, 0.015 * hm)


func skill_worth() -> bool:
	return Game.enemies.nearest(me(), LEAP_RANGE) >= 0 and Game.enemies.query(me(), LEAP_RANGE).size() >= 4


func ult() -> bool:
	h.hold_still(0.5, _blow)
	Game.fx.ring(h.position, 1.5, h.accent, 0.5)
	return true


func _blow() -> void:
	var at := me()
	var secs := 10.0 if h.has_mod("cen_u_long") else HORN_TIME
	if h.has_mod("cen_u_stun"):
		for i in Game.enemies.query(at, HORN_RADIUS):
			Game.enemies.stun(i, 1.5)
	Game.enemies.slow_in_radius(at, HORN_RADIUS, HORN_SLOW, secs)
	for k in int(secs):
		after(1.0 * (k + 1), func() -> void: _horn_tick(at))
	if h.has_mod("cen_u_heal"):
		for a in Game.party.heroes:
			a.heal(a.max_hp * 0.15)
	if h.has_mod("cen_u_freca"):
		_freca = 10
	# Back to Back (bond): everything in range turns on Solenne, and her
	# counters come twice as often for 6 s.
	var sol = Game.party.hero("Solenne")
	if Game.party.bonds.has("bond_back") and sol != null and not sol.downed:
		Game.enemies.taunt_in_radius(at, HORN_RADIUS, Game.party.heroes.find(sol), 6.0)
		sol.kit.taunting = maxf(sol.kit.taunting, 6.0)
		sol.kit.counter_boost = 6.0
		sol.taunt_time = maxf(sol.taunt_time, 6.0)
	Game.fx.ring(h.position, 16.0, h.accent, 0.6)
	Game.fx.ring(h.position, 8.0, h.accent, 0.45)
	Game.fx.ring(h.position, 3.0, Color.WHITE, 0.3)
	h.lunge(0.8)
	shake(0.4, 0.06)


func _horn_tick(at: Vector2) -> void:
	var dmg := h.ult_power(0.5)
	for i in Game.enemies.query(at, HORN_RADIUS):
		var rel: Vector2 = Game.enemies.pos[i] - at
		Game.enemies.damage(i, dmg, rel.normalized() if rel.length() > 0.05 else Vector2.UP, HORN_PUSH)
	Game.fx.ring(at3(at), 6.0, h.accent, 0.3)
