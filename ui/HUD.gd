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

const TEXT_LEFT_WITH_PORTRAIT := 150.0
const TEXT_LEFT_NO_PORTRAIT := 16.0

const Crosshair := preload("res://ui/Crosshair.gd")
const PauseMenu := preload("res://ui/PauseMenu.gd")
const HEALTH_BAR_W := 200.0

## --- First-person combat HUD, built in _build_combat_hud() -------------------
var crosshair: Control
var _prompt: Label
var _health_fill: ColorRect
var _health_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _mode_label: Label
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _toast: Label
var _fps_label: Label
var _damage_flash: float = 0.0
var _toast_t: float = 0.0
var _pause_menu: CanvasLayer

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 0.75));
	float v = smoothstep(0.22, 0.72, d);
	COLOR = vec4(0.55, 0.0, 0.0, v * intensity);
}
"""

func _ready() -> void:
	add_to_group("hud")
	GameState.cash_changed.connect(_update_cash)
	GameState.craving_changed.connect(_update_craving)
	GameState.inventory_changed.connect(_update_inventory)
	GameState.wanted_changed.connect(_update_wanted)
	GameState.day_changed.connect(func(_d): _update_day())
	GameState.strikes_changed.connect(func(_s): _update_day())
	GameState.run_ended.connect(_show_run_end)
	_update_day()
	_update_cash(GameState.cash)
	_update_craving(GameState.craving)
	_update_inventory()
	_update_wanted(GameState.wanted)
	dialogue_panel.visible = false
	busted_overlay.visible = false
	_build_combat_hud()
	GameState.health_changed.connect(_update_health)
	GameState.ammo_changed.connect(_update_ammo)
	GameState.player_damaged.connect(func(amount, _from): _damage_flash = minf(1.0, _damage_flash + amount / 30.0))
	GameState.lethal_changed.connect(func(_l): _update_wanted(GameState.wanted))
	_update_health(GameState.health)
	_update_ammo(GameState.ammo_mag, GameState.ammo_reserve)
	# The pause menu belongs to the room, not the HUD, so hiding the HUD
	# behind the drug menu doesn't hide it too.
	_pause_menu = PauseMenu.new()
	get_parent().add_child.call_deferred(_pause_menu)

func _panel_style() -> StyleBoxFlat:
	return $TopBar/StatsBg.get_theme_stylebox("panel") as StyleBoxFlat

func _anchored(c: Control, anchor: Vector2, offset_rect: Rect2) -> Control:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset_rect.position.x
	c.offset_top = offset_rect.position.y
	c.offset_right = offset_rect.position.x + offset_rect.size.x
	c.offset_bottom = offset_rect.position.y + offset_rect.size.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _hud_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_combat_hud() -> void:
	# Damage vignette sits under everything else.
	_vignette = ColorRect.new()
	_vignette_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vignette_mat.shader = sh
	_vignette.material = _vignette_mat
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	move_child(_vignette, withdrawal_tint.get_index() + 1)

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(crosshair)

	_prompt = _hud_label("", 16, Color(0.95, 0.9, 0.75))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_anchored(_prompt, Vector2(0.5, 0.5), Rect2(-250, 34, 500, 26)))

	_toast = _hud_label("", 15, Color(0.85, 0.78, 0.35))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_anchored(_toast, Vector2(0.5, 1.0), Rect2(-250, -120, 500, 24)))

	# Health, bottom left.
	var hp_bg := Panel.new()
	hp_bg.add_theme_stylebox_override("panel", _panel_style())
	add_child(_anchored(hp_bg, Vector2(0, 1), Rect2(16, -58, HEALTH_BAR_W + 60, 42)))
	_health_label = _hud_label("100", 20, Color(0.92, 0.9, 0.85))
	add_child(_anchored(_health_label, Vector2(0, 1), Rect2(26, -52, 48, 30)))
	var hp_back := ColorRect.new()
	hp_back.color = Color(0.12, 0.12, 0.12, 1)
	add_child(_anchored(hp_back, Vector2(0, 1), Rect2(70, -42, HEALTH_BAR_W, 10)))
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.85, 0.85, 0.8)
	add_child(_anchored(_health_fill, Vector2(0, 1), Rect2(70, -42, HEALTH_BAR_W, 10)))

	# Ammo, bottom right.
	var ammo_bg := Panel.new()
	ammo_bg.add_theme_stylebox_override("panel", _panel_style())
	add_child(_anchored(ammo_bg, Vector2(1, 1), Rect2(-196, -74, 180, 58)))
	_ammo_label = _hud_label("30", 34, Color(0.95, 0.93, 0.88))
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_anchored(_ammo_label, Vector2(1, 1), Rect2(-186, -74, 70, 44)))
	_reserve_label = _hud_label("/ 90", 18, Color(0.6, 0.58, 0.55))
	add_child(_anchored(_reserve_label, Vector2(1, 1), Rect2(-110, -62, 90, 26)))
	_mode_label = _hud_label("AK  ·  AUTO", 11, Color(0.8, 0.68, 0.33))
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_anchored(_mode_label, Vector2(1, 1), Rect2(-186, -34, 160, 16)))

	_fps_label = _hud_label("", 12, Color(0.6, 0.9, 0.6))
	add_child(_anchored(_fps_label, Vector2(1, 0), Rect2(-80, 8, 70, 18)))

	# Busted/Wasted overlay above everything.
	move_child(busted_overlay, get_child_count() - 1)

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("weapon" in player) or player.weapon == null:
		crosshair.visible = false
		_prompt.text = ""
		return
	var w: Node = player.weapon
	# Spread cone half-angle -> pixels at the current FOV.
	var cam: Camera3D = player.camera
	var half_h := get_viewport().get_visible_rect().size.y * 0.5
	var px := tan(deg_to_rad(w.current_spread())) / tan(deg_to_rad(cam.fov * 0.5)) * half_h
	crosshair.gap = 5.0 + px
	crosshair.lines_alpha = clampf(1.0 - w.ads * 1.6, 0.0, 1.0) * (0.0 if player.is_sprinting() else 1.0)
	crosshair.visible = not player.dialogue_active and not player.dead
	var prompt: String = player.interact_prompt()
	_prompt.text = ("[E]  " + prompt) if prompt != "" else ""
	var mode: String = "RELOADING" if w.is_reloading() else w.fire_mode_name()
	_mode_label.text = "AK  ·  %s" % mode
	_damage_flash = maxf(0.0, _damage_flash - delta * 1.4)
	var low := clampf(1.0 - GameState.health / 40.0, 0.0, 1.0)
	_vignette_mat.set_shader_parameter("intensity", clampf(_damage_flash + low * (0.55 + sin(Time.get_ticks_msec() * 0.006) * 0.15), 0.0, 1.0))
	_toast_t = maxf(0.0, _toast_t - delta)
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_fps_label.visible = Settings.show_fps
	if Settings.show_fps:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

func _update_health(hp: float) -> void:
	var frac := clampf(hp / GameState.MAX_HEALTH, 0.0, 1.0)
	_health_fill.size.x = HEALTH_BAR_W * frac
	_health_label.text = str(int(ceil(hp)))
	_health_fill.color = Color(0.85, 0.85, 0.8) if frac > 0.35 else Color(0.85, 0.2, 0.18)

func _update_ammo(mag: int, reserve: int) -> void:
	_ammo_label.text = str(mag)
	_reserve_label.text = "/ %d" % reserve
	_ammo_label.add_theme_color_override("font_color",
		Color(0.9, 0.25, 0.2) if mag <= 5 else Color(0.95, 0.93, 0.88))

func hitmarker(killed: bool, headshot: bool) -> void:
	crosshair.hit(killed, headshot)
	SFX.play("kill_confirm" if killed else "hitmarker", -6.0 if killed else -10.0, 1.0 if not headshot else 1.25)
	if killed:
		toast("HEADSHOT" if headshot else "KILLED")

## A line of feedback above the ammo -- pickups, fire mode, kills.
func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.0

func flash_wasted() -> void:
	($BustedOverlay/Label as Label).text = "WASTED"
	busted_overlay.visible = true

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
		if not ResourceLoader.exists(ICON_PATH % id):
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
	# Stretch the badge to fit the longer armed-response text.
	wanted_label.text = "WANTED  ·  SHOTS FIRED" if GameState.lethal else "WANTED"
	wanted_label.offset_right = wanted_label.offset_left + (330.0 if GameState.lethal else 160.0)

## Day plus how many chances are left this run, e.g. "Day 4  * * o". Shown
## together because they're the two numbers that say how a run is going, and
## it keeps the strike count out of a panel of its own.
func _update_day() -> void:
	var left: int = GameState.max_strikes() - GameState.strikes
	var pips := "*".repeat(max(0, left)) + "o".repeat(max(0, GameState.strikes))
	day_label.text = "Day %d  %s" % [GameState.day, pips]

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
	var hint_width := hint_label.offset_right - hint_label.offset_left
	hint_label.offset_left = text_left
	hint_label.offset_right = text_left + hint_width

	dialogue_panel.visible = true

func advance_or_close_dialogue() -> void:
	SFX.play("blip", -4.0, 0.85)
	dialogue_panel.visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.dialogue_active = false

func flash_busted() -> void:
	($BustedOverlay/Label as Label).text = "BUSTED"
	busted_overlay.visible = true
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(busted_overlay):
		busted_overlay.visible = false
