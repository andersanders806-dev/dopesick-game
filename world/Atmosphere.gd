extends Node3D
## The weather and the hours on the street, beyond the rain and the light:
##
## - Morning fog: thick from first light, burned off by mid-morning.
## - Puddles: they gather while it rains and dry out slowly after, one by
##   one -- dark, glossy, catching the lamps and the neon.
## - The block at night (21:00-04:00): a siren somewhere a few streets
##   over, and a couple fighting on the corner, loud enough to read.
##
## Added by City3D.gd after it connects its own clock, so the fog here lands
## on top of the daylight it just set.

const FOG_MORNING := 0.035
const FOG_GREY := Color(0.55, 0.58, 0.62)
## Hours: fog builds from 4:30, thickest 6:30-7:30, gone by 10.
const FOG_HOURS := Vector4(4.5, 6.5, 7.5, 10.0)
## Minutes of rain to soak, and of dry to dry out.
const SOAK_MINUTES := 45.0
const DRY_MINUTES := 150.0
const PUDDLES := [
	Vector3(-19.0, 0, -2.6), Vector3(-12.5, 0, -1.9), Vector3(-6.0, 0, -3.1), Vector3(1.5, 0, -2.2),
	Vector3(8.5, 0, -2.8), Vector3(15.5, 0, -2.0), Vector3(23.0, 0, -2.9), Vector3(-15.0, 0, 1.2),
	Vector3(-2.5, 0, 0.8), Vector3(11.0, 0, 1.5), Vector3(20.0, 0, 0.6),
]
const NIGHT_HOURS := [21, 4]
const SIREN_GAP := Vector2(50.0, 130.0)
const ARGUMENT_SPOT := Vector3(17.6, 0, -3.75)
const ARGUMENT_LINES := [
	["You said Friday!", "I said I'd TRY."],
	["Don't touch me.", "Then give me my phone back!"],
	["Where's the money, Dee?", "Where's YOURS?"],
	["You're high right now.", "So what if I am?"],
	["I'm done. I'm DONE.", "You always say that."],
]

var _env: Environment
var _wet := 0.0
var _last_minute := -1
var _puddles: Array = []
var _argument: Node3D
var _line := 0
var _line_timer := 0.0
var _siren_timer := 60.0

func _ready() -> void:
	_env = get_parent().get("_env")
	for i in PUDDLES.size():
		_puddles.append(_make_puddle(PUDDLES[i], i))
	GameState.clock_changed.connect(_on_clock)
	_wet = 1.0 if GameState.raining else 0.0
	_on_clock(int(GameState.clock))

func night() -> bool:
	return GameState.hours_contain(NIGHT_HOURS, GameState.hour())

func _on_clock(minute: int) -> void:
	if _last_minute >= 0:
		advance_wet(float(posmod(minute - _last_minute, 1440)))
	_last_minute = minute
	_apply_fog()
	if night() and _argument == null:
		_start_argument()
	elif not night() and _argument != null:
		_argument.queue_free()
		_argument = null

# --- Fog ---------------------------------------------------------------------

func _apply_fog() -> void:
	if _env == null:
		return
	var h := GameState.clock / 60.0
	var k := 0.0
	if h >= FOG_HOURS.x and h < FOG_HOURS.y:
		k = smoothstep(FOG_HOURS.x, FOG_HOURS.y, h)
	elif h >= FOG_HOURS.y and h < FOG_HOURS.z:
		k = 1.0
	elif h >= FOG_HOURS.z and h < FOG_HOURS.w:
		k = 1.0 - smoothstep(FOG_HOURS.z, FOG_HOURS.w, h)
	if k <= 0.0:
		return
	_env.fog_enabled = true
	_env.fog_density += FOG_MORNING * k
	_env.fog_light_color = _env.fog_light_color.lerp(FOG_GREY, 0.6 * k)

# --- Puddles -------------------------------------------------------------------

func advance_wet(minutes: float) -> void:
	if GameState.raining:
		_wet = minf(1.0, _wet + minutes / SOAK_MINUTES)
	else:
		_wet = maxf(0.0, _wet - minutes / DRY_MINUTES)
	for i in _puddles.size():
		var p: MeshInstance3D = _puddles[i]
		# The deepest dips fill first and dry last.
		var need := float(i) / _puddles.size() * 0.8
		var a := clampf((_wet - need) * 4.0, 0.0, 1.0)
		p.visible = a > 0.02
		(p.material_override as StandardMaterial3D).albedo_color.a = 0.75 * a

func puddles_shown() -> int:
	return _puddles.filter(func(p): return p.visible).size()

static var _blob: Texture2D

static func _blob_texture() -> Texture2D:
	if _blob:
		return _blob
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.035
	for y in 128:
		for x in 128:
			var d := Vector2(x - 63.5, y - 63.5).length() / 63.5
			var edge := 0.72 + noise.get_noise_2d(x, y) * 0.35
			var a := clampf((edge - d) / 0.22, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_blob = ImageTexture.create_from_image(img)
	return _blob

func _make_puddle(at: Vector3, i: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Puddle%d" % i
	var m := PlaneMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 7919
	m.size = Vector2(rng.randf_range(0.9, 1.8), rng.randf_range(0.6, 1.1))
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.06, 0.07, 0.085, 0.0)
	# A soft, uneven blob, not a sheet of glass: the alpha comes from a
	# radial gradient broken up by noise.
	mat.albedo_texture = _blob_texture()
	mat.roughness = 0.04
	mat.metallic = 0.15
	mat.metallic_specular = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = at + Vector3(0, 0.015, 0)
	mi.rotation.y = rng.randf_range(-0.4, 0.4)
	mi.visible = false
	return mi

# --- The block at night ----------------------------------------------------------

func _process(delta: float) -> void:
	if not night():
		return
	if _argument:
		_line_timer -= delta
		if _line_timer <= 0.0:
			_line_timer = 2.6
			_next_line()
	_siren_timer -= delta
	if _siren_timer <= 0.0 and not GameState.wanted:
		_siren_timer = randf_range(SIREN_GAP.x, SIREN_GAP.y)
		distant_siren()

## One siren, passing a few streets over: far off down the block, low,
## fading. Returns the player (the smoke test checks it).
func distant_siren() -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	s.stream = SFX.SIREN_STREAM
	s.bus = "Ambience"
	s.unit_size = 30.0
	s.volume_db = -14.0
	add_child(s)
	s.position = Vector3(60.0 * (1.0 if randf() < 0.5 else -1.0), 4.0, -12.0)
	s.play()
	var t := create_tween()
	t.tween_property(s, "position:x", -s.position.x, 9.0)
	t.parallel().tween_property(s, "volume_db", -40.0, 9.0).set_delay(5.0)
	t.tween_callback(s.queue_free)
	return s

func _start_argument() -> void:
	_argument = Node3D.new()
	_argument.name = "Argument"
	add_child(_argument)
	_argument.position = ARGUMENT_SPOT
	var Cast := preload("res://npc/CharacterCast.gd")
	var Animator := preload("res://npc/CharacterAnimator.gd")
	for side in 2:
		var holder := Node3D.new()
		holder.scale = Vector3.ONE * 1.5
		holder.position = Vector3(-0.55 + side * 1.1, 0, 0)
		holder.rotation_degrees.y = 90.0 if side == 0 else -90.0
		_argument.add_child(holder)
		var entry: Dictionary = Cast.PASSERSBY[[1, 4][side] % Cast.PASSERSBY.size()]
		var model: Node = Cast.scene_for(entry["model"]).instantiate()
		holder.add_child(model)
		preload("res://npc/CharacterLook.gd").apply(model, entry["look"])
		var anim = Animator.new(model)
		anim.play("idle", 1.35)
		var bubble := Label3D.new()
		bubble.name = "Shout%d" % side
		bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bubble.font_size = 40
		bubble.pixel_size = 0.006
		bubble.outline_size = 10
		bubble.modulate = Color(1.0, 0.92, 0.85)
		bubble.no_depth_test = true
		_argument.add_child(bubble)
		bubble.position = holder.position + Vector3(0, 2.2, 0.3)
	_line = randi() % ARGUMENT_LINES.size()
	_line_timer = 0.0
	_next_line()

func _next_line() -> void:
	var pair: Array = ARGUMENT_LINES[(_line / 2) % ARGUMENT_LINES.size()]
	var who := _line % 2
	for side in 2:
		var b := _argument.get_node("Shout%d" % side) as Label3D
		b.text = pair[side] if side == who else ""
		b.visible = side == who
	_line += 1
