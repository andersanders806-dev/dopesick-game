extends CanvasLayer
## The story's HUD, in the game's one visual language (ui/UiStyle.gd: Barlow, the safe area, amber on dark):
## top left the money, the day and clock and the body's meters as clean bars with an icon each; top right the
## objective chip (and what you carry, and new messages, only when there are any); the interact prompt by the
## crosshair in first person. While you walk and nothing needs you it all steps back (in first person, away).

const UiStyle := preload("res://ui/UiStyle.gd")

const BAR_W := 190.0
const ROW_H := 28.0
const CARRY_ICON := 30.0

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
@onready var wanted_label: Label = $TopBar/WantedLabel
@onready var withdrawal_tint: ColorRect = $WithdrawalTint
@onready var dialogue_panel: Control = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/SpeakerLabel
@onready var text_label: Label = $DialoguePanel/TextLabel
@onready var hint_label: Label = $DialoguePanel/HintLabel
@onready var portrait_rect: TextureRect = $DialoguePanel/Portrait
@onready var portrait_frame: ColorRect = $DialoguePanel/PortraitFrame
@onready var busted_overlay: Control = $BustedOverlay

## The clock: warm by day, cold blue at night, so the time of day reads at a glance.
const CLOCK_DAY_COLOR := Color(0.98, 0.88, 0.6)
const CLOCK_NIGHT_COLOR := Color(0.6, 0.7, 1.0)
var clock_label: Label
## What you owe the pusher; red once it's overdue.
var debt_label: Label
## Rent, court, probation or a warrant -- whichever's most pressing.
var status_label: Label
var treatment_label: Label
var craving_fill: ColorRect
var inventory_icons: HBoxContainer
var pips: Pips
var reticle: Reticle
var _carry_chip: PanelContainer
var _right: VBoxContainer
var _notes: VBoxContainer
var _prompt: Label

const TEXT_LEFT_WITH_PORTRAIT := 150.0
const TEXT_LEFT_NO_PORTRAIT := 16.0

## A drawn icon for each meter: nothing to import, crisp at any scale, and it takes the bar's colour.
class StatIcon extends Control:
	var kind := ""
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	func _init(k: String = "") -> void:
		kind = k
		custom_minimum_size = Vector2(22, 22)
		size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var shade := Color(0, 0, 0, 0.55)
		match kind:
			"health":
				draw_rect(Rect2(8, 3, 6, 16), color)
				draw_rect(Rect2(3, 8, 16, 6), color)
			"craving":
				draw_set_transform(Vector2(11, 11), -0.75, Vector2.ONE)
				draw_circle(Vector2(-4.5, 0), 4.5, color)
				draw_circle(Vector2(4.5, 0), 4.5, color)
				draw_rect(Rect2(-4.5, -4.5, 9, 9), color)
				draw_rect(Rect2(-0.8, -4.5, 1.6, 9), shade)
			"food":
				draw_circle(Vector2(8, 13), 6.0, color)
				draw_circle(Vector2(14, 13), 6.0, color)
				draw_line(Vector2(11, 8), Vector2(13, 2), color, 2.0, true)
			"warm":
				draw_colored_polygon(PackedVector2Array([Vector2(11, 1.5), Vector2(15.5, 8), Vector2(18, 14),
					Vector2(15, 20), Vector2(7, 20), Vector2(4, 14), Vector2(6.5, 9), Vector2(8.5, 12)]), color)
				draw_circle(Vector2(11, 16), 3.0, shade)
			"rest":
				draw_arc(Vector2(11, 11), 6.0, deg_to_rad(110), deg_to_rad(330), 24, color, 4.5, true)

## The strikes left in a run: a filled dot each, an empty ring for each one spent.
class Pips extends Control:
	const UiStyle := preload("res://ui/UiStyle.gd")
	var total := 3
	var lost := 0
	var left: int:
		get:
			return total - lost
	func set_state(t: int, l: int) -> void:
		total = t
		lost = l
		custom_minimum_size = Vector2(total * 15.0, 20.0)
		size = custom_minimum_size
		queue_redraw()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for i in total:
			var c := Vector2(8.0 + i * 15.0, 10.0)
			if i < total - lost:
				draw_circle(c, 4.5, UiStyle.AMBER)
			else:
				draw_arc(c, 3.8, 0.0, TAU, 16, UiStyle.DIM, 1.6, true)

## A quiet dot at the centre of the view in first person, opening to a ring over something you can use.
class Reticle extends Control:
	const UiStyle := preload("res://ui/UiStyle.gd")
	var hot := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 3.4 + hot * 2.0, Color(0, 0, 0, 0.42))
		draw_circle(c, 1.9 + hot * 1.0, Color(UiStyle.PAPER, 0.82 + hot * 0.18))
		if hot > 0.01:
			draw_arc(c, 8.0 + (1.0 - hot) * 6.0, 0.0, TAU, 28, Color(UiStyle.AMBER, hot * 0.9), 1.8, true)

func _ready() -> void:
	add_to_group("hud")
	_build_film_look()
	_prompt = preload("res://ui/InteractPrompt.gd").new()
	add_child(_prompt)
	add_child(preload("res://ui/StifleHint.gd").new())
	_build_high_tint()
	reticle = Reticle.new()
	reticle.name = "Reticle"
	add_child(reticle)
	for sig in [GameState.cash_changed, GameState.inventory_changed, GameState.wanted_changed,
			GameState.day_changed, GameState.debt_changed, GameState.rent_changed, GameState.legal_changed]:
		sig.connect(_wake_on)
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
	_style_top_left()
	_build_clock()
	_build_craving()
	_build_survival()
	_build_notes()
	_build_right()
	GameState.debt_changed.connect(_on_debt_changed)
	GameState.rent_changed.connect(_update_status)
	GameState.legal_changed.connect(_update_status)
	GameState.clock_changed.connect(_on_clock_changed)
	_update_day()
	_update_cash(GameState.cash)
	_update_craving(GameState.craving)
	_update_inventory()
	_update_wanted(GameState.wanted)
	_style_dialogue()
	dialogue_panel.visible = false
	busted_overlay.visible = false
	_build_headline()
	Headlines.headline_changed.connect(_on_headline_changed)

## A Label in the HUD's type: Barlow Condensed for numbers and captions, Barlow for sentences.
func _text(parent: Node, text: String, font_path: String, size: int, color: Color, tracking := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Small type gets a thin outline (a soft shadow blobs it up); the big numbers keep the shadow.
	UiStyle.style_label(l, font_path, size, color, tracking, size > 20)
	if size <= 20:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 4)
	if parent:
		parent.add_child(l)
	return l

## A dark chip with an accent down its left edge: what the right-hand column is made of.
func _chip(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.048, 0.056, 0.8)
	sb.border_color = accent
	sb.border_width_left = 3
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	return p

# --- Top left: money, day, clock ---------------------------------------------------------------

func _style_top_left() -> void:
	UiStyle.style_label(cash_label, UiStyle.COND_BOLD, 44, UiStyle.PAPER, 1)
	cash_label.offset_left = UiStyle.SAFE_X
	cash_label.offset_top = UiStyle.SAFE_Y - 12.0
	cash_label.offset_right = UiStyle.SAFE_X + 220.0
	cash_label.offset_bottom = UiStyle.SAFE_Y + 40.0
	UiStyle.style_label(day_label, UiStyle.COND_BOLD, 21, UiStyle.AMBER, 3)
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	day_label.offset_left = UiStyle.SAFE_X + 2.0
	day_label.offset_top = UiStyle.SAFE_Y + 40.0
	day_label.offset_right = UiStyle.SAFE_X + 90.0
	day_label.offset_bottom = UiStyle.SAFE_Y + 66.0
	day_label.remove_theme_color_override("font_shadow_color")
	UiStyle.style_label(day_label, UiStyle.COND_BOLD, 21, UiStyle.AMBER, 3)
	# WANTED: dead centre at the top, blood red, pulsing.
	UiStyle.style_label(wanted_label, UiStyle.COND_BOLD, 32, Color(1.0, 0.32, 0.28), 8)
	wanted_label.anchor_left = 0.5
	wanted_label.anchor_right = 0.5
	wanted_label.offset_left = -110.0
	wanted_label.offset_right = 110.0
	wanted_label.offset_top = UiStyle.SAFE_Y
	wanted_label.offset_bottom = UiStyle.SAFE_Y + 46.0
	pips = Pips.new()
	pips.name = "StrikePips"
	pips.position = Vector2(UiStyle.SAFE_X + 156.0, UiStyle.SAFE_Y + 43.0)
	$TopBar.add_child(pips)

func _build_clock() -> void:
	clock_label = _text($TopBar, "", UiStyle.COND_BOLD, 21, UiStyle.PAPER, 2)
	clock_label.name = "ClockLabel"
	clock_label.position = Vector2(UiStyle.SAFE_X + 82.0, UiStyle.SAFE_Y + 40.0)
	_update_clock()

# --- The bars -----------------------------------------------------------------------------------

## One meter: its icon, a thin bar, its name. Returns the fill (its full width in meta "full").
func _meter(parent: Control, kind: String, caption: String, y: float, color: Color) -> ColorRect:
	var icon := StatIcon.new(kind)
	icon.color = color
	icon.position = Vector2(0, y)
	icon.name = "Icon" + kind.capitalize()
	parent.add_child(icon)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.58)
	bg.position = Vector2(30, y + 6)
	bg.size = Vector2(BAR_W, 10)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var edge := ReferenceRect.new()
	edge.border_color = UiStyle.PANEL_EDGE
	edge.border_width = 1.0
	edge.editor_only = false
	edge.position = bg.position
	edge.size = bg.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(edge)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = bg.position + Vector2(1, 1)
	fill.size = Vector2(BAR_W - 2.0, 8)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_meta("full", BAR_W - 2.0)
	fill.set_meta("icon", icon)
	parent.add_child(fill)
	var cap := _text(parent, caption, UiStyle.COND_BOLD, 14, UiStyle.MUTED, 2)
	cap.position = Vector2(30 + BAR_W + 10.0, y + 1.0)
	return fill

const CRAVING_COLOR := Color(0.95, 0.72, 0.28)
## What you aren't craving yet, drains: it is the one meter that is always moving, so it does not wake the HUD.
func _build_craving() -> void:
	var holder := Control.new()
	holder.name = "CravingMeter"
	holder.position = Vector2(UiStyle.SAFE_X, UiStyle.SAFE_Y + 80.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TopBar.add_child(holder)
	craving_fill = _meter(holder, "craving", "CRAVING", 0.0, CRAVING_COLOR)

## Health, then food, warmth and rest.
const NEED_COLORS := [Color(0.9, 0.62, 0.3), Color(0.45, 0.75, 0.98), Color(0.7, 0.6, 0.95)]
const HEALTH_OK := Color(0.5, 0.78, 0.4)
var survival_panel: Control
var health_fill: ColorRect
var need_fills: Array = []
var survival_warn: Label

func _build_survival() -> void:
	survival_panel = Control.new()
	survival_panel.name = "SurvivalBg"
	survival_panel.position = Vector2(UiStyle.SAFE_X, UiStyle.SAFE_Y + 80.0 + ROW_H)
	survival_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TopBar.add_child(survival_panel)
	health_fill = _meter(survival_panel, "health", "HEALTH", 0.0, HEALTH_OK)
	var names := ["FOOD", "WARM", "REST"]
	var kinds := ["food", "warm", "rest"]
	for i in 3:
		need_fills.append(_meter(survival_panel, kinds[i], names[i], ROW_H * (i + 1), NEED_COLORS[i]))
	Survival.changed.connect(_update_survival)
	_update_survival()

func _on_hurt(amount: float) -> void:
	if _hurt_flash == null:
		_hurt_flash = ColorRect.new()
		_hurt_flash.name = "HurtFlash"
		_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hurt_flash.color = Color(0.7, 0.0, 0.0, 0.0)
		add_child(_hurt_flash)
	_hurt_flash.color.a = clampf(amount / 40.0, 0.15, 0.45)
	_hurt_flash.create_tween().tween_property(_hurt_flash, "color:a", 0.0, 0.5)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("kick"):
		player.kick(clampf(amount / 15.0, 0.4, 1.5))
	var base := survival_panel.position
	var tw := survival_panel.create_tween()
	for i in 4:
		tw.tween_property(survival_panel, "position", base + Vector2(randf_range(-4, 4), randf_range(-2, 2)), 0.04)
	tw.tween_property(survival_panel, "position", base, 0.04)

var _last_health := -1.0
var _hurt_flash: ColorRect

func _fill(f: ColorRect, frac: float, color: Color) -> void:
	f.size.x = float(f.get_meta("full")) * clampf(frac, 0.0, 1.0)
	f.color = color
	(f.get_meta("icon") as StatIcon).color = color

func _update_survival() -> void:
	if health_fill == null:
		return
	# A real hit, not the slow drain: red flash, a jolt, the bar shakes.
	if _last_health >= 0.0 and _last_health - Survival.health >= 3.0:
		_on_hurt(_last_health - Survival.health)
	_last_health = Survival.health
	var hp := Survival.health / Survival.MAX
	_fill(health_fill, hp, Color(0.9, 0.2, 0.2) if hp < 0.3 else Color(0.85, 0.3, 0.26).lerp(HEALTH_OK, hp))
	_wake_if_moved("health", Survival.health)
	var vals := [Survival.hunger, Survival.warmth, Survival.rest]
	for i in 3:
		var low: bool = vals[i] < Survival.LOW
		_fill(need_fills[i], vals[i] / Survival.MAX,
			Color(0.95, 0.28, 0.22) if low and int(Time.get_ticks_msec() / 400) % 2 == 0 else NEED_COLORS[i])
		_wake_if_moved("need%d" % i, vals[i])
	if survival_warn:
		survival_warn.text = "  ".join(Survival.warnings())

# --- Notes under the bars: what's wrong, what you owe, the law --------------------------------------

func _build_notes() -> void:
	_notes = VBoxContainer.new()
	_notes.name = "Notes"
	_notes.add_theme_constant_override("separation", 2)
	_notes.position = Vector2(UiStyle.SAFE_X, UiStyle.SAFE_Y + 80.0 + ROW_H * 5.0 + 6.0)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TopBar.add_child(_notes)
	survival_warn = _text(_notes, "", UiStyle.COND_BOLD, 17, Color(1.0, 0.36, 0.3), 2)
	survival_warn.name = "SurvivalWarn"
	debt_label = _text(_notes, "", UiStyle.BODY_SEMI, 16, UiStyle.AMBER)
	debt_label.name = "DebtLabel"
	status_label = _text(_notes, "", UiStyle.BODY_SEMI, 16, UiStyle.AMBER)
	status_label.name = "StatusLabel"
	treatment_label = _text(_notes, "", UiStyle.COND_BOLD, 16, HEALTH_OK, 2)
	treatment_label.name = "TreatmentLabel"
	_update_debt()
	_update_status()

# --- Right: what now, what you carry, messages ---------------------------------------------------------

const Objectives := preload("res://ui/Objectives.gd")
var objective_label: Label
var unread_label: Label
var _objective_t := 0.0
var _hint_t := 2.0

func _build_right() -> void:
	_right = VBoxContainer.new()
	_right.name = "RightColumn"
	_right.add_theme_constant_override("separation", 8)
	_right.anchor_left = 1.0
	_right.anchor_right = 1.0
	_right.offset_left = -(UiStyle.SAFE_X + 400.0)
	_right.offset_right = -UiStyle.SAFE_X
	_right.offset_top = UiStyle.SAFE_Y
	_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TopBar.add_child(_right)
	# What now.
	var obj := _chip(UiStyle.AMBER)
	obj.name = "ObjectiveChip"
	_right.add_child(obj)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	obj.add_child(box)
	_text(box, "OBJECTIVE", UiStyle.COND_BOLD, 14, UiStyle.AMBER, 4)
	objective_label = _text(box, "", UiStyle.BODY_SEMI, 19, UiStyle.PAPER)
	objective_label.name = "Objective"
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size = Vector2(340, 0)
	_update_objective()
	# What you carry: only when there is something.
	_carry_chip = _chip(UiStyle.MUTED)
	_carry_chip.name = "CarryChip"
	_right.add_child(_carry_chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_carry_chip.add_child(row)
	var kick := _text(row, "CARRYING", UiStyle.COND_BOLD, 14, UiStyle.MUTED, 4)
	kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inventory_icons = HBoxContainer.new()
	inventory_icons.name = "InventoryIcons"
	inventory_icons.add_theme_constant_override("separation", 6)
	row.add_child(inventory_icons)
	# New messages.
	var msg := _chip(Color(0.5, 0.82, 1.0))
	msg.name = "MessagesChip"
	_right.add_child(msg)
	unread_label = _text(msg, "", UiStyle.BODY_SEMI, 17, Color(0.62, 0.86, 1.0))
	unread_label.name = "UnreadLabel"
	Story.messages_changed.connect(_update_unread)
	_update_unread()

func _update_objective() -> void:
	objective_label.text = Objectives.current()

## Every half second; and the next first-run hint every few seconds.
func _tick_objective(delta: float) -> void:
	_objective_t -= delta
	if _objective_t <= 0.0:
		_objective_t = 0.5
		_update_objective()
	_hint_t -= delta
	if _hint_t <= 0.0:
		_hint_t = 6.0
		for h in Objectives.FIRST_STEPS:
			if not MetaProgress.hints_seen.has(h[0]):
				MetaProgress.hints_seen[h[0]] = true
				MetaProgress.save_progress()
				Graphics._show_toast(h[1], 5.5)
				break

func _update_unread() -> void:
	var n: int = Story.unread()
	unread_label.visible = n > 0
	unread_label.get_parent().visible = n > 0
	unread_label.text = "%d new message%s   %s" % [n, "" if n == 1 else "s", GameState.control_name("notebook")]

# --- Immersive HUD -------------------------------------------------------------
## While you walk and nothing needs you, the panels step back so the world is the picture (almost gone in
## third person, gone in first). Anything changing (cash, what you carry, the objective, a meter moving, a
## warning), a third-person pause, or holding Tab brings them straight back.
## Settings > "Fade the HUD while walking" (Graphics.immersive_hud).
const CALM_ALPHA := 0.2
const AWAKE_TIME := 6.0
const STILL_TIME := 0.8
var _awake := AWAKE_TIME
var _still := 0.0
var _last_objective := ""
var _woke_at := {}

func wake() -> void:
	_awake = AWAKE_TIME

## Any of GameState's signals, whatever they carry.
func _wake_on(_a = null) -> void:
	wake()

## A meter that has moved a good step since it last asked for attention wakes the HUD; the slow drain does not.
func _wake_if_moved(key: String, value: float) -> void:
	if not _woke_at.has(key):
		_woke_at[key] = value
	elif absf(float(_woke_at[key]) - value) >= 8.0:
		_woke_at[key] = value
		wake()

## Whether the panels have to be readable right now.
func hud_needed() -> bool:
	if not Graphics.immersive_hud or _awake > 0.0:
		return true
	# Standing still in third person shows it; in first person you are looking at the world, so it doesn't.
	if _still >= STILL_TIME and not Graphics.first_person:
		return true
	if Input.is_physical_key_pressed(KEY_TAB) or dialogue_panel.visible:
		return true
	if GameState.wanted or GameState.sickness() >= 0.5:
		return true
	return Survival.enabled and not Survival.warnings().is_empty()

func _tick_fade(delta: float) -> void:
	if get_tree().paused:
		return
	_awake -= delta
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var moving := player != null and Vector2(player.velocity.x, player.velocity.z).length() > 0.4
	_still = 0.0 if moving else _still + delta
	if objective_label and objective_label.text != _last_objective:
		_last_objective = objective_label.text
		wake()
	var calm := 0.0 if Graphics.first_person else CALM_ALPHA
	var want := 1.0 if hud_needed() else calm
	var bar: Control = $TopBar
	bar.modulate.a = move_toward(bar.modulate.a, want, delta * (4.0 if want > bar.modulate.a else 0.8))
	# WANTED pulses.
	if wanted_label.visible:
		wanted_label.modulate.a = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.008)
	# The reticle: story first person only, opening over something you can use.
	var show_dot := Graphics.first_person and GameState.mode == "story" and not dialogue_panel.visible \
			and not Cutscene.is_playing()
	reticle.visible = show_dot
	if show_dot:
		var target := 1.0 if _prompt != null and _prompt.visible else 0.0
		var h := move_toward(reticle.hot, target, delta * 7.0)
		if h != reticle.hot:
			reticle.hot = h
			reticle.queue_redraw()

# --- Word on the block ------------------------------------------------------
## Today's headline (autoload/Headlines.gd), once a day: a strip under the
## top bar that slides in, holds, and fades. Waits out any cutscene.
const HEADLINE_HOLD := 9.0
var _headline_panel: PanelContainer
var _headline_title: Label
var _headline_text: Label
var _headline_t: float = -1.0

func _build_headline() -> void:
	_headline_panel = _chip(UiStyle.AMBER)
	_headline_panel.name = "Headline"
	_headline_panel.size_flags_horizontal = Control.SIZE_FILL
	_headline_panel.anchor_left = 0.5
	_headline_panel.anchor_right = 0.5
	_headline_panel.offset_left = -230.0
	_headline_panel.offset_right = 230.0
	# Under the toasts (Graphics) and clear of the objective column.
	_headline_panel.offset_top = 196.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_headline_panel.add_child(box)
	_headline_title = _text(box, "", UiStyle.COND_BOLD, 15, UiStyle.AMBER, 3)
	_headline_text = _text(box, "", UiStyle.BODY, 19, UiStyle.PAPER)
	_headline_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline_text.custom_minimum_size = Vector2(420, 0)
	_headline_panel.visible = false
	add_child(_headline_panel)

func _on_headline_changed(_id: String) -> void:
	_headline_t = -1.0

## Sick, the world goes grey: the room's grade loses its colour and gains a
## hard edge as the craving bottoms out. Graphics sets the base grade; this
## leans on it every frame, so it follows the meter both ways.
const SICK_SATURATION := 0.55
var _graded_env: Environment

## The warm side of a dose: an amber wash, a little more colour and bloom, a softer vignette, all
## by GameState.high_glow() -- how good the dose felt, fading as it wears off. A dose that feels
## flat (tolerance) leaves the grade where it was.
const HIGH_TINT := Color(1.0, 0.62, 0.32)
## Added light, not a veil: a warm lift over everything, the way a good dose makes the room glow.
const HIGH_TINT_ALPHA := 0.10
const HIGH_SATURATION := 0.28
const HIGH_BRIGHTNESS := 0.06
const HIGH_BLOOM := 0.2
const HIGH_GLOW_INTENSITY := 0.6
const HIGH_VIGNETTE := 0.5
var _high_tint: ColorRect
var _glow_base := Vector2(-1.0, -1.0)

func _build_high_tint() -> void:
	_high_tint = ColorRect.new()
	_high_tint.name = "HighTint"
	_high_tint.color = Color(HIGH_TINT, 0.0)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_high_tint.material = add
	_high_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_high_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_high_tint)
	move_child(_high_tint, withdrawal_tint.get_index() + 1)

func _update_high() -> void:
	var g := GameState.high_glow()
	# The soft bloom needs a look at the frame, which is the full shader's job; it is only used while it shows.
	var mat0 := $PostFX.material as ShaderMaterial
	if mat0 != null and (g > 0.003) != (mat0.shader == POST_FULL) and GameState.sickness() <= 0.0:
		mat0.shader = POST_FULL if g > 0.003 else POST_LITE
	if _high_tint != null:
		# Not drawn at all when there is nothing to show: a full-screen blend is not free on a small GPU.
		_high_tint.visible = g > 0.003
		_high_tint.color.a = HIGH_TINT_ALPHA * g
	var mat := $PostFX.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("vignette_strength", 0.85 * (1.0 - HIGH_VIGNETTE * g))
		mat.set_shader_parameter("high", g)
		var player := get_tree().get_first_node_in_group("player")
		var bursts: Node = player.get("sick_bursts") if player != null else null
		mat.set_shader_parameter("tunnel", float(bursts.get("tunnel")) if bursts != null else 0.0)

func _update_sick_grade() -> void:
	if _graded_env == null:
		var scene := get_tree().current_scene
		var we := scene.find_child("WorldEnvironment", false, false) as WorldEnvironment if scene else null
		if we == null or we.environment == null:
			return
		_graded_env = we.environment
	var s := GameState.sickness()
	var k := s * s
	var g := GameState.high_glow()
	_graded_env.adjustment_saturation = Graphics.SATURATION * lerpf(1.0, SICK_SATURATION, k) * (1.0 + HIGH_SATURATION * g)
	_graded_env.adjustment_contrast = Graphics.CONTRAST * lerpf(1.0, 1.08, k)
	_graded_env.adjustment_brightness = 1.0 + HIGH_BRIGHTNESS * g
	if _graded_env.glow_enabled:
		if _glow_base.x < 0.0:
			_glow_base = Vector2(_graded_env.glow_intensity, _graded_env.glow_bloom)
		_graded_env.glow_intensity = _glow_base.x + HIGH_GLOW_INTENSITY * g
		_graded_env.glow_bloom = _glow_base.y + HIGH_BLOOM * g

## A line that doesn't stop the game: what a guard says over his shoulder, or what goes through your head.
## "bark": a card with the speaker's name; "thought": bigger, no card, held longer (inner monologue).
var _sub: Label
var _sub_t := 0.0
var _sub_len := 1.0

func show_subtitle(text: String, secs := 2.5, kind := "line", speaker := "") -> void:
	if _sub == null:
		_sub = Label.new()
		_sub.name = "Subtitle"
		_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sub.anchor_left = 0.5
		_sub.anchor_right = 0.5
		_sub.anchor_top = 0.76
		_sub.anchor_bottom = 0.76
		_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_sub.grow_vertical = Control.GROW_DIRECTION_BOTH
		_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_sub)
	if kind == "thought":
		UiStyle.style_label(_sub, UiStyle.BODY_SEMI, 30, UiStyle.PAPER, 0)
		_sub.add_theme_constant_override("outline_size", 8)
		_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_sub.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_sub.text = text
	else:
		UiStyle.style_label(_sub, UiStyle.BODY_SEMI, 24, UiStyle.PAPER, 0)
		_sub.add_theme_constant_override("outline_size", 0)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.045, 0.048, 0.056, 0.84)
		box.border_color = UiStyle.AMBER
		box.border_width_left = 3
		box.set_corner_radius_all(4)
		box.content_margin_left = 16
		box.content_margin_right = 18
		box.content_margin_top = 4
		box.content_margin_bottom = 6
		_sub.add_theme_stylebox_override("normal", box)
		_sub.text = ("%s:  \"%s\"" % [speaker, text]) if speaker != "" else text
	_sub_t = secs
	_sub_len = secs
	_sub.visible = true
	_sub.reset_size()

func _tick_subtitle(delta: float) -> void:
	if _sub == null or not _sub.visible:
		return
	_sub_t -= delta
	_sub.modulate.a = clampf(minf(_sub_t, _sub_len - _sub_t) / 0.35, 0.0, 1.0)
	if _sub_t <= 0.0:
		_sub.visible = false

func _process(delta: float) -> void:
	_update_sick_grade()
	_update_high()
	_tick_subtitle(delta)
	_tick_fade(delta)
	if objective_label and not Cutscene.is_playing() and not get_tree().paused:
		_tick_objective(delta)
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

func _on_day_or_strikes_changed(_value: int = 0) -> void:
	_update_day()

func _on_clock_changed(_minute: int) -> void:
	_update_clock()
	_update_debt()
	_update_status()

func _update_status() -> void:
	if status_label == null:
		return
	var s: Array = GameState.status_line()
	status_label.visible = not s.is_empty()
	if s.is_empty():
		return
	status_label.text = s[0]
	status_label.add_theme_color_override("font_color", Color(1.0, 0.36, 0.3) if s[1] else UiStyle.AMBER)

func _on_debt_changed(_amount: int) -> void:
	_update_debt()

func _update_debt() -> void:
	if debt_label == null:
		return
	debt_label.visible = GameState.debt > 0
	if GameState.debt_overdue():
		debt_label.text = "OWE $%d -- OVERDUE" % GameState.debt
		debt_label.add_theme_color_override("font_color", Color(1.0, 0.36, 0.3))
	else:
		debt_label.text = "Owe $%d, due %s" % [GameState.debt, GameState.debt_due_text()]
		debt_label.add_theme_color_override("font_color", Color(0.95, 0.68, 0.5))

func _update_clock() -> void:
	clock_label.text = GameState.clock_text()
	clock_label.add_theme_color_override("font_color", CLOCK_NIGHT_COLOR.lerp(CLOCK_DAY_COLOR, GameState.daylight()))

var _last_cash := -1

func _update_cash(cash: int) -> void:
	cash_label.text = "$%d" % cash
	if _last_cash >= 0 and cash != _last_cash and is_inside_tree():
		_cash_pop(cash - _last_cash)
	_last_cash = cash

## "+$5" in green or "-$5" in red, floating up off the cash, and the cash
## itself giving a little bump.
func _cash_pop(delta: int) -> void:
	var l := Label.new()
	l.text = ("+$%d" if delta > 0 else "-$%d") % absi(delta)
	UiStyle.style_label(l, UiStyle.COND_BOLD, 26, Color(0.55, 0.95, 0.5) if delta > 0 else Color(1.0, 0.45, 0.4), 1)
	l.position = Vector2(cash_label.position.x + cash_label.get_minimum_size().x + 12.0, cash_label.position.y + 12.0)
	$TopBar.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 26.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)
	cash_label.pivot_offset = Vector2(0.0, cash_label.size.y * 0.5)
	var bump := cash_label.create_tween()
	bump.tween_property(cash_label, "scale", Vector2.ONE * 1.15, 0.08)
	bump.tween_property(cash_label, "scale", Vector2.ONE, 0.18)

func _update_craving(craving: float) -> void:
	if craving_fill == null:
		return
	var low := craving <= 20.0
	_fill(craving_fill, craving / 100.0, Color(0.9, 0.22, 0.2) if low else CRAVING_COLOR)
	_wake_if_moved("craving", craving)
	if craving <= 35.0:
		wake_soft()
	# Only once you're actually getting sick -- it used to sit at ~20% green
	# over everything at a normal craving, which muddied every colour.
	# Pale and sweaty, not night-vision green: the room has to stay readable.
	withdrawal_tint.color = Color(0.62, 0.62, 0.54, GameState.sickness() * 0.13)
	_set_post_fx(GameState.sickness())

## Getting low on what you crave keeps the meter up (sickness itself already does, past half).
func wake_soft() -> void:
	_awake = maxf(_awake, 1.0)

## Well, the PostFX is only a vignette and grain: the lite shader draws
## them over the frame without copying the screen (~3.5 ms on a UHD 620).
## Getting sick swaps in the full one.
const POST_FULL := preload("res://assets/fx/postfx.gdshader")
const POST_LITE := preload("res://assets/fx/postfx_lite.gdshader")

func _set_post_fx(sick: float) -> void:
	var mat := $PostFX.material as ShaderMaterial
	var want: Shader = POST_FULL if (sick > 0.0 or GameState.high_glow() > 0.003) else POST_LITE
	if mat.shader != want:
		mat.shader = want
	mat.set_shader_parameter("sickness", sick)

var _last_inv := 0

func _update_inventory() -> void:
	if inventory_icons == null:
		return
	for child in inventory_icons.get_children():
		inventory_icons.remove_child(child)
		child.queue_free()
	_carry_chip.visible = not GameState.inventory.is_empty()
	if GameState.inventory.is_empty():
		_last_inv = 0
		return
	for id in GameState.inventory:
		if not ResourceLoader.exists(ICON_PATH % id):
			# No rendered icon (the carburetor): its name, small.
			var tag := _text(inventory_icons, GameState.item_name_for(id).trim_prefix("a ").trim_prefix("an "),
				UiStyle.BODY_SEMI, 15, UiStyle.PAPER)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			continue
		var icon := TextureRect.new()
		icon.texture = load(ICON_PATH % id)
		icon.custom_minimum_size = Vector2(CARRY_ICON, CARRY_ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inventory_icons.add_child(icon)
	# Something new in your pockets pops in.
	if GameState.inventory.size() > _last_inv and inventory_icons.get_child_count() > 0:
		# (A container resets its children's scale, so the newest flashes
		# bright and the whole row bumps.)
		var newest := inventory_icons.get_child(inventory_icons.get_child_count() - 1) as Control
		newest.modulate = Color(2.2, 2.0, 1.2)
		newest.create_tween().tween_property(newest, "modulate", Color.WHITE, 0.45)
		inventory_icons.pivot_offset = Vector2(inventory_icons.size.x, inventory_icons.size.y * 0.5)
		inventory_icons.scale = Vector2.ONE * 1.15
		inventory_icons.create_tween().tween_property(inventory_icons, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_last_inv = GameState.inventory.size()

func _update_wanted(is_wanted: bool) -> void:
	wanted_label.visible = is_wanted

## "DAY 4" and the chances left this run as dots, and the clean streak under treatment. Shown together
## because they're the numbers that say how a run is going.
func _update_day() -> void:
	day_label.text = "DAY %d" % GameState.day
	var total: int = GameState.max_strikes()
	if pips:
		pips.set_state(total, clampi(GameState.strikes, 0, total))
	if treatment_label:
		treatment_label.visible = GameState.in_treatment
		treatment_label.text = "CLEAN  %d / %d" % [GameState.treatment_streak, GameState.RECOVERY_DAYS]

## The talking panel in the HUD's own type: Barlow, amber speaker, the same dark card as everything else.
func _style_dialogue() -> void:
	var bg := dialogue_panel.get_node("Bg") as Panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.048, 0.056, 0.9)
	sb.border_color = UiStyle.AMBER
	sb.border_width_left = 4
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 10
	bg.add_theme_stylebox_override("panel", sb)
	portrait_frame.color = Color(1, 1, 1, 0.14)
	UiStyle.style_label(speaker_label, UiStyle.COND_BOLD, 26, UiStyle.AMBER, 3)
	UiStyle.style_label(text_label, UiStyle.BODY, 20, UiStyle.PAPER)
	# Room for four lines of it (the walkman's menu is one) and the hint under them.
	dialogue_panel.offset_top = 470.0
	bg.offset_bottom = 200.0
	text_label.offset_top = 38.0
	text_label.offset_bottom = 158.0
	hint_label.offset_top = 166.0
	hint_label.offset_bottom = 190.0
	hint_label.remove_theme_stylebox_override("normal")
	UiStyle.style_label(hint_label, UiStyle.BODY_SEMI, 15, UiStyle.MUTED, 1, false)

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
	hint_label.text = "%s  continue" % GameState.control_name("interact")
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
