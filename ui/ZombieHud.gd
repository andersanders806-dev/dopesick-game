extends CanvasLayer
## Dead Block's HUD: the round in blood red bottom-left, your points above
## it with what each hit paid floating up beside them, and the round's name
## across the screen as it starts. Added by world/ZombieBlock.gd; the
## story's HUD is hidden beneath.

const BLOOD := Color(0.72, 0.08, 0.08)
const PAPER := Color(0.93, 0.9, 0.82)
const POP_TIME := 1.1

var round_label: Label
var points_label: Label
var banner: Label
var _pops: Control

func _ready() -> void:
	add_to_group("zombie_hud")
	layer = 12
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/Bungee-Regular.ttf")
	round_label = _label(font, 64, BLOOD, Vector2(28, 590))
	points_label = _label(font, 30, PAPER, Vector2(32, 552))
	_pops = Control.new()
	_pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pops.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pops)
	banner = _label(font, 72, BLOOD, Vector2(0, 150))
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.modulate.a = 0.0
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
