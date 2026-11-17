extends "res://world/Purchase.gd"
## A gun on the wall, drawn in chalk on a board: press E to buy it for its
## price; once you carry it (in either version), the same board sells its ammo
## at half price. Placed by world/ZombieBlock.gd against the block's walls.
##
## The board faces +Z of this node; the wall is behind it.

const GunModel := preload("res://weapons/GunModel.gd")
const BOARD := Vector2(1.7, 1.05)
const CHALK := Color(0.92, 0.9, 0.82, 0.8)

var data: WD

func setup(weapon: WD) -> void:
	data = weapon
	name = "WallBuy_" + weapon.id
	set_meta("kind", "WallBuy")
	_make_zone(Vector3(2.2, 1.8, 1.8), Vector3(0, 0.9, 0.9))
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(BOARD.x, BOARD.y, 0.05)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.07, 0.075)
	mat.roughness = 0.95
	board.material_override = mat
	board.position = Vector3(0, 1.45, 0.03)
	add_child(board)
	var gun := GunModel.build(weapon)
	gun.name = "Chalk"
	# Drawn as big as the board takes: 1.25 m long, or 0.78 m high for a stubby one (a pistol).
	var b := GunModel.bounds(gun, gun)
	var k := minf(1.25 / maxf(weapon.model_length, 0.1), 0.78 / maxf(b.size.y, 0.05))
	# A long thin weapon (the bat, the machete) would be a bar in a big black board: drawn longer, tilted across it.
	var thin: bool = b.size.y < 0.22 * maxf(weapon.model_length, 0.1)
	if thin:
		k = 1.45 / maxf(weapon.model_length, 0.1)
	gun.scale = Vector3(0.03, 1.0, 1.0) * k
	gun.rotation_degrees = Vector3(0, -90, 0)
	gun.position = Vector3(0.1, 1.45, 0.07)
	var tilt: Node3D = null
	if thin:
		# The pivot carries the tilt about the board's own axis, the gun inside it in its place.
		tilt = Node3D.new()
		tilt.name = "ChalkTilt"
		tilt.position = Vector3(0.0, 1.45, 0.0)
		tilt.rotation_degrees = Vector3(0, 0, 28)
		gun.position = Vector3(0.0, 0.0, 0.07)
	var chalk := StandardMaterial3D.new()
	chalk.albedo_color = CHALK
	chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chalk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = chalk
		m.material_overlay = null
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tilt != null:
		add_child(tilt)
		tilt.add_child(gun)
	else:
		add_child(gun)
	label = _make_label("%s\n%d" % [weapon.display_name.to_upper(), weapon.price], Vector3(0, 0.78, 0.08), 0.0042)
	var spot := OmniLight3D.new()
	spot.light_color = Color(1.0, 0.9, 0.7)
	spot.light_energy = 0.5
	spot.omni_range = 3.0
	spot.shadow_enabled = false
	spot.position = Vector3(0, 1.6, 0.9)
	add_child(spot)

## What E would do now (the prompt).
func prompt_text() -> String:
	var h := holder_of(get_tree().get_first_node_in_group("player"))
	if data.melee:
		if h != null and h.has_method("has_melee") and h.has_melee(data.family()):
			return "You carry the %s" % h.melee_data.display_name
		if h != null and h.get("melee_data") != null and h.melee_data.upgraded:
			return "Keep your %s" % h.melee_data.display_name
		return "Buy the %s  [%d]" % [data.display_name, data.price]
	if h != null and h.has_weapon(data.family()):
		var held: WD = h.slot_data(h.slot_of(data.family()))
		return "Refill the %s  [%d]" % [held.display_name, held.ammo_price]
	return "Buy the %s  [%d]" % [data.display_name, data.price]

func interact(player: Node) -> void:
	try_buy(holder_of(player))

## "bought", "ammo" (a refill of a gun you carry), "poor", "full" (nothing to
## refill: nothing is charged) or "none".
func try_buy(holder: Node) -> String:
	if holder == null:
		return _result("none")
	# A melee weapon takes the knife's place (there is no ammo to refill).
	if data.melee:
		if holder.has_melee(data.family()):
			return _result("full", "You carry it")
		# An upgraded weapon (5000 points at the machine) is not thrown away for a plain one off the wall.
		if holder.melee_data != null and holder.melee_data.upgraded:
			return _result("full", "Keep your %s" % holder.melee_data.display_name)
		if not _pay(data.price):
			return _result("poor")
		holder.give_melee(data)
		return _result("bought")
	var i: int = holder.slot_of(data.family())
	if i >= 0:
		var held: WD = holder.slot_data(i)
		var s: Dictionary = holder.slots[i]
		if s.mag >= held.mag_size and s.reserve >= held.reserve_max:
			return _result("full", "Ammo full")
		if not _pay(held.ammo_price):
			return _result("poor")
		# (A round in the chamber stays where it is.)
		s.mag = maxi(int(s.mag), held.mag_size)
		s.reserve = held.reserve_max
		holder.ammo_changed.emit()
		return _result("ammo")
	if not _pay(data.price):
		return _result("poor")
	holder.give(data)
	return _result("bought")
