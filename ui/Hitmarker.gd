extends Control
## The crosshair and the hitmarker of Dead Block's first person.
##
## Crosshair: four short ticks round the centre, their gap the gun's spread
## (hip), gone while aiming down the sights. Hitmarker: four short diagonal
## strokes about 8 px from the centre, shown for 0.12 s with a scale punch of
## 1.3 down to 1.0; white on a body hit, bigger and warmer on a headshot,
## red on a kill. WeaponHolder's `hit(part, killed)` drives it; flash() is the
## method the tests call.

const SHOW_TIME := 0.12
const PUNCH := 1.3
const OFFSET := 8.0
const LENGTH := 9.0
const BODY := Color(1, 1, 1)
const HEAD := Color(1.0, 0.93, 0.62)
const KILL := Color(0.95, 0.12, 0.1)

## Seconds the marker has left, what kind it is ("body", "head", "kill").
var left := 0.0
var kind := "body"
var _holder: Node
var _aim := 0.0
## Tests: skip following the holder / camera (they set `spread_px` and `aim_amount` themselves).
var manual := false
var spread_px := 8.0
var aim_amount := 0.0

func _ready() -> void:
	name = "Hitmarker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("hitmarker")

func _hooked() -> bool:
	if is_instance_valid(_holder):
		return true
	_holder = get_tree().get_first_node_in_group("weapon_holder")
	if _holder != null and _holder.has_signal("hit"):
		_holder.connect("hit", _on_hit)
		return true
	return false

func _on_hit(part: String, killed: bool) -> void:
	flash(part, killed)

## Shows the marker: red for a kill, a bigger warm one for the head.
func flash(part: String, killed: bool) -> void:
	kind = "kill" if killed else ("head" if part == "head" else "body")
	left = SHOW_TIME
	queue_redraw()

## Whether the marker is up right now.
func showing() -> bool:
	return left > 0.0

func _process(delta: float) -> void:
	_hooked()
	if left > 0.0:
		left = maxf(left - delta, 0.0)
	if not manual:
		_follow(delta)
	queue_redraw()

## The crosshair follows the gun: gap from the spread, gone as the sights come up.
func _follow(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var d = _holder.get("current") if _holder != null else null
	if cam == null or d == null:
		spread_px = 8.0
		return
	var cone: float = d.spread_ads if _holder.aiming else d.spread_hip
	var half_h := get_viewport_rect().size.y * 0.5
	var px := tan(deg_to_rad(cone)) * half_h / tan(deg_to_rad(cam.fov) * 0.5)
	spread_px = lerpf(spread_px, 5.0 + px, 1.0 - exp(-18.0 * delta))
	_aim = move_toward(_aim, 1.0 if _holder.aiming else 0.0, delta / 0.15)
	aim_amount = _aim

## Whether a sniper rifle's sights are up: the picture is the scope's circle.
func _scoped() -> bool:
	var d = _holder.get("current") if is_instance_valid(_holder) else null
	return d != null and d.family() == "sniper" and aim_amount > 0.85

## A black frame round a round view, hairlines through the middle, and the
## breath: the sight swings in a slow figure-8 (the camera does too, in FPFeel).
func _draw_scope(c: Vector2) -> void:
	var size := get_viewport_rect().size
	var r := size.y * 0.46
	var sway := Vector2(sin(Time.get_ticks_msec() * 0.0013), sin(Time.get_ticks_msec() * 0.0021)) * 3.0
	var mid := c + sway
	var black := Color(0, 0, 0, 1)
	draw_rect(Rect2(0, 0, mid.x - r, size.y), black)
	draw_rect(Rect2(mid.x + r, 0, size.x - mid.x - r, size.y), black)
	var corner := Vector2(r, r).length()
	var thick := corner - r + 4.0
	draw_arc(mid, r + thick * 0.5, 0.0, TAU, 96, black, thick)
	draw_arc(mid, r, 0.0, TAU, 96, Color(0, 0, 0, 0.8), 3.0)
	var line := Color(0, 0, 0, 0.9)
	draw_line(mid + Vector2(-r, 0), mid + Vector2(-8, 0), line, 2.0)
	draw_line(mid + Vector2(8, 0), mid + Vector2(r, 0), line, 2.0)
	draw_line(mid + Vector2(0, -r), mid + Vector2(0, -8), line, 2.0)
	draw_line(mid + Vector2(0, 8), mid + Vector2(0, r), line, 2.0)
	draw_circle(mid, 1.8, Color(0.9, 0.1, 0.1, 0.9))
	for i in range(1, 5):
		draw_circle(mid + Vector2(i * 22.0, 0), 1.5, line)
		draw_circle(mid + Vector2(-i * 22.0, 0), 1.5, line)
		draw_circle(mid + Vector2(0, i * 22.0), 1.5, line)
		draw_circle(mid + Vector2(0, -i * 22.0), 1.5, line)

func _draw() -> void:
	var c := get_viewport_rect().size * 0.5
	var show_cross := Graphics.first_person and ZombieMode.active and not ZombieMode.over
	if show_cross and aim_amount < 0.99:
		var a := 1.0 - aim_amount
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var p0: Vector2 = c + dir * spread_px
			var p1: Vector2 = c + dir * (spread_px + 8.0)
			draw_line(p0, p1, Color(0, 0, 0, 0.55 * a), 4.0)
			draw_line(p0, p1, Color(1, 1, 1, 0.9 * a), 2.0)
	if aim_amount > 0.5 and show_cross and not _scoped():
		draw_circle(c, 1.6, Color(1, 1, 1, 0.85))
	if show_cross and _scoped():
		_draw_scope(c)
	if left <= 0.0:
		return
	var k := left / SHOW_TIME
	var scale := lerpf(1.0, PUNCH, k)
	var col: Color = {"body": BODY, "head": HEAD, "kill": KILL}[kind]
	var len := LENGTH * (1.35 if kind != "body" else 1.0) * scale
	var off := OFFSET * scale
	var alpha := clampf(k * 2.0, 0.0, 1.0)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var dir := Vector2(sx, sy).normalized()
			var p0 := c + dir * off
			var p1 := c + dir * (off + len)
			draw_line(p0, p1, Color(0, 0, 0, 0.7 * alpha), 5.0)
			draw_line(p0, p1, Color(col.r, col.g, col.b, alpha), 2.6)
