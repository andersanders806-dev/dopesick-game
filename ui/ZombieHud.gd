extends CanvasLayer
## Dead Block's HUD: the round in blood red bottom-left, your points above
## it with what each hit paid floating up beside them, and the round's name
## across the screen as it starts; bottom-right the gun in your hands (name,
## mag and reserve); over the middle what E would do (a wall gun, the box) and
## a line when something didn't go through. Added by world/ZombieBlock.gd; the
## story's HUD is hidden beneath.

const BLOOD := Color(0.72, 0.08, 0.08)
const PAPER := Color(0.93, 0.9, 0.82)
const POP_TIME := 1.1

var round_label: Label
var points_label: Label
var banner: Label
var ammo_label: Label
var gun_label: Label
var prompt: Label
var message: Label
var _pops: Control
var _message_tween: Tween
var _holder: Node

func _ready() -> void:
	add_to_group("zombie_hud")
	layer = 12
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/Bungee-Regular.ttf")
	# Pinned to the bottom-left corner and growing up and right, so a long
	# round or points number never runs off the window.
	round_label = _label(font, 64, BLOOD, Vector2.ZERO)
	_pin_bottom_left(round_label, 28.0, 24.0)
	points_label = _label(font, 30, PAPER, Vector2.ZERO)
	_pin_bottom_left(points_label, 32.0, 100.0)
	_pops = Control.new()
	_pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pops.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pops)
	# The full width of the window, text centred in it.
	banner = _label(font, 72, BLOOD, Vector2.ZERO)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 150.0
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	# The gun: pinned to the bottom-right corner, growing up and left.
	ammo_label = _label(font, 56, PAPER, Vector2.ZERO)
	_pin_bottom_right(ammo_label, 32.0, 24.0)
	gun_label = _label(font, 22, BLOOD, Vector2.ZERO)
	_pin_bottom_right(gun_label, 34.0, 96.0)
	# What E does, low in the middle; a word of refusal above it.
	prompt = _label(font, 24, PAPER, Vector2.ZERO)
	_pin_bottom_centre(prompt, 190.0)
	message = _label(font, 28, BLOOD, Vector2.ZERO)
	_pin_bottom_centre(message, 240.0)
	message.modulate.a = 0.0
	ZombieMode.round_started.connect(_on_round_started)
	ZombieMode.points_changed.connect(_on_points_changed)
	ZombieMode.game_over_started.connect(_on_game_over)
	_refresh()

func _label(font: Font, size: int, color: Color, at: Vector2) -> Label:
	var l := Label.new()
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 8)
	add_child(l)
	return l

func _pin_bottom_left(l: Label, left: float, bottom: float) -> void:
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	l.offset_left = left
	l.offset_right = left
	l.offset_top = -bottom
	l.offset_bottom = -bottom
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.grow_horizontal = Control.GROW_DIRECTION_END

## Pinned to the bottom-right corner, growing up and left.
func _pin_bottom_right(l: Label, right: float, bottom: float) -> void:
	l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	l.offset_left = -right
	l.offset_right = -right
	l.offset_top = -bottom
	l.offset_bottom = -bottom
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN

## The width of the window along the bottom edge, `bottom` px up, text centred
## in it (so a long line can't run off either side).
func _pin_bottom_centre(l: Label, bottom: float) -> void:
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -bottom - 30.0
	l.offset_bottom = -bottom
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func _process(_delta: float) -> void:
	_update_gun()
	_update_prompt()

func _update_gun() -> void:
	if not is_instance_valid(_holder):
		_holder = get_tree().get_first_node_in_group("weapon_holder")
	var d = _holder.current if _holder != null else null
	if d == null:
		ammo_label.text = ""
		gun_label.text = ""
		return
	var low: bool = _holder.mag <= maxi(d.mag_size / 4, 1)
	ammo_label.text = "%d / %d" % [_holder.mag, _holder.reserve]
	ammo_label.add_theme_color_override("font_color", BLOOD if low else PAPER)
	gun_label.text = String(d.display_name).to_upper() + ("  RELOADING" if _holder.reloading else "")

func _update_prompt() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var text := ""
	if player != null and not player.dialogue_active and not get_tree().paused:
		var target = player._nearest_interactable()
		if target != null and target.has_method("prompt_text"):
			text = target.prompt_text()
	prompt.text = "%s  %s" % [GameState.control_name("interact"), text] if text != "" else ""

## A line of refusal or news over the prompt ("Not enough points"), gone in a moment.
func say(text: String) -> void:
	message.text = text
	message.modulate.a = 1.0
	if _message_tween != null:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(1.2)
	_message_tween.tween_property(message, "modulate:a", 0.0, 0.6)

func _refresh() -> void:
	round_label.text = str(ZombieMode.round)
	points_label.text = str(ZombieMode.points)

func _on_round_started(r: int) -> void:
	_refresh()
	banner.text = "ROUND %d" % r
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.8)
	tw.tween_property(banner, "modulate:a", 0.0, 1.0)

func _on_points_changed(_total: int, amount: int, _reason: String) -> void:
	_refresh()
	var pop := Label.new()
	pop.text = "%+d" % amount
	pop.position = points_label.position + Vector2(points_label.get_minimum_size().x + 14.0, 6.0)
	pop.add_theme_font_size_override("font_size", 22)
	pop.add_theme_color_override("font_color", PAPER if amount > 0 else BLOOD)
	pop.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	pop.add_theme_constant_override("outline_size", 5)
	_pops.add_child(pop)
	var tw := create_tween().set_parallel()
	tw.tween_property(pop, "position:y", pop.position.y - 34.0, POP_TIME)
	tw.tween_property(pop, "modulate:a", 0.0, POP_TIME)
	tw.chain().tween_callback(pop.queue_free)

func _on_game_over(_summary: Dictionary) -> void:
	visible = false
