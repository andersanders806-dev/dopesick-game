extends "res://world/WorldRoot3D.gd"
## Any store you can steal from. Each store scene (built by
## dev-tools/build_rooms_3d.gd) sets which items it stocks and a few possible
## fixture layouts; this picks a layout, shuffles the stock onto the
## fixtures, and calls the police when a guard spots a theft.

## Which store this is ("pharmacy", ...), matching GameState.REQUEST_POOL.
@export var store_id: String = ""
## How long after grabbing something you still look like you're stealing
## (stuffing it under your jacket): the window a guard has to notice. Tuned
## per store with dev-tools/balance_sim.gd.
@export var theft_window: float = 1.0
## One item id per fixture, in any order -- shuffled each visit.
@export var item_ids: Array[String] = []
## Each entry is one layout: a PackedVector2Array of (x, z) floor positions,
## index-matched to the Fixture1..N nodes.
@export var fixture_layouts: Array = []

## Cops don't materialise at the door the instant the alarm goes up; the
## siren starts right away, but an officer takes a moment to arrive.
const POLICE_RESPONSE_TIME := 2.0

@onready var police_spawn: Marker3D = $PoliceSpawn

var fixtures: Array[Node3D] = []
var item_slots: Array[Node3D] = []

func _ready() -> void:
	_setup_store()
	super._ready()
	_wire_guards()
	_shuffle_items()

## What a store is, whatever it hangs from: its fixtures and goods, a layout
## for this visit. A walk-in shop (world/WalkInShop.gd) is a part of the
## street's scene rather than a scene of its own, and runs this without
## WorldRoot3D's room set-up.
func _setup_store() -> void:
	var i := 1
	while has_node("Fixture%d" % i):
		fixtures.append(get_node("Fixture%d" % i))
		item_slots.append(get_node("Item%d" % i))
		i += 1
	_randomize_layout()

func _wire_guards() -> void:
	for guard in get_tree().get_nodes_in_group("guards"):
		if is_ancestor_of(guard):
			guard.spotted_theft.connect(_on_spotted_theft)

## A layout is a PackedVector2Array of (x, z) floor spots, or, for fixtures
## that stand against a wall and face the aisle, a PackedVector3Array of
## (x, z, yaw in degrees).
func _randomize_layout() -> void:
	if fixture_layouts.is_empty():
		_place_items()
		return
	var layout: Variant = fixture_layouts.pick_random()
	for i in range(mini(fixtures.size(), layout.size())):
		fixtures[i].position = Vector3(layout[i].x, 0.0, layout[i].y)
		if layout is PackedVector3Array:
			fixtures[i].rotation_degrees.y = layout[i].z
	_place_items()

## Each fixture carries its item offset as metadata, since a low glass case
## and a tall shelf hold their stock at different heights.
func _place_items() -> void:
	for i in range(fixtures.size()):
		var offset: Vector3 = fixtures[i].get_meta("item_offset", Vector3(0, 0.45, 0.5))
		# Turned with the fixture, so a shelf on the side wall holds its goods
		# on the aisle side.
		item_slots[i].position = fixtures[i].position + fixtures[i].basis * offset
		item_slots[i].theft_window = theft_window

## Fixtures with a "stock" meta list (e.g. the supermarket's meat cooler)
## only ever hold those items; the rest share `item_ids`, shuffled.
func _shuffle_items() -> void:
	var ids := item_ids.duplicate()
	ids.shuffle()
	var next := 0
	for i in range(item_slots.size()):
		var stock: Array = fixtures[i].get_meta("stock", [])
		if not stock.is_empty():
			item_slots[i].set_item_id(stock.pick_random())
		else:
			item_slots[i].set_item_id(ids[next % ids.size()])
			next += 1
	_ensure_every_item_stocked()

## Patrons' orders stick until delivered, so an order must never point at a
## store that happens not to have that item on its shelves this visit. Any
## catalogue item for this store that the shuffle left out replaces a
## duplicate on a fixture allowed to hold it.
func _ensure_every_item_stocked() -> void:
	var required := GameState.REQUEST_POOL.filter(func(r): return r["store"] == store_id).map(func(r): return r["id"])
	var order := range(item_slots.size())
	order.shuffle()
	for id in required:
		if item_slots.any(func(slot): return slot.item_id == id):
			continue
		for i in order:
			var current: String = item_slots[i].item_id
			var copies := item_slots.filter(func(slot): return slot.item_id == current).size()
			var stock: Array = fixtures[i].get_meta("stock", [])
			if copies > 1 and (stock.is_empty() or id in stock):
				item_slots[i].set_item_id(id)
				break

## Is this still the place the theft happened? The street's scene is the one
## you're in for as long as you play it; a room of its own is left behind by
## walking out of its door.
func _still_here() -> bool:
	return get_tree().current_scene == self

## Where the officer is put in the world.
func _police_parent() -> Node:
	return self

func _on_spotted_theft() -> void:
	if GameState.wanted or GameState.in_custody:
		return
	GameState.set_wanted(true)
	var tree := get_tree()
	var room := self
	tree.create_timer(POLICE_RESPONSE_TIME).timeout.connect(func():
		# Only if we're still in this store and nobody's already on it.
		if not is_instance_valid(room) or not room._still_here():
			return
		if not GameState.wanted or GameState.in_custody or tree.get_first_node_in_group("police"):
			return
		var police := PoliceScene.instantiate()
		room._police_parent().add_child(police)
		police.global_position = room.police_spawn.global_position
	)
