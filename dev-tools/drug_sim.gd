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
	await process_frame
	var runs := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 400
	var gs := root.get_node("GameState")
	var drugs := root.get_node("Drugs")

	print("Drug economy: %d runs per strategy, %d days each, $%d/day income\n" % [runs, DAYS_PER_RUN, INCOME_PER_DAY])
	print("%-22s %6s %7s %7s %7s %8s" % ["strategy", "days", "OD%", "broke%", "spent", "tol"])
	print("-".repeat(62))

	for strategy in ["cheapest opioid", "always oxy", "always heroin", "always fentanyl", "bupe maintenance", "opioid + benzo"]:
		var days_total := 0
		var od := 0
		var broke := 0
		var spend_total := 0
		var tol_total := 0.0
		for r in runs:
			gs.start_run()
			var cash := 0
			var died := false
			var ran_dry := false
			var day := 0
			for d in DAYS_PER_RUN:
				day = d + 1
				cash += INCOME_PER_DAY
				for s in SCORES_PER_DAY:
					var pick: String = _pick(strategy, gs, drugs, s)
					var cost: int = gs.price_of(pick)
					if cost > cash:
						ran_dry = true
						break
					cash -= cost
					spend_total += cost
					# Buying "oxy" on the street may not be oxy.
					var got: String = drugs.resolve_purchase(pick)
					if gs.take_drug(got) == "overdose":
						died = true
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
	quit()

## What this strategy scores with. `slot` alternates so the mixing strategy
## actually mixes classes within a day.
func _pick(strategy: String, gs: Node, drugs: Node, slot: int) -> String:
	match strategy:
		"always oxy": return "oxy"
		"always heroin": return "heroin"
		"always fentanyl": return "fentanyl"
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
