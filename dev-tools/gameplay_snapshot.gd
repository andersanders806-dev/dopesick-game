extends SceneTree
## Records where everything gameplay touches sits in a set of rooms -- doors,
## zones, spawn points, colliders, people -- so a pure art pass can prove it
## moved none of it (smoke_test_3d.gd's _world_art_2_checks compares).
##   godot --headless --path . -s res://dev-tools/gameplay_snapshot.gd
const ROOMS := ["Jail3D", "Pawn3D", "Shelter3D", "MusicStore3D", "KartCenter3D", "Backyard3D"]
const OUT := "res://dev-tools/world_art2_baseline.json"

static func snapshot(room: Node) -> Dictionary:
	var out := {}
	for n in room.find_children("*", "", true, false):
		var keep: bool = n is Area3D or n is Marker3D or n is CharacterBody3D or (n is CollisionShape3D and not (n.get_parent() is Area3D))
		if not keep or not (n is Node3D):
			continue
		var path := String(room.get_path_to(n))
		# Stores shuffle their shelves between fixed layouts each visit.
		var shuffled: bool = not (room.get("fixture_layouts") as Array if room.get("fixture_layouts") != null else []).is_empty()
		if shuffled and (path.begins_with("Fixture") or path.begins_with("Item")):
			continue
		var e := {"pos": _v(_in_room(room, n).origin)}
		if n is CollisionShape3D and n.shape:
			e["shape"] = _shape(n.shape)
		out[path] = e
	return out

## Its transform relative to the room, from the local transforms up the
## chain -- works before the tree has computed any global ones.
static func _in_room(room: Node, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != room:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

static func _shape(s: Shape3D) -> Array:
	if s is BoxShape3D:
		return _v(s.size)
	if s is CylinderShape3D:
		return [snappedf(s.radius, 0.01), snappedf(s.height, 0.01)]
	if s is CapsuleShape3D:
		return [snappedf(s.radius, 0.01), snappedf(s.height, 0.01)]
	return []

func _initialize() -> void:
	var all := {}
	for r in ROOMS:
		var room: Node = load("res://world/%s.tscn" % r).instantiate()
		root.add_child(room)
		all[r] = snapshot(room)
		room.free()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(all, "\t"))
	print("wrote %s (%s)" % [OUT, ", ".join(ROOMS.map(func(r): return "%s %d" % [r, all[r].size()]))])
	quit()
