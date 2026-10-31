extends CanvasLayer
## Blood on the lens: a zombie's claw lands, or you cut one down point blank, and a few dark
## splats spread across the screen's edges and run dry over a few seconds. Pooled (6).

const SPLATS := ["res://assets/decals/blood_splatter_01.png", "res://assets/decals/blood_splatter_02.png", "res://assets/decals/blood_spray_01.png"]
const POOL := 6
const LIFE := 3.6

var _items: Array = []
var _next := 0
var _textures: Array[Texture2D] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	layer = 60
	name = "ScreenBlood"
	rng.randomize()
	for p in SPLATS:
		var t := load(p) as Texture2D
		if t != null:
			_textures.append(t)
	for i in POOL:
		var r := TextureRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.visible = false
		add_child(r)
		_items.append([r, 99.0, 1.0])

## `strength` 1 is a claw; a melee at point blank is about 0.6.
func splat(strength := 1.0) -> void:
	if _textures.is_empty():
		return
	var n := 1 + int(strength > 1.3)
	for k in n:
		var e: Array = _items[_next]
		_next = (_next + 1) % _items.size()
		var r: TextureRect = e[0]
		r.texture = _textures[rng.randi() % _textures.size()]
		var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
		var s := rng.randf_range(0.35, 0.6) * vp.y * (0.8 + 0.5 * clampf(strength, 0.0, 1.5))
		r.size = Vector2(s, s)
		# Near an edge, not in the middle of the view.
		var side := rng.randi() % 4
		var x := rng.randf_range(-0.1, 0.9) * vp.x
		var y := rng.randf_range(-0.1, 0.7) * vp.y
		match side:
			0: x = rng.randf_range(-0.15, 0.1) * vp.x
			1: x = rng.randf_range(0.65, 0.95) * vp.x
			2: y = rng.randf_range(-0.2, 0.0) * vp.y
			3: y = rng.randf_range(0.55, 0.8) * vp.y
		r.position = Vector2(x, y)
		r.pivot_offset = r.size * 0.5
		r.rotation = rng.randf() * TAU
		r.modulate = Color(0.8, 0.05, 0.05, 0.95)
		r.visible = true
		e[1] = 0.0

func _process(delta: float) -> void:
	for e in _items:
		var r: TextureRect = e[0]
		if not r.visible:
			continue
		e[1] += delta
		var u: float = e[1] / LIFE
		if u >= 1.0:
			r.visible = false
			continue
		# It runs down the glass as it dries.
		r.position.y += delta * 14.0 * u
		r.modulate.a = 0.95 * (1.0 - smoothstep(0.35, 1.0, u))

func shown() -> int:
	var n := 0
	for e in _items:
		if (e[0] as Control).visible:
			n += 1
	return n
