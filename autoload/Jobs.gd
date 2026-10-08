extends Node
## Honest work, for less than stealing pays and with nobody chasing you:
##
## - The dock (lot out back, 6-10, once a day): ask the delivery driver for
##   work, then carry five boxes from the truck to the pallet. $12.
## - Flyers (the shelter's noticeboard, once a day): five flyers for the
##   laundromat, pinned up at the marked spots along the block. $8.
## - Bottles and cans: a few turn up in the gutter every day. The machine
##   inside the supermarket's door pays $1 for every three.
##
## Everything here is added to rooms as they load (decorate(), called by
## WorldRoot3D once the navmesh is baked, so every zone lands on a spot
## you can actually walk to).

const InteractableScript := preload("res://interactables/Interactable3D.gd")
const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

const DOCK_BOXES := 5
const DOCK_PAY := 12
const DOCK_MINUTES := 90
const FLYER_PAY := 8
const FLYER_SPOTS := [-21.0, -13.9, -8.8, -1.7, 5.3, 21.0]
const FLYERS := 5
const BOTTLES_PER_DOLLAR := 3
const BOTTLES_PER_DAY := 5
const CARRY_SPEED := 0.8

## Run state, saved with the run: {kind, left} for the job in hand, bottles
## in your pockets, and which gutter spots are still to be picked today.
var job: Dictionary = {}
var bottles: int = 0
var bottle_day: int = -1
var bottle_spots: Array = []

func _ready() -> void:
	GameState.run_ended.connect(func(_s): reset())

func reset() -> void:
	job = {}
	bottles = 0
	bottle_day = -1
	bottle_spots = []

func carrying_box() -> bool:
	return job.get("kind", "") == "dock" and job.get("holding", false)

## Adds this room's jobs. Deferred a physics frame so the fresh navmesh is
## live for snapping.
func decorate(room: Node3D) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(room):
		return
	match room.name:
		"Backyard3D":
			# No truck on a strike day (Headlines), so no job unloading it.
			if GameState.hours_contain([6, 10], GameState.hour()) and Headlines.delivery_today():
				_zone(room, "DockAsk", Vector3(3.4, 0, -0.4), _on_dock_ask)
				_zone(room, "DockTruck", Vector3(3.9, 0, -2.3), _on_dock_truck)
				_zone(room, "DockPallet", Vector3(1.3, 0, -2.4), _on_dock_pallet)
		"Shelter3D":
			_zone(room, "Noticeboard", Vector3(-4.1, 0, 2.0), _on_board, true)
		"StoreSupermarket3D":
			_zone(room, "BottleMachine", Vector3(-7.0, 0, 3.4), _on_machine, true)
		"City3D":
			if job.get("kind", "") == "flyers":
				for x in job["left"]:
					_flyer_spot(room, x)
			_scatter_bottles(room)

func _snap(room: Node3D, p: Vector3) -> Vector3:
	var map := room.get_world_3d().navigation_map
	var q := NavigationServer3D.map_get_closest_point(map, p)
	return q if q != Vector3.ZERO or p == Vector3.ZERO else p

func _zone(room: Node3D, zname: String, pos: Vector3, action: Callable, marker := false) -> Area3D:
	var zone := Area3D.new()
	zone.name = zname
	zone.set_meta("kind", zname)
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	room.add_child(zone)
	zone.global_position = _snap(room, pos)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.4, 1.2)
	shape.shape = box
	shape.position = Vector3(0, 0.7, 0)
	zone.add_child(shape)
	zone.interacted.connect(func(_z, player): action.call(zone, player))
	if marker:
		_add_marker(zone, Color(0.95, 0.85, 0.5))
	return zone

## A small warm glow so a job spot reads from across the room.
func _add_marker(zone: Node3D, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 1.4
	light.light_energy = 0.7
	light.position = Vector3(0, 1.2, 0)
	zone.add_child(light)

func _say(text: String, speaker := "") -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player:
		player.dialogue_active = true
		hud.show_dialogue(speaker, text)

func _pay(amount: int, what: String, image := "") -> void:
	GameState.cash += amount
	GameState.cash_changed.emit(GameState.cash)
	SFX.play("cash", -6.0, 1.0)
	GameState.log_event("%s. $%d, honest." % [what, amount], image)

# --- The dock ---------------------------------------------------------------

func _on_dock_ask(_zone: Area3D, _player: Node) -> void:
	if job.get("kind", "") == "dock":
		_say("\"Truck's right there. Boxes go on the pallet.\" (%d to go)" % job["left"], "Driver")
		return
	if not GameState.daily_available("dock_job"):
		_say("\"You already did today's. Come back tomorrow, early.\"", "Driver")
		return
	GameState.daily_available("dock_job", true)
	job = {"kind": "dock", "left": DOCK_BOXES, "holding": false}
	_say("He looks you over. \"You want twelve bucks? Five boxes, truck to pallet. Don't drop the eggs.\"", "Driver")

func _on_dock_truck(_zone: Area3D, player: Node) -> void:
	if job.get("kind", "") != "dock" or job["holding"]:
		return
	job["holding"] = true
	SFX.play("steal", -4.0, 0.8)
	_set_box(player, true)

func _on_dock_pallet(_zone: Area3D, player: Node) -> void:
	if job.get("kind", "") != "dock" or not job["holding"]:
		return
	job["holding"] = false
	job["left"] -= 1
	SFX.play("door", -10.0, 1.3)
	_set_box(player, false)
	if job["left"] <= 0:
		job = {}
		GameState.advance_clock(DOCK_MINUTES)
		_pay(DOCK_PAY, "Unloaded a truck behind the supermarket", "job_dock")
		_say("Your arms are shaking by the last one. He counts twelve dollars into your hand without looking up. \"Same time tomorrow, if you're awake.\"", "Driver")

func _set_box(player: Node, on: bool) -> void:
	var old := player.get_node_or_null("CarriedBox")
	if old:
		old.queue_free()
	if on:
		var box := MeshInstance3D.new()
		box.name = "CarriedBox"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.35, 0.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.48, 0.3)
		mat.roughness = 0.9
		mesh.material = mat
		box.mesh = mesh
		box.position = Vector3(0, 1.15, 0.35)
		player.add_child(box)

# --- Flyers -----------------------------------------------------------------

func _on_board(_zone: Area3D, player: Node) -> void:
	if job.get("kind", "") == "flyers":
		_say("A stack of laundromat flyers in your pocket, %d to go. The spots are marked on the block." % job["left"].size())
		return
	if not GameState.daily_available("flyer_job"):
		_say("The noticeboard: AA Tuesdays, a lost cat, a flyer job with today's already crossed off. Tomorrow.")
		return
	player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if i == 0:
			GameState.daily_available("flyer_job", true)
			var spots: Array = FLYER_SPOTS.duplicate()
			spots.shuffle()
			job = {"kind": "flyers", "left": spots.slice(0, FLYERS)}
			_say("You take the stack. \"Five up on the block, where it's marked,\" the note says, \"and the laundromat pays eight.\""))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Noticeboard", "Pinned between an AA schedule and a lost cat: HELP WANTED -- put up 5 flyers on the block, $8, ask at the desk. A stack of them in a tray underneath.", ["Take the flyers"])

func _flyer_spot(room: Node3D, x: float) -> void:
	var zone := _zone(room, "FlyerSpot%d" % int(x * 10), Vector3(x, 0, -4.1), _on_flyer_spot, true)
	zone.set_meta("x", x)

func _on_flyer_spot(zone: Area3D, _player: Node) -> void:
	if job.get("kind", "") != "flyers":
		return
	job["left"].erase(zone.get_meta("x"))
	SFX.play("steal", -6.0, 1.3)
	zone.queue_free()
	if job["left"].is_empty():
		job = {}
		_pay(FLYER_PAY, "Put flyers up along the block")
		_say("Last one up. On the way past the laundromat, the woman at the counter hands you eight dollars and a free wash you'll never use.")
	else:
		_say("Flyer up. %d to go." % job["left"].size())

# --- Bottles ------------------------------------------------------------------

func _scatter_bottles(room: Node3D) -> void:
	if bottle_day != GameState.day:
		bottle_day = GameState.day
		bottle_spots.clear()
		for i in BOTTLES_PER_DAY:
			bottle_spots.append(randf_range(-27.0, 27.0))
	for x in bottle_spots:
		var zone := _zone(room, "Bottle%d" % int(x * 100), Vector3(x, 0, -1.8), _on_bottle)
		zone.set_meta("x", x)
		var mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.05
		cyl.height = 0.25
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.45, 0.25, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		cyl.material = mat
		mesh.mesh = cyl
		mesh.rotation_degrees = Vector3(0, randf() * 360.0, 90)
		mesh.position = Vector3(0, 0.05, 0)
		zone.add_child(mesh)

func _on_bottle(zone: Area3D, _player: Node) -> void:
	bottles += 1
	bottle_spots.erase(zone.get_meta("x"))
	SFX.play("steal", -10.0, 1.6)
	zone.queue_free()
	_say("A bottle out of the gutter. %d in your pockets; the machine at the supermarket takes them." % bottles)

func _on_machine(_zone: Area3D, _player: Node) -> void:
	if bottles < BOTTLES_PER_DOLLAR:
		_say("The bottle machine hums. It pays a dollar for every %d. You've got %d." % [BOTTLES_PER_DOLLAR, bottles])
		return
	var dollars := bottles / BOTTLES_PER_DOLLAR
	bottles -= dollars * BOTTLES_PER_DOLLAR
	_pay(dollars, "Returned bottles")
	_say("Clunk, clunk, clunk. The machine spits out a slip; the cashier swaps it for $%d without a word." % dollars)
