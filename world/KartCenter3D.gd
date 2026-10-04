extends "res://world/WorldRoot3D.gd"
## Southside Speedway's front office. The marshal at the desk sells a ride:
## $5 for three laps against the Dive Bar regulars (ui/KartRace.gd). The
## day's first race pays the podium; after that it's for the board. Open
## afternoons until midnight (GameState.OPENING_HOURS), floodlit at night.
##
## And the hustle around it:
## - Big Eddie (npc/KartHustler3D.gd) pays $30 if you throw the race:
##   fourth or worse, close enough to the kart ahead that it looks real.
## - When the pusher's on shift his runner's in the stands taking bets:
##   $10 on yourself pays $25 for a podium.
## - The spare-parts box behind the desk has a carburetor in it worth $30
##   at the pawnshop. Lift it and the track's shut tomorrow (Headlines);
##   get seen and the marshal throws you out for the day.

const KartRace := preload("res://ui/KartRace.gd")
const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const NPCScene := preload("res://npc/NPC3D.tscn")
const InteractableScript := preload("res://interactables/Interactable3D.gd")
const RIDE_PRICE := 5
const BET_STAKE := 10
const BET_PAYS := 25
const PARTS_SEEN_CHANCE := 0.35
## Per visit, so a test can make her look (1.0) or not (0.0).
var parts_seen_chance: float = PARTS_SEEN_CHANCE

const EDDIE_PAY := 30

func _ready() -> void:
	super._ready()
	var desk := find_child("KartDesk", true, false)
	if desk:
		desk.interacted.connect(_on_desk)
	_add_eddie()
	_add_parts_box()

func _add_eddie() -> void:
	# He won't come near you if you've burned him.
	if GameState.rep_of("Big Eddie") < -1:
		return
	var eddie := NPCScene.instantiate()
	eddie.set_script(preload("res://npc/KartHustler3D.gd"))
	eddie.name = "BigEddie"
	eddie.set("npc_name", "Big Eddie")
	eddie.set("role", "Big Eddie")
	eddie.set("fences_items", false)
	add_child(eddie)
	eddie.global_position = Vector3(-4.6, 0, -0.6)
	(eddie.get_node("ModelRoot") as Node3D).rotation_degrees.y = 60.0

func _add_parts_box() -> void:
	var zone := Area3D.new()
	zone.name = "PartsBox"
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	add_child(zone)
	zone.global_position = Vector3(3.3, 0, -2.6)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.2, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	zone.add_child(shape)
	var crate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.45, 0.5)
	crate.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.3, 0.38)
	m.roughness = 0.6
	crate.material_override = m
	zone.add_child(crate)
	crate.position = Vector3(0, 0.23, -0.3)
	var label := Label3D.new()
	label.text = "SPARES"
	label.font_size = 28
	label.pixel_size = 0.005
	label.modulate = Color(0.9, 0.9, 0.85)
	zone.add_child(label)
	label.position = Vector3(0, 0.3, -0.04)
	zone.interacted.connect(_on_parts)

## Eddie's deal lives in GameState.daily_used so it survives walking out
## and back in (and a save): taken today and not yet raced.
func throw_deal_active() -> bool:
	return int(GameState.daily_used.get("kart_throw_active", -1)) == GameState.day

func accept_throw(_who: String, _pay: int) -> void:
	GameState.daily_available("kart_throw", true)
	GameState.daily_used["kart_throw_active"] = GameState.day

func _on_desk(_zone: Area3D, player: Node) -> void:
	player.dialogue_active = true
	if not GameState.daily_available("kart_banned"):
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_dialogue("Marshal", "\"Nope. Not after what you did with my spares. Out.\"")
		return
	var mult := Headlines.kart_prize_mult()
	var prizes: Array = KartRace.PRIZES.map(func(p): return p * mult)
	var prize := "Podium pays $%d / $%d / $%d -- first race of the day only." % prizes
	if mult > 1:
		prize = "It's Cup night -- the podium pays $%d / $%d / $%d, first race only." % prizes
	if not GameState.daily_available(KartRace.PRIZE_DAILY_KEY):
		prize = "Today's prize pot's gone. You'd be racing for the board."
	var options := ["Race ($%d)" % RIDE_PRICE]
	var deals: Array = [{}]
	if throw_deal_active():
		options[0] = "Race ($%d) -- and finish 4th or worse for Big Eddie" % RIDE_PRICE
		deals[0] = {"kind": "throw", "by": "Big Eddie", "pay": EDDIE_PAY}
	elif GameState.pusher_on_shift():
		options.append("Race, with $%d on yourself (podium pays $%d)" % [BET_STAKE, BET_PAYS])
		deals.append({"kind": "bet", "stake": BET_STAKE, "pays": BET_PAYS})
	options.append("Not tonight")
	var disabled := []
	if GameState.cash < RIDE_PRICE:
		disabled.append(0)
	if deals.size() > 1 and GameState.cash < RIDE_PRICE + BET_STAKE:
		disabled.append(1)
	var text := "\"Three laps, five drivers, one of them's you. %s Sign the waiver.\"" % prize
	if deals.size() > 1:
		text += " A kid in the stands with the pusher's colours on is taking bets."
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if i < deals.size():
			_start_race(player, deals[i])
		else:
			player.dialogue_active = false)
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Marshal", text, options, disabled)

func _start_race(player: Node, deal: Dictionary = {}) -> void:
	var cost := RIDE_PRICE + int(deal.get("stake", 0))
	if not GameState.spend_cash(cost):
		player.dialogue_active = false
		return
	SFX.play("cash")
	player.dialogue_active = true
	if deal.get("kind", "") == "throw":
		# One race to do it in.
		GameState.daily_used["kart_throw_active"] = -1
	var race: CanvasLayer = KartRace.new()
	get_tree().root.add_child(race)
	race.start("player", deal)
	race.tree_exited.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)

## The spares box: one try a day. The marshal's at the desk with her back
## half to it; sometimes she turns round.
func _on_parts(_zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	if not GameState.daily_available("kart_parts", true):
		hud.show_dialogue("", "Gaskets, a chain, spark plugs in a coffee can. Nothing else worth the risk today.")
		return
	if randf() < parts_seen_chance:
		GameState.daily_available("kart_banned", true)
		SFX.play("latch", -2.0)
		hud.show_dialogue("Marshal", "\"HEY. Hands out of the box.\" She comes round the desk. \"Out. You don't ride here today.\"")
		GameState.log_event("Caught with a hand in the kart track's spares box. Thrown out for the day.")
		return
	SFX.play("steal", -4.0, 0.8)
	GameState.steal_item("carburetor")
	GameState.sabotage_day = GameState.day + 1
	hud.show_dialogue("", "Under the spark plugs: a carburetor in a ziplock bag, nearly new. It goes in your jacket. Somebody's kart isn't running tomorrow.")
	GameState.log_event("Lifted a carburetor from the kart track's spares.")
