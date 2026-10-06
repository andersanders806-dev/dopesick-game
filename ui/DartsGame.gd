extends CanvasLayer
## Darts for money at the Dive Bar: three rounds of three darts each, you
## then them, and the higher total takes the pot. A tie hands the stakes
## back.
##
## Your aim sways -- and sways worse the sicker you are (GameState.sickness()),
## because withdrawal is in your hands before it's anywhere else. Hold the
## right mouse button or Shift to hold your breath and steady it, for as long
## as the breath lasts; it comes back while you let go. Left click or Space
## throws. Arrow keys nudge the aim for players without a mouse.
##
## The board is the standard clock -- 20 at the top -- at the real
## proportions (bull 6.35 mm, outer bull 15.9, treble 99-107, double
## 162-170), drawn in code with a sisal-and-spotlight shader over it. The
## regular throws at the treble 20 (or the fat single 20 if they're not much
## of a player) and scatters by skill.

signal finished(won: bool)

const ORDER := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
const CENTRE := Vector2(470, 380)
const R := 270.0  # the double ring's outer edge, in pixels
const MM := R / 170.0
const ROUNDS := 3
const DARTS := 3
const BREATH_MAX := 1.6
const BLACK := Color(0.08, 0.075, 0.07)
const CREAM := Color(0.9, 0.84, 0.68)
const RED := Color(0.72, 0.1, 0.09)
const GREEN := Color(0.06, 0.42, 0.2)

static var _shown_howto := false

var opponent_name := "Regular"
var skill := 0.5
var bet := 5

var _round := 1
var _player_turn := true
var _darts_left := DARTS
var _totals := [0, 0]
var _round_scores := [[], []]
var _board_darts: Array = []  # {pos, label, t} landed this turn
var _flying: Dictionary = {}  # {from, to, t, who, label}
var _aim := CENTRE
var _mouse := CENTRE
var _sway_t := 0.0
var _breath := BREATH_MAX
var _steady := false
var _ai_timer := 0.0
var _over := false
var _howto := false
var _message := ""
var _canvas: Control
var _hud: CanvasLayer
var _thunk: AudioStreamPlayer

func start(opponent: String, opponent_skill: float, stake: int) -> void:
	opponent_name = opponent
	skill = opponent_skill
	bet = stake
	layer = 95
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud:
		_hud.visible = false
	GameState.set_process(false)
	var room := ColorRect.new()
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	room.color = Color(0.05, 0.035, 0.03)
	add_child(room)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)
	# Sisal fibres and the spotlight, over the drawn board.
	var fx := ColorRect.new()
	fx.position = CENTRE - Vector2.ONE * R * 1.3
	fx.size = Vector2.ONE * R * 2.6
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = BOARD_FX
	fx.material = mat
	add_child(fx)
	# The overlay (darts, aim, text) draws above the fibres.
	var over := Control.new()
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.draw.connect(_draw_over.bind(over))
	over.name = "Over"
	add_child(over)
	_thunk = AudioStreamPlayer.new()
	_thunk.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	if ResourceLoader.exists("res://assets/sfx/pool_cushion.wav"):
		_thunk.stream = load("res://assets/sfx/pool_cushion.wav")
	add_child(_thunk)
	_message = "%s chalks the scores up. $%d on it. Your throw." % [opponent_name, bet]
	_howto = not _shown_howto
	_shown_howto = true

func _exit_tree() -> void:
	GameState.set_process(true)

func _process(delta: float) -> void:
	_sway_t += delta
	# Hold your breath: right click, Shift, or L2 -- COD's aim-down-sights.
	_steady = (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_action_pressed("sprint") or Input.is_action_pressed("steady")) and _breath > 0.0
	if _steady:
		_breath = maxf(0.0, _breath - delta)
	else:
		_breath = minf(BREATH_MAX, _breath + delta * 0.6)
	# The arrows, or the left stick (analogue, so a light touch is fine aim).
	var nudge := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	_mouse += nudge * 220.0 * delta
	_aim = _mouse + _sway()
	if not _flying.is_empty():
		_flying["t"] += delta / 0.28
		if _flying["t"] >= 1.0:
			_land()
	elif not _over and not _howto and not _player_turn and _darts_left > 0:
		# _darts_left hits 0 during the pause at the end of their turn; a
		# throw then would score a fourth dart and end the game twice.
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_ai_throw()
	_canvas.queue_redraw()
	get_node("Over").queue_redraw()

## Two slow sines and a faster tremor; withdrawal multiplies it, holding
## your breath damps it.
func _sway() -> Vector2:
	var sick := GameState.sickness()
	var amp := 14.0 + 55.0 * sick
	var tremor := 1.5 + 9.0 * sick
	var t := _sway_t
	var v := Vector2(sin(t * 1.3) + 0.6 * sin(t * 2.9 + 1.0), cos(t * 1.1) + 0.5 * sin(t * 3.7)) * amp * 0.6
	v += Vector2(sin(t * 23.0), cos(t * 19.0)) * tremor
	return v * (0.25 if _steady else 1.0)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_ui"):
		get_viewport().set_input_as_handled()
		if _over:
			_close()
			return
		_message = "You put the darts down. %s pockets the $%d." % [opponent_name, bet]
		_finish(false)
	elif (event.is_action_pressed("fire") or event.is_action_pressed("interact")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		_click()

func _click() -> void:
	if _howto:
		_howto = false
		return
	if _over:
		_close()
		return
	if _player_turn and _flying.is_empty() and _darts_left > 0:
		var scatter := 4.0 + 10.0 * GameState.sickness()
		_throw(_aim + Vector2(randfn(0.0, scatter), randfn(0.0, scatter)), 0)

func _throw(to: Vector2, who: int) -> void:
	_flying = {"from": Vector2(to.x + 160.0, 760.0), "to": to, "t": 0.0, "who": who}
	SFX.play("steal", -14.0, 1.8)

func _land() -> void:
	var to: Vector2 = _flying["to"]
	var who: int = _flying["who"]
	_flying = {}
	var hit := score_at(to)
	_board_darts.append({"pos": to, "label": hit["label"]})
	_round_scores[who].append(hit["points"])
	_totals[who] += hit["points"]
	_darts_left -= 1
	if _thunk.stream:
		_thunk.pitch_scale = randf_range(1.6, 1.9)
		_thunk.volume_db = -8.0 if hit["points"] > 0 else -16.0
		_thunk.play()
	var who_name := "You" if who == 0 else opponent_name
	_message = "%s: %s" % [who_name, hit["label"]]
	if _darts_left > 0:
		if who == 1:
			_ai_timer = 0.9
		return
	# End of a turn.
	var turn_total := 0
	for p in _round_scores[who].slice(-DARTS):
		turn_total += p
	_message = "%s scored %d this round." % [who_name, turn_total]
	if who == 0:
		_player_turn = false
		_ai_timer = 1.6
		_darts_left = DARTS
		await get_tree().create_timer(1.2).timeout
		_board_darts.clear()
	else:
		await get_tree().create_timer(1.2).timeout
		_board_darts.clear()
		if _round >= ROUNDS:
			_end_game()
			return
		_round += 1
		_player_turn = true
		_darts_left = DARTS
		_message = "Round %d. Your throw." % _round

func _ai_throw() -> void:
	# Weaker players go for the fat single 20; better ones for the treble.
	var target_r := (103.0 if skill > 0.45 else 135.0) * MM
	var target := CENTRE + Vector2(0, -target_r)
	var spread := lerpf(62.0, 11.0, skill)
	_throw(target + Vector2(randfn(0.0, spread), randfn(0.0, spread)), 1)
	_ai_timer = 0.9

func _end_game() -> void:
	if _over:
		return
	if _totals[0] == _totals[1]:
		_message = "%d apiece. %s shrugs and slides your money back." % [_totals[0], opponent_name]
		_over = true
		return
	var won: bool = _totals[0] > _totals[1]
	if won:
		_message = "%d to %d. %s slaps $%d on the bar." % [_totals[0], _totals[1], opponent_name, bet]
	else:
		_message = "%d to %d. %s holds out a hand. $%d, pal." % [_totals[1], _totals[0], opponent_name, bet]
	_finish(won)

func _finish(won: bool) -> void:
	_over = true
	GameState.log_event(("Won $%d at darts off %s." if won else "Lost $%d at darts to %s.") % [bet, opponent_name])
	if won:
		GameState.cash += bet
		GameState.cash_earned += bet
		GameState.cash_changed.emit(GameState.cash)
		SFX.play("cash")
	else:
		GameState.spend_cash(mini(bet, GameState.cash))
	finished.emit(won)

func _close() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.visible = true
	queue_free()

## Points and a label ("T20", "D5", "BULL", "miss") for a dart at `p`.
static func score_at(p: Vector2) -> Dictionary:
	var off := p - CENTRE
	var mm := off.length() / MM
	if mm <= 6.35:
		return {"points": 50, "label": "BULL"}
	if mm <= 15.9:
		return {"points": 25, "label": "25"}
	if mm > 170.0:
		return {"points": 0, "label": "miss"}
	var deg := fposmod(rad_to_deg(off.angle()) + 90.0 + 9.0, 360.0)
	var n: int = ORDER[int(deg / 18.0) % 20]
	if mm >= 99.0 and mm <= 107.0:
		return {"points": n * 3, "label": "T%d" % n}
	if mm >= 162.0:
		return {"points": n * 2, "label": "D%d" % n}
	return {"points": n, "label": str(n)}

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var c := _canvas
	# Cabinet and surround.
	c.draw_rect(Rect2(CENTRE - Vector2.ONE * R * 1.32, Vector2.ONE * R * 2.64), Color(0.16, 0.08, 0.04))
	c.draw_rect(Rect2(CENTRE - Vector2.ONE * R * 1.26, Vector2.ONE * R * 2.52), Color(0.09, 0.05, 0.03))
	c.draw_circle(CENTRE + Vector2(6, 10), R * 1.2, Color(0, 0, 0, 0.5))
	c.draw_circle(CENTRE, R * 1.2, Color(0.05, 0.05, 0.05))
	var rings := [[170.0, 162.0, true], [162.0, 107.0, false], [107.0, 99.0, true], [99.0, 15.9, false]]
	for i in 20:
		var a0 := deg_to_rad(-90.0 - 9.0 + i * 18.0)
		var a1 := a0 + deg_to_rad(18.0)
		var dark := i % 2 == 0
		for ring in rings:
			var col: Color
			if ring[2]:
				col = RED if dark else GREEN
			else:
				col = BLACK if dark else CREAM
			_sector(c, a0, a1, ring[0] * MM, ring[1] * MM, col)
	c.draw_circle(CENTRE, 15.9 * MM, GREEN)
	c.draw_circle(CENTRE, 6.35 * MM, RED)
	# The wire.
	var wire := Color(0.75, 0.75, 0.72, 0.8)
	for r in [170.0, 162.0, 107.0, 99.0, 15.9, 6.35]:
		c.draw_arc(CENTRE, r * MM, 0, TAU, 96, wire, 1.2)
	for i in 20:
		var a := deg_to_rad(-90.0 - 9.0 + i * 18.0)
		c.draw_line(CENTRE + Vector2.from_angle(a) * 15.9 * MM, CENTRE + Vector2.from_angle(a) * 170.0 * MM, wire, 1.0)
	# Numbers on the ring.
	var font := ThemeDB.fallback_font
	for i in 20:
		var a := deg_to_rad(-90.0 + i * 18.0)
		var p := CENTRE + Vector2.from_angle(a) * R * 1.1
		var s := str(ORDER[i])
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		c.draw_string(font, p + Vector2(-w * 0.5, 8), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.9, 0.84))

func _sector(c: Control, a0: float, a1: float, r_out: float, r_in: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 8
	for k in steps + 1:
		pts.append(CENTRE + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * r_out)
	for k in steps + 1:
		pts.append(CENTRE + Vector2.from_angle(lerpf(a1, a0, float(k) / steps)) * r_in)
	c.draw_colored_polygon(pts, col)

func _draw_over(c: Control) -> void:
	var font := ThemeDB.fallback_font
	for d in _board_darts:
		_dart(c, d["pos"], 1.0)
		_text(c, font, d["pos"] + Vector2(14, -22), d["label"], 15, Color(1, 0.9, 0.5))
	if not _flying.is_empty():
		var t: float = _flying["t"]
		var p: Vector2 = (_flying["from"] as Vector2).lerp(_flying["to"], ease(t, 0.6))
		_dart(c, p, lerpf(2.4, 1.0, t))
	if _player_turn and not _over and not _howto and _flying.is_empty():
		var col := Color(1, 1, 1, 0.9) if _steady else Color(1, 0.85, 0.5, 0.8)
		c.draw_arc(_aim, 10.0, 0, TAU, 24, col, 1.5)
		c.draw_line(_aim - Vector2(16, 0), _aim - Vector2(5, 0), col, 1.5)
		c.draw_line(_aim + Vector2(5, 0), _aim + Vector2(16, 0), col, 1.5)
		c.draw_line(_aim - Vector2(0, 16), _aim - Vector2(0, 5), col, 1.5)
		c.draw_line(_aim + Vector2(0, 5), _aim + Vector2(0, 16), col, 1.5)
	_draw_panel(c, font)
	if _howto:
		c.draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.72))
		var lines := [
			"DARTS  -  three rounds, three darts each. Higher total takes the pot.",
			"",
			"Move the mouse to aim. Your hand sways -- worse the sicker you are.",
			"Hold RIGHT MOUSE or SHIFT to hold your breath and steady it (it runs out).",
			"LEFT CLICK or SPACE throws.",
			"",
			"Treble ring x3, outer double ring x2, bull 50, outer bull 25.",
			"Treble 20 at the top is the money shot.",
			"",
			"Click to start.",
		]
		for i in lines.size():
			_text(c, font, Vector2(300, 220 + i * 30), lines[i], 19, Color(0.95, 0.9, 0.78))

func _dart(c: Control, tip: Vector2, k: float) -> void:
	var dir := Vector2(0.55, 0.85).normalized()
	var shadow := Vector2(6, 8) * k
	c.draw_line(tip + shadow, tip + dir * 48.0 * k + shadow, Color(0, 0, 0, 0.35), 3.0 * k)
	c.draw_line(tip, tip + dir * 14.0 * k, Color(0.8, 0.8, 0.82), 1.6 * k)
	c.draw_line(tip + dir * 14.0 * k, tip + dir * 32.0 * k, Color(0.35, 0.35, 0.38), 4.0 * k)
	var f := tip + dir * 40.0 * k
	var perp := dir.orthogonal()
	c.draw_colored_polygon(PackedVector2Array([tip + dir * 32.0 * k, f + perp * 7.0 * k, tip + dir * 50.0 * k, f - perp * 7.0 * k]), Color(0.85, 0.2, 0.25))

func _draw_panel(c: Control, font: Font) -> void:
	var x := 900.0
	_text(c, font, Vector2(x, 90), "DARTS  -  $%d" % bet, 24, Color(0.95, 0.85, 0.45))
	_text(c, font, Vector2(x, 128), "Round %d of %d" % [mini(_round, ROUNDS), ROUNDS], 16, Color(0.75, 0.72, 0.65))
	for who in 2:
		var y := 180.0 + who * 110.0
		var who_name := "You" if who == 0 else opponent_name
		var active := (_player_turn == (who == 0)) and not _over
		_text(c, font, Vector2(x, y), who_name, 20, Color(0.98, 0.88, 0.55) if active else Color(0.72, 0.7, 0.65))
		_text(c, font, Vector2(x + 250, y), str(_totals[who]), 26, Color(0.95, 0.93, 0.88))
		var shots: Array = _round_scores[who]
		_text(c, font, Vector2(x, y + 30), "  ".join(shots.map(func(p): return str(p))), 14, Color(0.6, 0.58, 0.54))
	if _player_turn and not _over:
		_text(c, font, Vector2(x, 440), "Darts left: %d" % _darts_left, 16, Color(0.75, 0.72, 0.65))
		_text(c, font, Vector2(x, 480), "Breath", 13, Color(0.6, 0.58, 0.54))
		c.draw_rect(Rect2(x + 60, 468, 200, 12), Color(0.15, 0.15, 0.16))
		c.draw_rect(Rect2(x + 60, 468, 200 * _breath / BREATH_MAX, 12), Color(0.55, 0.75, 0.9))
		if GameState.sickness() > 0.2:
			_text(c, font, Vector2(x, 510), "Your hands won't keep still.", 13, Color(0.85, 0.5, 0.5))
	var wrapped := _message
	_text(c, font, Vector2(x, 570), wrapped, 15, Color(0.9, 0.87, 0.8))
	var hint := "[E] / click to walk away" if _over else "Mouse aim  -  hold right click/Shift: steady  -  click/Space: throw  -  Esc: give up"
	if GameState.using_pad:
		hint = "[Square] walk away" if _over else "Left stick aim  -  hold L2: steady  -  R2: throw  -  Circle: give up"
	_text(c, font, Vector2(40, 704), hint, 13, Color(0.6, 0.58, 0.54))

func _text(c: Control, font: Font, p: Vector2, s: String, size: int, col: Color) -> void:
	c.draw_string(font, p + Vector2(1, 2), s, HORIZONTAL_ALIGNMENT_LEFT, 360, size, Color(0, 0, 0, 0.8))
	c.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, 360, size, col)

## Sisal fibre over the board face, and a spotlight from above.
const BOARD_FX := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec2 d = UV - vec2(0.5);
	float r = length(d);
	float fibre = (hash(floor(UV * 700.0)) - 0.5) * 0.14;
	float in_board = 1.0 - smoothstep(0.37, 0.375, r);
	c *= 1.0 + fibre * in_board;
	float light = 1.18 - smoothstep(0.0, 0.62, length(d - vec2(0.0, -0.12))) * 0.75;
	c *= light;
	COLOR = vec4(c, 1.0);
}
"""
