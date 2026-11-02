extends Control
## The "+points" that float up beside the score when a shot pays: a small
## white +10 for a hit, gold +60 for a kill, a bigger orange +100 for a
## headshot, red for a spend. Pooled labels (eight), each pushed up as a newer
## one arrives so a burst of fire reads as a column rather than a pile.

const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const POOL := 8
const LIFE := 1.1
const RISE := 38.0
const STEP := 26.0
const PAPER := Color(0.93, 0.9, 0.82)
const GOLD := Color(1.0, 0.82, 0.3)
const HEAD := Color(1.0, 0.55, 0.2)
const BLOOD := Color(0.85, 0.12, 0.12)

## Where the newest one starts (the hud puts it beside the score).
var origin := Vector2(200, 600)
var _labels: Array[Label] = []
var _age: Array[float] = []
var _shift: Array[float] = []
var _next := 0

func _ready() -> void:
	name = "PointsPopup"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var font := FontVariation.new()
	font.base_font = FONT
	for i in POOL:
		var l := Label.new()
		l.visible = false
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", font)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", 6)
		l.pivot_offset = Vector2(0, 14)
		add_child(l)
		_labels.append(l)
		_age.append(LIFE)
		_shift.append(0.0)

## A popup for `amount`; `reason` is "hit", "kill", "head" or anything else (a spend / bonus).
func add(amount: int, reason := "") -> void:
	var l := _labels[_next]
	var i := _next
	_next = (_next + 1) % POOL
	# Everything showing makes room.
	for j in POOL:
		if j != i and _age[j] < LIFE:
			_shift[j] += STEP
	var col := PAPER
	var size := 22
	if amount < 0:
		col = BLOOD
		size = 24
	elif reason == "head" or amount >= 100:
		col = HEAD
		size = 32
	elif reason == "kill" or amount >= 50:
		col = GOLD
		size = 28
	l.text = "%+d" % amount
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.visible = true
	l.modulate.a = 1.0
	_age[i] = 0.0
	_shift[i] = 0.0
	_place(i)

## How many are on screen.
func active() -> int:
	var n := 0
	for j in POOL:
		if _age[j] < LIFE:
			n += 1
	return n

func _process(delta: float) -> void:
	for j in POOL:
		if _age[j] >= LIFE:
			continue
		_age[j] += delta
		if _age[j] >= LIFE:
			_labels[j].visible = false
			continue
		_place(j)

func _place(j: int) -> void:
	var l := _labels[j]
	var t := clampf(_age[j] / LIFE, 0.0, 1.0)
	l.position = origin + Vector2(0.0, -RISE * (1.0 - pow(1.0 - t, 2.0)) - _shift[j])
	l.modulate.a = 1.0 - smoothstep(0.6, 1.0, t)
	var punch := lerpf(1.3, 1.0, clampf(_age[j] / 0.1, 0.0, 1.0))
	l.scale = Vector2.ONE * punch
