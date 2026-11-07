extends Node3D
## The city beyond the block: a ring of building silhouettes with lit windows and the glow of the streets
## under them, on one inside-out cylinder (a single draw call, no light, no shadow). Without it the street
## ends in a flat colour a few blocks out, which from eye height is the edge of the world.
## The silhouettes are drawn once into a texture (no asset); the hour tints them from black glass at night
## to a pale haze by day, and the windows are only lit after dark.

const RADIUS := 125.0
const HEIGHT := 80.0
const TEX_W := 2048
const TEX_H := 256

var _mat: StandardMaterial3D
var _glow: StandardMaterial3D

func _ready() -> void:
	name = "Skyline"
	var imgs := _paint()
	_mat = _tube(RADIUS, imgs[0])
	_glow = _tube(RADIUS + 1.0, imgs[1])
	GameState.clock_changed.connect(_on_clock)
	_tint()

## One inside-out cylinder, unlit, with a painted texture.
func _tube(radius: float, tex: Texture2D) -> StandardMaterial3D:
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = HEIGHT
	tube.radial_segments = 48
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.disable_fog = true
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mi := MeshInstance3D.new()
	mi.mesh = tube
	mi.material_override = m
	mi.position.y = HEIGHT * 0.5 - 4.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return m

func _on_clock(_minute: int) -> void:
	_tint()

## Black glass at night, pale haze by day; the glow of the streets only after dark.
func _tint() -> void:
	var d := GameState.daylight()
	_mat.albedo_color = Color(1.0, 1.0, 1.0).lerp(Color(3.4, 3.9, 4.8), d)
	_glow.albedo_color = Color(1.0, 1.0, 1.0, 1.0 - d)

## [the buildings and their windows, the glow of the streets behind them].
func _paint() -> Array[ImageTexture]:
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var glow := Image.create(1, TEX_H, false, Image.FORMAT_RGBA8)
	# The glow of the streets, round the roofline: warm at the bottom, gone by a third of the way up.
	for y in TEX_H:
		var t := float(y) / float(TEX_H)
		var a := pow(clampf((t - 0.3) / 0.7, 0.0, 1.0), 1.3) * 0.8
		glow.set_pixel(0, y, Color(0.62, 0.34, 0.22, a))
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var x := 0
	while x < TEX_W:
		var w := rng.randi_range(36, 120)
		var h := rng.randi_range(40, 150) if rng.randf() > 0.2 else rng.randi_range(150, 215)
		var top := TEX_H - h
		var shade := rng.randf_range(0.025, 0.06)
		var body := Color(shade, shade * 1.05, shade * 1.5, 1.0)
		img.fill_rect(Rect2i(x, top, w, h), body)
		# A tank or an aerial on some roofs.
		if rng.randf() < 0.35:
			img.fill_rect(Rect2i(x + w / 3, top - rng.randi_range(6, 16), rng.randi_range(4, 10), 16), body)
		# Windows, a few of them lit.
		var wy := top + 8
		while wy < TEX_H - 6:
			var wx := x + 6
			while wx < x + w - 8:
				if rng.randf() < 0.22:
					var warm := rng.randf() < 0.7
					img.fill_rect(Rect2i(wx, wy, 4, 5), Color(1.0, 0.78, 0.45, 1.0) if warm else Color(0.6, 0.78, 1.0, 1.0))
				wx += 11
			wy += 13
		x += w + rng.randi_range(0, 10)
	img.generate_mipmaps()
	glow.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(glow)]
