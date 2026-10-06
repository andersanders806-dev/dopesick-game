# Batch 2: The Street Gets Dangerous Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An overdose in the alley you can answer (or not), a bad batch with test strips, and Tasha, a rival booster.

**Architecture:** Rules and state go in `autoload/GameState.gd` (new sections: "Bad batch", "The alley", "Tasha"). Events are driven by batch 1's `_on_new_day` and a new hourly hook, so they happen whether or not you're on the block. Presentation goes in two new City children, `world/AlleyOverdose.gd` and `world/Booster.gd`, built in code like `StreetScenes.gd`. Small changes go in `Headlines`, `Outreach3D`, `Pusher3D`, `DiveBar3D`, `CharacterAnimator`, `CharacterCast` and `Notebook`.

**Tech Stack:** Godot 4.7 (flatpak), GDScript, the headless smoke test.

**Spec:** `docs/superpowers/specs/2026-10-06-batch2-street-gets-dangerous-design.md`

## Global Constraints

- `GODOT` = `flatpak run org.godotengine.Godot`. Never run two Godot test processes at once (they share `user://` and hang).
- Test loop: `.superpowers/sdd/<plan>/t.sh smoke_batch2`, which also fails on any `SCRIPT ERROR`.
- OD roll 25% (100% on bad batch), never day 1. Window `OD_WINDOW = 90.0` real seconds, on the block only. Naloxone `rep +3`, payphone `rep +2`, pockets `$8-20`, walk away = 2/3 die.
- `BAD_BATCH_CHANCE = 0.4`, contaminated OD risk ×3. Strips: 2 per outreach visit, once a day.
- Vigil: the day after a death, pusher prices ×0.9.
- Booster: 40% of days, 10-20, never day 1 or a vigil day. A hit is `set_store_heat(store, 1.3, 1)`. Team up is ×0.6 on one store and half the next order. Rat out: gone for the run, clears her heat and your warrant, Ray's trust → 0, `rep -1` to each living regular.
- House style: tabs, `##` comments that say why, the game's voice in player text. Commit per task with the Claude Opus 5.5 trailer.

## Review Focus

1. **Running out of regulars.** The bar has 3 seats and 6 names. If 4 die, `_new_patron`'s `pick_random()` on an empty list crashes. Cap: no OD rolls once only 3 are alive. Pinned in Task 3.
2. **The OD starting while you're in another room, and the day turning over while they're down.** It should resolve as walking away, once. Pinned in Task 3.
3. **A bar save from before this batch** seating a regular who has since died, when `bar_patrons` holds their name. `_refresh_patrons` must replace them. Pinned in Task 3.
4. **The strip menu cancelled (Esc).** It should mean "just take it", never a paid-for dose vanishing silently. Pinned in Task 2.
5. **Booster hits while you're indoors**, and teaming up at 19:59. The hourly hook does the work, and "team up" only lasts until midnight. Pinned in Task 4.

---

### Task 1: Bad batch, contamination, and test strips (rules)

**Files:** `autoload/Headlines.gd`, `autoload/GameState.gd`, `npc/Outreach3D.gd`, `dev-tools/smoke_test_3d.gd` (new `_bad_batch_checks`, and `_batch2_checks` called after `_batch1_checks`). Create `dev-tools/smoke_batch2.gd`.

**Produces:**
- `Headlines`: events `bad_batch` and `vigil`, `od_risk_bad_batch() -> bool`.
- `GameState`: `BAD_BATCH_CHANCE`, `CONTAMINATED_RISK`, `test_strips: int`, `last_risk: float`, `roll_contaminated(drug_id) -> bool`, `take_drug(drug_id, dose_scale := 1.0, risk_mult := 1.0) -> String`, `strip_reading(asked, got, contaminated) -> String`.
- `Outreach3D` option order: 0 naloxone, 1 program, **2 strips**, 3 talk.

- [ ] **Step 1: Tests**

```gdscript
func _batch2_checks(gs: Node) -> void:
	await _bad_batch_checks(gs)

func _bad_batch_checks(gs: Node) -> void:
	await _section("Bad batch and test strips")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 18 * 60
	var hl := root.get_node("Headlines")
	hl.forced = "bad_batch"
	hl.roll(gs.day)
	var hits := 0
	for i in 2000:
		if gs.roll_contaminated("heroin"):
			hits += 1
	_check(hits > 700 and hits < 900, "  about 40%% of opioids are cut on a bad batch day (%d/2000)" % hits)
	_check(not gs.roll_contaminated("meth"), "  ...only the opioids")
	hl.forced = "quiet"
	hl.roll(gs.day)
	_check(not gs.roll_contaminated("heroin"), "  ...and none on an ordinary day")
	gs.tolerance.clear()
	gs.take_drug("bupe")
	var base: float = gs.last_risk
	gs.start_run()
	gs.take_drug("bupe", 1.0, gs.CONTAMINATED_RISK)
	_check(absf(gs.last_risk - base * 3.0) < 1e-9, "  contaminated is three times the risk")
	gs.start_run()
	gs.craving = 10.0
	gs.take_drug("bupe", 0.5)
	_check(absf(gs.last_risk - base * 0.5) < 1e-9 and gs.craving < 10.0 + float(root.get_node("Drugs").info("bupe")["relief"]) * 0.6, "  a little at a time: half the risk, half the relief")
	_check(gs.strip_reading("oxy", "fentanyl", false).contains("fentanyl"), "  a strip shows the blue was a press")
	_check(gs.strip_reading("heroin", "heroin", true).contains("cut"), "  ...and a cut bag")
	_check(gs.strip_reading("heroin", "heroin", false).contains("nothing"), "  ...and a clean one")
	gs.start_run()
	gs.clock = 18 * 60
	var shelter := await _load("res://world/Shelter3D.tscn")
	var outreach := shelter.get_node("Outreach")
	var hud = shelter.get_tree().get_first_node_in_group("hud")
	outreach._on_choice(2, _player(), hud)
	outreach._on_choice(2, _player(), hud)
	_check(gs.test_strips == 2, "  outreach hands out two strips, once a day")
	_player().dialogue_active = false
	gs.start_run()
```

`smoke_batch2.gd`: same shape as `smoke_batch1.gd`, calling `_batch2_checks(_gs())`.

- [ ] **Step 2: Run, and expect failure.**

- [ ] **Step 3: Implement**

`Headlines.EVENTS`:

```gdscript
	"bad_batch": {"weight": 2, "title": "Bad batch",
		"text": "Something bad's going round. Two people went over on the next block last night. Outreach is handing out test strips."},
	"vigil": {"weight": 0, "title": "Vigil",
		"text": "Candles at the mouth of the alley, and a name in marker on the wall. The corner's quiet today."},
```

In `roll()`, after the sabotage branch: `elif GameState.vigil_day == day: id = "vigil"`. Add `pusher_price_mult`, `"vigil": return 0.9`.

`GameState` (a new section after Rent):

```gdscript
## Bad batch: on its day, a lot of what's sold as opioids is cut with
## something stronger. Test strips from outreach tell you; nothing else does.
const BAD_BATCH_CHANCE := 0.4
const CONTAMINATED_RISK := 3.0
var test_strips: int = 0
## The overdose risk of the last dose taken, for tests.
var last_risk: float = 0.0

func roll_contaminated(drug_id: String) -> bool:
	var hl := _headlines()
	return hl != null and hl.is_today("bad_batch") and Drugs.info(drug_id).get("class", "") == Drugs.OPIOID and randf() < BAD_BATCH_CHANCE

## What a strip tells you about what you were handed.
func strip_reading(asked: String, got: String, contaminated: bool) -> String:
	if got == "fentanyl" and asked != "fentanyl":
		return "Two lines -- no. One line. Fentanyl. Whatever he called it, that's what it is."
	if contaminated:
		return "The strip lights up. It's cut with something, and it's strong."
	return "Two clean lines. It shows nothing it shouldn't."
```

Add `var vigil_day: int = -1` here as well (Task 3 sets it). Reset `test_strips`, `vigil_day` and `last_risk` in `start_run`.

`take_drug(drug_id: String, dose_scale := 1.0, risk_mult := 1.0)`:
- `var risk: float = d["od_risk"] * risk_mult * dose_scale` (replaces the first `risk` line).
- The `resp_load +=` line multiplies by `dose_scale`.
- The `tolerance[...]` add uses `float(d["tolerance"]) * dose_scale`.
- `relief` uses `float(d["relief"]) * dose_scale`.
- Set `last_risk = risk` right before the `randf() < risk` roll.

`Outreach3D.interact`: `options := ["Take a naloxone kit", program, "Take test strips", "Just talk"]`, and disable index 2 when `not GameState.daily_available("shelter_strips")`. In `_on_choice`, add case 2 and move "talk" to 3:

```gdscript
		2:
			GameState.daily_available("shelter_strips", true)
			GameState.test_strips += 2
			hud.show_dialogue(npc_name, "Two strips in a little baggie. \"Dissolve a few grains in water, dip it, wait. One line means fentanyl. It won't tell you how much. Use less, go slow, don't use alone.\"")
```

- [ ] **Step 4: Run, and expect PASS.** **Step 5: Commit** "Add the bad batch headline, contaminated doses, and test strips".

### Task 2: Testing at the pusher

**Files:** `npc/Pusher3D.gd`, `dev-tools/smoke_test_3d.gd` (`_strip_checks`).

**Produces:** `Pusher3D._asked_drug: String`, `_owed_contaminated: bool`, `_consume(player, drug: String, contaminated: bool, action: String) -> String` (action "take"/"half"/"toss"; returns the outcome or "tossed"), `_dose_choice(player, asked, drug, contaminated) -> String` (awaits menus; cancel → "take").

- [ ] **Step 1: Tests**

```gdscript
func _strip_checks(gs: Node) -> void:
	await _section("Testing what he sold you")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 18 * 60
	var city := await _load("res://world/City3D.tscn")
	var pusher := city.get_tree().get_first_node_in_group("pusher")
	var p := _player()
	gs.craving = 20.0
	_check(pusher._consume(p, "heroin", false, "toss") == "tossed" and gs.craving == 20.0 and gs.doses_taken == 0, "  thrown away: nothing goes in")
	gs.naloxone = 5
	pusher._consume(p, "heroin", true, "half")
	_check(absf(gs.last_risk - float(root.get_node("Drugs").info("heroin")["od_risk"]) * 3.0 * 0.5) < 1e-6, "  a cut bag taken slow: x3 risk, halved")
	gs.test_strips = 1
	var answer := [""]
	var asking = func(): answer[0] = await pusher._dose_choice(p, "heroin", "heroin", false)
	asking.call()
	await _frames(2)
	_close_menus()  # Esc on the first menu
	await _frames(2)
	_check(answer[0] == "take" and gs.test_strips == 1, "  closing the menu just takes it, strip unspent")
	p.dialogue_active = false
	gs.start_run()
```

`_close_menus()` frees the menu without emitting `cancelled`, so `_dose_choice` would hang. Use the menu's own cancel instead: find it (as `_close_menus` does) and call `_on_cancel()`. Write the check that way.

- [ ] **Step 2: Run, and expect failure.**

- [ ] **Step 3: Implement** in `Pusher3D.gd`:

```gdscript
var _asked_drug: String = ""
var _owed_contaminated: bool = false
signal _answered(index: int)
```

In `_buy`, in both branches next to `_owed_drug = Drugs.resolve_purchase(drug_id)`: `_asked_drug = drug_id` and `_owed_contaminated = GameState.roll_contaminated(_owed_drug)`.

In `_handoff`, replace `var outcome := GameState.take_drug(drug)` and the dialogue with:

```gdscript
	var contaminated := _owed_contaminated
	_owed_contaminated = false
	var action := "take"
	if GameState.test_strips > 0 and Drugs.info(drug).get("class", "") == Drugs.OPIOID:
		action = await _dose_choice(player, _asked_drug, drug, contaminated)
	var outcome := _consume(player, drug, contaminated, action)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and is_instance_valid(player):
		player.dialogue_active = true
		hud.show_dialogue("Pusher", "You tip it into the gutter. He shrugs. \"Your money.\"" if outcome == "tossed" else _handoff_line(drug, outcome), PORTRAIT)
	sale_completed.emit()
```

```gdscript
## A strip, if you've got one: test it, then decide. Esc on either menu
## means you just take it -- you paid, and nobody throws it away by accident.
func _dose_choice(player: Node, asked: String, drug: String, contaminated: bool) -> String:
	if await _ask(player, "It's in your hand. You've got %d test strip%s." % [GameState.test_strips, "" if GameState.test_strips == 1 else "s"], ["Test it first", "Just take it"]) != 0:
		return "take"
	GameState.test_strips -= 1
	var reading := GameState.strip_reading(asked, drug, contaminated)
	match await _ask(player, reading, ["Take it anyway", "Take a little at a time", "Throw it away"]):
		1: return "half"
		2: return "toss"
	return "take"

func _ask(player: Node, text: String, options: Array) -> int:
	if is_instance_valid(player):
		player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _answered.emit(i))
	menu.cancelled.connect(func(): _answered.emit(-1))
	menu.open("", text, options)
	return await _answered

func _consume(_player: Node, drug: String, contaminated: bool, action: String) -> String:
	if action == "toss":
		GameState.log_event("Tested it, and threw it away.")
		return "tossed"
	var risk := GameState.CONTAMINATED_RISK if contaminated else 1.0
	return GameState.take_drug(drug, 0.5 if action == "half" else 1.0, risk)
```

Check that `Pusher3D` already preloads `ChoiceMenu` (it uses a DrugMenu). Add `const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")` if it doesn't.

- [ ] **Step 4: Run, PASS.** **Step 5: Commit** "Let you test what the pusher hands you, and take less or bin it".

### Task 3: Someone goes over in the alley

**Files:** `autoload/GameState.gd`, `world/AlleyOverdose.gd` (create), `world/City3D.gd` (add it), `world/DiveBar3D.gd`, `npc/CharacterAnimator.gd` (`"collapse"` alias), `ui/Notebook.gd` (skip dead in rep list, if it lists them), test `_alley_checks`.

**Produces:**
- `GameState.REGULARS` (the six names; a test asserts it equals `DiveBar3D.PATRON_NAMES`).
- `OD_CHANCE = 0.25`, `OD_WINDOW = 90.0`, `od_event: Dictionary` (`{day, minute, who, state, left}`, where state is `"pending"`, `"down"`, `"saved"`, `"dead"`, `"robbed"` or `""`), `dead_regulars: Array`, `vigil_day` (from Task 1), `vigil_for: String`.
- `_roll_overdose()`, `living_regulars() -> Array`, `_check_overdose_start()`, `resolve_overdose(choice: String) -> String` (choice is `"naloxone"`, `"payphone"`, `"pockets"` or `"walk"`; returns `"saved"` or `"dead"`), `_regular_died(who, robbed: bool)`.
- `AlleyOverdose.gd` (`victim: Node3D`, `refresh()`, `_process` counts down `od_event.left` when `state == "down"`, interact → menu → `GameState.resolve_overdose`).

- [ ] **Step 1: Tests**

```gdscript
func _alley_checks(gs: Node) -> void:
	await _section("Someone goes over in the alley")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	_check(gs.REGULARS == load("res://world/DiveBar3D.gd").PATRON_NAMES, "  one list of regulars")
	var hl := root.get_node("Headlines")
	var rolled := 0
	for i in 400:
		gs.day = 3
		gs._roll_overdose()
		if gs.od_event.get("state", "") == "pending":
			rolled += 1
	_check(rolled > 70 and rolled < 130, "  about one night in four (%d/400)" % rolled)
	gs.day = 1
	gs._roll_overdose()
	_check(gs.od_event.get("state", "") == "", "  never on day 1")
	hl.forced = "bad_batch"
	hl.roll(3)
	gs.day = 3
	gs._roll_overdose()
	_check(gs.od_event["state"] == "pending" and gs.od_event["who"] in gs.REGULARS and gs.od_event["minute"] >= 18 * 60, "  always on a bad batch night, a regular, after 18:00")
	hl.forced = "quiet"
	hl.roll(3)
	# The start time passes whether you're there or not.
	gs.clock = gs.od_event["minute"] - 30
	gs.advance_clock(60)
	_check(gs.od_event["state"] == "down", "  at the time, they go down")
	gs.clock = 21 * 60
	var city := await _load("res://world/City3D.tscn")
	var alley := city.get_node("AlleyOverdose")
	await _frames(3)
	_check(alley.victim != null and alley.victim.visible, "  ...and they're in the alley")
	var who: String = gs.od_event["who"]
	gs.naloxone = 1
	_check(gs.resolve_overdose("naloxone") == "saved" and gs.naloxone == 0 and gs.rep_of(who) == 3, "  naloxone: saved, and they owe you (rep 3)")
	await _frames(2)
	_check(not alley.victim.visible, "  ...and they get up and go")
	for choice in ["payphone", "pockets"]:
		gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Quiet Kid", "state": "down", "left": 90.0}
		gs.rep.clear()
		var cash0: int = gs.cash
		var out: String = gs.resolve_overdose(choice)
		if choice == "payphone":
			_check(out == "saved" and gs.rep_of("Quiet Kid") == 2 and city.get_tree().get_nodes_in_group("patrol").size() >= 1, "  the payphone: saved, and a cop comes with the ambulance")
		else:
			_check(out == "dead" and gs.cash >= cash0 + 8 and gs.dead_regulars.has("Quiet Kid") and gs.vigil_day == gs.day + 1, "  their pockets: $%d, and they die" % (gs.cash - cash0))
	var died := 0
	for i in 300:
		gs.dead_regulars.clear()
		gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Old Sailor", "state": "down", "left": 90.0}
		if gs.resolve_overdose("walk") == "dead":
			died += 1
	_check(died > 170 and died < 230, "  walking away: two in three die (%d/300)" % died)
	gs.dead_regulars.clear()
	gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Old Sailor", "state": "down", "left": 0.5}
	await _frames(60)
	_check(gs.od_event["state"] in ["saved", "dead"], "  run out the clock and it's decided for you")
	gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Nervous Dave", "state": "down", "left": 90.0}
	gs.clock_running = false
	var diary_before: int = gs.diary.size()
	gs.advance_clock(24 * 60)
	_check(gs.od_event["state"] in ["saved", "dead"], "  the night ends while they're down: decided, once")
	# The dead stay dead.
	gs.dead_regulars.assign(["Big Eddie", "Wiry Guy", "Tired Woman"])
	gs.bar_patrons.clear()
	gs.bar_patrons.append({"name": "Big Eddie", "model": "", "seat": 0, "request_id": "cigs", "price": 22, "fulfilled": false})
	gs.clock = 18 * 60
	await _load("res://world/DiveBar3D.tscn")
	var names: Array = gs.bar_patrons.map(func(p): return p["name"])
	_check(not names.any(func(n): return n in gs.dead_regulars), "  nobody who died sits in the bar again: %s" % [names])
	gs.day = 3
	var none := true
	for i in 50:
		gs._roll_overdose()
		if gs.od_event.get("state", "") == "pending":
			none = false
	_check(none, "  with only three regulars left, nobody else goes over")
	gs.dead_regulars.clear()
	gs.vigil_day = gs.day + 1
	gs.vigil_for = "Quiet Kid"
	gs.advance_clock(24 * 60)
	_check(hl.is_today("vigil") and absf(hl.pusher_price_mult() - 0.9) < 1e-6, "  the next day is a vigil, and he charges less")
	gs.clock = 20 * 60
	city = await _load("res://world/City3D.tscn")
	_check(city.get_node("AlleyOverdose").get_node_or_null("Vigil") != null, "  ...with candles in the alley")
	gs.start_run()
```

The two `gs.advance_clock` calls that cross midnight run `Headlines.roll`, which uses `forced` when it's set. `_initialize` sets `forced = "quiet"`. So for the vigil check, set `hl.forced = ""` before the advance and back to `"quiet"` after it.

- [ ] **Step 2: Run, and expect failure.**

- [ ] **Step 3: Implement**

`CharacterAnimator.CLIP_ALIASES`: `"collapse": ["death", "_death"],` (Quaternius `Man_Death`/`Female_Death`). It isn't looped, so `set_rest_clip("collapse")` plays it once and holds the last frame.

`GameState`:

```gdscript
# --- The alley -------------------------------------------------------------

## The Dive Bar's regulars (DiveBar3D.PATRON_NAMES -- the test keeps the two
## lists the same). Some nights one of them goes over behind the dumpster.
const REGULARS := ["Wiry Guy", "Tired Woman", "Big Eddie", "Quiet Kid", "Old Sailor", "Nervous Dave"]
const OD_CHANCE := 0.25
## Real seconds they've got once they're down, counted only while you're
## on the block to see it.
const OD_WINDOW := 90.0
const OD_POCKETS := Vector2i(8, 20)
## {day, minute, who, state, left}; state "" (nothing tonight), "pending",
## "down", "saved", "dead".
var od_event: Dictionary = {}
var dead_regulars: Array = []
var vigil_for: String = ""
signal overdose_changed

func living_regulars() -> Array:
	return REGULARS.filter(func(n): return n not in dead_regulars)

## At the start of each day. The bar needs three, so it stops at three.
func _roll_overdose() -> void:
	od_event = {}
	var alive := living_regulars()
	var hl := _headlines()
	var chance := 1.0 if hl and hl.is_today("bad_batch") else OD_CHANCE
	if day <= 1 or alive.size() <= 3 or randf() >= chance:
		return
	od_event = {"day": day, "minute": randi_range(18 * 60, 23 * 60 + 30), "who": alive.pick_random(), "state": "pending", "left": OD_WINDOW}

## Hourly and on every clock tick of a room: the start time came.
func _check_overdose_start() -> void:
	if od_event.get("state", "") == "pending" and day == int(od_event["day"]) and clock >= float(od_event["minute"]):
		od_event["state"] = "down"
		log_event("Someone's down in the alley by the dumpster.")
		overdose_changed.emit()

func resolve_overdose(choice: String) -> String:
	if od_event.get("state", "") != "down":
		return ""
	var who: String = od_event["who"]
	var outcome := "saved"
	match choice:
		"naloxone":
			naloxone -= 1
			inventory_changed.emit()
			change_rep(who, 3)
			log_event("Found %s in the alley, not breathing. The naloxone brought them back." % who)
		"payphone":
			change_rep(who, 2)
			log_event("Ran for the payphone. The ambulance got %s in time." % who)
		"pockets":
			var took := randi_range(OD_POCKETS.x, OD_POCKETS.y)
			cash += took
			cash_changed.emit(cash)
			outcome = "dead"
			_regular_died(who, true)
		_:
			if randf() < 1.0 / 3.0:
				log_event("Somebody else called it in for %s." % who)
			else:
				outcome = "dead"
				_regular_died(who, false)
	od_event["state"] = outcome
	overdose_changed.emit()
	return outcome

func _regular_died(who: String, robbed: bool) -> void:
	dead_regulars.append(who)
	vigil_day = day + 1
	vigil_for = who
	log_event("%s died in the alley." % who, "overdose_floor")
	if robbed and randf() < 0.5:
		for n in living_regulars():
			change_rep(n, -2)
		log_event("Somebody saw you go through their pockets.")
```

Wire it up:
- In `_on_new_day`: first, if `od_event.state == "down"`, call `resolve_overdose("walk")`. Then `_roll_overdose()`.
- `_roll_overdose` must run *after* `Headlines` has rolled the day. Both listen to `day_changed`, and GameState connected first. So call it deferred: `_roll_overdose.call_deferred()` from `_on_new_day`.
- Call `_check_overdose_start()` from `_emit_clock` when the minute changes (cheap).
- Reset `od_event`, `dead_regulars`, `vigil_day` and `vigil_for` in `start_run`.

`DiveBar3D`:
- `_new_patron`: name filter adds `and n not in GameState.dead_regulars`.
- `_refresh_patrons`: replace an entry if `state[i]["fulfilled"] or state[i]["name"] in GameState.dead_regulars`.

`world/AlleyOverdose.gd`: an `Area3D`-free `Node3D`. It builds:
- **The victim:** an `Area3D` zone (Interactable3D) at `Vector3(21.5, 0, -3.6)` with the regular's model (`CharacterCast.model_for(who)`, dressed, `root.scale 1.5`, `CharacterAnimator.set_rest_clip("collapse")`).
- **The Vigil node** (only if `Headlines.is_today("vigil")`): five small emissive candles (`CylinderMesh` 0.03 × 0.12, warm `OmniLight3D`, range 1.5, energy 0.5, flickering in `_process`) at x 20.6-21.4, z -3.9, and a `Label3D` "RIP %s" % `GameState.vigil_for` on the wall at y 1.3.

```gdscript
func _process(delta: float) -> void:
	if GameState.od_event.get("state", "") == "down":
		GameState.od_event["left"] = float(GameState.od_event["left"]) - delta
		if float(GameState.od_event["left"]) <= 0.0:
			GameState.resolve_overdose("walk")
```

On `overdose_changed`: `refresh()` (victim visible iff state is "down"). The first time it's visible in this scene, `Graphics._show_toast("Someone's down in the alley by the dumpster.")`.

Interact → `ChoiceMenu` with `["Use your naloxone (%d)" % n, "Shout for help and run for the payphone", "Go through their pockets", "Walk away"]`. Index 0 is disabled when `naloxone == 0`. Map to the choices, then a narrated line per outcome:
- **Payphone:** `get_parent()._spawn_patrol(Vector3(18.0, 0, -1.3))` (City3D's own spawner), then `SFX.play("siren")` if that sound exists. Check `SFX.gd` for the siren name; it's near line 169.
- **Saved by naloxone:** "They come round gasping, sick and furious and alive."
- **Dead:** "You leave them there." or "You go through their jacket. $%d. They don't move."

In `City3D._ready()`, add it next to `Temptation`: `var alley: Node3D = preload("res://world/AlleyOverdose.gd").new(); alley.name = "AlleyOverdose"; add_child(alley)`.

- [ ] **Step 4: Run, PASS.** Take a quiet-capture screenshot of the victim (copy `dev-tools/.scratch/cap_notes.gd`, set `od_event` to "down", `closeup:AlleyOverdose`) and look at it.

- [ ] **Step 5: Commit** "Someone goes over in the alley: save them, rob them, or walk on".

### Task 4: Tasha

**Files:** `autoload/GameState.gd`, `npc/CharacterCast.gd` (`booster` role), `world/Booster.gd` (create), `world/City3D.gd`, `ui/Notebook.gd` (map T), test `_booster_checks`.

**Produces:**
- `BOOSTER_CHANCE = 0.4`, `BOOSTER_HOURS = [10, 20]`, `BOOSTER_STORES = ["pharmacy", "convenience", "liquor", "supermarket", "electronics"]`.
- `booster_day: int`, `booster_gone: bool`, `booster_store: String`, `booster_hit: Array`, `booster_team: String` (store teamed on today), `booster_cut_pending: bool`, `signal booster_changed`.
- `_roll_booster()`, `booster_present() -> bool`, `_booster_hour()`, `booster_team_up(store) -> void`, `booster_rat() -> void`. The cut is applied in `sell_item`.
- `Booster.gd` (`npc: Area3D`, `refresh()`).

- [ ] **Step 1: Tests**

```gdscript
func _booster_checks(gs: Node) -> void:
	await _section("Tasha, working the same stores")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	var days := 0
	for i in 400:
		gs.day = 3
		gs._roll_booster()
		if gs.booster_day == 3:
			days += 1
	_check(days > 130 and days < 190, "  out about two days in five (%d/400)" % days)
	gs.day = 1
	gs._roll_booster()
	_check(gs.booster_day != 1, "  never day 1")
	gs.day = 3
	gs.vigil_day = 3
	gs._roll_booster()
	_check(gs.booster_day != 3, "  never on a vigil day")
	gs.vigil_day = -1
	gs.booster_day = 3
	gs.clock = 9 * 60 + 50
	gs.advance_clock(20)
	_check(gs.booster_present() and gs.booster_store != "", "  at ten she's out, casing %s" % gs.booster_store)
	var first: String = gs.booster_store
	gs.advance_clock(60)
	_check(gs.booster_hit == [first] and gs.store_alertness(first) > gs.staff_alertness() * 1.25, "  an hour later it's hit, and its staff are jumpy")
	gs.booster_team_up("liquor")
	_check(gs.booster_team == "liquor" and gs.store_alertness("liquor") < gs.staff_alertness() * 0.7 and gs.booster_cut_pending, "  teaming up: she works the liquor clerk")
	var hits: int = gs.booster_hit.size()
	gs.advance_clock(120)
	_check(gs.booster_hit.size() == hits, "  ...and stops hitting other stores")
	gs.inventory.append("vodka")
	var cash0: int = gs.cash
	gs.sell_item("vodka", 30)
	_check(gs.cash - cash0 == int(round(30 * root.get_node("MetaProgress").payout_scale())) / 2 and not gs.booster_cut_pending, "  ...and takes half your next order")
	gs.start_run()
	gs.clock_running = false
	gs.day = 3
	gs.booster_day = 3
	gs.clock = 10 * 60 + 5
	gs.advance_clock(60)
	var hit: String = gs.booster_hit[0]
	gs.warrant = true
	gs.homeless_trust = 3
	gs.change_rep("Big Eddie", 2)
	gs.booster_rat()
	_check(gs.booster_gone and not gs.booster_present() and not gs.store_heat.has(hit) and not gs.warrant, "  ratting her out: gone, heat cleared, warrant lost")
	_check(gs.homeless_trust == 0 and gs.rep_of("Big Eddie") == 1, "  ...and the street knows")
	gs.day = 9
	gs._roll_booster()
	_check(gs.booster_day != 9, "  ...for good")
	gs.start_run()
	gs.day = 3
	gs.booster_day = 3
	gs.clock = 14 * 60
	gs._booster_hour()
	var city := await _load("res://world/City3D.tscn")
	await _frames(3)
	_check(city.get_node("Booster").npc.visible, "  she's on the block")
	gs.start_run()
```

- [ ] **Step 2: Run, and expect failure.**

- [ ] **Step 3: Implement** in `GameState`:

```gdscript
# --- Tasha -----------------------------------------------------------------

## A rival booster, out some days, hitting the same stores you do: each
## hour she works one, and when she's done its staff are on edge for the
## day. Team up and she works a clerk for you, for a cut; rat her out and
## she's gone, and so is your standing on the street.
const BOOSTER_CHANCE := 0.4
const BOOSTER_HOURS := [10, 20]
const BOOSTER_STORES := ["pharmacy", "convenience", "liquor", "supermarket", "electronics"]
var booster_day: int = -1
var booster_gone: bool = false
var booster_store: String = ""
var booster_hit: Array = []
var booster_team: String = ""
var booster_cut_pending: bool = false
signal booster_changed

func _roll_booster() -> void:
	booster_hit.clear()
	booster_store = ""
	booster_team = ""
	if booster_gone or day <= 1 or day == vigil_day or randf() >= BOOSTER_CHANCE:
		return
	booster_day = day

func booster_present() -> bool:
	return not booster_gone and booster_day == day and hours_contain(BOOSTER_HOURS, hour())

## On the hour: the store she was casing is hit, and she moves on.
func _booster_hour() -> void:
	if booster_team != "" or booster_gone or booster_day != day:
		return
	if booster_store != "":
		booster_hit.append(booster_store)
		set_store_heat(booster_store, 1.3, 1)
		Graphics._show_toast("Someone just hit %s. Staff will be jumpy." % STORE_NAMES[booster_store])
		log_event("Tasha hit %s." % STORE_NAMES[booster_store])
	booster_store = ""
	if booster_present():
		booster_store = BOOSTER_STORES.filter(func(s): return s not in booster_hit).pick_random() if booster_hit.size() < BOOSTER_STORES.size() else ""
	booster_changed.emit()

func booster_team_up(store: String) -> void:
	booster_team = store
	booster_store = store
	set_store_heat(store, 0.6, 1)
	booster_cut_pending = true
	log_event("Teamed up with Tasha on %s. She gets half the next order." % STORE_NAMES[store])
	booster_changed.emit()

func booster_rat() -> void:
	booster_gone = true
	for s in booster_hit:
		store_heat.erase(s)
	booster_store = ""
	if warrant:
		warrant = false
		legal_changed.emit()
	homeless_trust = 0
	for n in living_regulars():
		change_rep(n, -1)
	log_event("Gave Tasha up to the beat cop. The street will remember.")
	booster_changed.emit()
```

Wire it up:
- `_on_new_day`: `_roll_booster.call_deferred()`, after `_roll_overdose`, because it reads `vigil_day`.
- `_emit_clock` hour branch: `_booster_hour()`.
- `sell_item`: after computing `paid`, `if booster_cut_pending: paid = paid / 2; booster_cut_pending = false; log_event("Tasha took her half.")`.
- Reset everything in `start_run`.

The test's 09:50 + 20 min crosses into 10:00. `_booster_hour` then picks a store, because `booster_store == ""` and nothing is hit yet. At 11:00 it hits it. Good.

`CharacterCast.CAST["booster"]`: `FEMALE_ALT`, look `{"Shirt": Color(0.12, 0.12, 0.14), "Pants": Color(0.18, 0.20, 0.26), "Hair": Color(0.08, 0.06, 0.05)}`.

`world/Booster.gd`: like `StreetScenes._make`. One Interactable zone with the booster model, idle, `root.scale 1.5`. `refresh()` puts it at `STORE_X[booster_store] + 1.6, z -3.4` (`STORE_X = {"pharmacy": -10.5, "convenience": 3.5, "liquor": 10.5, "supermarket": 17.5, "electronics": 24.5}`). It's visible and in the "interactable" group only when `booster_present() and booster_store != ""`. Connect `GameState.booster_changed` and `clock_changed` (methods, not lambdas).

Interact → `ChoiceMenu`, speaker "Tasha":
- Greeting: "\"Don't look at me like that. Rent's rent.\" She's watching the %s door."
- Options: "Team up -- she works a clerk, she takes half your next order" (disabled if `booster_team != ""`), "Rat her out to the beat cop", "Leave her be".
- Team up opens a second menu of the five stores (store names) → `booster_team_up(store)`.
- Rat → `booster_rat()`, and a line: "You catch the cop's eye and tip your head at her. He's already walking."

Notebook `_draw_map`: for each hit store, a small red "x" over its door. If `booster_store != ""`, a "T" over it (`BLOCK` has the door x positions).

- [ ] **Step 4: Run, PASS.** **Step 5: Commit** "Add Tasha, a rival booster you can team up with or give up".

### Task 5: Save, README, full regression

`SaveGame.FIELDS` += `"test_strips", "od_event", "dead_regulars", "vigil_day", "vigil_for", "booster_day", "booster_gone", "booster_store", "booster_hit", "booster_team", "booster_cut_pending"`.

Test `_batch2_save_checks`: set each one, save, `start_run`, continue, and compare. Specifically check that `od_event` "down" with `left` survives, and that loading doesn't reroll the day's overdose or Tasha. Loading emits `day_changed` → `_on_new_day` → the deferred rolls would wipe them. So in `_on_new_day`, skip `_roll_overdose`/`_roll_booster` when `od_event.get("day", -1) == day` / `booster_day == day`, and resolve a "down" event only when `od_event.day < day`. Write the check first; it should fail on the reroll.

README: a "The street gets dangerous" group after batch 1's bullets. Full `smoke_test_3d` alone, PASS, then commit "Save batch 2's state, and document the street".
