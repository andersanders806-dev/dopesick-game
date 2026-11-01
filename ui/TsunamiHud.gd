extends CanvasLayer
## The tsunami's own HUD layer (above the zombie HUD, below the pause menu and the game over):
##   - an emergency broadcast banner that slides in (red and black, flicker, scanlines), then settles
##     into a slim strip with a scrolling alert across the top;
##   - the big countdown (it pops on every second of the last ten, and goes red);
##   - DROWNED 0/2 and what to do;
##   - markers for the two Drowned (a diamond with the distance over one in view, an arrow on the screen's
##     edge for one that is not) and, in the last half minute, one for the wave: readable on a pad,
##     and no sound needed;
##   - the dread: a pulsing vignette, red flashes on the countdown pulses;
##   - the relief banner when it is cancelled, and the water that takes the screen when it is not.
## Driven by fx/Tsunami.gd; it decides nothing.

const BLOOD := Color(0.78, 0.06, 0.06)
const PAPER := Color(0.93, 0.9, 0.82)
const SEA := Color(0.5, 0.92, 0.86)
const STRIP_TEXT := "   TSUNAMI WARNING  -  EVACUATE TO HIGH GROUND  -  A WAVE IS EXPECTED ON THE BLOCK  -  DO NOT REMAIN IN THE STREET  -  THIS IS NOT A TEST   "

const VIGNETTE := """shader_type canvas_item;
uniform float amount = 0.0;
uniform float pulse = 0.0;
uniform vec3 tint = vec3(0.0, 0.1, 0.07);
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.5, 1.0);
	float e = smoothstep(0.25, 0.98, length(d));
	vec3 flash = vec3(0.6, 0.02, 0.02) * pulse;
	float a = clamp(e * amount + pulse * e * 0.9, 0.0, 0.92);
	COLOR = vec4(tint * 0.35 + flash * e, a);
}"""

const SCAN := """shader_type canvas_item;
uniform float strength = 0.18;
void fragment() {
	float line = 0.5 + 0.5 * sin(UV.y * 900.0);
	float roll = smoothstep(0.0, 1.0, fract(UV.y * 0.8 - TIME * 0.12));
	COLOR = vec4(0.0, 0.0, 0.0, strength * line + 0.04 * roll);
}"""

const WATER := """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, repeat_disable, filter_linear;
uniform float foam = 0.0;
uniform float under = 0.0;
void fragment() {
	vec2 w = vec2(sin(UV.y * 38.0 + TIME * 3.1), cos(UV.x * 27.0 + TIME * 2.4)) * 0.006 * under;
	vec3 c = textureLod(screen, SCREEN_UV + w, 0.0).rgb;
	float luma = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 sea = mix(vec3(0.02, 0.1, 0.12), vec3(0.14, 0.42, 0.45), luma);
	c = mix(c, sea, under);
	float caustic = sin((UV.x + sin(UV.y * 9.0 + TIME) * 0.05) * 38.0 + TIME * 1.5) * sin((UV.y + cos(UV.x * 7.0 - TIME) * 0.05) * 31.0 - TIME * 1.1);
	c += vec3(0.04, 0.12, 0.12) * max(caustic, 0.0) * under * (1.0 - UV.y * 0.6);
	float depth = smoothstep(0.0, 1.0, UV.y);
	c *= 1.0 - 0.45 * under * depth;
	vec2 d = (UV - 0.5) * vec2(1.4, 1.0);
	c *= 1.0 - under * 0.55 * smoothstep(0.3, 1.0, length(d));
	vec3 f = vec3(0.7, 0.85, 0.82);
	float n = 0.5 + 0.5 * sin(UV.x * 23.0 + sin(UV.y * 11.0 + TIME * 6.0) * 2.0);
	float fm = clamp(foam * (0.75 + 0.5 * n), 0.0, 1.0);
	COLOR = vec4(mix(c, f, fm), 1.0);
}"""

var strip: Control
var strip_label: Label
var banner: Control
var timer_label: Label
var tracker_label: Label
var hint_label: Label
var markers: Control
var vignette: ColorRect
var water: ColorRect
var cancel_banner: Control
var cancel_label: Label
var bonus_label: Label
var bubbles: CPUParticles2D

var time_text := "2:00"
var remaining := 120.0
var total := 120.0
var killed := 0
var needed := 2
var targets: Array = []
var wave_dir := Vector3.ZERO
var wave_marker := false
var safe_at := Vector3.ZERO
var safe_marker := false
var dread := 0.0
var pulse := 0.0
var shown := false
## Flicker dips so far (the tests look for them).
var flickers := 0

var _font: Font
var _pop := 0.0
var _flicker_t := 0.8
var _flicker_off := 0.0
var _strip_x := 0.0
var _banner_tween: Tween
var _cancel_tween: Tween
var _beat := 0.0
var _last_second := -1
## Where this frame's edge arrows are (they keep apart).
var _placed: Array[Vector2] = []

func _ready() -> void:
	layer = 14
	name = "TsunamiHud"
	add_to_group("tsunami_hud")
	var f := FontVariation.new()
	f.base_font = load("res://assets/fonts/Bungee-Regular.ttf")
	_font = f
	vignette = _rect(VIGNETTE)
	markers = Control.new()
	markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	markers.draw.connect(_draw_markers)
	add_child(markers)
	_build_strip()
	_build_timer()
	_build_banner()
	_build_cancel()
	water = _rect(WATER)
	water.visible = false
	_build_bubbles()
	_set_shown(false)

func _rect(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	add_child(r)
	return r

func _label(text: String, size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 6)
	parent.add_child(l)
	return l

## The slim strip across the top, with the alert crawling along it.
func _build_strip() -> void:
	strip = Control.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 24.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.clip_contents = true
	add_child(strip)
	var bg := ColorRect.new()
	bg.color = Color(0.5, 0.02, 0.02, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(bg)
	strip_label = _label(STRIP_TEXT + STRIP_TEXT, 15, PAPER, strip)
	strip_label.position = Vector2(0, -2)
	var scan := _rect(SCAN)
	remove_child(scan)
	strip.add_child(scan)

## The full broadcast card: slides in from above, holds, and goes.
func _build_banner() -> void:
	banner = Control.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# not over the seismograph (top right, 330 wide) while the quake is still on
	banner.offset_right = -372.0
	banner.offset_bottom = 190.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.0, 0.0, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg)
	var bar := ColorRect.new()
	bar.color = BLOOD
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.offset_top = 48.0
	bar.offset_bottom = -52.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bar)
	var head := _label("EMERGENCY ALERT SYSTEM    CIVIL DEFENSE    ALL STATIONS", 18, Color(0.85, 0.2, 0.2), banner)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 14.0
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var big := _label("TSUNAMI WARNING", 70, PAPER, banner)
	big.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	big.offset_top = 40.0
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label("EVACUATE TO HIGH GROUND", 30, Color(1.0, 0.82, 0.3), banner)
	sub.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sub.offset_top = -50.0
	sub.offset_bottom = -8.0
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scan := _rect(SCAN)
	remove_child(scan)
	banner.add_child(scan)
	banner.position.y = -260.0

func _build_timer() -> void:
	timer_label = _label("2:00", 84, PAPER, self)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	timer_label.offset_top = 40.0
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tracker_label = _label("DROWNED  0 / 2", 34, SEA, self)
	tracker_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tracker_label.offset_top = 146.0
	tracker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label = _label("KILL BOTH BEFORE THE WAVE", 18, Color(0.85, 0.82, 0.74), self)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint_label.offset_top = 186.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.pivot_offset = Vector2(640, 48)
	timer_label.resized.connect(func(): timer_label.pivot_offset = timer_label.size * 0.5)

func _build_cancel() -> void:
	cancel_banner = Control.new()
	cancel_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	cancel_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cancel_banner.modulate.a = 0.0
	add_child(cancel_banner)
	cancel_label = _label("TSUNAMI CANCELLED", 76, Color(0.78, 1.0, 0.9), cancel_banner)
	cancel_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	cancel_label.offset_top = 90.0
	cancel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_label = _label("", 44, Color(1.0, 0.82, 0.3), cancel_banner)
	bonus_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bonus_label.offset_top = 184.0
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_bubbles() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length()
			var ring := smoothstep(11.0, 14.0, d) * (1.0 - smoothstep(14.0, 15.5, d))
			var fill := (1.0 - smoothstep(0.0, 14.0, d)) * 0.12
			img.set_pixel(x, y, Color(0.8, 0.95, 1.0, clampf(ring * 0.8 + fill, 0.0, 1.0)))
	bubbles = CPUParticles2D.new()
	bubbles.texture = ImageTexture.create_from_image(img)
	bubbles.emitting = false
	bubbles.amount = 70
	bubbles.lifetime = 2.6
	bubbles.preprocess = 0.0
	bubbles.direction = Vector2(0, -1)
	bubbles.spread = 18.0
	bubbles.gravity = Vector2(0, -60)
	bubbles.initial_velocity_min = 120.0
	bubbles.initial_velocity_max = 380.0
	bubbles.scale_amount_min = 0.3
	bubbles.scale_amount_max = 1.5
	bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	bubbles.emission_rect_extents = Vector2(700, 8)
	add_child(bubbles)

func _process(delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	bubbles.position = Vector2(size.x * 0.5, size.y + 20.0)
	bubbles.emission_rect_extents = Vector2(size.x * 0.5, 8.0)
	if not shown:
		return
	# the alert crawls
	_strip_x -= 70.0 * delta
	var one := strip_label.get_minimum_size().x * 0.5
	if one > 10.0 and _strip_x < -one:
		_strip_x += one
	strip_label.position.x = _strip_x
	# the broadcast flickers: now and then it drops out for a blink
	_flicker_t -= delta
	if _flicker_t <= 0.0:
		_flicker_t = randf_range(0.25, 1.6)
		_flicker_off = randf_range(0.04, 0.12)
		flickers += 1
	if _flicker_off > 0.0:
		_flicker_off -= delta
	var a := 0.25 if _flicker_off > 0.0 else 1.0
	strip.modulate.a = a
	banner.modulate.a = a
	# the clock's pop settles
	_pop = move_toward(_pop, 0.0, delta * 3.2)
	timer_label.scale = Vector2.ONE * (1.0 + 0.32 * _pop)
	var red := remaining <= 30.0
	var col := PAPER.lerp(BLOOD, 1.0 if red else 0.0)
	if remaining <= 10.0:
		col = BLOOD.lerp(Color(1, 0.9, 0.85), _pop * 0.7)
	timer_label.add_theme_color_override("font_color", col)
	pulse = move_toward(pulse, 0.0, delta * 2.6)
	# the heart: a slow thump under the vignette in the last half minute
	var rate := 0.0
	if remaining <= 10.0:
		rate = 2.2
	elif remaining <= 30.0:
		rate = 1.15
	_beat += delta * rate
	var thump := 0.0
	if rate > 0.0:
		var ph := fposmod(_beat, 1.0)
		thump = exp(-ph * 9.0) * 0.7 + exp(-maxf(ph - 0.22, 0.0) * 12.0) * (0.45 if ph > 0.22 else 0.0)
	var motion := 1.0 if Graphics.camera_motion else 0.4
	var m := vignette.material as ShaderMaterial
	m.set_shader_parameter("amount", clampf(dread * 0.75 + thump * 0.25 * motion, 0.0, 0.9))
	m.set_shader_parameter("pulse", clampf(pulse * motion + thump * 0.18 * motion, 0.0, 1.0))
	markers.queue_redraw()

# --- Driven by the Tsunami -------------------------------------------------------------------

func _set_shown(on: bool) -> void:
	shown = on
	strip.visible = on
	banner.visible = on
	timer_label.visible = on
	tracker_label.visible = on
	hint_label.visible = on
	markers.visible = on

## The warning card slides in, holds and goes; the strip, clock and tracker stay.
func start(total_seconds: float, need: int, banner_delay := 0.0) -> void:
	total = total_seconds
	remaining = total_seconds
	needed = need
	killed = 0
	targets = []
	wave_marker = false
	_last_second = -1
	_set_shown(true)
	cancel_banner.modulate.a = 0.0
	set_time(total_seconds)
	set_kills(0, need)
	if _banner_tween != null:
		_banner_tween.kill()
	banner.position.y = -260.0
	_banner_tween = create_tween()
	if banner_delay > 0.0:
		_banner_tween.tween_interval(banner_delay)
	_banner_tween.tween_property(banner, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(6.0)
	_banner_tween.tween_property(banner, "position:y", -260.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hint_label.modulate.a = 1.0

func format_time(t: float) -> String:
	var s := int(ceil(maxf(t, 0.0) - 0.0001))
	return "%d:%02d" % [s / 60, s % 60]

func set_time(t: float) -> void:
	remaining = t
	time_text = format_time(t)
	timer_label.text = time_text
	var sec := int(ceil(t))
	if sec != _last_second:
		if _last_second >= 0 and sec <= 10 and sec >= 1:
			_pop = 1.0
			pulse = 0.9
		elif _last_second >= 0 and sec <= 30 and sec % 5 == 0:
			_pop = 0.35
		_last_second = sec

func set_kills(n: int, need: int) -> void:
	killed = n
	needed = need
	tracker_label.text = "DROWNED  %d / %d" % [n, need]
	tracker_label.add_theme_color_override("font_color", SEA if n < need else Color(0.6, 1.0, 0.6))
	hint_label.visible = shown and n < need

func set_hint(text: String) -> void:
	hint_label.text = text
	hint_label.visible = shown and killed < needed and text != ""

func set_targets(list: Array) -> void:
	targets = list

## The high ground's marker (a world point, shown while `on`).
func set_safe(at: Vector3, on: bool) -> void:
	safe_at = at
	safe_marker = on

func set_wave(dir: Vector3, on: bool) -> void:
	wave_dir = dir
	wave_marker = on

## 0..1: how much of the dread (vignette) there is now.
func set_dread(d: float) -> void:
	dread = clampf(d, 0.0, 1.0)

func flash(strength := 0.8) -> void:
	pulse = maxf(pulse, strength)

## The relief card.
func show_cancelled(bonus: int, title := "TSUNAMI CANCELLED") -> void:
	cancel_label.text = title
	bonus_label.text = "+%d" % bonus
	timer_label.visible = false
	tracker_label.visible = false
	hint_label.visible = false
	markers.visible = false
	strip.visible = false
	if _banner_tween != null:
		_banner_tween.kill()
	banner.position.y = -260.0
	if _cancel_tween != null:
		_cancel_tween.kill()
	cancel_banner.modulate.a = 0.0
	cancel_banner.position.y = -40.0
	_cancel_tween = create_tween()
	_cancel_tween.set_parallel(true)
	_cancel_tween.tween_property(cancel_banner, "modulate:a", 1.0, 0.35)
	_cancel_tween.tween_property(cancel_banner, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cancel_tween.chain().tween_interval(3.6)
	_cancel_tween.chain().tween_property(cancel_banner, "modulate:a", 0.0, 1.2)
	_cancel_tween.tween_callback(func(): _set_shown(false))
	set_dread(0.0)
	pulse = 0.0

## The screen taken by the water: foam 0..1 (the white wall arriving) and under 0..1 (the sea).
func set_engulf(foam: float, under: float) -> void:
	var on := foam > 0.001 or under > 0.001
	water.visible = on
	var m := water.material as ShaderMaterial
	m.set_shader_parameter("foam", foam)
	m.set_shader_parameter("under", under)
	bubbles.emitting = under > 0.4

## The HUD's own bits put away (the run is over or the countdown was cancelled).
func clear() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	if _cancel_tween != null:
		_cancel_tween.kill()
	_set_shown(false)
	cancel_banner.modulate.a = 0.0
	set_dread(0.0)
	pulse = 0.0
	set_engulf(0.0, 0.0)

# --- Markers -----------------------------------------------------------------------------------

func _draw_markers() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not shown:
		return
	var rect := Rect2(Vector2.ZERO, markers.size)
	_placed = []
	for t in targets:
		if not is_instance_valid(t) or not t.has_method("is_alive") or not t.is_alive():
			continue
		var warn := int(t.get("charge")) == 1
		var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.025)
		var col := Color(1.0, 0.9, 0.2).lerp(Color(1.0, 0.2, 0.1), flash) if warn else Color(1.0, 0.35, 0.28)
		_mark(cam, rect, (t as Node3D).global_position + Vector3(0, 2.9, 0), "CHARGE!" if warn else "DROWNED", col, t)
	if safe_marker:
		_mark(cam, rect, safe_at, "HIGH GROUND", Color(0.45, 1.0, 0.55), null, true)
	if wave_marker and wave_dir != Vector3.ZERO:
		var far := cam.global_position + wave_dir * 400.0 + Vector3(0, 30.0, 0)
		_mark(cam, rect, far, "WAVE", SEA, null)

func _mark(cam: Camera3D, rect: Rect2, at: Vector3, label: String, color: Color, who: Node, show_dist := false) -> void:
	var local := cam.global_transform.affine_inverse() * at
	var dist := cam.global_position.distance_to(at)
	var margin := 64.0
	var sp := cam.unproject_position(at) if local.z < 0.0 else Vector2(-9999, -9999)
	var inside := rect.grow(-margin).has_point(sp)
	var meters := "%dm" % int(dist) if (who != null or show_dist) else ""
	if inside:
		var p := Vector2(sp.x, maxf(sp.y - 26.0, 232.0))
		var s := clampf(1.3 - dist / 70.0, 0.75, 1.3)
		var pts := PackedVector2Array([p + Vector2(0, 16) * s, p + Vector2(-14, 0) * s, p + Vector2(0, -16) * s, p + Vector2(14, 0) * s])
		markers.draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		markers.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), color, 3.0, true)
		if who != null and who.get("max_health") != null:
			var ratio := clampf(float(who.get("health")) / maxf(float(who.get("max_health")), 1.0), 0.0, 1.0)
			var bar := Rect2(p + Vector2(-34, 22) * s, Vector2(68, 7) * s)
			markers.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.7))
			markers.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), color)
			if bool(who.get("helmet_on")):
				markers.draw_rect(Rect2(bar.position + Vector2(0, bar.size.y + 3), Vector2(bar.size.x * clampf(float(who.get("helmet")) / maxf(float(who.get("helmet_max")), 1.0), 0.0, 1.0), 4.0 * s)), Color(0.8, 0.8, 0.7))
		markers.draw_string(_font, p + Vector2(-100, -22) * s, ("%s %s" % [label, meters]).strip_edges(), HORIZONTAL_ALIGNMENT_CENTER, 200.0, int(18 * s), color)
	else:
		# off screen: an arrow on the edge, pointing the way to turn
		var dir := Vector2(local.x, -local.y)
		if local.z > 0.0 and dir.length() < 0.001:
			dir = Vector2(0, 1)
		if dir.length() < 0.001:
			dir = Vector2(0, -1)
		dir = dir.normalized()
		if local.z > 0.0:
			# behind: the side it is on, along the lower part of the screen
			dir = Vector2(signf(local.x) if absf(local.x) > 0.05 else 1.0, 0.55).normalized()
		# the arrow rides the edge of a box that keeps clear of the clock, the points and the ammo
		var box_top := 130.0
		var box_bottom := rect.size.y - 270.0
		var centre := Vector2(rect.size.x * 0.5, (box_top + box_bottom) * 0.5)
		var sx := (rect.size.x * 0.5 - 70.0) / maxf(absf(dir.x), 0.0001)
		var sy := ((box_bottom - box_top) * 0.5) / maxf(absf(dir.y), 0.0001)
		var p := centre + dir * minf(sx, sy)
		# never on top of another arrow: slide along the edge until there is room
		var tangent := Vector2(-dir.y, dir.x)
		for attempt in 4:
			var clash := false
			for q in _placed:
				if absf(p.x - q.x) < 190.0 and absf(p.y - q.y) < 56.0:
					clash = true
			if not clash:
				break
			p += tangent * 70.0
			p.x = clampf(p.x, 70.0, rect.size.x - 70.0)
			p.y = clampf(p.y, box_top, box_bottom)
			if attempt == 1:
				tangent = -tangent
		_placed.append(p)
		var ang := dir.angle()
		var tri := PackedVector2Array([Vector2(26, 0), Vector2(-14, -20), Vector2(-4, 0), Vector2(-14, 20)])
		var xf := Transform2D(ang, p)
		var pts := PackedVector2Array()
		for q in tri:
			pts.append(xf * q)
		markers.draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
		markers.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), color, 3.0, true)
		var text := ("%s %s" % [label, meters]).strip_edges()
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		# the words go inward of the arrow, never on it
		var centre_text := p - Vector2(signf(dir.x) * (38.0 + tw * 0.5), -6.0) if absf(dir.x) >= absf(dir.y) * 0.8 else p - Vector2(0.0, signf(dir.y) * 34.0 - 6.0)
		markers.draw_string(_font, centre_text - Vector2(tw * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
