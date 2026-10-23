extends RefCounted
## The level-up cards, built for whichever three heroes are in the party.
##
## Every card shows real numbers, before → after, and its level ("Lv 2/5").
##   Common     small steps that stack: damage, attack speed, health
##   Rare       bigger steps: skill and ultimate cooldowns, area, skill damage
##   Epic       one more swipe / axe / bolt per attack (stacks a few times)
##   Legendary  ultimate upgrades that change how it works (every 5th level)
##   Bond       duo cards for two heroes in the party (also every 5th level)
## Party cards (grey) help everyone and stack up to 5 times. Echo is a rare
## find: +1 to every hero's basic attack.
##
## Every 5th level draws from the ultimate upgrades and unlocked bonds. A
## bond unlocks once both its heroes have at least one ultimate card.
## Each night has 3 rerolls and 3 banishes; a banished card never returns.

const HeroData := preload("res://scripts/hero_data.gd")
const RARITY_WEIGHT := {"common": 60.0, "rare": 30.0, "epic": 10.0}

var rerolls_left := 3
var banishes_left := 3
var taken := {}
var banished := {}
var pool: Array = []

const BONDS := [
	["bond_back", "solenne", "cenhelm", "Back to Back", "When the Horn sounds, everything in range turns on Solenne, and her counter chance doubles (30% → 60%) for 6 s."],
	["bond_penance", "solenne", "kheiron", "Penance", "Each of Solenne's counters heals the most hurt ally for 1% of their max health."],
	["bond_together", "cenhelm", "kheiron", "Walk Out Together", "Where Cenhelm lands from Walk Out, a small grove grows for 3 s."],
]


func _init() -> void:
	_build_pool()


func _build_pool() -> void:
	pool.clear()
	for kind in Game.party_kinds():
		var d: Dictionary = HeroData.get_hero(kind)
		var n: String = d["name"]
		var skill: String = d["skill"]["name"]
		var ult: String = d["ult"]["name"]
		var basic: String = d["basic"]
		var skip: Array = d.get("skip_cards", [])
		pool.append(_card(kind + "_dmg", n, kind, "common", "Harder Hits", "dmg", 5))
		pool.append(_card(kind + "_spd", n, kind, "common", "Faster Attacks", "spd", 5))
		pool.append(_card(kind + "_hp", n, kind, "common", "Tougher", "hp", 5))
		pool.append(_card(kind + "_skill_cd", n, kind, "rare", "%s, Sooner" % skill, "skill_cd", 3))
		pool.append(_card(kind + "_ult_cd", n, kind, "rare", "%s, Sooner" % ult, "ult_cd", 3))
		if not skip.has("skill_dmg"):
			pool.append(_card(kind + "_skill_dmg", n, kind, "rare", "%s, Stronger" % skill, "skill_dmg", 3))
		if not skip.has("area"):
			pool.append(_card(kind + "_area", n, kind, "rare", "Wider %s" % basic, "area", 3))
		pool.append(_card(kind + "_more", n, kind, "epic", "One More", "more", 3))
		if d.get("healer", false):
			pool.append(_card(kind + "_heal", n, kind, "rare", "Deeper Lessons", "heal", 3))
		if d.get("ranged", false):
			pool.append(_card(kind + "_pierce", n, kind, "rare", "Through and Through", "pierce", 2))
		for u in d["ult_cards"]:
			var c := _card(u[0], n, kind, "legendary", u[1], "mod", 1)
			c["text"] = u[2]
			pool.append(c)
	pool.append(_card("party_might", "Party", "", "common", "Might", "might", 5))
	pool.append(_card("party_haste", "Party", "", "common", "Haste", "haste", 5))
	pool.append(_card("party_vigour", "Party", "", "common", "Vigour", "vigour", 5))
	pool.append(_card("party_swift", "Party", "", "common", "Swiftness", "swift", 5))
	pool.append(_card("party_magnet", "Party", "", "common", "Keen Eyes", "magnet", 3))
	pool.append(_card("party_reach", "Party", "", "rare", "Reach", "reach", 5))
	pool.append(_card("party_focus", "Party", "", "rare", "Focus", "focus", 5))
	var echo := _card("party_echo", "Party", "", "epic", "Echo", "echo", 1)
	echo["weight"] = 3.0
	pool.append(echo)
	var kinds: Array = Game.party_kinds()
	for b in BONDS:
		if kinds.has(b[1]) and kinds.has(b[2]):
			pool.append({"id": b[0], "hero": "%s + %s" % [HeroData.HEROES[b[1]]["name"], HeroData.HEROES[b[2]]["name"]],
				"heroes": [HeroData.HEROES[b[1]]["name"], HeroData.HEROES[b[2]]["name"]], "kinds": [b[1], b[2]],
				"rarity": "bond", "title": b[3], "text": b[4], "stat": "bond", "max": 1})


static func _card(id: String, hero: String, kind: String, rarity: String, title: String, stat: String, max_times: int) -> Dictionary:
	return {"id": id, "hero": hero, "kind": kind, "rarity": rarity, "title": title, "stat": stat, "max": max_times}


func times_taken(id: String) -> int:
	return int(taken.get(id, 0))


func is_ult_level(level: int) -> bool:
	return level % 5 == 0


## Draws `n` cards for the given level, leaving out `exclude` ids. Each card
## comes back with its description and level filled in.
func roll(n: int, level: int, exclude: Array = []) -> Array:
	var out: Array
	if is_ult_level(level):
		var ult := _ult_pool(exclude)
		ult.shuffle()
		out = ult.slice(0, n)
		if out.size() < n:
			out.append_array(_weighted(_normal_pool(exclude + _ids(out)), n - out.size()))
	else:
		out = _weighted(_normal_pool(exclude), n)
	var shown: Array = []
	for c in out:
		var copy: Dictionary = c.duplicate()
		copy["desc"] = describe(c)
		copy["level"] = times_taken(c["id"]) + 1
		shown.append(copy)
	return shown


func _hero_of(card: Dictionary):
	var kind: String = card.get("kind", "")
	if kind == "":
		return null
	for h in Game.party.heroes:
		if h.kind == kind:
			return h
	return null


func _available(card: Dictionary, exclude: Array) -> bool:
	var id: String = card["id"]
	if banished.has(id) or exclude.has(id):
		return false
	if times_taken(id) >= int(card["max"]):
		return false
	if card["rarity"] != "bond" and card.get("kind", "") != "" and _hero_of(card) == null:
		return false
	return true


func _normal_pool(exclude: Array) -> Array:
	var out: Array = []
	for card in pool:
		if card["rarity"] in ["common", "rare", "epic"] and _available(card, exclude):
			out.append(card)
	return out


func _ult_pool(exclude: Array) -> Array:
	var out: Array = []
	for card in pool:
		if not _available(card, exclude):
			continue
		if card["rarity"] == "legendary":
			out.append(card)
		elif card["rarity"] == "bond":
			var ok := true
			for k in card["kinds"]:
				var h = null
				for x in Game.party.heroes:
					if x.kind == k:
						h = x
				ok = ok and h != null and h.ult_cards >= 1
			if ok:
				out.append(card)
	return out


func _weighted(cards: Array, n: int) -> Array:
	var bag := cards.duplicate()
	var out: Array = []
	while out.size() < n and not bag.is_empty():
		var total := 0.0
		for c in bag:
			total += _weight(c)
		var r := randf() * total
		for i in bag.size():
			r -= _weight(bag[i])
			if r <= 0.0:
				out.append(bag[i])
				bag.remove_at(i)
				break
	return out


func _weight(c: Dictionary) -> float:
	return float(c.get("weight", RARITY_WEIGHT.get(c["rarity"], 10.0)))


static func _ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c["id"])
	return out


func banish(card: Dictionary) -> void:
	banished[card["id"]] = true
	banishes_left -= 1


# --- Numbers on the card ---------------------------------------------------------

const STEP := {
	"dmg": 0.15, "spd": 0.10, "hp": 0.12, "skill_cd": 0.85, "ult_cd": 0.85, "skill_dmg": 0.25,
	"area": 0.20, "heal": 0.30, "might": 0.10, "haste": 0.08, "vigour": 0.10, "swift": 0.08,
	"magnet": 1.4, "reach": 0.10, "focus": 0.92,
}


static func _x(v: float) -> String:
	return "×%.2f" % v


## What the card does, in numbers: before → after.
func describe(card: Dictionary) -> String:
	var stat: String = card["stat"]
	var h = _hero_of(card)
	var P = Game.party
	match stat:
		"dmg":
			return "Damage: %s → %s" % [_x(h.damage_mult), _x(h.damage_mult + STEP["dmg"])]
		"spd":
			return "Attack speed: %s → %s" % [_x(h.rate_mult), _x(h.rate_mult + STEP["spd"])]
		"hp":
			return "Max health: %d → %d" % [int(h.max_hp), int(h.max_hp * (1.0 + STEP["hp"]))]
		"skill_cd":
			return "%s cooldown: %.1f s → %.1f s" % [h.skill_name("q"), h.skill_cooldown("q"), h.skill_cooldown("q") * STEP["skill_cd"]]
		"ult_cd":
			return "%s cooldown: %.0f s → %.0f s" % [h.skill_name("e"), h.skill_cooldown("e"), h.skill_cooldown("e") * STEP["ult_cd"]]
		"skill_dmg":
			return "%s damage: %s → %s" % [h.skill_name("q"), _x(h.skill_mult), _x(h.skill_mult + STEP["skill_dmg"])]
		"area":
			return "%s area: %s → %s" % [h.data["basic"], _x(h.area_mult), _x(h.area_mult + STEP["area"])]
		"more":
			var n: int = h.instances()
			return "%s: %d → %d %s" % [h.data["basic"], n, n + 1, h.data["instance_word"]]
		"heal":
			return "Healing: %s → %s" % [_x(h.heal_mult), _x(h.heal_mult + STEP["heal"])]
		"pierce":
			return "%s pierce: %d → %d enemies" % [h.data["basic"], h.pierce_bonus + _base_pierce(h), h.pierce_bonus + _base_pierce(h) + 1]
		"might":
			return "Everyone's damage: %s → %s" % [_x(P.might), _x(P.might + STEP["might"])]
		"haste":
			return "Everyone's attack speed: %s → %s" % [_x(P.haste), _x(P.haste + STEP["haste"])]
		"vigour":
			return "Everyone's max health: +10%, and heals 25%"
		"swift":
			return "Party speed: %s → %s" % [_x(P.speed_mult), _x(P.speed_mult + STEP["swift"])]
		"magnet":
			return "Pickup range: %.1f m → %.1f m" % [Game.xp.magnet, Game.xp.magnet * STEP["magnet"]]
		"reach":
			return "Everyone's area: %s → %s" % [_x(P.reach), _x(P.reach + STEP["reach"])]
		"focus":
			return "Everyone's cooldowns: %s → %s" % [_x(P.focus), _x(P.focus * STEP["focus"])]
		"echo":
			return "Every hero's basic attack: +1 (one more swipe, axe, bolt...)"
		_:
			return card.get("text", "")


static func _base_pierce(h) -> int:
	match h.kind:
		"bram", "levana":
			return 2
	return 0


# --- Applying a card -----------------------------------------------------------

func apply(card: Dictionary) -> void:
	var id: String = card["id"]
	taken[id] = times_taken(id) + 1
	var P = Game.party
	var h = _hero_of(card)
	match card["stat"]:
		"dmg":
			h.damage_mult += STEP["dmg"]
		"spd":
			h.rate_mult += STEP["spd"]
		"hp":
			_grow_hp(h, STEP["hp"])
		"skill_cd":
			h.cd_mult["q"] *= STEP["skill_cd"]
		"ult_cd":
			h.cd_mult["e"] *= STEP["ult_cd"]
		"skill_dmg":
			h.skill_mult += STEP["skill_dmg"]
		"area":
			h.area_mult += STEP["area"]
		"more":
			h.extra_instances += 1
		"heal":
			h.heal_mult += STEP["heal"]
		"pierce":
			h.pierce_bonus += 1
		"mod":
			h.mods[id] = true
			h.ult_cards += 1
		"bond":
			P.bonds[id] = true
		"might":
			P.might += STEP["might"]
		"haste":
			P.haste += STEP["haste"]
		"vigour":
			for x in P.heroes:
				_grow_hp(x, STEP["vigour"])
				x.heal(x.max_hp * 0.25)
		"swift":
			P.speed_mult += STEP["swift"]
		"magnet":
			Game.xp.magnet *= STEP["magnet"]
		"reach":
			P.reach += STEP["reach"]
		"focus":
			P.focus *= STEP["focus"]
		"echo":
			P.echo += 1


static func _grow_hp(h, frac: float) -> void:
	var gain: float = h.max_hp * frac
	h.max_hp += gain
	h.hp = minf(h.max_hp, h.hp + gain)
