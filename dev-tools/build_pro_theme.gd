extends SceneTree
## Builds ui/theme/pro.tres from ui/UiStyle.gd's values: the project's default theme.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/build_pro_theme.gd
const U := preload("res://ui/UiStyle.gd")

func _box(bg: Color, edge := Color(0, 0, 0, 0), bw := 0, left := 0, margins := Vector4(14, 6, 14, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(bw)
	if left > 0:
		s.border_width_left = left
		s.border_color = edge
	s.set_corner_radius_all(2)
	s.content_margin_left = margins.x
	s.content_margin_top = margins.y
	s.content_margin_right = margins.z
	s.content_margin_bottom = margins.w
	s.anti_aliasing = true
	return s

func _square(c: Color, w := 12, h := 18) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([c, c])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = w
	t.height = h
	return t

func _initialize() -> void:
	var t := Theme.new()
	t.default_font = U.font(U.BODY)
	t.default_font_size = 16
	# Buttons: dark slab, amber bar on the left when hot.
	var edge := U.PANEL_EDGE
	t.set_stylebox("normal", "Button", _box(Color(0.1, 0.105, 0.115, 0.92), edge, 1))
	t.set_stylebox("hover", "Button", _box(Color(0.16, 0.15, 0.13, 0.96), Color(U.AMBER, 0.55), 1, 4))
	t.set_stylebox("pressed", "Button", _box(Color(U.AMBER, 0.28), U.AMBER, 1, 4))
	t.set_stylebox("disabled", "Button", _box(Color(0.08, 0.08, 0.09, 0.6), edge, 1))
	t.set_stylebox("focus", "Button", _box(Color(U.AMBER, 0.14), U.AMBER, 2, 4))
	t.set_color("font_color", "Button", Color(0.86, 0.84, 0.79))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", U.AMBER)
	t.set_color("font_hover_pressed_color", "Button", U.AMBER)
	t.set_color("font_disabled_color", "Button", U.DIM)
	t.set_font("font", "Button", U.font(U.BODY_SEMI))
	for cls in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", cls, _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4(6, 4, 6, 4)))
		t.set_stylebox("hover", cls, _box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 0, Vector4(6, 4, 6, 4)))
		t.set_stylebox("pressed", cls, _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4(6, 4, 6, 4)))
		t.set_stylebox("hover_pressed", cls, _box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 0, Vector4(6, 4, 6, 4)))
		t.set_stylebox("focus", cls, _box(Color(U.AMBER, 0.14), U.AMBER, 2, 4, Vector4(6, 4, 6, 4)))
		t.set_color("font_color", cls, Color(0.86, 0.84, 0.79))
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color(0.96, 0.94, 0.88))
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_font("font", cls, U.font(U.BODY_SEMI))
		t.set_constant("h_separation", cls, 12)
	# Sliders: a thin track, amber fill, square grabber.
	var track := _box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(U.AMBER, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0))
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	var fill_hot := fill.duplicate()
	fill_hot.bg_color = Color(1.0, 0.88, 0.5)
	for cls in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", cls, track)
		t.set_stylebox("grabber_area", cls, fill)
		t.set_stylebox("grabber_area_highlight", cls, fill_hot)
		t.set_icon("grabber", cls, _square(Color(0.93, 0.9, 0.82)))
		t.set_icon("grabber_highlight", cls, _square(Color(1.0, 0.88, 0.5), 14, 22))
		t.set_icon("grabber_disabled", cls, _square(U.DIM))
		t.set_constant("center_grabber", cls, 0)
	# Panels, labels, lists, scroll bars, separators.
	var panel := _box(U.PANEL, U.PANEL_EDGE, 1, 0, Vector4(0, 0, 0, 0))
	panel.border_width_top = 2
	panel.border_color = Color(1, 1, 1, 0.1)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_color("font_color", "Label", Color(0.9, 0.88, 0.82))
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_y", "Label", 1)
	var sb_track := _box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0))
	var sb_grab := _box(Color(1, 1, 1, 0.28), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0))
	var sb_grab_hot := _box(U.AMBER, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0))
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, sb_track)
		t.set_stylebox("scroll_focus", cls, sb_track)
		t.set_stylebox("grabber", cls, sb_grab)
		t.set_stylebox("grabber_highlight", cls, sb_grab_hot)
		t.set_stylebox("grabber_pressed", cls, sb_grab_hot)
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.12)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 10)
	# Drop-downs and pop-ups.
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.06, 0.062, 0.07, 0.98), edge, 1, 0, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hover", "PopupMenu", _box(Color(U.AMBER, 0.22), Color(0, 0, 0, 0), 0))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", U.font(U.BODY_SEMI))
	var pb_bg := _box(Color(0.1, 0.105, 0.115, 0.92), edge, 1)
	var pb_fill := _box(U.AMBER, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0))
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	var err := ResourceSaver.save(t, "res://ui/theme/pro.tres")
	print("pro.tres saved: ", err)
	quit()
