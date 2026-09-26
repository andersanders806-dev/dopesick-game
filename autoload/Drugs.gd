extends Node
## What the pusher sells, what it costs, and what it does to you.
##
## Replaces the old single abstract "$20 fix". Every score is now a choice
## between things that differ on price, how much relief they give, how long
## that lasts, how fast they build tolerance, and how likely they are to kill
## you -- so "what can I afford" and "what can I survive" stop being the same
## question.
##
## PRICES are anchored to published figures, not invented, the same way the
## shoplifting catalogue is anchored to the CRAVED research:
##
## - Diverted pharmaceuticals use StreetRx / RADARS crowdsourced
##   price-per-milligram means (Psychiatric Services 2022; Drug Alcohol
##   Depend. 2018): oxycodone ~$0.97/mg, buprenorphine ~$2.13/mg, methadone
##   ~$0.96/mg. A 30 mg oxycodone tablet therefore lands near $30, an 8 mg
##   buprenorphine strip near $17-20, a 10 mg methadone near $10.
## - Heroin is quoted per bag rather than per mg; reported ranges run about
##   $5-20 a bag depending on region and purity.
## - Benzodiazepine tablets are commonly reported at roughly $2-20 each.
## - Fentanyl is the cheapest opioid per dose on the street, which is most of
##   why it displaced the others.
##
## These are deliberately *fixed*, researched figures used as game balance.
## Real street prices swing enormously by region, purity, quantity and
## relationship, and nothing here should be read as a current price list.
##
## THE COUNTERFEIT MECHANIC is the important one, and it comes straight from
## DEA laboratory analysis: most "oxycodone 30 mg" (M30) tablets sold on the
## street are not oxycodone at all but pressed fentanyl, made with no dosing
## control, and roughly half of those fake pills carry a potentially lethal
## amount. So in this game the expensive, familiar, apparently-predictable
## pill is the single most dangerous thing you can buy -- you just don't find
## out until after you've taken it. That is the actual shape of the risk, and
## it is worth more than any amount of warning text.

## Classes matter because tolerance is shared within a class (cross-tolerance
## is real), and because mixing an opioid with a benzodiazepine is what
## actually kills people -- both suppress breathing.
const OPIOID := "opioid"
const BENZO := "benzo"
const STIMULANT := "stimulant"
const TREATMENT := "treatment"
const RESCUE := "rescue"

## OD RISK IS PER DOSE, and a run is roughly 25-30 doses, so these numbers
## compound hard: 0.02 for fentanyl works out near a 40% chance of going
## over across a full run, while 0.0004 for buprenorphine is about 1%.
## Retune them with dev-tools/drug_sim.gd, which plays whole runs per
## strategy, never by eye -- figures that look sane per dose produced a
## 95% overdose rate across a run.
##
## relief   - craving restored (the meter runs 0-100)
## hours    - how long it holds you, as a multiplier on craving decay while
##            it's in you; higher = you go longer before you're sick again
## tolerance- how much tolerance one dose adds to its class
## od_risk  - base chance per dose of going over
## fake     - chance what you bought is a fentanyl press instead
const CATALOGUE := [
	{
		"id": "heroin", "name": "Heroin", "street": "a bag", "class": OPIOID,
		"price": 15, "relief": 95.0, "hours": 1.0, "tolerance": 1.3,
		"od_risk": 0.006, "fake": 0.18,
		"desc": "A bag. Short, and you'll be sick again by evening.",
	},
	{
		"id": "oxy", "name": "Oxycodone 30mg", "street": "a blue", "class": OPIOID,
		"price": 30, "relief": 100.0, "hours": 1.5, "tolerance": 1.0,
		"od_risk": 0.002, "fake": 0.55,
		"desc": "An M30. Clean, predictable, lasts. If it's real.",
	},
	{
		"id": "fentanyl", "name": "Fentanyl", "street": "fetty", "class": OPIOID,
		"price": 8, "relief": 100.0, "hours": 0.55, "tolerance": 2.2,
		"od_risk": 0.020, "fake": 0.0,
		"desc": "Cheapest thing on the street. Wears off fastest. No two doses the same.",
	},
	{
		"id": "clonazepam", "name": "Clonazepam 2mg", "street": "pins", "class": BENZO,
		"price": 5, "relief": 30.0, "hours": 2.2, "tolerance": 0.8,
		"od_risk": 0.001, "fake": 0.10,
		"desc": "Won't touch dopesickness. Makes the waiting bearable. Never on top of an opioid.",
	},
	{
		"id": "alprazolam", "name": "Alprazolam 2mg", "street": "bars", "class": BENZO,
		"price": 6, "relief": 25.0, "hours": 1.4, "tolerance": 1.1,
		"od_risk": 0.0015, "fake": 0.25,
		"desc": "Hits harder than pins and leaves sooner. Most bars on the street are pressed.",
	},
	{
		"id": "methadone", "name": "Methadone 10mg", "street": "done", "class": TREATMENT,
		"price": 10, "relief": 85.0, "hours": 3.0, "tolerance": 0.5,
		"od_risk": 0.005, "fake": 0.05,
		"desc": "Holds you a long time. No real lift to it. Builds up in you.",
	},
	{
		"id": "bupe", "name": "Buprenorphine 8mg", "street": "strips", "class": TREATMENT,
		"price": 20, "relief": 100.0, "hours": 4.0, "tolerance": -2.0,
		"od_risk": 0.0004, "fake": 0.05,
		"desc": "Stops the sickness cold for a day and brings your tolerance down. No high. Take it too soon after an opioid and it rips you into withdrawal.",
	},
	{
		"id": "meth", "name": "Methamphetamine", "street": "a point", "class": STIMULANT,
		"price": 10, "relief": 15.0, "hours": 2.5, "tolerance": 1.0,
		"od_risk": 0.002, "fake": 0.08,
		"desc": "Keeps you upright and moving. Does nothing for opioid withdrawal.",
	},
	{
		"id": "crack", "name": "Crack cocaine", "street": "a rock", "class": STIMULANT,
		"price": 10, "relief": 12.0, "hours": 0.4, "tolerance": 1.2,
		"od_risk": 0.002, "fake": 0.05,
		"desc": "Twenty good minutes, then you want another one immediately.",
	},
	{
		"id": "naloxone", "name": "Naloxone", "street": "Narcan", "class": RESCUE,
		"price": 12, "relief": 0.0, "hours": 0.0, "tolerance": 0.0,
		"od_risk": 0.0, "fake": 0.0,
		"desc": "Reverses an overdose. Carrying it means the next one doesn't have to end you.",
	},
]

## Taking a buprenorphine dose within this long of a full opioid agonist
## throws you into precipitated withdrawal instead of relief -- bupe binds
## harder than heroin or fentanyl and shoves them off the receptor. It is the
## single most common way people ruin their first attempt at getting on it.
const PRECIPITATED_WINDOW := 240.0
## Opioid taken on top of a benzo still in you (or the reverse) multiplies
## the chance of going over: both suppress breathing.
const MIX_WINDOW := 300.0
const MIX_OD_MULTIPLIER := 3.5

func all_ids() -> Array:
	return CATALOGUE.map(func(d): return d["id"])

func info(id: String) -> Dictionary:
	for d in CATALOGUE:
		if d["id"] == id:
			return d
	return {}

func name_for(id: String) -> String:
	return info(id).get("name", id)

## What a dose actually costs today. Opioid prices drift up with the
## tolerance you've built in that class, because you need more of it -- the
## old game modelled this as one global fix price rising $4 a day.
func price_for(id: String, tolerance: float) -> int:
	var d := info(id)
	if d.is_empty():
		return 0
	if d["class"] in [OPIOID, TREATMENT]:
		return int(round(d["price"] * (1.0 + tolerance * 0.05)))
	return int(d["price"])

## What you were actually sold. Most of the time it's what you asked for;
## `fake` of the time it's a fentanyl press wearing its name.
func resolve_purchase(id: String) -> String:
	var d := info(id)
	if d.is_empty():
		return id
	if d.get("fake", 0.0) > 0.0 and randf() < d["fake"]:
		return "fentanyl"
	return id
