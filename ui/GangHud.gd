extends "res://ui/ZombieHud.gd"
## Ghetto Wars' HUD: Dead Block's (points, gun, prompts, hitmarker, the red edge when hurt) plus the fight's own:
## the wave in the crew's voice, three armour plates, red arcs on the ring round the crosshair pointing at who is
## shooting you, the blur and darkening of rounds going past (suppression), and what the crew shouts, in text.

const CALLOUT_LIFE := 4.0
const CALLOUT_MAX := 4
const ARC_LIFE := 1.6
const ARC_RADIUS := 170.0

const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5);
	float edge = smoothstep(0.1, 0.75, length(d * vec2(1.4, 1.0)));
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 acc = c;
	float r = amount * 0.012 * (0.4 + edge);
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472;
		acc += texture(screen, SCREEN_UV + vec2(cos(a), sin(a)) * r).rgb;
	}
	acc /= 7.0;
	vec3 o = mix(c, acc, clamp(amount * 1.4, 0.0, 1.0));
	o *= 1.0 - edge * amount * 0.5;
	COLOR = vec4(o, 1.0);
}"""

## A row of armour plates (full or empty), bottom-left above the points.
class PlateBar extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(190, 26)

	func _draw() -> void:
		var armor := ZombieMode.armor
		for i in ZombieMode.MAX_PLATES:
			var left := clampf((armor - i * ZombieMode.PLATE_HP) / ZombieMode.PLATE_HP, 0.0, 1.0)
			var r := Rect2(i * 62.0, 0, 54, 22)
			draw_rect(r, Color(0, 0, 0, 0.55))
			draw_rect(r, Color(0.8, 0.82, 0.86, 0.6), false, 2.0)
			if left > 0.0:
				draw_rect(Rect2(r.position + Vector2(3, 3), Vector2((r.size.x - 6.0) * left, r.size.y - 6.0)), Color(0.7, 0.78, 0.9, 0.95))

## The red arcs: one per source, drawn at the angle (to your view) the shot came from.
class Arcs extends Control:
	var hits: Array = []
	var last_angle := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func add(world_from: Vector3, armor: bool) -> void:
		hits.append({"from": world_from, "t": 0.0, "armor": armor})
		while hits.size() > 8:
			hits.pop_front()

	## Screen angle (radians, 0 = straight ahead, clockwise) of a point in the world against the camera.
	static func angle_to(cam: Camera3D, p: Vector3) -> float:
		var fwd := -cam.global_transform.basis.z
		var to := p - cam.global_position
		var f := Vector2(fwd.x, fwd.z).normalized()
		var t := Vector2(to.x, to.z).normalized()
		return f.angle_to(t)

	func _process(delta: float) -> void:
		for h in hits:
			h["t"] += delta
		hits = hits.filter(func(h): return h["t"] < ARC_LIFE)
		queue_redraw()

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var c := size * 0.5
		for h in hits:
			var a := angle_to(cam, h["from"])
			last_angle = a
			var k := 1.0 - float(h["t"]) / ARC_LIFE
			var col := Color(0.75, 0.82, 0.95, 0.85 * k) if h["armor"] else Color(0.85, 0.05, 0.05, 0.9 * k)
			# 0 is up on the screen, positive clockwise: Godot's arc angles run from +X, y down.
			var mid := a - PI * 0.5
			draw_arc(c, ARC_RADIUS, mid - 0.32, mid + 0.32, 16, col, 20.0, true)

## Where the last men are, when they have been hiding too long (npc/LastStand.gd): a ring and a chevron over the
## spot, or on the edge of the screen pointing the way if it is off to the side or behind you, and the distance.
class Ping extends Control:
	const LIFE := 4.5
	var marks: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func add(world_pos: Vector3) -> void:
		marks.append({"pos": world_pos, "t": 0.0})
		while marks.size() > 4:
			marks.pop_front()

	func _process(delta: float) -> void:
		for m in marks:
			m["t"] += delta
		marks = marks.filter(func(m): return m["t"] < LIFE)
		visible = not marks.is_empty()
		queue_redraw()

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var c := size * 0.5
		var font := get_theme_default_font()
		for m in marks:
			var t: float = m["t"]
			var k := minf(t / 0.25, 1.0) * clampf((LIFE - t) / 0.8, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(t * 7.0)
			var col := Color(0.95, 0.25, 0.15, k)
			var p: Vector3 = m["pos"]
			var meters := int(cam.global_position.distance_to(p))
			var on_screen := not cam.is_position_behind(p)
			var sp := cam.unproject_position(p) if on_screen else c
			var inset := Rect2(Vector2(60, 60), size - Vector2(120, 120))
			var halo := Color(0, 0, 0, 0.55 * k)
			var label := Color(1, 0.92, 0.85, k)
			if on_screen and inset.has_point(sp):
				draw_arc(sp, 20.0 + 6.0 * pulse, 0.0, TAU, 28, halo, 8.0, true)
				draw_arc(sp, 20.0 + 6.0 * pulse, 0.0, TAU, 28, col, 4.0, true)
				var tri := PackedVector2Array([sp + Vector2(0, -34), sp + Vector2(-11, -54), sp + Vector2(11, -54)])
				draw_colored_polygon(tri, col)
				draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), halo, 2.0)
				draw_string_outline(font, sp + Vector2(-30, 62), "%d m" % meters, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 24, 6, Color(0, 0, 0, 0.8 * k))
				draw_string(font, sp + Vector2(-30, 62), "%d m" % meters, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 24, label)
			else:
				# Off to the side or behind: on an ellipse well inside the screen (clear of the corners' numbers), pointing the way.
				var dir := (sp - c) if on_screen else Vector2(sin(Arcs.angle_to(cam, p)), -cos(Arcs.angle_to(cam, p)))
				if dir.length() < 1.0:
					dir = Vector2.UP
				dir = dir.normalized()
				var ra := c.x - 120.0
				var rb := c.y - 140.0
				var k_e := 1.0 / sqrt(pow(dir.x / ra, 2.0) + pow(dir.y / rb, 2.0))
				var edge := c + dir * k_e
				var side := Vector2(-dir.y, dir.x)
				var tri := PackedVector2Array([edge + dir * 20.0, edge - dir * 14.0 + side * 16.0, edge - dir * 14.0 - side * 16.0])
				draw_colored_polygon(tri, col)
				draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), halo, 3.0)
				var at := edge - dir * 36.0 + Vector2(-30, 8)
				draw_string_outline(font, at, "%d m" % meters, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 24, 6, Color(0, 0, 0, 0.8 * k))
				draw_string(font, at, "%d m" % meters, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 24, label)

var plates: Control
var arcs: Control
var ping: Control
var suppress: ColorRect
var feed: VBoxContainer
var callouts: Array = []
## How many callouts have been shown in all (the feed itself is capped and fades).
var callouts_shown := 0
var banner_line: Label
var flash_rect: ColorRect

func _ready() -> void:
	super._ready()
	plates = PlateBar.new()
	add_child(plates)
	plates.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	plates.offset_left = 32.0
	plates.offset_top = -184.0
	plates.offset_bottom = -158.0
	plates.offset_right = 222.0
	arcs = Arcs.new()
	add_child(arcs)
	ping = Ping.new()
	add_child(ping)
	ping.visible = false
	suppress = ColorRect.new()
	suppress.set_anchors_preset(Control.PRESET_FULL_RECT)
	suppress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = BLUR_SHADER
	suppress.material = sm
	add_child(suppress)
	move_child(suppress, 0)
	suppress.visible = false
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 0.95, 1)
	flash_rect.modulate.a = 0.0
	add_child(flash_rect)
	feed = VBoxContainer.new()
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed)
	feed.set_anchors_preset(Control.PRESET_TOP_LEFT)
	feed.position = Vector2(32, 150)
	feed.add_theme_constant_override("separation", 2)
	banner_line = Label.new()
	banner_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_line.add_theme_font_override("font", banner.get_theme_font("font"))
	banner_line.add_theme_font_size_override("font_size", 26)
	banner_line.add_theme_color_override("font_color", PAPER)
	banner_line.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	banner_line.add_theme_constant_override("shadow_offset_y", 3)
	add_child(banner_line)
	banner_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_line.offset_top = 150.0
	banner_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_line.modulate.a = 0.0
	ZombieMode.player_damaged.connect(_on_damaged)
	ZombieMode.armor_changed.connect(func(_a: float): plates.queue_redraw())

## A flashbang: the screen whites out and clears over `secs` (the sound is the caller's).
func flash(secs := 1.8) -> void:
	flash_rect.modulate.a = 0.92
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(flash_rect, "modulate:a", 0.0, secs)

## A man you have put down is within reach: the knife finishes him (and pays more).
func _update_prompt() -> void:
	super._update_prompt()
	if prompt.markup != "":
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	for g in get_tree().get_nodes_in_group("gangsters"):
		if is_instance_valid(g) and g.get("downed") == true and (g as Node3D).global_position.distance_to(player.global_position) < 2.6:
			prompt.markup = "{melee}  Finish him  [+%d]" % int(g.FINISH_BONUS)
			return

func _on_damaged(from: Vector3, _amount: float, armor_hit: bool) -> void:
	if from != Vector3.INF:
		arcs.add(from, armor_hit)

## The last men's position, shown for a few seconds.
func reveal(world_pos: Vector3) -> void:
	ping.add(world_pos)

## Number of arcs on screen (the tests read it).
func indicator_count() -> int:
	return arcs.hits.size()

func _process(delta: float) -> void:
	super._process(delta)
	var fx := get_tree().get_first_node_in_group("gang_fx")
	var s: float = fx.suppression if fx != null else 0.0
	suppress.visible = s > 0.02
	if suppress.visible:
		(suppress.material as ShaderMaterial).set_shader_parameter("amount", s)
	for c in callouts.duplicate():
		c["t"] += delta
		var l: Label = c["label"]
		if c["t"] > CALLOUT_LIFE:
			callouts.erase(c)
			l.queue_free()
		elif c["t"] > CALLOUT_LIFE - 0.8:
			l.modulate.a = (CALLOUT_LIFE - c["t"]) / 0.8

func _on_round_started(r: int) -> void:
	_refresh()
	banner.text = "WAVE %d" % r if not ZombieMode.is_boss_wave(r) else ("WAVE %d  THE ENFORCER" % r if r < 8 else "WAVE %d  TAC LEAD" % r)
	banner_line.text = wave_line(r)
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(banner_line, "modulate:a", 1.0, 0.6)
	tw.tween_interval(2.2)
	tw.tween_property(banner, "modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(banner_line, "modulate:a", 0.0, 1.0)

## What the street says as a wave starts.
static func wave_line(r: int) -> String:
	if r >= 8:
		return "Warrant team on the block. Don't get cuffed." if not ZombieMode.is_boss_wave(r) else "Their lead is in plates. Aim for the head."
	if ZombieMode.is_boss_wave(r):
		return "He brought his own armour. Aim for the head."
	var lines := ["THEY WANT YOUR CORNER.", "They're not done. Hold it.", "More of them. Keep your head down.",
		"They're coming with rifles now.", "Nobody's coming to help. Hold it."]
	return lines[mini(r - 1, lines.size() - 1)] if r <= lines.size() else "Still standing. Hold the corner."

## A line from the crew: shown in its colour, a few at once, gone in a moment.
func callout(who: String, text: String, _pos := Vector3.INF, crew := "Dock Boys") -> void:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = "%s: %s" % [who, text]
	l.add_theme_font_size_override("font_size", 19)
	var col := Color(0.86, 0.85, 0.35) if crew == "Dock Boys" else (Color(0.55, 0.72, 1.0) if crew == "Police" else Color(0.7, 0.5, 0.95))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_y", 2)
	feed.add_child(l)
	callouts.append({"label": l, "t": 0.0, "text": text})
	callouts_shown += 1
	while callouts.size() > CALLOUT_MAX:
		var old: Dictionary = callouts.pop_front()
		(old["label"] as Label).queue_free()

func last_callout() -> String:
	return String(callouts.back()["text"]) if not callouts.is_empty() else ""
