extends Node3D
## Things that move on the block so it doesn't look like a photograph:
##
## - Traffic: cars (Kenney Car Kit, CC0) running the one-way lane between the
##   curb and the parked cars, more by day. Headlights and tail-lights at
##   night. They stop for you and lean on the horn.
## - Steam coming up out of the manholes.
## - Rain (GameState.raining): streaks around the camera, a rain loop, the
##   road and sidewalk going wet and shiny, and a darker, greyer sky.
## - Neon that isn't quite right: a couple of the shop signs flicker.
##
## Added by City3D.gd (and Backyard3D.gd for the rain). Everything here is
## cheap enough for the Low preset: no shadows, small particle counts.

const CARS := ["sedan", "taxi", "van", "suv", "hatchback-sports", "delivery", "police", "garbage-truck"]
const CAR_SCALE := 1.6
const LANE_Z := 0.35
const LANE_SPEED := Vector2(7.0, 10.0)
const STREET_END := 31.0
const CAR_GAP_DAY := Vector2(4.0, 10.0)
const CAR_GAP_NIGHT := Vector2(12.0, 26.0)
## Stop this far short of a person (or the car in front) in the lane.
const STOP_DISTANCE := 4.2

@export var traffic: bool = true
@export var steam_points: Array[Vector3] = []

var _cars: Array = []
var _car_timer: float = 2.0
var _rain: GPUParticles3D
var _rain_sound: AudioStreamPlayer
var _wet_materials: Array = []
var _flicker: Array = []

func _ready() -> void:
	for p in steam_points:
		_add_steam(p)
	_build_rain()
	_pick_flickering_signs()
	GameState.weather_changed.connect(_on_weather_changed)
	_on_weather_changed(GameState.raining)
	# A car already on its way through when you step outside.
	if traffic:
		_spawn_car(randf_range(-20.0, 10.0))

## Cars move on the physics tick like everything else that moves, so
## physics interpolation smooths them between ticks.
func _physics_process(delta: float) -> void:
	if traffic:
		_update_traffic(delta)

func _process(delta: float) -> void:
	_update_flicker(delta)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and _rain:
		_rain.global_position = player.global_position + Vector3(0, 9.0, 2.0)

# --- Traffic ---------------------------------------------------------------

func _update_traffic(delta: float) -> void:
	_car_timer -= delta
	if _car_timer <= 0.0:
		var gap := CAR_GAP_DAY if GameState.daylight() > 0.5 else CAR_GAP_NIGHT
		_car_timer = randf_range(gap.x, gap.y)
		_spawn_car(-STREET_END)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for car in _cars.duplicate():
		if not is_instance_valid(car):
			_cars.erase(car)
			continue
		var speed: float = car.get_meta("speed")
		var blocked := false
		for who in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("police") + get_tree().get_nodes_in_group("collector"):
			var ahead: float = who.global_position.x - car.position.x
			if ahead > 0.0 and ahead < STOP_DISTANCE + 1.0 and absf(who.global_position.z - LANE_Z) < 1.4:
				blocked = true
		for other in _cars:
			if other != car and is_instance_valid(other):
				var gap: float = other.position.x - car.position.x
				if gap > 0.0 and gap < STOP_DISTANCE + 1.5:
					blocked = true
		if blocked:
			if not car.get_meta("honked") and player and absf(player.global_position.x - car.position.x) < STOP_DISTANCE + 1.0:
				car.set_meta("honked", true)
				(car.get_node("Horn") as AudioStreamPlayer3D).play()
		else:
			car.set_meta("honked", false)
			car.position.x += speed * delta
		if car.position.x > STREET_END:
			_cars.erase(car)
			car.queue_free()

func _spawn_car(x: float) -> void:
	var car := Node3D.new()
	car.name = "TrafficCar"
	var model: Node3D = load("res://assets/kenney/cars/%s.glb" % CARS.pick_random()).instantiate()
	model.scale = Vector3.ONE * CAR_SCALE
	model.position.y = 0.3 * CAR_SCALE
	model.rotation_degrees.y = 90.0
	car.add_child(model)
	add_child(car)
	car.position = Vector3(x, 0, LANE_Z)
	car.reset_physics_interpolation()
	car.set_meta("speed", randf_range(LANE_SPEED.x, LANE_SPEED.y))
	car.set_meta("honked", false)
	var horn := AudioStreamPlayer3D.new()
	horn.name = "Horn"
	horn.stream = preload("res://assets/sfx/car_horn.wav")
	horn.volume_db = -2.0
	horn.unit_size = 6.0
	car.add_child(horn)
	var engine := AudioStreamPlayer3D.new()
	engine.name = "Engine"
	engine.stream = preload("res://assets/sfx/car_pass.wav")
	engine.volume_db = -6.0
	engine.unit_size = 5.0
	engine.max_distance = 30.0
	car.add_child(engine)
	engine.play()
	# Lights, but only once it's getting dark.
	if GameState.daylight() < 0.6:
		var beam := SpotLight3D.new()
		beam.light_color = Color(1.0, 0.95, 0.8)
		beam.light_energy = 3.0
		beam.spot_range = 12.0
		beam.spot_angle = 32.0
		beam.shadow_enabled = false
		beam.position = Vector3(2.0, 0.8, 0)
		beam.rotation_degrees = Vector3(-8, -90, 0)
		car.add_child(beam)
		var glow := StandardMaterial3D.new()
		glow.emission_enabled = true
		glow.albedo_color = Color(1.0, 0.95, 0.8)
		glow.emission = Color(1.0, 0.95, 0.8)
		glow.emission_energy_multiplier = 4.0
		var tail := glow.duplicate() as StandardMaterial3D
		tail.albedo_color = Color(1.0, 0.1, 0.05)
		tail.emission = Color(1.0, 0.1, 0.05)
		for side in [-0.55, 0.55]:
			_lamp(car, Vector3(2.05, 0.75, side), glow)
			_lamp(car, Vector3(-2.05, 0.8, side), tail)
	_cars.append(car)

func _lamp(car: Node3D, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.12, 0.28)
	box.material = mat
	m.mesh = box
	m.position = pos
	car.add_child(m)

# --- Steam -----------------------------------------------------------------

func _add_steam(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.name = "Steam"
	p.amount = 18
	p.lifetime = 3.5
	p.preprocess = 3.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.15, 0.05, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var grow := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	grow.curve = curve
	pm.scale_curve = grow
	var ramp := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.85, 0.9, 0.0))
	g.set_color(1, Color(0.85, 0.85, 0.9, 0.0))
	g.add_point(0.25, Color(0.8, 0.82, 0.88, 0.09))
	ramp.gradient = g
	pm.color_ramp = ramp
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 0.8))
	pg.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = pg
	mat.albedo_texture = puff
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	p.position = at

# --- Rain ------------------------------------------------------------------

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 900
	_rain.lifetime = 0.7
	_rain.visibility_aabb = AABB(Vector3(-15, -12, -12), Vector3(30, 14, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.5, 10)
	pm.direction = Vector3(0.12, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.6)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	streak.material = mat
	_rain.draw_pass_1 = streak
	_rain.emitting = false
	add_child(_rain)
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = preload("res://assets/sfx/rain_loop.wav")
	_rain_sound.volume_db = -10.0
	_rain_sound.bus = "Ambience"
	add_child(_rain_sound)
	# The street's ground materials, to wet down in the rain.
	for mi in get_parent().find_children("*", "MeshInstance3D", true, false):
		if mi.name in ["Road", "Sidewalk", "Floor"] or String(mi.get_parent().name) == "Floor" or String(mi.name).begins_with("Alley"):
			var mat2 := mi.get_active_material(0) as StandardMaterial3D
			if mat2 and not _wet_materials.has(mat2):
				_wet_materials.append(mat2)
				mat2.set_meta("dry_roughness", mat2.roughness)

func _on_weather_changed(raining: bool) -> void:
	if _rain:
		_rain.emitting = raining
	if raining and not _rain_sound.playing:
		_rain_sound.play()
	elif not raining:
		_rain_sound.stop()
	for mat in _wet_materials:
		mat.roughness = 0.35 if raining else float(mat.get_meta("dry_roughness", 1.0))

# --- Neon ------------------------------------------------------------------

func _pick_flickering_signs() -> void:
	var glows := get_parent().find_children("*SignGlow", "Light3D", true, false)
	glows.shuffle()
	for glow in glows.slice(0, 2):
		var sign := get_parent().get_node_or_null(String(glow.name).replace("SignGlow", "Sign")) as Label3D
		_flicker.append({"light": glow, "sign": sign, "energy": glow.light_energy, "timer": randf_range(1.0, 6.0), "off": 0.0})

## Sick enough, every sign on the block starts to stutter, not just the two
## that always do; they settle again as you come back up.
const SICK_FLICKER := 0.5
var _sick_signs_added: bool = false

func _add_sick_flicker() -> void:
	_sick_signs_added = true
	var taken := _flicker.map(func(f): return f["light"])
	for glow in get_parent().find_children("*SignGlow", "Light3D", true, false):
		if glow in taken:
			continue
		var sign := get_parent().get_node_or_null(String(glow.name).replace("SignGlow", "Sign")) as Label3D
		_flicker.append({"light": glow, "sign": sign, "energy": glow.light_energy, "timer": randf_range(0.5, 4.0), "off": 0.0, "sick": true})

func _update_flicker(delta: float) -> void:
	var sick := GameState.sickness() >= SICK_FLICKER
	if sick and not _sick_signs_added:
		_add_sick_flicker()
	for f in _flicker:
		if f.get("sick", false) and not sick:
			if f["off"] > 0.0:
				f["off"] = 0.0
				_set_sign(f, true)
			continue
		if f["off"] > 0.0:
			f["off"] -= delta
			if f["off"] <= 0.0:
				_set_sign(f, true)
			continue
		f["timer"] -= delta
		if f["timer"] <= 0.0:
			# A burst of a few quick cut-outs, then steady for a while.
			f["off"] = randf_range(0.04, 0.18)
			f["timer"] = randf_range(0.05, 0.3) if randf() < 0.6 else randf_range(3.0, 9.0)
			_set_sign(f, false)

func _set_sign(f: Dictionary, on: bool) -> void:
	# Visibility, not energy: City3D owns the energy (it follows daylight).
	(f["light"] as Light3D).visible = on
	if f["sign"]:
		(f["sign"] as Label3D).modulate.a = 1.0 if on else 0.25
