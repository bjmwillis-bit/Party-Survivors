extends RefCounted
## The base for every hero's kit: their basic attack, skill (Q) and ultimate
## (E). Each hero has a kit script in this folder that fills these in. The
## hero (hero.gd) handles everything shared: moving, health, the look, cards.
##
## Kits read the card stats from the hero:
##   h.power(mult)       basic-attack damage (cards, leader bonus, buffs)
##   h.skill_power(mult) skill damage; h.ult_power(mult) ultimate damage
##   h.area()            area multiplier; h.instances() how many swipes/axes...
##   h.has_mod(id)       an ultimate upgrade card is in play

const HeroScript := preload("res://scripts/hero.gd")

var h: HeroScript # the hero this kit belongs to
var _timers: Array = [] # [seconds left, Callable]


func setup(hero: HeroScript) -> void:
	h = hero


# --- What each kit fills in ----------------------------------------------------

## The basic attack. Return true if it fired (the attack timer restarts).
func attack() -> bool:
	return false


## Q. Return true if it went off.
func skill() -> bool:
	return false


## E (leader only). Return true if it went off.
func ult() -> bool:
	return false


## Followers cast their skill the moment this is true.
func skill_worth() -> bool:
	return Game.enemies.nearest(me(), 6.0) >= 0


## Every frame while the hero is up (after timers have run).
func tick(_delta: float) -> void:
	pass


## True while the kit is mid-move or channelling: no basic attacks.
func busy() -> bool:
	return false


## An enemy's blow landed (after damage). For counters and the like.
func on_struck(_attacker: int) -> void:
	pass


## The hero went down: stop anything in progress.
func on_downed() -> void:
	_timers.clear()


## Pressing E again while the ultimate is running (Cael lands early).
func ult_pressed_again() -> bool:
	return false


# --- Timing --------------------------------------------------------------------

## Runs `fn` after `seconds` (cancelled if the hero goes down).
func after(seconds: float, fn: Callable) -> void:
	_timers.append([seconds, fn])


func run_timers(delta: float) -> void:
	var i := 0
	while i < _timers.size():
		_timers[i][0] -= delta
		if _timers[i][0] <= 0.0:
			var fn: Callable = _timers[i][1]
			_timers.remove_at(i)
			if not h.downed:
				fn.call()
			continue
		i += 1


# --- Helpers -------------------------------------------------------------------

func me() -> Vector2:
	return Vector2(h.position.x, h.position.z)


func at3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


## Which way to strike: where the leader aims, else the nearest enemy within
## `reach` (followers). ZERO if there's nothing to hit.
func aim(reach: float) -> Vector2:
	if h.is_leader and h.aim_dir != Vector2.ZERO:
		return h.aim_dir
	if not h.is_leader and h.ai_aim != Vector2.ZERO:
		return h.ai_aim
	var t: int = Game.enemies.nearest(me(), reach)
	if t < 0:
		return Vector2.ZERO
	var d: Vector2 = Game.enemies.pos[t] - me()
	return d.normalized() if d.length() > 0.01 else Vector2(sin(h.facing), cos(h.facing))


## The leader swings at the cursor only if something is there to hit.
func leader_has_target(dir: Vector2, reach: float, half: float) -> bool:
	return enemy_in_arc(me(), dir, reach, half)


func enemy_in_arc(from: Vector2, dir: Vector2, reach: float, half: float) -> bool:
	for i in Game.enemies.query(from, reach):
		var rel: Vector2 = Game.enemies.pos[i] - from
		if rel.length() < 0.001 or absf(dir.angle_to(rel)) <= half:
			return true
	return false


## Damages everything in an arc. `inner` skips the near part (Cael's sweep).
## `rot` turns the arc's centre (Niten's off-centre swing). Returns hits.
func hit_arc(from: Vector2, dir: Vector2, reach: float, half: float, dmg: float, knock := 6.0, inner := 0.0, on_hit := Callable()) -> int:
	var n := 0
	for i in Game.enemies.query(from, reach):
		var rel: Vector2 = Game.enemies.pos[i] - from
		var d := rel.length()
		if d < inner:
			continue
		if d > 0.001 and absf(dir.angle_to(rel)) > half:
			continue
		Game.enemies.damage(i, dmg, rel.normalized() if d > 0.001 else dir, knock)
		if on_hit.is_valid():
			on_hit.call(i)
		n += 1
	return n


func hit_circle(at: Vector2, r: float, dmg: float, knock := 8.0, on_hit := Callable()) -> int:
	var n := 0
	for i in Game.enemies.query(at, r):
		var rel: Vector2 = Game.enemies.pos[i] - at
		Game.enemies.damage(i, dmg, rel.normalized() if rel.length() > 0.05 else Vector2.UP, knock)
		if on_hit.is_valid():
			on_hit.call(i)
		n += 1
	return n


## Everything within `width` of the line from a to b.
func hit_line(a: Vector2, b: Vector2, width: float, dmg: float, knock := 6.0, already := {}, on_hit := Callable()) -> int:
	var n := 0
	var mid := (a + b) * 0.5
	var reach := a.distance_to(b) * 0.5 + width
	var dir := (b - a).normalized()
	for i in Game.enemies.query(mid, reach):
		if already.has(i):
			continue
		var p: Vector2 = Game.enemies.pos[i]
		if seg_dist(p, a, b) <= width:
			already[i] = true
			Game.enemies.damage(i, dmg, dir, knock)
			if on_hit.is_valid():
				on_hit.call(i)
			n += 1
	return n


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Bleeding: `per_second` damage each second for `seconds`.
func bleed(i: int, per_second: float, seconds := 4.0) -> void:
	var E = Game.enemies
	if i < 0 or i >= E.count:
		return
	E.dot_t[i] = maxf(E.dot_t[i], seconds)
	E.dot_dmg[i] = maxf(E.dot_dmg[i], per_second)


## The enemy furthest from `from`, within `r` of `center`. -1 if none.
func furthest_in(center: Vector2, r: float, from: Vector2) -> int:
	var best := -1
	var best_d := -1.0
	for i in Game.enemies.query(center, r):
		var d: float = from.distance_squared_to(Game.enemies.pos[i])
		if d > best_d:
			best_d = d
			best = i
	return best


## The leash: centred on the leader.
func leash_center() -> Vector2:
	var l = Game.party.leader()
	return Vector2(l.position.x, l.position.z) if l != null else me()


func shake(amount: float, stop := 0.0) -> void:
	if h.is_leader:
		Game.add_shake(amount)
		if stop > 0.0:
			Game.hitstop(stop)


## A loose prop in the world (a thrown axe, a dagger on the ground). It lives
## under the effects node, so it's cleared with everything else each night.
func make_prop(model_path: String, scale := 1.0, fallback_color := Color.GRAY) -> Node3D:
	var n := Game.model("res://assets/kaykit/" + model_path)
	if n == null:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 0.5, 0.08)
		mi.mesh = box
		mi.material_override = Game.material(fallback_color)
		n = mi
	n.scale = Vector3.ONE * scale
	Game.fx.add_child(n)
	return n


## A soft-edged disc on the ground (clouds, markers). Returns [node, material].
func make_disc(radius: float, color: Color) -> Array:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.04
	cyl.radial_segments = 32
	mi.mesh = cyl
	var mat := Game.effect_material(color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Game.fx.add_child(mi)
	return [mi, mat]
