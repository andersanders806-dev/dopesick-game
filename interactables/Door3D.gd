extends Area3D

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

@export var target_scene: String = ""
@export var target_spawn: String = ""

const HingedDoor := preload("res://interactables/HingedDoor3D.tscn")
const SlidingDoor := preload("res://interactables/SlidingDoor3D.tscn")
const DoorSky := preload("res://interactables/DoorSky.gd")
## The doors to the Dive Bar, the pharmacy, the supermarket, the electronics store and the kart track
## (both the street's and the room's) are real doors (HingedDoor3D, or SlidingDoor3D for the glass
## ones): the scene change is faked round them -- the door starts to swing or slide and the screen
## fades during it, and the door in the room you arrive in is just closing behind you.
var hinged: Node3D = null
const BAR_FADE := 0.45

## By the room behind the door (its scene name): the kind of door, and its leaf width and opening
## on the street's facade (`s`) and in the room's wall (`r`).
const STYLES := {
	"DiveBar3D": {"kind": "bar", "sw": 1.28, "so": 1.4, "rw": 1.12, "ro": 1.2},
	"StorePharmacy3D": {"kind": "sliding_glass", "so": 1.5, "ro": 1.6},
	"StoreSupermarket3D": {"kind": "sliding_glass", "so": 1.5, "ro": 1.6},
	"StoreElectronics3D": {"kind": "shop_glass", "sw": 1.28, "so": 1.4, "rw": 1.28, "ro": 1.4},
	"KartCenter3D": {"kind": "steel_back", "sw": 1.0, "so": 1.12, "rw": 1.0, "ro": 1.12},
}

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("doors")
	if not _style().is_empty():
		_install_hinged()

## The room this door is the door of: where it leads, or where it is.
func _room() -> String:
	if target_scene.ends_with("City3D.tscn"):
		return String(owner.name) if owner != null else ""
	return target_scene.get_file().get_basename()

func _style() -> Dictionary:
	return STYLES.get(_room(), {})

func _from_street() -> bool:
	return not target_scene.ends_with("City3D.tscn")

## Takes the slab's place: the door with its frame, on the street's facade (which has no opening: a
## dark doorway is put behind it) or in the room's wall (which gets a doorway cut in it).
func _install_hinged() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or not (mesh.mesh is BoxMesh):
		return
	var st := _style()
	var from_street := _from_street()
	var off := Vector3(mesh.position.x, 0.0, mesh.position.z)
	var approach := -off.normalized()
	mesh.visible = false
	var sliding: bool = st["kind"] == "sliding_glass"
	hinged = (SlidingDoor if sliding else HingedDoor).instantiate()
	hinged.name = "StoreDoor" if st["kind"] != "bar" else "BarDoor"
	hinged.kind = st["kind"]
	hinged.hinge_east = true
	hinged.arrival_id = "door"
	hinged.quiet_open = true
	hinged.frame = true
	hinged.opening = st["so"] if from_street else st["ro"]
	if not sliding:
		hinged.door_width = st["sw"] if from_street else st["rw"]
	if from_street and sliding:
		hinged.place = GameState.place_for_scene(target_scene)
	# Placed before it enters the tree: a leaf is an AnimatableBody3D that keeps the transform it came in with.
	hinged.position = off
	hinged.rotation.y = atan2(approach.x, approach.z)
	add_child(hinged)
	if from_street:
		var pl := GameState.place_for_scene(target_scene)
		var hrs: Array = GameState.OPENING_HOURS.get(pl, [0, 24])
		hinged.set_hours("OPEN %02d - %02d" % [int(hrs[0]), int(hrs[1]) % 24] if int(hrs[1]) - int(hrs[0]) < 24 and int(hrs[1]) > int(hrs[0]) else "OPEN 24 HRS")
	_dark_behind(from_street)
	if from_street:
		if st["kind"] == "bar":
			_leak_music()
	else:
		_open_wall(float(st["ro"]) / 2.0 + 0.02, off)
		if st["kind"] == "bar":
			_exit_lamp(approach)

## The room's way out is lit: an EXIT sign over it and its red glow on the door.
func _exit_lamp(approach: Vector3) -> void:
	var sign := Label3D.new()
	sign.name = "ExitSign"
	sign.text = "EXIT"
	sign.font_size = 44
	sign.pixel_size = 0.0025
	sign.shaded = false
	sign.outline_size = 0
	sign.modulate = Color(1.0, 0.28, 0.2)
	sign.double_sided = false
	add_child(sign)
	sign.position = hinged.position + approach * 0.12 + Vector3(0, 2.38, 0)
	sign.rotation.y = hinged.rotation.y
	var lamp := OmniLight3D.new()
	lamp.name = "ExitGlow"
	lamp.light_color = Color(1.0, 0.55, 0.42)
	lamp.light_energy = 0.45
	lamp.omni_range = 3.4
	lamp.shadow_enabled = false
	add_child(lamp)
	lamp.position = hinged.position + approach * 0.7 + Vector3(0, 2.0, 0)

## What shows where the door opens: a doorway of dark, warm at the top.
## The room behind a facade's door isn't there: a box room is drawn by interior mapping (interactables/interior_map.gdshader)
## in the doorway, with depth as you move. Shut for the night it's gone, and the facade's own shutter shows behind the glass.
var _room_mi: MeshInstance3D = null

func _on_clock(_m: int) -> void:
	_refresh_room()

func _exit_tree() -> void:
	if GameState.clock_changed.is_connected(_on_clock):
		GameState.clock_changed.disconnect(_on_clock)

func _refresh_room() -> void:
	if _room_mi == null:
		return
	var place := GameState.place_for_scene(target_scene)
	_room_mi.visible = place == "" or GameState.is_open(place)

func _dark_behind(from_street: bool) -> void:
	if not from_street:
		return
	var dim: bool = _style()["kind"] in ["bar", "steel_back"]
	var q := QuadMesh.new()
	var size := Vector2(float(hinged.opening) + 0.1, 2.2)
	q.size = size
	q.material = DoorSky.room_material("dim" if dim else "store", size)
	var mi := MeshInstance3D.new()
	mi.name = "DoorwayRoom"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var n := Vector3(hinged.position.x, 0.0, hinged.position.z)
	var back := n.normalized() * 0.025
	mi.position = Vector3(n.x + back.x, 1.1, n.z + back.z)
	mi.rotation.y = hinged.rotation.y
	_room_mi = mi
	GameState.clock_changed.connect(_on_clock)
	_refresh_room()

## A room's wall has no doorway where its door is: cut one (three boxes round it), and put the night
## street behind it. The wall is whichever one's box the door stands in.
func _open_wall(half: float, off: Vector3) -> void:
	if owner == null:
		return
	var here := hinged.global_position
	var wall: StaticBody3D = null
	for c in owner.get_children():
		if c is StaticBody3D and String(c.name).begins_with("Wall") and c.get_node_or_null("Mesh") is MeshInstance3D and c.get_node_or_null("CollisionShape3D") is CollisionShape3D:
			var m := c.get_node("Mesh") as MeshInstance3D
			if not (m.mesh is BoxMesh):
				continue
			var sz: Vector3 = (m.mesh as BoxMesh).size
			var d: Vector3 = (here - (c as Node3D).global_position).abs()
			if d.x <= sz.x / 2.0 + 0.1 and d.z <= sz.z / 2.0 + 0.1 and d.y <= sz.y / 2.0 + 1.3:
				wall = c
				break
	if wall == null:
		return
	var mesh := wall.get_node("Mesh") as MeshInstance3D
	var shape := wall.get_node("CollisionShape3D") as CollisionShape3D
	var size: Vector3 = (mesh.mesh as BoxMesh).size
	var mat: Material = mesh.material_override if mesh.material_override != null else (mesh.mesh as BoxMesh).material
	# The wall runs along its longer horizontal side.
	var along_z := size.z >= size.x
	var local := here - wall.global_position
	var t := local.z if along_z else local.x
	var len_total := size.z if along_z else size.x
	var top := 2.2
	var floor_y := -wall.global_position.y
	# [from, to, y from, y to] along the wall
	var parts := [
		[-len_total / 2.0, t - half, -size.y / 2.0, size.y / 2.0],
		[t + half, len_total / 2.0, -size.y / 2.0, size.y / 2.0],
		[t - half, t + half, top + floor_y, size.y / 2.0],
	]
	mesh.visible = false
	shape.disabled = true
	var i := 0
	for part in parts:
		var p0: float = part[0]
		var p1: float = part[1]
		var y0: float = part[2]
		var y1: float = part[3]
		if p1 - p0 < 0.01 or y1 - y0 < 0.01:
			continue
		var sz: Vector3 = Vector3(size.x, y1 - y0, p1 - p0) if along_z else Vector3(p1 - p0, y1 - y0, size.z)
		var mid: float = (p0 + p1) / 2.0
		var c: Vector3 = Vector3(0.0, (y0 + y1) / 2.0, mid) if along_z else Vector3(mid, (y0 + y1) / 2.0, 0.0)
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
	# The street outside, matching the hour: a quad behind the doorway that shows the street panorama by the
	# direction you look (at infinity, so it needs no depth and slides right as you move).
	var back := MeshInstance3D.new()
	back.name = "Street"
	var q := QuadMesh.new()
	q.size = Vector2(7.0, 4.0)
	q.material = DoorSky.sky_material()
	back.mesh = q
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)
	var out := Vector3(off.x, 0.0, off.z).normalized()
	back.position = hinged.position + out * 1.2 + Vector3(0, 0.9, 0)
	back.rotation.y = hinged.rotation.y

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
	hinged.push_open(pos, 1.5, _from_street())
	hinged.hold_open(1.5)
	hinged.arrival_pending = "door"
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
