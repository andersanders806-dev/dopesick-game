extends Control
## The seismograph on Dead Block's HUD (top right) while the RICHTER 8.0 surge builds and hits: a
## jagged trace scrolling left across a dark panel and a readout in blood red climbing from 1.0 to
## 8.0. fx/Quake.gd feeds it (`amplitude`, `value`, `shown`); it only draws. ZombieHud owns it.

const BLOOD := Color(0.72, 0.08, 0.08)
const PAPER := Color(0.93, 0.9, 0.82)
const SIZE := Vector2(330.0, 150.0)
## Trace samples per second and how many the panel holds (about 2 px each).
const RATE := 48.0
const SAMPLES := 150

## 0..1: how hard the ground moves right now (the trace's height).
var amplitude := 0.0
## The magnitude on the readout.
var value := 1.0
## Whether the panel is up (it fades in and out).
var shown := false: set = _set_shown
## Seconds the trace has run (the tests read it).
var scrolled := 0.0
var _trace: PackedFloat32Array = PackedFloat32Array()
var _acc := 0.0
var _fade := 0.0
var _font: Font
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "Seismograph"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -SIZE.x - 28.0
	offset_right = -28.0
	offset_top = 26.0
	offset_bottom = 26.0 + SIZE.y
	_trace.resize(SAMPLES)
	_rng.randomize()
	visible = false
	modulate.a = 0.0

func _ready() -> void:
	var f := FontVariation.new()
	f.base_font = load("res://assets/fonts/Bungee-Regular.ttf")
	_font = f

func _set_shown(on: bool) -> void:
	shown = on
	if on:
		visible = true

## The readout text ("RICHTER 8.0").
func readout() -> String:
	return "RICHTER %.1f" % value

func clear() -> void:
	_trace.fill(0.0)
	amplitude = 0.0
	value = 1.0
	scrolled = 0.0
	_acc = 0.0

## Steps the trace and the fade by `delta` seconds (the tests call it by hand).
func advance(delta: float) -> void:
	_fade = move_toward(_fade, 1.0 if shown else 0.0, delta / (0.25 if shown else 1.2))
	modulate.a = _fade
	if _fade <= 0.0 and not shown:
		visible = false
		return
	scrolled += delta
	_acc += delta * RATE
	while _acc >= 1.0:
		_acc -= 1.0
		# Jagged: a noisy swing, now and then a spike, riding the amplitude.
		var s := _rng.randf_range(-1.0, 1.0)
		if _rng.randf() < 0.12:
			s = signf(s) * _rng.randf_range(0.85, 1.25)
		_trace.remove_at(0)
		_trace.append(s * amplitude + _rng.randf_range(-0.03, 0.03))
	queue_redraw()

func _process(delta: float) -> void:
	if visible:
		advance(delta)

func _draw() -> void:
	if _font == null:
		return
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.02, 0.0, 0.0, 0.62))
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(BLOOD, 0.7), false, 2.0)
	draw_string(_font, Vector2(14.0, 22.0), "SEISMIC ACTIVITY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(PAPER, 0.7))
	var hot := value >= 7.95
	draw_string(_font, Vector2(14.0, 66.0), readout(), HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 20.0, 40, BLOOD.lightened(0.18) if hot else BLOOD)
	# The trace on a grid.
	var top := 78.0
	var mid := top + (SIZE.y - top - 8.0) * 0.5
	var half := (SIZE.y - top - 8.0) * 0.5
	for i in 5:
		var gx := 12.0 + i * (SIZE.x - 24.0) / 4.0
		draw_line(Vector2(gx, top), Vector2(gx, SIZE.y - 8.0), Color(PAPER, 0.07), 1.0)
	draw_line(Vector2(12.0, mid), Vector2(SIZE.x - 12.0, mid), Color(PAPER, 0.16), 1.0)
	var pts := PackedVector2Array()
	var step := (SIZE.x - 24.0) / float(SAMPLES - 1)
	for i in SAMPLES:
		pts.append(Vector2(12.0 + i * step, mid - clampf(_trace[i], -1.2, 1.2) * half * 0.92))
	draw_polyline(pts, Color(BLOOD, 0.35), 5.0)
	draw_polyline(pts, BLOOD.lightened(0.25), 1.8)
