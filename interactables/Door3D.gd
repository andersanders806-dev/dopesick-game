extends Area3D

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

@export var target_scene: String = ""
@export var target_spawn: String = ""

const HingedDoor := preload("res://interactables/HingedDoor3D.tscn")
## The Dive Bar's two doors (the street's and the room's) are real doors
## (interactables/HingedDoor3D.gd): the scene change is faked round them -- the
## leaf starts to swing and the screen fades during it, and the door in the room
## you arrive in is just finishing its close behind you.
var hinged: Node3D = null
const BAR_FADE := 0.45

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("doors")
	if _is_bar_door():
		_install_hinged()

func _is_bar_door() -> bool:
	if target_scene.ends_with("DiveBar3D.tscn"):
		return true
	return target_scene.ends_with("City3D.tscn") and owner != null and String(owner.name) == "DiveBar3D"

## Takes the slab's place: a wood door with a frame, hinged on the east side
## as seen from where you stand. In the room, the wall gets a doorway cut in it.
func _install_hinged() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or not (mesh.mesh is BoxMesh):
		return
	var from_street := target_scene.ends_with("DiveBar3D.tscn")
	var off := Vector3(mesh.position.x, 0.0, mesh.position.z)
	var approach := -off.normalized()
	mesh.visible = false
	hinged = HingedDoor.instantiate()
	hinged.name = "BarDoor"
	hinged.kind = "bar"
	hinged.hinge_east = true
	hinged.arrival_id = "bar"
	hinged.quiet_open = true
	if from_street:
		# On the facade (which has the opening): the leaf, the frame, the dark behind it.
		hinged.door_width = 1.28
		hinged.opening = 1.4
		hinged.frame = true
	else:
		hinged.door_width = 1.12
		hinged.opening = 1.2
		hinged.frame = true
	add_child(hinged)
	hinged.position = off
	hinged.rotation.y = atan2(approach.x, approach.z)
	_dark_behind(from_street)
	if from_street:
		_leak_music()
	else:
		_open_wall()

## What shows where the door opens: a doorway of dark, warm at the top.
func _dark_behind(from_street: bool) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.012, 0.01))
	grad.set_color(1, Color(0.16, 0.09, 0.05) if from_street else Color(0.03, 0.04, 0.07))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 1.0)
	gt.fill_to = Vector2(0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = gt
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 2.2)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.name = "DoorwayDark"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var n := Vector3(hinged.position.x, 0.0, hinged.position.z)
	var back := n.normalized() * 0.025
	mi.position = Vector3(n.x + back.x, 1.1, n.z + back.z)
	mi.rotation.y = hinged.rotation.y

## The Dive Bar's wall has no doorway where its door is: cut one, and put the
## night street behind it.
func _open_wall() -> void:
	var wall := owner.get_node_or_null("WallEast") as StaticBody3D if owner != null else null
	if wall == null:
		return
	var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
	var shape := wall.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if mesh == null or shape == null or not (mesh.mesh is BoxMesh):
		return
	var size: Vector3 = (mesh.mesh as BoxMesh).size
	var mat: Material = mesh.material_override if mesh.material_override != null else (mesh.mesh as BoxMesh).material
	var dz := hinged.global_position.z - wall.global_position.z
	var half := 0.62
	var top := 2.15
	# [z from, z to, y from, y to]
	var parts := [
		[-size.z / 2.0, dz - half, -size.y / 2.0, size.y / 2.0],
		[dz + half, size.z / 2.0, -size.y / 2.0, size.y / 2.0],
		[dz - half, dz + half, top - wall.global_position.y, size.y / 2.0],
	]
	mesh.visible = false
	shape.disabled = true
	var i := 0
	for part in parts:
		var sz := Vector3(size.x, part[3] - part[2], part[1] - part[0])
		var c := Vector3(0.0, (part[2] + part[3]) / 2.0, (part[0] + part[1]) / 2.0)
		var bm := BoxMesh.new()
		bm.size = sz
		var mi := MeshInstance3D.new()
		mi.name = "WallPart%d" % i
		mi.mesh = bm
		mi.material_override = mat
		wall.add_child(mi)
		mi.position = c
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.name = "WallShape%d" % i
		wall.add_child(cs)
		cs.position = c
		i += 1
	# The street, a long way off and dark.
	var back := MeshInstance3D.new()
	back.name = "NightStreet"
	var q := QuadMesh.new()
	q.size = Vector2(6.0, 3.2)
	var bm2 := StandardMaterial3D.new()
	bm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm2.albedo_color = Color(0.035, 0.04, 0.06)
	q.material = bm2
	back.mesh = q
	wall.add_child(back)
	back.position = Vector3(1.6, 0.4, dz)
	back.rotation.y = -PI / 2.0

## A bar leaks: from the street you hear the jukebox through the door, a muffled
## thump of it, and a lot more when the door's open.
func _leak_music() -> void:
	var leak := preload("res://world/BarLeak.gd").new()
	leak.name = "BarLeak"
	leak.door = hinged
	add_child(leak)
	leak.position = hinged.position + Vector3(0, 1.5, -0.6)

func interact(player: Node) -> void:
	if target_scene == "":
		return
	if target_scene.ends_with("Apartment3D.tscn") and GameState.locked_out():
		_locked_out(player)
		return
	var place := GameState.place_for_scene(target_scene)
	if place != "" and not GameState.is_open(place):
		_show_closed(player, place)
		return
	SFX.play("door")
	GameState.pending_spawn = target_spawn
	if hinged != null and is_instance_valid(hinged):
		_swing_through(player)
		return
	SceneLoader.go(target_scene, target_spawn)

## The leaf starts to swing while the screen fades, and sound carries on
## through the change; the room you arrive in has its own door closing.
func _swing_through(player: Node) -> void:
	hinged.process_mode = Node.PROCESS_MODE_ALWAYS
	var pos := (player as Node3D).global_position
	# Pulled open from the street, shoved from inside.
	hinged.push_open(pos, 1.5, target_scene.ends_with("DiveBar3D.tscn"))
	hinged.hold_open(1.5)
	hinged.arrival_pending = "bar"
	SceneLoader.go(target_scene, target_spawn, BAR_FADE)

func _show_closed(player: Node, place: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	if hinged != null and is_instance_valid(hinged):
		hinged.rattle()
		await get_tree().create_timer(0.55).timeout
	else:
		SFX.play("latch", -4.0)
	var name: String = "the bar" if place == "bar" else GameState.STORE_NAMES.get(place, "it")
	hud.show_dialogue("", "Locked. %s opens at %02d:00. It's %s." % [name.left(1).to_upper() + name.substr(1), GameState.opening_hour(place), GameState.clock_text()])

## Behind on the rent long enough that the lock's been changed: buzz the
## landlord and pay everything, or walk away.
func _locked_out(player: Node) -> void:
	SFX.play("latch", -4.0)
	player.dialogue_active = true
	var awake := GameState.hours_contain(GameState.LANDLORD_HOURS, GameState.hour())
	var owed := GameState.rent_amount()
	var disabled := [] if awake and GameState.cash >= owed else [0]
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(_i: int): _pay_landlord(player))
	menu.cancelled.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
	var text := "Your key doesn't turn. A new lock, and a notice taped over it: $%d to the landlord, locksmith included." % owed
	if not awake:
		text += " His window's dark."
	menu.open("", text, ["Buzz the landlord -- pay $%d" % owed], disabled)

func _pay_landlord(player: Node) -> void:
	if not GameState.pay_rent():
		return
	SFX.play("cash")
	if is_instance_valid(player):
		player.dialogue_active = false
	interact(player)
