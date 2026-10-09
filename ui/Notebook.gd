extends CanvasLayer
## The notebook in your back pocket (J): what the regulars want and where to
## get it, when everything's open, a map of the block drawn in biro, and
## notes on the run so far (GameState.diary). The game waits while it's out.
## J, Esc or a click outside the page puts it away; Tab or the tabs across
## the top turn the page.

const PAGES := ["Orders", "Hours", "Map", "Notes", "Messages"]
const INK := Color(0.12, 0.14, 0.3)
const INK_FADED := Color(0.3, 0.32, 0.45)
const RED_INK := Color(0.62, 0.12, 0.12)
const PAGE := Rect2(190, 70, 900, 580)
## West to east along the block (build_rooms_3d.gd's city), for the map.
const Booster := preload("res://world/Booster.gd")
const BLOCK := [
	[-24.5, "Police"], [-17.5, "Home"], [-14.0, "Karts"], [-10.5, "Pharmacy"], [-7.0, "Tape Deck"], [-3.5, "Bar"],
	[0.0, "Pawn"], [3.5, "24/7 Shop"], [7.0, "Shelter"], [10.5, "Liquor"], [17.5, "Supermarket"], [24.5, "Electronics"],
]
const PLACE_NAMES := {"convenience": "24/7 Shop", "pharmacy": "Pharmacy", "supermarket": "Supermarket",
	"liquor": "Liquor store", "electronics": "Electronics", "bar": "Dive Bar", "shelter": "Shelter",
	"pawn": "Pawn shop", "music": "Tape Deck", "karts": "Kart track"}

var _page: int = 0
var _canvas: Control
var _was_paused: bool = false

func open(page := 0) -> void:
	layer = 104
	process_mode = Node.PROCESS_MODE_ALWAYS
	_page = page
	_was_paused = get_tree().paused
	get_tree().paused = true
	SFX.play("steal", -12.0, 1.4)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not PAGE.has_point(e.position):
			_close())
	add_child(shade)
	var paper := ColorRect.new()
	paper.position = PAGE.position
	paper.size = PAGE.size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = PAPER
	mat.set_shader_parameter("size", PAGE.size)
	paper.material = mat
	add_child(paper)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)

func _unhandled_input(event: InputEvent) -> void:
	# Keys and pad buttons both; the game waits while it's out, so nothing
	# behind it gets them either.
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if event.is_action("notebook") or event.is_action("cancel_ui") or event.is_action("pause"):
		_close()
	elif event.is_action("page_next"):
		_turn(1)
	elif event.is_action("page_prev"):
		_turn(-1)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in PAGES.size():
			if _tab_rect(i).has_point(event.position):
				_page = i
				SFX.play("steal", -16.0, 1.6)
				_canvas.queue_redraw()

func _turn(step: int) -> void:
	_page = posmod(_page + step, PAGES.size())
	SFX.play("steal", -16.0, 1.6)
	_canvas.queue_redraw()

func _close() -> void:
	get_tree().paused = _was_paused
	queue_free()

func _tab_rect(i: int) -> Rect2:
	return Rect2(PAGE.position.x + 30 + i * 150, PAGE.position.y - 34, 140, 36)

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var c := _canvas
	var font := ThemeDB.fallback_font
	for i in PAGES.size():
		var r := _tab_rect(i)
		var active := i == _page
		c.draw_rect(r, Color(0.93, 0.89, 0.78) if active else Color(0.78, 0.74, 0.64))
		c.draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
		c.draw_string(font, r.position + Vector2(16, 25), PAGES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK if active else INK_FADED)
	match _page:
		0: _draw_orders(c, font)
		1: _draw_hours(c, font)
		2: _draw_map(c, font)
		3: _draw_notes(c, font)
		4: _draw_messages(c, font)
	c.draw_string(font, Vector2(PAGE.position.x + 20, PAGE.end.y + 26), ("Touchpad / Circle: put it away     L1 / R1: turn the page" if GameState.using_pad else "J / Esc: put it away     Tab or arrows: turn the page"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.78, 0.72))

func _line(c: Control, font: Font, row: int, text: String, col := INK, indent := 0.0, size := 17) -> void:
	c.draw_string(font, Vector2(PAGE.position.x + 70 + indent, PAGE.position.y + 62 + row * 30), text, HORIZONTAL_ALIGNMENT_LEFT, PAGE.size.x - 110 - indent, size, col)

func _draw_orders(c: Control, font: Font) -> void:
	_line(c, font, 0, "Who wants what", INK, 0.0, 22)
	_line(c, font, 1, "Today: %s" % Headlines.title().to_lower(), RED_INK if not Headlines.is_today("quiet") else INK_FADED, 0.0, 15)
	var row := 2
	var open := GameState.bar_patrons.filter(func(p): return not p.get("fulfilled", false))
	if open.is_empty():
		_line(c, font, row, "Nothing yet. Go sit at the bar and listen.", INK_FADED)
	for p in open:
		var item: String = _misread(GameState.item_name_for(p["request_id"]))
		var store: String = _misread(GameState.store_name_for(p["request_id"]))
		var have: bool = GameState.has_item(p["request_id"])
		_line(c, font, row, "%s  --  %s   ($%d)" % [p["name"], item, GameState.order_price(p["name"], p["price"])])
		_line(c, font, row + 1, ("got it, take it to the bar" if have else "from %s" % store), RED_INK if have else INK_FADED, 30.0, 15)
		row += 2
	row += 1
	# The regulars, and how they feel about you.
	var known: Array = GameState.rep.keys().filter(func(n): return GameState.rep_of(n) != 0 and n not in GameState.dead_regulars)
	if not known.is_empty():
		var bits: Array = known.map(func(n): return "%s %s" % [n, GameState.rep_word(GameState.rep_of(n))])
		_line(c, font, row, "People: " + ", ".join(bits), INK_FADED, 0.0, 15)
		row += 1
	if GameState.debt > 0:
		_line(c, font, row, "Owe the pusher $%d  -- %s" % [GameState.debt, GameState.debt_due_text()], RED_INK)
		row += 1
	if GameState.in_treatment:
		_line(c, font, row, "Program: %d of %d clean days. Clinic dose at the shelter, every day." % [GameState.treatment_streak, GameState.RECOVERY_DAYS], Color(0.1, 0.4, 0.2))

## Badly sick, your own handwriting swims: letters swap and drop out of
## the names, a little differently every time you look.
func _misread(text: String) -> String:
	var s := GameState.sickness()
	if s < 0.8:
		return text
	var chars := text.split("")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text) + int(Time.get_ticks_msec() / 1500)
	for i in range(1, chars.size() - 1):
		if chars[i] == " " or rng.randf() > (s - 0.75) * 1.2:
			continue
		var j := i + 1
		if chars[j] != " ":
			var t := chars[i]
			chars[i] = chars[j]
			chars[j] = t
	return "".join(chars)

func _draw_hours(c: Control, font: Font) -> void:
	_line(c, font, 0, "When things are open", INK, 0.0, 22)
	var row := 2
	for place in GameState.OPENING_HOURS:
		var h: Array = GameState.OPENING_HOURS[place]
		var open_now := GameState.is_open(place)
		var span := "all night and day" if h[0] == 0 and h[1] == 24 else "%02d:00 - %02d:00" % [h[0], h[1] % 24]
		_line(c, font, row, "%s" % PLACE_NAMES.get(place, place))
		_line(c, font, row, span + ("   open now" if open_now else ""), Color(0.1, 0.4, 0.2) if open_now else INK_FADED, 260.0)
		row += 1
	row += 1
	var ph: Array = GameState.PUSHER_HOURS
	_line(c, font, row, "The pusher")
	_line(c, font, row, "%02d:00 - %02d:00, east end of the block%s" % [ph[0], ph[1], "   there now" if GameState.pusher_on_shift() else ""], RED_INK if GameState.pusher_on_shift() else INK_FADED, 260.0)
	row += 1
	_line(c, font, row, "Shelter meals")
	_line(c, font, row, "07:00 - 10:00 and 17:00 - 20:00", INK_FADED, 260.0)
	row += 2
	_line(c, font, row, "It's %s on day %d." % [GameState.clock_text(), GameState.day], INK_FADED)

func _draw_map(c: Control, font: Font) -> void:
	_line(c, font, 0, "The block", INK, 0.0, 22)
	var left := PAGE.position.x + 60
	var right := PAGE.end.x - 60
	var top := PAGE.position.y + 150
	var sx := func(x: float) -> float: return lerpf(left, right, (x + 29.0) / 58.0)
	# Buildings, the sidewalk, the road -- in biro, a bit wobbly.
	c.draw_rect(Rect2(left, top, right - left, 110), Color(INK, 0.06))
	c.draw_line(Vector2(left, top + 110), Vector2(right, top + 110), INK, 2.0)
	c.draw_line(Vector2(left, top + 150), Vector2(right, top + 150), INK_FADED, 1.0)
	c.draw_dashed_line(Vector2(left, top + 215), Vector2(right, top + 215), INK_FADED, 1.5, 14.0)
	c.draw_line(Vector2(left, top + 280), Vector2(right, top + 280), INK_FADED, 1.0)
	for b in BLOCK:
		var x: float = sx.call(b[0])
		c.draw_line(Vector2(x - 22, top + 110), Vector2(x + 22, top + 110), RED_INK, 4.0)
		c.draw_set_transform(Vector2(x - 6, top + 100), -PI / 2.6)
		c.draw_string(font, Vector2.ZERO, b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
		c.draw_set_transform(Vector2.ZERO)
	# What Tasha's done today, and where she is now.
	for s in GameState.booster_hit:
		var hx: float = sx.call(Booster.STORE_X[s])
		c.draw_string(font, Vector2(hx + 14, top + 128), "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, RED_INK)
	if GameState.booster_present() and GameState.booster_store != "":
		var tx: float = sx.call(Booster.STORE_X[GameState.booster_store] + 1.6)
		c.draw_string(font, Vector2(tx - 4, top + 130), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	var px: float = sx.call(14.0)
	c.draw_circle(Vector2(px, top + 135), 6.0, RED_INK)
	c.draw_string(font, Vector2(px + 10, top + 140), "him (4pm on)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, RED_INK)
	c.draw_string(font, Vector2(left, top + 200), "road", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK_FADED)
	c.draw_string(font, Vector2(left, top + 330), "The lot out back: through the alley. The supermarket's trucks unload there, early mornings.", HORIZONTAL_ALIGNMENT_LEFT, right - left, 14, INK_FADED)
	var scene := get_tree().current_scene
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if scene and scene.name == "City3D" and player:
		var me := Vector2(sx.call(player.global_position.x), top + 110 + clampf((player.global_position.z + 4.5) / 9.0, 0.0, 1.0) * 170.0)
		c.draw_circle(me, 7.0, Color(0.1, 0.45, 0.2))
		c.draw_string(font, me + Vector2(10, 18), "you", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.45, 0.2))
	else:
		_line(c, font, 12, "You're inside: %s." % (String(scene.name).trim_suffix("3D") if scene else "?"), INK_FADED)

func _draw_notes(c: Control, font: Font) -> void:
	# What's coming up goes at the top, and the diary gives up a line for
	# each of them.
	var due := _obligations()
	for i in due.size():
		_line(c, font, i, due[i][0], RED_INK if due[i][1] else INK, 0.0, 15)
	var top := due.size() + 1
	_line(c, font, top, "What's happened", INK, 0.0, 22)
	var entries: Array = GameState.diary
	var shown := entries.slice(maxi(0, entries.size() - (15 - top)))
	if shown.is_empty():
		_line(c, font, top + 2, "Nothing yet.", INK_FADED)
	for i in shown.size():
		var e: Dictionary = shown[i]
		_line(c, font, top + 2 + i, "Day %d, %s" % [e["day"], e["clock"]], INK_FADED, 0.0, 14)
		_line(c, font, top + 2 + i, e["text"], INK, 140.0, 16)

## Your phone: Mia's texts, St. Jude's, newest at the bottom.
func _draw_messages(c: Control, font: Font) -> void:
	_line(c, font, 0, "Messages", INK, 0.0, 22)
	var msgs: Array = Story.messages()
	var row := 2
	if Story.state()["mia"] == "blocked":
		_line(c, font, 1, "Mia has blocked your number.", RED_INK, 0.0, 15)
	if msgs.is_empty():
		_line(c, font, row, "No messages.", INK_FADED)
	for m in msgs.slice(maxi(0, msgs.size() - 7)):
		_line(c, font, row, "%s -- day %d, %s" % [m["from"], m["day"], m["clock"]], INK_FADED, 0.0, 14)
		_line(c, font, row + 1, m["text"], INK, 20.0, 15)
		row += 2

## Dates and debts, for the top of the notes page: [text, urgent].
func _obligations() -> Array:
	var out := []
	if GameState.warrant:
		out.append(["WARRANT -- they know your face", true])
	if GameState.court_day > 0:
		out.append(["Court: day %d, 9-12 at the station" % GameState.court_day, true])
	if not GameState.probation_days.is_empty():
		out.append(["Probation: check in days %s" % ", ".join(GameState.probation_days.map(func(d): return str(int(d)))), true])
	if Story.appointment_text() != "":
		out.append([Story.appointment_text(), Story.state()["dana"] == "booked"])
	var rent_when: String = "LOCKED OUT" if GameState.locked_out() else "due day %d" % GameState.rent_due_day
	out.append(["Rent: $%d %s" % [GameState.rent_amount(), rent_when], GameState.rent_stage > 0])
	for id in GameState.pawn_tickets:
		out.append(["Pawn ticket: %s, $%d by day %d" % [GameState.item_name_for(id).trim_prefix("your "), GameState.buyback_price(id), GameState.ticket_last_day(id)], false])
	return out

## Lined notebook paper: faint blue rules, a red margin, grain, the edges
## gone grey from being in a pocket.
const PAPER := """
shader_type canvas_item;
uniform vec2 size;
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void fragment() {
	vec2 px = UV * size;
	vec3 c = vec3(0.93, 0.9, 0.8);
	c *= 0.96 + (hash(floor(px * 0.5)) - 0.5) * 0.05;
	float rule = step(fract((px.y - 44.0) / 30.0), 0.035) * step(44.0, px.y);
	c = mix(c, vec3(0.55, 0.65, 0.85), rule * 0.45);
	c = mix(c, vec3(0.8, 0.25, 0.25), step(abs(px.x - 58.0), 0.8) * 0.6);
	vec2 e = min(UV, 1.0 - UV);
	c *= 0.82 + 0.18 * smoothstep(0.0, 0.05, min(e.x, e.y));
	float ring = abs(length(px - vec2(size.x - 120.0, size.y - 110.0)) - 46.0);
	c = mix(c, vec3(0.6, 0.45, 0.3), (1.0 - smoothstep(0.0, 3.0, ring)) * 0.18);
	COLOR = vec4(c, 1.0);
}
"""
