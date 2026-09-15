extends CanvasLayer

const CRAVING_BAR_WIDTH := 120.0

@onready var cash_label: Label = $TopBar/CashLabel
@onready var day_label: Label = $TopBar/DayLabel
@onready var craving_fill: ColorRect = $TopBar/CravingBarFill
@onready var wanted_label: Label = $TopBar/WantedLabel
@onready var inventory_label: Label = $TopBar/InventoryLabel
@onready var withdrawal_tint: ColorRect = $WithdrawalTint
@onready var dialogue_panel: Control = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/SpeakerLabel
@onready var text_label: Label = $DialoguePanel/TextLabel
@onready var busted_overlay: Control = $BustedOverlay

func _ready() -> void:
	add_to_group("hud")
	GameState.cash_changed.connect(_update_cash)
	GameState.craving_changed.connect(_update_craving)
	GameState.inventory_changed.connect(_update_inventory)
	GameState.wanted_changed.connect(_update_wanted)
	_update_cash(GameState.cash)
	_update_craving(GameState.craving)
	_update_inventory()
	_update_wanted(GameState.wanted)
	day_label.text = "Day %d" % GameState.day
	dialogue_panel.visible = false
	busted_overlay.visible = false

func _update_cash(cash: int) -> void:
	cash_label.text = "$%d" % cash

func _update_craving(craving: float) -> void:
	var frac: float = craving / 100.0
	craving_fill.size.x = CRAVING_BAR_WIDTH * frac
	if craving <= 20.0:
		craving_fill.color = Color(0.75, 0.2, 0.2)
	else:
		craving_fill.color = Color(0.55, 0.65, 0.35)
	withdrawal_tint.color.a = clamp(1.0 - frac, 0.0, 1.0) * 0.35

func _update_inventory() -> void:
	if GameState.inventory.is_empty():
		inventory_label.text = "Carrying: nothing"
		return
	var names: Array = []
	for id in GameState.inventory:
		names.append(GameState.item_name_for(id))
	inventory_label.text = "Carrying: " + ", ".join(names)

func _update_wanted(is_wanted: bool) -> void:
	wanted_label.visible = is_wanted

func show_dialogue(speaker: String, text: String) -> void:
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	text_label.text = text
	dialogue_panel.visible = true

func advance_or_close_dialogue() -> void:
	dialogue_panel.visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.dialogue_active = false

func flash_busted() -> void:
	busted_overlay.visible = true
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(busted_overlay):
		busted_overlay.visible = false
