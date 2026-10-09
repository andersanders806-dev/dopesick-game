extends Node
## The week's story: three people, woven.
##
## Mia, your younger sister, texts and calls (a phone buzz and the
## notebook's Messages page) and comes to your door on day 3. Ray, the man
## by the alley, went to school with you; on day 2 he says he wants out, and
## if nobody helps him he's the one down in the alley on day 4. Dana, the
## counsellor at St. Jude's, has one bed: book it, turn up for the
## appointment, and the program's yours -- miss two and it goes to someone
## else. They talk to each other, and what happens to one reaches the rest.
## Lose all three and that's an ending of its own.
##
## State is GameState.story (saved with the run). Beats run off the hourly
## clock (GameState calls hourly()).

const CharacterCast := preload("res://npc/CharacterCast.gd")
const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")

const MIA_VISIT := [18, 23]
## Evenings, when St. Jude's is open (GameState.OPENING_HOURS["shelter"]).
const DANA_HOURS := [17, 20]
const RAY_OD_DAY := 4
const RAY_OD_MINUTE := 20 * 60
const MIA_GIFT := 20
const MIA_PURSE := 40
## Where Mia stands in the apartment, inside the door.
const MIA_POS := Vector3(3.3, 0, -0.2)

const DEFAULTS := {
	"msgs": [], "fired": [],
	"mia": "close", "mia_promise": false, "mia_visited": false,
	"ray": "using",
	"dana": "none", "dana_day": -1, "dana_missed": 0,
	"ended": false,
}

## The story so far, defaults filled in, and caught up with what the rest
## of the game decided (Ray's night in the alley).
func state() -> Dictionary:
	var s: Dictionary = GameState.story
	for k in DEFAULTS:
		if not s.has(k):
			s[k] = DEFAULTS[k].duplicate() if DEFAULTS[k] is Array else DEFAULTS[k]
	if "Ray" in GameState.dead_regulars:
		s["ray"] = "dead"
	elif GameState.od_event.get("who", "") == "Ray" and GameState.od_event.get("state", "") == "saved" and s["ray"] in ["using", "asked"]:
		s["ray"] = "saved"
	return s

func messages() -> Array:
	return state()["msgs"]

# --- The phone ---------------------------------------------------------------

func send(from: String, text: String) -> void:
	var s := state()
	if from == "Mia" and s["mia"] == "blocked":
		return
	s["msgs"].append({"day": GameState.day, "clock": GameState.clock_text(), "from": from, "text": text})
	GameState.log_event("%s: \"%s\"" % [from, text])
	if is_inside_tree():
		SFX.play("blip", -6.0, 1.3)
		Graphics._show_toast("Phone -- %s: %s" % [from, text], 6.0)

func _once(id: String) -> bool:
	var fired: Array = state()["fired"]
	if id in fired:
		return false
	fired.append(id)
	return true

# --- The clock -----------------------------------------------------------------

func hourly() -> void:
	var s := state()
	if s["ended"]:
		return
	var d := GameState.day
	var h := GameState.hour()
	if d >= 1 and h >= 10 and _once("mia_1"):
		send("Mia", "Mom's birthday is Sunday. Are you coming? Please say yes.")
	if d >= 2 and h >= 9 and _once("mia_2"):
		send("Mia", "You didn't answer. There's a counsellor at St. Jude's, Dana. She keeps a bed for people. Please go see her.")
	if mia_visit_now() and _in_apartment() and _mia_node() == null:
		furnish_apartment(get_tree().current_scene)
	if (d > 3 or (d == 3 and h >= MIA_VISIT[1])) and not s["mia_visited"] and _mia_node() == null and _once("mia_missed"):
		send("Mia", "I waited outside your door for an hour. I'm not doing that again.")
		_mia_worse()
	# Only on the day itself, before the hour: a late load mustn't plant it
	# over another night's overdose.
	if d == RAY_OD_DAY and h < RAY_OD_MINUTE / 60 and s["ray"] in ["using", "asked"] and _once("ray_od"):
		GameState.od_event = {"day": RAY_OD_DAY, "minute": RAY_OD_MINUTE, "who": "Ray", "state": "pending", "left": GameState.OD_WINDOW}
	if d >= 5 and h >= 9 and _once("mia_5"):
		if s["ray"] == "dead":
			send("Mia", "I heard about Ray. I keep thinking it's going to be you next.")
		elif s["dana"] == "in" or GameState.in_treatment:
			send("Mia", "Dana says you came in. I'm so proud of you. I mean it.")
		else:
			send("Mia", "Mom asked about you. I didn't know what to tell her.")
	if d >= 6 and h >= 17 and _once("mia_6"):
		send("Mia", "We're at Mom's. There's a plate for you." if s["mia"] == "close" else "Mom cried at dinner. Just so you know.")
	_check_appointment()
	if s["mia"] == "blocked" and s["ray"] == "dead" and s["dana"] == "lost" and not _busy():
		s["ended"] = true
		GameState.end_run("alone")

## Mid-conversation or mid-cutscene: the ending can wait an hour.
func _busy() -> bool:
	if not is_inside_tree():
		return false
	var player := get_tree().get_first_node_in_group("player")
	return Cutscene.is_playing() or (player != null and player.dialogue_active)

func _in_apartment() -> bool:
	return is_inside_tree() and get_tree().current_scene != null and get_tree().current_scene.name == "Apartment3D"

func _mia_node() -> Node:
	if not _in_apartment():
		return null
	return get_tree().current_scene.get_node_or_null("Mia")

# --- Mia -----------------------------------------------------------------------

func _mia_worse() -> void:
	var s := state()
	s["mia"] = "hurt" if s["mia"] == "close" else "blocked"
	if s["mia"] == "blocked":
		GameState.log_event("Mia blocked your number.")

func ring_gone() -> bool:
	return GameState.belongings.get("ring", "home") not in ["home", "carried"]

func mia_visit_now() -> bool:
	var s := state()
	return GameState.day == 3 and GameState.hours_contain(MIA_VISIT, GameState.hour()) and not s["mia_visited"] and s["mia"] != "blocked"

func mia_opening() -> String:
	var text := "Mia's at the door with a grocery bag, her coat still on. She looks at you for a long time before she says anything."
	if ring_gone():
		text += " Then her eyes go to the shelf. \"Where's Mom's ring?\""
	else:
		text += " \"You look like hell. Can I come in?\""
	return text

## "promise", "leave" or "steal".
func mia_choice(choice: String) -> void:
	var s := state()
	s["mia_visited"] = true
	match choice:
		"promise":
			s["mia_promise"] = true
			book_dana()
			GameState.cash += MIA_GIFT
			GameState.cash_changed.emit(GameState.cash)
			GameState.log_event("Mia came by. Promised her I'd see Dana.")
			if ring_gone():
				_mia_worse()
		"leave":
			GameState.log_event("Mia came by. Told her to leave.")
			_mia_worse()
			if ring_gone():
				_mia_worse()
		"steal":
			GameState.cash += MIA_PURSE
			GameState.cash_changed.emit(GameState.cash)
			s["mia"] = "blocked"
			GameState.log_event("Took $%d from Mia's bag while she put the groceries away. She noticed." % MIA_PURSE)

func furnish_apartment(room: Node3D) -> void:
	if not mia_visit_now():
		return
	var zone := Area3D.new()
	zone.name = "Mia"
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	room.add_child(zone)
	zone.position = MIA_POS
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 1.6
	shape.shape = cyl
	shape.position = Vector3(0, 0.8, 0)
	zone.add_child(shape)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 1.5
	holder.rotation_degrees.y = -90.0
	zone.add_child(holder)
	var model: Node = CharacterCast.scene_for(CharacterCast.model_for("mia")).instantiate()
	holder.add_child(model)
	CharacterCast.dress(model, "mia")
	CharacterAnimator.new(model)
	zone.set_meta("prompt", "Talk to Mia")
	zone.interacted.connect(func(z, player): _talk_to_mia(z, player))

func _talk_to_mia(zone: Node, player: Node) -> void:
	player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	player.get_tree().root.add_child(menu)
	var choices := ["promise", "leave", "steal"]
	menu.chosen.connect(func(i: int):
		mia_choice(choices[i])
		var line: String = {
			"promise": "She lets out a breath she's been holding since Tuesday. Folds a twenty into your hand. \"Tomorrow evening. Five o'clock. I called Dana -- she's expecting you. Don't make me a liar.\"",
			"leave": "\"Fine.\" She sets the bag down inside the door and goes. You hear her stop on the stairs, and then keep going.",
			"steal": "While she puts the milk away you go through her bag. She sees you in the window's reflection. She doesn't say anything at all. She just leaves.",
		}[choices[i]]
		if is_instance_valid(zone):
			zone.queue_free()
		var hud := player.get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_dialogue("Mia", line)
		else:
			player.dialogue_active = false)
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Mia", mia_opening(), ["\"I'll see Dana tomorrow. I promise.\"", "\"You should go.\"", "Go through her bag while she's in the kitchen"])

# --- Ray -----------------------------------------------------------------------

func ray_wants_out() -> bool:
	return GameState.day >= 2 and state()["ray"] in ["using", "asked"]

## "naloxone", "strips" or "dana".
func help_ray(how: String) -> bool:
	var s := state()
	match how:
		"naloxone":
			if GameState.naloxone <= 0:
				return false
			GameState.naloxone -= 1
			GameState.inventory_changed.emit()
		"strips":
			if GameState.test_strips <= 0:
				return false
			GameState.test_strips -= 1
	_ray_helped()
	GameState.log_event("Helped Ray. He says he'll go see Dana. Maybe he will.")
	return true

## Helped: and if his night in the alley was still coming, it isn't now.
func _ray_helped() -> void:
	state()["ray"] = "helped"
	if GameState.od_event.get("who", "") == "Ray" and GameState.od_event.get("state", "") == "pending":
		GameState.od_event = {}

func ray_line() -> String:
	match state()["ray"]:
		"saved":
			return "\"Somebody told me you were there. In the alley.\" He can't look at you. \"I'm going to Dana's tonight. I owe you that.\""
		"helped", "sober":
			return "\"Dana's got me on the list.\" He looks almost clean. \"She asks about you. You should go in.\""
	return "He doesn't look up. \"Remember Mr. Kowalski's class? You and me, back row. Look at us.\" A long breath. \"I can't do this anymore. I want out. I don't know how.\""

# --- Dana ------------------------------------------------------------------------

func book_dana() -> void:
	var s := state()
	if s["dana"] != "none":
		return
	s["dana"] = "booked"
	s["dana_day"] = GameState.day + 1
	GameState.log_event("Dana has a bed for me. Appointment: day %d, %d-%d." % [s["dana_day"], DANA_HOURS[0], DANA_HOURS[1]])

func appointment_text() -> String:
	var s := state()
	match s["dana"]:
		"booked":
			return "Dana at St. Jude's: day %d, %d-%d" % [s["dana_day"], DANA_HOURS[0], DANA_HOURS[1]]
		"lost":
			return "Dana's bed: gone to someone else"
	return ""

func appointment_open() -> bool:
	var s := state()
	return s["dana"] == "booked" and GameState.day == s["dana_day"] and GameState.hours_contain(DANA_HOURS, GameState.hour())

func keep_appointment() -> bool:
	if not appointment_open():
		return false
	state()["dana"] = "in"
	GameState.log_event("Kept the appointment with Dana. The bed's mine.")
	return true

func can_start_program() -> bool:
	return state()["dana"] == "in" or GameState.in_treatment

func _check_appointment() -> void:
	var s := state()
	if s["dana"] != "booked":
		return
	var past: bool = GameState.day > s["dana_day"] or (GameState.day == s["dana_day"] and GameState.hour() >= DANA_HOURS[1])
	if not past:
		return
	s["dana_missed"] += 1
	if s["dana_missed"] >= 2:
		s["dana"] = "lost"
		if s["ray"] in ["using", "asked"]:
			_ray_helped()
			send("St. Jude's", "Your bed has gone to someone on the waiting list. (Dana: it went to Ray. He was waiting outside at ten.)")
		else:
			send("St. Jude's", "Your bed has gone to someone on the waiting list. The next one is six weeks out.")
		return
	s["dana_day"] = GameState.day + 1
	send("St. Jude's", "You missed your appointment with Dana. Tomorrow, %d-%d. She can't hold the bed past that." % DANA_HOURS)

# --- Endings -----------------------------------------------------------------------

func ending_line(cause: String) -> String:
	var s := state()
	var mia_here: bool = s["mia"] != "blocked"
	match cause:
		"overdose":
			if mia_here and GameState.day >= 3:
				return "Mia found you the next morning. She'd come to take you to see Dana."
			return "Nobody found you for two days."
		"recovered":
			var line := "Mia's waiting outside the clinic. She doesn't say anything. She doesn't have to." if mia_here else "Nobody's waiting outside. You walk home anyway."
			if s["ray"] in ["helped", "saved", "sober"]:
				line += " Ray's there too, in a clean shirt."
			return line
		"alone":
			return "No one left to call. Mia's number goes to voicemail. Ray's name is on the alley wall. Dana's bed has someone else in it."
	return "Mia's in the back row of the courtroom. She doesn't look away." if mia_here else "Nobody comes to the hearing."
