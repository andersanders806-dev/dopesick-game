extends "res://ui/GlyphLabel.gd"
## The warning over a cough coming on: "Q  Hold it in" (or the pad's L2), in the interact prompt's card.
## While it is held back, a thin bar along the bottom of the card runs down -- how long it will hold.
## Shown only while a tell or a hold is actually on (player/SickBursts.gd): it never claims anything
## that is not happening.

const UiStyle := preload("res://ui/UiStyle.gd")
## Where on the screen: a third of the way up from the bottom.
const FROM_BOTTOM := 0.30

var _bursts: Node
var _left := 0.0

func _ready() -> void:
	name = "StifleHint"
	super._ready()
	UiStyle.style_label(self, UiStyle.BODY_SEMI, 22, UiStyle.PAPER, 0)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.045, 0.048, 0.056, 0.84)
	box.border_color = Color(1.0, 0.36, 0.3)
	box.border_width_left = 3
	box.set_corner_radius_all(4)
	box.content_margin_left = 16
	box.content_margin_right = 18
	box.content_margin_top = 6
	box.content_margin_bottom = 12
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 6
	add_theme_stylebox_override("normal", box)
	visible = false

func _place() -> void:
	super._place()
	var pad := get_theme_stylebox("normal").content_margin_top if has_theme_stylebox_override("normal") else 0.0
	for g in glyphs:
		if is_instance_valid(g):
			(g as Control).position.y += pad

func _process(_delta: float) -> void:
	if _bursts == null or not is_instance_valid(_bursts):
		var player := get_tree().get_first_node_in_group("player")
		_bursts = player.get("sick_bursts") if player != null else null
		if _bursts == null:
			visible = false
			return
	if not _bursts.warning():
		visible = false
		return
	markup = "{stifle}  Hold it in" if not _bursts.holding() else "{stifle}  Holding it in"
	_left = _bursts.hold_left() / _bursts.HOLD_MAX if _bursts.holding() else 1.0
	size = Vector2.ZERO
	var screen := get_viewport().get_visible_rect().size
	position = (Vector2(screen.x * 0.5, screen.y * (1.0 - FROM_BOTTOM)) - size * 0.5).round()
	visible = true
	queue_redraw()

func _draw() -> void:
	if _bursts == null or not _bursts.holding():
		return
	var w := (size.x - 20.0) * _left
	draw_rect(Rect2(10.0, size.y - 7.0, size.x - 20.0, 3.0), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(10.0, size.y - 7.0, w, 3.0), Color(1.0, 0.36, 0.3, 0.95))
