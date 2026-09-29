extends SceneTree
## Drug economy simulator. Plays N runs per strategy against the real
## Drugs catalogue and the real GameState dosing code (no mocks), scoring
## each time the player gets sick, and reports how runs end and what they
## cost. Answers the questions a single playthrough can't: is any strategy
## dominant, is overdose too common or too rare, and can you afford to live?
##   godot --headless --path . -s res://dev-tools/drug_sim.gd -- [runs]

## A day of scraping: roughly what a couple of delivered orders pays.
const INCOME_PER_DAY := 45
const DAYS_PER_RUN := 14
## How many times a day the craving bottoms out and you have to score.
const SCORES_PER_DAY := 2

func _initialize() -> void:
	# Don't touch the player's progress, settings or saved run.
	Engine.set_meta("sandbox", true)
	await process_frame
	var runs := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 400
	var gs := root.get_node("GameState")
	var drugs := root.get_node("Drugs")

	print("Drug economy: %d runs per strategy, %d days each, $%d/day income\n" % [runs, DAYS_PER_RUN, INCOME_PER_DAY])
	print("%-22s %6s %7s %7s %7s %8s" % ["strategy", "days", "OD%", "broke%", "spent", "tol"])
	print("-".repeat(62))

	for strategy in ["cheapest opioid", "always oxy", "always heroin", "always fentanyl", "bupe maintenance", "opioid + benzo", "fentanyl binge x4", "relapse after 2 clean"]:
		var days_total := 0
		var od := 0
		var broke := 0
		var spend_total := 0
		var tol_total := 0.0
		var relapse_first := 0
		var relapse_first_od := 0
		for r in runs:
			gs.start_run()
			var cash := 0
			var died := false
			var ran_dry := false
			var day := 0
			for d in DAYS_PER_RUN:
				day = d + 1
				cash += INCOME_PER_DAY
				# Two clean days in the middle (a stretch in jail, a try at
				# stopping), then straight back to the old dose.
				if strategy == "relapse after 2 clean" and (d == 7 or d == 8):
					_pass_time(gs, 24 * 60)
					continue
				for s in SCORES_PER_DAY:
					# Scores are hours apart: what's on board fades between them,
					# and a benzo in the morning isn't still working at night.
					_pass_time(gs, 24 * 60 / SCORES_PER_DAY)
					var pick: String = _pick(strategy, gs, drugs, s)
					var cost: int = gs.price_of(pick)
					if cost > cash:
						ran_dry = true
						break
					cash -= cost
					spend_total += cost
					# Buying "oxy" on the street may not be oxy.
					var got: String = drugs.resolve_purchase(pick)
					var hits := 4 if strategy == "fentanyl binge x4" else 1
					for h in hits:
						var outcome: String = gs.take_drug(got)
						if strategy == "relapse after 2 clean" and d == 9 and s == 0:
							relapse_first += 1
							if outcome == "overdose":
								relapse_first_od += 1
						if outcome == "overdose":
							died = true
							break
						gs.run_time += 20.0
					if died:
						break
				if died or ran_dry:
					break
			days_total += day
			tol_total += gs.tolerance_for("heroin")
			if died: od += 1
			if ran_dry: broke += 1
		print("%-22s %6.1f %6.1f%% %6.1f%% %7.0f %8.1f" % [
			strategy, float(days_total) / runs, 100.0 * od / runs, 100.0 * broke / runs,
			float(spend_total) / runs, tol_total / runs])
		if relapse_first > 0:
			print("    first dose back after the break: %.1f%% went over" % (100.0 * relapse_first_od / relapse_first))
	quit()

## Time passing between doses, the way the game passes it: the clock (which
## decays tolerance), run time (which decides mixing), and the respiratory
## load fading on its half-life.
func _pass_time(gs: Node, minutes: float) -> void:
	var secs: float = minutes / gs.MINUTES_PER_SEC
	gs.run_time += secs
	gs.resp_load *= pow(0.5, secs / gs.get_node("/root/Drugs").LOAD_HALF_LIFE)
	gs.advance_clock(minutes)

## What this strategy scores with. `slot` alternates so the mixing strategy
## actually mixes classes within a day.
func _pick(strategy: String, gs: Node, drugs: Node, slot: int) -> String:
	match strategy:
		"always oxy": return "oxy"
		"always heroin", "relapse after 2 clean": return "heroin"
		"always fentanyl", "fentanyl binge x4": return "fentanyl"
		"bupe maintenance": return "bupe"
		"opioid + benzo": return "heroin" if slot == 0 else "clonazepam"
		_:
			var best := ""
			var best_cost := 99999
			for d in drugs.CATALOGUE:
				if d["class"] not in [drugs.OPIOID, drugs.TREATMENT]:
					continue
				var c: int = gs.price_of(d["id"])
				if c < best_cost:
					best_cost = c
					best = d["id"]
			return best
