extends Node
## The DualSense, driven directly: adaptive triggers, lightbar and player LEDs for Dead Block.
## Godot only reaches the two rumble motors (player/PadRumble.gd keeps doing that); the rest of the
## controller is a HID device, so this autoload writes the output report itself.
##
## How it gets there. Godot's FileAccess refuses to open anything that is not a regular file (it
## cannot even open /dev/null), so the writes go through a tiny child process started with
## OS.execute_with_pipe: `dd bs=<report size> iflag=fullblock of=/dev/hidrawN`. dd writes every
## block it reads as one write(), which is what a HID report needs. When the game goes away
## (quit, crash, kill -9) the pipe closes, dd ends, and the shell runs the last command of that
## line: a reset report (triggers off, lightbar and player LED back to default), so the controller
## is never left stiff. The flatpak has devices=all and the user has an ACL on the node.
##
## Report layouts (checked against the Linux driver drivers/hid/hid-playstation.c, nowrep/dualsensectl
## main.c, and the layout every DualSense library shares):
##   USB   0x02, 63 bytes: [0] id, [1..47] common block, rest zero.
##   BT    0x31, 78 bytes: [0] id, [1] seq<<4, [2] tag 0x10, [3..49] common block, 24 zero,
##         [74..77] CRC32 (little endian) of bytes 0..73 with the seed byte 0xA2 in front.
##   common block (47 bytes): 0 valid_flag0 (0x04 right trigger, 0x08 left trigger), 1 valid_flag1
##         (0x04 lightbar, 0x10 player LEDs), 10..20 right trigger (mode + 10 params), 21..31 left
##         trigger, 38 valid_flag2, 43 player LEDs, 44..46 lightbar R G B.
## Trigger modes: Off 0x05, Feedback 0x21, Weapon 0x25, Vibration 0x26. Zones are the 10 steps of
## the trigger's travel, strengths 1..8 are sent as 0..7 in 3 bits per zone.
##
## Everything goes through write_report(), so the tests give `sink` a Callable and read the bytes.
## With the settings Adaptive triggers and Lightbar effects both off nothing is ever written.

const VENDOR := 0x054C
const PRODUCTS := [0x0CE6, 0x0DF2]
const USB_SIZE := 63
const BT_SIZE := 78
const OUT_USB := 0x02
const OUT_BT := 0x31
const BT_TAG := 0x10
const CRC_SEED := 0xA2

const F0_RIGHT := 0x04
const F0_LEFT := 0x08
const F1_LIGHTBAR := 0x04
const F1_PLAYER_LEDS := 0x10

## Offsets inside the common block.
const C_FLAG0 := 0
const C_FLAG1 := 1
const C_RIGHT := 10
const C_LEFT := 21
const C_LEDS := 43
const C_RGB := 44
const TRIGGER_LEN := 11

const T_OFF := 0x05
const T_FEEDBACK := 0x21
const T_WEAPON := 0x25
const T_VIBRATION := 0x26

const DEFAULT_RGB := Vector3i(0, 0, 255)
const DEFAULT_LEDS := 0x04
const AMBER := Color(0.47, 0.27, 0.03)
const RED := Color(1.0, 0.0, 0.0)
const TEAL := Color(0.0, 0.75, 0.85)
const GAME_OVER := Color(0.3, 0.0, 0.0)

## Seconds between two reports at the most (a lightbar pulse changes every frame).
const MIN_INTERVAL := 0.025
## Shot to shot: how long an automatic gun's trigger keeps vibrating after its last round.
const FIRE_HOLD := 0.2
const STREAK_KILLS := 3
const STREAK_WINDOW := 2.5

## [start zone, end zone, strength] of the Weapon effect (the resistance, then the break) per gun
## family; the automatic guns have a light Feedback and a Vibration at their rate while firing:
## [feedback position, feedback strength, vibration position, vibration amplitude].
const WEAPON := {
	"pistol": [4, 6, 5], "magnum": [3, 6, 7], "shotgun": [3, 7, 8], "sniper": [2, 8, 8],
	"wonder": [3, 6, 6],
}
const WEAPON_DEFAULT := [4, 7, 5]
const AUTO := {
	"smg": [4, 2, 3, 4], "ar": [4, 3, 3, 5], "lmg": [3, 4, 2, 7],
}
const AUTO_DEFAULT := [4, 2, 3, 4]
## L2: [position, strength] of the scope's weight.
const ADS := {"sniper": [2, 4]}
const ADS_DEFAULT := [3, 2]

## Tests set these: no process, no device; the bytes go to `sink`.
var sink := Callable()
var manual := false
var bt := false
## Allows the real device in a headless run (the demo; tests of other things must not reach it).
var allow_headless := false

var holder: Node
var writes := 0
var device_path := ""
var is_open := false

var _pipe := {}
var _io: FileAccess
var _t := 0.0
var _since_send := 1.0
var _lb_acc := 0.0
var _retry := 0.0
var _seq := 0
var _focused := true
var _touched := false
var _sent_r := PackedByteArray()
var _sent_l := PackedByteArray()
var _sent_rgb := Vector3i(-1, -1, -1)
var _sent_leds := -1
var _fire_t := 0.0
var _burst_t := 0.0
var _burst_amp := 1.0
var _quake := 0
var _quake_cd := 0.0
var _hp := 100.0
var _hurt := 0.0
var _flash := 0.0
var _flash_rate := 8.0
var _kills: Array[float] = []
var _flicker := 1.0
var _flicker_cd := 0.0
var _tpulse := 0.0
var _tsunami: Node
var _drowned: Array = []
var _charge_seen := {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "DualSense"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()

func _ready() -> void:
	ZombieMode.health_changed.connect(_on_health)
	ZombieMode.surge_warning.connect(_on_surge_warning)
	ZombieMode.surge_started.connect(_on_surge_started)
	ZombieMode.surge_ended.connect(_on_surge_ended)
	ZombieMode.round_started.connect(func(_r: int): _since_send = 1.0)
	get_tree().node_added.connect(_watch)

func _process(delta: float) -> void:
	if not manual:
		tick(delta)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			reset()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			shutdown()

func _exit_tree() -> void:
	shutdown()

# --- Reports --------------------------------------------------------------------

## CRC32 (the zlib one) of data[0..length), with `seed` as a byte in front when it is >= 0.
static func crc32(data: PackedByteArray, length: int, seed := -1) -> int:
	var table := _crc_table()
	var crc := 0xFFFFFFFF
	if seed >= 0:
		crc = table[(crc ^ seed) & 0xFF] ^ (crc >> 8)
	for i in length:
		crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8)
	return (~crc) & 0xFFFFFFFF

static var _table: PackedInt64Array = PackedInt64Array()

static func _crc_table() -> PackedInt64Array:
	if _table.is_empty():
		_table.resize(256)
		for i in 256:
			var c := i
			for _k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) != 0 else (c >> 1)
			_table[i] = c
	return _table

## One output report. `right` and `left` are 11-byte trigger blocks, only written when their flag
## is set in `f0`; `rgb` and `leds` when `f1` has the lightbar / player LED bit.
static func build_report(use_bt: bool, seq: int, f0: int, f1: int, right: PackedByteArray, left: PackedByteArray, rgb: Vector3i, leds: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(BT_SIZE if use_bt else USB_SIZE)
	var o := 1
	if use_bt:
		r[0] = OUT_BT
		r[1] = (seq & 0x0F) << 4
		r[2] = BT_TAG
		o = 3
	else:
		r[0] = OUT_USB
	r[o + C_FLAG0] = f0
	r[o + C_FLAG1] = f1
	if (f0 & F0_RIGHT) != 0:
		for i in mini(TRIGGER_LEN, right.size()):
			r[o + C_RIGHT + i] = right[i]
	if (f0 & F0_LEFT) != 0:
		for i in mini(TRIGGER_LEN, left.size()):
			r[o + C_LEFT + i] = left[i]
	if (f1 & F1_LIGHTBAR) != 0:
		r[o + C_RGB] = clampi(rgb.x, 0, 255)
		r[o + C_RGB + 1] = clampi(rgb.y, 0, 255)
		r[o + C_RGB + 2] = clampi(rgb.z, 0, 255)
	if (f1 & F1_PLAYER_LEDS) != 0:
		r[o + C_LEDS] = leds
	if use_bt:
		var crc := crc32(r, BT_SIZE - 4, CRC_SEED)
		for i in 4:
			r[BT_SIZE - 4 + i] = (crc >> (8 * i)) & 0xFF
	return r

## The report that puts everything back: triggers off, lightbar and player LED default.
static func reset_report(use_bt: bool, seq := 0) -> PackedByteArray:
	return build_report(use_bt, seq, F0_RIGHT | F0_LEFT, F1_LIGHTBAR | F1_PLAYER_LEDS, eff_off(), eff_off(), DEFAULT_RGB, DEFAULT_LEDS)

# --- Trigger effects -------------------------------------------------------------

static func eff_off() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(TRIGGER_LEN)
	b[0] = T_OFF
	return b

## strengths: 10 values 0..8 (0: that zone is free). Feedback and Vibration pack them the same way.
static func _zones(mode: int, strengths: Array, frequency: int) -> PackedByteArray:
	var strength_zones := 0
	var active := 0
	for i in 10:
		var s: int = clampi(int(strengths[i]), 0, 8)
		if s > 0:
			strength_zones |= ((s - 1) & 0x07) << (3 * i)
			active |= 1 << i
	var b := eff_off()
	b[0] = mode
	b[1] = active & 0xFF
	b[2] = (active >> 8) & 0xFF
	b[3] = strength_zones & 0xFF
	b[4] = (strength_zones >> 8) & 0xFF
	b[5] = (strength_zones >> 16) & 0xFF
	b[6] = (strength_zones >> 24) & 0xFF
	b[9] = frequency & 0xFF
	return b

## Resistance of `strength` (1..8) from zone `position` (0..9) to the end of the travel.
static func eff_feedback(position: int, strength: int) -> PackedByteArray:
	var s: Array = []
	for i in 10:
		s.append(clampi(strength, 1, 8) if i >= clampi(position, 0, 9) else 0)
	return _zones(T_FEEDBACK, s, 0)

## A trigger pull that resists from zone `start` (2..7) to `end` (start+1..8) and then breaks.
static func eff_weapon(start: int, end: int, strength: int) -> PackedByteArray:
	var a := clampi(start, 2, 7)
	var z := clampi(end, a + 1, 8)
	var zones := (1 << a) | (1 << z)
	var b := eff_off()
	b[0] = T_WEAPON
	b[1] = zones & 0xFF
	b[2] = (zones >> 8) & 0xFF
	b[3] = clampi(strength, 1, 8) - 1
	return b

## The trigger buzzes at `frequency` Hz with `amplitude` (1..8) from zone `position`.
static func eff_vibration(position: int, amplitude: int, frequency: int) -> PackedByteArray:
	var s: Array = []
	for i in 10:
		s.append(clampi(amplitude, 1, 8) if i >= clampi(position, 0, 9) else 0)
	return _zones(T_VIBRATION, s, clampi(frequency, 1, 255))

## A strength 1..8 scaled by the Trigger strength setting `k` (0.3 .. 1.0).
static func scaled(s: int, k: float) -> int:
	return clampi(roundi(float(s) * k), 1, 8)

## R2 for `data` as `{effect}`: the effect for the gun, `firing` for an automatic one mid-burst.
static func right_for(data: Resource, firing: bool, k: float) -> PackedByteArray:
	if data == null or data.get("melee") == true:
		return eff_off()
	var fam: String = data.call("family")
	if data.get("auto") == true:
		var p: Array = AUTO.get(fam, AUTO_DEFAULT)
		if firing:
			var hz := clampi(roundi(float(data.get("rpm")) / 60.0), 1, 255)
			return eff_vibration(p[2], scaled(p[3], k), hz)
		return eff_feedback(p[0], scaled(p[1], k))
	var w: Array = WEAPON.get(fam, WEAPON_DEFAULT)
	return eff_weapon(w[0], w[1], scaled(w[2], k))

## L2: the scope's weight.
static func left_for(data: Resource, k: float) -> PackedByteArray:
	if data == null or data.get("melee") == true:
		return eff_off()
	var p: Array = ADS.get(data.call("family"), ADS_DEFAULT)
	return eff_feedback(p[0], scaled(p[1], k))

## A short buzz on both triggers.
static func eff_burst(amp: float) -> PackedByteArray:
	return eff_vibration(0, clampi(roundi(8.0 * amp), 1, 8), 40)

## The five player LEDs for round `r` (1 lit, then 2 ... 5, then round again).
static func round_leds(r: int) -> int:
	var table := [0x04, 0x04, 0x0A, 0x15, 0x1B, 0x1F]
	return table[((maxi(r, 1) - 1) % 5) + 1]

## Pulses per second of the tsunami's glow: slow, quicker as the sea nears, quickest in the last 10 s.
static func tsunami_rate(remaining: float, duration: float) -> float:
	if remaining <= 10.0:
		return 3.4
	return lerpf(0.7, 1.8, 1.0 - clampf(remaining / maxf(duration, 1.0), 0.0, 1.0))

# --- Device ----------------------------------------------------------------------

## {bus, vendor, product} out of a hidraw uevent's HID_ID line, or {}.
static func parse_hid_id(uevent: String) -> Dictionary:
	for line in uevent.split("\n"):
		if line.begins_with("HID_ID="):
			var parts := line.substr(7).split(":")
			if parts.size() == 3:
				return {"bus": parts[0].hex_to_int(), "vendor": parts[1].hex_to_int(), "product": parts[2].hex_to_int()}
	return {}

## The first DualSense / DualSense Edge in /sys/class/hidraw: {path, bt, name} or {}.
static func find_device(root := "/sys/class/hidraw", dev := "/dev") -> Dictionary:
	var dir := DirAccess.open(root)
	if dir == null:
		return {}
	var names: Array[String] = []
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n.begins_with("hidraw"):
			names.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for node in names:
		var info := parse_hid_id(FileAccess.get_file_as_string("%s/%s/device/uevent" % [root, node]))
		if info.is_empty() or info["vendor"] != VENDOR or not PRODUCTS.has(info["product"]):
			continue
		return {"path": "%s/%s" % [dev, node], "bt": info["bus"] == 0x0005, "name": "DualSense Edge" if info["product"] == 0x0DF2 else "DualSense"}
	return {}

## The shell line the child runs: copy report-sized blocks to the node, then the reset report.
static func shell_command(path: String, size: int, reset: PackedByteArray) -> String:
	var esc := ""
	for b in reset:
		esc += "\\%03o" % b
	return "dd bs=%d iflag=fullblock of='%s' 2>/dev/null; printf '%s' >> '%s' 2>/dev/null" % [size, path, esc, path]

func _can_use_hardware() -> bool:
	if sink.is_valid():
		return true
	if DisplayServer.get_name() == "headless" and not allow_headless:
		return false
	return not Engine.get_meta("sandbox", false) or allow_headless

## Opens the child process on the controller, if there is one. False: nothing to drive.
func open_device() -> bool:
	if sink.is_valid():
		is_open = true
		return true
	if is_open:
		return true
	if not _can_use_hardware():
		return false
	var dev := find_device()
	if dev.is_empty():
		return false
	bt = dev["bt"]
	device_path = dev["path"]
	var cmd := shell_command(device_path, BT_SIZE if bt else USB_SIZE, reset_report(bt))
	var r := OS.execute_with_pipe("/bin/sh", ["-c", cmd])
	if r.is_empty():
		return false
	_pipe = r
	_io = r["stdio"]
	is_open = true
	return true

func _close_pipe() -> void:
	if _io != null:
		_io.close()
	if _pipe.has("stderr") and _pipe["stderr"] != null:
		(_pipe["stderr"] as FileAccess).close()
	_io = null
	_pipe = {}
	is_open = false

## The one place a report goes out.
func write_report(b: PackedByteArray) -> bool:
	if sink.is_valid():
		writes += 1
		sink.call(b)
		return true
	if _io == null:
		return false
	if not OS.is_process_running(int(_pipe["pid"])):
		_close_pipe()
		_retry = 5.0
		return false
	_io.store_buffer(b)
	_io.flush()
	writes += 1
	return _io.get_error() == OK

# --- State from the game -----------------------------------------------------------

func _watch(n: Node) -> void:
	if n.has_signal("charged") and "charge" in n:
		_drowned.append(n)

func _attach_holder() -> void:
	if holder != null and is_instance_valid(holder):
		return
	holder = get_tree().get_first_node_in_group("weapon_holder")
	if holder == null:
		return
	holder.connect("fired", _on_fired)
	holder.connect("hit", _on_hit)
	holder.connect("melee_swung", func(found: bool): burst(0.14, 0.9 if found else 0.4))
	_drowned.clear()
	for n in get_tree().get_nodes_in_group("zombies"):
		_watch(n)

func _on_fired() -> void:
	_fire_t = FIRE_HOLD

func _on_hit(part: String, killed: bool) -> void:
	if killed:
		_kills.append(_t)
		while _kills.size() > 0 and _t - _kills[0] > STREAK_WINDOW:
			_kills.pop_front()
		if _kills.size() >= STREAK_KILLS:
			_flash = 1.0
			_flash_rate = 4.0
			_kills.clear()
			return
	if part == "head":
		_flash = maxf(_flash, 0.8)
		_flash_rate = 12.0

func _on_health(hp: float) -> void:
	if hp < _hp - 0.01:
		var drop := _hp - hp
		_hurt = clampf(0.55 + drop / 40.0, 0.55, 1.0)
		burst(0.18, clampf(0.5 + drop / 40.0, 0.5, 1.0))
	_hp = hp

func _on_surge_warning() -> void:
	_quake = 1
	burst(0.12, 0.4)

func _on_surge_started() -> void:
	_quake = 2
	_quake_cd = 0.0

func _on_surge_ended() -> void:
	_quake = 0

## Both triggers buzz for `seconds`, at `amp` (0..1) of full.
func burst(seconds: float, amp := 1.0) -> void:
	_burst_amp = amp if _burst_t <= 0.0 else maxf(_burst_amp, amp)
	_burst_t = maxf(_burst_t, seconds)

# --- Frame -------------------------------------------------------------------------

func _wants_hardware() -> bool:
	return (Graphics.ds_triggers or Graphics.ds_lightbar) and ZombieMode.active and _focused

## One frame. The autoload calls it from _process; tests call it with their own delta.
func tick(delta: float) -> void:
	_t += delta
	_since_send += delta
	_lb_acc += delta
	_fire_t = maxf(_fire_t - delta, 0.0)
	_burst_t = maxf(_burst_t - delta, 0.0)
	_hurt = maxf(_hurt - delta / 0.9, 0.0)
	_flash = maxf(_flash - delta * _flash_rate, 0.0)
	_retry = maxf(_retry - delta, 0.0)
	if not _wants_hardware():
		if _touched:
			reset()
		if not ZombieMode.active and is_open and not sink.is_valid():
			_close_pipe()
		_hp = ZombieMode.health
		return
	if not is_open:
		if _retry > 0.0:
			return
		if not open_device():
			_retry = 5.0
			return
	# A new run starts at full health without a signal.
	_hp = maxf(_hp, ZombieMode.health)
	_attach_holder()
	_watch_drowned()
	_watch_tsunami()
	if _quake == 2:
		_quake_cd -= delta
		if _quake_cd <= 0.0:
			_quake_cd = 0.5
			burst(0.12, 0.7)
	if _since_send < MIN_INTERVAL:
		return
	_send()

func _watch_drowned() -> void:
	for d in _drowned.duplicate():
		if not is_instance_valid(d):
			_drowned.erase(d)
			_charge_seen.erase(d)
			continue
		var c: int = d.get("charge")
		var before: int = _charge_seen.get(d, 0)
		if c != before:
			_charge_seen[d] = c
			if c == 1:
				burst(0.3, 0.8)
			elif c == 2:
				burst(0.18, 1.0)

func _watch_tsunami() -> void:
	if not ZombieMode.tsunami_active:
		_tsunami = null
		return
	if _tsunami == null or not is_instance_valid(_tsunami):
		_tsunami = get_tree().get_first_node_in_group("tsunami")
		if _tsunami != null and _tsunami.has_signal("wave_hit"):
			_tsunami.connect("wave_hit", func(): burst(0.5, 1.0))

## The triggers now: {r, l}.
func desired_triggers() -> Dictionary:
	var off := eff_off()
	if not Graphics.ds_triggers or not ZombieMode.active or ZombieMode.over or get_tree().paused:
		return {"r": off, "l": off}
	var k: float = Graphics.ds_trigger_strength
	if _burst_t > 0.0:
		var b := eff_burst(_burst_amp * k)
		return {"r": b, "l": b}
	if holder == null or not is_instance_valid(holder):
		return {"r": off, "l": off}
	var data: Resource = holder.get("current")
	if data == null:
		return {"r": off, "l": off}
	var feel = holder.get("feel")
	if feel != null and float(feel.get("sprint_blend")) > 0.5:
		return {"r": off, "l": off}
	if holder.get("reloading") == true:
		return {"r": off, "l": off}
	var empty: bool = int(holder.get("mag")) <= 0
	var r := off if empty else right_for(data, _fire_t > 0.0, k)
	return {"r": r, "l": left_for(data, k)}

## The lightbar now (0..1 per channel).
func lightbar_color(delta := 0.0) -> Color:
	if not Graphics.ds_lightbar:
		return Color(DEFAULT_RGB.x / 255.0, DEFAULT_RGB.y / 255.0, DEFAULT_RGB.z / 255.0)
	var c := AMBER
	if _quake > 0:
		_flicker_cd -= delta
		if _flicker_cd <= 0.0:
			if _quake == 2:
				_flicker = _rng.randf_range(0.08, 1.0)
				_flicker_cd = _rng.randf_range(0.03, 0.12)
			else:
				_flicker = 1.0 if _rng.randf() > 0.4 else _rng.randf_range(0.1, 0.4)
				_flicker_cd = _rng.randf_range(0.05, 0.25)
		c = AMBER.lerp(Color(1.0, 0.85, 0.5), 0.5 if _quake == 2 else 0.0) * _flicker
	if ZombieMode.tsunami_active:
		var rem := 120.0
		var dur := 120.0
		if _tsunami != null and is_instance_valid(_tsunami):
			rem = float(_tsunami.get("remaining"))
			dur = float(_tsunami.get("duration"))
		_tpulse += delta * tsunami_rate(rem, dur) * TAU
		c = TEAL * (0.2 + 0.8 * (0.5 + 0.5 * sin(_tpulse)))
	if ZombieMode.over:
		c = GAME_OVER
	var hurt := _hurt
	if _hp < 35.0 and not ZombieMode.over:
		hurt = maxf(hurt, 0.25 + 0.25 * (0.5 + 0.5 * sin(_t * TAU * 1.4)))
	c = c.lerp(RED, hurt)
	c = c.lerp(Color.WHITE, clampf(_flash, 0.0, 1.0))
	return c

func _rgb_of(c: Color) -> Vector3i:
	return Vector3i(clampi(roundi(c.r * 255.0), 0, 255), clampi(roundi(c.g * 255.0), 0, 255), clampi(roundi(c.b * 255.0), 0, 255))

func _send() -> void:
	var trig := desired_triggers()
	var rgb := _rgb_of(lightbar_color(_lb_acc))
	_lb_acc = 0.0
	var leds := round_leds(ZombieMode.round) if Graphics.ds_lightbar else DEFAULT_LEDS
	var f0 := 0
	var f1 := 0
	# A feature that is off and was never touched is left alone (the controller keeps its own).
	var trig_in_use := Graphics.ds_triggers or not _sent_r.is_empty()
	var bar_in_use := Graphics.ds_lightbar or _sent_leds >= 0
	if trig_in_use and trig["r"] != _sent_r:
		f0 |= F0_RIGHT
	if trig_in_use and trig["l"] != _sent_l:
		f0 |= F0_LEFT
	if bar_in_use and rgb != _sent_rgb:
		f1 |= F1_LIGHTBAR
	if bar_in_use and leds != _sent_leds:
		f1 |= F1_PLAYER_LEDS
	if f0 == 0 and f1 == 0:
		return
	_since_send = 0.0
	if write_report(build_report(bt, _seq, f0, f1, trig["r"], trig["l"], rgb, leds)):
		_seq = (_seq + 1) & 0x0F
		_touched = true
		if (f0 & F0_RIGHT) != 0:
			_sent_r = trig["r"]
		if (f0 & F0_LEFT) != 0:
			_sent_l = trig["l"]
		if (f1 & F1_LIGHTBAR) != 0:
			_sent_rgb = rgb
		if (f1 & F1_PLAYER_LEDS) != 0:
			_sent_leds = leds

## Triggers off, lightbar and player LED default, now.
func reset() -> void:
	if _touched and is_open:
		write_report(reset_report(bt, _seq))
		_seq = (_seq + 1) & 0x0F
	_touched = false
	_sent_r = PackedByteArray()
	_sent_l = PackedByteArray()
	_sent_rgb = Vector3i(-1, -1, -1)
	_sent_leds = -1
	_fire_t = 0.0
	_burst_t = 0.0
	_flash = 0.0
	_hurt = 0.0
	_quake = 0

## reset(), and the child process is let go.
func shutdown() -> void:
	reset()
	if is_open and not sink.is_valid():
		_close_pipe()
