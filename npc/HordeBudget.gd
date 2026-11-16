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
## Judged on the window's mean RENDER COST (the work a frame took, not the vsync wait: a healthy 60 Hz frame is
## 16.7 ms on the clock whatever it cost) and the share of frames over SLOW_MS on the clock.
## Below good_ms it can climb; above bad_ms it must drop; in between it holds.
## Laptop graphics (lean) use the tight numbers (the perf gate: 60 fps, no frame over 25 ms); every other GPU
## keeps the trunk numbers.
const GOOD_MS_LEAN := 17.3
const BAD_MS_LEAN := 18.6
const SLOW_MS_LEAN := 25.0
const GOOD_SLOW_SHARE := 0.01
const BAD_SLOW_SHARE_LEAN := 0.04
const GOOD_MS_DESKTOP := 18.5
const BAD_MS_DESKTOP := 22.0
const SLOW_MS_DESKTOP := 33.0
const BAD_SLOW_SHARE_DESKTOP := 0.06
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
var good_ms := GOOD_MS_DESKTOP
var bad_ms := BAD_MS_DESKTOP
var slow_ms := SLOW_MS_DESKTOP
var bad_slow_share := BAD_SLOW_SHARE_DESKTOP
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

func _init(start := 32, lo := 24, hi := 48, lean := false) -> void:
	min_cap = lo
	max_cap = hi
	cap = clampi(start, lo, hi)
	if lean:
		good_ms = GOOD_MS_LEAN
		bad_ms = BAD_MS_LEAN
		slow_ms = SLOW_MS_LEAN
		bad_slow_share = BAD_SLOW_SHARE_LEAN

## What the last frame cost to make, in ms, without the vsync wait: the larger of the GPU's render time and the
## CPU's (scripts + physics + the render thread's submit). -1 when the renderer does not measure (headless).
static func render_cost_ms() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return -1.0
	var rid := tree.root.get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid) \
		+ (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var cost := maxf(gpu, cpu)
	return cost if gpu > 0.0 else -1.0

## One drawn frame took `ms` on the clock (render_cost_ms of it, when known: the mean is judged on that);
## `alive` of the dead are out; `delta_s` is the time it covers. Returns true on the frame the cap changed.
func feed(ms: float, alive: int, delta_s: float, cost_ms := -1.0) -> bool:
	if not enabled:
		return false
	_hold = maxf(_hold - delta_s, 0.0)
	_clock += delta_s
	if ms < IGNORE_MS:
		_sum += cost_ms if cost_ms >= 0.0 else ms
		_n += 1
		if ms > slow_ms:
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
	if last_mean > bad_ms or last_slow_share > bad_slow_share:
		_good_run = 0
		_hold = HOLD_AFTER_DROP
		var was := cap
		cap = maxi(cap - STEP_DOWN, min_cap)
		if cap != was:
			lowered += 1
			return true
		return false
	if last_mean < good_ms and last_slow_share <= GOOD_SLOW_SHARE:
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
