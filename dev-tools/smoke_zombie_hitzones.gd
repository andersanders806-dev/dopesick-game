extends "res://dev-tools/smoke_test_3d.gd"
## The dead's hit zones, every body: rays over the silhouette (front, side, across the shoulders) find no gap.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_hitzones.gd
func _run() -> void:
	await _section("Dead Block: hit zones of every body")
	var gs := _gs()
	_close_menus()
	var zm := root.get_node("ZombieMode")
	zm.begin()
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	var holder: Node = _player().get_node("WeaponHolder")
	holder.give(load("res://weapons/pistol.tres"))
	holder.no_spread = true
	var ZS: GDScript = load("res://npc/Zombie3D.gd")
	var core := []
	var off := -0.04
	while off <= 0.0401:
		core.append(off)
		off += 0.02
	var shoulders := []
	off = -0.16
	while off <= 0.1601:
		shoulders.append(off)
		off += 0.02
	for bname in ZS.BODIES:
		var zb: Node = await _zw_target(city, -20.0, -3.0, 4.0, 1, bname)
		var hs := []
		var yy: float = _zw_part_at(zb, "torso").y - 0.2
		var yh: float = _zw_part_at(zb, "head").y
		while yy <= yh + 0.05:
			hs.append(yy)
			yy += 0.02
		var yn: float = _zw_part_at(zb, "neck").y
		var g1: Array = _zw_gaps(holder, zb, hs, core, true)
		var g2: Array = _zw_gaps(holder, zb, hs, core, false)
		var g3: Array = _zw_gaps(holder, zb, hs.filter(func(h): return h <= yn - 0.06), shoulders, true)
		_check(g1.is_empty() and g2.is_empty() and g3.is_empty(), "  %s: front %s side %s shoulders %s" % [bname, g1.slice(0, 6), g2.slice(0, 6), g3.slice(0, 6)])
		zb.queue_free()
		await _frames(2)
	zm.leave()
