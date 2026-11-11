extends RefCounted
## The steel back doors of the service lane and the back alley, and the corner shop's and the liquor store's
## on the lane: real doors (interactables/HingedDoor3D.gd, kind steel_back) with a heavy closer, a panic bar
## on the inside and a scrape. There are no stock rooms behind any of them -- the lane's doors are drawn flush
## in a wall with nothing behind it -- so they're set pieces: always locked. Walk at one and the handle
## rattles and the leaf jerks; E rattles it and says why (a note on the door, or the shop's own voice).

const HingedDoor := preload("res://interactables/HingedDoor3D.tscn")

const NOTES := [
	"Locked. A sign taped on the inside of the glass: STAFF ONLY. DELIVERIES 06:00-07:00. NO ONE HERE AFTER.",
	"Locked. The steel's cold and nobody's answering. A light burns over it all night.",
	"Locked. Fresh scratches round the lock. Someone else has already tried.",
	"Locked. Behind it, faint, a TV nobody is watching.",
	"Locked. Dumpster smell, no handle on this side.",
]

## City3D calls this once the street's built.
static func install(city: Node3D) -> void:
	if GameState.mode == "zombies":
		return
	var i := 0
	# The doors the lane and the back alley were drawn with: a steel slab in a wall, a step, a caged light.
	for n in city.find_children("LaneDoor*", "Node3D", true, false) + city.find_children("AlleyDoor*", "Node3D", true, false):
		var slab := n.get_node_or_null("Door") as MeshInstance3D
		if slab == null:
			continue
		slab.visible = false
		_door(n, Vector3(0.0, 0.0, 0.05), 0.0, NOTES[i % NOTES.size()])
		i += 1
	# The back of the corner shop and of the liquor store, on the service lane.
	for pair in [["Cell_Main/WalkIn_Convenience", "Back of the corner shop", "Locked. The corner shop's back door: steel, and from the other side someone's fridge hums. Deliveries 06:00-07:00."],
			["Cell_Main/WalkIn_Liquor", "Back of the liquor store", "Locked. The liquor store's back door, a padlock hasp on top of the deadbolt. Nobody's getting in here for free."]]:
		var shop := city.get_node_or_null(pair[0]) as Node3D
		if shop == null:
			continue
		var holder := Node3D.new()
		holder.name = "LaneDoorOf" + String(shop.name)
		city.add_child(holder)
		# The shop's back wall's outside face: 11 m back from the front wall plus its 0.2 m.
		holder.global_position = Vector3(shop.global_position.x, 0.0, shop.global_position.z - 11.2)
		holder.rotation.y = PI
		_door(holder, Vector3(0.0, 0.0, 0.03), 0.0, pair[2])
		_lamp(holder)

static func _door(parent: Node3D, pos: Vector3, yaw: float, note: String) -> void:
	var d := HingedDoor.instantiate()
	d.name = "BackDoor"
	d.kind = "steel_back"
	d.hinge_east = true
	d.frame = true
	d.reachable = true
	d.lock_text = note
	d.position = pos
	d.rotation.y = yaw
	parent.add_child(d)
	d.set_locked(true)

## A caged light over it, on all night (the model the lane's own doors have).
static func _lamp(parent: Node3D) -> void:
	var path := "res://assets/polyhaven/security_light/security_light.gltf"
	if ResourceLoader.exists(path):
		var lamp: Node3D = (load(path) as PackedScene).instantiate()
		lamp.name = "Lamp"
		parent.add_child(lamp)
		lamp.position = Vector3(0, 2.55, 0.05)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 0.9
	light.omni_range = 5.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 25.0
	light.distance_fade_length = 8.0
	parent.add_child(light)
	light.position = Vector3(0, 2.4, 0.6)
