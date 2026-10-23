extends Node
## Spoken lines (barks) during a run, shown as captions until the voices
## are recorded.
##
## All the words live in LINES below, so the story side can edit them
## without touching any logic. Each list is a set of variants: one is picked
## at random, so repeats across runs don't grate.

const LINES := {
	# The leader walks into the runestones. Once per run per hero.
	"trapped": {
		"solenne": ["We're trapped.", "There's no way out."],
		"cenhelm": ["We're trapped.", "There's no way out."],
		"kheiron": ["We're trapped.", "There's no way out."],
	},
	# The Beast falls: one of the others says this, then Solenne answers.
	"rest": {
		"cenhelm": ["Finally, some rest."],
		"kheiron": ["Finally, some rest."],
	},
	"rest_reply": {
		"solenne": ["...for now."],
	},
	# Boss teases: a line unique to that boss, once per fight.
	"beast_tease": {
		"beast": ["The Heart is MINE!"],
	},
}

const SPEAKERS := {
	"beast": {"name": "The Beast", "color": Color(1.0, 0.2, 0.12)},
}

## How close to the stones (metres) counts as walking into them.
const EDGE_ZONE := 1.2

var _trapped_said := {} # hero kind -> true, once a hero has said it this run


func _process(_delta: float) -> void:
	if Game.main.is_night():
		_check_trapped()


## The leader pushes against the runestones: "We're trapped."
func _check_trapped() -> void:
	var l = Game.party.leader() if Game.party != null else null
	if l == null or not l.moving or _trapped_said.has(l.kind):
		return
	var p := Vector2(l.position.x, l.position.z)
	if p.length() < Game.ARENA_RADIUS - EDGE_ZONE:
		return
	# Only when walking outwards, not just running along the edge.
	if Vector2(l.move_dir.x, l.move_dir.z).dot(p.normalized()) < 0.5:
		return
	_trapped_said[l.kind] = true
	say(l, "trapped")


## A hero says a random line from a set. Returns false if they have none.
func say(hero, key: String) -> bool:
	var lines: Array = LINES.get(key, {}).get(hero.kind, [])
	if lines.is_empty():
		return false
	Game.hud.caption(hero.hero_name, lines.pick_random(), hero.accent)
	return true


## A non-hero speaker, such as a boss.
func say_as(speaker: String, key: String) -> void:
	var lines: Array = LINES.get(key, {}).get(speaker, [])
	if lines.is_empty():
		return
	var s: Dictionary = SPEAKERS.get(speaker, {"name": speaker.capitalize(), "color": Color.WHITE})
	Game.hud.caption(s["name"], lines.pick_random(), s["color"], 3.0)


## The Beast is dead: one of the others hopes for rest, Solenne knows better.
func beast_slain() -> void:
	var candidates: Array = []
	for h in Game.party.heroes:
		if LINES["rest"].has(h.kind):
			candidates.append(h)
	var awake: Array = candidates.filter(func(h): return not h.downed)
	var who = (awake if not awake.is_empty() else candidates).pick_random() if not candidates.is_empty() else null
	if who != null:
		say(who, "rest")
	var sol = Game.party.hero("Solenne")
	if sol != null:
		say(sol, "rest_reply")
