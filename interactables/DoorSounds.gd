extends RefCounted
## The sounds of a door (assets/sfx/doors/, CC0 Freesound cuts -- see CREDITS.txt there, and
## Kenney's door and latch from assets/sfx/kenney/), by what they are. HingedDoor3D layers
## them: handle, bell, hinge creak, latch, slam, rattle, steel scrape.

const D := "res://assets/sfx/doors/"
const K := "res://assets/sfx/kenney/"

const SETS := {
	"handle": [preload(D + "handle.ogg")],
	"door_open": [preload(K + "door_open_1.ogg"), preload(K + "door_open_2.ogg")],
	"bell": [preload(D + "bell.ogg")],
	"latch": [preload(D + "latch.ogg"), preload(K + "latch.ogg")],
	"slam_light": [preload(D + "slam_light.ogg"), preload(D + "slam_wood_c.ogg")],
	"slam_wood": [preload(D + "slam_wood_a.ogg"), preload(D + "slam_wood_b.ogg"), preload(D + "slam_wood_c.ogg")],
	"slam_heavy": [preload(D + "slam_heavy.ogg")],
	"steel_slam": [preload(D + "steel_slam_a.ogg"), preload(D + "steel_slam_b.ogg")],
	"steel_slam_b": [preload(D + "steel_slam_b.ogg")],
	"steel_bar": [preload(D + "steel_bar.ogg")],
	"wood_close": [preload(D + "wood_close.ogg")],
	"stop": [preload(D + "wood_close.ogg"), preload(D + "slam_light.ogg")],
	"rattle": [preload(D + "rattle_a.ogg"), preload(D + "rattle_b.ogg"), preload(D + "rattle_c.ogg")],
	"glass_rattle": [preload(D + "rattle_c.ogg")],
	"scrape": [preload(D + "scrape_a.ogg"), preload(D + "scrape_b.ogg")],
}

## Hinge creaks: a voice per door, heavier ones for the heavy doors.
const CREAKS := {
	"shop_glass": [preload(D + "creak_c.ogg"), preload(D + "creak_d.ogg"), preload(D + "creak_b.ogg"), preload(D + "creak_c.ogg")],
	"steel_back": [preload(D + "creak_d.ogg"), preload(D + "scrape_b.ogg"), preload(D + "creak_a.ogg"), preload(D + "creak_b.ogg")],
	"bar": [preload(D + "creak_a.ogg"), preload(D + "creak_b.ogg"), preload(D + "creak_a.ogg"), preload(D + "creak_c.ogg")],
}
## Per voice: level (dB) and pitch, so two doors of one kind don't squeak the same.
const CREAK_GAIN := [0.0, -2.0, 1.0, -1.0]
const CREAK_PITCH := [1.0, 0.9, 1.08, 0.96]

static func pick(key: String) -> AudioStream:
	var a: Array = SETS.get(key, [])
	return a.pick_random() if not a.is_empty() else null

static func creak_for(kind: String, voice: int) -> AudioStream:
	var a: Array = CREAKS.get(kind, CREAKS["shop_glass"])
	return a[voice % a.size()]
