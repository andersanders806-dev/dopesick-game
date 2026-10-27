extends Area3D
## What the wall guns, the box and the upgrade machine have in common: a "press
## E" zone the player's InteractZone picks up (layer 4, group "interactable"),
## a price shown on a Label3D, the player's WeaponHolder, and a word to the
## HUD when it didn't go through.
##
## Prices are paid with ZombieMode.try_spend(): exactly enough is enough, one
## short pays nothing, and no power-up changes a price.

const WD := preload("res://weapons/WeaponData.gd")
const PAPER := Color(0.93, 0.9, 0.82)

## What the last attempt came to ("bought", "poor", ...): the tests read it.
var last_result := ""
var label: Label3D

func _init() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	add_to_group("interactable")

func _make_zone(size: Vector3, at := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	add_child(cs)

func _make_label(text: String, at: Vector3, size := 0.0035, color := PAPER) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.pixel_size = size
	l.font_size = 64
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l

static func holder_of(player: Node) -> Node:
	if player == null:
		return null
	var h := player.get_node_or_null("WeaponHolder")
	if h == null:
		h = player.get_tree().get_first_node_in_group("weapon_holder")
	return h

## A line on the HUD ("Not enough points").
func say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("zombie_hud")
	if hud != null and hud.has_method("say"):
		hud.call("say", text)

func _result(r: String, message := "") -> String:
	last_result = r
	if message != "":
		say(message)
	return r

## Pays `price`; false (and a word) if you can't.
func _pay(price: int) -> bool:
	if ZombieMode.try_spend(price):
		SFX.play("cash", 0.0)
		return true
	SFX.play("latch", -6.0, 0.8)
	say("Not enough points")
	return false
