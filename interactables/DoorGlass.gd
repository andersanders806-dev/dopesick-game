extends RefCounted
## The one glass material of every shop door (interactables/glass.gdshader): a street reflection that follows
## the time of day (assets/doors/glass_street_*.png, dev-tools/gen_door_glass.py) and a smudge film. Shared:
## one resource and one shader for all doors; the day/night mix is set on it from the clock.

const SHADER: Shader = preload("res://interactables/glass.gdshader")
const DAY: Texture2D = preload("res://assets/doors/glass_street_day.png")
const NIGHT: Texture2D = preload("res://assets/doors/glass_street_night.png")
const SMUDGE: Texture2D = preload("res://assets/doors/glass_smudge.png")

static var _mat: ShaderMaterial = null
static var _hooked := false

static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("street_day", DAY)
		_mat.set_shader_parameter("street_night", NIGHT)
		_mat.set_shader_parameter("smudge", SMUDGE)
		_refresh()
		var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
		if gs != null and not _hooked:
			_hooked = true
			gs.clock_changed.connect(func(_m): _refresh())
	return _mat

static func _refresh() -> void:
	var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
	if _mat != null and gs != null:
		_mat.set_shader_parameter("day_amount", clampf(float(gs.daylight()), 0.0, 1.0))
