extends Control
## Four ticks around the centre that open up with the rifle's actual spread,
## so the crosshair tells the truth about where rounds can land. Also draws
## the hitmarker: white for a hit, red for a kill, bigger for a headshot.

const TICK := 7.0
const THICK := 2.0
const COLOR := Color(0.95, 0.93, 0.88, 0.9)
const OUTLINE := Color(0, 0, 0, 0.6)

## Distance from centre to each tick, in pixels.
var gap: float = 8.0
var lines_alpha: float = 1.0
var _hit_t: float = 0.0
var _hit_kill: bool = false
var _hit_head: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func hit(killed: bool, headshot: bool) -> void:
	_hit_t = 1.0
	_hit_kill = killed
	_hit_head = headshot

func _process(delta: float) -> void:
	_hit_t = maxf(0.0, _hit_t - delta * (2.2 if _hit_kill else 4.5))
	queue_redraw()

func _tick(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, Color(OUTLINE, OUTLINE.a * color.a), THICK + 2.0)
	draw_line(from, to, color, THICK)

func _draw() -> void:
	var c := size * 0.5
	if lines_alpha > 0.01:
		var col := Color(COLOR, COLOR.a * lines_alpha)
		var g := gap
		_tick(c + Vector2(0, -g), c + Vector2(0, -g - TICK), col)
		_tick(c + Vector2(0, g), c + Vector2(0, g + TICK), col)
		_tick(c + Vector2(-g, 0), c + Vector2(-g - TICK, 0), col)
		_tick(c + Vector2(g, 0), c + Vector2(g + TICK, 0), col)
		draw_circle(c, 1.5, col)
	if _hit_t > 0.0:
		var col := Color(0.95, 0.15, 0.12, _hit_t) if _hit_kill else Color(1, 1, 1, _hit_t)
		var inner := 6.0
		var outer := 14.0 if _hit_head or _hit_kill else 11.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			_tick(c + n * inner, c + n * outer, col)
