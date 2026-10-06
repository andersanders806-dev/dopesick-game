extends Node3D
## The alley behind the dumpster, some nights: one of the Dive Bar regulars
## has gone over (GameState.od_event). They've got OD_WINDOW seconds of you
## being out here to see it. Naloxone, the payphone, their pockets, or
## walking on -- and the day after a death, candles and their name on the
## wall (the "vigil" headline).

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")
const SPOT := Vector3(22.4, 0, -2.6)

var victim: Area3D
var _victim_for: String = ""
var _announced: bool = false
var _candles: Array = []

func _ready() -> void:
	GameState.overdose_changed.connect(refresh)
	refresh()
	if Headlines.is_today("vigil") and GameState.vigil_for != "":
		_build_vigil()

func _process(delta: float) -> void:
	if GameState.od_event.get("state", "") == "down":
		GameState.od_event["left"] = float(GameState.od_event["left"]) - delta
		if float(GameState.od_event["left"]) <= 0.0:
			GameState.resolve_overdose("walk")
	for c in _candles:
		c.light_energy = 0.4 + 0.2 * absf(sin(Time.get_ticks_msec() * 0.003 + c.position.x * 7.0))

func refresh() -> void:
	var down: bool = GameState.od_event.get("state", "") == "down"
	var who: String = GameState.od_event.get("who", "")
	if down and who != _victim_for:
		_build_victim(who)
	if victim:
		victim.visible = down
		if down:
			victim.add_to_group("interactable")
		else:
			victim.remove_from_group("interactable")
	if down and not _announced:
		_announced = true
		Graphics._show_toast("Someone's down in the alley by the dumpster.")

func _build_victim(who: String) -> void:
	if victim:
		victim.queue_free()
	_victim_for = who
	victim = Area3D.new()
	victim.name = "Victim"
	victim.collision_layer = 4
	victim.collision_mask = 0
	victim.monitoring = false
	victim.set_script(InteractableScript)
	add_child(victim)
	victim.position = SPOT
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.0, 1.4)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0)
	victim.add_child(shape)
	var root := Node3D.new()
	root.scale = Vector3.ONE * 1.5
	root.rotation_degrees.y = 100.0
	victim.add_child(root)
	var model: Node = load(CharacterCast.model_for(who)).instantiate()
	root.add_child(model)
	CharacterCast.dress(model, who)
	var anim := CharacterAnimator.new(model)
	if anim.has_clip("collapse"):
		anim.set_rest_clip("collapse")
	else:
		# The Rocketbox people have no fall: lay the body down instead, on
		# its back along the wall, still -- a little off the ground so it
		# doesn't sink into the asphalt.
		root.rotation_degrees = Vector3(-90.0, 100.0, 0.0)
		root.position.y = 0.12
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
		if ap and ap.has_animation("idle"):
			# Arms at the sides, not the bind pose's A: snap to the idle's
			# first frame (no blend), then hold it.
			ap.play("idle", 0.0)
			ap.seek(0.0, true)
			ap.pause()
		victim.set_meta("lying", true)
	victim.set_meta("anim", anim)
	victim.interacted.connect(_on_victim)

func _on_victim(_zone: Area3D, player: Node) -> void:
	player.dialogue_active = true
	var who: String = GameState.od_event.get("who", "someone")
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _choose(["naloxone", "payphone", "pockets", "walk"][i]))
	menu.cancelled.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
	var text := "It's %s, on the ground behind the dumpster. Lips gone blue, breathing in long gaps, a snore that isn't one." % who
	menu.open("", text, ["Use your naloxone (%d)" % GameState.naloxone, "Shout for help and run for the payphone", "Go through their pockets", "Walk away"], [] if GameState.naloxone > 0 else [0])

## What you did, and what it did. Returns "saved" or "dead".
func _choose(choice: String) -> String:
	var who: String = GameState.od_event.get("who", "them")
	var outcome := GameState.resolve_overdose(choice)
	var line := ""
	match choice:
		"naloxone":
			line = "One spray. A long minute. Then %s comes round gasping -- sick, furious, alive." % who
		"payphone":
			line = "You yell until a light goes on, and run for the payphone on the corner. The ambulance comes fast. So does a cop."
			var city := get_parent()
			if city.has_method("_spawn_patrol"):
				city._spawn_patrol(Vector3(18.0, 0, -1.3))
			var siren := AudioStreamPlayer.new()
			siren.stream = SFX.SIREN_STREAM
			siren.volume_db = -10.0
			add_child(siren)
			siren.play()
			get_tree().create_timer(4.0).timeout.connect(siren.queue_free)
		"pockets":
			line = "You go through their jacket. $%d. They don't move. They don't move again." % int(GameState.od_event.get("took", 0))
		_:
			line = "You keep walking." + (" Later you hear the siren." if outcome == "saved" else " Nobody else stops either.")
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player:
		player.dialogue_active = true
		hud.show_dialogue("", line)
	return outcome

## The day after: candles at the alley mouth and a name in marker.
func _build_vigil() -> void:
	var vigil := Node3D.new()
	vigil.name = "Vigil"
	add_child(vigil)
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.95, 0.92, 0.85)
	wax.emission_enabled = true
	wax.emission = Color(1.0, 0.75, 0.4)
	wax.emission_energy_multiplier = 0.6
	for i in 5:
		var c := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.03
		mesh.bottom_radius = 0.03
		mesh.height = 0.12
		mesh.material = wax
		c.mesh = mesh
		vigil.add_child(c)
		c.position = Vector3(20.6 + i * 0.2, 0.06, -3.95 + (i % 2) * 0.08)
		var flame := OmniLight3D.new()
		flame.light_color = Color(1.0, 0.7, 0.35)
		flame.omni_range = 1.5
		flame.light_energy = 0.5
		flame.shadow_enabled = false
		vigil.add_child(flame)
		flame.position = c.position + Vector3(0, 0.12, 0)
		_candles.append(flame)
	var name_label := Label3D.new()
	name_label.text = "RIP %s" % GameState.vigil_for.to_upper()
	name_label.font_size = 40
	name_label.pixel_size = 0.005
	name_label.modulate = Color(0.95, 0.95, 0.9)
	vigil.add_child(name_label)
	name_label.position = Vector3(21.0, 1.3, -4.38)
