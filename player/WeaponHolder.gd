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
const ImpactFX := preload("res://fx/ImpactFX.gd")
const AimAssist := preload("res://player/AimAssist.gd")
const PadRumble := preload("res://player/PadRumble.gd")
const GunSounds := preload("res://weapons/GunSounds.gd")
const RocketScript := preload("res://fx/Rocket.gd")
## A shotgun this close throws a zombie back.
const KNOCK_RANGE := 4.5

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
## The selector went to another mode ("auto", "burst", "semi").
signal mode_changed(mode: String)
## A melee weapon's swing began: heavy (the button held), and whether it lunged at someone.
signal swing_started(heavy: bool, lunged: bool)
## A melee weapon's blow landed: how many it hit, whether one died, and whether it met a wall instead.
signal swing_landed(hits: int, killed: bool, wall: bool)
## The melee weapon in the knife's place changed (a bat or a machete bought off the wall, or upgraded).
signal melee_changed(data: WD)
## A rocket went off: where, and its blast radius.
signal exploded(at: Vector3, radius: float)

const MAX_SLOTS := 2
const START_WEAPON := "res://weapons/pistol.tres"
const KNIFE := "res://weapons/knife.tres"
const POOL_IDS := ["smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder", "mp5", "vector", "ak", "m16", "deagle", "aa12", "dmr",
	"amr", "saw", "rpg"]
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
## The melee button held this long swings a melee weapon's heavy hit.
const HEAVY_HOLD := 0.22
## A pierced zombie keeps this much of the round for the next.
const PIERCE_KEEP := 0.8
## Metres a second of a lunge at a zombie, and the most it lasts.
const LUNGE_SPEED := 11.0
const LUNGE_MAX := 0.32

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
## Rounds of the burst still to come, and seconds after a sprint before the trigger answers.
var _burst_left := 0
var _sprint_hold := 0.0
## A reload that a sprint or a swap cut short, to begin again when the way is clear.
var _reload_resume := false
## A press of the trigger that came while the sprint-out was still going: it fires when the delay is over.
var _fire_queued := false
## The seconds of the reload under way (the fraction of it that is done decides what a cut leaves).
var _reload_total := 0.0
## The reload under way began on an empty gun.
var reload_empty := false
## This shot's zombies hurt but not killed (instance id -> true), paid 10 each when it's over.
var _wounded: Dictionary = {}
var _in_melee := false
## Seconds the pad's reload button has been down at something to buy (-1: not held, -2: bought).
var _hold := -1.0
## A melee weapon's swing: seconds into it (-1: none), its length, heavy or not, whether the blow has landed.
var _swing_t := -1.0
var _swing_len := 0.0
var _swing_heavy := false
var _swing_done := false
## Seconds the melee button has been held for a heavy hit (-1: not held).
var _melee_hold := -1.0
## A lunge at a zombie under way: the velocity, and seconds left (Player3D asks for lunge_velocity()).
var lunging := false
var _lunge_v := Vector3.ZERO
var _lunge_left := 0.0
## Rockets in flight and at rest (pooled: a launcher's shot makes none).
var _rockets: Array = []

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
	# The pad: aim assist on the look (first person) and rumble from this node's signals.
	add_child(AimAssist.new())
	add_child(PadRumble.new())

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
	slots[i] = {"data": data, "mag": data.mag_size, "reserve": data.reserve_max, "mode": 0}
	_switch_to(i)

func _switch_to(i: int) -> void:
	# A reload that a swap cuts short is remembered by its gun, and begins again when you are back on it.
	var cut_short := reloading and not _cut_reload()
	if cut_short and slots[active] != null:
		slots[active]["resume"] = true
	active = i
	_cancel_reload()
	_burst_left = 0
	_cooldown = 0.0
	_swap_left = current.swap_time if current else 0.0
	_reload_resume = false
	if slots[active] != null and bool(slots[active].get("resume", false)):
		slots[active]["resume"] = false
		_reload_resume = true
	aiming = false
	_rebuild_viewmodel()
	weapon_changed.emit(current)
	ammo_changed.emit()

## Refills the gun in your hands (the wall's ammo).
func refill_current() -> void:
	if slots[active] == null:
		return
	slots[active].mag = maxi(int(slots[active].mag), current.mag_size)
	slots[active].reserve = current.reserve_max
	ammo_changed.emit()

## Max Ammo: every gun, full.
func refill_all() -> void:
	for s in slots:
		if s != null:
			s.mag = maxi(int(s.mag), s.data.mag_size)
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
	slots[active] = {"data": d.upgrade, "mag": d.upgrade.mag_size, "reserve": d.upgrade.reserve_max, "mode": int(slots[active].get("mode", 0))}
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
		_release_sprint()
		return
	var down := Input.is_action_pressed("fire")
	if InputMap.has_action("melee") and _melee_hold >= 0.0 and not Input.is_action_pressed("melee"):
		# Let go before the heavy hit: the light swing.
		_melee_hold = -1.0
		melee(false)
	# The trigger wins over a reload that a sprint cut short, when there are rounds in the gun to fire.
	if down and mag > 0:
		_reload_resume = false
	if not down:
		_fire_queued = false
	advance(delta)
	# Pulling the trigger on the run ends the sprint (Call of Duty's sprint-out); the gun answers a moment later.
	# (A burst once begun is finished before a sprint takes the gun down, as in Call of Duty.)
	if player != null and player.get("sprint_blocked") != null:
		if (down or _burst_left > 0) and _sprinting():
			player.set("sprint_blocked", true)
			player.set("_sprint_latched", false)
		elif not down and _burst_left <= 0:
			player.set("sprint_blocked", false)
	if down and current != null and (is_auto() or not _trigger_down):
		# A press that comes while the gun can't answer yet (the sprint-out, the cooldown, a swap) is kept until it
		# can, as long as the trigger stays down (a semi gun would lose it).
		if not fire() and mag > 0 and not reloading:
			_fire_queued = true
	_trigger_down = down
	aiming = Input.is_action_pressed("aim") and not reloading and not _sprinting()

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
		# A melee weapon with a heavy hit waits to see whether the button is held; the knife goes at once.
		if melee_data != null and melee_data.heavy_mult > 0.0 and melee_data.melee_arc > 0.0:
			if _swing_t < 0.0 and _melee_cd <= 0.0:
				_melee_hold = 0.0
		else:
			melee()
	elif InputMap.has_action("fire_mode") and event.is_action_pressed("fire_mode"):
		toggle_mode()

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
	var cd := _cooldown - delta
	_cooldown = maxf(cd, 0.0)
	var carry := maxf(-cd, 0.0)
	_swap_left = maxf(_swap_left - delta, 0.0)
	# The sprint: the trigger waits for it to end (and a moment more), and a reload on the run is cut short.
	if _sprinting():
		_sprint_hold = current.sprint_fire_delay if current != null else 0.2
		if reloading:
			_reload_resume = not _cut_reload()
	else:
		_sprint_hold = maxf(_sprint_hold - delta, 0.0)
	# The kept press fires the moment the gun can; an empty gun or a reload drops it.
	if _fire_queued and _sprint_hold <= 0.0 and not _sprinting():
		if current == null or mag <= 0 or reloading:
			_fire_queued = false
		elif fire():
			_fire_queued = false
	if _reload_resume and not reloading and _swap_left <= 0.0 and _sprint_hold <= 0.0:
		_reload_resume = false
		reload()
	# The rest of a burst, at the gun's rate.
	while _burst_left > 0 and _cooldown <= 0.0:
		var d := current
		if d == null or reloading or mag <= 0 or _swap_left > 0.0:
			_burst_left = 0
			break
		_fire_round()
		_burst_left -= 1
		if _burst_left <= 0 or mag <= 0:
			_burst_left = 0
			_cooldown += d.burst_delay
		var used := minf(carry, _cooldown)
		_cooldown -= used
		carry -= used
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	_advance_melee(delta)
	for r in _rockets:
		if r.flying:
			r.advance(delta)
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
		_reload_resume = false
		return false
	reloading = true
	aiming = false
	_burst_left = 0
	_reload_resume = false
	reload_empty = mag <= 0
	_reload_left = d.reload_for(reload_empty) * reload_mult
	_reload_total = _reload_left
	reload_started.emit()
	return true

func _finish_reload() -> void:
	reloading = false
	var d := current
	if d != null:
		# A tactical reload leaves a round in the chamber as well.
		var take := mini(d.mag_cap(not reload_empty) - mag, reserve)
		mag += take
		reserve -= take
	reload_finished.emit()
	ammo_changed.emit()

## A reload cut short (a sprint, a swap): once the new magazine is in (its cue has played) it counts as done, as in
## Call of Duty; before that nothing is loaded and it starts again later. True if it counted as done.
func _cut_reload() -> bool:
	if not reloading:
		return false
	var d := current
	var done := false
	if d != null and _reload_total > 0.0:
		var progress := 1.0 - _reload_left / _reload_total
		var cues: Array = d.reload_cues_empty if reload_empty else d.reload_cues_tactical
		for c in cues:
			if String(c[1]) == "mag_in" and progress >= float(c[0]):
				done = true
	if done:
		_finish_reload()
	else:
		_cancel_reload()
	return done

func _cancel_reload() -> void:
	reloading = false
	_reload_left = 0.0

## The sprint is the player's again (the trigger is up, or the holder is gone).
func _release_sprint() -> void:
	if player != null and is_instance_valid(player) and player.get("sprint_blocked") == true:
		player.set("sprint_blocked", false)

func _exit_tree() -> void:
	_release_sprint()

## Whether the player is running (the sights and the trigger wait for it).
func _sprinting() -> bool:
	return player != null and player.has_method("is_sprinting") and player.is_sprinting()

func reload_left() -> float:
	return _reload_left if reloading else 0.0

# --- Firing -------------------------------------------------------------------------

func can_fire() -> bool:
	return current != null and not reloading and _cooldown <= 0.0 and _swap_left <= 0.0 and _sprint_hold <= 0.0 and mag > 0

## Pulls the trigger once. False if nothing came out (cooling, reloading,
## swapping, or empty: which starts a reload while there is anything to load).
func fire() -> bool:
	var d := current
	if d == null or reloading or _cooldown > 0.0 or _swap_left > 0.0 or _sprint_hold > 0.0:
		return false
	if mag <= 0:
		if reserve > 0:
			reload()
		else:
			dry_fired.emit()
		return false
	_reload_resume = false
	_fire_round()
	# A burst (the gun's own, or the selector's): the rest of the rounds follow at its rate (advance), then the trigger waits.
	var n := d.burst_of(fire_mode())
	if n > 1:
		_burst_left = mini(n - 1, mag)
		if _burst_left == 0:
			_cooldown += d.burst_delay
	return true

## The mode the selector of the gun in your hands is on ("auto", "burst" or "semi").
func fire_mode() -> String:
	var d := current
	if d == null:
		return "semi"
	if d.fire_modes.is_empty():
		return d.fire_mode()
	var i := int(slots[active].get("mode", 0)) if slots[active] != null else 0
	return d.fire_modes[clampi(i, 0, d.fire_modes.size() - 1)]

## Whether holding the trigger keeps it firing.
func is_auto() -> bool:
	return fire_mode() == "auto"

## The selector to its next mode (B / D-pad left). False on a gun with one mode.
func toggle_mode() -> bool:
	var d := current
	if d == null or d.fire_modes.size() < 2 or slots[active] == null or _burst_left > 0:
		return false
	slots[active]["mode"] = (int(slots[active].get("mode", 0)) + 1) % d.fire_modes.size()
	mode_changed.emit(fire_mode())
	return true

## One round: ammo, the shot, the signals. No checks (fire() and the burst do those).
func _fire_round() -> void:
	var d := current
	mag -= 1
	_cooldown = d.interval() / maxf(rate_mult, 0.1)
	var aim := _aim()
	if d.projectile == "rocket":
		_launch(aim[0], aim[1], d)
	else:
		_shoot(aim[0], aim[1])
	fired.emit()
	ammo_changed.emit()
	if player != null and player.has_method("kick"):
		player.kick(clampf(d.recoil * 0.12, 0.0, 0.6))

## Shoots the gun's bullets from `origin` along `dir` (no ammo, no cooldown):
## fire() is this plus the trigger.
func shoot_at(origin: Vector3, dir: Vector3) -> void:
	_shoot(origin, dir.normalized())

func _shoot(origin: Vector3, dir: Vector3) -> void:
	var d := current
	_wounded.clear()
	var shoved := {}
	var cone: float = 0.0 if no_spread else (d.spread_ads if aiming else d.spread_hip)
	for i in d.pellets:
		var v := _scatter(dir, cone)
		var r := _cast(origin, v, RANGE)
		if r.is_empty():
			traced.emit(origin, origin + v * RANGE)
			continue
		var z: Node = r.get("zombie")
		if z == null:
			traced.emit(origin, r.position)
			var fx := ImpactFX.of(self)
			if fx != null:
				fx.bullet_hit(r.position, r.get("normal", Vector3.UP), r.get("collider"))
			continue
		var dist := origin.distance_to(r.position)
		_hurt(z, r.part, d.damage_at(r.part, dist), v, d, false, r.position)
		# The anti-materiel round goes on through: the next zombies on the line take most of it.
		var end: Vector3 = r.position
		if d.pierce > 0:
			var through: Array = [z]
			var keep := 1.0
			for k in d.pierce:
				var r2 := _cast(origin, v, RANGE, through)
				if r2.is_empty():
					end = origin + v * RANGE
					break
				end = r2.position
				var z2: Node = r2.get("zombie")
				if z2 == null:
					break
				keep *= PIERCE_KEEP
				through.append(z2)
				_hurt(z2, r2.part, d.damage_at(r2.part, origin.distance_to(r2.position)) * keep, v, d, false, r2.position)
		traced.emit(origin, end)
		if d.pellets > 1 and dist < KNOCK_RANGE and z.has_method("knock"):
			shoved[z] = (shoved.get(z, 0.0) as float) + 1.0
		if d.splash_radius > 0.0:
			_splash(z, r.position, d, v, dist)
	# A shotgun's blast at close range throws them back.
	for z in shoved:
		if is_instance_valid(z):
			var away: Vector3 = (z as Node3D).global_position - origin
			var k := clampf(1.0 - away.length() / KNOCK_RANGE, 0.15, 1.0) * clampf(float(shoved[z]) / float(d.pellets) * 1.6, 0.3, 1.0)
			z.knock(away.normalized() * 6.5 * k)
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
func _cast(origin: Vector3, dir: Vector3, length: float, through: Array = []) -> Dictionary:
	if player == null:
		return {}
	_sync_zones(origin, dir, length)
	var space := player.get_world_3d().direct_space_state
	var skip: Array[RID] = [(player as CollisionObject3D).get_rid()]
	for n in 24:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * length)
		q.exclude = skip
		# Not the dead's ragdoll bodies (fx/gore/Ragdolls.gd, layer 512): a shot goes through them.
		q.collision_mask = 0xFFFFFFFF & ~512
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
				if z != null and not through.has(z):
					return {"position": r.position, "collider": c, "zombie": z, "part": part}
			skip.append(c.get_rid())
			continue
		if c.has_method("take_hit"):
			skip.append(c.get_rid())
			continue
		# Chain-link (group "see_through", set by the arena): the round goes through, a spark off the wire.
		if c.is_in_group("see_through"):
			var fx := ImpactFX.of(self)
			if fx != null:
				fx.fence_ping(r.position, r.normal)
			skip.append(c.get_rid())
			continue
		return {"position": r.position, "normal": r.normal, "collider": c, "zombie": null, "part": ""}
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
func _hurt(z: Node, part: String, dmg: float, dir: Vector3, weapon: Resource, melee_hit: bool, at := Vector3.INF) -> void:
	if not z.has_method("take_hit") or (z.has_method("is_alive") and not z.is_alive()):
		return
	var on_hit := _on_zombie_hit
	var on_died := _on_zombie_died
	if z.has_signal("hit"):
		z.connect("hit", on_hit)
	if z.has_signal("died"):
		z.connect("died", on_died)
	z.take_hit(part, dmg, dir, weapon, melee_hit, at)
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

# --- The knife, and the melee weapons that take its place -----------------------------

## Puts a melee weapon (the bat, the machete, or their upgrades) in the knife's place.
func give_melee(d: WD) -> void:
	if d == null:
		return
	melee_data = d
	_swing_t = -1.0
	_melee_hold = -1.0
	melee_changed.emit(d)

## Whether this melee weapon (base id: "bat") is the one you carry in either version.
func has_melee(base: String) -> bool:
	return melee_data != null and melee_data.family() == base

## A melee weapon swings (`heavy`: the slower hit that does heavy_mult); the knife stabs at whatever is right in front
## of you at once. A swing's blow lands a moment in (advance()), on up to melee_targets zombies in its arc; a zombie
## out of reach but within lunge_range is lunged at first.
func melee(heavy := false) -> bool:
	if _melee_cd > 0.0 or melee_data == null or _swing_t >= 0.0:
		return false
	var d := melee_data
	if d.melee_arc > 0.0:
		_swing_heavy = heavy and d.heavy_mult > 0.0
		_swing_len = d.swing_time * (d.heavy_time if _swing_heavy else 1.0)
		_swing_t = 0.0
		_swing_done = false
		_melee_cd = maxf(_swing_len, d.swing_interval())
		var lunged := _try_lunge(d)
		swing_started.emit(_swing_heavy, lunged)
		melee_swung.emit(false)
		return true
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
	_hurt(r.zombie, r.part, melee_data.damage_at(r.part), aim[1], melee_data, true, r.position)
	_in_melee = false
	var gore := get_tree().get_first_node_in_group("gore")
	if gore != null:
		gore.screen_blood(0.6)
	_pay_hits()
	return true

## The swing's clock: the heavy hit's charge, the blow landing, the lunge running out.
func _advance_melee(delta: float) -> void:
	if _melee_hold >= 0.0:
		_melee_hold += delta
		if _melee_hold >= HEAVY_HOLD:
			_melee_hold = -1.0
			melee(true)
	if lunging:
		_lunge_left -= delta
		if _lunge_left <= 0.0:
			lunging = false
	if _swing_t < 0.0:
		return
	_swing_t += delta
	var d := melee_data
	if not _swing_done and d != null and _swing_t >= _swing_len * d.swing_hit:
		_swing_done = true
		lunging = false
		_strike(d)
	if _swing_t >= _swing_len:
		_swing_t = -1.0

## Seconds into the swing under way (-1: none), and its whole length.
func swing_time() -> float:
	return _swing_t

func swing_length() -> float:
	return _swing_len

func swing_heavy() -> bool:
	return _swing_heavy

## The zombies a swing from here would reach: [{z, dist, dir}] nearest first, in the arc and the reach, none behind a wall.
func swing_targets(d: WD, reach: float) -> Array:
	var out: Array = []
	if player == null:
		return out
	var aim := _aim()
	var origin: Vector3 = aim[0]
	var fwd: Vector3 = aim[1]
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var half := deg_to_rad(maxf(d.melee_arc, 10.0) * 0.5)
	var space := player.get_world_3d().direct_space_state
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D) or not z.has_method("take_hit") or (z.has_method("is_alive") and not z.is_alive()):
			continue
		var chest: Vector3 = (z as Node3D).global_position + Vector3(0.0, 1.1, 0.0)
		var to := chest - origin
		var flat_to := Vector3(to.x, 0.0, to.z)
		var dist := flat_to.length()
		if dist > reach + 0.35 or absf(to.y) > 1.6:
			continue
		if dist > 0.3 and flat.angle_to(flat_to.normalized()) > half:
			continue
		# Not through a wall (zombies and trigger zones don't count).
		var q := PhysicsRayQueryParameters3D.create(origin, chest)
		q.collision_mask = 1
		q.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider != z and not (hit.collider as Node).is_in_group("zombies"):
			continue
		out.append({"z": z, "dist": dist, "dir": to.normalized()})
	out.sort_custom(func(a, b): return a.dist < b.dist)
	return out

## A zombie out of reach but close enough: the player is thrown at it (COD's lunge). True if so.
func _try_lunge(d: WD) -> bool:
	if d.lunge_range <= d.melee_range:
		return false
	var near := swing_targets(d, d.lunge_range)
	if near.is_empty() or float(near[0].dist) <= d.melee_range:
		return false
	var gap := float(near[0].dist) - d.melee_range * 0.7
	var dir: Vector3 = near[0].dir
	_lunge_v = Vector3(dir.x, 0.0, dir.z).normalized() * LUNGE_SPEED
	_lunge_left = minf(gap / LUNGE_SPEED, LUNGE_MAX)
	lunging = _lunge_left > 0.0
	return lunging

## The velocity of the lunge this physics tick (Player3D asks while `lunging`).
func lunge_velocity(_delta: float) -> Vector3:
	return _lunge_v if lunging else Vector3.ZERO

## The blow: every zombie in the arc (up to the weapon's count) takes it, thrown back; nothing there and a wall in reach
## answers with the wall's sound.
func _strike(d: WD) -> void:
	var targets := swing_targets(d, d.melee_range)
	var hits := 0
	var killed := false
	_wounded.clear()
	_in_melee = true
	var aim := _aim()
	for t in targets:
		if hits >= d.melee_targets:
			break
		var z: Node = t.z
		# The part the blade meets: what the view's ray finds on this zombie, else the body.
		var part := "torso"
		var r := _cast(aim[0], (((z as Node3D).global_position + Vector3(0.0, 1.35, 0.0)) - aim[0]).normalized(), d.melee_range + 0.6)
		if not r.is_empty() and r.get("zombie") == z:
			part = r.part
		var dmg := d.damage_at(part) * (d.heavy_mult if _swing_heavy else 1.0)
		var was_alive: bool = not z.has_method("is_alive") or z.is_alive()
		_hurt(z, part, dmg, t.dir, d, true, (z as Node3D).global_position + Vector3(0.0, 1.2, 0.0))
		if is_instance_valid(z) and z.has_method("knock") and d.knockback > 0.0:
			var k := d.knockback * (1.5 if _swing_heavy else 1.0)
			z.knock(Vector3(t.dir.x, 0.15, t.dir.z).normalized() * k)
		if was_alive and is_instance_valid(z) and z.has_method("is_alive") and not z.is_alive():
			killed = true
		hits += 1
	_in_melee = false
	_pay_hits()
	var wall := false
	if hits == 0:
		var r2 := _cast(aim[0], aim[1], d.melee_range)
		wall = not r2.is_empty() and r2.get("zombie") == null
		if wall:
			var fx := ImpactFX.of(self)
			if fx != null:
				fx.bullet_hit(r2.position, r2.get("normal", Vector3.UP), r2.get("collider"))
	if hits > 0:
		var gore := get_tree().get_first_node_in_group("gore")
		if gore != null:
			gore.screen_blood(0.35 + 0.15 * hits + (0.2 if _swing_heavy else 0.0))
	swing_landed.emit(hits, killed, wall)

# --- The launcher ---------------------------------------------------------------------

## Sends a rocket from just ahead of the eye along `dir` (pooled: two are kept).
func _launch(origin: Vector3, dir: Vector3, d: WD) -> void:
	var r: Node3D = null
	for x in _rockets:
		if not x.flying:
			r = x
			break
	if r == null:
		r = _new_rocket()
	var spread := 0.0 if no_spread else (d.spread_ads if aiming else d.spread_hip)
	r.fire(origin + dir * 0.6, _scatter(dir, spread * 0.3), d)

func _new_rocket() -> Node3D:
	var r: Node3D = RocketScript.new()
	r.name = "Rocket%d" % _rockets.size()
	r.holder = self
	var world := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(r)
	_rockets.append(r)
	return r

## The two rockets made now (fx/Prewarm.gd), and shown at `at` with their trail and blast on until unwarm_rockets():
## the first shot of the launcher would make them, and draw their materials for the first time, mid-fight.
func warm_rockets(at: Vector3) -> void:
	while _rockets.size() < 2:
		_new_rocket()
	for r in _rockets:
		r.show_for_warm(at)

func unwarm_rockets() -> void:
	for r in _rockets:
		r.hide_after_warm()

## A rocket's blast at `at` (fx/Rocket.gd calls it): full damage at the middle down to a quarter at the edge for every
## zombie in the radius not behind a wall, the one it struck taking it whole; the shooter takes up to self_damage.
func rocket_blast(at: Vector3, d: WD, struck: Node) -> void:
	_wounded.clear()
	var radius := maxf(d.splash_radius, 0.5)
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D) or not z.has_method("take_hit"):
			continue
		var c: Vector3 = (z as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
		var dist := c.distance_to(at)
		if dist > radius + 0.6 and z != struck:
			continue
		var k := 1.0 if z == struck else clampf(1.0 - dist / (radius + 0.6), 0.25, 1.0)
		var dir := (c - at).normalized() if dist > 0.05 else Vector3.UP
		_hurt(z, "torso", d.damage * k, dir, d, false, c)
		if is_instance_valid(z) and z.has_method("knock"):
			z.knock(Vector3(dir.x, 0.6, dir.z).normalized() * 9.0 * k)
	_pay_hits()
	# Too close to your own rocket hurts.
	if player != null and d.self_damage > 0.0:
		var pd := (player.global_position + Vector3(0.0, 0.9, 0.0)).distance_to(at)
		if pd < radius:
			ZombieMode.player_hit(d.self_damage * (1.0 - pd / radius), at)
	if feel != null:
		var pd2 := player.global_position.distance_to(at) if player != null else 30.0
		feel.add_trauma(clampf(1.0 - pd2 / 28.0, 0.15, 0.9))
	exploded.emit(at, radius)

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
