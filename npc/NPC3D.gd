extends Area3D

const PORTRAITS := {
	"Bartender": preload("res://assets/portraits/bartender.png"),
	"Wiry Guy": preload("res://assets/portraits/wiry_guy.png"),
	"Tired Woman": preload("res://assets/portraits/tired_woman.png"),
	"Big Eddie": preload("res://assets/portraits/big_eddie.png"),
	"Quiet Kid": preload("res://assets/portraits/quiet_kid.png"),
	"Old Sailor": preload("res://assets/portraits/old_sailor.png"),
	"Nervous Dave": preload("res://assets/portraits/nervous_dave.png"),
}

const PATRON_SFX := {
	"cough": preload("res://assets/sfx/patron_cough.wav"),
	"cough_wet": preload("res://assets/sfx/patron_cough_wet.wav"),
	"sniff": preload("res://assets/sfx/patron_sniff.wav"),
	"sigh": preload("res://assets/sfx/patron_sigh.wav"),
	"glass_down": preload("res://assets/sfx/patron_glass_down.wav"),
	"sip": preload("res://assets/sfx/patron_sip.wav"),
	"tap": preload("res://assets/sfx/patron_tap.wav"),
}
const VOICES := [
	preload("res://assets/sfx/patron_mutter_a.wav"),
	preload("res://assets/sfx/patron_mutter_b.wav"),
	preload("res://assets/sfx/patron_mutter_c.wav"),
]

## What each patron does while sitting there, matched to how their portrait
## reads (see dev-tools/gen_portraits.py): the gaunt, restless opioid users
## sniff and drum their fingers, the benzo-glazed sigh, the heavy drinkers
## sip, cough, and set glasses down. `voice` is the pitch their mumbled
## greeting plays at; `volume` offsets how loud they are overall.
const PATRON_PROFILES := {
	"Wiry Guy": {"idle": ["sniff", "sniff", "tap", "cough"], "voice": 1.05, "volume": 0.0},
	"Tired Woman": {"idle": ["sigh", "sigh", "glass_down"], "voice": 1.35, "volume": -2.0},
	"Big Eddie": {"idle": ["sip", "sip", "cough", "glass_down"], "voice": 0.72, "volume": 2.0},
	"Quiet Kid": {"idle": ["sniff", "sigh"], "voice": 1.25, "volume": -6.0},
	"Old Sailor": {"idle": ["cough_wet", "cough_wet", "sip", "glass_down"], "voice": 0.8, "volume": 0.0},
	"Nervous Dave": {"idle": ["tap", "tap", "sniff", "sigh"], "voice": 1.0, "volume": -1.0},
}
const IDLE_SOUND_MIN_GAP := 5.0
const IDLE_SOUND_MAX_GAP := 14.0

@export var npc_name: String = "Stranger"
@export var is_patron: bool = false
@export_multiline var flavor_lines: String = "..."
@export var model_path: String = "res://assets/kenney/characters/character-male-b.glb"

@onready var model_root: Node3D = $ModelRoot
@onready var idle_sound: AudioStreamPlayer3D = $IdleSound
@onready var voice: AudioStreamPlayer3D = $Voice

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")

var anim: CharacterAnimator

var request_id: String = ""
var request_price: int = 0
var fulfilled: bool = false
var _idle_sound_timer: float = 0.0
var _talking: bool = false
var _idle_base_db: float
var _voice_base_db: float

func _ready() -> void:
	add_to_group("interactable")
	set_model(model_path)
	_idle_base_db = idle_sound.volume_db
	_voice_base_db = voice.volume_db
	# Random first delay so a freshly entered bar doesn't have every patron
	# coughing on the same frame.
	_idle_sound_timer = randf_range(1.0, IDLE_SOUND_MAX_GAP)

func _profile() -> Dictionary:
	return PATRON_PROFILES.get(npc_name, {})

func _process(delta: float) -> void:
	if not is_patron:
		return
	if _talking:
		# Quiet while the player is talking to them; resume once the
		# dialogue box closes.
		var player := get_tree().get_first_node_in_group("player")
		if player and player.dialogue_active:
			return
		_talking = false
	_idle_sound_timer -= delta
	if _idle_sound_timer <= 0.0:
		_idle_sound_timer = randf_range(IDLE_SOUND_MIN_GAP, IDLE_SOUND_MAX_GAP)
		play_idle_sound()

## One of this patron's idle sounds, from where they sit.
func play_idle_sound() -> void:
	var profile := _profile()
	if profile.is_empty():
		return
	var options: Array = profile["idle"]
	idle_sound.stream = PATRON_SFX[options.pick_random()]
	idle_sound.volume_db = _idle_base_db + profile["volume"]
	idle_sound.pitch_scale = randf_range(0.93, 1.07)
	idle_sound.play()

func _speak() -> void:
	var profile := _profile()
	if profile.is_empty():
		return
	idle_sound.stop()
	voice.stream = VOICES.pick_random()
	voice.volume_db = _voice_base_db + profile["volume"]
	voice.pitch_scale = profile["voice"] * randf_range(0.97, 1.03)
	voice.play()

## Swappable after _ready() so a room script can re-skin a patron -- child
## nodes are ready before their parent room, so the default model is already
## in place by the time DiveBar3D randomizes who shows up.
func set_model(path: String) -> void:
	model_path = path
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	anim = null
	if path != "":
		var model: Node = load(path).instantiate()
		model_root.add_child(model)
		anim = CharacterAnimator.new(model)

func set_request(id: String, price: int) -> void:
	request_id = id
	request_price = price
	fulfilled = false

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("blip")

	if is_patron:
		_talking = true
		_speak()
		_patron_interact(hud)
	else:
		_flavor_interact(hud)

func _portrait() -> Texture2D:
	return PORTRAITS.get(npc_name)

func _patron_interact(hud: Node) -> void:
	if request_id == "":
		hud.show_dialogue(npc_name, "Not looking for anything right now.", _portrait())
		return
	if fulfilled:
		hud.show_dialogue(npc_name, "Thanks again for that.", _portrait())
		return
	if GameState.has_item(request_id):
		GameState.sell_item(request_id, request_price)
		fulfilled = true
		SFX.play("cash")
		hud.show_dialogue(npc_name, "That's exactly it. Here's $%d." % request_price, _portrait())
	else:
		var item_name := GameState.item_name_for(request_id)
		hud.show_dialogue(npc_name, "I need %s. Get it for me and I'll pay $%d." % [item_name, request_price], _portrait())

func _flavor_interact(hud: Node) -> void:
	if not GameState.inventory.is_empty():
		var earned := GameState.fence_everything()
		SFX.play("cash")
		hud.show_dialogue(npc_name, "I'll take that off your hands. Here's $%d, no questions." % earned, _portrait())
		return
	var lines := flavor_lines.split("\n", false)
	if lines.is_empty():
		hud.show_dialogue(npc_name, "...", _portrait())
		return
	hud.show_dialogue(npc_name, lines[randi() % lines.size()], _portrait())
