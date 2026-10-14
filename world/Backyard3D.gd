extends "res://world/Store3D.gd"
## The lot behind the block, through the gate by the police station end.
## Nobody's in charge back here, which cuts both ways:
##
## - Mornings (DELIVERY_HOURS) a supermarket delivery sits on the loading
##   dock with only the driver keeping half an eye on it -- it's a Store3D
##   so the pallet's goods steal and get spotted like any shelf's.
## - The dumpster: dig through it once a day for whatever got thrown out.
## - Behind the dumpster: somewhere to crouch out of sight. Police lose you
##   if they can't see you, and back here they can't.
## - The old mattress under the tarp: a night's sleep, if you don't mind
##   waking up to your pockets turned out.

const DELIVERY_HOURS := [6, 10]
const DUMPSTER_FOOD_CHANCE := 0.6
const DUMPSTER_FOOD := 25.0
const DUMPSTER_CASH_CHANCE := 0.4
const DUMPSTER_ITEM_CHANCE := 0.3
## Things people actually throw out that are still worth something.
const DUMPSTER_FINDS := ["batteries", "charger", "energy", "sunglasses", "cheese"]
const ROUGH_SLEEP_ROB_CHANCE := 0.35

func _ready() -> void:
	# No delivery outside the morning: take the pallet, its goods, and the
	# driver out before Store3D goes looking for fixtures and guards.
	if not GameState.hours_contain(DELIVERY_HOURS, GameState.hour()) or not Headlines.delivery_today():
		for n in ["Fixture1", "Item1", "Fixture2", "Item2", "Driver", "DeliveryTruck"]:
			var node := get_node_or_null(n)
			if node:
				remove_child(node)
				node.queue_free()
	super._ready()
	var life: Node3D = preload("res://world/StreetLife.gd").new()
	life.traffic = false
	add_child(life)
	for zone in find_children("*", "Area3D", true, false):
		if zone.has_signal("interacted"):
			zone.interacted.connect(interact_zone)
		if zone.name == "HideSpot":
			zone.add_to_group("hide_spots")
	_build_camp()

func interact_zone(zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	match zone.name:
		"CampZone":
			open_camp_menu(player)
		"Dumpster":
			player.dialogue_active = true
			_dumpster(hud)
		"HideSpot":
			player.set_hiding(not player.hiding)
			if player.hiding:
				SFX.play("steal", -8.0, 0.8)
		"Mattress":
			player.dialogue_active = true
			_rough_sleep(hud)

func _dumpster(hud: Node) -> void:
	if not GameState.daily_available("dumpster", true):
		hud.show_dialogue("", "You've already been through it today. Wet cardboard and coffee grounds.")
		return
	SFX.play("steal", -4.0, 0.7)
	var roll := randf()
	if roll < DUMPSTER_CASH_CHANCE:
		var amount := randi_range(1, 4)
		GameState.cash += amount
		GameState.cash_changed.emit(GameState.cash)
		hud.show_dialogue("", "Elbow-deep in garbage bags, your fingers close on a crumpled bill. $%d." % amount)
	elif roll < DUMPSTER_CASH_CHANCE + DUMPSTER_ITEM_CHANCE:
		var id: String = DUMPSTER_FINDS.pick_random()
		GameState.steal_item(id)
		hud.show_dialogue("", "Under a split bag: %s, barely used. Somebody'll pay for that." % GameState.item_name_for(id))
	elif randf() < DUMPSTER_FOOD_CHANCE:
		# Hungry enough, this is dinner (autoload/Survival.gd).
		Survival.eat(DUMPSTER_FOOD)
		hud.show_dialogue("", ["Half a sandwich, still in its wrapper. You eat it over the bin.", "A box of cold fries somebody barely touched. You don't think about it.", "Day-old bagels from the café out back. Hard, but food."].pick_random())
	else:
		hud.show_dialogue("", "Nothing. Rotten lettuce, broken glass, a smell that follows you out.")

func _rough_sleep(hud: Node) -> void:
	if GameState.wanted:
		hud.show_dialogue("", "Not now. Not with sirens going.")
		return
	if GameState.hour() >= 9.0 and GameState.hour() < 19.0:
		hud.show_dialogue("", "In broad daylight, in the delivery lot? Somebody'd call it in.")
		return
	if not Headlines.can_sleep_rough():
		hud.show_dialogue("", "The mattress is gone -- slashed and tossed in the dumpster. There's a sweep on. Not here, not tonight.")
		return
	SFX.play("sleep")
	var robbed := ""
	var rob := ROUGH_SLEEP_ROB_CHANCE * (Camp.LEANTO_ROB if Camp.has("leanto") else 1.0)
	if GameState.cash > 0 and randf() < rob:
		var taken := GameState.cash
		GameState.cash = 0
		GameState.cash_changed.emit(0)
		robbed = " Your pockets are inside out. All $%d, gone." % taken
	GameState.sleep()
	hud.show_dialogue("", "Cold comes up through the mattress all night. You wake up stiff, damp, on day %d, %s.%s" % [GameState.day, GameState.clock_text(), robbed])

# --- Your camp (autoload/Camp.gd) ---------------------------------------------

const CAMP_POS := Vector3(-3.7, 0.0, 3.2)
const InteractableScript := preload("res://interactables/Interactable3D.gd")
var _camp_root: Node3D
var _fire_light: OmniLight3D
var _flame: MeshInstance3D

func _build_camp() -> void:
	var zone := Area3D.new()
	zone.name = "CampZone"
	zone.set_meta("prompt", "Your camp")
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	add_child(zone)
	zone.position = CAMP_POS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.4, 1.6)
	shape.shape = box
	shape.position = Vector3(0, 0.7, 0)
	zone.add_child(shape)
	zone.interacted.connect(interact_zone)
	Camp.changed.connect(_refresh_camp)
	_refresh_camp()

## The camp as built: a drum with a fire in it, a tarp over the mattress,
## a box behind the dumpster.
func _refresh_camp() -> void:
	if not is_inside_tree():
		return
	if _camp_root:
		_camp_root.queue_free()
	_camp_root = Node3D.new()
	_camp_root.name = "Camp"
	add_child(_camp_root)
	_fire_light = null
	_flame = null
	if Camp.has("fire"):
		var drum := _cyl(_camp_root, 0.28, 0.85, CAMP_POS + Vector3(0.4, 0.425, 0.0), Color(0.25, 0.14, 0.08), 0.85)
		drum.name = "FireBarrel"
		if Camp.fire_lit():
			_flame = _cyl(_camp_root, 0.2, 0.35, CAMP_POS + Vector3(0.4, 0.95, 0.0), Color(1.0, 0.5, 0.1), 0.6, 4.0)
			_fire_light = OmniLight3D.new()
			_fire_light.light_color = Color(1.0, 0.55, 0.2)
			_fire_light.light_energy = 2.2
			_fire_light.omni_range = 5.0
			_camp_root.add_child(_fire_light)
			_fire_light.position = CAMP_POS + Vector3(0.4, 1.3, 0.0)
	if Camp.has("leanto"):
		var tarp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 0.03, 1.6)
		tarp.mesh = bm
		tarp.material_override = _camp_mat(Color(0.2, 0.3, 0.45), 0.9)
		_camp_root.add_child(tarp)
		tarp.position = Vector3(-5.6, 1.15, 3.6)
		tarp.rotation_degrees.x = -18.0
		for x in [-6.6, -4.6]:
			_cyl(_camp_root, 0.03, 1.4, Vector3(x, 0.7, 2.95), Color(0.4, 0.4, 0.42), 0.5)
	if Camp.has("stash"):
		var crate := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.55, 0.4, 0.4)
		crate.mesh = cb
		crate.material_override = _camp_mat(Color(0.35, 0.25, 0.15), 0.9)
		_camp_root.add_child(crate)
		crate.position = Vector3(-3.4, 0.2, -3.9)

func _process(delta: float) -> void:
	super._process(delta)
	if _fire_light:
		_fire_light.light_energy = 2.0 + sin(Time.get_ticks_msec() * 0.013) * 0.35 + sin(Time.get_ticks_msec() * 0.031) * 0.2
		if not Camp.fire_lit():
			_refresh_camp()

func open_camp_menu(player: Node) -> CanvasLayer:
	player.dialogue_active = true
	var actions := []
	var options := []
	var disabled := []
	for i in Camp.BUILDS.size():
		var b: Dictionary = Camp.BUILDS[i]
		if Camp.has(b["id"]):
			continue
		var parts := []
		for id in b["needs"]:
			parts.append("%d %s" % [b["needs"][id], id])
		options.append("Build: %s  (%s)" % [b["label"], ", ".join(parts)])
		if not Camp.can_build(i):
			disabled.append(options.size() - 1)
		actions.append(func(): Camp.build(i))
	if Camp.has("fire"):
		if Camp.fire_lit():
			options.append("The fire's going (%.1f h left)" % ((Camp.fire_until - GameState.now_minutes()) / 60.0))
			disabled.append(options.size() - 1)
			actions.append(func(): pass)
		else:
			options.append("Light the fire  (1 rags)")
			if not GameState.inventory.has("rags"):
				disabled.append(options.size() - 1)
			actions.append(func(): Camp.light_fire())
	if Camp.has("stash"):
		options.append("Stash everything you're carrying (%d)" % GameState.inventory.size())
		if GameState.inventory.is_empty():
			disabled.append(options.size() - 1)
		actions.append(func():
			for id in GameState.inventory.duplicate():
				Camp.put(id))
		options.append("Take everything from the stash (%d)" % Camp.stash.size())
		if Camp.stash.is_empty():
			disabled.append(options.size() - 1)
		actions.append(func():
			for id in Camp.stash.duplicate():
				Camp.take(id))
	var menu: CanvasLayer = preload("res://ui/ChoiceMenu.gd").new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		player.dialogue_active = false
		actions[i].call())
	menu.cancelled.connect(func(): player.dialogue_active = false)
	var status := "Your corner of the lot."
	if Camp.built.is_empty():
		status = "A corner of the lot nobody uses. Scrap, rags and tape could make it yours."
	menu.open("Your camp", status, options, disabled)
	return menu

func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, col: Color, rough: float, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = _camp_mat(col, rough, emit)
	parent.add_child(mi)
	mi.position = pos
	return mi

func _camp_mat(col: Color, rough: float, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m
