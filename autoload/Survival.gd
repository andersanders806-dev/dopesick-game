extends Node
## The body, kept alive -- the survival layer under the addiction, after
## The Long Dark's Condition (one health bar fed by every need), Project
## Zomboid's moodles and bleeding, and Don't Starve's hunger clock.
##
## Four needs run down with game time (GameState.clock_changed); any of
## them empty, or a wound left open, and health drains. Health at 0 ends the
## run ("health", RunEndScreen says what did it). Fed, warm, rested and not
## bleeding, it comes back slowly.
##
## - Hunger: about a day from full. The shelter's plates, the vending
##   machine on the block (world/VendingMachine3D.gd), the backyard dumpster.
## - Warmth: outside at night and in the rain it bleeds away -- slower in
##   your winter coat, if you haven't pawned it. Any room warms you up.
## - Rest: about twenty hours awake; any bed, cot or mattress fills it.
## - Bleeding: a beating opens you up. Bandages (vending machine) close it;
##   left alone it clots after BLEED_HOURS.

signal changed

const MAX := 100.0
# Per game hour (a game hour is 15 s real time).
const HUNGER_PER_H := 4.0
const REST_PER_H := 5.0
const COLD_NIGHT_PER_H := 12.0
const COLD_RAIN_PER_H := 10.0
const COAT_FACTOR := 0.6
const WARM_INSIDE_PER_H := 30.0
const WARM_DAY_PER_H := 6.0
const WARM_DAY_CAP := 80.0
## What empty needs cost in health an hour.
const STARVING_DMG := 6.0
const FREEZING_DMG := 10.0
const EXHAUSTED_DMG := 4.0
const BLEEDING_DMG := 8.0
const DOPESICK_DMG := 2.0
const REGEN_PER_H := 2.5
const BLEED_HOURS := 8.0
## Below these a need starts to show (HUD, a toast).
const LOW := 25.0
const OUTSIDE_SCENES := ["City3D", "Backyard3D"]

var health := MAX
var hunger := 70.0
var warmth := 90.0
var rest := 80.0
var bleeding := false
var bleed_until := -1.0
## What's hurting most right now: "starved", "froze", "exhausted", "bled",
## "sick" -- the run-end screen names it.
var last_cause := ""
var dead := false
## Off, nothing changes (the smoke tests jump the clock days at a time).
var enabled := true
var _last_min := -1.0
var _warned := {}

func _ready() -> void:
	GameState.clock_changed.connect(_on_clock)

func reset() -> void:
	health = MAX
	hunger = 70.0
	warmth = 90.0
	rest = 80.0
	bleeding = false
	bleed_until = -1.0
	last_cause = ""
	dead = false
	_warned = {}
	_last_min = GameState.now_minutes()
	changed.emit()

func _on_clock(_minute: int) -> void:
	var now := GameState.now_minutes()
	var prev := _last_min
	_last_min = now
	# A first tick, a new run, or a jump nobody accounted for: just resync.
	if prev < 0.0 or now - prev <= 0.0 or now - prev > 24 * 60:
		return
	tick(now - prev)

## Where you are decides the cold.
func outside() -> bool:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return false
	return scene.scene_file_path.get_file().get_basename() in OUTSIDE_SCENES

func wearing_coat() -> bool:
	return GameState.belongings.get("coat", "home") in ["home", "carried"]

func night() -> bool:
	return GameState.daylight() < 0.3

## Advances the body by `minutes` of waking time.
func tick(minutes: float, is_outside := outside()) -> void:
	if dead or GameState.in_custody or not enabled:
		_last_min = GameState.now_minutes()
		return
	var h := minutes / 60.0
	hunger = maxf(0.0, hunger - HUNGER_PER_H * h)
	rest = maxf(0.0, rest - REST_PER_H * h)
	if is_outside:
		var hl := get_node_or_null("/root/Headlines")
		var cold := (COLD_NIGHT_PER_H if night() else 0.0) + (COLD_RAIN_PER_H if GameState.raining else 0.0)
		if hl:
			cold = cold * hl.cold_mult() + hl.day_cold()
		if cold > 0.0:
			warmth = maxf(0.0, warmth - cold * (COAT_FACTOR if wearing_coat() else 1.0) * h)
		elif warmth < WARM_DAY_CAP:
			warmth = minf(WARM_DAY_CAP, warmth + WARM_DAY_PER_H * h)
	else:
		warmth = minf(MAX, warmth + WARM_INSIDE_PER_H * h)
	if bleeding and GameState.now_minutes() >= bleed_until:
		bleeding = false
		_toast("The bleeding's stopped on its own.")
	_apply_health(h)
	_warn()
	changed.emit()

func _apply_health(h: float) -> void:
	var dmg := 0.0
	var worst := 0.0
	var cause := ""
	for c in [["starved", STARVING_DMG if hunger <= 0.0 else 0.0], ["froze", FREEZING_DMG if warmth <= 0.0 else 0.0],
			["exhausted", EXHAUSTED_DMG if rest <= 0.0 else 0.0], ["bled", BLEEDING_DMG if bleeding else 0.0],
			["sick", DOPESICK_DMG if GameState.sickness() >= 0.99 else 0.0]]:
		dmg += c[1]
		if c[1] > worst:
			worst = c[1]
			cause = c[0]
	if dmg > 0.0:
		health = maxf(0.0, health - dmg * h)
		last_cause = cause
	elif hunger > LOW and warmth > LOW and rest > 15.0:
		health = minf(MAX, health + REGEN_PER_H * h)
	if health <= 0.0 and not dead:
		die()

func die() -> void:
	dead = true
	health = 0.0
	changed.emit()
	var line: String = {"starved": "Days without a real meal. The body stops asking.",
		"froze": "A night outside with nothing between you and the cold.",
		"exhausted": "Too long without sleep. You sat down and didn't get up.",
		"bled": "The cut never closed. Nobody looked twice.",
		"sick": "The sickness went on too long, with nothing to stop it."}.get(last_cause, "Your body gave out.")
	GameState.log_event(line, "overdose_floor")
	GameState.end_run("health")

# --- What helps ---------------------------------------------------------------

func eat(amount: float, what := "") -> void:
	hunger = minf(MAX, hunger + amount)
	_warned.erase("hunger")
	if what != "":
		GameState.log_event("Ate %s." % what)
	changed.emit()

func warm(amount: float) -> void:
	warmth = minf(MAX, warmth + amount)
	changed.emit()

func refresh(amount: float) -> void:
	rest = minf(MAX, rest + amount)
	changed.emit()

func hurt(damage: float, bleed := true) -> void:
	if not enabled:
		return
	health = maxf(0.0, health - damage)
	if bleed:
		bleeding = true
		bleed_until = GameState.now_minutes() + BLEED_HOURS * 60.0
		_toast("You're bleeding. Bandages -- the vending machine on the block has them.")
	changed.emit()
	if health <= 0.0 and not dead:
		last_cause = "bled"
		die()

func bandage() -> void:
	bleeding = false
	health = minf(MAX, health + 8.0)
	changed.emit()

## A night's sleep (GameState.sleep): rested, a little hungrier, and the
## body mends if it was fed. `outside` is the backyard mattress.
func on_sleep(slept_minutes: float, is_outside := outside()) -> void:
	if not enabled:
		return
	var h := slept_minutes / 60.0
	rest = MAX
	hunger = maxf(0.0, hunger - HUNGER_PER_H * 0.5 * h)
	if is_outside:
		warmth = maxf(0.0, warmth - COLD_NIGHT_PER_H * 0.5 * (COAT_FACTOR if wearing_coat() else 1.0) * h)
	else:
		warmth = MAX
	if bleeding and GameState.now_minutes() >= bleed_until:
		bleeding = false
	if hunger > LOW and warmth > LOW and not bleeding:
		health = minf(MAX, health + REGEN_PER_H * 1.5 * h)
	else:
		_apply_health(h * 0.5)
	_last_min = GameState.now_minutes()
	_warned = {}
	changed.emit()

## The HUD's short list of what's wrong, worst first.
func warnings() -> Array:
	var out := []
	if bleeding:
		out.append("BLEEDING")
	if hunger <= 0.0:
		out.append("STARVING")
	elif hunger < LOW:
		out.append("HUNGRY")
	if warmth <= 0.0:
		out.append("FREEZING")
	elif warmth < LOW:
		out.append("COLD")
	if rest <= 0.0:
		out.append("EXHAUSTED")
	elif rest < LOW:
		out.append("TIRED")
	return out

func _warn() -> void:
	for w in [["hunger", hunger < LOW, "You're hungry. The shelter feeds people at 7 and 17; the vending machine's on the block."],
			["warmth", warmth < LOW, "You're getting cold. Get inside somewhere."],
			["rest", rest < LOW, "You're dead on your feet. Find a bed."]]:
		if w[1] and not _warned.get(w[0], false):
			_warned[w[0]] = true
			_toast(w[2])
		elif not w[1]:
			_warned.erase(w[0])

func _toast(text: String) -> void:
	if is_inside_tree() and has_node("/root/Graphics"):
		get_node("/root/Graphics")._show_toast(text, 4.0)
