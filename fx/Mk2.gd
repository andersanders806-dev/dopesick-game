extends RefCounted
## The Mk 2 "pineapple" frag (LonesomeDucky, CC0): GrenadeBody > GrenadeTop > [GrenadePin > GrenadeRing, GrenadeSwitch].
## Real size (7 cm x 11 cm). The player's viewmodel pulls the pin and ring off it and lets the spoon fly; the crews'
## grenade (fx/GangGrenade.gd) and the thrown one (fx/FragGrenade.gd) are this model whole or without its spoon.

const MODEL := "res://assets/models/grenade/mk2_grenade.glb"
## Half the body's height: the middle of the model sits this far below its origin's top, so a rolling one rests on its side.
const RADIUS := 0.036

static var _scene: PackedScene

## A fresh copy of the model (the scene is kept; nothing is read from disk after the first).
static func build() -> Node3D:
	if _scene == null:
		_scene = load(MODEL) as PackedScene
	var root := _scene.instantiate() as Node3D
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

static func part(root: Node, name_: String) -> Node3D:
	return root.find_child(name_, true, false) as Node3D

## Loads the model now (the title's and the level's warm-up).
static func warm() -> void:
	if _scene == null:
		_scene = load(MODEL) as PackedScene
