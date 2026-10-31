extends Node
## The pad's rumble for Dead Block, from the WeaponHolder's own signals (it is that node's child):
## a pulse per shot shaped by the gun (a pistol is a tap, a shotgun a slam, the LMG a steady
## thrum because every round of it is one), a short one for a hit, a firmer one for a kill, a hard
## one for taking a claw, one for the knife and a click when a reload starts and finishes. Settings >
## Rumble turns it all off.
##
## Godot can start the two motors (Input.start_joy_vibration) but cannot reach the DualSense's adaptive
## triggers or its haptic actuators: the trigger resistance and the finer feel of a real PS5 game are
## not here, and nothing pretends to be.
##
## Pulses asked for in the same frame are merged (the loudest of each motor, the longest), because the
## engine keeps only the last one started, and a hit would otherwise cancel the shot it came from.
## vibrate() is the one place the engine is called; `calls` keeps what went out, for the tests.

## [weak (the small, high motor), strong (the big, low one), seconds] per gun family.
const SHOT := {
	"pistol": [0.30, 0.35, 0.09], "smg": [0.30, 0.22, 0.06], "ar": [0.35, 0.40, 0.07],
	"shotgun": [0.55, 1.00, 0.24], "lmg": [0.40, 0.45, 0.08], "sniper": [0.40, 0.90, 0.22],
	"magnum": [0.45, 0.80, 0.16], "wonder": [0.65, 0.70, 0.12],
}
const SHOT_DEFAULT := [0.3, 0.4, 0.08]
const HIT := [0.45, 0.0, 0.04]
const HEADSHOT := [0.6, 0.15, 0.06]
const KILL := [0.7, 0.35, 0.10]
const MELEE_HIT := [0.5, 0.75, 0.14]
const MELEE_MISS := [0.15, 0.2, 0.06]
const RELOAD_START := [0.3, 0.0, 0.05]
const RELOAD_END := [0.2, 0.55, 0.07]
const DRY := [0.1, 0.0, 0.03]
## Aimed down the sights the shot is this much gentler.
const ADS_SOFTEN := 0.8
## A claw: the damage taken scales it between these.
const DAMAGE_MIN := 0.45
const DAMAGE_REF := 45.0

## Every pulse that went out: {weak, strong, duration, why}. Tests read and clear it.
static var calls: Array = []
## Tests: called with (weak, strong, duration) instead of the engine.
static var sink := Callable()

var holder: Node
var _want := {}

func _init() -> void:
	name = "PadRumble"

func _ready() -> void:
	holder = get_parent()
	holder.connect("fired", _on_fired)
	holder.connect("hit", _on_hit)
	holder.connect("melee_swung", _on_melee)
	holder.connect("reload_started", func(): ask(RELOAD_START, "reload"))
	holder.connect("reload_finished", func(): ask(RELOAD_END, "reload_done"))
	holder.connect("dry_fired", func(): ask(DRY, "dry"))
	get_tree().node_added.connect(_watch)
	for z in get_tree().get_nodes_in_group("zombies"):
		_watch(z)

## Wants a pulse [weak, strong, seconds] this frame.
func ask(p: Array, why := "") -> void:
	if not Graphics.rumble:
		return
	if _want.is_empty():
		_want = {"weak": 0.0, "strong": 0.0, "duration": 0.0, "why": why}
	elif not String(_want["why"]).split("+").has(why):
		_want["why"] = "%s+%s" % [_want["why"], why]
	_want["weak"] = maxf(_want["weak"], p[0])
	_want["strong"] = maxf(_want["strong"], p[1])
	_want["duration"] = maxf(_want["duration"], p[2])

func _process(_delta: float) -> void:
	flush()

## Sends what was asked for this frame.
func flush() -> void:
	if _want.is_empty():
		return
	var w := _want
	_want = {}
	vibrate(w["weak"], w["strong"], w["duration"], w["why"])

## The one call to the engine: every pad that is connected, both motors.
static func vibrate(weak: float, strong: float, duration: float, why := "") -> void:
	calls.append({"weak": weak, "strong": strong, "duration": duration, "why": why})
	if sink.is_valid():
		sink.call(weak, strong, duration)
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)

## The pulse for one shot of `data`.
static func shot_pulse(data: Resource, aiming: bool) -> Array:
	var base: Array = SHOT.get(data.family(), SHOT_DEFAULT)
	var k := ADS_SOFTEN if aiming else 1.0
	return [base[0] * k, base[1] * k, base[2]]

func _on_fired() -> void:
	var d = holder.get("current")
	if d != null:
		ask(shot_pulse(d, holder.get("aiming") == true), "shot")

func _on_hit(part: String, killed: bool) -> void:
	ask(KILL if killed else (HEADSHOT if part == "head" else HIT), "kill" if killed else "hit")

func _on_melee(found: bool) -> void:
	ask(MELEE_HIT if found else MELEE_MISS, "melee")

## A zombie that can claw (npc/Zombie3D.gd emits `attacked`) is listened to.
func _watch(n: Node) -> void:
	if n.has_signal("attacked") and not n.is_connected("attacked", _on_attacked):
		n.connect("attacked", _on_attacked)

func _on_attacked(z: Node, damage: float) -> void:
	var t = z.get("target")
	if t is Node and (t as Node).is_in_group("player"):
		damaged(damage)

## The player took `amount` of damage.
func damaged(amount: float) -> void:
	var k := clampf(DAMAGE_MIN + amount / DAMAGE_REF * (1.0 - DAMAGE_MIN), DAMAGE_MIN, 1.0)
	ask([0.4 * k, 1.0 * k, 0.28], "damage")
