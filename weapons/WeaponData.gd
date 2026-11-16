extends Resource
## One gun, as data: what it does to each part of a zombie, how fast it
## shoots and reloads, what it costs on the wall, what it looks like, and the
## upgraded version the upgrade machine turns it into. The .tres files in
## weapons/ are generated from dev-tools/gen_weapons.py.
##
## Damage is per pellet/bullet at the part's multiplier. Zombie3D.take_hit()
## takes the final damage, so WeaponHolder multiplies here, not there.

@export var id := ""
@export var display_name := ""
## The id of the gun this one is a version of ("" for a base gun). The wall
## and the box think in base ids: you can't be handed a gun you carry in
## either version.
@export var base_id := ""
@export var upgraded := false
@export var melee := false

@export_group("Damage")
@export var damage := 20.0
@export var head_mult := 2.0
@export var neck_mult := 1.5
@export var torso_mult := 1.0
@export var limb_mult := 0.75
@export var pellets := 1
## Full damage out to falloff_start metres, then down to `falloff_floor` of
## it at falloff_end (a shotgun's reach).
@export var falloff_start := 60.0
@export var falloff_end := 150.0
@export var falloff_floor := 0.6
## Zombies this close to where the shot landed take half (the wonder weapon).
@export var splash_radius := 0.0

@export_group("Handling")
@export var rpm := 400.0
@export var auto := false
@export var mag_size := 10
@export var reserve_max := 60
## Seconds of a tactical reload (a round still in the gun).
@export var reload_time := 1.8
## Seconds of an empty reload (bolt or slide forward on a new magazine). 0: reload_time + 0.7.
@export var reload_time_empty := 0.0
## A tactical reload leaves one in the chamber (mag_size + 1).
@export var chambers := false
## Degrees of cone, hip and aimed down the sights.
@export var spread_hip := 2.0
@export var spread_ads := 0.4
## Degrees the view kicks per shot (what the visual kick and the pad scale with).
@export var recoil := 1.0
@export var ads_zoom := 1.4
@export var swap_time := 0.4
## Seconds from hip to sights.
@export var ads_time := 0.3
## Seconds after a sprint ends before the trigger answers.
@export var sprint_fire_delay := 0.2
## The family the animations, sights, shell port and rumble are cut for ("pistol",
## "smg", "ar", "shotgun", "sniper", "magnum", "lmg", "wonder"); "" is this gun's own family.
@export var handling := ""

@export_group("Fire mode")
## More than 1: one pull fires this many rounds at the gun's rpm.
@export var burst_count := 0
## The pause after a burst before the trigger answers again.
@export var burst_delay := 0.18

@export_group("Recoil")
## One entry per shot of a burst: x degrees to the right, y degrees up. After the last
## entry the final eight repeat. Empty: a plain climb of `recoil`.
@export var recoil_pattern := PackedVector2Array()
## How fast the view comes home once the trigger lets go (per second), and while it is held.
@export var recoil_recover := 17.0
@export var recoil_hold := 3.0
## Multiples of the kick: the first shot after a rest, and aimed down the sights.
@export var recoil_first := 1.0
@export var recoil_ads := 0.75
## +- this share of every kick is random.
@export var recoil_random := 0.1
## What the gun does in the hands per shot: metres back, degrees up, and the roll (radians, +-).
## 0: worked out from `recoil`.
@export var kick_back := 0.0
@export var kick_up := 0.0
@export var kick_roll := 0.0

@export_group("Optic")
## "none" (iron sights), "red_dot" or "scope".
@export_enum("none", "red_dot", "scope") var optic := "none"
## The zoom through the optic (0: ads_zoom).
@export var optic_zoom := 0.0

@export_group("Sound")
## The folder in assets/sfx/guns/ with this gun's recordings (fire_N, fire_up_N, distant_N,
## tail_indoor, tail_outdoor, mech_N, dry). "": the synthesised fire_<family>_a/b.
@export var sound_set := ""
## Reload and handling cue -> sound files (stems under assets/sfx/guns/; several: one is picked).
## A cue not listed plays assets/sfx/guns/<cue>.wav.
@export var foley := {}
## [[fraction of the reload, cue], ...] for a tactical and for an empty reload. A cue named
## here replaces the one the gun's animation would have made at its own time.
@export var reload_cues_tactical := []
@export var reload_cues_empty := []

@export_group("Economy")
## What the wall asks for the gun (0: not on a wall).
@export var price := 0
## What the wall asks for a refill (half the gun, or what the upgrade says).
@export var ammo_price := 0
@export var in_box := true
@export var wonder := false
@export var upgrade: Resource

@export_group("Look")
@export_file("*.gltf", "*.glb") var model := ""
## Turn that points the model's barrel down -Z (degrees about Y).
@export var model_yaw := 0.0
## Metres from the back of the gun to the muzzle in the hand.
@export var model_length := 0.6
## Parts of the model to leave out (a loose spare magazine, a bullet).
@export var model_hide := PackedStringArray()
## The upgraded look: a glow over the whole gun.
@export var tint := Color(0, 0, 0, 0)

func interval() -> float:
	return 60.0 / maxf(rpm, 1.0)

## The part a hitbox names: "head", "neck", "torso", "upper_arm_l", ...
## (anything else counts as the body).
func multiplier(part: String) -> float:
	if part == "head":
		return head_mult
	if part == "neck":
		return neck_mult
	if part.contains("arm") or part.contains("leg"):
		return limb_mult
	return torso_mult

## What one bullet does to `part` from `dist` metres away.
func damage_at(part: String, dist := 0.0) -> float:
	var k := 1.0
	if dist > falloff_start:
		k = lerpf(1.0, falloff_floor, clampf((dist - falloff_start) / maxf(falloff_end - falloff_start, 0.01), 0.0, 1.0))
	return damage * multiplier(part) * k

## "pistol" for both the pistol and its upgrade.
func family() -> String:
	return base_id if base_id != "" else id

## The family the animation tables are cut for.
func handling_family() -> String:
	return handling if handling != "" else family()

## "semi", "auto" or "burst".
func fire_mode() -> String:
	if burst_count > 1:
		return "burst"
	return "auto" if auto else "semi"

## Seconds of the reload for a gun that is `empty` or not.
func reload_for(empty: bool) -> float:
	if not empty:
		return reload_time
	return reload_time_empty if reload_time_empty > 0.0 else reload_time + 0.7

## Rounds a tactical reload can leave in the gun.
func mag_cap(tactical: bool) -> int:
	return mag_size + (1 if chambers and tactical else 0)

## The zoom the sights give (the optic's own, or the gun's).
func sight_zoom() -> float:
	return optic_zoom if optic_zoom > 0.0 else ads_zoom

## The kick of shot number `i` (0 = the first of a burst): [right degrees, up degrees], before the multipliers.
func kick_of(i: int) -> Vector2:
	var n := recoil_pattern.size()
	if n == 0:
		return Vector2(0.0, recoil * 0.45)
	if i >= n:
		var cycle := mini(8, n)
		i = n - cycle + (i - n) % cycle
	return recoil_pattern[i]
