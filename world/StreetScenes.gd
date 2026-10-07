extends Node3D
## The block's regulars, who keep hours: a smoker in the liquor store's
## doorway from late morning to late night, a couple arguing outside the
## bar after dark (walk close and you catch pieces of it), and a man asleep
## on the apartment steps until morning. Each one is there on a schedule
## and can be talked to. Passersby ducking under the awnings when it rains
## live in Pedestrian3D.
##
## Kept clear of the doors (1.2 m or more) and well away from the pusher's
## corner, so none of them ever steals the "E" from something you're
## walking up to.

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")

## name, where, facing (degrees, 0 = toward the street), [from, to) hours,
## pose, who they look like (a CharacterCast role, or a model and colours),
## and what they say when you talk to them. Dee, Marcus and Carl eat at the
## shelter 17-20 and are out here the rest of their night.
const REGULARS := [
	# West of the liquor store's door: the pusher works the east side, and a
	# regular that close would take the "E" from him.
	{"name": "Smoker", "pos": Vector3(8.7, 0, -4.05), "yaw": -20.0, "hours": [10, 23], "pose": "idle",
		"role": "smoker",
		"lines": ["\"Break's fifteen minutes. I take twenty-five.\"", "\"Don't ask me for one. I'm down to three.\"", "\"You look like hell, man. No offence.\""]},
	{"name": "Dee", "pos": Vector3(-5.6, 0, -3.3), "yaw": 80.0, "hours": [21, 2], "pose": "idle",
		"role": "shelter_diner_b",
		"lines": ["\"This is between me and him. Keep walking.\"", "\"Do I know you? No. Good.\""]},
	{"name": "Marcus", "pos": Vector3(-4.5, 0, -3.3), "yaw": -100.0, "hours": [21, 2], "pose": "idle",
		"role": "shelter_diner_c",
		"lines": ["\"Man, not now.\"", "\"She'll calm down. She always calms down.\""]},
	{"name": "Carl", "pos": Vector3(-16.1, 0, -4.05), "yaw": 0.0, "hours": [0, 9], "pose": "sit",
		"role": "shelter_diner_a",
		"lines": ["He doesn't wake up. His chest is going up and down, at least.", "\"...mm. Five more minutes, Ma.\"", "He pulls his coat tighter without opening his eyes."]},
]
## What you overhear walking past the argument.
const ARGUMENT := [
	"...said you'd pay me back Friday...", "...every time, Marcus, every single time...",
	"...keep your voice down...", "...where'd the rent go then?", "...I'm not doing this out here...",
	"...you think I don't see it?", "...one more week, that's all I'm asking...",
]
const OVERHEAR_RANGE := 4.5

var _people: Array = []  # {spec, node, anim, label}
var _talk_timer: float = 2.0

func _ready() -> void:
	for spec in REGULARS:
		_people.append(_make(spec))
	GameState.clock_changed.connect(func(_m): _apply_schedule())
	_apply_schedule()

func _make(spec: Dictionary) -> Dictionary:
	var zone := Area3D.new()
	zone.name = spec["name"]
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	add_child(zone)
	zone.position = spec["pos"]
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = 1.4
	shape.shape = cyl
	shape.position = Vector3(0, 0.7, 0)
	zone.add_child(shape)
	var root := Node3D.new()
	root.scale = Vector3.ONE * 1.5
	root.rotation_degrees.y = spec["yaw"]
	zone.add_child(root)
	# Dee, Marcus and Carl are the shelter's dinner regulars: same bodies,
	# same clothes, on the block at the other end of their day.
	var model: Node
	if spec.has("role"):
		model = CharacterCast.scene_for(CharacterCast.model_for(spec["role"])).instantiate()
		root.add_child(model)
		CharacterCast.dress(model, spec["role"])
	else:
		model = CharacterCast.scene_for(spec["model"]).instantiate()
		root.add_child(model)
		CharacterLook.apply(model, spec["look"])
	var anim := CharacterAnimator.new(model)
	anim.set_rest_clip(spec["pose"])
	if spec["pose"] == "sit":
		root.position.y = -0.35
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.3, 0)
	label.font_size = 36
	label.pixel_size = 0.004
	label.modulate = Color(1, 0.92, 0.8, 0)
	label.outline_size = 8
	zone.add_child(label)
	if spec["name"] == "Smoker":
		_add_cigarette(zone)
	zone.interacted.connect(_on_talk.bind(spec))
	return {"spec": spec, "node": zone, "anim": anim, "label": label}

## A glowing ember at hand height and the odd drift of smoke.
func _add_cigarette(zone: Node3D) -> void:
	var ember := OmniLight3D.new()
	ember.name = "Ember"
	ember.light_color = Color(1.0, 0.45, 0.15)
	ember.omni_range = 0.7
	ember.light_energy = 0.6
	ember.position = Vector3(0.25, 1.45, 0.25)
	zone.add_child(ember)
	var smoke := CPUParticles3D.new()
	smoke.position = ember.position + Vector3(0, 0.1, 0)
	smoke.amount = 8
	smoke.lifetime = 3.0
	smoke.direction = Vector3(0.2, 1, 0)
	smoke.spread = 15.0
	smoke.initial_velocity_min = 0.15
	smoke.initial_velocity_max = 0.3
	smoke.gravity = Vector3(0.05, 0.05, 0)
	smoke.scale_amount_min = 0.2
	smoke.scale_amount_max = 0.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.75, 0.75, 0.78, 0.18)
	quad.material = mat
	smoke.mesh = quad
	zone.add_child(smoke)

func _present(spec: Dictionary) -> bool:
	return GameState.hours_contain(spec["hours"], GameState.hour())

func _apply_schedule() -> void:
	for p in _people:
		var here := _present(p["spec"])
		p["node"].visible = here
		if here and not p["node"].is_in_group("interactable"):
			p["node"].add_to_group("interactable")
		elif not here and p["node"].is_in_group("interactable"):
			p["node"].remove_from_group("interactable")

func _process(delta: float) -> void:
	for p in _people:
		var label: Label3D = p["label"]
		if label.modulate.a > 0.0:
			label.modulate.a = maxf(0.0, label.modulate.a - delta * 0.35)
		if p["spec"]["name"] == "Smoker" and p["node"].visible:
			var ember := p["node"].get_node("Ember") as OmniLight3D
			ember.light_energy = 0.45 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.0017))
	# The argument: one of them gestures, and if you're close you hear it.
	_talk_timer -= delta
	if _talk_timer > 0.0:
		return
	_talk_timer = randf_range(2.5, 4.5)
	var pair := _people.filter(func(p): return p["spec"]["name"] in ["Dee", "Marcus"] and p["node"].visible)
	if pair.is_empty():
		return
	var who: Dictionary = pair.pick_random()
	who["anim"].play_once_timed("interact", 1.2)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_to(who["node"].global_position) < OVERHEAR_RANGE:
		var label: Label3D = who["label"]
		label.text = ARGUMENT.pick_random()
		label.modulate.a = 1.0

func _on_talk(_zone: Area3D, player: Node, spec: Dictionary) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	var line: String = spec["lines"].pick_random()
	hud.show_dialogue(spec["name"] if line.begins_with("\"") else "", line)
