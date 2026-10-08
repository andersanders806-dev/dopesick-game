extends CanvasLayer

const CRAVING_BAR_WIDTH := 120.0

# The carrying panel is right-aligned and sized to its contents, so it only
# covers as much of the view as it needs to.
const CARRY_RIGHT_EDGE := 952.0
const CARRY_PADDING := 10.0
const ICON_SIZE := 22.0
const ICON_GAP := 6.0

## Icons are rendered from the same 3D models the shelves use
## (dev-tools/render_item_icons.gd), one per item in GameState.REQUEST_POOL.
const ICON_PATH := "res://assets/icons/item_%s.png"

## The film-look pass (assets/fx/filmlook, Arseniy Mirniy's MIT "Screen
## Effects Ultimate"), under the withdrawal PostFX: halation -- the warm
## bleed film gets around bright lights -- so neon and streetlights glow the
## way they do in the cutscene stills, a bloom boost, sharpening to put
## back what FSR's upscale softens, and light fringing toward the edges. Colour stays with Graphics' LUT; this only shapes light and
## texture. (Its own grain and vignette are off: its noise texture is too
## coarse at 720p, and the PostFX already does both.)
const FILM_LOOK := {
	"Pixelation": false, "Panini": 0.0, "Posterization": 0.0, "Filter_Strenght": 0.0,
	"Chromatic_Aberrations": 0.12, "Chromatic_Peripheral": 0.9, "Chromatic_Darkening": 0.9,
	"Blur_Amount": -0.7, "Blur_Centered": 1.0,
	"Bloom_Starts": 0.82, "Bloom_Halation": 0.55, "Bloom_Booster": 1.2,
	"Shadows_Split": 0.3, "Highlights_Split": 0.7,
	"Shadow_Color_Temp": 0.0, "Shadow_Green_Tint": 0.0, "Shadow_Brightness": 1.0, "Shadow_Contrast": 1.0, "Shadows_Saturation": 1.0,
	"Mid_Color_Temp": 0.0, "Mid_Green_Tint": 0.0, "Mid_Brightness": 1.0, "Mid_Contrast": 1.0, "Mid_Saturation": 1.0,
	"High_Color_Temp": 0.0, "High_Green_Tint": 0.0, "High_Brightness": 1.0, "High_Contrast": 1.0, "High_Saturation": 1.0,
	"Main_Color_Temp": 4500.0, "Main_Green_Tint": 0.0, "Main_Brightness": 1.0, "Main_Contrast": 1.03, "Main_Saturation": 1.0,
	# Grain and vignette stay with the PostFX, which already does both.
	"Vignette": 0.0, "Film_Grain": 0.0,
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
@onready var portrait_frame: ColorRect = $DialoguePanel/PortraitFrame
@onready var busted_overlay: Control = $BustedOverlay

## The clock sits right-aligned on the CRAVING row: warm by day, cold blue
## at night, so the time of day reads at a glance without a panel of its own.
const CLOCK_DAY_COLOR := Color(0.95, 0.85, 0.55)
const CLOCK_NIGHT_COLOR := Color(0.55, 0.65, 0.95)
var clock_label: Label
## What you owe the pusher, under the stats panel; red once it's overdue.
var debt_label: Label
## Rent, court, probation or a warrant -- whichever's most pressing.
var status_label: Label

const TEXT_LEFT_WITH_PORTRAIT := 150.0
const TEXT_LEFT_NO_PORTRAIT := 16.0

func _ready() -> void:
	add_to_group("hud")
	_build_film_look()
	add_child(preload("res://ui/InteractPrompt.gd").new())
	GameState.cash_changed.connect(_update_cash)
	GameState.craving_changed.connect(_update_craving)
	GameState.inventory_changed.connect(_update_inventory)
	GameState.wanted_changed.connect(_update_wanted)
	# Bound methods, not lambdas: GameState outlives every HUD, and only a
	# method connection is dropped automatically when its HUD is freed.
	GameState.day_changed.connect(_on_day_or_strikes_changed)
	GameState.strikes_changed.connect(_on_day_or_strikes_changed)
	GameState.treatment_changed.connect(_on_day_or_strikes_changed)
	GameState.run_ended.connect(_show_run_end)
	_build_clock()
	_build_debt()
	GameState.debt_changed.connect(_on_debt_changed)
	_build_status()
	GameState.rent_changed.connect(_update_status)
	GameState.legal_changed.connect(_update_status)
	GameState.clock_changed.connect(_on_clock_changed)
	_update_day()
	_update_cash(GameState.cash)
	_update_craving(GameState.craving)
	_update_inventory()
	_update_wanted(GameState.wanted)
	dialogue_panel.visible = false
	busted_overlay.visible = false
	_build_headline()
	Headlines.headline_changed.connect(_on_headline_changed)

# --- Word on the block ------------------------------------------------------
## Today's headline (autoload/Headlines.gd), once a day: a strip under the
## top bar that slides in, holds, and fades. Waits out any cutscene.
const HEADLINE_HOLD := 9.0
var _headline_panel: PanelContainer
var _headline_title: Label
var _headline_text: Label
var _headline_t: float = -1.0

func _build_headline() -> void:
	_headline_panel = PanelContainer.new()
	_headline_panel.name = "Headline"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.88)
	sb.border_color = Color(0.95, 0.8, 0.45, 0.8)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_content_margin_all(10)
	sb.content_margin_left = 14
	_headline_panel.add_theme_stylebox_override("panel", sb)
	_headline_panel.offset_left = 330.0
	_headline_panel.offset_right = 950.0
	_headline_panel.offset_top = 64.0
	var box := VBoxContainer.new()
	_headline_panel.add_child(box)
	_headline_title = Label.new()
	_headline_title.add_theme_font_size_override("font_size", 13)
	_headline_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	box.add_child(_headline_title)
	_headline_text = Label.new()
	_headline_text.add_theme_font_size_override("font_size", 14)
	_headline_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline_text.custom_minimum_size = Vector2(590, 0)
	box.add_child(_headline_text)
	_headline_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline_panel.visible = false
	add_child(_headline_panel)

func _on_headline_changed(_id: String) -> void:
	_headline_t = -1.0

## Sick, the world goes grey: the room's grade loses its colour and gains a
## hard edge as the craving bottoms out. Graphics sets the base grade; this
## leans on it every frame, so it follows the meter both ways.
const SICK_SATURATION := 0.3
var _graded_env: Environment

func _update_sick_grade() -> void:
	if _graded_env == null:
		var scene := get_tree().current_scene
		var we := scene.find_child("WorldEnvironment", false, false) as WorldEnvironment if scene else null
		if we == null or we.environment == null:
			return
		_graded_env = we.environment
	var s := GameState.sickness()
	var k := s * s
	_graded_env.adjustment_saturation = Graphics.SATURATION * lerpf(1.0, SICK_SATURATION, k)
	_graded_env.adjustment_contrast = Graphics.CONTRAST * lerpf(1.0, 1.18, k)

func _process(delta: float) -> void:
	_update_sick_grade()
	if _headline_panel == null:
		return
	if Headlines.announced_day != GameState.day and not Cutscene.is_playing() and not get_tree().paused:
		Headlines.announced_day = GameState.day
		_headline_title.text = "WORD ON THE BLOCK  -  DAY %d  -  %s" % [GameState.day, Headlines.title().to_upper()]
		_headline_text.text = Headlines.text()
		_headline_t = 0.0
		SFX.play("blip", -6.0, 0.7)
	if _headline_t < 0.0:
		_headline_panel.visible = false
		return
	_headline_t += delta
	_headline_panel.visible = true
	var a := clampf(_headline_t / 0.4, 0.0, 1.0) * clampf((HEADLINE_HOLD - _headline_t) / 1.2, 0.0, 1.0)
	_headline_panel.modulate.a = a
	if _headline_t >= HEADLINE_HOLD:
		_headline_t = -1.0

## Drawn first in the HUD, then a back-buffer copy so the PostFX above reads
## the film-looked frame rather than the raw one.
func _build_film_look() -> void:
	var shader := load("res://assets/fx/filmlook/screen_effects.tres") as Shader
	# DOPESICK_NO_FILM_LOOK=1 turns it off, for before/after comparisons.
	if shader == null or OS.has_environment("DOPESICK_NO_FILM_LOOK"):
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for k in FILM_LOOK:
		mat.set_shader_parameter(k, FILM_LOOK[k])
	mat.set_shader_parameter("Noise", load("res://assets/fx/filmlook/noise_texture.tres"))
	mat.set_shader_parameter("Color_Filter_Gradient", load("res://assets/fx/filmlook/gradient.tres"))
	var rect := ColorRect.new()
	rect.name = "FilmLook"
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# About 12 FPS on a UHD 620, so High only; Graphics toggles the group.
	rect.add_to_group("film_look")
	rect.visible = Graphics.is_high()
	add_child(rect)
	move_child(rect, 0)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	move_child(copy, 1)

func _build_clock() -> void:
	clock_label = Label.new()
	clock_label.name = "ClockLabel"
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.add_theme_font_size_override("font_size", 12)
	clock_label.offset_left = 90.0
	clock_label.offset_top = 33.0
	clock_label.offset_right = 148.0
	clock_label.offset_bottom = 48.0
	$TopBar.add_child(clock_label)
	_update_clock()

func _on_day_or_strikes_changed(_value: int = 0) -> void:
	_update_day()

func _on_clock_changed(_minute: int) -> void:
	_update_clock()
	_update_debt()
	_update_status()

func _build_status() -> void:
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	status_label.add_theme_constant_override("outline_size", 4)
	status_label.offset_left = 12.0
	status_label.offset_right = 300.0
	$TopBar.add_child(status_label)
	_update_status()

func _update_status() -> void:
	var s: Array = GameState.status_line()
	status_label.visible = not s.is_empty()
	# Under the debt line when there is one, in its place when there isn't.
	status_label.offset_top = 86.0 if debt_label.visible else 70.0
	status_label.offset_bottom = status_label.offset_top + 16.0
	if s.is_empty():
		return
	status_label.text = s[0]
	status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if s[1] else Color(0.9, 0.78, 0.45))

func _build_debt() -> void:
	debt_label = Label.new()
	debt_label.name = "DebtLabel"
	debt_label.add_theme_font_size_override("font_size", 12)
	debt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	debt_label.add_theme_constant_override("outline_size", 4)
	debt_label.offset_left = 12.0
	debt_label.offset_top = 70.0
	debt_label.offset_right = 300.0
	debt_label.offset_bottom = 86.0
	$TopBar.add_child(debt_label)
	_update_debt()

func _on_debt_changed(_amount: int) -> void:
	_update_debt()

func _update_debt() -> void:
	debt_label.visible = GameState.debt > 0
	if GameState.debt_overdue():
		debt_label.text = "OWE $%d -- OVERDUE" % GameState.debt
		debt_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	else:
		debt_label.text = "Owe $%d, due %s" % [GameState.debt, GameState.debt_due_text()]
		debt_label.add_theme_color_override("font_color", Color(0.9, 0.62, 0.45))

func _update_clock() -> void:
	clock_label.text = GameState.clock_text()
	clock_label.add_theme_color_override("font_color", CLOCK_NIGHT_COLOR.lerp(CLOCK_DAY_COLOR, GameState.daylight()))

func _update_cash(cash: int) -> void:
	cash_label.text = "$%d" % cash

func _update_craving(craving: float) -> void:
	var frac: float = craving / 100.0
	craving_fill.size.x = CRAVING_BAR_WIDTH * frac
	if craving <= 20.0:
		craving_fill.color = Color(0.75, 0.2, 0.2)
	else:
		craving_fill.color = Color(0.55, 0.65, 0.35)
	# Only once you're actually getting sick -- it used to sit at ~20% green
	# over everything at a normal craving, which muddied every colour.
	withdrawal_tint.color.a = GameState.sickness() * 0.3
	_set_post_fx(GameState.sickness())

## Well, the PostFX is only a vignette and grain: the lite shader draws
## them over the frame without copying the screen (~3.5 ms on a UHD 620).
## Getting sick swaps in the full one.
const POST_FULL := preload("res://assets/fx/postfx.gdshader")
const POST_LITE := preload("res://assets/fx/postfx_lite.gdshader")

func _set_post_fx(sick: float) -> void:
	var mat := $PostFX.material as ShaderMaterial
	var want: Shader = POST_FULL if sick > 0.0 else POST_LITE
	if mat.shader != want:
		mat.shader = want
	mat.set_shader_parameter("sickness", sick)

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
		if not ResourceLoader.exists(ICON_PATH % id):
			# No rendered icon (the carburetor): its name, small.
			var tag := Label.new()
			tag.text = GameState.item_name_for(id).trim_prefix("a ").trim_prefix("an ")
			tag.add_theme_font_size_override("font_size", 11)
			inventory_icons.add_child(tag)
			icon_count += 3
			continue
		icon_count += 1
		var icon := TextureRect.new()
		icon.texture = load(ICON_PATH % id)
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

## Day plus how many chances are left this run, e.g. "Day 4  * * o". Shown
## together because they're the two numbers that say how a run is going, and
## it keeps the strike count out of a panel of its own.
func _update_day() -> void:
	var left: int = GameState.max_strikes() - GameState.strikes
	var pips := "*".repeat(max(0, left)) + "o".repeat(max(0, GameState.strikes))
	day_label.text = "Day %d  %s" % [GameState.day, pips]
	if GameState.in_treatment:
		day_label.text += "   clean %d/%d" % [GameState.treatment_streak, GameState.RECOVERY_DAYS]

## Parented to the tree root, not this HUD: the bust that ends a run also
## changes scene, which would take a child of the current scene down with it
## before the player had read anything.
func _show_run_end(summary: Dictionary) -> void:
	var screen := preload("res://ui/RunEndScreen.gd").new()
	get_tree().root.add_child(screen)
	screen.show_summary(summary)

func show_dialogue(speaker: String, text: String, portrait: Texture2D = null) -> void:
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	text_label.text = text
	portrait_rect.texture = portrait
	portrait_rect.visible = portrait != null
	portrait_frame.visible = portrait != null

	var text_left: float = TEXT_LEFT_WITH_PORTRAIT if portrait != null else TEXT_LEFT_NO_PORTRAIT
	speaker_label.offset_left = text_left
	text_label.offset_left = text_left
	# Keep the hint's width fixed as it moves, or its background box
	# stretches across the panel when there's no portrait.
	hint_label.text = "[%s] continue" % GameState.control_name("interact")
	var hint_width := hint_label.offset_right - hint_label.offset_left
	hint_label.offset_left = text_left
	hint_label.offset_right = text_left + hint_width

	dialogue_panel.visible = true
	Voice.say(speaker, text)

func advance_or_close_dialogue() -> void:
	SFX.play("blip", -4.0, 0.85)
	Voice.stop()
	dialogue_panel.visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.dialogue_active = false

func flash_busted() -> void:
	busted_overlay.visible = true
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(busted_overlay):
		busted_overlay.visible = false
