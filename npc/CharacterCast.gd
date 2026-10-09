extends RefCounted
## Who wears which body. One source of truth for the whole cast, so nobody
## in the game hardcodes a model path.
##
## The people are Microsoft Rocketbox avatars (MIT licence,
## github.com/microsoft/Microsoft-Rocketbox; see assets/rocketbox/LICENSE.md):
## 115 realistic, textured, fully rigged adults -- real faces, hair, hands
## and clothes with folds -- made over ten years for research and VR. They
## replaced Quaternius' CC0 low-poly humans, which had the right proportions
## but no textures and very simple faces. dev-tools/fetch_rocketbox.py
## downloads and converts the ones cast here, with the game's clips (idle,
## walk, sprint, sit, and a sick walk and nervous idle for withdrawal) baked
## onto each one's own skeleton.
##
## Each person is a different avatar, so nobody needs recolouring to look
## like somebody else; `look` only carries an optional "tint" over the whole
## body (Ray's grime). Real-size in the scenes' 1.5x ModelRoot: the .glb files
## import at nodes/root_scale=0.6667.

const DIR := "res://assets/rocketbox/"

## role -> {model, look}.
const CAST := {
	# A brown hoodie and jeans: someone you'd walk past.
	"player": {"model": DIR + "Male_Adult_20.glb", "look": {}},
	# Modelled on how street-level sellers are described in policing guides:
	# an ordinary guy in a grey hoodie, not a movie villain.
	"pusher": {"model": DIR + "Male_Adult_18.glb", "look": {}},
	# Tasha, the rival booster: dark, plain, nothing a guard remembers.
	"booster": {"model": DIR + "Female_Adult_12.glb", "look": {}},
	"lookout": {"model": DIR + "Male_Adult_17.glb", "look": {}},
	"bartender": {"model": DIR + "Business_Male_07.glb", "look": {}},
	"police": {"model": DIR + "Police_Male_03.glb", "look": {}},
	"booking_officer": {"model": DIR + "Police_Male_01.glb", "look": {}},
	"clerk_convenience": {"model": DIR + "Male_Adult_09.glb", "look": {}},
	"clerk_pharmacy_cashier": {"model": DIR + "Medical_Female_01.glb", "look": {}},
	"clerk_pharmacy": {"model": DIR + "Medical_Male_01.glb", "look": {}},
	"clerk_supermarket": {"model": DIR + "Female_Adult_08.glb", "look": {}},
	"clerk_liquor": {"model": DIR + "Male_Adult_14.glb", "look": {}},
	"clerk_electronics": {"model": DIR + "Male_Adult_11.glb", "look": {}},
	"collector": {"model": DIR + "Business_Male_04.glb", "look": {}},
	"volunteer": {"model": DIR + "Female_Adult_02.glb", "look": {}},
	"outreach_worker": {"model": DIR + "Female_Adult_14.glb", "look": {}},
	"mia": {"model": DIR + "Female_Adult_01.glb", "look": {}},
	"shelter_diner_a": {"model": DIR + "Male_Adult_05.glb", "look": {}},
	"shelter_diner_b": {"model": DIR + "Female_Adult_09.glb", "look": {}},
	"shelter_diner_c": {"model": DIR + "Male_Adult_04.glb", "look": {}},
	"clerk_music": {"model": DIR + "Male_Adult_12.glb", "look": {}},
	"pawnbroker": {"model": DIR + "Male_Adult_03.glb", "look": {}},
	"kart_marshal": {"model": DIR + "Female_Adult_05.glb", "look": {}},
	"stocker_supermarket": {"model": DIR + "Male_Adult_16.glb", "look": {}},
	"assistant_pharmacy": {"model": DIR + "Medical_Female_02.glb", "look": {}},
	"sales_electronics": {"model": DIR + "Female_Adult_04.glb", "look": {}},
	"security_guard": {"model": DIR + "Security_Male_01.glb", "look": {}},
	# The smoker outside the liquor store, on a break that runs long.
	"smoker": {"model": DIR + "Construction_Male_08.glb", "look": {}},
}

## Dive Bar regulars. Keyed by the same names as NPC3D.PATRON_PROFILES and
## the portraits in assets/portraits, so a patron's body, their portrait, and
## the sounds they make all describe one person.
const PATRONS := {
	"Wiry Guy": {"model": DIR + "Male_Adult_10.glb", "look": {}},
	"Tired Woman": {"model": DIR + "Female_Adult_07.glb", "look": {}},
	"Big Eddie": {"model": DIR + "Male_Adult_13.glb", "look": {}},
	"Quiet Kid": {"model": DIR + "Female_Adult_03.glb", "look": {}},
	"Old Sailor": {"model": DIR + "Wood_Male_01.glb", "look": {}},
	"Nervous Dave": {"model": DIR + "Male_Adult_08.glb", "look": {}},
	"Newcomer": {"model": DIR + "Female_Adult_13.glb", "look": {}},
}

## People walking the block (npc/Pedestrian3D.gd): nobody in particular,
## so they're dealt from this pool rather than cast by name. Office
## clothes and everyday clothes.
const PASSERSBY := [
	{"model": DIR + "Business_Male_02.glb", "look": {}},
	{"model": DIR + "Business_Female_01.glb", "look": {}},
	{"model": DIR + "Male_Adult_06.glb", "look": {}},
	{"model": DIR + "Female_Adult_01.glb", "look": {}},
	{"model": DIR + "Male_Adult_01.glb", "look": {}},
	{"model": DIR + "Business_Female_02.glb", "look": {}},
	{"model": DIR + "Male_Adult_02.glb", "look": {}},
	{"model": DIR + "Business_Female_03.glb", "look": {}},
]

## Who sits by the alley with his cart (npc/Homeless3D.gd): an older man in
## work clothes, greyed and grimed.
const HOMELESS := {"model": DIR + "Gardener_Male_01.glb", "look": {"tint": Color(0.78, 0.74, 0.68)}}

static func entry(role: String) -> Dictionary:
	if CAST.has(role):
		return CAST[role]
	if PATRONS.has(role):
		return PATRONS[role]
	if role == "homeless":
		return HOMELESS
	return CAST["player"]

static func model_for(role: String) -> String:
	return entry(role)["model"]

## Character models stay loaded for the session: otherwise every room
## change frees them with the old room and reads them off disk again (most
## of a second for the street's extras).
static var _scenes := {}

static func scene_for(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

static func look_for(role: String) -> Dictionary:
	return entry(role)["look"]

## Applies a role's look to an already-instanced model. `model` can also be
## a container (Player3D, Police3D and Collector3D's $Model) whose scene
## has a body built in: if that body isn't the role's, it's swapped for it,
## so this file stays the one place that says who wears what.
static func dress(model: Node, role: String) -> void:
	var want := model_for(role)
	var body := model
	if model.scene_file_path != want:
		for c in model.get_children():
			if c.scene_file_path != "" and c.find_child("AnimationPlayer", true, false):
				body = c
				if c.scene_file_path != want:
					var fresh: Node3D = scene_for(want).instantiate()
					fresh.name = c.name
					fresh.transform = (c as Node3D).transform
					model.remove_child(c)
					c.queue_free()
					model.add_child(fresh)
					body = fresh
				break
	preload("res://npc/CharacterLook.gd").apply(body, look_for(role))
