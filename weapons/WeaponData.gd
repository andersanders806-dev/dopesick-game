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
@export var reload_time := 1.8
## Degrees of cone, hip and aimed down the sights.
@export var spread_hip := 2.0
@export var spread_ads := 0.4
## Degrees the view kicks per shot.
@export var recoil := 1.0
@export var ads_zoom := 1.4
@export var swap_time := 0.4

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
