extends SceneTree
## Plays the game with a bot and saves screenshots at chosen moments.
## Needs a real display (or a virtual one). Example:
##   SHOTS="20,90" OUT=/tmp/shots godot --fixed-fps 20 --path . --script res://tests/screenshot.gd

var _shots: Array = []
var _out := ""
var _taken := 0


func _initialize() -> void:
	for s in OS.get_environment("SHOTS").split(",", false):
		_shots.append(float(s))
	_out = OS.get_environment("OUT")
	var game = root.get_node("Game")
	game.skip_camp = true
	game.saving_enabled = false
	# PARTY=kheiron,halvar,rhian photographs another trio.
	var picked := OS.get_environment("PARTY")
	if picked != "":
		game.party_override = Array(picked.split(","))
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	var main = current_scene
	if main == null or not main.has_method("choose_upgrade"):
		return false
	var game = root.get_node("Game")
	if game.party == null:
		return false
	game.hitstop_enabled = false
	var t: float = game.time_alive
	main.autopilot = true
	if fmod(t, 4.0) < 2.5:
		main.autopilot_dir = Vector3(cos(t * 0.35), 0.0, sin(t * 0.35))
	else:
		main.autopilot_dir = Vector3.ZERO
	if main.choosing:
		if _taken < _shots.size() and t >= _shots[_taken] - 0.5:
			pass # let the level-up screen show up in the shot
		else:
			main.choose_upgrade(0)
	if _taken < _shots.size() and t >= _shots[_taken]:
		var img := root.get_texture().get_image()
		var path := "%s/shot_%05.1fs.png" % [_out, t]
		img.save_png(path)
		print("saved ", path)
		_taken += 1
		if main.choosing:
			main.choose_upgrade(0)
	if _taken >= _shots.size() or main.ended:
		return true
	return false
