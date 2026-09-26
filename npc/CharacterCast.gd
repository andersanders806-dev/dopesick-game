extends RefCounted
## Who wears which body, and in what colours. One source of truth for the
## whole cast, so nobody in the game hardcodes a model path.
##
## The bodies are Quaternius' CC0 human models (assets/quaternius/characters,
## see LICENSE.txt there), which replaced Kenney's Mini Characters. The Mini
## Characters are chibi -- roughly four heads tall, with a flat colour atlas
## and no facial geometry -- so at the ~11 m the camera sits back they read
## as coloured lumps rather than people. These are eight-heads-tall adults at
## real scale: the male bodies come out 1.75 m and the female 1.68 m once the
## scenes' existing 1.5x ModelRoot scale is applied (the .fbx files import at
## nodes/root_scale=0.2411 to land there).
##
## Eight downloaded bodies cover a cast of about twenty because each model
## splits into named surfaces -- Skin, Hair, Shirt, Pants, Shoes -- that
## CharacterLook recolours independently. Two people in the same body with
## different hair, skin, and clothes don't read as the same person at
## gameplay distance.
##
## Palette note: everything here is deliberately desaturated and dark. The
## game is lit by sodium streetlights, a bare bulb, and beer signs, and a
## saturated colour on a character reads as a costume against that.

const DIR := "res://assets/quaternius/characters/"

const MALE_CASUAL := DIR + "Smooth_Male_Casual.fbx"
const MALE_LONGSLEEVE := DIR + "Smooth_Male_LongSleeve.fbx"
const MALE_SHIRT := DIR + "Smooth_Male_Shirt.fbx"
const MALE_SUIT := DIR + "Smooth_Male_Suit.fbx"
const FEMALE_CASUAL := DIR + "Smooth_Female_Casual.fbx"
const FEMALE_ALT := DIR + "Smooth_Female_Alternative.fbx"
const FEMALE_DRESS := DIR + "Smooth_Female_Dress.fbx"
const FEMALE_TANKTOP := DIR + "Smooth_Female_TankTop.fbx"

## role -> {model, look}. `look` is passed straight to CharacterLook.apply(),
## so its keys are surface names ("Shirt", "Pants", "Hair", "Skin", "Shoes")
## plus the special "clothes" catch-all.
const CAST := {
	"player": {
		"model": MALE_CASUAL,
		"look": {"Shirt": Color(0.42, 0.45, 0.40), "Pants": Color(0.30, 0.33, 0.42), "Hair": Color(0.28, 0.22, 0.18)},
	},
	# Modelled on how street-level sellers are described in policing guides:
	# an ordinary guy in a grey hoodie, not a movie villain.
	"pusher": {
		"model": MALE_CASUAL,
		"look": {"Shirt": Color(0.34, 0.34, 0.36), "Pants": Color(0.22, 0.22, 0.25), "Hair": Color(0.16, 0.14, 0.13)},
	},
	"lookout": {
		"model": MALE_LONGSLEEVE,
		"look": {"Shirt": Color(0.45, 0.22, 0.20), "Pants": Color(0.26, 0.27, 0.30), "Hair": Color(0.20, 0.17, 0.15)},
	},
	"bartender": {
		"model": MALE_SHIRT,
		"look": {"Shirt": Color(0.78, 0.76, 0.72), "Pants": Color(0.18, 0.18, 0.20), "Hair": Color(0.35, 0.33, 0.31)},
	},
	# Navy shirt over navy trousers reads as a uniform at distance without
	# needing a uniform model.
	"police": {
		"model": MALE_SHIRT,
		"look": {"Shirt": Color(0.20, 0.26, 0.44), "Pants": Color(0.16, 0.19, 0.30), "Hair": Color(0.22, 0.19, 0.16)},
	},
	"booking_officer": {
		"model": MALE_LONGSLEEVE,
		"look": {"Shirt": Color(0.24, 0.30, 0.48), "Pants": Color(0.16, 0.19, 0.30), "Hair": Color(0.45, 0.44, 0.42)},
	},
	# One clerk per store, each a different body/colour so you can tell at a
	# glance which shop you walked into.
	"clerk_convenience": {
		"model": MALE_SHIRT,
		"look": {"Shirt": Color(0.52, 0.48, 0.30), "Pants": Color(0.25, 0.25, 0.27), "Hair": Color(0.15, 0.13, 0.12)},
	},
	# The pharmacy has two people: a front cashier and the pharmacist on the
	# raised back counter, so they need to look like different staff.
	"clerk_pharmacy_cashier": {
		"model": FEMALE_ALT,
		"look": {"Shirt": Color(0.42, 0.46, 0.52), "Pants": Color(0.24, 0.25, 0.28), "Hair": Color(0.18, 0.15, 0.13)},
	},
	"clerk_pharmacy": {
		"model": MALE_LONGSLEEVE,
		"look": {"Shirt": Color(0.80, 0.82, 0.84), "Pants": Color(0.30, 0.32, 0.38), "Hair": Color(0.40, 0.38, 0.36)},
	},
	"clerk_supermarket": {
		"model": FEMALE_CASUAL,
		"look": {"Shirt": Color(0.30, 0.42, 0.34), "Pants": Color(0.24, 0.24, 0.28), "Hair": Color(0.32, 0.20, 0.13)},
	},
	"clerk_liquor": {
		"model": MALE_CASUAL,
		"look": {"Shirt": Color(0.38, 0.26, 0.24), "Pants": Color(0.22, 0.22, 0.24), "Hair": Color(0.14, 0.12, 0.11)},
	},
	"clerk_electronics": {
		"model": MALE_SHIRT,
		"look": {"Shirt": Color(0.26, 0.34, 0.46), "Pants": Color(0.20, 0.20, 0.22), "Hair": Color(0.25, 0.21, 0.17)},
	},
	# The electronics store's door guard: the one person in the game dressed
	# to be noticed.
	"security_guard": {
		"model": MALE_SUIT,
		"look": {"Shirt": Color(0.16, 0.16, 0.18), "Pants": Color(0.14, 0.14, 0.16), "Hair": Color(0.12, 0.11, 0.10)},
	},
}

## Dive Bar regulars. Keyed by the same names as NPC3D.PATRON_PROFILES and
## the portraits in assets/portraits, so a patron's body, their portrait, and
## the sounds they make all describe one person. Bodies used to be dealt out
## at random per visit, which meant Big Eddie could come back as somebody
## else entirely; tying the look to the name keeps a regular recognisable.
## The looks lean on the same research as the portraits -- the gaunt restless
## opioid users, the glazed benzo users, the flushed heavy drinkers.
const PATRONS := {
	"Wiry Guy": {
		"model": MALE_LONGSLEEVE,
		"look": {"Shirt": Color(0.36, 0.38, 0.33), "Pants": Color(0.24, 0.25, 0.28), "Hair": Color(0.18, 0.15, 0.13), "Skin": Color(0.88, 0.86, 0.82)},
	},
	"Tired Woman": {
		"model": FEMALE_CASUAL,
		"look": {"Shirt": Color(0.40, 0.32, 0.40), "Pants": Color(0.22, 0.22, 0.26), "Hair": Color(0.30, 0.24, 0.20), "Skin": Color(0.90, 0.87, 0.84)},
	},
	"Big Eddie": {
		"model": MALE_CASUAL,
		"look": {"Shirt": Color(0.46, 0.30, 0.26), "Pants": Color(0.28, 0.28, 0.30), "Hair": Color(0.36, 0.30, 0.24), "Skin": Color(1.05, 0.92, 0.88)},
	},
	"Quiet Kid": {
		"model": FEMALE_TANKTOP,
		"look": {"Shirt": Color(0.30, 0.33, 0.40), "Pants": Color(0.20, 0.21, 0.25), "Hair": Color(0.14, 0.13, 0.12), "Skin": Color(0.92, 0.90, 0.88)},
	},
	"Old Sailor": {
		"model": MALE_SHIRT,
		"look": {"Shirt": Color(0.34, 0.40, 0.48), "Pants": Color(0.26, 0.26, 0.28), "Hair": Color(0.62, 0.61, 0.58), "Skin": Color(1.08, 0.90, 0.86)},
	},
	"Nervous Dave": {
		"model": MALE_CASUAL,
		"look": {"Shirt": Color(0.44, 0.42, 0.36), "Pants": Color(0.23, 0.24, 0.27), "Hair": Color(0.22, 0.18, 0.15), "Skin": Color(0.87, 0.86, 0.83)},
	},
	"Newcomer": {
		"model": FEMALE_ALT,
		"look": {"Shirt": Color(0.36, 0.34, 0.38), "Pants": Color(0.22, 0.23, 0.26), "Hair": Color(0.26, 0.20, 0.16)},
	},
}

static func entry(role: String) -> Dictionary:
	if CAST.has(role):
		return CAST[role]
	if PATRONS.has(role):
		return PATRONS[role]
	return CAST["player"]

static func model_for(role: String) -> String:
	return entry(role)["model"]

static func look_for(role: String) -> Dictionary:
	return entry(role)["look"]

## Applies a role's colours to an already-instanced model.
static func dress(model: Node, role: String) -> void:
	preload("res://npc/CharacterLook.gd").apply(model, look_for(role))
