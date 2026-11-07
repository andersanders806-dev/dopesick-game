extends RefCounted
## Ghetto Wars: the story, as data. Five chapters over the waves (fx/GhettoStory.gd plays it, ui/GhettoStoryHud.gd shows
## it, fx/GhettoVoice.gd speaks it). The arc is a drug-bust: you hold your crew's pill corner, move the stash, learn
## somebody is talking to the police, find out the new batch is killing people (and choose what to do with it), then the
## raid comes (flush the stash, run for the car, or get cuffed).
##
## Every line is [mature, clean]; ZombieMode.mature_language picks. The hard lines of the writing: no slurs of any kind,
## nothing about race, origin, sexuality or religion, no real gangs, places, people or brands, nothing sexual, no
## hate symbols; the overdoses are shown straight and never mocked; nobody but armed men is ever shot at.
##
## A beat is {t: seconds after its trigger, k: kind, ...}. Kinds: text (phone: from, body), radio (who, line), scan
## (dispatcher, line), obj (objective text, "" clears), beat (id, for the set dressing), sfx (name), spawn (a
## GhettoMode.spawn_wave dict), choice (id), stash / stash_report / raid (the objectives). A beat may carry
## `when: "sold"` / `"dumped"` (only after that choice). Triggers: "w<n>" (wave n starts), "w<n>_clear" (it is cleared),
## "choice_<id>_<option>" (right after a choice).

const CLOCK_START := 23 * 60 + 48 # the night begins at 11:48 PM

const CHAPTERS := [
	{"id": "corner", "title": "THE CORNER", "place": "Main Street", "sub": ["Your crew's corner. The Dock Boys want it.", "Your crew's corner. The Dock Boys want it."], "from": 1, "to": 2, "music": "ch1_corner"},
	{"id": "stash", "title": "STASH RUN", "place": "The laundromat, back room", "sub": ["Four bags. A week of product. Don't lose it.", "Four bags. A week of product. Don't lose it."], "from": 3, "to": 4, "music": "ch2_stash"},
	{"id": "snitch", "title": "THE SNITCH", "place": "Main Street, 1:02 AM", "sub": ["Somebody is talking to the police.", "Somebody is talking to the police."], "from": 5, "to": 6, "music": "ch3_snitch"},
	{"id": "tainted", "title": "TAINTED", "place": "Fifth Street, 1:40 AM", "sub": ["The new batch is killing people.", "The new batch is killing people."], "from": 7, "to": 7, "music": "ch4_tainted"},
	{"id": "bust", "title": "THE BUST", "place": "Main Street, 2:11 AM", "sub": ["Warrant team on the block.", "Warrant team on the block."], "from": 8, "to": 99, "music": "ch5_bust"},
]

## Where the objective pieces go when the set dressing has not put a marker (a Node3D in group "ghetto_pt" with meta
## "pt" = the name) on the map: the stash bags in the laundromat's back room, its sink, and the getaway car in the lot.
const POINTS := {
	"stash_a": Vector3(-18.0, 0.0, -9.0), "stash_b": Vector3(-19.5, 0.0, -10.5),
	"stash_c": Vector3(-16.5, 0.0, -10.8), "stash_d": Vector3(-18.5, 0.0, -12.0),
	"sink": Vector3(-20.5, 0.0, -9.5),
	"car": Vector3(30.0, 0.0, -17.5),
}
const BAG_NAMES := ["stash_a", "stash_b", "stash_c", "stash_d"]

const SELL_POINTS_BASE := 600
const SELL_POINTS_PER_BAG := 300
## The batch's cost: what you throw away (shown on the card, not taken from your score).
const DUMP_LOSS := 11000
const CHOICE_SECONDS := 25.0
const FLUSH_SECONDS := 9.0
const ESCAPE_SECONDS := 120.0
const REINFORCE_EVERY := 30.0
const MAX_REINFORCE := 3

## Who talks, and in which colour on the phone and the radio.
const WHO := {
	"NICO": {"name": "NICO", "color": Color(0.96, 0.78, 0.25)},
	"TISH": {"name": "TISH", "color": Color(0.5, 0.78, 0.95)},
	"UNKNOWN": {"name": "UNKNOWN", "color": Color(0.75, 0.75, 0.75)},
	"DEX": {"name": "DEX", "color": Color(0.85, 0.55, 0.55)},
	"DANA": {"name": "DANA (OUTREACH)", "color": Color(0.55, 0.9, 0.65)},
	"MOM": {"name": "MOM", "color": Color(0.95, 0.85, 0.7)},
	"DISPATCH": {"name": "DISPATCH", "color": Color(0.6, 0.95, 0.6)},
}

const BEATS := {
	# --- 1. THE CORNER ------------------------------------------------------------------------
	"w1": [
		{"t": 1.0, "k": "text", "from": "NICO", "body": ["Dock Boys. Two vans. They want our fucking corner. Hold it till I get the product moved.", "Dock Boys. Two vans. They want our corner. Hold it till I get the product moved."]},
		{"t": 6.0, "k": "radio", "who": "NICO", "line": ["Eyes up, Kings. Nobody takes this corner on my watch.", "Eyes up, Kings. Nobody takes this corner on my watch."]},
		{"t": 9.0, "k": "obj", "text": ["HOLD THE CORNER", "HOLD THE CORNER"]},
	],
	"w1_clear": [
		{"t": 2.0, "k": "text", "from": "TISH", "body": ["ok that was just the first wave. salt's whole crew is out tonight", "ok that was just the first wave. salt's whole crew is out tonight"]},
	],
	"w2": [
		{"t": 1.5, "k": "radio", "who": "NICO", "line": ["Salt is throwing bodies at us. Don't let them walk you off the corner.", "Salt is throwing everyone at us. Don't let them walk you off the corner."]},
	],
	"w2_clear": [
		{"t": 2.0, "k": "scan", "line": ["Dispatch to all units. Reports of shots fired, Main Street. Hold at the perimeter. Do not engage.", "Dispatch to all units. Reports of shots fired, Main Street. Hold at the perimeter. Do not engage."]},
		{"t": 2.5, "k": "beat", "id": "cops_circling"},
		{"t": 6.0, "k": "text", "from": "NICO", "body": ["Cops are circling. They're not coming in. They're waiting. That's worse.", "Cops are circling. They're not coming in. They're waiting. That's worse."]},
	],
	# --- 2. STASH RUN -------------------------------------------------------------------------
	"w3": [
		{"t": 1.0, "k": "text", "from": "NICO", "body": ["The product's in the laundromat, back room. Four bags. Grab them before Salt's guys find the door.", "The product's in the laundromat, back room. Four bags. Grab them before Salt's guys find the door."]},
		{"t": 2.5, "k": "stash"},
		{"t": 9.0, "k": "radio", "who": "NICO", "line": ["Four bags, Kings. That's the whole week. Go, go!", "Four bags, Kings. That's the whole week. Go, go!"]},
	],
	"w3_clear": [
		{"t": 1.5, "k": "radio", "who": "NICO", "line": ["Back room's still ours. Hold it, they're pushing again.", "Back room's still ours. Hold it, they're pushing again."]},
	],
	"w4": [
		{"t": 1.5, "k": "radio", "who": "NICO", "line": ["They know about the back room! Somebody gave them the door!", "They know about the back room! Somebody gave them the door!"]},
		{"t": 7.0, "k": "beat", "id": "stash_pressure"},
	],
	"w4_clear": [
		{"t": 1.0, "k": "stash_report"},
		{"t": 6.0, "k": "text", "from": "NICO", "body": ["Salt knew the door, the hour, all of it. Someone on our side is talking.", "Salt knew the door, the hour, all of it. Someone on our side is talking."]},
	],
	# --- 3. THE SNITCH ------------------------------------------------------------------------
	"w5": [
		{"t": 1.5, "k": "text", "from": "UNKNOWN", "body": ["u dont know me. somebody on ur crew is texting a detective. i saw the phone. be careful who u trust", "u dont know me. somebody on ur crew is texting a detective. i saw the phone. be careful who u trust"]},
		{"t": 6.5, "k": "text", "from": "TISH", "body": ["dont trust nico. hes been weird since tuesday", "dont trust nico. hes been weird since tuesday"]},
		{"t": 11.0, "k": "text", "from": "NICO", "body": ["Tish was in a cop car outside her mother's place last week. Ask her about that.", "Tish was in a cop car outside her mother's place last week. Ask her about that."]},
		{"t": 16.0, "k": "obj", "text": ["SURVIVE. TRUST NOBODY.", "SURVIVE. TRUST NOBODY."]},
	],
	"w5_clear": [
		{"t": 2.0, "k": "radio", "who": "NICO", "line": ["Don't read the texts. Somebody wants us shooting each other instead of them.", "Don't read the texts. Somebody wants us fighting each other instead of them."]},
	],
	"w6": [
		{"t": 2.0, "k": "radio", "who": "NICO", "line": ["CAR! Black sedan, east end! Get down!", "CAR! Black sedan, east end! Get down!"]},
		{"t": 2.4, "k": "sfx", "name": "car_pass"},
		{"t": 3.0, "k": "spawn", "spec": {"count": 6, "weapons": ["smg", "smg", "pistol"], "crew": "Dock Boys", "drive_by": true}},
		{"t": 3.0, "k": "beat", "id": "drive_by"},
	],
	"w6_clear": [
		{"t": 2.5, "k": "text", "from": "DEX", "body": ["its me. im sorry. they got my little brother with a bag and said 20 years. i gave them the corner and the date. get out. please", "its me. im sorry. they got my little brother with a bag and said 20 years. i gave them the corner and the date. get out. please"]},
		{"t": 8.5, "k": "radio", "who": "NICO", "line": ["Dex. Fucking Dex. Okay. He gave them tonight. We have minutes, not hours.", "Dex. Dex, of all people. Okay. He gave them tonight. We have minutes, not hours."]},
		{"t": 8.8, "k": "beat", "id": "snitch_revealed"},
	],
	# --- 4. TAINTED ---------------------------------------------------------------------------
	"w7": [
		{"t": 0.8, "k": "beat", "id": "ods_street"},
		{"t": 2.0, "k": "text", "from": "DANA", "body": ["Three OD calls on Fifth since midnight. Blue pills, stamped like yours. Something is in them. If that's your batch, please don't let it go out.", "Three OD calls on Fifth since midnight. Blue pills, stamped like yours. Something is in them. If that's your batch, please don't let it go out."]},
		{"t": 9.0, "k": "radio", "who": "NICO", "line": ["That's the new batch. Somebody cut it greedy. Four hundred pills in that stash.", "That's the new batch. Somebody cut it greedy. Four hundred pills in that stash."]},
		{"t": 14.0, "k": "choice", "id": "batch"},
	],
	"choice_batch_dump": [
		{"t": 1.0, "k": "radio", "who": "NICO", "line": ["Gone. Down the drain. Eleven grand, gone. Sleep okay tonight, if you can.", "Gone. Down the drain. Eleven grand, gone. Sleep okay tonight, if you can."]},
	],
	"choice_batch_sell": [
		{"t": 1.0, "k": "radio", "who": "NICO", "line": ["Okay. It's moving. Don't think about Fifth Street.", "Okay. It's moving. Don't think about Fifth Street."]},
	],
	"choice_batch_hesitate": [
		{"t": 1.0, "k": "radio", "who": "NICO", "line": ["You didn't pick. So it went out the door anyway. That's how it works.", "You didn't pick. So it went out the door anyway. That's how it works."]},
	],
	"w7_clear": [
		{"t": 2.0, "k": "text", "when": "dumped", "from": "DANA", "body": ["Narcan got there in time. Two of them sat up. Thank you. I mean it.", "Narcan got there in time. Two of them sat up. Thank you. I mean it."]},
		{"t": 2.0, "k": "text", "when": "sold", "from": "DANA", "body": ["Four more on Fifth. One was nineteen. I hope the money was worth it.", "Four more on Fifth. One was nineteen. I hope the money was worth it."]},
		{"t": 2.2, "k": "beat", "when": "sold", "id": "ods_more"},
		{"t": 8.0, "k": "text", "from": "MOM", "body": ["you eating? call me back. love you", "you eating? call me back. love you"]},
		{"t": 14.0, "k": "scan", "line": ["Command to all units. Warrant is signed. Eastside corner. Execute at the top of the hour.", "Command to all units. Warrant is signed. Eastside corner. Execute at the top of the hour."]},
	],
	# --- 5. THE BUST --------------------------------------------------------------------------
	"w8": [
		{"t": 0.5, "k": "scan", "line": ["ALL UNITS, WARRANT TEAM GO. EASTSIDE CORNER. ARMED SUSPECTS. EXPECT RESISTANCE.", "ALL UNITS, WARRANT TEAM GO. EASTSIDE CORNER. ARMED SUSPECTS. EXPECT RESISTANCE."]},
		{"t": 1.0, "k": "beat", "id": "raid_start"},
		{"t": 1.5, "k": "beat", "id": "heli"},
		{"t": 3.0, "k": "radio", "who": "NICO", "line": ["POLICE! It's the fucking police! Flush the stash, flush it NOW! The sink in the back room!", "POLICE! It's the police! Flush the stash, flush it NOW! The sink in the back room!"]},
		{"t": 4.0, "k": "raid"},
		{"t": 9.0, "k": "radio", "who": "NICO", "line": ["Car's in the lot behind the laundromat. Flush it or take it, but MOVE!", "Car's in the lot behind the laundromat. Flush it or take it, but MOVE!"]},
	],
}

## The raid's police wave and its reinforcements (GhettoMode.spawn_wave dicts).
const POLICE_WAVE := {"count": 8, "weapons": ["ar", "ar", "shotgun", "smg"], "crew": "Police"}
const POLICE_REINFORCE := {"count": 4, "weapons": ["ar", "shotgun"], "crew": "Police"}

const REINFORCE_SCAN := [
	["Command, requesting additional units at the laundromat. Suspect still inside.", "Command, requesting additional units at the laundromat. Suspect still inside."],
	["Units in the lot, hold your fire lanes. Subject is moving to the vehicle.", "Units in the lot, hold your fire lanes. Subject is moving to the vehicle."],
	["Air unit, we have the suspect in the back lot. Keep the light on him.", "Air unit, we have the suspect in the back lot. Keep the light on him."],
]

## What the stash report says, by how many bags you got.
const STASH_REPORT := {
	"all": ["That's all four. A whole week of product, in a laundromat. Funny.", "That's all four. A whole week of product, in a laundromat. Funny."],
	"some": ["We're short, but we'll make it work. We always do.", "We're short, but we'll make it work. We always do."],
	"none": ["You came back with nothing? Jesus. Dock Boys have it all now.", "You came back with nothing? Dock Boys have it all now."],
}

## Police shouting during the raid (GhettoVoice kind "police"); the mature set has the real swearing, the clean set the
## same command without it.
const POLICE_BARKS := {
	"spot": [
		["ARMED POLICE! DROP THE FUCKING GUN!", "ARMED POLICE! DROP THE GUN!"],
		["POLICE! SHOW ME YOUR HANDS!", "POLICE! SHOW ME YOUR HANDS!"],
		["GET ON THE GROUND! NOW!", "GET ON THE GROUND! NOW!"],
		["HE'S ARMED! WEAPON! WEAPON!", "HE'S ARMED! WEAPON! WEAPON!"],
		["ON THE GROUND OR WE WILL SHOOT!", "ON THE GROUND OR WE WILL SHOOT!"],
	],
	"advance": [
		["STACK UP! MOVE, MOVE!", "STACK UP! MOVE, MOVE!"],
		["CLEAR LEFT! CLEAR RIGHT!", "CLEAR LEFT! CLEAR RIGHT!"],
		["HE'S IN THE BACK ROOM!", "HE'S IN THE BACK ROOM!"],
		["CUT OFF THE LOT! DON'T LET HIM REACH THE CAR!", "CUT OFF THE LOT! DON'T LET HIM REACH THE CAR!"],
	],
	"reload": [
		["RELOADING! COVER ME!", "RELOADING! COVER ME!"],
		["MAG! I NEED COVER, FUCK!", "MAG! I NEED COVER!"],
	],
	"down": [
		["OFFICER DOWN! OFFICER DOWN!", "OFFICER DOWN! OFFICER DOWN!"],
		["I'M HIT! I NEED A MEDIC!", "I'M HIT! I NEED A MEDIC!"],
	],
	"radio": [
		["COMMAND, SHOTS FIRED! SHOTS FIRED!", "COMMAND, SHOTS FIRED! SHOTS FIRED!"],
	],
}

## More Dock Boys talk, over what npc/Barks.gd has (GhettoVoice kind "bark"; "cry" for the downed).
const EXTRA_BARKS := {
	"taunt_habit": [
		["You're shaking, dealer! Your habit's gonna... it's gonna kill you first!", "You're shaking, dealer! Your habit's gonna... it's gonna get you first!"],
		["Look at you, you can't even hold that gun still! So why can't I hit you?", "Look at you, you can't even hold that gun still! So why can't I hit you?"],
		["Nice stash, dealer. We'll burn it. We will. Just... stay back!", "Nice stash, dealer. We'll burn it. We will. Just... stay back!"],
	],
	"mock_reload2": [
		["He's reloading! Go! Go! Before he's done, shit!", "He's reloading! Go! Go! Before he's done!"],
		["Click! He's empty! Somebody get him, not me!", "Click! He's empty! Somebody get him, not me!"],
	],
	"drive_by": [
		["Burn the corner! Burn it and drive! Drive!", "Burn the corner! Burn it and drive! Drive!"],
		["Shoot and go, shoot and go! Don't stop the car!", "Shoot and go, shoot and go! Don't stop the car!"],
	],
	"cry": [
		["Don't leave me here. Please. Don't leave me.", "Don't leave me here. Please. Don't leave me."],
		["I can't feel my legs. Oh God. Oh God.", "I can't feel my legs. Oh no. Oh no."],
	],
}

## The endings: "<how>_<batch>", how is clean (flushed it, got out), bag (got out with the stash) or busted.
const ENDINGS := {
	"clean_dumped": {
		"title": "WALKED AWAY", "tone": "dawn",
		"lines": ["The sink took it all. The car took you.", "No stash, no batch, nobody face down on Fifth Street because of you.", "You still have the habit. That one doesn't flush."],
		"mature": ["The sink took it all. The car took you.", "No stash, no batch, nobody face down on Fifth Street because of you.", "You still have the habit. That one doesn't fucking flush."],
	},
	"clean_sold": {
		"title": "WALKED AWAY", "tone": "dawn",
		"lines": ["The sink took the rest. The car took you.", "The batch you sold is already on the street.", "Nobody will ever say your name. That's worse."],
		"mature": ["The sink took the rest. The car took you.", "The batch you sold is already on the street.", "Nobody will ever say your name. That's fucking worse."],
	},
	"bag_dumped": {
		"title": "ESCAPED WITH THE BAG", "tone": "dusk",
		"lines": ["The bag is on your lap and the car is moving.", "You poured out the bad batch. The rest is still evidence.", "Your hands are shaking. The raid never cared that you're sick."],
		"mature": ["The bag is on your lap and the car is moving.", "You poured out the bad batch. The rest is still evidence.", "Your hands are shaking. The raid never gave a shit that you're sick."],
	},
	"bag_sold": {
		"title": "ESCAPED WITH THE BAG", "tone": "dusk",
		"lines": ["The bag is on your lap and the car is moving.", "Somewhere behind you, an ambulance is working Fifth Street.", "You are not clean. You are only free."],
		"mature": ["The bag is on your lap and the car is moving.", "Somewhere behind you, an ambulance is working Fifth Street.", "You are not clean. You are only fucking free."],
	},
	"busted_dumped": {
		"title": "BUSTED", "tone": "cuffs",
		"lines": ["Face down on the pavement behind the laundromat.", "Possession with intent. It would have been worse if you had sold it.", "In the cell, the sickness catches up. Nobody comes."],
		"mature": ["Face down on the pavement behind the laundromat.", "Possession with intent. It would have been worse if you had sold it.", "In the cell, the sickness catches up. Nobody comes."],
	},
	"busted_sold": {
		"title": "BUSTED", "tone": "cuffs",
		"lines": ["Face down on the pavement behind the laundromat.", "Possession with intent. And a charge for every name from Fifth Street.", "You told yourself it was only business."],
		"mature": ["Face down on the pavement behind the laundromat.", "Possession with intent. And a charge for every name from Fifth Street.", "You told yourself it was only fucking business."],
	},
}

## --- lookup ----------------------------------------------------------------------------------

static func chapter_index_for_wave(n: int) -> int:
	for i in CHAPTERS.size():
		if n >= int(CHAPTERS[i]["from"]) and n <= int(CHAPTERS[i]["to"]):
			return i
	return CHAPTERS.size() - 1 if n > int(CHAPTERS[CHAPTERS.size() - 1]["to"]) else 0

static func pick(pair: Array, mature: bool) -> String:
	return String(pair[0] if mature else pair[1])

static func clock_text(minutes: int) -> String:
	var m := minutes % (24 * 60)
	var h := m / 60
	var ampm := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m % 60, ampm]

static func ending_lines(key: String, mature: bool) -> Array:
	var e: Dictionary = ENDINGS.get(key, {})
	return e.get("mature" if mature else "lines", []) as Array

## Every [mature, clean] pair that the story says, keyed "kind|who": for the voice bake and the tests.
## Phone texts are read, not spoken, so they have no voice; radio, scanner, police and barks do.
static func voiced_pairs() -> Array:
	var out: Array = []
	for key in BEATS:
		for e in BEATS[key]:
			if e["k"] == "radio":
				out.append({"kind": "radio", "who": e["who"], "pair": e["line"]})
			elif e["k"] == "scan":
				out.append({"kind": "scan", "who": "DISPATCH", "pair": e["line"]})
	for pair in REINFORCE_SCAN:
		out.append({"kind": "scan", "who": "DISPATCH", "pair": pair})
	for k in STASH_REPORT:
		out.append({"kind": "radio", "who": "NICO", "pair": STASH_REPORT[k]})
	for ev in POLICE_BARKS:
		for pair in POLICE_BARKS[ev]:
			out.append({"kind": "police", "who": "POLICE", "pair": pair})
	for ev in EXTRA_BARKS:
		for pair in EXTRA_BARKS[ev]:
			out.append({"kind": "cry" if ev == "cry" else "bark", "who": "DOCK", "pair": pair})
	return out

## Every text on the phone ([from, pair]).
static func all_texts() -> Array:
	var out: Array = []
	for key in BEATS:
		for e in BEATS[key]:
			if e["k"] == "text":
				out.append([e["from"], e["body"]])
	return out

## Every line of text in the story, mature or clean (the tests check the clean set is clean and the hard lines hold).
static func every_line(mature: bool) -> Array[String]:
	var out: Array[String] = []
	for key in BEATS:
		for e in BEATS[key]:
			if e.has("body"):
				out.append(pick(e["body"], mature))
			if e.has("line"):
				out.append(pick(e["line"], mature))
			if e.has("text"):
				out.append(pick(e["text"], mature))
	for pair in REINFORCE_SCAN:
		out.append(pick(pair, mature))
	for k in STASH_REPORT:
		out.append(pick(STASH_REPORT[k], mature))
	for set_ in [POLICE_BARKS, EXTRA_BARKS]:
		for ev in set_:
			for pair in set_[ev]:
				out.append(pick(pair, mature))
	for ch in CHAPTERS:
		out.append(pick(ch["sub"], mature))
	for k in ENDINGS:
		for l in ending_lines(k, mature):
			out.append(String(l))
	return out

## Words that never appear, in either set (slurs and the like): the test looks for them. Kept as fragments of words
## that can not be innocent here; the list is deliberately short and blunt.
const BANNED := ["nigg", "fagg", "faggot", "retard", "tranny", "chink", "spic", "kike", "wetback", "coon", "gook", "dyke",
	"rape", "swastika", "nazi", "whore", "slut", "cunt"]
## What the clean set may not contain.
const PROFANITY := ["fuck", "shit", "bastard", "asshole", "dickhead", "motherfucker", "prick", "damn", "dumb shit"]
