extends Node
## The block as Dead Block's arena. City3D adds this when GameState.mode is
## "zombies", after it has left the story's people, traffic and chores out:
## what's placed in the scene itself goes here (the shops' doors, the pusher
## and the rest of the cast); then permanent night under a dense, red fog,
## streetlights that stutter, the zombie HUD, and round 1.
##
## The parked cars stay for now (a later task wrecks them).

const ZombieHudScript := preload("res://ui/ZombieHud.gd")

## Scene-placed nodes of the story: the doors to every shop, the people.
const STORY_NODES := ["StationDoor", "Pusher", "Lookout", "Ray"]
const STORY_NODE_PREFIXES := ["DoorTo"]

## A red-tinged night. The sky is what the fog fades into; the moon is a
## dull red wash.
const SKY := Color(0.17, 0.025, 0.03)
const AMBIENT := Color(0.55, 0.28, 0.32)
const AMBIENT_ENERGY := 0.22
const FOG_LIGHT := Color(0.2, 0.05, 0.055)
const FOG_DENSITY := 0.05
const VOL_FOG_DENSITY := 0.03
const MOON_COLOR := Color(0.85, 0.38, 0.38)
const MOON_ENERGY := 0.22

## Every third streetlight stutters: a steady spell, then a burst of
## on-and-off, now and then dead for a moment.
const FLICKER_EVERY := 3
const STEADY_TIME := Vector2(1.2, 6.0)
const BURST_TIME := Vector2(0.15, 0.6)
const DEAD_CHANCE := 0.25

var city: Node3D
var hud: CanvasLayer
## [light, full energy, seconds to the next change, in a burst, dead]
var _flickering: Array = []
## How many streetlights stutter (the smoke test reads it).
var flicker_count: int:
	get: return _flickering.size()

func setup(block: Node3D) -> void:
	city = block
	_strip_story()
	_set_night()
	_pick_flickering()
	_hide_story_hud()
	hud = ZombieHudScript.new()
	hud.name = "ZombieHud"
	city.add_child(hud)
	ZombieMode.start_round()

func _strip_story() -> void:
	for child in city.get_children():
		var n := String(child.name)
		if n in STORY_NODES or STORY_NODE_PREFIXES.any(func(pre): return n.begins_with(pre)):
			# Out of the tree now (find_child, groups), freed at frame end.
			city.remove_child(child)
			child.queue_free()

## Over City3D's night baseline, which its daylight blend starts from (and
## which GameState.daylight() == 0 keeps us on).
func _set_night() -> void:
	var env: Environment = city._env
	var night: Dictionary = city._night
	night["sky"] = SKY
	night["ambient"] = AMBIENT
	night["ambient_energy"] = AMBIENT_ENERGY
	night["fog_light"] = FOG_LIGHT
	night["fog_density"] = FOG_DENSITY
	night["vol_density"] = VOL_FOG_DENSITY
	night["moon_color"] = MOON_COLOR
	night["moon_energy"] = MOON_ENERGY
	env.fog_enabled = true
	env.fog_sky_affect = 1.0
	env.volumetric_fog_albedo = Color(0.75, 0.45, 0.45)
	city._apply_daylight()

func _pick_flickering() -> void:
	var i := 0
	for entry in city._night_lights:
		var light := entry[0] as Light3D
		if not light.get_parent().name.begins_with("Streetlight"):
			continue
		if i % FLICKER_EVERY == 0:
			_flickering.append([light, light.light_energy, randf_range(0.0, STEADY_TIME.y), false, false])
		i += 1

## The story's cash, craving and clock mean nothing here.
func _hide_story_hud() -> void:
	var story_hud := get_tree().get_first_node_in_group("hud") as CanvasLayer
	if story_hud:
		story_hud.visible = false

func _process(delta: float) -> void:
	for f in _flickering:
		var light := f[0] as Light3D
		if not is_instance_valid(light):
			continue
		f[2] -= delta
		if f[2] <= 0.0:
			f[3] = not f[3]
			f[2] = randf_range(BURST_TIME.x, BURST_TIME.y) if f[3] else randf_range(STEADY_TIME.x, STEADY_TIME.y)
			f[4] = f[3] and randf() < DEAD_CHANCE
		# Full energy is the lamp's night one, kept when the burst began; a
		# sleeping cell's lamps are hidden by BlockCells, whatever we set.
		var base: float = f[1]
		var lit := base
		if f[3]:
			lit = 0.0 if f[4] else base * (1.0 if randf() > 0.45 else randf_range(0.0, 0.35))
		light.light_energy = lit
