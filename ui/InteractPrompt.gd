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
	visible = false

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var target: Node3D = null
	if player and not player.dialogue_active and not get_tree().paused and not SceneLoader.busy():
		target = player._nearest_interactable()
	var what := Prompts.text_for(target)
	var cam := get_viewport().get_camera_3d()
	if what == "" or cam == null:
		visible = false
		return
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
	position = (at - size * 0.5).round()
	visible = true
