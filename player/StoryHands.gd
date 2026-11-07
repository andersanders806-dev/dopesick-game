extends Node
## Your own hands in the story's first person -- the same arms, skin shader and
## two-bone IK as the gun modes (player/Viewmodel.gd), here without a gun.
##
## Idle they hang low in the view and move the way FPFeel moves a gun: a figure-8
## bob per stride, a lag behind the look, a breath. On top of that, by what is going on:
##   reach()      the right hand goes for what E is about to use (a door, a person, a shelf)
##   carrying     the thing you lifted is in your right hand; a dock box takes both
##   Walkman      comes up to press play, then rides in the left hand while a tape runs
##   dose_taken   hands to the mouth for a pill; down and out of frame, a dip of the head, for the rest
##   withdrawal   tremor that grows with the sickness, skin going grey, sweat
## Each of them has a sound. Child of Player3D, which builds it only in first person.

const Viewmodel := preload("res://player/Viewmodel.gd")
const ItemModels := preload("res://items/ItemModels.gd")
const WALKMAN_MODEL := "res://assets/polyhaven/portable_cassette_player/portable_cassette_player.gltf"

# --- Where the hands are, in camera space (x right, y up, -z ahead) -------------------
const IDLE_R := Vector3(0.18, -0.215, -0.50)
const IDLE_L := Vector3(-0.18, -0.215, -0.50)
const REACH_R := Vector3(0.07, -0.12, -0.64)
const CARRY_R := Vector3(0.12, -0.19, -0.37)
const BOX_R := Vector3(0.17, -0.2, -0.52)
const BOX_L := Vector3(-0.17, -0.2, -0.52)
const WALKMAN_UP_L := Vector3(-0.07, -0.13, -0.33)
const WALKMAN_HELD_L := Vector3(-0.15, -0.20, -0.40)
const MOUTH_R := Vector3(0.02, -0.10, -0.30)
const AWAY_R := Vector3(0.02, -0.40, -0.30)
const AWAY_L := Vector3(-0.08, -0.41, -0.30)
const BOX_SIZE := Vector3(0.27, 0.15, 0.22)
const WALKMAN_LONG := 0.115

const IDLE_ROLL := -80.0
const HAND_SCALE := 0.9
const REACH_TIME := 0.6
const WALKMAN_RAISE_TIME := 1.5
const USE_TIME := 2.1

## What the hand takes, by drug: pills go to the mouth, the rest happens down out of the picture.
const PILLS := ["oxy", "tramadol", "clonazepam", "alprazolam", "methadone", "bupe", "codeine", "hydrocodone", "xanax", "valium", "benzo"]

var player: Node3D
var camera: Camera3D
var vm: Viewmodel

var _pos := {"R": IDLE_R, "L": IDLE_L}
var _roll := {"R": 0.0, "L": 0.0}
var _grip := {"R": 0.0, "L": 0.0}
var _open := {"R": 0.0, "L": 0.0}
var _t := 0.0
var _bob_phase := 0.0
var _bob_weight := 0.0
var _sway := Vector2.ZERO
var _look_prev := Vector2.ZERO
var _look_known := false
var _tremor_seed := Vector3(randf() * 10.0, randf() * 10.0, randf() * 10.0)
var _sprint := 0.0

# Actions: each a timeline in seconds, -1 when not running.
var _reach_t := -1.0
var _reach_to := REACH_R
var _use_t := -1.0
var _use_pills := true
var _wm_t := -1.0
var _wm_playing := false
var _carry := 0.0
var _box := 0.0
var _item_id := ""
var _item: Node3D
var _box_prop: Node3D
var _walkman: Node3D
var _pill: Node3D
var _arm_mats_ok := false
var _sounds := {}
## What the last frame drew (the smoke test reads these).
var shown_item := ""

func setup(p: Node3D, cam: Camera3D) -> void:
	player = p
	camera = cam
	name = "StoryHands"
	vm = Viewmodel.new().setup_hands_only() as Viewmodel
	vm.position = Vector3.ZERO
	# The dark rooms get a little light on the hands, as the guns do.
	var lamp := OmniLight3D.new()
	lamp.name = "HandLamp"
	lamp.light_energy = 0.45
	lamp.omni_range = 1.4
	lamp.shadow_enabled = false
	lamp.light_color = Color(1.0, 0.93, 0.86)
	lamp.position = Vector3(-0.05, 0.2, 0.2)
	vm.add_child(lamp)
	cam.add_child(vm)
	vm.set_arm_param("bare", 1.0)
	_build_props()
	GameState.dose_taken.connect(_on_dose)
	GameState.inventory_changed.connect(_on_inventory)
	Walkman.tape_changed.connect(_on_tape)
	_wm_playing = Walkman.is_playing()
	_on_inventory()
	_snap()

func _exit_tree() -> void:
	if is_instance_valid(vm):
		vm.queue_free()

## Hands in place at once (a fresh view, a new room).
func _snap() -> void:
	_pos = {"R": IDLE_R, "L": IDLE_L}

# --- Props -----------------------------------------------------------------------------

func _build_props() -> void:
	_box_prop = Node3D.new()
	_box_prop.name = "Box"
	var bm := BoxMesh.new()
	bm.size = BOX_SIZE
	var card := StandardMaterial3D.new()
	card.albedo_color = Color(0.40, 0.30, 0.19)
	card.roughness = 0.9
	bm.material = card
	var bmi := MeshInstance3D.new()
	bmi.mesh = bm
	_box_prop.add_child(bmi)
	# The packing tape across the lid.
	var tm := BoxMesh.new()
	tm.size = Vector3(0.05, 0.004, BOX_SIZE.z + 0.002)
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.62, 0.5, 0.33)
	tape.roughness = 0.4
	tm.material = tape
	var tmi := MeshInstance3D.new()
	tmi.mesh = tm
	tmi.position = Vector3(0, BOX_SIZE.y * 0.5 + 0.001, 0)
	_box_prop.add_child(tmi)
	_box_prop.visible = false
	vm.add_child(_box_prop)
	vm._convert(_box_prop)

	var scene := load(WALKMAN_MODEL) as PackedScene
	if scene != null:
		_walkman = Node3D.new()
		_walkman.name = "Walkman"
		var model := scene.instantiate() as Node3D
		_walkman.add_child(model)
		var box := AABB()
		var first := true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var b := m.transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if longest > 0.0001:
			model.scale = Vector3.ONE * (WALKMAN_LONG / longest)
			model.position = -box.get_center() * model.scale.x
		_walkman.visible = false
		vm.add_child(_walkman)
		vm._convert(_walkman)

	# A pill between finger and thumb.
	_pill = Node3D.new()
	_pill.name = "Pill"
	var cap := CapsuleMesh.new()
	cap.radius = 0.004
	cap.height = 0.014
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.88, 0.88, 0.85)
	white.roughness = 0.5
	cap.material = white
	var cmi := MeshInstance3D.new()
	cmi.mesh = cap
	cmi.rotation.z = PI * 0.5
	_pill.add_child(cmi)
	_pill.visible = false
	vm.add_child(_pill)
	vm._convert(_pill)

func _set_item(id: String) -> void:
	if id == _item_id and (_item != null or id == ""):
		return
	if is_instance_valid(_item):
		_item.queue_free()
		_item = null
	_item_id = id
	shown_item = ""
	if id == "" or not (ItemModels.RECIPES.has(id) or id.begins_with("tape:")):
		return
	_item = ItemModels.build(id)
	_item.visible = false
	vm.add_child(_item)
	vm._convert(_item)
	_tone_down(_item, 0.7)
	shown_item = id

## Props meet the same lights as the arms; pale ones would blow out.
func _tone_down(node: Node, k: float) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(i) as ShaderMaterial
			if mat != null:
				var c: Color = mat.get_shader_parameter("albedo")
				mat.set_shader_parameter("albedo", Color(c.r * k, c.g * k, c.b * k, c.a))

func _on_inventory() -> void:
	var inv: Array = GameState.inventory
	_set_item(String(inv.back()) if not inv.is_empty() else "")

# --- Actions ---------------------------------------------------------------------------

## The right hand goes out toward `world_pos` (what E is about to use).
func reach(world_pos: Vector3, quiet := false) -> void:
	if camera == null:
		return
	var local := camera.global_transform.affine_inverse() * world_pos
	var depth := clampf(-local.z, 0.4, 3.0)
	# Where it lies in the view, brought in to arm's length: off to a side, a little up or down.
	var lat := clampf(local.x / depth, -0.7, 0.7)
	var vert := clampf(local.y / depth, -0.5, 0.5)
	_reach_to = Vector3(clampf(lat * 0.32, -0.16, 0.2), clampf(-0.12 + vert * 0.18, -0.2, 0.02), -0.64)
	_reach_t = 0.0
	if not quiet:
		_play("cloth", -16.0, randf_range(1.25, 1.45))

func _on_tape(id: String) -> void:
	if id == "":
		return
	_wm_t = 0.0
	_play("cloth", -14.0, 1.2)

func _on_dose(drug_id: String, outcome: String) -> void:
	if outcome == "saved" or drug_id == "":
		return
	_use_pills = drug_id in PILLS or String(Drugs.info(drug_id).get("class", "")) in ["benzo", "treatment", "cannabis"]
	_use_t = 0.0
	_play("cloth", -12.0, 1.0)

# --- Frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(vm):
		return
	var holder := player.get_node_or_null("WeaponHolder")
	var show: bool = bool(player.get("_first_person")) and not (holder != null and is_instance_valid(holder.get("viewmodel")))
	vm.visible = show
	if not show:
		return
	advance(delta)
	apply()

var _dt := 0.0
var _last_sick := -1.0
var _use_marks := {}
var _wm_stopped_t := -1.0

func advance(delta: float) -> void:
	delta = minf(delta, 0.1)
	_dt = delta
	_t += delta
	# Where the look is going: the hands trail it.
	var look := Vector2(float(player.get("_look_yaw")), float(player.get("_look_pitch")))
	if not _look_known:
		_look_prev = look
		_look_known = true
	var dyaw := angle_difference(_look_prev.x, look.x)
	var dpitch := look.y - _look_prev.y
	_look_prev = look
	_sway += Vector2(-dyaw, -dpitch) * 0.8
	_sway = _sway.limit_length(deg_to_rad(5.0))
	_sway *= exp(-8.0 * delta)
	# Stride.
	var v: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var speed := Vector2(v.x, v.z).length()
	_bob_weight = move_toward(_bob_weight, clampf(speed / 1.8, 0.0, 1.3), delta * 5.0)
	var sprinting: bool = player.has_method("is_sprinting") and player.is_sprinting()
	_sprint = move_toward(_sprint, 1.0 if sprinting else 0.0, delta * 6.0)
	_bob_phase = fmod(_bob_phase + TAU * (2.6 if sprinting else 1.8) * delta * clampf(speed / 1.6, 0.4, 1.6), TAU * 4.0)
	# Timelines.
	if _reach_t >= 0.0:
		_reach_t += delta
		if _reach_t >= REACH_TIME:
			_reach_t = -1.0
	if _use_t >= 0.0:
		_use_t += delta
		if _use_t >= USE_TIME:
			_use_t = -1.0
			_set_dip(0.0)
	if _wm_t >= 0.0:
		_wm_t += delta
		if _wm_t >= WALKMAN_RAISE_TIME:
			_wm_t = -1.0
	var playing: bool = Walkman.is_playing()
	if _wm_playing and not playing:
		_wm_t = 0.0
		_wm_stopped_t = 0.0
		_play("cloth", -14.0, 1.1)
	_wm_playing = playing
	_carry = move_toward(_carry, 1.0 if (_item != null and not Jobs.carrying_box()) else 0.0, delta * 4.0)
	_box = move_toward(_box, 1.0 if Jobs.carrying_box() else 0.0, delta * 3.0)

func _set_dip(d: float) -> void:
	if player != null and "fp_dip" in player:
		player.fp_dip = d

## The pose for this moment, then the nodes. Split from advance() so a test can step the clock itself.
func apply() -> void:
	var sick := GameState.sickness()
	var sweat := clampf(sick * 1.3, 0.0, 1.0)
	var k := 1.0 - exp(-14.0 * _dt) if _dt > 0.0 else 1.0
	# --- targets
	var tr := IDLE_R
	var tl := IDLE_L
	var roll_r := IDLE_ROLL
	var roll_l := 180.0 - IDLE_ROLL
	var shape_r := "relaxed"
	var shape_l := "relaxed"
	var gr := 0.0
	var gl := 0.0
	var open_r := 0.0
	var open_l := 0.0
	# The sick hold their hands closer in, lower, and don't swing them.
	tr += Vector3(-0.015, -0.02, 0.0) * sick
	tl += Vector3(0.015, -0.02, 0.0) * sick
	# Walking: a figure-8, the hands swing a little against it.
	var amp := 0.012 * _bob_weight * (1.0 + 0.7 * _sprint)
	var bob := Vector3(sin(_bob_phase) * amp, sin(_bob_phase * 2.0) * amp * 0.8, 0.0)
	tr += bob + Vector3(0, 0, -sin(_bob_phase) * 0.006 * _bob_weight)
	tl += Vector3(-bob.x, bob.y, 0.0) + Vector3(0, 0, sin(_bob_phase) * 0.006 * _bob_weight)
	# Sprinting brings them up and in.
	tr += Vector3(-0.03, 0.04, 0.0) * _sprint
	tl += Vector3(0.03, 0.04, 0.0) * _sprint
	# A breath.
	var breath := sin(_t * 1.5) * 0.0035 * (1.0 + sick)
	tr.y += breath
	tl.y += breath * 0.8
	# The look drags them: they trail a turn and a tilt of the head.
	var drag := Vector3(_sway.x * 0.9, _sway.y * 0.8, 0.0)
	tr += drag
	tl += drag

	# --- carrying
	if _carry > 0.001:
		tr = tr.lerp(CARRY_R + bob + drag + Vector3(0, breath, 0), _carry)
		gr = maxf(gr, _carry)
		roll_r = lerpf(roll_r, -40.0, _carry)
	if _box > 0.001:
		tr = tr.lerp(BOX_R + bob * 1.4 + drag, _box)
		tl = tl.lerp(BOX_L + Vector3(-bob.x, bob.y, 0.0) * 1.4 + drag, _box)
		gr = maxf(gr, _box)
		gl = maxf(gl, _box)
		roll_r = lerpf(roll_r, -100.0, _box)
		roll_l = lerpf(roll_l, 280.0, _box)
	# --- Walkman: up to press play, then held low in the left hand while a tape runs
	var wm_vis := 0.0
	var wm_pos := WALKMAN_HELD_L
	if _wm_playing or _wm_t >= 0.0:
		wm_vis = 1.0
		var up := 0.0
		if _wm_t >= 0.0:
			up = sin(clampf(_wm_t / WALKMAN_RAISE_TIME, 0.0, 1.0) * PI)
			up = clampf(up * 1.6, 0.0, 1.0)
		wm_pos = WALKMAN_HELD_L.lerp(WALKMAN_UP_L, up)
		var press := 0.0
		if _wm_t >= 0.0:
			# The right thumb comes over and presses play at the top of the lift.
			var ph := _wm_t / WALKMAN_RAISE_TIME
			press = smoothstep(0.28, 0.42, ph) * (1.0 - smoothstep(0.52, 0.68, ph))
			tr = tr.lerp(wm_pos + Vector3(0.09, 0.0, 0.02), up * 0.85)
			roll_r = lerpf(roll_r, -25.0, up)
			shape_r = "relaxed"
			tr.z += 0.012 * press
		tl = tl.lerp(wm_pos + Vector3(0.0, -0.035, 0.0), 1.0)
		gl = maxf(gl, 1.0)
		roll_l = lerpf(roll_l, 220.0, 1.0)
	elif _wm_stopped_t >= 0.0:
		_wm_stopped_t = -1.0
	# --- reaching
	if _reach_t >= 0.0:
		var ph := _reach_t / REACH_TIME
		var w := sin(clampf(ph, 0.0, 1.0) * PI)
		w = clampf(w * 1.5, 0.0, 1.0)
		tr = tr.lerp(_reach_to, w)
		open_r = maxf(open_r, w * 0.9)
		roll_r = lerpf(roll_r, 18.0, w)
		gr = minf(gr, 1.0 - w)
	# --- using
	var pill_vis := false
	if _use_t >= 0.0:
		var ph := _use_t / USE_TIME
		if _use_pills:
			# Lift the pills to the mouth, tip them in, down again.
			var up := smoothstep(0.0, 0.3, ph) * (1.0 - smoothstep(0.66, 0.94, ph))
			tr = tr.lerp(MOUTH_R, up)
			tl = tl.lerp(Vector3(-0.07, -0.20, -0.30), up * 0.5)
			shape_r = "pinch"
			gr = maxf(gr, up)
			roll_r = lerpf(roll_r, -35.0, up)
			pill_vis = ph < 0.5
			if not _use_marks.get("a", false) and ph > 0.3:
				_use_marks["a"] = true
				_play("rattle", -9.0, randf_range(0.95, 1.1))
			if not _use_marks.get("b", false) and ph > 0.52:
				_use_marks["b"] = true
				_play("swallow", -10.0, 1.0)
		else:
			# Hands drop out of the bottom of the picture, the head bows after them.
			var down := smoothstep(0.0, 0.28, ph) * (1.0 - smoothstep(0.7, 0.96, ph))
			tr = tr.lerp(AWAY_R, down)
			tl = tl.lerp(AWAY_L, down)
			gr = maxf(gr, down)
			gl = maxf(gl, down)
			_set_dip(down * 0.34)
			if not _use_marks.get("a", false) and ph > 0.3:
				_use_marks["a"] = true
				_play("snap", -10.0, 1.0)
			if not _use_marks.get("b", false) and ph > 0.62:
				_use_marks["b"] = true
				_play("cloth", -12.0, 0.9)
	else:
		_use_marks.clear()
	# --- the sickness: a tremor, and the hands never settle
	if sick > 0.02:
		var amp_t := 0.0015 + 0.011 * sick * sick + 0.004 * sick
		var n := Vector3(
			sin(_t * 6.3 + _tremor_seed.x) + 0.6 * sin(_t * 11.7 + _tremor_seed.y),
			sin(_t * 7.1 + _tremor_seed.y) + 0.6 * sin(_t * 13.3 + _tremor_seed.z),
			0.5 * sin(_t * 5.3 + _tremor_seed.z))
		tr += n * amp_t
		tl += Vector3(n.y, n.z * 2.0, n.x) * amp_t * 0.9
		# A flinch now and then: the whole hand jerks.
		var jerk := pow(maxf(0.0, sin(_t * 0.9 + _tremor_seed.x * 3.0)), 24.0) * sick
		tr += Vector3(0.012, 0.01, 0.0) * jerk
		tl += Vector3(-0.01, 0.012, 0.0) * jerk
		roll_r += sin(_t * 8.9 + _tremor_seed.x) * 4.0 * sick
		roll_l += sin(_t * 9.7 + _tremor_seed.y) * 4.0 * sick
	# --- smooth, then write
	_pos["R"] = (_pos["R"] as Vector3).lerp(tr, k)
	_pos["L"] = (_pos["L"] as Vector3).lerp(tl, k)
	_roll["R"] = lerpf(_roll["R"], roll_r, k)
	_roll["L"] = lerpf(_roll["L"], roll_l, k)
	_grip["R"] = lerpf(_grip["R"], gr, k)
	_grip["L"] = lerpf(_grip["L"], gl, k)
	_open["R"] = lerpf(_open["R"], open_r, k)
	_open["L"] = lerpf(_open["L"], open_l, k)
	var rshape := Viewmodel.blend_shape("relaxed", shape_r if shape_r != "relaxed" else "hold", _grip["R"])
	var lshape := Viewmodel.blend_shape("relaxed", shape_l if shape_l != "relaxed" else "hold", _grip["L"])
	vm.set_hand("R", rshape, _roll["R"], HAND_SCALE)
	vm.set_hand("L", lshape, _roll["L"], HAND_SCALE)
	vm.grip_r = _pos["R"]
	vm.aim_hands(_pos["L"], {"open_r": _open["R"], "open_l": _open["L"]})
	if absf(sick - _last_sick) > 0.004:
		_last_sick = sick
		vm.set_arm_param("sick", sick)
		vm.set_arm_param("sweat", sweat)
	# --- props ride the hands
	if is_instance_valid(_item):
		var showing: bool = _carry > 0.05 and _box < 0.5 and _use_t < 0.0 and _reach_t < 0.0 or (_carry > 0.6 and _reach_t >= 0.0 and _reach_t > REACH_TIME * 0.6)
		_item.visible = showing
		if showing:
			_item.position = _pos["R"] + Vector3(-0.01, 0.02, -0.03)
			_item.scale = Vector3.ONE * 0.8
			_item.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(-30.0), 0.0)
	_box_prop.visible = _box > 0.1
	if _box_prop.visible:
		_box_prop.position = ((_pos["R"] as Vector3) + (_pos["L"] as Vector3)) * 0.5 + Vector3(0, -0.01, -0.09)
		_box_prop.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	if _walkman != null:
		_walkman.visible = wm_vis > 0.5
		if _walkman.visible:
			_walkman.position = (_pos["L"] as Vector3) + Vector3(0.0, 0.03, -0.02)
			_walkman.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(8.0), deg_to_rad(-6.0))
	if _pill != null:
		_pill.visible = pill_vis
		if pill_vis:
			_pill.position = (_pos["R"] as Vector3) + Vector3(0.0, 0.02, -0.03)

# --- Sounds -----------------------------------------------------------------------------

func _play(kind: String, volume_db: float, pitch: float) -> void:
	match kind:
		"cloth":
			SFX.play("steal", volume_db, pitch)
		_:
			SFX._play_stream(_synth(kind), volume_db, pitch)

## Small foley made in code, so it needs no files: pills shaken in a hand, a swallow, an elastic snap.
func _synth(kind: String) -> AudioStreamWAV:
	if _sounds.has(kind):
		return _sounds[kind]
	var rate := 22050
	var secs := 0.45
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lp := 0.0
	var ticks: Array = []
	if kind == "rattle":
		for i in 9:
			ticks.append([rng.randf_range(0.0, 0.34), rng.randf_range(0.4, 1.0)])
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		match kind:
			"rattle":
				for tk in ticks:
					var dt: float = t - tk[0]
					if dt >= 0.0 and dt < 0.02:
						s += rng.randf_range(-1.0, 1.0) * exp(-dt * 260.0) * tk[1]
			"swallow":
				# A throat: a low soft glide, filtered noise swelling and sinking.
				var env := sin(clampf(t / 0.3, 0.0, 1.0) * PI)
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.06
				s = lp * env * 2.4 + sin(TAU * (90.0 - 30.0 * t / 0.3) * t) * env * 0.25
			"snap":
				# A rubber band let go: a short crack, then a thrum.
				s = rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.8 + sin(TAU * 140.0 * t) * exp(-t * 18.0) * 0.4
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 24000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	_sounds[kind] = w
	return w
