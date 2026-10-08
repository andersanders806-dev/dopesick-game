extends RefCounted
## Silk Lane: the darknet market on the laptop at home. A different way to
## score with different risks -- cheaper than the corner and fewer fakes
## (vendors live on their reviews), but you pay up front, wait until the next
## morning, and not every package comes: some vendors take the money and
## vanish, and now and then the post office opens one with your name on it.
##
## The order lives in GameState.parcel (saved with the run):
##   {"asked": id, "drug": what's really in it, "contaminated": bool,
##    "day": the morning it arrives, "fate": "ok" | "scam" | "seized"}
## Everything is settled when you order; the hourly clock and the apartment
## only play it out.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")

const SITE := "SILK LANE  ·  silklane7xq...onion"
## Of the street price, plus a flat fee for the coin and the stamps.
const DISCOUNT := 0.75
const FEE := 2
## Half the street's chance of a fentanyl press: reviews keep vendors honest.
const FAKE_MULT := 0.5
const SCAM_CHANCE := 0.10
const SEIZE_CHANCE := 0.05
const ARRIVAL_HOUR := 9
## What's listed: no naloxone or strips on the street's terms, but a
## harm-reduction vendor sells strips by the five.
const LISTED := ["heroin", "oxy", "fentanyl", "clonazepam", "alprazolam", "bupe", "meth"]
const STRIPS_PRICE := 6
const LAPTOP_POS := Vector3(-3.35, 0, 0.45)
const PACKAGE_POS := Vector3(3.3, 0, -1.3)

static func price(id: String) -> int:
	if id == "strips":
		return STRIPS_PRICE
	return int(round(GameState.price_of(id) * DISCOUNT)) + FEE

static func name_for(id: String) -> String:
	return "Test strips (5)" if id == "strips" else Drugs.name_for(id)

## Pays and settles what happens to the order. `fate` is for the smoke test;
## left empty it's rolled.
static func order(id: String, fate := "") -> bool:
	if not GameState.parcel.is_empty() or not GameState.spend_cash(price(id)):
		return false
	var got := id
	var dirty := false
	if id != "strips":
		got = Drugs.resolve_purchase(id) if randf() < FAKE_MULT else id
		dirty = GameState.roll_contaminated(got)
	if fate == "":
		var r := randf()
		fate = "scam" if r < SCAM_CHANCE else ("seized" if r < SCAM_CHANCE + SEIZE_CHANCE else "ok")
	GameState.parcel = {"asked": id, "drug": got, "contaminated": dirty, "day": GameState.day + 1, "fate": fate}
	GameState.log_event("Ordered %s off Silk Lane for $%d." % [name_for(id), price(id)])
	return true

static func arrived() -> bool:
	var p: Dictionary = GameState.parcel
	return not p.is_empty() and (GameState.day > p["day"] or (GameState.day == p["day"] and GameState.hour() >= ARRIVAL_HOUR))

## Hourly (GameState): a seized package means a warrant as soon as it would
## have arrived, home or not.
static func hourly() -> void:
	if arrived() and GameState.parcel["fate"] == "seized":
		GameState.parcel = {}
		GameState._issue_warrant("The post office opened a package with your name on it.")

## What the laptop screen says before the listings, if anything -- and an
## exit scam, once seen, closes the order.
static func laptop_text() -> String:
	var p: Dictionary = GameState.parcel
	if p.is_empty():
		return ""
	if arrived() and p["fate"] == "scam":
		GameState.parcel = {}
		GameState.log_event("The Silk Lane vendor took the money and disappeared.")
		return "Your order page is a 404. The vendor's gone -- shop, reviews, all of it -- and your $%d with them." % price(p["asked"])
	if arrived():
		return "Tracking says delivered. Check inside the door."
	return "Order status: shipped. Plain envelope, no return address. Arrives tomorrow morning."

## The laptop and, when it's come, the package -- added to the apartment at
## load, so the room's scene doesn't change.
static func furnish(room: Node3D) -> void:
	var crate := MeshInstance3D.new()
	crate.name = "LaptopCrate"
	var cb := BoxMesh.new()
	cb.size = Vector3(0.5, 0.42, 0.4)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.24, 0.16)
	wood.roughness = 0.9
	cb.material = wood
	crate.mesh = cb
	room.add_child(crate)
	crate.position = LAPTOP_POS + Vector3(0, 0.21, 0)
	var laptop := _zone(room, "Laptop", LAPTOP_POS, 0.42)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.02, 0.24)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.metallic = 0.4
	dark.roughness = 0.5
	bm.material = dark
	base.mesh = bm
	laptop.add_child(base)
	base.position = Vector3(0, 0.43, 0.02)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.34, 0.22, 0.012)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.05, 0.12, 0.08)
	glow.emission_enabled = true
	glow.emission = Color(0.25, 0.85, 0.5)
	glow.emission_energy_multiplier = 1.4
	sm.material = glow
	screen.mesh = sm
	laptop.add_child(screen)
	screen.position = Vector3(0, 0.54, -0.1)
	screen.rotation_degrees.x = -15.0
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.6)
	light.light_energy = 0.35
	light.omni_range = 1.4
	laptop.add_child(light)
	light.position = Vector3(0, 0.6, 0.15)
	laptop.set_meta("prompt", "Use the laptop")
	laptop.interacted.connect(func(_z, player): open_laptop(player))
	refresh_package(room)

static func refresh_package(room: Node3D) -> void:
	var old := room.get_node_or_null("Package")
	var want: bool = arrived() and GameState.parcel.get("fate", "") == "ok"
	if old and not want:
		old.queue_free()
	if want and old == null:
		var box := _zone(room, "Package", PACKAGE_POS, 0.0)
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.3, 0.12, 0.22)
		var card := StandardMaterial3D.new()
		card.albedo_color = Color(0.55, 0.42, 0.27)
		b.material = card
		m.mesh = b
		box.add_child(m)
		m.position = Vector3(0, 0.06, 0)
		m.rotation_degrees.y = 20.0
		box.set_meta("prompt", "Open the package")
		box.interacted.connect(func(z, player): _open_with_menus(z, player))

static func _zone(room: Node3D, zname: String, pos: Vector3, lift: float) -> Area3D:
	var zone := Area3D.new()
	zone.name = zname
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	room.add_child(zone)
	zone.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.2, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.6 + lift * 0.5, 0)
	zone.add_child(shape)
	return zone

# --- The screens ------------------------------------------------------------

static func open_laptop(player: Node) -> void:
	var status := laptop_text()
	if not GameState.parcel.is_empty():
		_say(player, SITE, status)
		return
	var ids: Array = LISTED + ["strips"]
	var options := []
	var disabled := []
	for i in ids.size():
		var id: String = ids[i]
		options.append("%s  --  $%d" % [name_for(id), price(id)])
		if GameState.cash < price(id):
			disabled.append(i)
	var text := (status + "\n\n" if status != "" else "") + "The neighbour's wifi, a browser that takes a minute to load anything. Prices in coin, shown in dollars. Pay now, it comes tomorrow morning. You have $%d." % GameState.cash
	player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	player.get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _confirm(player, ids[i]))
	menu.cancelled.connect(func(): _done(player))
	menu.open(SITE, text, options, disabled)

static func _confirm(player: Node, id: String) -> void:
	var menu: CanvasLayer = ChoiceMenu.new()
	player.get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if i == 0 and order(id):
			SFX.play("cash", -8.0, 1.2)
			_say(player, SITE, "Order placed. $%d gone. Now you wait." % price(id))
		else:
			_done(player))
	menu.cancelled.connect(func(): _done(player))
	menu.open(SITE, "%s from a vendor with 4.%d stars. $%d, paid now. Plain envelope, arrives tomorrow morning -- probably." % [name_for(id), randi_range(3, 9), price(id)], ["Pay and order", "Back"])

## Opening it: the drug goes in, the strips go in your pocket. `ask` false
## skips the test-strip question (the smoke test). Returns take_drug's
## outcome, or "strips".
static func open_package(box: Node, ask := true) -> String:
	var p: Dictionary = GameState.parcel
	GameState.parcel = {}
	if is_instance_valid(box):
		box.queue_free()
	if p.get("asked", "") == "strips":
		GameState.test_strips += 5
		return "strips"
	if not ask:
		return GameState.take_drug(p["drug"], 1.0, GameState.CONTAMINATED_RISK if p["contaminated"] else 1.0)
	return ""

static func _open_with_menus(box: Node, player: Node) -> void:
	var p: Dictionary = GameState.parcel.duplicate()
	if p.is_empty():
		return
	SFX.play("steal", -6.0, 0.9)
	if p["asked"] == "strips":
		open_package(box)
		_say(player, "", "Five test strips in a ziplock, and a note: STAY SAFE <3.")
		return
	var take := func(action: String) -> void:
		GameState.parcel = {}
		if is_instance_valid(box):
			box.queue_free()
		if action == "toss":
			GameState.log_event("Tested the package, and threw it away.")
			_say(player, "", "You flush it. The envelope goes in the trash.")
			return
		var risk: float = GameState.CONTAMINATED_RISK if p["contaminated"] else 1.0
		var outcome := GameState.take_drug(p["drug"], 0.5 if action == "half" else 1.0, risk)
		SFX.play("fix")
		_say(player, "", _outcome_line(outcome))
	var strips_ok: bool = GameState.test_strips > 0 and Drugs.info(p["drug"]).get("class", "") == Drugs.OPIOID
	player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	player.get_tree().root.add_child(menu)
	if strips_ok:
		menu.chosen.connect(func(i: int):
			if i == 0:
				GameState.test_strips -= 1
				var m2: CanvasLayer = ChoiceMenu.new()
				player.get_tree().root.add_child(m2)
				m2.chosen.connect(func(j: int): take.call(["take", "half", "toss"][j]))
				m2.cancelled.connect(func(): take.call("take"))
				m2.open("", GameState.strip_reading(p["asked"], p["drug"], p["contaminated"]), ["Take it anyway", "Take a little at a time", "Throw it away"])
			elif i == 1:
				take.call("take")
			else:
				_done(player))
		menu.cancelled.connect(func(): _done(player))
		menu.open("", "A padded envelope, a vacuum-sealed bag inside a DVD case. %s, it says." % Drugs.name_for(p["asked"]), ["Test it first", "Just take it", "Not now"])
	else:
		menu.chosen.connect(func(i: int):
			if i == 0:
				take.call("take")
			else:
				_done(player))
		menu.cancelled.connect(func(): _done(player))
		menu.open("", "A padded envelope, a vacuum-sealed bag inside a DVD case. %s, it says." % Drugs.name_for(p["asked"]), ["Take it", "Not now"])

static func _outcome_line(outcome: String) -> String:
	match outcome:
		"precipitated":
			return "It goes wrong within minutes -- the sickness comes back twice as hard. Too soon after the last one."
		"overdose":
			return "It hits harder than anything ever has, and the room tips slowly on its side."
		"saved":
			return "It hits far too hard. Then grey, wrung out, and instantly sick again."
	return "Five stars, the review said. For once, a review was right."

static func _say(player: Node, who: String, text: String) -> void:
	var hud := player.get_tree().get_first_node_in_group("hud")
	if hud == null:
		_done(player)
		return
	player.dialogue_active = true
	hud.show_dialogue(who, text)

static func _done(player: Node) -> void:
	if is_instance_valid(player):
		player.dialogue_active = false
