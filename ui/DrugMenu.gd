extends CanvasLayer
## What the pusher has on him tonight, and what each one costs *you* --
## prices move with the tolerance you've built, so the longer a run goes the
## worse this screen looks.
##
## Built in code, like ui/RunEndScreen.gd, so adding an entry to
## Drugs.CATALOGUE makes a row appear with no scene editing.

signal chosen(drug_id: String)
signal cancelled

const ROW_H := 62.0

var _stock: Array = []
var _hud: CanvasLayer

## `stock` is the subset of Drugs.CATALOGUE ids he's actually holding.
func open_with(stock: Array) -> void:
	_stock = stock
	_build()

func _build() -> void:
	layer = 90
	# Frees the mouse from the first-person camera while this is up.
	add_to_group("modal_ui")
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud:
		_hud.visible = false

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.9)
	_fill(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var margin := MarginContainer.new()
	_fill(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	root.add_child(_label("\"What do you need?\"", 24, Color(0.82, 0.80, 0.76), true))
	root.add_child(_label("You have $%d." % GameState.cash, 14, Color(0.60, 0.58, 0.55), true))
	root.add_child(_spacer(6))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	root.add_child(scroll)

	for id in _stock:
		list.add_child(_row(id))

	root.add_child(_spacer(6))
	var leave := Button.new()
	leave.text = "Walk away"
	leave.custom_minimum_size = Vector2(0, 36)
	leave.pressed.connect(_on_cancel)
	root.add_child(leave)

func _row(id: String) -> Control:
	var d: Dictionary = Drugs.info(id)
	var cost: int = GameState.price_of(id)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, ROW_H)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	box.add_child(inner)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("%s  (%s)" % [d["name"], d["street"]], 15, Color(0.84, 0.82, 0.78), false)
	var desc := _label(d["desc"], 12, Color(0.55, 0.53, 0.50), false)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	text.add_child(desc)
	inner.add_child(text)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(120, 34)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.text = "$%d" % cost
	buy.disabled = GameState.cash < cost
	buy.pressed.connect(func(): _on_pick(id))
	inner.add_child(buy)
	return box

func _label(text: String, size: int, color: Color, centered: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _fill(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

func _close() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.visible = true
	queue_free()

func _on_pick(id: String) -> void:
	chosen.emit(id)
	_close()

func _on_cancel() -> void:
	cancelled.emit()
	_close()
