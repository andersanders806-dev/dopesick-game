extends "res://ui/GlyphLabel.gd"
## The few words over whatever E / Square would use right now: "E  Enter the Dive Bar", with the PlayStation
## button drawn when the pad was last used (ui/GlyphLabel.gd). In first person it sits just under the crosshair,
## otherwise above the thing. The HUD's type and card (ui/UiStyle.gd).

const Prompts := preload("res://ui/Prompts.gd")
const UiStyle := preload("res://ui/UiStyle.gd")
## How far above a thing's origin (m) the prompt floats.
const LIFT := 1.9
## In first person: this far under the centre of the screen (clear of the reticle's ring).
const FP_DROP := 46.0

func _ready() -> void:
	name = "InteractPrompt"
	super._ready()
	UiStyle.style_label(self, UiStyle.BODY_SEMI, 22, UiStyle.PAPER, 0)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A dark card with the accent down its left edge, like the objective chip.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.045, 0.048, 0.056, 0.84)
	box.border_color = UiStyle.AMBER
	box.border_width_left = 3
	box.set_corner_radius_all(4)
	box.content_margin_left = 16
	box.content_margin_right = 18
	box.content_margin_top = 6
	box.content_margin_bottom = 8
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 6
	add_theme_stylebox_override("normal", box)
	visible = false

## The glyph is laid out as if the text started at the label's edge; the card's top padding pushes it down.
func _place() -> void:
	super._place()
	var pad := get_theme_stylebox("normal").content_margin_top if has_theme_stylebox_override("normal") else 0.0
	for g in glyphs:
		if is_instance_valid(g):
			(g as Control).position.y += pad

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
	markup = "{interact}  %s" % what
	size = Vector2.ZERO
	var at: Vector2
	var screen := get_viewport().get_visible_rect().size
	if Graphics.first_person:
		at = Vector2(screen.x * 0.5, screen.y * 0.5 + FP_DROP + size.y * 0.5)
	else:
		var p := target.global_position + Vector3(0, LIFT, 0)
		if cam.is_position_behind(p):
			visible = false
			return
		at = cam.unproject_position(p)
	position = (at - size * 0.5 + Vector2(0, RISE * (1.0 - k))).round()
	visible = true
