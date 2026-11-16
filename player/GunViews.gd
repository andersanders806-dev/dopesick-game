extends RefCounted
## The first-person tables of a gun that differs from its handling family's (SHIP 16 B2): where the hands go, the
## sight picture, the moving parts of its model (the magazine, the slide, the charging handle, a break-action's
## barrels, the RPG's rocket, the M249's feed cover), the muzzle and the shell port, and how it is carried.
## player/Viewmodel.gd and player/GunHandling.gd look a gun up here by its base id first, then fall back to the
## family's own tables. Points are metres in the gun's space as weapons/GunModel.gd builds it (-Z the muzzle, the
## pivot at the grip), read off dev-tools/bench_models.gd; fractions are of the gun's box as in Viewmodel.
##
## Keys (all optional):
##   hands     Viewmodel.HANDS row          anchors  Viewmodel.ANCHORS row (the magwell is the real magazine's
##                                                  middle when the model has one)
##   sights    Viewmodel.SIGHTS row (zones) sight_pts [front, rear]: the sights' tops, measured
##   rail      where a red dot's base sits   relief   metres from the eye to the rear sight / the dot
##   parts     kind -> [name fragments]: "mag" (follows the hand in a reload), "slide" (back with each shot),
##             "carrier" (the bolt carrier and its handle, back with each shot), "charge" (a charging handle the
##             empty reload pulls), "barrels" (a break-action's, turns on `hinge`), "shells" (in the breech),
##             "rocket" (the round in a launcher's muzzle)
##   bones     kind -> bone name of a rigged model ("mag", "cover", "charge")
##   hinge     [pivot, axis]: what "barrels" turns about
##   muzzle    the muzzle's point            eject    Viewmodel/GunHandling eject profile (a whole EJECT row)
##   hip / sprint / cant   GunHandling HIP / SPRINT / CANTS rows   weight   GunHandling WEIGHT
##   carrier_back / slide_back   metres the part goes back with a shot

const VIEW := {
	"glock": {
		"sight_pts": [Vector3(0.001, 0.0705, -0.124), Vector3(0.001, 0.0705, 0.024)],
		"parts": {"slide": ["glockslide"], "mag": ["glockmag"]},
		"muzzle": Vector3(0.002, 0.057, -0.137),
		"slide_back": 0.024,
	},
	"deagle": {
		"sight_pts": [Vector3(0.0, 0.0795, -0.173), Vector3(0.0, 0.079, 0.03)],
		"parts": {"slide": ["group001/"], "mag": ["_magazine_0"]},
		"muzzle": Vector3(0.0, 0.051, -0.185),
		"slide_back": 0.03,
		"hands": [Vector3(0.5, 0.3, 0.24), Vector3(-0.9, 0.1, 0.26), 0.0, 0.0, 1.0, 1.0, "pistol_r", "pistol_l", 0.86],
	},
	"tec9": {
		"sights": [0.0, 0.1, 0.72, 0.95, 0.3, false, 0.0],
		"parts": {"mag": ["mag/mag_main"]},
		"hands": [Vector3(0.5, 0.25, 0.3), Vector3(0.5, 0.2, 0.56), 0.0, 0.0, 1.0, 1.0, "pistol_r", "vert_l", 0.92],
		"hip": [Vector3(0.12, -0.15, -0.34), Vector3(0.0, 2.0, 0.0)],
	},
	"uzi": {
		"sights": [0.0, 0.08, 0.6, 0.68, 0.24, false, 0.0],
		"parts": {"mag": ["clip/"], "charge": ["/slide/"]},
		"hands": [Vector3(0.5, 0.29, 0.4), Vector3(0.5, 0.45, 0.8), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
	},
	"mp5": {
		# The model's own reflex sight on its claw mount: the eye looks down its tube (the glass cut away), the dot in it.
		# (Measured: the sight's body is y 0.132..0.164, x +-0.018, z -0.24..-0.16, on a rail at 0.124.)
		"sights": [0.02, 0.12, 0.5, 0.62, 0.14, false, 0.0],
		"sight_pts": [Vector3(0.0, 0.1485, -0.24), Vector3(0.0, 0.1485, -0.16)],
		"hole": [Vector3(-0.0135, 0.1365, -0.25), Vector3(0.0135, 0.1605, -0.15)],
		"dot": Vector3(0.0, 0.1485, -0.21),
		"hands": [Vector3(0.5, 0.25, 0.38), Vector3(-0.3, 0.55, 0.7), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
	},
	"vector": {
		"sights": [0.25, 0.55, 0.52, 0.0, 0.14, true, 0.0],
		"parts": {"mag": ["mag_low"], "charge": ["slider_low"]},
		"hands": [Vector3(0.5, 0.35, 0.42), Vector3(0.5, 0.3, 0.72), 0.0, 0.0, 1.0, 1.0, "rifle_r", "vert_l", 1.0],
	},
	"ak": {
		"sight_pts": [Vector3(-0.009, 0.129, -0.579), Vector3(-0.009, 0.128, -0.215)],
		"relief": 0.34,
		"parts": {"mag": ["magazine_low"], "carrier": ["slide_low"]},
		"muzzle": Vector3(-0.009, 0.078, -0.6),
		# (Hands measured on the model: the pistol grip at 0.33 from the back, the C-grip on the wooden handguard.)
		"hands": [Vector3(0.5, 0.42, 0.33), Vector3(-0.35, 0.66, 0.7), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
		"carrier_back": 0.07,
	},
	"m16": {
		"sight_pts": [Vector3(-0.001, 0.1235, -0.482), Vector3(-0.001, 0.115, -0.004)],
		"relief": 0.11,
		"parts": {"mag": ["magazine_3"], "charge": ["charging_handle_16"]},
		"muzzle": Vector3(-0.001, 0.056, -0.674),
		"hands": [Vector3(0.5, 0.36, 0.29), Vector3(-0.35, 0.68, 0.72), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
	},
	"sawnoff": {
		# HenRi's double barrel (the alt pick: the "extremely" sawn-off's 10 cm barrels hide behind its own grip in first
		# person). Barrels and forend are one part that drops on the hinge pin; the two shells sit in its chambers.
		"sight_pts": [Vector3(0.0, 0.044, -0.268), Vector3(0.0, 0.044, -0.045)],
		"parts": {"barrels": ["cube_009"], "shells": ["bullet1", "bullet2"]},
		"hinge": [Vector3(0.0, -0.004, -0.045), Vector3(1.0, 0.0, 0.0)],
		# (Held out at arm's length when aimed, the hand low on the grip with the thumb along the frame, the rib clear.)
		"hands": [Vector3(0.5, 0.1, 0.09), Vector3(0.5, 0.42, 0.65), 0.0, 0.0, 1.0, 1.0, "pistol_r", "pump_l", 0.95],
	},
	"aa12": {
		"sights": [0.0, 0.12, 0.62, 0.76, 0.2, false, 0.0],
		"parts": {"mag": ["drum mag empty_12"], "charge": ["reload handle_10"], "carrier": ["bolt carrier_6"]},
		"carrier_back": 0.05,
		"eject": {"port": Vector3(1.0, 0.7, 0.55), "lo": Vector3(1.2, 1.4, 0.2), "hi": Vector3(2.0, 2.4, 0.8), "spin": 24.0, "size": Vector2(0.0105, 0.07), "kind": 1},
		# (The drum makes the box wide: the hands are placed on the gun's middle, not the box's edge.)
		"hands": [Vector3(0.5, 0.36, 0.31), Vector3(0.5, 0.42, 0.6), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
	},
	"dmr": {
		"sights": [0.0, 0.06, 0.58, 0.7, 0.12, false, 0.0],
	},
	"amr": {
		"sights": [0.3, 0.4, 0.72, 0.8, 0.2, false, 0.0],
		"parts": {"mag": ["empty mag_2"], "carrier": ["bolt carrier_4", "barrel_5"]},
		"muzzle": Vector3(-0.018, 0.033, -0.987),
		"carrier_back": 0.03,
		"eject": {"port": Vector3(1.0, 0.75, 0.62), "lo": Vector3(1.4, 1.4, 0.3), "hi": Vector3(2.2, 2.2, 1.0), "spin": 20.0, "size": Vector2(0.0075, 0.1), "kind": 0},
		"weight": 1.7,
		# The .50 is long: the support hand holds the front of the receiver, and the gun rides higher to show it.
		"hands": [Vector3(0.5, 0.21, 0.22), Vector3(0.5, 0.34, 0.47), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
		"hip": [Vector3(0.19, -0.155, -0.27), Vector3(0.0, 5.0, 0.0)],
		# Its rail is the receiver's top (y 0.088); the scope sits over the magazine well.
		"scope": Vector3(-0.018, 0.088, -0.02),
		"relief": 0.09,
	},
	"saw": {
		"sights": [0.45, 0.62, 0.55, 0.0, 0.17, true, 0.0],
		"hands": [Vector3(0.5, 0.37, 0.3), Vector3(0.45, 0.5, 0.64), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
		"bones": {"mag": "Magazine_06", "charge": "Cocking_Handle_07"},
	},
	"rpg": {
		# The RPG-7's sights stand on the left of the tube: the tube rides low and right of the picture. Its rocket is the
		# "magazine": gone once fired, carried in by the hand and pushed into the muzzle.
		"sights": [0.0, 0.25, 0.45, 0.6, 0.22, false, 0.0],
		"sight_pts": [Vector3(-0.065, 0.075, -0.3), Vector3(-0.065, 0.075, -0.05)],
		"parts": {"mag": ["pcylinder8"]},
		"muzzle": Vector3(-0.02, 0.0, -0.66),
		"hands": [Vector3(0.34, 0.13, 0.52), Vector3(0.5, 0.13, 0.6), 0.0, 0.0, 1.0, 1.0, "rifle_r", "vert_l", 1.0],
		"weight": 1.5,
	},
	# Melee: both hands choked up on the bat's handle; the machete in the right hand alone.
	"bat": {"hands": [Vector3(0.5, 0.5, 0.05), Vector3(0.5, 0.5, 0.16), 0.0, 0.0, 1.0, 1.0, "pump_l", "pump_l", 1.0]},
	"machete": {"hands": [Vector3(0.5, 0.45, 0.1), Vector3(0.5, 0.45, 0.1), 0.0, 0.0, 1.0, 1.0, "pump_l", "pump_l", 1.0]},
}

## The table of `d`'s gun ({} if it has none): looked up by its base id, so an upgraded gun has its plain one's.
static func of(d: Resource) -> Dictionary:
	if d == null:
		return {}
	var key := String(d.get("base_id"))
	if key == "":
		key = String(d.get("id"))
	return VIEW.get(key, {})

## `key` of `d`'s table, or `fallback`.
static func pick(d: Resource, key: String, fallback: Variant) -> Variant:
	var v := of(d)
	return v[key] if v.has(key) else fallback
