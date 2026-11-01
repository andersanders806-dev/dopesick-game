extends RefCounted
## How many of the dead may be on the block at once, between ZombieMode.MAX_ALIVE_MIN and _MAX:
## it climbs while the frames come in quickly with the horde at its size, and drops when they
## don't. Frame times are collected over WINDOW seconds, then judged once (so one hitch is not a
## verdict); it has to be good twice in a row to climb (hysteresis), and there is a band in the
## middle where nothing moves, so it does not hunt up and down.
##
## Pure logic: feed(ms, alive, delta_s) from the spawner's _process, read `cap`. The tests drive
## it with made-up frame times.

## Seconds of frames per verdict.
const WINDOW := 3.0
## Judged on the window's mean frame time and the share of frames over 33 ms.
## Below GOOD_MS (about 54 fps) it can climb; above BAD_MS (about 45 fps) it must drop; in
## between it holds.
const GOOD_MS := 18.5
const BAD_MS := 22.0
const SLOW_MS := 33.0
const GOOD_SLOW_SHARE := 0.01
const BAD_SLOW_SHARE := 0.06
## Steps: down fast, up slow.
const STEP_DOWN := 4
const STEP_UP := 2
## Good windows in a row before it climbs; seconds it stays put after a drop.
const GOOD_NEEDED := 2
const HOLD_AFTER_DROP := 6.0
## One frame longer than this (a load, a pause, a window drag) is not the horde's doing.
const IGNORE_MS := 250.0

var cap := 32
var min_cap := 24
var max_cap := 48
var enabled := true
## How many verdicts went each way (the tests read them).
var raised := 0
var lowered := 0
var last_mean := 0.0
var last_slow_share := 0.0

var _sum := 0.0
var _n := 0
var _slow := 0
var _clock := 0.0
var _good_run := 0
var _hold := 0.0

func _init(start := 32, lo := 24, hi := 48) -> void:
	min_cap = lo
	max_cap = hi
	cap = clampi(start, lo, hi)

## One drawn frame took `ms`; `alive` of the dead are out; `delta_s` is the time it covers.
## Returns true on the frame the cap changed.
func feed(ms: float, alive: int, delta_s: float) -> bool:
	if not enabled:
		return false
	_hold = maxf(_hold - delta_s, 0.0)
	_clock += delta_s
	if ms < IGNORE_MS:
		_sum += ms
		_n += 1
		if ms > SLOW_MS:
			_slow += 1
	if _clock < WINDOW:
		return false
	var changed := _judge(alive)
	_clock = 0.0
	_sum = 0.0
	_n = 0
	_slow = 0
	return changed

func _judge(alive: int) -> bool:
	if _n < 10:
		return false
	last_mean = _sum / float(_n)
	last_slow_share = float(_slow) / float(_n)
	if last_mean > BAD_MS or last_slow_share > BAD_SLOW_SHARE:
		_good_run = 0
		_hold = HOLD_AFTER_DROP
		var was := cap
		cap = maxi(cap - STEP_DOWN, min_cap)
		if cap != was:
			lowered += 1
			return true
		return false
	if last_mean < GOOD_MS and last_slow_share <= GOOD_SLOW_SHARE:
		# Only a window with the horde near the cap says anything about room for more.
		if alive >= cap - 3 and _hold <= 0.0:
			_good_run += 1
			if _good_run >= GOOD_NEEDED:
				_good_run = 0
				var was := cap
				cap = mini(cap + STEP_UP, max_cap)
				if cap != was:
					raised += 1
					return true
		return false
	# The middle band: neither.
	_good_run = 0
	return false
