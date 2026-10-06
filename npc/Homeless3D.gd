extends "res://npc/NPC3D.gd"
## Ray: sits out on the sidewalk by the alley with everything he owns in a
## shopping cart, and sees everything that happens on the block.
##
## Give him something -- a couple of dollars, or something you lifted -- and
## he's on your side: he'll tell you what he's seen (who's working where,
## when the pusher's out, who's been asking about you), and when the cops
## come running past he'll point them the wrong way. Never give him
## anything, and when a cop asks, he'll point right at you.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
## How close a chase has to come for him to get involved.
const SHOUT_RANGE := 8.0
const GIFT_CASH := 2

var _shouted_this_chase: bool = false
var _bubble: Label3D

func _ready() -> void:
	fences_items = false
	super._ready()
	set_pose("sit")
	GameState.wanted_changed.connect(_on_wanted_changed)

func _process(delta: float) -> void:
	super._process(delta)
	_watch_chase()

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("blip")
	var greeting := "\"Hey, friend.\" He shifts on his cardboard." if GameState.homeless_trust > 0 else "He looks up from under his hood. \"Spare anything? Anything at all.\""
	var options := ["Give him $%d" % GIFT_CASH, "Give him something you're carrying", "Ask what he's seen"]
	var disabled := []
	if GameState.cash < GIFT_CASH:
		disabled.append(0)
	if GameState.inventory.is_empty():
		disabled.append(1)
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _on_choice(i, player, hud))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open(npc_name, greeting, options, disabled)

func _on_choice(i: int, player: Node, hud: Node) -> void:
	player.dialogue_active = true
	match i:
		0:
			GameState.spend_cash(GIFT_CASH)
			GameState.homeless_trust += 1
			SFX.play("cash", -10.0, 1.1)
			hud.show_dialogue(npc_name, "\"God bless.\" It goes into a coffee cup with a few coins. \"I see you, friend. I see you.\"")
		1:
			# You choose: with your mother's ring in your pocket, "something
			# you're carrying" shouldn't mean whatever came first.
			var items: Array = GameState.inventory.duplicate()
			var menu: CanvasLayer = ChoiceMenu.new()
			get_tree().root.add_child(menu)
			menu.chosen.connect(func(k: int): _give(items[k], hud))
			menu.cancelled.connect(func(): player.dialogue_active = false)
			menu.open(npc_name, "\"What've you got?\"", items.map(func(id): return GameState.item_name_for(id)))
		2:
			hud.show_dialogue(npc_name, _tip())

func _give(item: String, hud: Node) -> void:
	if not GameState.inventory.has(item):
		return
	GameState.inventory.erase(item)
	GameState.inventory_changed.emit()
	GameState.homeless_trust += 2
	hud.show_dialogue(npc_name, "He turns %s over in his hands. \"I can move that.\" It disappears into the cart. \"You're all right.\"" % GameState.item_name_for(item))

## What he's noticed. Worth something only once he trusts you.
func _tip() -> String:
	if GameState.homeless_trust <= 0:
		return ["\"I ain't seen nothing.\" He looks away.", "\"Seeing's worth something, friend. Nothing's free.\"", "\"Mind your business, I'll mind mine.\""].pick_random()
	if GameState.debt > 0:
		return "\"Big fella in a black jacket was asking after you. Asked nice, if you know what I mean. You square with the man?\""
	if not GameState.pusher_on_shift():
		return "\"Your guy? Not till four. He don't do mornings. Nobody sells in the mornings, too many eyes.\""
	var h := GameState.hour()
	var tips := [
		"\"Cop walks the block now and then. Slow, looks at everybody. Don't be carrying when he goes by, and don't run.\"",
		"\"Night clerk at the 24-hour's half asleep after ten. Day guy's another story.\"",
		"\"Liquor store's got a mirror in the corner. Old man sees everything in that mirror.\"",
	]
	if h >= 11.0 and h < 19.0:
		tips.append("\"Supermarket's got a kid stocking back by the coolers till about seven. After that nobody watches the meat.\"")
	if h >= 12.0 and h < 18.0:
		tips.append("\"Electronics has an extra girl on the floor this time of day. Wait till after six.\"")
	if h >= 10.0 and h < 18.0:
		tips.append("\"Pharmacy's got a helper on the floor till six. Just the old man in back after that.\"")
	return tips.pick_random()

func _on_wanted_changed(is_wanted: bool) -> void:
	if not is_wanted:
		_shouted_this_chase = false

## A chase comes past him. He picks a side.
func _watch_chase() -> void:
	if _shouted_this_chase or not GameState.wanted:
		return
	var police := get_tree().get_first_node_in_group("police") as Node3D
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if police == null or player == null:
		return
	if global_position.distance_to(player.global_position) > SHOUT_RANGE or global_position.distance_to(police.global_position) > SHOUT_RANGE + 4.0:
		return
	_shouted_this_chase = true
	_speak()
	if GameState.homeless_trust > 0:
		_shout("\"He went down the alley! That way!\"")
		# The officer loses a few seconds on the wrong trail -- often enough
		# to break line of sight and get away.
		police.set("_lose_timer", police.LOSE_SIGHT_TIME * 0.6)
		var target := police.get_node_or_null("NavAgent") as NavigationAgent3D
		if target:
			target.target_position = Vector3(21.0, 0, -3.8)
			police.set("_retarget_timer", 2.5)
	else:
		_shout("\"Right there! He's right there!\"")
		police.set("_lose_timer", -3.0)

func _shout(text: String) -> void:
	Voice.say(npc_name, text)
	if _bubble and is_instance_valid(_bubble):
		_bubble.queue_free()
	_bubble = Label3D.new()
	_bubble.text = text
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 40
	_bubble.pixel_size = 0.006
	_bubble.outline_size = 10
	_bubble.modulate = Color(1.0, 0.95, 0.8)
	_bubble.no_depth_test = true
	_bubble.position = Vector3(0, 2.2, 0)
	add_child(_bubble)
	var tween := _bubble.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(_bubble, "modulate:a", 0.0, 0.6)
	tween.tween_callback(_bubble.queue_free)
