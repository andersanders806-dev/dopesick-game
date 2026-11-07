extends RefCounted
## The game's one visual language for menus and HUD: colours, fonts, the safe-area grid and a few
## helpers (blurred backdrop, film grain, hover/focus animation, number tick). The Theme itself is
## ui/theme/pro.tres (built by dev-tools/build_pro_theme.gd from these same values) and is the project's
## default theme, so every Button, slider, panel and check box already wears it.
## Fonts: Bungee (display), Barlow and Barlow Condensed (UI text), all SIL OFL; see assets/fonts.

const AMBER := Color(1.0, 0.8, 0.3)
const PINK := Color(0.93, 0.35, 0.55)
const BLOOD := Color(0.72, 0.08, 0.08)
const PAPER := Color(0.93, 0.9, 0.82)
const MUTED := Color(0.62, 0.6, 0.56)
const DIM := Color(0.46, 0.45, 0.42)
const PANEL := Color(0.055, 0.058, 0.066, 0.94)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.09)
const SHADOW := Color(0, 0, 0, 0.85)

## Type scale: every menu and HUD size comes from here.
const FS_TITLE := 84
const FS_H1 := 34
const FS_H2 := 22
const FS_BODY := 18
const FS_SMALL := 14
const FS_TINY := 12

## Safe area: the HUD sits this far in from the window edge (about 5 percent of 720p, a COD title-safe).
const SAFE_X := 44.0
const SAFE_Y := 36.0

const BUNGEE := "res://assets/fonts/Bungee-Regular.ttf"
const BODY := "res://assets/fonts/Barlow-Medium.ttf"
const BODY_SEMI := "res://assets/fonts/Barlow-SemiBold.ttf"
const COND := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"
const COND_BOLD := "res://assets/fonts/BarlowCondensed-Bold.ttf"
const THEME := "res://ui/theme/pro.tres"

static var _fonts := {}

## A cached font; `tracking` adds letter spacing (a FontVariation then).
static func font(path: String, tracking := 0) -> Font:
	var key := "%s|%d" % [path, tracking]
	if not _fonts.has(key):
		var f: Font = load(path)
		if tracking != 0:
			var v := FontVariation.new()
			v.base_font = f
			v.spacing_glyph = tracking
			f = v
		_fonts[key] = f
	return _fonts[key]

## Font, size, colour and the soft drop shadow that keeps text readable over a bright scene.
static func style_label(l: Label, path: String, size: int, color: Color, tracking := 0, shadow := true) -> Label:
	l.add_theme_font_override("font", font(path, tracking))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", SHADOW)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", 6)
	return l

## A section header for a menu column: spaced capitals in amber with a hairline under them.
static func section(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.text = text.to_upper()
	style_label(l, COND_BOLD, FS_SMALL + 2, AMBER, 3, false)
	box.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(AMBER, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 2)
	box.add_child(pad)
	return box

## A screen title: Bungee, spaced, with a short accent rule beneath.
static func title(text: String, size := FS_H2, color := PAPER) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = text.to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_label(l, BUNGEE, size, color, 4)
	box.add_child(l)
	var rule := ColorRect.new()
	rule.color = AMBER
	rule.custom_minimum_size = Vector2(56, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)
	return box

const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float lod = 3.0;
uniform vec4 tint : source_color = vec4(0.02, 0.02, 0.03, 1.0);
uniform float dark = 0.55;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, lod).rgb;
	float v = smoothstep(0.35, 1.05, distance(UV, vec2(0.5)));
	c = mix(c, tint.rgb, dark + v * 0.3);
	COLOR = vec4(c, 1.0);
}"""

## The live frame behind a menu, blurred, darkened and vignetted (not a flat black sheet).
static func blur_backdrop(dark := 0.55, lod := 3.0) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = BLUR_SHADER
	m.set_shader_parameter("dark", dark)
	m.set_shader_parameter("lod", lod)
	r.material = m
	return r

const GRAIN_SHADER := """shader_type canvas_item;
uniform float grain = 0.05;
uniform float vignette = 0.55;
float h(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	float n = h(floor(FRAGCOORD.xy * 0.5) + floor(TIME * 24.0) * 17.0) - 0.5;
	float v = smoothstep(0.45, 1.1, distance(UV, vec2(0.5)) * 1.25);
	COLOR = vec4(vec3(n > 0.0 ? 1.0 : 0.0), abs(n) * grain * 2.0) ;
	COLOR.a = max(COLOR.a, v * vignette);
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), v);
}"""

## Film grain with a vignette, over a whole screen; never takes the mouse.
static func grain_overlay(grain := 0.05, vignette := 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = GRAIN_SHADER
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("vignette", vignette)
	r.material = m
	return r

## A panel eases in (fade and a short rise) when a menu opens. Safe under a paused tree if `owner`
## is a node that keeps running.
static func ease_in(c: Control, owner: Node, rise := 14.0, time := 0.22) -> void:
	c.modulate.a = 0.0
	var tw := owner.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, time)
	var y := c.position.y
	c.position.y = y + rise
	tw.tween_property(c, "position:y", y, time)

## The number on `l` counts up to `to` instead of jumping. `shown` is remembered in the label's meta.
static func tick_number(l: Label, to: int, time := 0.35) -> void:
	var from := int(l.get_meta("tick_to", to))
	l.set_meta("tick_to", to)
	if l.has_meta("tick_tw"):
		var old = l.get_meta("tick_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	if from == to or not l.is_inside_tree():
		l.text = str(to)
		return
	var tw := l.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	l.set_meta("tick_tw", tw)
	tw.tween_method(func(v: float): l.text = str(roundi(v)), float(from), float(to), time)
	tw.tween_callback(func(): l.text = str(to))

static var _armed_at := 0

## A soft tick as the menu focus moves (not for the first, programmatic grab).
static func tick() -> void:
	if Time.get_ticks_msec() - _armed_at < 250:
		return
	var sfx = Engine.get_main_loop().root.get_node_or_null("SFX") if Engine.get_main_loop() is SceneTree else null
	if sfx != null:
		sfx.play("blip", -17.0, 1.35)

## Hover = focus: the mouse moves the focus (so pad and mouse show the same one highlight) and every
## focus move ticks. Wired once per control by PadFocus.dress().
static func wire(c: Control) -> void:
	if c.has_meta("ui_wired"):
		return
	c.set_meta("ui_wired", true)
	if _armed_at == 0:
		_armed_at = Time.get_ticks_msec()
	c.focus_entered.connect(tick)
	if c is BaseButton and not (c is OptionButton):
		c.mouse_entered.connect(func():
			if not (c as BaseButton).disabled and c.is_visible_in_tree() and c.focus_mode == Control.FOCUS_ALL:
				c.grab_focus())

## Title-style menu item: no box, big spaced capitals; focus slides the text right, lights an amber
## bar on the left and draws an underline. Animates; the pad and the mouse reach the same state.
static func menu_item(b: Button) -> void:
	b.flat = true
	b.add_theme_font_override("font", font(COND_BOLD, 3))
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_hover_pressed_color", AMBER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.custom_minimum_size = Vector2(300, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var bar := ColorRect.new()
	bar.color = AMBER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = Vector2(4, 0)
	b.add_child(bar)
	var line := ColorRect.new()
	line.color = Color(AMBER, 0.55)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size = Vector2(0, 2)
	b.add_child(line)
	var lay := func():
		bar.position = Vector2(0, 8)
		line.position = Vector2(16, b.size.y - 3.0)
	b.resized.connect(lay)
	lay.call()
	var go := func(on: bool):
		var tw := b.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sb, "content_margin_left", 30.0 if on else 16.0, 0.16)
		tw.tween_property(bar, "size:y", maxf(b.size.y - 16.0, 8.0) if on else 0.0, 0.16)
		tw.tween_property(line, "size:x", (b.size.x - 36.0) * 0.7 if on else 0.0, 0.26)
	b.focus_entered.connect(go.bind(true))
	b.focus_exited.connect(go.bind(false))
