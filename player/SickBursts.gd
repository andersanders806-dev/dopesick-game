extends Node
## Withdrawal's involuntary noises: a cough, a sniff, a retch, at random intervals that get shorter
## and louder the sicker you are -- and every one is heard (GameState.emit_noise), so in a shop with
## a guard in it they are a real problem.
##
## Each one gives a tell first: a second of warning (a breath caught, the hand going to the mouth,
## the head hitching) in which you can HOLD the stifle button (Q, L2). Holding it delays the burst up
## to HOLD_MAX seconds -- time to get behind a shelf or out of earshot -- and then it breaks out
## louder than it would have. Letting go lets it out at its usual volume at once. Stifling is felt:
## the edges of the view close in and you move slower the whole time you hold.
##
## Child of Player3D. Bursts only happen in the story, in the open (no dialogue, menu or cutscene).

## Where it starts: below this sickness (0..1, GameState.sickness()) there are none.
const SICK_FROM := 0.3
## Seconds between bursts, [min, max], when it has just started and at its worst.
const INTERVAL_MILD := Vector2(45.0, 90.0)
const INTERVAL_SEVERE := Vector2(15.0, 30.0)
## How far a burst carries (m) at the two ends.
const LOUD_MILD := 4.0
const LOUD_SEVERE := 9.0
## The warning, and the longest it can be held back.
const TELL_TIME := 1.0
const HOLD_MAX := 4.0
## Held to the limit it breaks out this much louder.
const BREAKOUT_LOUDER := 1.5
## What holding it in costs: the speed you keep, and how closed in the view gets (0..1).
const STIFLE_SPEED := 0.6
const STIFLE_TUNNEL := 0.75
## How long each kind lasts, and how far it carries next to a plain cough.
const KINDS := {
	"sniff": {"len": 0.55, "loud": 0.55},
	"cough": {"len": 0.9, "loud": 1.0},
	"retch": {"len": 1.0, "loud": 1.0},
	"cough_fit": {"len": 2.0, "loud": 1.1},
}

enum State { IDLE, TELL, HOLD, BURST }

var state: int = State.IDLE
## How closed in the view is (0..1): the HUD's PostFX reads it.
var tunnel := 0.0
## Counts and the last one's details (the smoke test reads them).
var bursts := 0
var last_kind := ""
var last_loudness := 0.0
var last_broke_out := false

var _player: Node3D
var _timer := 0.0
var _t := 0.0
var _burst_left := 0.0
var _kind := ""
var _loud := 0.0
var _broke_out := false
var _second_done := false
var _forced_kind := ""
## A fixed answer for the stifle button (-1 reads the input; 0 / 1 is released / held): the tests.
var stifle_override := -1

func setup(player: Node3D) -> void:
	name = "SickBursts"
	_player = player
	_timer = _roll_interval()

## 0 at SICK_FROM, 1 at the bottom of the meter.
func severity() -> float:
	return clampf((GameState.sickness() - SICK_FROM) / (1.0 - SICK_FROM), 0.0, 1.0)

func _roll_interval() -> float:
	var t := severity()
	return randf_range(lerpf(INTERVAL_MILD.x, INTERVAL_SEVERE.x, t), lerpf(INTERVAL_MILD.y, INTERVAL_SEVERE.y, t))

## How loud a plain cough is now (m).
func loudness_now() -> float:
	return lerpf(LOUD_MILD, LOUD_SEVERE, severity())

func stifle_held() -> bool:
	if stifle_override >= 0:
		return stifle_override == 1
	return Input.is_action_pressed("stifle")

## The player's speed, scaled: slower while you hold it in.
func speed_mult() -> float:
	return lerpf(1.0, STIFLE_SPEED, tunnel / STIFLE_TUNNEL) if state == State.HOLD else 1.0

## Whether the burst is being held back right now (the HUD says so).
func holding() -> bool:
	return state == State.HOLD

## Seconds of holding left before it breaks out (the HUD's bar).
func hold_left() -> float:
	return maxf(0.0, HOLD_MAX - _t) if state == State.HOLD else 0.0

## Whether a tell or a hold is on: the HUD shows the prompt.
func warning() -> bool:
	return state == State.TELL or state == State.HOLD

func _quiet() -> bool:
	var p := _player
	if p == null or not is_instance_valid(p):
		return true
	if GameState.mode != "story" or GameState.in_custody or get_tree().paused or Cutscene.is_playing():
		return true
	return bool(p.get("dialogue_active"))

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var want_tunnel := 0.0
	match state:
		State.IDLE:
			if GameState.sickness() < SICK_FROM or _quiet():
				# Not sick, or talking: the next one is rolled when it starts again.
				if GameState.sickness() < SICK_FROM:
					_timer = _roll_interval()
			else:
				_timer -= delta
				if _timer <= 0.0:
					begin_tell()
		State.TELL:
			_t += delta
			if _t >= TELL_TIME:
				if stifle_held():
					_start_hold()
				else:
					_burst(false)
		State.HOLD:
			_t += delta
			want_tunnel = STIFLE_TUNNEL
			if not stifle_held():
				_burst(false)
			elif _t >= HOLD_MAX:
				_burst(true)
		State.BURST:
			_burst_left -= delta
			_burst_step()
			if _burst_left <= 0.0:
				_end_burst()
	tunnel = move_toward(tunnel, want_tunnel, delta * (1.6 if want_tunnel > tunnel else 2.2))
	# The head: a hitch at the tell, jerks in the burst, then it settles.
	_player.set("fp_hitch", _hitch())

func _hitch() -> float:
	match state:
		State.TELL:
			return 0.035 * smoothstep(0.0, 0.5, _t)
		State.HOLD:
			return 0.05 + sin(_t * 23.0) * 0.012
		State.BURST:
			var k := clampf(_burst_left / maxf(float(KINDS[_kind]["len"]), 0.1), 0.0, 1.0)
			return maxf(0.0, sin(_t * 26.0)) * 0.09 * k * (0.5 + 0.5 * severity()) + 0.04 * k
	return 0.0

## The warning. (Public so the tests and the demo can start one.)
func begin_tell() -> void:
	if state != State.IDLE:
		return
	state = State.TELL
	_t = 0.0
	SFX.play("breath_catch", -9.0, randf_range(0.95, 1.05))
	var hands: Node = _player.get("story_hands")
	if hands != null:
		hands.cover_mouth(true)
	_player.call("kick", 0.12)

func _start_hold() -> void:
	state = State.HOLD
	_t = 0.0
	SFX.play("stifle_strain", -10.0, randf_range(0.95, 1.05))

## Picks what it is and lets it out. `broke_out`: it was held to the limit, so it is louder.
func _burst(broke_out: bool) -> void:
	var t := severity()
	var held := state == State.HOLD
	_kind = _forced_kind if _forced_kind != "" else _pick_kind(t, held)
	_forced_kind = ""
	_loud = loudness_now() * float(KINDS[_kind]["loud"]) * (BREAKOUT_LOUDER if broke_out else 1.0)
	_broke_out = broke_out
	state = State.BURST
	_t = 0.0
	_burst_left = float(KINDS[_kind]["len"])
	_second_done = false
	bursts += 1
	last_kind = _kind
	last_loudness = _loud
	last_broke_out = broke_out
	var db := lerpf(-15.0, -4.0, clampf((_loud - LOUD_MILD * 0.5) / (LOUD_SEVERE * BREAKOUT_LOUDER - LOUD_MILD * 0.5), 0.0, 1.0))
	SFX.play(_kind, db, randf_range(0.94, 1.06))
	GameState.emit_noise(_player.global_position, _loud, _kind)
	_player.call("kick", 0.3 + 0.5 * t + (0.3 if broke_out else 0.0))

## A fit's second wave.
func _burst_step() -> void:
	if _kind == "cough_fit" and not _second_done and _burst_left < float(KINDS[_kind]["len"]) - 1.0:
		_second_done = true
		GameState.emit_noise(_player.global_position, _loud * 0.85, "cough_fit")
		_player.call("kick", 0.4)

func _end_burst() -> void:
	state = State.IDLE
	_timer = _roll_interval()
	var hands: Node = _player.get("story_hands")
	if hands != null:
		hands.cover_mouth(false)

## Mild: sniffs and the odd cough. Bad: coughs, retching, and fits. Held back and let go: always
## something with a bark in it.
func _pick_kind(t: float, held: bool) -> String:
	var w := {"sniff": 0.6 - 0.5 * t, "cough": 0.4 + 0.2 * t, "retch": maxf(0.0, t - 0.35) * 1.4, "cough_fit": maxf(0.0, t - 0.55) * 1.6}
	if held:
		w["sniff"] = 0.0
		w["cough"] += 0.3
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "cough"

## Straight to a burst, for the tests and the demo: now, of this kind ("" for whatever it would be).
func force_burst(kind := "") -> void:
	if state != State.IDLE:
		return
	begin_tell()
	_t = TELL_TIME
	if kind != "":
		# One-shot: the pick is made when it lets go.
		_forced_kind = kind
