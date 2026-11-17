extends Control
## The lethal slot's part of the HUD (SHIP 16G): the Mk 2 frag count above the gun's name (icon and number, red at none), and
## the danger arrows: for every live grenade within 12 m of the camera (yours, the crews') a red arrow on a ring round the
## crosshair pointing to where it is, with a grenade beside it, pulsing faster as its fuse runs down and solid once you are
## inside its blast. Added by ui/ZombieHud.gd (so Ghetto Wars' HUD has it too). Everything is drawn here, no node per arrow.

const U := preload("res://ui/UiStyle.gd")
const Glyphs := preload("res://ui/Glyphs.gd")
const PAPER := Color(0.93, 0.9, 0.82)
const RED := Color(0.92, 0.13, 0.1)
const REACH := 12.0

var holder: Node
## For the tests: the arrows now: [{angle (rad, 0 ahead, + right), dist, fuse, inside}].
var arrows: Array = []
var count := -1
## Seconds the "[G] MK 2 FRAG" hint still shows (6 s from the start of a run, 3 s after a restock), and the pulse of the red 0.
var hint_t := 6.0
var pulse_t := 0.0
var _wired: Node
var _font: Font

func _ready() -> void:
	name = "GrenadeHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = U.font(U.COND_BOLD, 1)

func _process(delta: float) -> void:
	if not is_instance_valid(holder):
		holder = get_tree().get_first_node_in_group("weapon_holder")
	if holder != null and _wired != holder:
		_wired = holder
		holder.grenades_changed.connect(_on_count)
		if holder.get("lethal") != null:
			holder.lethal.empty_pressed.connect(func(): pulse_t = 0.4)
	hint_t = maxf(hint_t - delta, 0.0)
	pulse_t = maxf(pulse_t - delta, 0.0)
	count = int(holder.get("grenades")) if holder != null else -1
	_collect()
	queue_redraw()

func _on_count(n: int) -> void:
	# A restock (the count went up) shows the key again for a moment.
	if n > count and count >= 0:
		hint_t = 3.0

func _collect() -> void:
	arrows.clear()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var inv := cam.global_transform.basis.inverse()
	for g in get_tree().get_nodes_in_group("live_grenade"):
		if not g.has_method("fuse_left") or not (g is Node3D):
			continue
		var fuse: float = g.fuse_left()
		if fuse == INF:
			continue
		var delta: Vector3 = (g as Node3D).global_position - cam.global_position
		if delta.length() > REACH:
			continue
		var local := inv * delta
		var r: float = g.danger_radius() if g.has_method("danger_radius") else 6.0
		arrows.append({"angle": atan2(local.x, -local.z), "dist": delta.length(), "fuse": fuse, "inside": delta.length() <= r})

func _draw() -> void:
	if count >= 0:
		_draw_count()
	var centre := size * 0.5
	var ring := minf(size.x, size.y) * 0.34
	var t := Time.get_ticks_msec() * 0.001
	for a in arrows:
		var f: float = clampf(1.0 - float(a["fuse"]) / 3.5, 0.0, 1.0)
		var pulse := 0.62 + 0.38 * sin(t * lerpf(7.0, 28.0, f))
		var alpha := 0.95 if a["inside"] else pulse
		var dir := Vector2(sin(float(a["angle"])), -cos(float(a["angle"])))
		var at := centre + dir * ring
		var side := Vector2(-dir.y, dir.x)
		var k := 1.25 if a["inside"] else 1.0
		var pts := PackedVector2Array([at + dir * 20.0 * k, at - dir * 8.0 * k + side * 17.0 * k, at - dir * 1.0 * k, at - dir * 8.0 * k - side * 17.0 * k])
		draw_colored_polygon(pts, Color(RED.r, RED.g, RED.b, alpha))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, alpha * 0.7), 2.0)
		draw_icon(at - dir * 34.0 * k, 0.8 * k, Color(PAPER.r, PAPER.g, PAPER.b, alpha))

func _draw_count() -> void:
	var right := size.x - U.SAFE_X
	var base := size.y - (U.SAFE_Y + 104.0)
	var col := PAPER if count > 0 else Color(RED.r, RED.g, RED.b, 0.9)
	# The empty pouch answered a press: the 0 swells and flashes for 0.4 s.
	var swell := sin(clampf(pulse_t / 0.4, 0.0, 1.0) * PI) if pulse_t > 0.0 else 0.0
	var fs := int(40.0 + 16.0 * swell)
	if swell > 0.0:
		col = col.lerp(Color(1.0, 0.45, 0.35), swell)
	var txt := str(count)
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(right - w + 2.0, base + 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(_font, Vector2(right - w, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_icon(Vector2(right - w - 22.0, base - 17.0), 1.0, col)
	# The name and the key, for the first seconds of a run and after a restock.
	if hint_t > 0.0:
		var a := clampf(hint_t / 0.6, 0.0, 1.0)
		var hint := "[%s]  MK 2 FRAG" % Glyphs.name_of("lethal")
		var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var hx := right - w - 44.0 - hw
		draw_string(_font, Vector2(hx + 1.0, base - 9.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.6 * a))
		draw_string(_font, Vector2(hx, base - 10.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.96, 0.74, 0.16, a))

## The Mk 2 as a small drawing, centred on `c`: segmented body, cap, lever and ring.
func draw_icon(c: Vector2, k: float, col: Color) -> void:
	var body := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		body.append(c + Vector2(cos(a) * 9.0, sin(a) * 12.0 + 3.0) * k)
	draw_colored_polygon(body, col)
	var dark := Color(0, 0, 0, col.a * 0.55)
	for dx in [-4.0, 0.0, 4.0]:
		draw_line(c + Vector2(dx, -7.0) * k, c + Vector2(dx, 15.0) * k, dark, 1.4 * k)
	for dy in [0.0, 6.0, 12.0]:
		draw_line(c + Vector2(-8.0, dy) * k, c + Vector2(8.0, dy) * k, dark, 1.4 * k)
	draw_rect(Rect2(c + Vector2(-4.0, -15.0) * k, Vector2(8.0, 6.0) * k), col)
	draw_line(c + Vector2(4.0, -14.0) * k, c + Vector2(12.0, -10.0) * k, col, 2.4 * k)
	draw_line(c + Vector2(12.0, -10.0) * k, c + Vector2(12.0, 8.0) * k, col, 2.4 * k)
	draw_arc(c + Vector2(-5.0, -18.0) * k, 4.5 * k, 0.0, TAU, 14, col, 1.6 * k)
