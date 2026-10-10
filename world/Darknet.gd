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
	_vendor_hourly()

# --- Your own shop ---------------------------------------------------------------
#
# GameState.vendor: {"stock", "sold", "earned", "heat", "incoming_day",
# "incoming_fate", "sale_day"}. Buy a wholesale lot; it comes the next
# morning; every morning a few units sell. Every sale is a trail in the
# coin, and heat * RAID_SCALE is the chance each day that someone follows it.

const WHOLESALE_PRICE := 80
const WHOLESALE_UNITS := 10
const UNIT_PRICE := 14
const SALES_PER_DAY := Vector2i(2, 4)
const HEAT_PER_UNIT := 0.04
const RAID_SCALE := 0.35
const WHOLESALE_SEIZE := 0.1
const SALE_HOUR := 9

static func vendor_order(fate := "") -> bool:
	var v: Dictionary = GameState.vendor
	if int(v.get("incoming_day", -1)) >= 0 or not GameState.spend_cash(WHOLESALE_PRICE):
		return false
	if fate == "":
		fate = "seized" if randf() < WHOLESALE_SEIZE else "ok"
	v["incoming_day"] = GameState.day + 1
	v["incoming_fate"] = fate
	GameState.vendor = v
	GameState.log_event("Bought a wholesale lot to sell on Silk Lane. $%d." % WHOLESALE_PRICE)
	return true

static func _vendor_hourly() -> void:
	var v: Dictionary = GameState.vendor
	if v.is_empty():
		return
	var d := GameState.day
	var h := GameState.hour()
	var due := int(v.get("incoming_day", -1))
	if due >= 0 and (d > due or (d == due and h >= SALE_HOUR)):
		v["incoming_day"] = -1
		if v.get("incoming_fate", "ok") == "seized":
			GameState._issue_warrant("The wholesale lot was opened at the sorting office.")
		else:
			v["stock"] = int(v.get("stock", 0)) + WHOLESALE_UNITS
			GameState.log_event("The lot came in. %d listed on Silk Lane." % int(v["stock"]))
	if h >= SALE_HOUR and int(v.get("sale_day", -1)) != d:
		v["sale_day"] = d
		var stock := int(v.get("stock", 0))
		if stock > 0:
			var n := mini(stock, randi_range(SALES_PER_DAY.x, SALES_PER_DAY.y))
			v["stock"] = stock - n
			v["sold"] = int(v.get("sold", 0)) + n
			if v["sold"] >= 10:
				MetaProgress.unlock("vendor")
			v["earned"] = int(v.get("earned", 0)) + n * UNIT_PRICE
			v["heat"] = float(v.get("heat", 0.0)) + n * HEAT_PER_UNIT
			GameState.cash += n * UNIT_PRICE
			GameState.cash_earned += n * UNIT_PRICE
			GameState.cash_changed.emit(GameState.cash)
			GameState.log_event("Shipped %d off Silk Lane overnight. $%d in coin." % [n, n * UNIT_PRICE])
			raid_check()
		else:
			v["heat"] = float(v.get("heat", 0.0)) * 0.7
	GameState.vendor = v

## Did someone follow the coin? `chance` overrides the heat (the smoke test).
static func raid_check(chance := -1.0) -> bool:
	var v: Dictionary = GameState.vendor
	var p: float = chance if chance >= 0.0 else float(v.get("heat", 0.0)) * RAID_SCALE
	if randf() >= p:
		return false
	v["stock"] = 0
	v["heat"] = 0.0
	v["incoming_day"] = -1
	GameState.vendor = v
	GameState._issue_warrant("They traced the coin back to your shop.")
	return true

static func vendor_text() -> String:
	var v: Dictionary = GameState.vendor
	var text := "Your shop: %d listed, %d sold, $%d earned." % [int(v.get("stock", 0)), int(v.get("sold", 0)), int(v.get("earned", 0))]
	if int(v.get("incoming_day", -1)) >= 0:
		text += " A lot's on its way."
	var heat := float(v.get("heat", 0.0))
	if heat > 0.3:
		text += " Someone left a one-star review: 'cop?'"
	return text

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
	# Poly Haven's classic laptop (CC0), open on the crate, screen to the couch.
	var model: Node3D = load("res://assets/polyhaven/classic_laptop/classic_laptop.gltf").instantiate()
	model.name = "Model"
	laptop.add_child(model)
	model.position = Vector3(0, 0.42, 0)
	model.scale = Vector3.ONE * 0.6
	model.rotation_degrees.y = -90.0
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
	var ids: Array = [] if not GameState.parcel.is_empty() else LISTED + ["strips"]
	var options := []
	var disabled := []
	for i in ids.size():
		var id: String = ids[i]
		options.append("%s  --  $%d" % [name_for(id), price(id)])
		if GameState.cash < price(id):
			disabled.append(i)
	options.append("Your vendor page (sell your own)")
	var text := (status + "\n\n" if status != "" else "") + "The neighbour's wifi, a browser that takes a minute to load anything. Prices in coin, shown in dollars. Pay now, it comes tomorrow morning. You have $%d." % GameState.cash
	player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	player.get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if i >= ids.size():
			_vendor_page(player)
		else:
			_confirm(player, ids[i]))
	menu.cancelled.connect(func(): _done(player))
	menu.open(SITE, text, options, disabled)

static func _vendor_page(player: Node) -> void:
	var menu: CanvasLayer = ChoiceMenu.new()
	player.get_tree().root.add_child(menu)
	var disabled := [] if GameState.cash >= WHOLESALE_PRICE and int(GameState.vendor.get("incoming_day", -1)) < 0 else [0]
	menu.chosen.connect(func(_i: int):
		if vendor_order():
			SFX.play("cash", -8.0, 1.2)
			_say(player, SITE, "A wholesale lot, ten units, $%d. It comes tomorrow morning. Then you're a vendor." % WHOLESALE_PRICE)
		else:
			_done(player))
	menu.cancelled.connect(func(): _done(player))
	menu.open(SITE, vendor_text() + "\n\nBuy wholesale, list it, ship it from your kitchen. Every sale is a trail in the coin.", ["Buy a wholesale lot -- $%d (%d units)" % [WHOLESALE_PRICE, WHOLESALE_UNITS]], disabled)

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
			if p["drug"] == "fentanyl" or p["contaminated"]:
				MetaProgress.unlock("tested")
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
