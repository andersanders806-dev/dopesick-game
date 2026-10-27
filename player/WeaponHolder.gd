extends Node
## What the player carries in Dead Block: two gun slots with their own mag and
## reserve, firing (hitscan from the view through the zombies' hit zones),
## reloading, swapping, the knife -- and the points a hit, a kill, a
## headshot and a knife kill pay.
##
## Child of the Player3D (world/ZombieBlock.gd adds it). Input is the
## "fire", "reload", "swap_weapon", "melee" and "aim" actions, made here so
## project.godot stays as it is. Everything the input does is a method
## (fire(), reload(), swap(), melee()), which the tests call directly;
## advance(delta) is the clock (_process) the cooldowns and the reload run on.
##
## A zombie (npc/Zombie3D.gd, or the tests' double) takes the final damage
## through take_hit(part, damage, dir, weapon, melee) and says what happened
## with its `hit` and `died` signals, which are read for the points while
## take_hit() runs, so a hit is paid once however many pellets land.

const WD := preload("res://weapons/WeaponData.gd")
const GunModel := preload("res://weapons/GunModel.gd")

signal fired
## A zombie was hit: the hit zone's part, and whether that killed it.
signal hit(part: String, killed: bool)
signal weapon_changed(data: WD)
signal ammo_changed
signal reload_started
signal reload_finished
## A shot ended on world or air (for tracers and sparks): [from, to].
signal traced(from: Vector3, to: Vector3)

const MAX_SLOTS := 2
const START_WEAPON := "res://weapons/pistol.tres"
const KNIFE := "res://weapons/knife.tres"
const POOL_IDS := ["smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder"]
## The zombies' hit zones sit on this physics layer (npc/ZombieHitboxes.gd).
const HITBOX_LAYER := 64
const MELEE_RANGE := 1.9
const MELEE_COOLDOWN := 0.55
## How far a bullet goes.
const RANGE := 120.0
## Where the third-person shot starts and the height it flies at.
const TP_MUZZLE_HEIGHT := 1.25

## [{data, mag, reserve}] with a null for an empty slot.
var slots: Array = [null, null]
var active := 0
var reloading := false
var aiming := false
## Perks (Quickhands, Double Shot) scale these.
var reload_mult := 1.0
var rate_mult := 1.0
## Tests: no spread, so a shot goes exactly where it is aimed.
var no_spread := false
## Tests: where to shoot from and along, instead of the view. () -> [origin, dir]
var aim_source := Callable()
var rng := RandomNumberGenerator.new()

var player: Node3D
var viewmodel: Node3D
var melee_data: WD
var _cooldown := 0.0
var _swap_left := 0.0
var _reload_left := 0.0
var _melee_cd := 0.0
var _trigger_down := false
## This shot's zombies hurt but not killed (instance id -> true), paid 10 each when it's over.
var _wounded: Dictionary = {}
var _in_melee := false

var current: WD:
	get: return slots[active].data if slots[active] != null else null
var mag: int:
	get: return int(slots[active].mag) if slots[active] != null else 0
	set(v):
		if slots[active] != null:
			slots[active].mag = v
var reserve: int:
	get: return int(slots[active].reserve) if slots[active] != null else 0
	set(v):
		if slots[active] != null:
			slots[active].reserve = v

func _ready() -> void:
	add_to_group("weapon_holder")
	name = "WeaponHolder"
	rng.randomize()
	player = get_parent() as Node3D
	melee_data = load(KNIFE)
	_make_actions()
	if current == null:
		give(load(START_WEAPON))
	if Graphics.has_signal("view_changed"):
		Graphics.view_changed.connect(func(_on: bool): _rebuild_viewmodel())

func _make_actions() -> void:
	_action("fire", [_mouse(MOUSE_BUTTON_LEFT)], [_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("aim", [_mouse(MOUSE_BUTTON_RIGHT)], [_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action("reload", [_key(KEY_R)], [_button(JOY_BUTTON_X)])
	_action("swap_weapon", [_key(KEY_Q)], [_button(JOY_BUTTON_Y)])
	_action("melee", [_key(KEY_V)], [_button(JOY_BUTTON_RIGHT_STICK)])

func _action(action: String, keys: Array, pads: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.3)
	for e in keys + pads:
		InputMap.action_add_event(action, e)

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e

func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e

func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e

func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e

# --- The guns you hold -------------------------------------------------------------

func slot_data(i: int) -> WD:
	return slots[i].data if slots[i] != null else null

## Whether a version of this gun (base id: "smg") is in either slot.
func has_weapon(base: String) -> bool:
	for s in slots:
		if s != null and s.data.family() == base:
			return true
	return false

func held_families() -> Array:
	var out := []
	for s in slots:
		if s != null:
			out.append(s.data.family())
	return out

## The slot a version of this gun is in, or -1.
func slot_of(base: String) -> int:
	for i in MAX_SLOTS:
		if slots[i] != null and slots[i].data.family() == base:
			return i
	return -1

## Hands you a gun, full: in a free slot if there is one (and switches to
## it), otherwise in place of the one in your hands. A gun you already carry
## is just topped up.
func give(data: WD) -> void:
	var have := slot_of(data.family())
	var i := have
	if i < 0:
		i = slots.find(null)
		if i < 0:
			i = active
	slots[i] = {"data": data, "mag": data.mag_size, "reserve": data.reserve_max}
	_switch_to(i)

func _switch_to(i: int) -> void:
	active = i
	_cancel_reload()
	_cooldown = 0.0
	_swap_left = current.swap_time if current else 0.0
	aiming = false
	_rebuild_viewmodel()
	weapon_changed.emit(current)
	ammo_changed.emit()

## Refills the gun in your hands (the wall's ammo).
func refill_current() -> void:
	if slots[active] == null:
		return
	slots[active].mag = current.mag_size
	slots[active].reserve = current.reserve_max
	ammo_changed.emit()

## Max Ammo: every gun, full.
func refill_all() -> void:
	for s in slots:
		if s != null:
			s.mag = s.data.mag_size
			s.reserve = s.data.reserve_max
	ammo_changed.emit()

func is_full() -> bool:
	return current != null and mag >= current.mag_size and reserve >= current.reserve_max

## The upgrade machine: the gun in your hands becomes its upgraded self,
## full. False if it has none or already is one.
func upgrade_current() -> bool:
	var d: WD = current
	if d == null or d.upgrade == null or d.upgraded:
		return false
	slots[active] = {"data": d.upgrade, "mag": d.upgrade.mag_size, "reserve": d.upgrade.reserve_max}
	_cancel_reload()
	_rebuild_viewmodel()
	weapon_changed.emit(current)
	ammo_changed.emit()
	return true

func swap() -> bool:
	var other := 1 - active
	if slots[other] == null:
		return false
	_switch_to(other)
	return true

# --- Time ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _can_act():
		_trigger_down = false
		return
	advance(delta)
	var down := Input.is_action_pressed("fire")
	if down and current != null and (current.auto or not _trigger_down):
		fire()
	_trigger_down = down
	aiming = Input.is_action_pressed("aim") and not reloading
	if Input.is_action_just_pressed("reload"):
		reload()
	if Input.is_action_just_pressed("swap_weapon"):
		swap()
	if Input.is_action_just_pressed("melee"):
		melee()

func _can_act() -> bool:
	if get_tree().paused or not ZombieMode.active or ZombieMode.over:
		return false
	if player != null and player.get("dialogue_active") == true:
		return false
	return true

## Runs the cooldowns and the reload.
func advance(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_swap_left = maxf(_swap_left - delta, 0.0)
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

# --- Reloading ----------------------------------------------------------------------

func reload() -> bool:
	var d := current
	if d == null or reloading or mag >= d.mag_size or reserve <= 0:
		return false
	reloading = true
	aiming = false
	_reload_left = d.reload_time * reload_mult
	reload_started.emit()
	return true

func _finish_reload() -> void:
	reloading = false
	var d := current
	if d != null:
		var take := mini(d.mag_size - mag, reserve)
		mag += take
		reserve -= take
	reload_finished.emit()
	ammo_changed.emit()

func _cancel_reload() -> void:
	reloading = false
	_reload_left = 0.0

func reload_left() -> float:
	return _reload_left if reloading else 0.0

# --- Firing -------------------------------------------------------------------------

func can_fire() -> bool:
	return current != null and not reloading and _cooldown <= 0.0 and _swap_left <= 0.0 and mag > 0

## Pulls the trigger once. False if nothing came out (cooling, reloading,
## swapping, or empty: which starts a reload while there is anything to load).
func fire() -> bool:
	var d := current
	if d == null or reloading or _cooldown > 0.0 or _swap_left > 0.0:
		return false
	if mag <= 0:
		if reserve > 0:
			reload()
		else:
			SFX.play("latch", -10.0, 1.4)
		return false
	mag -= 1
	_cooldown = d.interval() / maxf(rate_mult, 0.1)
	var aim := _aim()
	_shoot(aim[0], aim[1])
	fired.emit()
	ammo_changed.emit()
	SFX.play("punch", -9.0, 0.55 if d.pellets > 1 else 0.8)
	if player != null and player.has_method("kick"):
		player.kick(clampf(d.recoil * 0.12, 0.0, 0.6))
	return true

## Shoots the gun's bullets from `origin` along `dir` (no ammo, no cooldown):
## fire() is this plus the trigger.
func shoot_at(origin: Vector3, dir: Vector3) -> void:
	_shoot(origin, dir.normalized())

func _shoot(origin: Vector3, dir: Vector3) -> void:
	var d := current
	_wounded.clear()
	var cone: float = 0.0 if no_spread else (d.spread_ads if aiming else d.spread_hip)
	for i in d.pellets:
		var v := _scatter(dir, cone)
		var r := _cast(origin, v, RANGE)
		if r.is_empty():
			traced.emit(origin, origin + v * RANGE)
			continue
		var z: Node = r.get("zombie")
		traced.emit(origin, r.position)
		if z == null:
			continue
		var dist := origin.distance_to(r.position)
		_hurt(z, r.part, d.damage_at(r.part, dist), v, d, false)
		if d.splash_radius > 0.0:
			_splash(z, r.position, d, v, dist)
	_pay_hits()

func _scatter(dir: Vector3, cone_deg: float) -> Vector3:
	if cone_deg <= 0.0:
		return dir
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var real_up := right.cross(dir).normalized()
	var ang := deg_to_rad(cone_deg) * sqrt(rng.randf())
	var around := rng.randf() * TAU
	return (dir + (right * cos(around) + real_up * sin(around)) * tan(ang)).normalized()

## The first thing a ray from `origin` along `dir` stops at, looking through
## zombies' own capsules and through every trigger zone: {position, collider,
## zombie, part} (zombie is null for a wall or the ground), or {} for air.
func _cast(origin: Vector3, dir: Vector3, length: float) -> Dictionary:
	if player == null:
		return {}
	var space := player.get_world_3d().direct_space_state
	var skip: Array[RID] = [(player as CollisionObject3D).get_rid()]
	for n in 24:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * length)
		q.exclude = skip
		q.collide_with_areas = true
		q.collide_with_bodies = true
		var r := space.intersect_ray(q)
		if r.is_empty():
			return {}
		var c := r.collider as CollisionObject3D
		if c is Area3D:
			var part := _part_of(c)
			if part != "" and (c.collision_layer & HITBOX_LAYER) != 0:
				var z := _owner_of(c)
				if z != null:
					return {"position": r.position, "collider": c, "zombie": z, "part": part}
			skip.append(c.get_rid())
			continue
		if c.has_method("take_hit"):
			skip.append(c.get_rid())
			continue
		return {"position": r.position, "collider": c, "zombie": null, "part": ""}
	return {}

## "head", "neck", "torso", "upper_arm_l", ...: what a hit zone says it is.
func _part_of(area: Node) -> String:
	if area.has_meta("part"):
		return String(area.get_meta("part"))
	return ""

## The zombie a hit zone belongs to: what it says, or the nearest parent that can take a hit.
func _owner_of(area: Node) -> Node:
	if area.has_meta("zombie"):
		var z = area.get_meta("zombie")
		if is_instance_valid(z):
			return z as Node
	var n := area.get_parent()
	while n != null:
		if n.has_method("take_hit"):
			return n
		n = n.get_parent()
	return null

## The wonder weapon's burst: the zombies near the one hit take half.
func _splash(first: Node, at: Vector3, d: WD, dir: Vector3, dist: float) -> void:
	for other in get_tree().get_nodes_in_group("zombies"):
		if other == first or not (other is Node3D):
			continue
		if (other as Node3D).global_position.distance_to(at) <= d.splash_radius + 0.8:
			_hurt(other, "torso", d.damage_at("torso", dist) * 0.5, dir, d, false)

## Hands the zombie its damage and pays for what happened.
func _hurt(z: Node, part: String, dmg: float, dir: Vector3, weapon: Resource, melee_hit: bool) -> void:
	if not z.has_method("take_hit") or (z.has_method("is_alive") and not z.is_alive()):
		return
	var on_hit := _on_zombie_hit
	var on_died := _on_zombie_died
	if z.has_signal("hit"):
		z.connect("hit", on_hit)
	if z.has_signal("died"):
		z.connect("died", on_died)
	z.take_hit(part, dmg, dir, weapon, melee_hit)
	if is_instance_valid(z):
		if z.has_signal("hit") and z.is_connected("hit", on_hit):
			z.disconnect("hit", on_hit)
		if z.has_signal("died") and z.is_connected("died", on_died):
			z.disconnect("died", on_died)

func _on_zombie_hit(z: Node, part: String, _damage: float, killed: bool) -> void:
	hit.emit(part, killed)
	if not killed:
		_wounded[z.get_instance_id()] = true

## 10 for each zombie the shot hurt and didn't kill, once however many pellets landed (a kill pays its own).
func _pay_hits() -> void:
	for id in _wounded:
		ZombieMode.add_points(ZombieMode.POINTS_HIT, "hit")
	_wounded.clear()

func _on_zombie_died(z: Node, part: String, melee_kill: bool) -> void:
	_wounded.erase(z.get_instance_id())
	ZombieMode.add_points(kill_points(part, melee_kill or _in_melee), "kill")

## What the kill pays: 130 for the knife, 100 headshot, 70 neck, 60 anything else.
static func kill_points(part: String, melee_kill: bool) -> int:
	if melee_kill:
		return ZombieMode.POINTS_KILL_MELEE
	if part == "head":
		return ZombieMode.POINTS_KILL_HEAD
	if part == "neck":
		return ZombieMode.POINTS_KILL_NECK
	return ZombieMode.POINTS_KILL_BODY

# --- The knife ----------------------------------------------------------------------

## A quick stab at whatever is right in front of you.
func melee() -> bool:
	if _melee_cd > 0.0 or melee_data == null:
		return false
	_melee_cd = MELEE_COOLDOWN
	var aim := _aim()
	var r := _cast(aim[0], aim[1], MELEE_RANGE)
	SFX.play("punch", -4.0, 1.1)
	if r.is_empty() or r.get("zombie") == null:
		return true
	_wounded.clear()
	_in_melee = true
	_hurt(r.zombie, r.part, melee_data.damage_at(r.part), aim[1], melee_data, true)
	_in_melee = false
	_pay_hits()
	return true

# --- Aim ----------------------------------------------------------------------------

## [origin, direction] of a shot: from the eye through the crosshair in first
## person; from the chest toward the mouse in third.
func _aim() -> Array:
	if aim_source.is_valid():
		var a: Array = aim_source.call()
		return [a[0], (a[1] as Vector3).normalized()]
	var cam := get_viewport().get_camera_3d()
	if Graphics.first_person and cam != null:
		return [cam.global_position, -cam.global_transform.basis.z]
	var chest := player.global_position + Vector3(0, TP_MUZZLE_HEIGHT, 0)
	var dir := _facing()
	if cam != null:
		var mouse := get_viewport().get_mouse_position()
		var ro := cam.project_ray_origin(mouse)
		var rd := cam.project_ray_normal(mouse)
		if absf(rd.y) > 0.001:
			var t := (TP_MUZZLE_HEIGHT - ro.y) / rd.y
			if t > 0.0:
				var spot := ro + rd * t
				var flat := Vector3(spot.x - chest.x, 0, spot.z - chest.z)
				if flat.length() > 0.3:
					dir = flat.normalized()
	return [chest, dir]

func _facing() -> Vector3:
	var m: Node3D = player.get("model") as Node3D if player != null else null
	var a: float = m.rotation.y if m != null else 0.0
	return Vector3(sin(a), 0.0, cos(a))

# --- What you see -------------------------------------------------------------------

## The gun in your hands, low on the right of the first-person view. (The
## feel of it -- sway, reload dip, third-person hands -- is Z4/Z5's.)
func _rebuild_viewmodel() -> void:
	if is_instance_valid(viewmodel):
		viewmodel.queue_free()
		viewmodel = null
	var d := current
	if d == null or player == null or not Graphics.first_person:
		return
	var cam := player.get("camera") as Camera3D
	if cam == null:
		return
	viewmodel = Node3D.new()
	viewmodel.name = "Viewmodel"
	viewmodel.position = Vector3(0.15, -0.16, -0.42)
	viewmodel.rotation_degrees.y = -2.0
	var gun := GunModel.build(d)
	viewmodel.add_child(gun)
	# The night is red-dark; the gun gets a little light of its own.
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.9
	lamp.omni_range = 1.6
	lamp.shadow_enabled = false
	lamp.light_color = Color(1.0, 0.92, 0.85)
	lamp.position = Vector3(-0.1, 0.25, 0.3)
	viewmodel.add_child(lamp)
	cam.add_child(viewmodel)
