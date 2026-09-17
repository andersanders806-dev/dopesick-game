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

enum State { POST, TO_STASH, AT_STASH, TO_POST, AWAIT_BUYER, HANDOFF, TO_HIDE, HIDDEN, RETURNING }

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")
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

const GREETINGS := ["\"You good?\"", "\"What you need?\"", "\"Keep walking unless you're buying.\""]
const WAIT_LINES := [
	"\"$%d. ...Wait here.\" He pockets your cash and walks off down the street.",
	"He takes your $%d without counting it. \"Stay put. Don't follow me.\"",
]
const HANDOFF_LINES := [
	"He brushes past you and presses it into your palm. You feel it hit.",
	"A quick handshake, and it's yours. You feel it hit.",
]

@export var street_facing_deg: float = 0.0
@export var model_path: String = "res://assets/kenney/characters/character-male-f.glb"
## Dark grey, like a zip-up hoodie -- and so he doesn't read as the player,
## who wears the same base model's green shirt.
@export var clothes_tint: Color = Color(0.32, 0.33, 0.36)
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

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("pusher")
	var model: Node = load(model_path).instantiate()
	model_root.add_child(model)
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

func is_busy() -> bool:
	return state != State.POST

func _process(delta: float) -> void:
	match state:
		State.POST:
			_face(_idle_facing(delta), delta)
			anim.update(0.0)
		State.TO_STASH:
			if _walk_to(stash_position, delta):
				state = State.AT_STASH
				_timer = anim.play_once("pick-up", 0.5) + 0.3
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
				state = State.HIDDEN
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
	var cost := GameState.current_fix_cost()
	if GameState.cash < cost:
		hud.show_dialogue("Pusher", "%s \"$%d. Come back when you've got it.\"" % [GREETINGS.pick_random(), cost], PORTRAIT)
		return
	GameState.spend_cash(cost)
	_owes_fix = true
	SFX.play("cash", -6.0, 0.8)
	hud.show_dialogue("Pusher", WAIT_LINES.pick_random() % cost, PORTRAIT)
	state = State.TO_STASH

func _handoff(player: Node) -> void:
	state = State.HANDOFF
	_timer = anim.play_once("interact-right", 0.8)
	_speak()
	_owes_fix = false
	GameState.receive_fix()
	SFX.play("fix")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and not player.dialogue_active:
		player.dialogue_active = true
		hud.show_dialogue("Pusher", HANDOFF_LINES.pick_random(), PORTRAIT)
	sale_completed.emit()

## The lookout's whistle: clear out, or come back once it's quiet. A sale
## that's already paid for is still owed -- he picks up where he left off.
func _on_wanted_changed(is_wanted: bool) -> void:
	if is_wanted:
		if state not in [State.TO_HIDE, State.HIDDEN]:
			state = State.TO_HIDE
	elif state in [State.HIDDEN, State.TO_HIDE]:
		_set_hidden(false)
		state = State.RETURNING

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
	voice.stream = VOICES.pick_random()
	voice.pitch_scale = VOICE_PITCH * randf_range(0.97, 1.03)
	voice.play()
