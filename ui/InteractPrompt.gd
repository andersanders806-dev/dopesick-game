extends Label
## The few words over whatever E / Square would use right now: "E  Enter
## the Dive Bar". In first person it sits under the crosshair instead.

const Prompts := preload("res://ui/Prompts.gd")
## How far above a thing's origin (m) the prompt floats.
const LIFT := 1.9

func _ready() -> void:
	name = "InteractPrompt"
	add_theme_font_size_override("font_size", 17)
	add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("outline_size", 5)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A dark pill with the accent down its left edge, like the arrival card.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.035, 0.05, 0.72)
	box.border_color = Color(0.93, 0.35, 0.55)
	box.border_width_left = 3
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 5
	add_theme_stylebox_override("normal", box)
	visible = false

## Each new thing to use eases in: a fade and a short rise.
const EASE_IN := 0.18
const RISE := 8.0
var _target: Node3D
var _shown := 0.0

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var target: Node3D = null
	if player and not player.dialogue_active and not get_tree().paused and not SceneLoader.busy():
		target = player._nearest_interactable()
	var what := Prompts.text_for(target)
	var cam := get_viewport().get_camera_3d()
	if what == "" or cam == null:
		visible = false
		_target = null
		return
	if target != _target:
		_target = target
		_shown = 0.0
	_shown = minf(_shown + delta / EASE_IN, 1.0)
	var k := 1.0 - pow(1.0 - _shown, 3.0)
	modulate.a = k
	text = "%s  %s" % [GameState.control_name("interact"), what]
	size = Vector2.ZERO
	var at: Vector2
	var screen := get_viewport().get_visible_rect().size
	if Graphics.first_person:
		at = Vector2(screen.x * 0.5, screen.y * 0.62)
	else:
		var p := target.global_position + Vector3(0, LIFT, 0)
		if cam.is_position_behind(p):
			visible = false
			return
		at = cam.unproject_position(p)
	position = (at - size * 0.5 + Vector2(0, RISE * (1.0 - k))).round()
	visible = true
