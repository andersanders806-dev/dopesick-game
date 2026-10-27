extends "res://world/Purchase.gd"
## The upgrade machine: 5000 points turn the gun in your hands into its
## upgraded self (more damage, bigger mag and reserve, a glow over it), full
## of ammo. A gun that has no upgrade, or already is one, is refused and
## costs nothing.

const PRICE := 5000
const GLOW := Color(0.35, 1.0, 0.55)

var _light: OmniLight3D
var _flash := 0.0

func _ready() -> void:
	name = "UpgradeMachine"
	set_meta("kind", "UpgradeMachine")
	_make_zone(Vector3(2.0, 2.2, 1.8), Vector3(0, 1.1, 0.4))
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.13, 0.14, 0.15)
	steel.metallic = 0.7
	steel.roughness = 0.5
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.45, 0.05, 0.05)
	red.roughness = 0.6
	var glow := StandardMaterial3D.new()
	glow.albedo_color = GLOW
	glow.emission_enabled = true
	glow.emission = GLOW
	glow.emission_energy_multiplier = 3.0
	_box(Vector3(1.1, 2.1, 0.8), Vector3(0, 1.05, 0), steel)
	_box(Vector3(1.2, 0.18, 0.9), Vector3(0, 2.16, 0), red)
	_box(Vector3(1.2, 0.18, 0.9), Vector3(0, 0.09, 0), red)
	_box(Vector3(0.8, 0.12, 0.05), Vector3(0, 1.3, 0.41), glow)
	_box(Vector3(0.5, 0.5, 0.05), Vector3(0, 1.8, 0.41), glow)
	label = _make_label("UPGRADE\n%d" % PRICE, Vector3(0, 0.62, 0.43), 0.0045, Color(0.7, 1.0, 0.8))
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.light_energy = 1.2
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.5, 1.0)
	add_child(_light)

func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	add_child(mi)

func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_light.light_energy = 1.2 + _flash * 6.0 + 0.2 * sin(Time.get_ticks_msec() * 0.004)

func prompt_text() -> String:
	var h := holder_of(get_tree().get_first_node_in_group("player"))
	var cur: WD = h.current if h != null else null
	if cur == null:
		return "Nothing to upgrade"
	if cur.upgraded:
		return "The %s is already upgraded" % cur.display_name
	if cur.upgrade == null:
		return "The %s can't be upgraded" % cur.display_name
	return "Upgrade the %s  [%d]" % [cur.display_name, PRICE]

func interact(player: Node) -> void:
	try_upgrade(holder_of(player))

## "upgraded", "poor", "already" (it is one already), "none" (nothing to upgrade).
func try_upgrade(holder: Node) -> String:
	if holder == null or holder.current == null:
		return _result("none", "Nothing to upgrade")
	if holder.current.upgraded:
		return _result("already", "Already upgraded")
	if holder.current.upgrade == null:
		return _result("none", "Nothing to upgrade")
	if not _pay(PRICE):
		return _result("poor")
	holder.upgrade_current()
	_flash = 1.0
	return _result("upgraded", "Upgraded")
