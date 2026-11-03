extends "res://world/Purchase.gd"
## Armour plates on the wall (Ghetto Wars), wall-buy style: a board with a plate drawn on it. E puts a plate on
## (PLATE_PRICE points), up to three; each soaks 50 damage before your health is touched. They do not come back
## by themselves. Placed by world/GangBlock.gd against the block's walls.

const PLATE_PRICE := 600
const BOARD := Vector2(1.5, 1.05)
const CHALK := Color(0.92, 0.9, 0.82, 0.85)

func setup() -> void:
	name = "ArmorBuy"
	set_meta("kind", "ArmorBuy")
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
	# A plate in chalk: a rounded slab with the carrier's straps.
	var chalk := StandardMaterial3D.new()
	chalk.albedo_color = CHALK
	chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chalk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for part in [[Vector3(0.5, 0.62, 0.012), Vector3(0, 1.5, 0.07)], [Vector3(0.62, 0.05, 0.012), Vector3(0, 1.78, 0.07)], [Vector3(0.62, 0.05, 0.012), Vector3(0, 1.22, 0.07)]]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		m.mesh = b
		m.material_override = chalk
		m.position = part[1]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
	label = _make_label("ARMOUR PLATE\n%d" % PLATE_PRICE, Vector3(0, 0.78, 0.08), 0.0042)
	var spot := OmniLight3D.new()
	spot.light_color = Color(1.0, 0.9, 0.7)
	spot.light_energy = 0.5
	spot.omni_range = 3.0
	spot.shadow_enabled = false
	spot.position = Vector3(0, 1.6, 0.9)
	add_child(spot)

func prompt_text() -> String:
	if ZombieMode.plates() >= ZombieMode.MAX_PLATES:
		return "Armour full  (%d plates)" % ZombieMode.plates()
	return "Armour plate  [%d]  (%d / %d)" % [PLATE_PRICE, ZombieMode.plates(), ZombieMode.MAX_PLATES]

func interact(_player: Node) -> void:
	try_buy()

## "bought", "poor" or "full".
func try_buy() -> String:
	if ZombieMode.plates() >= ZombieMode.MAX_PLATES:
		return _result("full", "Armour full")
	if not _pay(PLATE_PRICE):
		return _result("poor")
	ZombieMode.add_plate()
	SFX.play("latch", -2.0, 1.4)
	return _result("bought")
