extends RefCounted
## The level-up card pool.
##
## Rarities: common, rare, epic (normal levels), legendary (ultimate upgrades,
## every 5th level) and bond (duo cards, also on every 5th level).
## - Normal levels draw 3 cards, weighted toward commons.
## - Every 5th level draws 3 from all heroes' untaken ultimate upgrades plus
##   any unlocked bonds. A bond unlocks once both of its heroes have at least
##   one ultimate card.
## - Each run has 3 rerolls and 3 banishes. A banished card never comes back
##   this run.
##
## Card effects mostly set entries in a hero's `mods` dictionary, which the
## hero's skills read. See hero.gd for what each mod does.

const RARITY_WEIGHT := {"common": 60.0, "rare": 30.0, "epic": 10.0}

var rerolls_left := 3
var banishes_left := 3
var taken := {}
var banished := {}

var pool := [
	# --- Solenne (red) ---
	_c("sol_dmg", "Solenne", "common", "Oathcut, Sharpened", "Solenne's slash deals 15% more damage.", 5),
	_c("sol_hp", "Solenne", "common", "White Steel", "Solenne gains 12% max health.", 5),
	_c("sol_spd", "Solenne", "common", "Quick Blade", "Solenne attacks 10% faster.", 5),
	_c("sol_arc", "Solenne", "rare", "Through", "Solenne's slash and counter reach 20% further.", 3),
	_c("sol_contempt", "Solenne", "rare", "Still Offended", "Solenne can hold 5 more Contempt.", 2),
	_c("sol_faceme_cd", "Solenne", "rare", "Never Turning", "Face Me's cooldown is 20% shorter.", 2),
	_c("sol_counter_twice", "Solenne", "epic", "Cut Through Twice", "Every counter strikes twice.", 1),
	_c("sol_counter_chance", "Solenne", "epic", "I'll Give You My Back", "Counter chance rises from 30% to 45%.", 1),
	_c("sol_pull", "Solenne", "epic", "Don't Make Me Look", "Face Me drags taunted enemies toward her.", 1),
	_c("sol_third", "Solenne", "epic", "Wasn't Looking", "Every third slash also cuts the arc behind her.", 1),
	# --- Solenne ultimate (Ultrix) ---
	_c("sol_u_flames", "Solenne", "legendary", "Even Blind", "Ultrix: the backstep slash fires 3 flame waves.", 1),
	_c("sol_u_scorch", "Solenne", "legendary", "Scorched Path", "Ultrix: the lunge leaves burning ground for 4 s.", 1),
	_c("sol_u_twice", "Solenne", "legendary", "Twice Blind", "Ultrix: after the lunge, she lunges back.", 1),
	_c("sol_u_contempt", "Solenne", "legendary", "Contempt Unbound", "Ultrix spends all Contempt: +10% lunge damage per stack.", 1),

	# --- Cenhelm (orange) ---
	_c("cen_dmg", "Cenhelm", "common", "Heavier Hands", "Cenhelm's punches deal 15% more damage.", 5),
	_c("cen_hp", "Cenhelm", "common", "Broad Back", "Cenhelm gains 15% max health (his punches scale with it).", 5),
	_c("cen_spd", "Cenhelm", "common", "Quick Fists", "Cenhelm punches 10% faster.", 5),
	_c("cen_splash", "Cenhelm", "rare", "Heavier Gate", "Cenhelm's punch and slam splash 20% wider.", 3),
	_c("cen_cover", "Cenhelm", "rare", "For His People", "Cenhelm takes 10% more of the hits aimed at his allies.", 2),
	_c("cen_walk_cd", "Cenhelm", "rare", "Always Walking Out", "Walk Out's cooldown is 20% shorter.", 2),
	_c("cen_gate_stun", "Cenhelm", "epic", "Set Your Feet", "The Gate also stuns for 1 s.", 1),
	_c("cen_walk_taunt", "Cenhelm", "epic", "Face The Fist", "Walk Out taunts enemies around where he lands.", 1),
	_c("cen_uppercut", "Cenhelm", "epic", "First Blow", "Every 4th punch is an uppercut: double damage, bigger splash.", 1),
	_c("cen_gate_cdr", "Cenhelm", "epic", "The War", "Each punch takes 1.5 s off The Gate instead of 1 s.", 1),
	# --- Cenhelm ultimate (The Horn) ---
	_c("cen_u_heal", "Cenhelm", "legendary", "The Warhorn", "The Horn heals every ally 15% of their max health.", 1),
	_c("cen_u_stun", "Cenhelm", "legendary", "Last Man", "The Horn stuns everything for 1.5 s before the slow.", 1),
	_c("cen_u_long", "Cenhelm", "legendary", "Long Note", "The Horn's slow lasts 10 s and slows by 65%.", 1),
	_c("cen_u_freca", "Cenhelm", "legendary", "Freca", "After the Horn, his next 10 punches hit twice as hard.", 1),

	# --- Kheiron (green) ---
	_c("khe_dmg", "Kheiron", "common", "Sharper Bolts", "Kheiron's bolts deal 15% more damage.", 5),
	_c("khe_hp", "Kheiron", "common", "Old Bark", "Kheiron gains 12% max health.", 5),
	_c("khe_spd", "Kheiron", "common", "Quick Hands", "Kheiron fires 10% faster.", 5),
	_c("khe_bolts", "Kheiron", "rare", "Taking Disciples", "Kheiron fires one more bolt.", 3),
	_c("khe_heal", "Kheiron", "rare", "Atonement", "Kheiron's heals are 30% stronger.", 3),
	_c("khe_grove_time", "Kheiron", "rare", "Deep Grove", "The Grove lasts 1 s longer.", 2),
	_c("khe_pierce", "Kheiron", "epic", "Staff and Hand", "Kheiron's bolts pierce 2 enemies.", 1),
	_c("khe_lesson_two", "Kheiron", "epic", "Two Students", "Lesson heals the two lowest-health allies.", 1),
	_c("khe_grove_slow", "Kheiron", "epic", "Roots", "Enemies in a grove are slowed by 30%.", 1),
	_c("khe_volley", "Kheiron", "epic", "The Wound", "Lesson also fires a volley at the enemy nearest the healed ally.", 1),
	# --- Kheiron ultimate (Give the Sky) ---
	_c("khe_u_open", "Kheiron", "legendary", "Open Sky", "Give the Sky also resets allies' Q and E.", 1),
	_c("khe_u_light", "Kheiron", "legendary", "Light Burden", "Give the Sky costs 10% health instead of 20%.", 1),
	_c("khe_u_grove", "Kheiron", "legendary", "Sky Grove", "Give the Sky grows a grove under every ally.", 1),
	_c("khe_u_shared", "Kheiron", "legendary", "Shared Sky", "Give the Sky grants allies +20% damage for 8 s.", 1),

	# --- Party (neutral) ---
	_c("party_speed", "Party", "common", "Lighter Step", "The party moves 8% faster.", 4),
	_c("party_haste", "Party", "rare", "Quicker Hands", "Everyone attacks 10% faster.", 4),
	_c("party_hp", "Party", "common", "Hardened", "Everyone gains 10% max health and heals 25%.", 4),
	_c("magnet", "Party", "common", "Keen Eyes", "Pick up XP from 40% further away.", 3),

	# --- Bonds (duo cards) ---
	_bond("bond_back", "Solenne", "Cenhelm", "Back to Back", "When the Horn sounds, everything in range is taunted to Solenne, and her counter chance doubles for 6 s."),
	_bond("bond_penance", "Solenne", "Kheiron", "Penance", "Each of Solenne's counters heals the lowest-health ally for 1% of their max health."),
	_bond("bond_together", "Cenhelm", "Kheiron", "Walk Out Together", "Where Cenhelm lands, a small grove grows for 3 s."),
]


static func _c(id: String, hero: String, rarity: String, title: String, desc: String, max_times: int) -> Dictionary:
	return {"id": id, "hero": hero, "rarity": rarity, "title": title, "desc": desc, "max": max_times}


static func _bond(id: String, a: String, b: String, title: String, desc: String) -> Dictionary:
	return {"id": id, "hero": "%s + %s" % [a, b], "heroes": [a, b], "rarity": "bond", "title": title, "desc": desc, "max": 1}


func times_taken(id: String) -> int:
	return int(taken.get(id, 0))


func is_ult_level(level: int) -> bool:
	return level % 5 == 0


## Draws `n` cards for the given level, leaving out `exclude` ids.
func roll(n: int, level: int, exclude: Array = []) -> Array:
	if is_ult_level(level):
		var ult := _ult_pool(exclude)
		ult.shuffle()
		var out: Array = ult.slice(0, n)
		if out.size() < n:
			out.append_array(_weighted(_normal_pool(exclude + _ids(out)), n - out.size()))
		return out
	return _weighted(_normal_pool(exclude), n)


func _available(card: Dictionary, exclude: Array) -> bool:
	var id: String = card["id"]
	if banished.has(id) or exclude.has(id):
		return false
	if times_taken(id) >= int(card["max"]):
		return false
	if card["hero"] != "Party" and card["rarity"] != "bond":
		var h = Game.party.hero(card["hero"])
		if h == null:
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
			var a = Game.party.hero(card["heroes"][0])
			var b = Game.party.hero(card["heroes"][1])
			if a != null and b != null and a.ult_cards >= 1 and b.ult_cards >= 1:
				out.append(card)
	return out


func _weighted(cards: Array, n: int) -> Array:
	var bag := cards.duplicate()
	var out: Array = []
	while out.size() < n and not bag.is_empty():
		var total := 0.0
		for c in bag:
			total += RARITY_WEIGHT.get(c["rarity"], 10.0)
		var r := randf() * total
		for i in bag.size():
			r -= RARITY_WEIGHT.get(bag[i]["rarity"], 10.0)
			if r <= 0.0:
				out.append(bag[i])
				bag.remove_at(i)
				break
	return out


static func _ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c["id"])
	return out


func banish(card: Dictionary) -> void:
	banished[card["id"]] = true
	banishes_left -= 1


# --- Applying a card -----------------------------------------------------------

func apply(card: Dictionary) -> void:
	var id: String = card["id"]
	taken[id] = times_taken(id) + 1
	var party = Game.party
	var sol = party.hero("Solenne")
	var cen = party.hero("Cenhelm")
	var khe = party.hero("Kheiron")
	if card["rarity"] == "legendary":
		party.hero(card["hero"]).ult_cards += 1
	match id:
		"sol_dmg":
			sol.damage_mult += 0.15
		"sol_hp":
			_grow_hp(sol, 0.12)
		"sol_spd":
			sol.rate_mult += 0.10
		"sol_arc":
			sol.area_mult += 0.2
		"sol_contempt":
			sol.contempt_cap += 5
		"sol_faceme_cd":
			sol.cd_mult["e"] *= 0.8
		"cen_dmg":
			cen.damage_mult += 0.15
		"cen_hp":
			_grow_hp(cen, 0.15)
		"cen_spd":
			cen.rate_mult += 0.10
		"cen_splash":
			cen.area_mult += 0.2
		"cen_cover":
			cen.intercept_share += 0.1
		"cen_walk_cd":
			cen.cd_mult["e"] *= 0.8
		"khe_dmg":
			khe.damage_mult += 0.15
		"khe_hp":
			_grow_hp(khe, 0.12)
		"khe_spd":
			khe.rate_mult += 0.10
		"khe_bolts":
			khe.extra_bolts += 1
		"khe_heal":
			khe.heal_mult += 0.3
		"khe_grove_time":
			khe.mods["grove_time"] = float(khe.mods.get("grove_time", 0.0)) + 1.0
		"party_speed":
			party.speed_mult += 0.08
		"party_haste":
			party.haste += 0.10
		"party_hp":
			for h in party.heroes:
				_grow_hp(h, 0.10)
				h.heal(h.max_hp * 0.25)
		"magnet":
			Game.xp.magnet *= 1.4
		_:
			# Epics, ultimate upgrades and bonds switch on a named effect.
			var h = party.hero(card["hero"])
			if card["rarity"] == "bond":
				party.bonds[id] = true
			elif h != null:
				h.mods[id] = true


static func _grow_hp(h, frac: float) -> void:
	var gain: float = h.max_hp * frac
	h.max_hp += gain
	h.heal(gain)
