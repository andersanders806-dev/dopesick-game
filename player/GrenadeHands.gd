extends Node
## The hands of the lethal slot (SHIP 16G), first person only: the same arms and two-bone IK as the guns (player/Viewmodel.gd,
## here without a gun, as player/StoryHands.gd does it). The gun dips and its support hand lets go; the off (left) hand comes up
## from below with the Mk 2 (fx/Mk2.gd, real size), the pin and ring come out, the hand holds it (the cook), draws back and throws
## and the spoon flies off at the release; the right hand stays on the gun. Short and COD-like, never inside the lens (the arm
## shader cuts what is nearer than ARM_NEAR_CUT). Driven by player/Lethal.gd's state each frame; nothing is made while throwing.

const Viewmodel := preload("res://player/Viewmodel.gd")
const Mk2 := preload("res://fx/Mk2.gd")

# Camera space: x right, y up, -z ahead.
const AWAY_L := Vector3(-0.20, -0.46, -0.30)
const HELD_L := Vector3(-0.115, -0.165, -0.37)
const BACK_L := Vector3(-0.15, -0.075, -0.17)
const FWD_L := Vector3(-0.045, -0.125, -0.60)
const AWAY_R := Vector3(0.30, -0.95, -0.10)
const HAND_SCALE := 0.9
## The gun's dip: down, a touch to the right, nose down.
const DIP_POS := Vector3(0.03, -0.22, 0.04)
const DIP_ROT := Vector3(-16.0, 6.0, 4.0)
## The model in the hand, camera space: where the palm is from the wrist, and how it is turned (the pin side faces the lens).
const IN_HAND := Vector3(0.0, 0.04, -0.04)
const IN_HAND_ROT := Vector3(-28.0, -35.0, 14.0)

var lethal: Node
var holder: Node
var vm: Viewmodel
var _model: Node3D
var _pin: Node3D
var _spoon: Node3D
var _pin_home: Transform3D
var _spoon_home: Transform3D
var _pin_parent: Node
var _spoon_parent: Node
var _pin_t := -1.0
var _pin_v := Vector3.ZERO
var _spoon_t := -1.0
var _spoon_v := Vector3.ZERO
var _grip := 0.0
var _dip := 0.0
var _pos := AWAY_L
var _last_state := 0
var _built_on: Node
var dip_amount := 0.0

func setup(l: Node) -> void:
	lethal = l
	holder = l.get("holder")
	l.pin_pulled.connect(_on_pin)
	l.state_changed.connect(_on_state)
	if Graphics.has_signal("view_changed"):
		Graphics.view_changed.connect(func(_on: bool): _drop())

func _fp() -> bool:
	return Graphics.first_person

func _camera() -> Camera3D:
	var p := holder.get("player") as Node3D if holder != null else null
	return p.get("camera") as Camera3D if p != null else null

## The hands and the grenade built on the camera (once; again after a change of view).
func _ensure() -> bool:
	var cam := _camera()
	if cam == null or not _fp():
		return false
	if is_instance_valid(vm) and vm.get_parent() == cam:
		return true
	_drop()
	vm = Viewmodel.new().setup_hands_only() as Viewmodel
	vm.name = "GrenadeViewmodel"
	vm.position = Vector3.ZERO
	var lamp := OmniLight3D.new()
	lamp.name = "HandLamp"
	lamp.light_energy = 0.6
	lamp.omni_range = 1.4
	lamp.shadow_enabled = false
	lamp.light_color = Color(1.0, 0.93, 0.86)
	lamp.position = Vector3(-0.05, 0.2, 0.2)
	vm.add_child(lamp)
	vm.visible = false
	cam.add_child(vm)
	_model = Mk2.build()
	vm.add_child(_model)
	vm._convert(_model)
	_pin = Mk2.part(_model, "GrenadePin")
	_spoon = Mk2.part(_model, "GrenadeSwitch")
	if _pin != null:
		_pin_parent = _pin.get_parent()
		_pin_home = _pin.transform
	if _spoon != null:
		_spoon_parent = _spoon.get_parent()
		_spoon_home = _spoon.transform
	_model.visible = false
	return true

func _drop() -> void:
	if is_instance_valid(vm):
		vm.queue_free()
	vm = null
	_model = null
	_pin = null
	_spoon = null

## Built now (fx/Prewarm.gd draws it behind the loading black), and put away.
func warm() -> void:
	if _ensure():
		vm.visible = true
		_model.visible = true
		vm.grip_r = AWAY_R
		vm.aim_hands(HELD_L, {})
		_model.position = HELD_L + IN_HAND

func unwarm() -> void:
	if is_instance_valid(vm):
		vm.visible = false
		_model.visible = false

func reset() -> void:
	_pin_t = -1.0
	_spoon_t = -1.0
	_restore_parts()
	if is_instance_valid(vm):
		vm.visible = false
		_model.visible = false
	_dip = 0.0

func _restore_parts() -> void:
	if _pin != null and is_instance_valid(_pin) and _pin.get_parent() != _pin_parent:
		_pin.reparent(_pin_parent, false)
	if _pin != null:
		_pin.transform = _pin_home
		_pin.visible = true
	if _spoon != null and is_instance_valid(_spoon) and _spoon.get_parent() != _spoon_parent:
		_spoon.reparent(_spoon_parent, false)
	if _spoon != null:
		_spoon.transform = _spoon_home
		_spoon.visible = true

func _on_state(s: int) -> void:
	if s == lethal.S.DRAW:
		_restore_parts()
		_pin_t = -1.0
		_spoon_t = -1.0
	elif s == lethal.S.FOLLOW and _spoon != null and is_instance_valid(vm) and _model != null and _model.visible:
		# The spoon flies at the release.
		_spoon.reparent(vm, true)
		_spoon_t = 0.0
		_spoon_v = Vector3(0.25, 0.55, -1.4)

func _on_pin() -> void:
	if _pin != null and is_instance_valid(vm) and _model != null and _model.visible:
		_pin.reparent(vm, true)
		_pin_t = 0.0
		_pin_v = Vector3(0.55, 0.15, 0.25)

func advance(delta: float) -> void:
	var s: int = lethal.state
	var t: float = lethal.t
	if s == lethal.S.IDLE:
		if dip_amount > 0.0:
			dip_amount = 0.0
		if is_instance_valid(vm) and vm.visible and _spoon_t < 0.0:
			vm.visible = false
		return
	if not _ensure():
		return
	var S = lethal.S
	var target := AWAY_L
	var grip := 0.0
	var show_model := true
	var dip := 1.0
	match s:
		S.DRAW:
			var u := smoothstep(0.0, 1.0, t / lethal.DRAW_TIME)
			target = AWAY_L.lerp(HELD_L, u)
			grip = lerpf(0.2, 1.0, u)
			dip = smoothstep(0.0, 0.2, t)
		S.HELD:
			# Steady, with the weight of it: a slow breath and the fuse's own tremor late in the cook.
			var k: float = lethal.cook / lethal.FUSE
			var tremor := 0.0015 + 0.006 * k * k
			target = HELD_L + Vector3(sin(lethal.cook * 7.0), sin(lethal.cook * 9.3 + 1.0), 0.0) * tremor
			grip = 1.0
		S.WIND:
			var u2 := smoothstep(0.0, 1.0, t / lethal.WIND_TIME)
			target = HELD_L.lerp(BACK_L, u2)
			grip = 1.0
		S.FOLLOW:
			show_model = false
			if t < 0.10:
				target = BACK_L.lerp(FWD_L, smoothstep(0.0, 1.0, t / 0.10))
				grip = 1.0 - smoothstep(0.03, 0.09, t)
			else:
				target = FWD_L.lerp(AWAY_L, smoothstep(0.0, 1.0, (t - 0.10) / (lethal.FOLLOW_TIME - 0.10)))
			dip = 1.0 - smoothstep(0.12, lethal.FOLLOW_TIME, t)
	_pos = target
	_grip = grip
	dip_amount = dip
	vm.visible = true
	var rshape := Viewmodel.blend_shape("relaxed", "hold", 0.0)
	var lshape := Viewmodel.blend_shape("relaxed", "hold", grip)
	vm.set_hand("R", rshape, -80.0, HAND_SCALE)
	vm.set_hand("L", lshape, -80.0, HAND_SCALE)
	vm.grip_r = AWAY_R
	vm.aim_hands(_pos, {})
	_model.visible = show_model
	if show_model:
		_model.position = _pos + IN_HAND
		_model.rotation = Vector3(deg_to_rad(IN_HAND_ROT.x), deg_to_rad(IN_HAND_ROT.y), deg_to_rad(IN_HAND_ROT.z))
	# The pin and ring fly off to the right and fall; the spoon after the throw.
	if _pin_t >= 0.0 and _pin != null:
		_pin_t += delta
		_pin_v.y -= 4.0 * delta
		_pin.position += _pin_v * delta
		_pin.rotate_x(9.0 * delta)
		if _pin_t > 0.5:
			_pin.visible = false
			_pin_t = -1.0
	if _spoon_t >= 0.0 and _spoon != null:
		_spoon_t += delta
		_spoon_v.y -= 4.0 * delta
		_spoon.position += _spoon_v * delta
		_spoon.rotate_x(14.0 * delta)
		if _spoon_t > 0.3:
			_spoon.visible = false
			_spoon_t = -1.0
	_dip_gun(dip)

## The gun goes down and to the side; its support hand lets go (the left is busy).
func _dip_gun(k: float) -> void:
	var v := holder.get("viewmodel") as Node3D
	if v == null or not is_instance_valid(v) or k <= 0.0:
		return
	v.position += DIP_POS * k
	v.rotation += Vector3(deg_to_rad(DIP_ROT.x), deg_to_rad(DIP_ROT.y), deg_to_rad(DIP_ROT.z)) * k
	var feel = holder.get("feel")
	if feel != null and v.has_method("aim_hands"):
		var left: Vector3 = feel.get("_left_hand")
		v.aim_hands(left.lerp(Vector3(-0.2, -0.62, 0.1), k), feel.get("_hand_opt"))
