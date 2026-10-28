extends "res://world/Purchase.gd"
## The mystery box: 950 points for a random gun from the pool (every gun the
## wall doesn't sell, plus the LMG and the one wonder weapon), never one you
## already carry. The box spins through the guns, then holds one out for a
## few seconds: E takes it. After a few uses it moves to another spot on the
## block.
##
## try_open() / try_take() are what E does; advance() is the clock.

signal moved(spot: int)

const GunModel := preload("res://weapons/GunModel.gd")
const CRATE := "res://assets/polyhaven/wooden_crate_01/wooden_crate_01.gltf"
const PRICE := 950
const SPIN_TIME := 3.0
const OFFER_TIME := 10.0
const SWITCH_EVERY := 0.14
## Uses before it moves: a random number from here.
const MOVE_AFTER := Vector2i(4, 7)
const GLOW := Color(0.5, 0.75, 1.0)

enum State { IDLE, SPINNING, OFFER }

var state: State = State.IDLE
var offered: WD
var uses := 0
var move_after := 5
var spot := 0
## Transform3Ds the box can stand at.
var spots: Array = []
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _switch_t := 0.0
var _shown: Dictionary = {}
var _preview: Node3D
var _lid_light: OmniLight3D

func setup(places: Array) -> void:
	spots = places
	name = "MysteryBox"
	set_meta("kind", "MysteryBox")
	rng.randomize()
	move_after = rng.randi_range(MOVE_AFTER.x, MOVE_AFTER.y)
	_build()
	_put_at(0)

func _build() -> void:
	_make_zone(Vector3(2.0, 1.8, 2.0), Vector3(0, 0.9, 0.5))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.9, 0.8)
	cs.shape = box
	cs.position.y = 0.45
	body.add_child(cs)
	add_child(body)
	var ps := load(CRATE) as PackedScene
	if ps != null:
		var crate := ps.instantiate() as Node3D
		crate.name = "Crate"
		add_child(crate)
		var b := GunModel.bounds(crate, self)
		if b.size.x > 0.0:
			var k := 1.2 / maxf(b.size.x, 0.01)
			crate.scale = Vector3.ONE * k
			crate.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.5)
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A pale column of light out of the lid, so it can be found at night.
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.28
	cm.height = 6.0
	cm.radial_segments = 8
	beam.mesh = cm
	beam.material_override = mat
	beam.position.y = 3.9
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_lid_light = OmniLight3D.new()
	_lid_light.light_color = GLOW
	_lid_light.light_energy = 1.4
	_lid_light.omni_range = 5.0
	_lid_light.shadow_enabled = false
	_lid_light.position = Vector3(0, 1.3, 0.3)
	add_child(_lid_light)
	label = _make_label("MYSTERY BOX\n%d" % PRICE, Vector3(0, 1.75, 0), 0.0045, Color(0.75, 0.9, 1.0))
	_preview = Node3D.new()
	_preview.position = Vector3(0, 1.25, 0)
	add_child(_preview)

func _put_at(i: int) -> void:
	if spots.is_empty():
		return
	spot = i % spots.size()
	transform = spots[spot]

func pool() -> Array:
	var out: Array = []
	for id in ["smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder"]:
		var d := load("res://weapons/%s.tres" % id) as WD
		if d != null and d.in_box:
			out.append(d)
	return out

## What the box could give this holder: the pool without any family it holds.
func options_for(holder: Node) -> Array:
	var held: Array = holder.held_families() if holder != null else []
	return pool().filter(func(d: WD): return not held.has(d.family()))

func prompt_text() -> String:
	match state:
		State.IDLE:
			return "Open the mystery box  [%d]" % PRICE
		State.OFFER:
			return "Take the %s" % offered.display_name
	return ""

func interact(player: Node) -> void:
	if state == State.OFFER:
		try_take(holder_of(player))
	else:
		try_open(holder_of(player))

## Pays and starts the spin: "opened", "poor", "busy" or "none".
func try_open(holder: Node) -> String:
	if holder == null:
		return _result("none")
	if state != State.IDLE:
		return _result("busy")
	var options := options_for(holder)
	if options.is_empty():
		return _result("none", "The box has nothing to give you")
	if not _pay(PRICE):
		return _result("poor")
	offered = options[rng.randi() % options.size()]
	state = State.SPINNING
	_t = SPIN_TIME
	_switch_t = 0.0
	uses += 1
	return _result("opened")

## Takes the gun it holds out: "taken", or "none" if it isn't offering one. If
## you got that gun some other way while it was held out (a board, the
## machine), it holds out another instead ("changed"): taking a copy would top
## it up, or swap an upgraded one for a plain one.
func try_take(holder: Node) -> String:
	if state != State.OFFER or holder == null or offered == null:
		return _result("none")
	if holder.has_weapon(offered.family()):
		var options := options_for(holder)
		if options.is_empty():
			_close()
			return _result("none", "The box has nothing to give you")
		offered = options[rng.randi() % options.size()]
		_show(offered)
		_t = OFFER_TIME
		return _result("changed", "It holds out another gun")
	holder.give(offered)
	_close()
	return _result("taken")

func _close() -> void:
	state = State.IDLE
	offered = null
	_show(null)
	if uses >= move_after:
		_relocate()

## It goes: to another spot, with a new count to go.
func _relocate() -> void:
	if spots.size() > 1:
		var next := spot
		while next == spot:
			next = rng.randi() % spots.size()
		_put_at(next)
		moved.emit(next)
		say("The mystery box has moved")
	uses = 0
	move_after = rng.randi_range(MOVE_AFTER.x, MOVE_AFTER.y)

## The clock: the spin, then the held-out gun running out.
func advance(delta: float) -> void:
	match state:
		State.SPINNING:
			_t -= delta
			_switch_t -= delta
			if _switch_t <= 0.0:
				_switch_t = SWITCH_EVERY
				var all := pool()
				_show(all[rng.randi() % all.size()])
			if _t <= 0.0:
				state = State.OFFER
				_t = OFFER_TIME
				_show(offered)
		State.OFFER:
			_t -= delta
			if _t <= 0.0:
				_close()

func _process(delta: float) -> void:
	advance(delta)
	_lid_light.light_energy = 1.4 + (0.8 if state != State.IDLE else 0.0) + 0.25 * sin(Time.get_ticks_msec() * 0.005)
	if _preview.visible:
		_preview.rotation.y += delta * 1.6

## The gun floating over the lid (null: none).
func _show(d: WD) -> void:
	for id in _shown:
		(_shown[id] as Node3D).visible = false
	_preview.visible = d != null
	if d == null:
		return
	if not _shown.has(d.id):
		var m := GunModel.build(d)
		_preview.add_child(m)
		_shown[d.id] = m
	(_shown[d.id] as Node3D).visible = true
