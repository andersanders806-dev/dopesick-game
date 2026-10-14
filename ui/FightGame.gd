extends CanvasLayer
## A mugging on the block (npc/Mugger3D.gd): first the standoff -- fight,
## hand it over, or run -- then, if it comes to it, the fight.
##
## The fight is read-and-react, like a stripped-down Punch-Out: the mugger
## winds up (the red bar fills) and swings. Dodge (Shift / left / L1) in the
## last DODGE_WINDOW of the wind-up and they're left open for a moment,
## taking double damage; hit (Space / click / R2) to punch. Get caught by the
## swing and it comes off your health (autoload/Survival.gd) -- a knife cut
## bleeds. A shiv (autoload/Crafting.gd) more than doubles your damage;
## withdrawal shrinks the dodge window and takes the weight out of your
## punches. Put them down and they run; go down yourself and they take
## everything, and leave you bleeding.

signal finished(outcome: String)  # "won", "lost", "paid", "ran", "caught"

const MUGGER_HP := 40.0
const KNIFE_HP := 50.0
const PUNCH := 9.0
const SHIV_MULT := 2.4
const OPEN_MULT := 2.0
const SWING_DMG := 9.0
const KNIFE_DMG := 13.0
const WINDUP := Vector2(0.9, 1.5)
const DODGE_WINDOW := 0.38
const OPEN_TIME := 0.9
const PUNCH_COOLDOWN := 0.35
## You go down after this much health lost in one fight.
const GO_DOWN := 35.0

var knife := false
var phase := "standoff"  # standoff, fight, over
var mugger_hp := MUGGER_HP
var state := "idle"  # idle, windup, open, recover
var t := 0.0
var windup_len := 1.2
var lost := 0.0
var outcome := ""
var message := ""
var _cooldown := 0.0
var _punch_anim := 0.0
var _hit_flash := 0.0
var _dodge_anim := 0.0
## Screen shake after a hit, either way; dies away fast.
var _shake := 0.0
var _hud: CanvasLayer
var _canvas: Control
var _choice: int = 0

func start(with_knife := false) -> void:
	knife = with_knife
	mugger_hp = KNIFE_HP if knife else MUGGER_HP
	layer = 96
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud:
		_hud.visible = false
	GameState.set_process(false)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.03, 0.05, 0.92)
	add_child(bg)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)
	message = ("A guy steps out of a doorway with a knife low by his leg. \"Wallet. Now.\"" if knife
		else "Somebody's been walking behind you for a block. Now he's in front of you. \"Give it here.\"")
	SFX.play("blip", -6.0, 0.7)

func _exit_tree() -> void:
	GameState.set_process(true)
	Engine.time_scale = 1.0

func damage_mult() -> float:
	return (SHIV_MULT if Crafting.has_shiv() else 1.0) * lerpf(1.0, 0.6, GameState.sickness())

func dodge_window() -> float:
	return lerpf(DODGE_WINDOW, DODGE_WINDOW * 0.5, GameState.sickness())

# --- The standoff ---------------------------------------------------------------

func choose(i: int) -> void:
	if phase != "standoff":
		return
	match i:
		0:
			_begin_fight()
		1:
			var cash := GameState.cash
			GameState.spend_cash(cash)
			GameState.log_event("Got mugged on the block. Handed over $%d." % cash)
			_end("paid", "You hand over the $%d. He counts it walking away." % cash if cash > 0 else "You turn out your empty pockets. He shoves you into the wall and goes.")
		2:
			if randf() < run_chance():
				GameState.log_event("Got away from a mugger.")
				_end("ran", "You bolt. Footsteps behind you for half a block, then nothing.")
			else:
				# He catches you, and gets the first one in.
				_take_hit()
				_begin_fight()
				message = "You don't get three steps. He drags you back by the hood."

## Your legs: rested and not sick, you'll mostly get away.
func run_chance() -> float:
	return clampf(0.75 - GameState.sickness() * 0.45 - (0.2 if Survival.rest < Survival.LOW else 0.0), 0.15, 0.85)

func _begin_fight() -> void:
	phase = "fight"
	state = "idle"
	t = 0.0
	message = "Shift to dodge his swing, Space to hit."

# --- The fight ------------------------------------------------------------------

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_punch_anim = maxf(0.0, _punch_anim - delta * 4.0)
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
	_dodge_anim = maxf(0.0, _dodge_anim - delta * 3.0)
	_shake = maxf(0.0, _shake - delta * 5.0)
	_canvas.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * _shake
	if phase == "fight":
		step(delta)
	_canvas.queue_redraw()

## Advances the mugger's side of the fight.
func step(delta: float) -> void:
	t += delta
	match state:
		"idle":
			if t > 0.5:
				state = "windup"
				t = 0.0
				windup_len = randf_range(WINDUP.x, WINDUP.y)
		"windup":
			if t >= windup_len:
				_take_hit()
				state = "recover"
				t = 0.0
		"open", "recover":
			if t >= (OPEN_TIME if state == "open" else 0.6):
				state = "idle"
				t = 0.0

func in_dodge_window() -> bool:
	return state == "windup" and windup_len - t <= dodge_window()

func dodge() -> void:
	if phase != "fight":
		return
	_dodge_anim = 1.0
	if in_dodge_window():
		state = "open"
		t = 0.0
		message = "He swings at air. He's wide open."
		SFX.play("steal", -8.0, 1.4)
	elif state == "windup":
		# Too early: he sees it and waits you out.
		t = maxf(0.0, t - 0.2)

func punch() -> void:
	if phase != "fight" or _cooldown > 0.0:
		return
	_cooldown = PUNCH_COOLDOWN
	_punch_anim = 1.0
	var dmg := PUNCH * damage_mult()
	if state == "open":
		dmg *= OPEN_MULT
	elif state == "idle" and randf() < 0.35:
		message = "He blocks it."
		SFX.play("punch", -12.0, 1.3)
		return
	mugger_hp -= dmg
	SFX.play("punch", -4.0, randf_range(0.95, 1.1))
	_impact(0.6 if state != "open" else 1.0)
	if mugger_hp <= 0.0:
		var dropped := randi_range(0, 6)
		if dropped > 0:
			GameState.cash += dropped
			GameState.cash_changed.emit(GameState.cash)
		GameState.log_event("Fought off a mugger on the block.")
		_end("won", "He goes down on one knee, then he's up and running. %s" % ("He dropped $%d." % dropped if dropped > 0 else "Your hands won't stop shaking."))

func _take_hit() -> void:
	var dmg := KNIFE_DMG if knife else SWING_DMG
	lost += dmg
	_hit_flash = 1.0
	SFX.play("punch", -2.0, 0.85)
	_impact(1.0)
	Survival.hurt(dmg, knife)
	message = "The blade catches your arm." if knife else "He catches you on the jaw."
	if Survival.dead:
		_end("lost", "")
		return
	if phase == "fight" and lost >= GO_DOWN:
		var cash := GameState.cash
		GameState.spend_cash(cash)
		Survival.hurt(0.0, true)
		GameState.log_event("Got beaten and robbed on the block.")
		_end("lost", "You're on the pavement and he's going through your pockets. $%d, gone. You're bleeding." % cash)

## Hit-stop and shake: the world freezes for a beat on contact, the way
## fighting games sell a hit.
func _impact(strength: float) -> void:
	_shake = maxf(_shake, strength)
	if not is_inside_tree():
		return
	Engine.time_scale = 0.05
	get_tree().create_timer(0.07 * strength, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)

func _end(result: String, text: String) -> void:
	if phase == "over":
		return
	phase = "over"
	outcome = result
	if text != "":
		message = text
	finished.emit(result)

func _close() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.visible = true
	queue_free()

# --- Input ----------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if phase == "fight":
			punch()
		elif phase == "standoff":
			for i in 3:
				if _option_rect(i).has_point(event.position):
					choose(i)
		elif phase == "over":
			_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	get_viewport().set_input_as_handled()
	if phase == "over":
		if event.is_action_pressed("interact") or event.is_action_pressed("fire") or event.is_action_pressed("cancel_ui") or event.is_action_pressed("ui_accept"):
			_close()
		return
	if phase == "standoff":
		if event.is_action_pressed("ui_up"):
			_choice = (_choice + 2) % 3
		elif event.is_action_pressed("ui_down"):
			_choice = (_choice + 1) % 3
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") or event.is_action_pressed("fire"):
			choose(_choice)
		elif event is InputEventKey and event.keycode in [KEY_1, KEY_2, KEY_3]:
			choose(event.keycode - KEY_1)
		return
	if event.is_action_pressed("sprint") or event.is_action_pressed("ui_left") or event.is_action_pressed("page_prev"):
		dodge()
	elif event.is_action_pressed("fire") or event.is_action_pressed("interact"):
		punch()

# --- Drawing --------------------------------------------------------------------

func _option_rect(i: int) -> Rect2:
	return Rect2(440, 470 + i * 52, 400, 44)

func _draw() -> void:
	var c := _canvas
	var f := ThemeDB.fallback_font
	# The mugger: a dark figure under a streetlight, leaning back to swing.
	var lean := 0.0
	if state == "windup":
		lean = -clampf(t / windup_len, 0.0, 1.0) * 40.0
	elif state == "recover":
		lean = 30.0 * (1.0 - clampf(t / 0.3, 0.0, 1.0))
	elif state == "open":
		lean = 18.0
	var cx := 640.0 + lean - _dodge_anim * 0.0
	c.draw_circle(Vector2(640, 120), 260, Color(1.0, 0.85, 0.55, 0.06))
	var body := Color(0.2, 0.19, 0.22)
	var rim := Color(1.0, 0.8, 0.5, 0.55)
	var torso := PackedVector2Array([Vector2(cx - 110, 470), Vector2(cx - 80, 250), Vector2(cx + 80, 250), Vector2(cx + 110, 470)])
	c.draw_colored_polygon(torso, body)
	c.draw_polyline(PackedVector2Array([torso[0], torso[1], torso[2], torso[3]]), rim, 3.0)
	c.draw_circle(Vector2(cx, 205), 54, rim)
	c.draw_circle(Vector2(cx, 205), 52, body)
	c.draw_circle(Vector2(cx - 16, 200), 4, Color(0.9, 0.85, 0.7, 0.6))
	c.draw_circle(Vector2(cx + 16, 200), 4, Color(0.9, 0.85, 0.7, 0.6))
	# His arm, cocked back on the wind-up.
	var arm_end := Vector2(cx + 120 + lean * 1.5, 300 + lean)
	c.draw_line(Vector2(cx + 70, 270), arm_end, rim, 30)
	c.draw_line(Vector2(cx + 70, 270), arm_end, body, 26)
	if knife:
		c.draw_line(arm_end, arm_end + Vector2(42, -42), Color(0.85, 0.87, 0.9), 6)
	if state == "open":
		c.draw_string(f, Vector2(cx - 40, 150), "OPEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.3))
	# Your fists.
	var reach := _punch_anim * 120.0
	var dx := -_dodge_anim * 160.0
	for side in [-1, 1]:
		var p := Vector2(640 + side * 230 + dx, 640 - (reach if side == 1 else 0.0))
		c.draw_circle(p, 48, Color(0.55, 0.4, 0.32))
		if side == 1 and Crafting.has_shiv():
			c.draw_line(p, p + Vector2(-20, -70), Color(0.7, 0.7, 0.72), 6)
	if _hit_flash > 0.0:
		c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.8, 0.05, 0.05, 0.35 * _hit_flash))
	# Bars: his strength, your health, the wind-up.
	_bar(c, f, Vector2(440, 40), 400, mugger_hp / (KNIFE_HP if knife else MUGGER_HP), Color(0.8, 0.75, 0.6), "HIM")
	_bar(c, f, Vector2(440, 74), 400, Survival.health / Survival.MAX, Color(0.75, 0.25, 0.22), "YOU")
	if phase == "fight" and state == "windup":
		var k := clampf(t / windup_len, 0.0, 1.0)
		var window_start := 1.0 - dodge_window() / windup_len
		c.draw_rect(Rect2(440, 108, 400, 14), Color(0.15, 0.15, 0.15))
		c.draw_rect(Rect2(440 + 400 * window_start, 108, 400 * (1.0 - window_start), 14), Color(0.3, 0.8, 0.4, 0.5))
		c.draw_rect(Rect2(440, 108, 400 * k, 14), Color(0.9, 0.2, 0.15))
		c.draw_string(f, Vector2(850, 121), "DODGE in the green", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.9, 0.7))
	c.draw_string(f, Vector2(140, 440), message, HORIZONTAL_ALIGNMENT_CENTER, 1000, 20, Color(0.95, 0.92, 0.85))
	if phase == "standoff":
		var labels := ["Fight%s" % (" (you've got a shiv)" if Crafting.has_shiv() else ""), "Hand it over ($%d)" % GameState.cash, "Run (%d%%)" % roundi(run_chance() * 100.0)]
		for i in 3:
			var r := _option_rect(i)
			c.draw_rect(r, Color(0.2, 0.18, 0.16) if i != _choice else Color(0.45, 0.2, 0.15))
			c.draw_string(f, r.position + Vector2(16, 29), "%d  %s" % [i + 1, labels[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.8))
	elif phase == "fight":
		c.draw_string(f, Vector2(40, 704), "Shift / Left: dodge   -   Space / click: hit" + ("   -   your shiv's out" if Crafting.has_shiv() else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.62, 0.58))
	else:
		c.draw_string(f, Vector2(40, 704), "[E] / click: get up", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.62, 0.58))

func _bar(c: Control, f: Font, at: Vector2, w: float, frac: float, col: Color, label: String) -> void:
	c.draw_rect(Rect2(at, Vector2(w, 22)), Color(0.12, 0.12, 0.12))
	c.draw_rect(Rect2(at, Vector2(w * clampf(frac, 0.0, 1.0), 22)), col)
	c.draw_string(f, at + Vector2(-50, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.82, 0.75))
