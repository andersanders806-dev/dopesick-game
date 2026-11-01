extends Node
## The Richter 8.0 surge: now and then the street shakes and the dead come out of everywhere. The
## logic side (fx/Quake.gd shows it from the signals):
##
##   surge_warning   SURGE_WARNING seconds before the quake: the build-up (rumble, lights, alarms)
##   surge_started   the quake: 25 to 40 of the dead, mostly runners, erupt from the ground, the
##                   fire escapes, the roofs and the shop fronts all round the player within
##                   ~10 s; double points from now
##   surge_ended     the last of them is out (the round cannot end until then); double points
##                   last LINGER seconds more
##
## It comes every 3 or 4 rounds (the first in round 3 or 4), and now and then at random in a round
## of its own (a rare event, never within 2 rounds of the last). The surge's dead are on top of the
## round's own and are let out whatever the alive cap says, up to ZombieMode.SURGE_HARD_CAP in all;
## the round's own wait while it lasts.
##
## Child of the block, next to the spawner. `time_scale` shortens every wait (tests).

signal spawned(zombie: Node)

enum Phase { IDLE, WARNING, QUAKE, LINGER }

const SURGE_TIME := 10.0
const LINGER := 8.0
const COUNT := Vector2i(25, 40)
const RUNNER_SHARE := 0.8
const FIRST_ROUND := Vector2i(3, 4)
const INTERVAL := Vector2i(3, 4)
## A round from 2 on has this chance of a surge of its own, if the last one was 3+ rounds ago.
const RANDOM_CHANCE := 0.1
const RANDOM_MIN_GAP := 3
## Seconds into the round a planned surge goes off.
const PLAN_DELAY := Vector2(6.0, 14.0)
const RANDOM_DELAY := Vector2(10.0, 30.0)
## A surge zombie that cannot come out (the hard cap) is tried again until the window plus this.
const GRACE := 3.0

var spawner: Node
var enabled := true
var time_scale := 1.0
var phase: Phase = Phase.IDLE
var rng := RandomNumberGenerator.new()
## The round the next scheduled surge belongs to, and the last one that had one.
var next_round := 3
var last_round := -99
## Seconds until a planned surge goes off (negative: none planned).
var plan_in := -1.0
## This surge: how many, how many are out, the times they come at, the kinds.
var total := 0
var released := 0
var times: Array[float] = []
var kinds: Array[String] = []
var surges := 0
var entrance_counts := {}
var _t := 0.0
var _clock := 0.0

func _ready() -> void:
	name = "ZombieSurge"
	add_to_group("zombie_surge")
	rng.randomize()
	next_round = rng.randi_range(FIRST_ROUND.x, FIRST_ROUND.y)
	ZombieMode.round_started.connect(_on_round_started)

func _on_round_started(r: int) -> void:
	if r <= 1:
		# A new run.
		next_round = rng.randi_range(FIRST_ROUND.x, FIRST_ROUND.y)
		last_round = -99
		plan_in = -1.0
	if plan_in >= 0.0 or phase != Phase.IDLE:
		return
	if r >= next_round:
		plan_in = rng.randf_range(PLAN_DELAY.x, PLAN_DELAY.y) * time_scale
	elif r >= 2 and r - last_round >= RANDOM_MIN_GAP and rng.randf() < RANDOM_CHANCE:
		plan_in = rng.randf_range(RANDOM_DELAY.x, RANDOM_DELAY.y) * time_scale

## How many a surge in round `r` lets out: 25 at the start, more later, never over 40.
func surge_size(r: int) -> int:
	return clampi(COUNT.x + int(r * 1.2) + rng.randi_range(0, 4), COUNT.x, COUNT.y)

## Starts a surge now (the warning first). False if one is on already or the run is not.
func trigger(count := -1) -> bool:
	if phase != Phase.IDLE or not ZombieMode.active or ZombieMode.over:
		return false
	total = count if count > 0 else surge_size(ZombieMode.round)
	released = 0
	plan_in = -1.0
	var runners := int(round(total * RUNNER_SHARE))
	kinds = []
	for i in total:
		kinds.append("runner" if i < runners else "walker")
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	# Front-loaded: the ground goes at once, then the rest keep coming.
	times = []
	for i in total:
		var u := (float(i) + rng.randf()) / float(total)
		times.append(SURGE_TIME * pow(u, 1.35) * time_scale)
	times.sort()
	entrance_counts = {}
	ZombieMode.surge_busy = true
	ZombieMode.surge_count = total
	phase = Phase.WARNING
	_t = ZombieMode.SURGE_WARNING * time_scale
	ZombieMode.surge_warning.emit()
	return true

func _process(delta: float) -> void:
	if not enabled or (spawner != null and not spawner.enabled):
		return
	if ZombieMode.over or not ZombieMode.active:
		if phase != Phase.IDLE:
			_abort()
		return
	match phase:
		Phase.IDLE:
			if plan_in >= 0.0:
				plan_in -= delta
				if plan_in <= 0.0 and not ZombieMode.tsunami_active:
					trigger()
		Phase.WARNING:
			_t -= delta
			if _t <= 0.0:
				_begin_quake()
		Phase.QUAKE:
			_clock += delta
			_release_due()
			var window := (SURGE_TIME + GRACE) * time_scale
			if released >= total or _clock >= window:
				_end_quake()
		Phase.LINGER:
			_t -= delta
			if _t <= 0.0:
				ZombieMode.surge_active = false
				phase = Phase.IDLE

func _begin_quake() -> void:
	phase = Phase.QUAKE
	_clock = 0.0
	surges += 1
	ZombieMode.surge_active = true
	ZombieMode.surge_started.emit()

## Lets out everyone whose time has come, as far as the hard cap allows.
func _release_due() -> void:
	while released < total and times[released] <= _clock:
		if spawner.alive() >= ZombieMode.SURGE_HARD_CAP:
			return
		var kind := kinds[released]
		var e: Dictionary = spawner._pick_entrance(spawner.Entrances.SURGE_WEIGHTS) if spawner._entrances_ready else {}
		var z: CharacterBody3D
		if e.is_empty():
			z = spawner.spawn_one(kind)
			if z != null:
				entrance_counts["plain"] = int(entrance_counts.get("plain", 0)) + 1
		else:
			z = spawner.spawn_entrance(kind, e)
			if z != null:
				entrance_counts[e["type"]] = int(entrance_counts.get(e["type"], 0)) + 1
		released += 1
		if z != null:
			spawned.emit(z)

func _end_quake() -> void:
	phase = Phase.LINGER
	_t = LINGER * time_scale
	last_round = ZombieMode.round
	next_round = ZombieMode.round + rng.randi_range(INTERVAL.x, INTERVAL.y)
	ZombieMode.surge_busy = false
	ZombieMode.surge_ended.emit()

func _abort() -> void:
	phase = Phase.IDLE
	plan_in = -1.0
	ZombieMode.surge_busy = false
	ZombieMode.surge_active = false
