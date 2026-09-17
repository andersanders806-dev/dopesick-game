extends "res://world/WorldRoot3D.gd"
## Any store you can steal from. Each store scene (built by
## dev-tools/build_rooms_3d.gd) sets which items it stocks and a few possible
## fixture layouts; this picks a layout, shuffles the stock onto the
## fixtures, and calls the police when a guard spots a theft.

## Which store this is ("pharmacy", ...), matching GameState.REQUEST_POOL.
@export var store_id: String = ""
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
	var i := 1
	while has_node("Fixture%d" % i):
		fixtures.append(get_node("Fixture%d" % i))
		item_slots.append(get_node("Item%d" % i))
		i += 1
	_randomize_layout()
	super._ready()
	for guard in get_tree().get_nodes_in_group("guards"):
		if is_ancestor_of(guard):
			guard.spotted_theft.connect(_on_spotted_theft)
	_shuffle_items()

func _randomize_layout() -> void:
	if fixture_layouts.is_empty():
		_place_items()
		return
	var layout: PackedVector2Array = fixture_layouts.pick_random()
	for i in range(mini(fixtures.size(), layout.size())):
		fixtures[i].position = Vector3(layout[i].x, 0.0, layout[i].y)
	_place_items()

## Each fixture carries its item offset as metadata, since a low glass case
## and a tall shelf hold their stock at different heights.
func _place_items() -> void:
	for i in range(fixtures.size()):
		var offset: Vector3 = fixtures[i].get_meta("item_offset", Vector3(0, 0.45, 0.5))
		item_slots[i].position = fixtures[i].position + offset

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

func _on_spotted_theft() -> void:
	if GameState.wanted or GameState.in_custody:
		return
	GameState.set_wanted(true)
	var tree := get_tree()
	var room := self
	tree.create_timer(POLICE_RESPONSE_TIME).timeout.connect(func():
		# Only if we're still in this store and nobody's already on it.
		if not is_instance_valid(room) or tree.current_scene != room:
			return
		if not GameState.wanted or GameState.in_custody or tree.get_first_node_in_group("police"):
			return
		var police := PoliceScene.instantiate()
		room.add_child(police)
		police.global_position = room.police_spawn.global_position
	)
