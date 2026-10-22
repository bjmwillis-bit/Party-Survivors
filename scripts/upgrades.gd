extends RefCounted
## The level-up card pool for the prototype. Each card can be taken up to
## "max" times. Names nod to the Heroes Final kits. In later milestones these
## become skill ranks, and the talent A/B forks move to the pre-run loadout.

var pool := [
	{"id": "sol_dmg", "hero": "Solenne", "title": "Oathcut, Sharpened", "desc": "Solenne's cut deals 30% more damage.", "max": 5},
	{"id": "sol_arc", "hero": "Solenne", "title": "Through", "desc": "Solenne's cut reaches 20% further.", "max": 3},
	{"id": "sol_contempt", "hero": "Solenne", "title": "Still Offended", "desc": "Solenne can hold 5 more Contempt.", "max": 2},
	{"id": "cen_gate", "hero": "Cenhelm", "title": "Heavier Gate", "desc": "Cenhelm's slam is 20% wider and 15% stronger.", "max": 4},
	{"id": "cen_hp", "hero": "Cenhelm", "title": "Found Standing", "desc": "Cenhelm gains 40 max HP (and his slam hits harder).", "max": 4},
	{"id": "cen_cover", "hero": "Cenhelm", "title": "Walk Out", "desc": "Cenhelm takes 10% more of the hits aimed at his allies.", "max": 2},
	{"id": "khe_bolts", "hero": "Kheiron", "title": "Taking Disciples", "desc": "Kheiron fires one more bolt.", "max": 4},
	{"id": "khe_heal", "hero": "Kheiron", "title": "Lesson", "desc": "Kheiron's heals are 50% stronger.", "max": 3},
	{"id": "party_speed", "hero": "Party", "title": "Lighter Step", "desc": "The party moves 8% faster.", "max": 4},
	{"id": "party_haste", "hero": "Party", "title": "Quicker Hands", "desc": "Everyone attacks 12% faster.", "max": 5},
	{"id": "party_hp", "hero": "Party", "title": "Hardened", "desc": "Everyone gains 15% max HP and heals 25%. (Kheiron is Incurable.)", "max": 4},
	{"id": "magnet", "hero": "Party", "title": "Keen Eyes", "desc": "Pick up XP from 40% further away.", "max": 3},
]

var taken := {}


func roll(n: int) -> Array:
	var open: Array = []
	for card in pool:
		if int(taken.get(card["id"], 0)) < int(card["max"]):
			open.append(card)
	open.shuffle()
	return open.slice(0, n)


func times_taken(id: String) -> int:
	return int(taken.get(id, 0))


func apply(card: Dictionary) -> void:
	var id: String = card["id"]
	taken[id] = times_taken(id) + 1
	var party = Game.party
	match id:
		"sol_dmg":
			party.hero("Solenne").damage_mult += 0.3
		"sol_arc":
			party.hero("Solenne").area_mult += 0.2
		"sol_contempt":
			party.hero("Solenne").contempt_cap += 5
		"cen_gate":
			var c = party.hero("Cenhelm")
			c.area_mult += 0.2
			c.damage_mult += 0.15
		"cen_hp":
			var c = party.hero("Cenhelm")
			c.max_hp += 40.0
			c.heal(40.0)
		"cen_cover":
			party.hero("Cenhelm").intercept_share += 0.1
		"khe_bolts":
			party.hero("Kheiron").extra_bolts += 1
		"khe_heal":
			party.hero("Kheiron").heal_mult += 0.5
		"party_speed":
			party.speed_mult += 0.08
		"party_haste":
			party.haste += 0.12
		"party_hp":
			for h in party.heroes:
				h.max_hp *= 1.15
				h.heal(h.max_hp * 0.25)
		"magnet":
			Game.xp.magnet *= 1.4
