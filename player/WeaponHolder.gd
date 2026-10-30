extends Node
## What the player carries in Dead Block: two gun slots with their own mag and
## reserve, firing (hitscan from the view through the zombies' hit zones),
## reloading, swapping, the knife -- and the points a hit, a kill, a
## headshot and a knife kill pay.
##
## Child of the Player3D (world/ZombieBlock.gd adds it). Input is the "fire",
## "aim", "reload", "swap_weapon", "weapon_slot_1/2" and "melee" actions, which
## player/ZombieControls.gd binds for the mode (Call of Duty's layout, nothing
## on a button the story uses for something else). Everything the input does is a method
## (fire(), reload(), swap(), melee()), which the tests call directly;
## advance(delta) is the clock (_process) the cooldowns and the reload run on.
##
## A zombie (npc/Zombie3D.gd, or the tests' double) takes the final damage
## through take_hit(part, damage, dir, weapon, melee) and says what happened
## with its `hit` and `died` signals, which are read for the points while
## take_hit() runs, so a hit is paid once however many pellets land.

const WD := preload("res://weapons/WeaponData.gd")
const GunModel := preload("res://weapons/GunModel.gd")
const ZombieControls := preload("res://player/ZombieControls.gd")
const Viewmodel := preload("res://player/Viewmodel.gd")
const FPFeel := preload("res://player/FPFeel.gd")

signal fired
## A zombie was hit: the hit zone's part, and whether that killed it.
signal hit(part: String, killed: bool)
signal weapon_changed(data: WD)
signal ammo_changed
signal reload_started
signal reload_finished
## The trigger was pulled on an empty gun with nothing to load.
signal dry_fired
## The knife went out: whether it found something.
signal melee_swung(found: bool)
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
## Where the third-person shot starts (chest height).
const TP_MUZZLE_HEIGHT := 1.25
## With the pad in third person the crosshair is this far ahead of the chest.
const PAD_CROSSHAIR := 6.0
## How long the pad's reload button is held at a board, the box or the machine to buy.
const HOLD_TIME := 0.4

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
## Tests: the screen point third-person aims through, instead of the mouse / pad crosshair. () -> Vector2
var screen_aim_source := Callable()
var rng := RandomNumberGenerator.new()

var player: Node3D
var viewmodel: Node3D
## player/FPFeel.gd: aiming, recoil, sway, slide, the effects of a shot.
var feel: Node
var melee_data: WD
var _cooldown := 0.0
var _swap_left := 0.0
var _reload_left := 0.0
var _melee_cd := 0.0
var _trigger_down := false
## This shot's zombies hurt but not killed (instance id -> true), paid 10 each when it's over.
var _wounded: Dictionary = {}
var _in_melee := false
## Seconds the pad's reload button has been down at something to buy (-1: not held, -2: bought).
var _hold := -1.0

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
	ZombieControls.apply()
	if current == null:
		give(load(START_WEAPON))
	if Graphics.has_signal("view_changed"):
		Graphics.view_changed.connect(func(_on: bool): _rebuild_viewmodel())
	feel = FPFeel.new()
	add_child(feel)

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
	aiming = Input.is_action_pressed("aim") and not reloading and not (player != null and player.has_method("is_sprinting") and player.is_sprinting())

## The one-shot buttons (a press is an event: the mouse wheel has no "held").
func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not _can_act():
		_hold = -1.0
		return
	if event.is_action_pressed("reload"):
		# On the pad Square is also "use": at something to buy, a tap reloads
		# and a hold buys.
		if event is InputEventJoypadButton and _purchase_in_reach():
			_hold = 0.0
		else:
			reload()
	elif event.is_action_released("reload"):
		if _hold >= 0.0:
			reload()
		_hold = -1.0
	elif event.is_action_pressed("swap_weapon"):
		swap()
	elif event.is_action_pressed("weapon_slot_1"):
		select(0)
	elif event.is_action_pressed("weapon_slot_2"):
		select(1)
	elif event.is_action_pressed("melee"):
		melee()

func _purchase_in_reach() -> bool:
	return player != null and player.has_method("_nearest_interactable") and player._nearest_interactable() != null

## The gun in slot `i`, if there is one there and it isn't in your hands.
func select(i: int) -> bool:
	if i < 0 or i >= MAX_SLOTS or i == active or slots[i] == null:
		return false
	_switch_to(i)
	return true

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
	if _hold >= 0.0:
		_hold += delta
		if _hold >= HOLD_TIME:
			_hold = -2.0
			if player != null and player.has_method("_try_interact"):
				player._try_interact()
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
			dry_fired.emit()
		return false
	mag -= 1
	_cooldown = d.interval() / maxf(rate_mult, 0.1)
	var aim := _aim()
	_shoot(aim[0], aim[1])
	fired.emit()
	ammo_changed.emit()
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
	_sync_zones(origin, dir, length)
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

## The hit zones are not kept on the bones every frame (npc/ZombieHitboxes.gd):
## the zombies near this ray get them put where their animation has the bones,
## just before the cast.
func _sync_zones(origin: Vector3, dir: Vector3, length: float) -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D) or not z.has_method("sync_hitboxes"):
			continue
		var c: Vector3 = (z as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
		var along := (c - origin).dot(dir)
		if along < -1.5 or along > length + 1.5:
			continue
		if (c - (origin + dir * clampf(along, 0.0, length))).length_squared() < 2.6:
			z.sync_hitboxes()

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
	var found: bool = not r.is_empty() and r.get("zombie") != null
	melee_swung.emit(found)
	if not found:
		return true
	SFX.play("punch", -4.0, 1.1)
	_wounded.clear()
	_in_melee = true
	_hurt(r.zombie, r.part, melee_data.damage_at(r.part), aim[1], melee_data, true)
	_in_melee = false
	_pay_hits()
	return true

# --- Aim ----------------------------------------------------------------------------

## [origin, direction] of a shot. First person: from the eye through the
## crosshair. Third person: from the chest to the point the active camera sees
## under the crosshair, so a zombie's head can be shot at (aim_screen_point).
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
		var p := aim_screen_point()
		var ro := cam.project_ray_origin(p)
		var rd := cam.project_ray_normal(p)
		# The first thing the camera's ray meets, looking only from just before
		# it passes the chest (a roof or wall near the lens is not what you aim at).
		var t0 := maxf((chest - ro).dot(rd) - 1.0, 0.0)
		var r := _cast(ro + rd * t0, rd, RANGE)
		var spot: Vector3 = r.position if not r.is_empty() else ro + rd * (t0 + 60.0)
		if spot.distance_to(chest) > 0.3:
			dir = (spot - chest).normalized()
	return [chest, dir]

## Where on the screen the third-person crosshair is: under the mouse, or with
## the pad (or a captured mouse) a spot 6 m ahead of the chest.
func aim_screen_point() -> Vector2:
	if screen_aim_source.is_valid():
		return screen_aim_source.call()
	var cam := get_viewport().get_camera_3d()
	if GameState.using_pad or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return cam.unproject_position(player.global_position + Vector3(0, TP_MUZZLE_HEIGHT, 0) + _facing() * PAD_CROSSHAIR)
	return get_viewport().get_mouse_position()

func _facing() -> Vector3:
	var m: Node3D = player.get("model") as Node3D if player != null else null
	var a: float = m.rotation.y if m != null else 0.0
	return Vector3(sin(a), 0.0, cos(a))

# --- What you see -------------------------------------------------------------------

## The gun in your hands and the arms holding it (player/Viewmodel.gd), on the
## camera; player/FPFeel.gd moves it. Nothing in third person.
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
	viewmodel = Viewmodel.new().setup(d)
	viewmodel.position = FPFeel.HIP_POS
	# The night is red-dark; the gun gets a little light of its own.
	var lamp := OmniLight3D.new()
	lamp.name = "GunLamp"
	lamp.light_energy = 0.9
	lamp.omni_range = 1.6
	lamp.shadow_enabled = false
	lamp.light_color = Color(1.0, 0.92, 0.85)
	lamp.position = Vector3(-0.1, 0.25, 0.3)
	viewmodel.add_child(lamp)
	cam.add_child(viewmodel)
