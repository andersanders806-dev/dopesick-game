extends Area3D
## The pusher: sells you a fix in person, out on the street.
##
## Modelled on how street-level selling is described in policing and
## problem-oriented-policing guides (Police Magazine, ASU Center for
## Problem-Oriented Policing): he works a fixed, badly lit spot so buyers know
## where to find him; he doesn't carry anything on him, so a sale is cash
## first, then a walk to a stash tucked away nearby, then a quick
## hand-to-hand; he keeps checking the street; and a lookout down the block
## warns him about police, at which point he disappears around the corner
## until the heat is off.

signal sale_completed

enum State { POST, TO_STASH, AT_STASH, TO_POST, AWAIT_BUYER, HANDOFF, TO_HIDE, HIDDEN, RETURNING, OFF_SHIFT }

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const PORTRAIT := preload("res://assets/portraits/pusher.png")
const VOICES := [
	preload("res://assets/sfx/patron_mutter_a.wav"),
	preload("res://assets/sfx/patron_mutter_b.wav"),
	preload("res://assets/sfx/patron_mutter_c.wav"),
]
const VOICE_PITCH := 0.82
const WALK_SPEED := 2.2
## Close enough that he turns to size you up.
const NOTICE_RANGE := 4.0
## How close you need to be for the handoff once he's back from the stash.
const HANDOFF_RANGE := 2.2
const TURN_SPEED := 6.0
const GLANCE_ARC_DEG := 90.0
const GLANCE_SPEED := 0.45
## The beat cop coming within this range sends him down his alley; he comes
## back once the cop is past HEAT_CLEAR_RANGE.
const HEAT_RANGE := 10.0
const HEAT_CLEAR_RANGE := 14.0

const GREETINGS := ["\"You good?\"", "\"What you need?\"", "\"Keep walking unless you're buying.\""]
const WAIT_LINES := [
	"\"$%d. ...Wait here.\" He pockets your cash and walks off down the street.",
	"He takes your $%d without counting it. \"Stay put. Don't follow me.\"",
]
const DrugMenuScene := preload("res://ui/DrugMenu.gd")
## He never has everything. A nightly subset means what you can get is part
## of the problem, instead of the menu being the same every time.
## He's holding a lot now: most of the catalogue on any given night, but
## never quite all of it.
const STOCK_MIN := 12
const STOCK_MAX := 17
const HANDOFF_LINES := [
	"He brushes past you and presses it into your palm. You feel it hit.",
	"A quick handshake, and it's yours. You feel it hit.",
]

@export var street_facing_deg: float = 0.0
## Cast role (npc/CharacterCast.gd); decides the body and its colours.
@export var role: String = "pusher"
@export var model_path: String = ""
## Dark grey, like a zip-up hoodie -- and so he doesn't read as the player,
## who wears the same base model's green shirt.
@export var clothes_tint: Color = Color.WHITE
## Where he keeps the stash and where he ducks out of sight -- set by the
## room to Marker3D positions (world space).
@export var stash_position: Vector3
@export var hide_position: Vector3

@onready var model_root: Node3D = $ModelRoot
@onready var voice: AudioStreamPlayer3D = $Voice
@onready var talk_shape: CollisionShape3D = $CollisionShape3D
@onready var body_shape: CollisionShape3D = $Body/CollisionShape3D

var anim: CharacterAnimator
var state: State = State.POST
var _post_position: Vector3
var _glance_t: float = 0.0
var _timer: float = 0.0
## Paid for but not yet handed over (survives him having to hide).
var _owes_fix: bool = false
## What he asked for and what was actually pressed into his hand -- decided
## at purchase, revealed only when it hits.
var _owed_drug: String = ""
## Tonight's stock, rerolled each day.
var _stock: Array = []
var _stock_day: int = -1

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("pusher")
	var model: Node = load(model_path if model_path != "" else CharacterCast.model_for(role)).instantiate()
	model_root.add_child(model)
	CharacterCast.dress(model, role)
	CharacterLook.tint_clothes(model, clothes_tint)
	anim = CharacterAnimator.new(model)
	_post_position = global_position
	_glance_t = randf() * TAU
	GameState.wanted_changed.connect(_on_wanted_changed)
	if GameState.wanted:
		# Walked in mid-chase: he's already gone.
		global_position = hide_position
		_set_hidden(true)
		state = State.HIDDEN
	elif not GameState.pusher_on_shift():
		global_position = hide_position
		_set_hidden(true)
		state = State.OFF_SHIFT

func is_busy() -> bool:
	return state != State.POST

func _physics_process(delta: float) -> void:
	match state:
		State.POST:
			_face(_idle_facing(delta), delta)
			anim.update(0.0)
			# Knocks off at the end of his hours -- but only between sales.
			if not GameState.pusher_on_shift():
				state = State.TO_HIDE
			elif _patrol_within(HEAT_RANGE):
				state = State.TO_HIDE
		State.TO_STASH:
			if _walk_to(stash_position, delta):
				state = State.AT_STASH
				_timer = anim.play_once_timed("pick-up", 0.9) + 0.3
		State.AT_STASH:
			_timer -= delta
			if _timer <= 0.0:
				state = State.TO_POST
		State.TO_POST:
			if _walk_to(_post_position, delta):
				state = State.AWAIT_BUYER
		State.AWAIT_BUYER:
			anim.update(0.0)
			var player := _player()
			if player:
				_face(_yaw_to(player.global_position), delta)
				if _flat_dist(player.global_position) <= HANDOFF_RANGE and not player.dialogue_active:
					_handoff(player)
		State.HANDOFF:
			_timer -= delta
			if _timer <= 0.0:
				state = State.POST
		State.TO_HIDE:
			if _walk_to(hide_position, delta):
				_set_hidden(true)
				state = State.OFF_SHIFT if not GameState.pusher_on_shift() and not _owes_fix else State.HIDDEN
		State.HIDDEN:
			# Hid from the beat cop (not a chase): back once he's gone by.
			if not GameState.wanted and not _patrol_within(HEAT_CLEAR_RANGE) and (GameState.pusher_on_shift() or _owes_fix):
				_set_hidden(false)
				state = State.RETURNING
		State.OFF_SHIFT:
			if GameState.pusher_on_shift() and not GameState.wanted:
				_set_hidden(false)
				state = State.RETURNING
		State.RETURNING:
			if _walk_to(_post_position, delta):
				state = State.TO_STASH if _owes_fix else State.POST

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if state == State.AWAIT_BUYER:
		_handoff(player)
		return
	player.dialogue_active = true
	_speak()
	if GameState.wanted:
		hud.show_dialogue("Pusher", "\"You brought cops with you? Walk away. Now.\"", PORTRAIT)
		return
	if state != State.POST:
		hud.show_dialogue("Pusher", "\"I said wait.\"", PORTRAIT)
		return
	# Late: he takes what you've got before anything else, and sells you
	# nothing more until you're square.
	if GameState.debt_overdue():
		var taken := GameState.pay_debt(GameState.cash)
		if taken > 0:
			SFX.play("cash", -6.0, 0.8)
		if GameState.debt > 0:
			hud.show_dialogue("Pusher", "He holds his hand out before you've said a word. %s \"You still owe me $%d. Nothing till I'm paid -- and my man's looking for you.\"" % [("He takes your $%d." % taken) if taken > 0 else "Your pockets are empty.", GameState.debt], PORTRAIT)
		else:
			hud.show_dialogue("Pusher", "He counts it twice. \"Late. Don't make me send somebody. We're square.\"", PORTRAIT)
		return
	var cheapest := GameState.cheapest_opioid_cost()
	if GameState.cash < min(cheapest, GameState.price_of("clonazepam")) and not GameState.can_front(cheapest):
		hud.show_dialogue("Pusher", "%s \"Cheapest thing I've got is $%d. Come back when you've got it.\"" % [GREETINGS.pick_random(), cheapest], PORTRAIT)
		return
	_open_menu(player)

## Shows what he's holding tonight and waits for a pick.
func _open_menu(player: Node) -> void:
	player.dialogue_active = true
	var menu: CanvasLayer = DrugMenuScene.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(id: String): _buy(player, id))
	menu.fronted.connect(func(id: String): _buy(player, id, true))
	menu.paid_back.connect(func(amount: int): _pay_back(player, amount))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open_with(_todays_stock())

## Rerolled once a day. Naloxone is always available -- he'd rather his
## buyers didn't die, and dealers carrying it is increasingly normal.
func _todays_stock() -> Array:
	if _stock_day == GameState.day and not _stock.is_empty():
		return _stock
	var pool: Array = Drugs.CATALOGUE.filter(func(d): return d["class"] != Drugs.RESCUE).map(func(d): return d["id"])
	pool.shuffle()
	_stock = pool.slice(0, randi_range(STOCK_MIN, STOCK_MAX))
	_stock.append("naloxone")
	_stock_day = GameState.day
	return _stock

func _buy(player: Node, drug_id: String, on_credit := false) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var cost := GameState.price_of(drug_id)
	if on_credit:
		if not GameState.can_front(cost):
			player.dialogue_active = false
			return
		GameState.take_front(cost)
		_owed_drug = Drugs.resolve_purchase(drug_id)
		_owes_fix = true
		if hud:
			player.dialogue_active = true
			hud.show_dialogue("Pusher", "He looks you over for a long second. \"$%d. By this time tomorrow. I know where you sleep.\" He walks off down the street." % GameState.debt, PORTRAIT)
		state = State.TO_STASH
		return
	if not GameState.spend_cash(cost):
		player.dialogue_active = false
		return
	# What he actually hands over is settled now, not when it hits you.
	_owed_drug = Drugs.resolve_purchase(drug_id)
	_owes_fix = true
	SFX.play("cash", -6.0, 0.8)
	if hud:
		player.dialogue_active = true
		hud.show_dialogue("Pusher", WAIT_LINES.pick_random() % cost, PORTRAIT)
	state = State.TO_STASH

func _pay_back(player: Node, amount: int) -> void:
	var paid := GameState.pay_debt(amount)
	SFX.play("cash", -6.0, 0.8)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		player.dialogue_active = true
		if GameState.debt == 0:
			hud.show_dialogue("Pusher", "He counts your $%d and it disappears. \"We're good.\"" % paid, PORTRAIT)
		else:
			hud.show_dialogue("Pusher", "He pockets your $%d. \"That's a start. $%d to go.\"" % [paid, GameState.debt], PORTRAIT)

func _handoff(player: Node) -> void:
	state = State.HANDOFF
	_timer = anim.play_once_timed("interact", 0.8)
	_speak()
	_owes_fix = false
	SFX.play("fix")
	var drug := _owed_drug if _owed_drug != "" else "heroin"
	_owed_drug = ""
	var outcome := GameState.take_drug(drug)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		player.dialogue_active = true
		hud.show_dialogue("Pusher", _handoff_line(drug, outcome), PORTRAIT)
	sale_completed.emit()

## Naloxone is bought, not taken, so it never "hits". Everything else gets
## narrated by what it did to you -- which is the only way you find out the
## blue you paid $30 for was a fentanyl press.
func _handoff_line(drug: String, outcome: String) -> String:
	if Drugs.info(drug).get("class", "") == Drugs.RESCUE:
		return "A quick handshake. \"Keep it on you. Seriously.\""
	match outcome:
		"precipitated":
			return "A quick handshake, and it's yours. It goes wrong within minutes -- the sickness comes back twice as hard, sweating and cramping. Too soon after the last one."
		"overdose":
			return "A quick handshake, and it's yours. It hits harder than anything ever has, and the street tilts away from you."
		"saved":
			return "It hits far too hard. Somebody gets the naloxone into you and the world comes back grey, wrung out, and instantly sick again."
		_:
			return HANDOFF_LINES.pick_random()

## The lookout's whistle: clear out, or come back once it's quiet. A sale
## that's already paid for is still owed -- he picks up where he left off.
func _on_wanted_changed(is_wanted: bool) -> void:
	if is_wanted:
		if state not in [State.TO_HIDE, State.HIDDEN, State.OFF_SHIFT]:
			state = State.TO_HIDE
	elif state in [State.HIDDEN, State.TO_HIDE]:
		if GameState.pusher_on_shift() or _owes_fix:
			_set_hidden(false)
			state = State.RETURNING
		elif state == State.HIDDEN:
			state = State.OFF_SHIFT

func _patrol_within(range_m: float) -> bool:
	var cop := get_tree().get_first_node_in_group("patrol") as Node3D
	return cop != null and _flat_dist(cop.global_position) < range_m

func _set_hidden(hidden: bool) -> void:
	model_root.visible = not hidden
	talk_shape.set_deferred("disabled", hidden)
	body_shape.set_deferred("disabled", hidden)

## Moves along the ground toward `target`; true once there.
func _walk_to(target: Vector3, delta: float) -> bool:
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.1:
		anim.update(0.0)
		return true
	var step := minf(dist, WALK_SPEED * delta)
	global_position += to / dist * step
	_face(rad_to_deg(atan2(to.x, to.z)), delta)
	anim.update(WALK_SPEED)
	return false

func _idle_facing(delta: float) -> float:
	var player := _player()
	if player and _flat_dist(player.global_position) < NOTICE_RANGE:
		return _yaw_to(player.global_position)
	_glance_t += delta * GLANCE_SPEED
	return street_facing_deg + sin(_glance_t) * GLANCE_ARC_DEG * 0.5

func _face(target_deg: float, delta: float) -> void:
	model_root.rotation.y = lerp_angle(model_root.rotation.y, deg_to_rad(target_deg), TURN_SPEED * delta)

func _yaw_to(pos: Vector3) -> float:
	var to := pos - global_position
	return rad_to_deg(atan2(to.x, to.z))

func _flat_dist(pos: Vector3) -> float:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length()

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

func _speak() -> void:
	if Voice._piper_ok:
		return
	voice.stream = VOICES.pick_random()
	voice.pitch_scale = VOICE_PITCH * randf_range(0.97, 1.03)
	voice.play()
