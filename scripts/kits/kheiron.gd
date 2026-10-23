extends "res://scripts/kits/kit.gd"
## Kheiron. Basic: bolts from range.
## Lesson (automatic): every 2 s heals the lowest-health ally (never himself)
##   for 5% of their max health.
## Q The Grove: a leash-sized grove for 4 s; allies inside heal 1.5% a second.
## E Give the Sky: pays 20% of his health to reset the other heroes' ultimates.

const LESSON_EVERY := 2.0
const LESSON_HEAL := 0.05
const GROVE_TIME := 4.0
const GROVE_HEAL := 0.015
const SKY_COST := 0.2

var _lesson_t := LESSON_EVERY


func attack() -> bool:
	var target: int = Game.enemies.nearest(me(), h.shot_range())
	if target < 0:
		return false
	var to: Vector2 = (Game.enemies.pos[target] - me()).normalized()
	if h.is_leader and h.aim_dir != Vector2.ZERO:
		to = h.aim_dir # leading: fire where the player aims
	var count: int = h.instances()
	for b in count:
		var spread := (b - (count - 1) * 0.5) * 0.18
		Game.fx.bolt(h.position + Vector3(0.0, 1.0, 0.0), to.rotated(spread), h.power(), h.pierce_bonus, h.accent)
	h.face(to, 0.12)
	h.lunge(0.4)
	return true


func tick(delta: float) -> void:
	_lesson_t -= delta
	if _lesson_t <= 0.0:
		_lesson_t = LESSON_EVERY
		_lesson()


## Heals the most hurt ally (by health percentage), never himself.
func _lesson() -> void:
	var best = null
	var best_frac := 1.0
	for a in Game.party.heroes:
		if a == h or a.downed:
			continue
		var frac: float = a.hp / a.max_hp
		if frac < best_frac:
			best_frac = frac
			best = a
	if best == null:
		return
	best.heal(best.max_hp * LESSON_HEAL * h.heal_mult)
	Game.fx.ring(best.position, 1.2, h.accent, 0.35)


func skill() -> bool:
	Game.party.place_grove(h.position, Game.party.LEASH, GROVE_TIME, GROVE_HEAL * h.heal_mult)
	return true


func skill_worth() -> bool:
	return Game.party.lowest_health_ally(null, 0.7) != null


func ult() -> bool:
	var cost := 0.1 if h.has_mod("khe_u_light") else SKY_COST
	h.hp = maxf(1.0, h.hp - h.max_hp * cost)
	h.flash(0.12)
	for a in Game.party.heroes:
		if a == h:
			continue
		a.cooldown["e"] = 0.0
		if h.has_mod("khe_u_open"):
			a.cooldown["q"] = 0.0
		if a.downed:
			continue
		Game.fx.ring(a.position, 1.4, h.accent, 0.4)
		if h.has_mod("khe_u_grove"):
			Game.party.place_grove(a.position, 4.0, GROVE_TIME, GROVE_HEAL * h.heal_mult)
		if h.has_mod("khe_u_shared"):
			a.damage_buff_t = 8.0
	Game.fx.ring(h.position, 2.5, h.accent, 0.45)
	shake(0.2)
	return true
