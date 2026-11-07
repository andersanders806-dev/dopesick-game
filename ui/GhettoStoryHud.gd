extends CanvasLayer
## Ghetto Wars' story on the screen (fx/GhettoStory.gd drives it): the chapter card in the HUD's Bungee, burner-phone
## texts that slide in from the right (sender, time, a typing indicator), the crew's radio along the bottom, a police
## scanner chip top left that types itself out, the objective with the flush bar and the escape clock, the two-way choice
## (dump or sell), and the ending cards (BUSTED with the cuffs closing under a red and blue strobe).
## Everything animates in real time (it ignores Engine.time_scale, so the slow-mo of the cuffs does not slow the HUD).

signal choice_picked(option: String)
signal ending_dismissed

const BLOOD := Color(0.78, 0.08, 0.08)
const PAPER := Color(0.93, 0.9, 0.82)
const DIM := Color(0.6, 0.58, 0.54)
const AMBER := Color(1.0, 0.72, 0.2)
const UiStyle := preload("res://ui/UiStyle.gd")
const PHONE_W := 340.0
const PHONE_TOP := 200.0
const PHONE_HOLD := 3.5  ## a text waits this long (at most) while a centre card is up
const SCAN_W := 300.0
const CARD_TIME := 2.6
const ANN_GAP := 0.15
const MAX_PHONES := 2

var font: FontVariation
var mono: SystemFont
var root: Control

## State the tests read.
var cards_shown: Array[String] = []
var texts_shown: Array[String] = []
var radio_text := ""
var scanner_texts: Array[String] = []
var objective_text := ""
var choice_active := false
var choice_options: Array = []
var ending_key := ""
var flush_shown := 0.0
var timer_shown := -1.0

var _now := 0.0
var _card: Control
var _card_kicker: Label
var _card_title: Label
var _card_ghost: Label
var _card_sub: Label
var _card_place: Label
var _card_tween: Tween
var _phones: Array[Dictionary] = []
var _radio: Control
var _radio_name: Label
var _radio_line: Label
var _radio_dot: ColorRect
var _radio_bar: ColorRect
var _radio_hold := 0.0
var _scan: PanelContainer
var _scan_head: Label
var _scan_dot: ColorRect
var _scan_body: Label
var _scan_age := 99.0
var _scan_len := 0
var _scan_life := 0.0
var _ann_q: Array[Dictionary] = []
var _ann_cur := {}
var _ann_t := 0.0
var _ann_gap := 0.0
var _obj: Label
var _obj_bar: Control
var _obj_fill: ColorRect
var _prompt: Label
var _timer: Label
var _choice: Control
var _choice_fill: ColorRect
var _choice_cards: Array[Control] = []
var _end: Control
var _end_age := 0.0
var _end_tone := ""
var _end_strobe: ColorRect
var _cuffs: Control
var _end_ready := false

func _ready() -> void:
	layer = 14
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ghetto_story_hud")
	font = FontVariation.new()
	font.base_font = load("res://assets/fonts/Bungee-Regular.ttf")
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "monospace"])
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_card()
	_build_radio()
	_build_scanner()
	_build_objective()

func _label(size: int, color: Color, parent: Node = null, f: Font = null) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", f if f != null else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(l)
	return l

func _tween() -> Tween:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	return t

func _vp() -> Vector2:
	return root.size if root != null and root.size.x > 10.0 else Vector2(1280, 720)

# --- chapter card ------------------------------------------------------------------------------

func _build_card() -> void:
	_card = Control.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	root.add_child(_card)
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.74)
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.3
	band.anchor_bottom = 0.7
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(band)
	for a in [0.3, 0.7]:
		var line := ColorRect.new()
		line.color = BLOOD
		line.anchor_left = 0.0
		line.anchor_right = 1.0
		line.anchor_top = a
		line.anchor_bottom = a
		line.offset_top = -2.0
		line.offset_bottom = 2.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(line)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.anchor_top = 0.3
	box.anchor_bottom = 0.7
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)
	_card_kicker = _label(26, BLOOD, box)
	_card_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 110)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)
	_card_ghost = _label(92, Color(0.75, 0.05, 0.05, 0.8), holder)
	_card_title = _label(92, PAPER, holder)
	for l in [_card_ghost, _card_title]:
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_sub = _label(22, PAPER, box)
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_place = _label(15, DIM, box, mono)
	_card_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func show_chapter(num: int, title: String, sub: String, place: String) -> void:
	cards_shown.append(title)
	announce("chapter", CARD_TIME, _play_chapter.bind(num, title, sub, place), _stop_chapter)

func _play_chapter(num: int, title: String, sub: String, place: String) -> void:
	_card_kicker.text = "CHAPTER %d" % num
	_card_title.text = title
	_card_ghost.text = title
	_card_sub.text = sub
	_card_place.text = place.to_upper()
	_card_title.visible_ratio = 0.0
	_card_ghost.visible_ratio = 0.0
	_stop_chapter()
	_card.modulate.a = 0.0
	_card_tween = _tween()
	_card_tween.tween_property(_card, "modulate:a", 1.0, 0.25)
	_card_tween.tween_property(_card_title, "visible_ratio", 1.0, 0.5)
	_card_tween.parallel().tween_property(_card_ghost, "visible_ratio", 1.0, 0.5)
	_card_tween.tween_interval(1.4)
	_card_tween.tween_property(_card, "modulate:a", 0.0, 0.4)

func _stop_chapter() -> void:
	if _card_tween != null:
		_card_tween.kill()
		_card_tween = null

# --- announcements -----------------------------------------------------------------------------
# One queue for everything that takes the middle of the screen (chapter card, the wave banner that GangHud hands over):
# one at a time, the next waits for the last to fade. A chapter jumps ahead of waiting banners, and it replaces a
# banner that has only just started (a chapter that opens with a wave).

## `play` starts the item (it fades itself out inside `dur`); `stop` cuts it short if a chapter pre-empts it.
func announce(kind: String, dur: float, play: Callable, stop := Callable()) -> void:
	var it := {"kind": kind, "dur": dur, "play": play, "stop": stop}
	if kind == "chapter":
		if not _ann_cur.is_empty() and _ann_cur["kind"] != "chapter" and _ann_t < 0.8:
			_end_announcement(true)
		var at := 0
		while at < _ann_q.size() and _ann_q[at]["kind"] == "chapter":
			at += 1
		_ann_q.insert(at, it)
	else:
		_ann_q.append(it)

## A chapter card is up or waiting: texts hold off (the wave banner sits above the phone, they do not collide).
func centre_busy() -> bool:
	if not _ann_cur.is_empty() and _ann_cur["kind"] == "chapter":
		return true
	for it in _ann_q:
		if it["kind"] == "chapter":
			return true
	return false

func _end_announcement(cut: bool) -> void:
	if cut and _ann_cur.has("stop") and (_ann_cur["stop"] as Callable).is_valid():
		(_ann_cur["stop"] as Callable).call()
	_ann_cur = {}
	_ann_gap = ANN_GAP

func _step_announcements(dt: float) -> void:
	if not _ann_cur.is_empty():
		_ann_t += dt
		if _ann_t >= float(_ann_cur["dur"]):
			_end_announcement(false)
	elif _ann_gap > 0.0:
		_ann_gap -= dt
	elif not _ann_q.is_empty():
		_ann_cur = _ann_q.pop_front()
		_ann_t = 0.0
		(_ann_cur["play"] as Callable).call()

# --- phone -------------------------------------------------------------------------------------

func show_text(_from: String, sender: String, body: String, stamp: String, color: Color) -> void:
	texts_shown.append(body)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(PHONE_W, 0)
	p.size = Vector2(PHONE_W, 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.08, 0.94)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(2)
	sb.border_color = Color(color.r, color.g, color.b, 0.7)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var who := _label(14, color, head)
	who.text = "✉ " + sender
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := _label(12, DIM, head, mono)
	st.text = stamp
	var bodyl := _label(17, PAPER, vb, mono)
	bodyl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bodyl.custom_minimum_size = Vector2(PHONE_W - 28.0, 0)
	bodyl.text = body
	bodyl.visible_characters = 0
	root.add_child(p)
	var item := {"node": p, "body": bodyl, "stamp": st, "stamp_text": stamp, "len": body.length(), "age": 0.0, "x": PHONE_W + 40.0, "y": PHONE_TOP, "leaving": false, "wait": 0.0,
		"typing": 0.9 + minf(body.length() * 0.004, 0.6)}
	_phones.append(item)
	while _phones.size() > MAX_PHONES:
		_phones[0]["leaving"] = true
		_phones[0]["age"] = maxf(float(_phones[0]["age"]), 99.0)
		break

func _step_phones(dt: float) -> void:
	var vp := _vp()
	var y := PHONE_TOP
	for item in _phones.duplicate():
		var n: Control = item["node"]
		# A centre card is up: the text waits off to the side (but not for ever).
		if centre_busy() and not item["leaving"] and float(item["wait"]) < PHONE_HOLD and float(item["age"]) < 1.0:
			item["wait"] = float(item["wait"]) + dt
			n.visible = false
			continue
		n.visible = true
		item["age"] = float(item["age"]) + dt
		var age: float = item["age"]
		var len_: int = item["len"]
		var typed: float = maxf(0.0, age - float(item["typing"]))
		(item["body"] as Label).visible_characters = clampi(int(typed * 55.0), 0, len_) if age >= float(item["typing"]) else 0
		var hold := float(item["typing"]) + len_ / 55.0 + 4.0 + len_ / 30.0
		if age > hold:
			item["leaving"] = true
		var target_x := PHONE_W + 40.0 if item["leaving"] else 0.0
		item["x"] = lerpf(float(item["x"]), target_x, 1.0 - exp(-12.0 * dt))
		var h := n.get_combined_minimum_size().y
		n.size = Vector2(PHONE_W, h)
		item["y"] = lerpf(float(item["y"]), y, 1.0 - exp(-14.0 * dt))
		n.position = Vector2(vp.x - PHONE_W - UiStyle.SAFE_X + float(item["x"]), float(item["y"]))
		y += h + 10.0
		if item["leaving"] and float(item["x"]) > PHONE_W + 20.0:
			_phones.erase(item)
			n.queue_free()
	# "typing..." in place of the time while the message is being written.
	for item in _phones:
		var st: Label = item["stamp"]
		st.text = ("typing" + ".".repeat(1 + int(_now * 3.0) % 3)) if float(item["age"]) < float(item["typing"]) else String(item["stamp_text"])

# --- radio -------------------------------------------------------------------------------------

func _build_radio() -> void:
	_radio = Control.new()
	_radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio.modulate.a = 0.0
	root.add_child(_radio)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio.add_child(bg)
	_radio_bar = ColorRect.new()
	_radio_bar.color = AMBER
	_radio_bar.size = Vector2(5, 10)
	_radio_bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_radio_bar.offset_right = 5.0
	_radio.add_child(_radio_bar)
	_radio_dot = ColorRect.new()
	_radio_dot.color = BLOOD
	_radio_dot.position = Vector2(18, 15)
	_radio_dot.size = Vector2(9, 9)
	_radio.add_child(_radio_dot)
	_radio_name = _label(16, AMBER, _radio)
	_radio_name.position = Vector2(34, 6)
	_radio_line = _label(22, PAPER, _radio, null)
	_radio_line.remove_theme_font_override("font")
	_radio_line.position = Vector2(34, 32)
	_radio_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func show_radio(who: String, line: String, color: Color) -> void:
	radio_text = line
	_radio_name.text = "RADIO  •  " + who
	_radio_name.add_theme_color_override("font_color", color)
	_radio_bar.color = color
	_radio_line.text = line
	_radio_hold = 2.6 + line.length() * 0.05
	_radio.modulate.a = 1.0

func _step_radio(dt: float) -> void:
	var vp := _vp()
	var w := minf(760.0, vp.x - 40.0)
	_radio_line.custom_minimum_size = Vector2(w - 50.0, 0)
	_radio_line.size = Vector2(w - 50.0, 10)
	var h := 40.0 + _radio_line.get_combined_minimum_size().y
	_radio.size = Vector2(w, h)
	_radio.position = Vector2((vp.x - w) * 0.5, vp.y - 190.0 - h)
	if choice_active:
		# The choice has the screen: the line has been heard, its text steps aside.
		_radio.modulate.a = 0.0
		_radio_hold = 0.0
	elif _radio_hold > 0.0:
		_radio_hold -= dt
		_radio_dot.visible = int(_now * 4.0) % 2 == 0
	else:
		_radio.modulate.a = maxf(0.0, _radio.modulate.a - dt * 2.5)

# --- scanner -----------------------------------------------------------------------------------

func _build_scanner() -> void:
	_scan = PanelContainer.new()
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan.modulate.a = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.04, 0.045, 0.84)
	sb.set_corner_radius_all(5)
	sb.border_width_left = 3
	sb.border_color = AMBER
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 9
	_scan.add_theme_stylebox_override("panel", sb)
	root.add_child(_scan)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	_scan_dot = ColorRect.new()
	_scan_dot.color = AMBER
	_scan_dot.custom_minimum_size = Vector2(7, 7)
	_scan_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scan_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_scan_dot)
	_scan_head = UiStyle.style_label(Label.new(), UiStyle.COND_BOLD, 13, AMBER, 2)
	_scan_head.text = "POLICE SCANNER"
	_scan_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_scan_head)
	_scan_body = UiStyle.style_label(Label.new(), UiStyle.BODY, 16, PAPER)
	_scan_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scan_body.custom_minimum_size = Vector2(SCAN_W - 24.0, 0)
	_scan_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_scan_body)

## A call on the police band: one chip at a time (a new call replaces the old one), typed out, then gone.
func show_scanner(line: String) -> void:
	scanner_texts.append(line)
	_scan_body.text = line
	_scan_body.visible_characters = 0
	_scan_len = line.length()
	_scan_age = 0.0
	_scan_life = _scan_len / 70.0 + 4.5 + _scan_len / 30.0

func _step_scanner(dt: float) -> void:
	var vp := _vp()
	var w := minf(SCAN_W, vp.x * 0.3)
	_scan_body.custom_minimum_size = Vector2(w - 24.0, 0)
	_scan.size = Vector2(w, 10)
	_scan.size = Vector2(w, _scan.get_combined_minimum_size().y)
	_scan.position = Vector2(UiStyle.SAFE_X, UiStyle.SAFE_Y)
	_scan_age += dt
	_scan_body.visible_characters = clampi(int(_scan_age * 70.0), 0, _scan_len)
	_scan_dot.modulate.a = 1.0 if _scan_age < _scan_life and int(_now * 3.0) % 2 == 0 else 0.35
	var fade_in := clampf(_scan_age * 6.0, 0.0, 1.0)
	_scan.modulate.a = fade_in if _scan_age < _scan_life else maxf(0.0, 1.0 - (_scan_age - _scan_life) * 2.5)

# --- objective, flush bar and clock ------------------------------------------------------------

func _build_objective() -> void:
	_obj = _label(22, PAPER, root)
	_obj.anchor_left = 0.0
	_obj.anchor_right = 1.0
	_obj.offset_top = 22.0
	_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer = _label(54, BLOOD, root)
	_timer.anchor_left = 0.0
	_timer.anchor_right = 1.0
	_timer.offset_top = 52.0
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.visible = false
	_prompt = _label(24, PAPER, root)
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	_obj_bar = Control.new()
	_obj_bar.anchor_left = 0.5
	_obj_bar.anchor_right = 0.5
	_obj_bar.anchor_top = 0.5
	_obj_bar.anchor_bottom = 0.5
	_obj_bar.offset_left = -170.0
	_obj_bar.offset_right = 170.0
	_obj_bar.offset_top = 38.0
	_obj_bar.offset_bottom = 52.0
	_obj_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_obj_bar.visible = false
	root.add_child(_obj_bar)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.7)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_obj_bar.add_child(back)
	_obj_fill = ColorRect.new()
	_obj_fill.color = Color(0.4, 0.85, 1.0)
	_obj_fill.anchor_bottom = 1.0
	_obj_fill.offset_left = 2.0
	_obj_fill.offset_top = 2.0
	_obj_fill.offset_bottom = -2.0
	_obj_bar.add_child(_obj_fill)

func set_objective(t: String) -> void:
	objective_text = t
	_obj.text = t
	_obj.visible = t != ""
	if t != "":
		_obj.scale = Vector2(1.25, 1.25)
		_obj.pivot_offset = Vector2(_vp().x * 0.5, 14)
		_tween().tween_property(_obj, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The flush bar and its prompt (HOLD [E] to flush), shown while you are at the sink or it is filling.
func set_flush(f: float, shown: bool) -> void:
	flush_shown = f
	_obj_bar.visible = shown
	_prompt.visible = shown
	_obj_fill.anchor_right = clampf(f, 0.0, 1.0) * 0.99 + 0.005
	var key := "E"
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("control_name"):
		key = String(gs.control_name("interact"))
	_prompt.text = "HOLD [%s]  FLUSH THE STASH  %d%%" % [key, int(f * 100.0)]

## The escape clock (seconds left); negative hides it.
func set_timer(left: float) -> void:
	timer_shown = left
	_timer.visible = left >= 0.0
	if left >= 0.0:
		_timer.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
		_timer.add_theme_color_override("font_color", BLOOD if left > 20.0 or int(_now * 4.0) % 2 == 0 else PAPER)

func set_clock(t: float) -> void:
	_now = t

# --- choice ------------------------------------------------------------------------------------

func show_choice(id: String, title: String, options: Array, _seconds: float) -> void:
	hide_choice()
	# The messages on the phone have been read: they slide away so the choice has the screen.
	for item in _phones:
		item["age"] = 999.0
	choice_active = true
	choice_options = options
	_choice = Control.new()
	_choice.name = "Choice_" + id
	_choice.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_choice)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice.add_child(dim)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.3
	box.anchor_bottom = 0.3
	box.offset_left = -400.0
	box.offset_right = 400.0
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice.add_child(box)
	var k := _label(18, BLOOD, box)
	k.text = "DECIDE"
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t := _label(48, PAPER, box)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_choice_cards.clear()
	var pad := _using_pad()
	var hints := ["SQUARE", "CIRCLE"] if pad else ["1", "2"]
	var cols := [Color(0.4, 0.85, 0.55), BLOOD]
	for i in options.size():
		var o: Dictionary = options[i]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(380, 150)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.05, 0.06, 0.95)
		sb.set_border_width_all(3)
		sb.border_color = cols[i % 2]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		card.add_theme_stylebox_override("panel", sb)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vb := VBoxContainer.new()
		card.add_child(vb)
		var h := _label(34, cols[i % 2], vb)
		h.text = "[%s]" % hints[i % 2]
		var l := _label(22, PAPER, vb)
		l.text = o["label"]
		var s := _label(15, DIM, vb, mono)
		s.text = o["sub"]
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(340, 0)
		row.add_child(card)
		_choice_cards.append(card)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.7)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(back)
	_choice_fill = ColorRect.new()
	_choice_fill.color = BLOOD
	_choice_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(_choice_fill)
	var note := _label(14, DIM, box, mono)
	note.text = "No answer is an answer."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice.modulate.a = 0.0
	_tween().tween_property(_choice, "modulate:a", 1.0, 0.3)

func set_choice_time(f: float) -> void:
	if _choice_fill != null:
		_choice_fill.anchor_right = clampf(f, 0.0, 1.0)

func hide_choice() -> void:
	choice_active = false
	if _choice != null and is_instance_valid(_choice):
		_choice.queue_free()
	_choice = null
	_choice_fill = null
	_choice_cards.clear()

func _using_pad() -> bool:
	var gs := get_node_or_null("/root/GameState")
	return gs != null and bool(gs.get("using_pad"))

func pick(i: int) -> void:
	if choice_active and i >= 0 and i < choice_options.size():
		choice_picked.emit(String(choice_options[i]["key"]))

func _unhandled_input(ev: InputEvent) -> void:
	if choice_active:
		if ev is InputEventKey and ev.pressed and not ev.echo:
			if ev.keycode == KEY_1 or ev.keycode == KEY_KP_1:
				pick(0)
			elif ev.keycode == KEY_2 or ev.keycode == KEY_KP_2:
				pick(1)
		elif ev is InputEventJoypadButton and ev.pressed:
			if ev.button_index == JOY_BUTTON_X:
				pick(0)
			elif ev.button_index == JOY_BUTTON_B:
				pick(1)
	elif _end_ready and ev.is_action_pressed("interact"):
		_end_ready = false
		ending_dismissed.emit()

# --- endings -----------------------------------------------------------------------------------

func show_ending(key: String, data: Dictionary) -> void:
	ending_key = key
	_end_tone = String(data.get("tone", "dawn"))
	_end_age = 0.0
	_end_ready = false
	if _end != null and is_instance_valid(_end):
		_end.queue_free()
	_end = Control.new()
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_end)
	var bg := TextureRect.new()
	var g := Gradient.new()
	match _end_tone:
		"dawn":
			g.colors = PackedColorArray([Color(0.02, 0.03, 0.07), Color(0.1, 0.1, 0.2), Color(0.8, 0.46, 0.25)])
		"dusk":
			g.colors = PackedColorArray([Color(0.02, 0.01, 0.04), Color(0.14, 0.05, 0.12), Color(0.5, 0.16, 0.18)])
		_:
			g.colors = PackedColorArray([Color(0.0, 0.0, 0.0), Color(0.03, 0.02, 0.05), Color(0.08, 0.02, 0.04)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end.add_child(bg)
	if _end_tone == "cuffs":
		_end_strobe = ColorRect.new()
		_end_strobe.set_anchors_preset(Control.PRESET_FULL_RECT)
		_end_strobe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_end.add_child(_end_strobe)
	else:
		_end_strobe = null
	var title := _label(130 if _end_tone == "cuffs" else 84, PAPER, _end)
	if _end_tone == "cuffs":
		title.add_theme_color_override("font_outline_color", BLOOD)
		title.add_theme_constant_override("outline_size", 14)
	title.text = String(data.get("title", ""))
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.1 if _end_tone == "cuffs" else 0.2
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.pivot_offset = Vector2(_vp().x * 0.5, 80)
	title.scale = Vector2(2.4, 2.4)
	title.rotation = deg_to_rad(-6.0 if _end_tone == "cuffs" else 0.0)
	title.modulate.a = 0.0
	var tw := _tween().set_parallel(true)
	tw.tween_property(title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "modulate:a", 1.0, 0.2)
	if _end_tone == "cuffs":
		_cuffs = Cuffs.new()
		_cuffs.position = Vector2(_vp().x * 0.5 - 220, _vp().y * 0.45)
		_cuffs.size = Vector2(440, 160)
		_end.add_child(_cuffs)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.66
	col.offset_left = -380.0
	col.offset_right = 380.0
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end.add_child(col)
	var i := 0
	for line in data.get("lines", []):
		var l := _label(22, PAPER, col, null)
		l.remove_theme_font_override("font")
		l.text = String(line)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.modulate.a = 0.0
		var t2 := _tween()
		t2.tween_interval(1.0 + i * 1.3)
		t2.tween_property(l, "modulate:a", 1.0, 0.6)
		i += 1
	var tally := GridContainer.new()
	tally.columns = 2
	tally.add_theme_constant_override("h_separation", 24)
	tally.add_theme_constant_override("v_separation", 2)
	tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tally.modulate.a = 0.0
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	col.add_child(spacer)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(tally)
	col.add_child(hb)
	for row in data.get("tally", []):
		var a := _label(17, DIM, tally, mono)
		a.text = String(row[0])
		var b := _label(17, PAPER, tally, mono)
		b.text = String(row[1])
	var t3 := _tween()
	t3.tween_interval(1.0 + i * 1.3 + 0.4)
	t3.tween_property(tally, "modulate:a", 1.0, 0.5)
	t3.tween_callback(func(): _end_ready = true)

func _step_ending(dt: float) -> void:
	if _end == null or not is_instance_valid(_end):
		return
	_end_age += dt
	if _end_strobe != null:
		var red := int(_end_age * 7.0) % 2 == 0
		var a := 0.22 * (0.5 + 0.5 * sin(_end_age * 30.0))
		_end_strobe.color = Color(0.9, 0.05, 0.05, a) if red else Color(0.05, 0.2, 0.95, a)
	if _cuffs != null and is_instance_valid(_cuffs):
		_cuffs.set("t", clampf((_end_age - 0.5) / 1.4, 0.0, 1.0))
		_cuffs.queue_redraw()

func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.05)
	_now += dt
	_step_phones(dt)
	_step_radio(dt)
	_step_scanner(dt)
	_step_announcements(dt)
	_step_ending(dt)
	if _card != null and _card.modulate.a > 0.0:
		# A flicker of the red ghost behind the title.
		_card_ghost.position.x = sin(_now * 41.0) * 3.0 + 4.0
		_card_ghost.modulate.a = 0.5 + 0.5 * sin(_now * 23.0)
	if choice_active and _choice != null:
		for c in _choice_cards:
			c.modulate = Color.WHITE.lerp(Color(1.2, 1.15, 1.1), 0.5 + 0.5 * sin(_now * 6.0))

## The cuffs that close on the BUSTED card: two steel rings sliding in, a chain between, a clack when they meet.
class Cuffs extends Control:
	var t := 0.0
	func _draw() -> void:
		var steel := Color(0.72, 0.74, 0.78)
		var dark := Color(0.2, 0.2, 0.24)
		var c := size * 0.5
		var gap := lerpf(200.0, 38.0, t * t * (3.0 - 2.0 * t))
		var l := c + Vector2(-gap, 0)
		var r := c + Vector2(gap, 0)
		# the chain
		var links := 5
		for i in links:
			var f := (i + 0.5) / links
			var p := l.lerp(r, f)
			draw_arc(p, 9.0, 0.0, TAU, 20, steel if i % 2 == 0 else dark, 4.0)
		for ring_c in [l, r]:
			draw_arc(ring_c, 52.0, 0.0, TAU, 48, dark, 20.0)
			draw_arc(ring_c, 52.0, 0.0, TAU, 48, steel, 12.0)
			draw_rect(Rect2(ring_c + Vector2(-8, -72), Vector2(16, 18)), steel)
		if t >= 1.0:
			draw_circle(c, 6.0, Color(1, 1, 1, 0.8))
