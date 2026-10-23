extends "res://scripts/kits/kit.gd"
## Rhian. Basic: a piercing forward stab, 4 m. Each stab that lands makes the
##   next come 20% faster, up to 5 times (+100%), as long as she keeps hitting.
## Q Hold the Line: spins her glaive; everything within 7 m is knocked back to
##   7 m and takes ×0.8.
## E The Line: a battle cry and stance (0.5 s), then three lightning stabs:
##   to the furthest enemy in the leash, then the furthest from there, twice
##   more. ×2.5 to everything she passes.

const REACH := 4.0
const STACK := 0.2
const MAX_STACKS := 5
const FORGET := 2.5 # seconds without a hit before the stacks fall away
const SPIN_RADIUS := 7.0
const LINE_MULT := 2.5
const STRIKE_TIME := 0.11
const GOLD_RED := Color(1.0, 0.55, 0.3)

var stacks := 0
var _since_hit := 0.0
var _line_left := 0


func attack() -> bool:
	var reach := REACH * h.area()
	var dir := aim(reach)
	if dir == Vector2.ZERO or (h.is_leader and not leader_has_target(dir, reach, deg_to_rad(30.0))):
		return false
	_stab(dir)
	for k in range(1, h.instances()):
		after(0.12 * k, func() -> void:
			var d := aim(reach)
			_stab(d if d != Vector2.ZERO else dir))
	return true


func _stab(dir: Vector2) -> void:
	var reach := REACH * h.area()
	var n := hit_line(me(), me() + dir * reach, 0.6, h.power(), 6.0)
	Game.fx.thrust(h.position, atan2(dir.x, dir.y), reach, h.accent)
	h.face(dir)
	h.lunge(1.0)
	if n > 0:
		stacks = mini(MAX_STACKS, stacks + 1)
		_since_hit = 0.0
	else:
		stacks = 0


func tick(delta: float) -> void:
	_since_hit += delta
	if _since_hit > FORGET:
		stacks = 0
	h.buff_rate = STACK * stacks


func skill() -> bool:
	var r := SPIN_RADIUS * h.area()
	var dmg := h.skill_power(0.8)
	for i in Game.enemies.query(me(), r):
		var rel: Vector2 = Game.enemies.pos[i] - me()
		var d := rel.length()
		var dir := rel / d if d > 0.05 else Vector2.UP
		# A knock that carries them out to the edge of the spin.
		Game.enemies.damage(i, dmg, dir, (r - d) * 7.0)
	Game.fx.slash(h.position, h.facing, r, PI, h.accent)
	Game.fx.slash(h.position, h.facing + PI, r, PI, h.accent)
	Game.fx.ring(h.position, r, h.accent, 0.3)
	h.twist(1.5)
	shake(0.25)
	return true


func skill_worth() -> bool:
	return Game.enemies.query(me(), 2.5).size() >= 4 or h.hp < h.max_hp * 0.4 and Game.enemies.query(me(), 3.0).size() >= 2


func ult() -> bool:
	if furthest_in(leash_center(), Game.party.LEASH, me()) < 0:
		return false
	_line_left = 5 if h.has_mod("rhi_u_five") else 3
	h.untargetable = true
	Game.fx.ring(h.position, 2.0, GOLD_RED, 0.4)
	h.hold_still(0.5, _next_strike)
	return true


func _next_strike() -> void:
	if _line_left <= 0:
		_finish()
		return
	var from := me()
	var t := furthest_in(from, Game.party.LEASH, from)
	if t < 0:
		_finish()
		return
	_line_left -= 1
	var to: Vector2 = Game.enemies.pos[t]
	var dir := (to - from).normalized()
	var end := to + dir * 1.0
	var hit := {}
	var width := 1.6 if h.has_mod("rhi_u_cleave") else 0.8
	var shaken := h.has_mod("rhi_u_shake")
	h.start_motion(at3(end), STRIKE_TIME, 0.0, func() -> void:
		hit_line(from, me(), width, h.ult_power(LINE_MULT), 9.0, hit, func(i: int) -> void:
			if shaken:
				Game.enemies.stun(i, 1.0)), func() -> void:
		Game.fx.thrust(at3(from), atan2(dir.x, dir.y), from.distance_to(end), GOLD_RED)
		shake(0.25, 0.04)
		after(0.08, _next_strike))


func _finish() -> void:
	h.untargetable = false
	if h.has_mod("rhi_u_fury"):
		stacks = MAX_STACKS
		_since_hit = 0.0


func on_downed() -> void:
	super.on_downed()
	stacks = 0
	_line_left = 0
