extends CanvasLayer

const CRAVING_BAR_WIDTH := 120.0

# The carrying panel is right-aligned and sized to its contents, so it only
# covers as much of the view as it needs to.
const CARRY_RIGHT_EDGE := 952.0
const CARRY_PADDING := 10.0
const ICON_SIZE := 22.0
const ICON_GAP := 6.0

const ITEM_ICONS := {
	"whiskey": preload("res://assets/sprites/item_whiskey_icon.png"),
	"cigs": preload("res://assets/sprites/item_cigs_icon.png"),
	"charger": preload("res://assets/sprites/item_charger_icon.png"),
	"batteries": preload("res://assets/sprites/item_batteries_icon.png"),
	"watch": preload("res://assets/sprites/item_watch_icon.png"),
}

@onready var cash_label: Label = $TopBar/CashLabel
@onready var day_label: Label = $TopBar/DayLabel
@onready var craving_fill: ColorRect = $TopBar/CravingBarFill
@onready var wanted_label: Label = $TopBar/WantedLabel
@onready var inventory_label: Label = $TopBar/InventoryLabel
@onready var inventory_icons: HBoxContainer = $TopBar/InventoryIcons
@onready var carry_bg: Panel = $TopBar/CarryBg
@onready var withdrawal_tint: ColorRect = $WithdrawalTint
@onready var dialogue_panel: Control = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/SpeakerLabel
@onready var text_label: Label = $DialoguePanel/TextLabel
@onready var hint_label: Label = $DialoguePanel/HintLabel
@onready var portrait_rect: TextureRect = $DialoguePanel/Portrait
@onready var busted_overlay: Control = $BustedOverlay

const TEXT_LEFT_WITH_PORTRAIT := 150.0
const TEXT_LEFT_NO_PORTRAIT := 16.0

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
	for child in inventory_icons.get_children():
		inventory_icons.remove_child(child)
		child.queue_free()
	if GameState.inventory.is_empty():
		inventory_label.text = "Carrying: nothing"
		_layout_carry_panel(0)
		return
	inventory_label.text = "Carrying:"
	var icon_count := 0
	for id in GameState.inventory:
		if not ITEM_ICONS.has(id):
			continue
		icon_count += 1
		var icon := TextureRect.new()
		icon.texture = ITEM_ICONS[id]
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		inventory_icons.add_child(icon)
	_layout_carry_panel(icon_count)

func _layout_carry_panel(icon_count: int) -> void:
	var label_w := inventory_label.get_minimum_size().x
	var icons_w := 0.0
	if icon_count > 0:
		icons_w = ICON_GAP + icon_count * ICON_SIZE + (icon_count - 1) * ICON_GAP
	var left := CARRY_RIGHT_EDGE - (CARRY_PADDING * 2.0 + label_w + icons_w)
	carry_bg.offset_left = left
	inventory_label.offset_left = left + CARRY_PADDING
	inventory_label.offset_right = left + CARRY_PADDING + label_w
	inventory_icons.offset_left = inventory_label.offset_right + ICON_GAP
	inventory_icons.offset_right = CARRY_RIGHT_EDGE - CARRY_PADDING

func _update_wanted(is_wanted: bool) -> void:
	wanted_label.visible = is_wanted

func show_dialogue(speaker: String, text: String, portrait: Texture2D = null) -> void:
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	text_label.text = text
	portrait_rect.texture = portrait
	portrait_rect.visible = portrait != null

	var text_left: float = TEXT_LEFT_WITH_PORTRAIT if portrait != null else TEXT_LEFT_NO_PORTRAIT
	speaker_label.offset_left = text_left
	text_label.offset_left = text_left
	hint_label.offset_left = text_left

	dialogue_panel.visible = true

func advance_or_close_dialogue() -> void:
	SFX.play("blip", -4.0, 0.85)
	dialogue_panel.visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.dialogue_active = false

func flash_busted() -> void:
	busted_overlay.visible = true
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(busted_overlay):
		busted_overlay.visible = false
