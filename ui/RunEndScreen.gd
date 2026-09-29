extends CanvasLayer
## Shown when a run ends: what the run was worth, and what you can buy with
## it before starting over.
##
## Built in code rather than as a .tscn because the upgrade list is driven by
## MetaProgress.UPGRADES -- adding an upgrade there should make a row appear
## here with no scene editing.

const PANEL_W := 720.0
const ROW_H := 54.0

var _summary: Dictionary = {}
var _rows: Array = []
var _know_how_label: Label
## The in-game HUD, hidden while this is up and restored if it outlives us.
var _hud: CanvasLayer

func show_summary(summary: Dictionary) -> void:
	_summary = summary
	# Show how it ended before the numbers. This node sits on the tree root,
	# so it outlives the scene change to the jail that a final bust triggers
	# while the cutscene is still playing.
	await Cutscene.play(_cutscene_id())
	_build()

func _cutscene_id() -> String:
	match _summary.get("cause", "busted"):
		"overdose":
			return "overdose"
		"recovered":
			return "recovered"
	return "sent_away"

func _build() -> void:
	layer = 100
	# The gameplay HUD would otherwise show through the overlay.
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud:
		_hud.visible = false

	# The cutscene's last still stays behind the summary, heavily dimmed.
	var scene: Array = Cutscene.SCENES[_cutscene_id()]
	var backdrop_tex := Cutscene.art_for(scene[scene.size() - 1]["image"])
	if backdrop_tex:
		var backdrop := TextureRect.new()
		backdrop.texture = backdrop_tex
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_fill_screen(backdrop)
		add_child(backdrop)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.86 if backdrop_tex else 0.94)
	_fill_screen(shade)
	# The overlay eats input so the player can't walk around behind it.
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	# Everything lives inside a full-screen margin box rather than a centred
	# fixed-size column: the upgrade list grows as upgrades are added, and a
	# centred column silently pushes its title off the top of the screen and
	# its "Start over" button off the bottom once it outgrows the window.
	var margin := MarginContainer.new()
	_fill_screen(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	# There are two ways to lose, and they should not read the same.
	if _summary.get("cause", "busted") == "recovered":
		root.add_child(_heading("YOU GOT OUT", 30, Color(0.55, 0.85, 0.6)))
		root.add_child(_heading("Five days in the program, clean. Not cured -- out. This is what the other endings were keeping from you.",
			14, Color(0.62, 0.60, 0.56)))
	elif _summary.get("cause", "busted") == "overdose":
		root.add_child(_heading("YOU WENT OVER", 30, Color(0.80, 0.30, 0.55)))
		root.add_child(_heading("Nobody had naloxone. This is how most runs really end.",
			14, Color(0.62, 0.60, 0.56)))
	else:
		root.add_child(_heading("PICKED UP AGAIN", 30, Color(0.85, 0.25, 0.22)))
		root.add_child(_heading("That's %d strikes. You're going away for a while." % _summary.get("strikes", 0),
			14, Color(0.62, 0.60, 0.56)))
	root.add_child(_spacer(6))

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stats.custom_minimum_size = Vector2(PANEL_W, 0)
	stats.add_child(_stat("Days survived", str(_summary.get("days", 0))))
	stats.add_child(_stat("Orders delivered", str(_summary.get("orders", 0))))
	stats.add_child(_stat("Cash earned", "$%d" % _summary.get("cash", 0)))
	stats.add_child(_stat("Doses taken", str(_summary.get("doses", 0))))
	stats.add_child(_stat("Know-How earned", "+%d" % _summary.get("know_how", 0), Color(0.85, 0.78, 0.35)))
	root.add_child(stats)
	root.add_child(_spacer(6))

	_know_how_label = _heading("", 17, Color(0.85, 0.78, 0.35))
	root.add_child(_know_how_label)
	root.add_child(_heading("What you picked up, you keep.", 12, Color(0.55, 0.53, 0.50)))
	root.add_child(_spacer(4))

	# The list scrolls, so however many upgrades exist the buttons below it
	# stay on screen.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	root.add_child(scroll)

	for id in MetaProgress.UPGRADES:
		var row := _upgrade_row(id)
		_rows.append(row)
		list.add_child(row["node"])

	root.add_child(_spacer(6))
	var start := Button.new()
	start.text = "Start over"
	start.custom_minimum_size = Vector2(0, 38)
	start.pressed.connect(_on_start_over)
	root.add_child(start)

	_refresh()

## Anchors a control to the whole viewport. set_anchors_preset alone leaves
## the offsets wherever they were, which on a bare CanvasLayer child means a
## zero-sized control that draws nothing.
func _fill_screen(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

func _heading(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _stat(label: String, value: String, color := Color(0.80, 0.78, 0.74)) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Color(0.58, 0.56, 0.53))
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", color)
	row.add_child(l)
	row.add_child(v)
	return row

## One upgrade: name, what it does, tier pips, and a buy button.
func _upgrade_row(id: String) -> Dictionary:
	var info: Dictionary = MetaProgress.UPGRADES[id]
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, ROW_H)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	box.add_child(inner)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 15)
	var desc := Label.new()
	desc.text = info["desc"]
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.55, 0.53, 0.50))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	text.add_child(desc)
	inner.add_child(text)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(140, 34)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(_on_buy.bind(id))
	inner.add_child(buy)

	return {"node": box, "id": id, "title": title, "buy": buy}

func _on_buy(id: String) -> void:
	if MetaProgress.buy(id):
		SFX.play("cash", -6.0, 1.0)
		_refresh()

## Repaints every row against current Know-How, so buying one upgrade
## immediately greys out anything the rest of the balance can't cover.
func _refresh() -> void:
	_know_how_label.text = "Know-How: %d" % MetaProgress.know_how
	for row in _rows:
		var id: String = row["id"]
		var info: Dictionary = MetaProgress.UPGRADES[id]
		var t := MetaProgress.tier(id)
		var pips := "*".repeat(t) + "-".repeat(int(info["max_tier"]) - t)
		row["title"].text = "%s   [%s]" % [info["name"], pips]
		var buy: Button = row["buy"]
		if MetaProgress.is_maxed(id):
			buy.text = "Maxed"
			buy.disabled = true
		else:
			buy.text = "Buy  %d" % MetaProgress.next_cost(id)
			buy.disabled = not MetaProgress.can_afford(id)

func _on_start_over() -> void:
	GameState.start_run()
	if _hud and is_instance_valid(_hud):
		_hud.visible = true
	queue_free()
	get_tree().change_scene_to_file("res://world/Apartment3D.tscn")
