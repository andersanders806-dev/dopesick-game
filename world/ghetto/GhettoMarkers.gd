extends Node3D
## Objective markers standing in the world (the story's own text markers and HUD stay as they are): a pulsing ring
## on the ground with a shaft of light over it and a small coloured light. The set drives them from the story's
## chapters and beats; `mark(id, pos, color)` / `clear(id)` work for anything else.

const SHADER := preload("res://assets/shaders/ghetto_marker.gdshader")
const MAX_MARKERS := 8

var _marks: Dictionary = {}     # id -> Node3D
var _t := 0.0

func mark(id: String, pos: Vector3, col := Color(1.0, 0.8, 0.3), radius := 1.2, shaft := true) -> Node3D:
	if _marks.has(id):
		clear(id)
	if _marks.size() >= MAX_MARKERS:
		return null
	var n := Node3D.new()
	n.name = "Marker_" + id
	add_child(n)
	n.global_position = pos
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	ring.mesh = q
	ring.rotation_degrees.x = -90.0
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rm := ShaderMaterial.new()
	rm.shader = SHADER
	rm.set_shader_parameter("tint", col)
	rm.set_shader_parameter("ring", 1.0)
	rm.set_shader_parameter("phase", float(_marks.size()))
	ring.material_override = rm
	n.add_child(ring)
	if shaft:
		var s := MeshInstance3D.new()
		s.name = "Shaft"
		var cm := CylinderMesh.new()
		cm.top_radius = radius * 0.3
		cm.bottom_radius = radius * 0.34
		cm.height = 7.0
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 16
		cm.rings = 1
		s.mesh = cm
		s.position.y = 3.5
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		sm.set_shader_parameter("tint", col)
		sm.set_shader_parameter("ring", 0.0)
		sm.set_shader_parameter("intensity", 0.55)
		s.material_override = sm
		n.add_child(s)
	var l := OmniLight3D.new()
	l.name = "Glow"
	l.light_color = col
	l.light_energy = 1.1
	l.omni_range = 4.5
	l.shadow_enabled = false
	l.position.y = 0.6
	n.add_child(l)
	_marks[id] = n
	return n

func clear(id: String) -> void:
	if _marks.has(id):
		var n: Node = _marks[id]
		_marks.erase(id)
		if is_instance_valid(n):
			n.queue_free()

func clear_all() -> void:
	for id in _marks.keys():
		clear(id)

func has(id: String) -> bool:
	return _marks.has(id)

func ids() -> Array:
	return _marks.keys()

func _process(delta: float) -> void:
	_t += delta
	for id in _marks:
		var n: Node3D = _marks[id]
		if is_instance_valid(n) and n.has_node("Glow"):
			(n.get_node("Glow") as OmniLight3D).light_energy = 1.1 * (0.7 + 0.3 * sin(_t * 3.2 + float(hash(id) % 7)))
