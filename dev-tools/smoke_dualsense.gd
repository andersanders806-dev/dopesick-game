extends SceneTree
## The DualSense checks (autoload/DualSense.gd): the output report bytes for USB and Bluetooth against
## vectors made by an independent Python port of the layout in the Linux driver (hid-playstation.c) and
## dualsensectl, the trigger bytes per gun, a slack trigger on an empty magazine and while reloading and
## sprinting, the L2 weight, the lightbar when hurt / in a quake / in the tsunami, a reset when the mode
## is left or the window loses focus, nothing written with the settings off, and the child process that
## really writes (to a file standing in for the node).
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_dualsense.gd
## Loaded once the autoloads exist (a script run with -s compiles before them).
var DS: GDScript

const USB_A := "020c140000000000000000255000040000000000000021f803009224090000000000000000000000000000000a784608000000000000000000000000000000"
const BT_A := "3150100c140000000000000000255000040000000000000021f803009224090000000000000000000000000000000a784608000000000000000000000000000000000000000000000000e46a7082"
const USB_C := "020400000000000000000026f80300b66d1b00000b000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
const USB_D := "020c140000000000000000050000000000000000000005000000000000000000000000000000000000000000040000ff000000000000000000000000000000"
const BT_D := "3100100c140000000000000000050000000000000000000005000000000000000000000000000000000000000000040000ff000000000000000000000000000000000000000000000000efbfeb00"

var _failures := 0
var _sent: Array[PackedByteArray] = []
var _gfx: Node
var _zm: Node
var h: FakeHolder
var feel: FakeFeel

## Stands in for the WeaponHolder: the same signals and the few properties DualSense reads.
class FakeHolder extends Node:
	signal fired
	signal hit(part: String, killed: bool)
	signal melee_swung(found: bool)
	var current: Resource
	var mag := 10
	var reloading := false
	var aiming := false
	var feel: Node
	func _init() -> void:
		name = "FakeHolder"
		add_to_group("weapon_holder")

class FakeFeel extends Node:
	var sprint_blend := 0.0

class FakeTsunami extends Node:
	signal wave_hit
	var remaining := 100.0
	var duration := 120.0
	func _init() -> void:
		add_to_group("tsunami")

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	DS = load("res://autoload/DualSense.gd")
	_gfx = root.get_node("Graphics")
	_zm = root.get_node("ZombieMode")
	_run()
	print("\n%s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)

## A new stand-in holder (the old one goes), found by DualSense through the group like the real one.
func _fresh_holder(gun := "pistol") -> void:
	if h != null:
		h.free()
		feel.free()
	h = FakeHolder.new()
	feel = FakeFeel.new()
	h.feel = feel
	h.current = _gun(gun)
	root.add_child(h)
	root.add_child(feel)

func _gun(id: String) -> Resource:
	return load("res://weapons/%s.tres" % id)

## A DualSense of its own on the fake sink (the autoload never touches the controller in a headless run).
func _make(use_bt := false) -> Node:
	var d: Node = DS.new()
	d.manual = true
	d.bt = use_bt
	_sent.clear()
	d.sink = func(b: PackedByteArray): _sent.append(b)
	root.add_child(d)
	return d

func _flags(b: PackedByteArray, bt: bool) -> Array:
	var o := 3 if bt else 1
	return [b[o], b[o + 1]]

func _right(b: PackedByteArray, bt := false) -> PackedByteArray:
	var o: int = (3 if bt else 1) + DS.C_RIGHT
	return b.slice(o, o + 11)

func _left(b: PackedByteArray, bt := false) -> PackedByteArray:
	var o: int = (3 if bt else 1) + DS.C_LEFT
	return b.slice(o, o + 11)

func _rgb(b: PackedByteArray, bt := false) -> Vector3i:
	var o: int = (3 if bt else 1) + DS.C_RGB
	return Vector3i(b[o], b[o + 1], b[o + 2])

## Runs `d` for `seconds`, 60 fps; the reports it sent.
func _run_for(d: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		d.tick(1.0 / 60.0)

func _last() -> PackedByteArray:
	return _sent[_sent.size() - 1]

func _run() -> void:
	print("== DualSense: report bytes")
	_gfx.ds_triggers = true
	_gfx.ds_trigger_strength = 1.0
	_gfx.ds_lightbar = true
	_check(DS.crc32("123456789".to_ascii_buffer(), 9) == 0xCBF43926, "  CRC32 of '123456789' is the standard 0xCBF43926")
	_check(DS.crc32("123456789".to_ascii_buffer(), 9, 0xA2) == 0x63DA9F12, "  with the 0xA2 seed byte in front it is 0x63DA9F12 (zlib's)")
	_check(DS.eff_weapon(4, 6, 5).hex_encode() == "2550000400000000000000", "  Weapon 4..6 strength 5: zones 0x0050, strength-1 = 4")
	_check(DS.eff_feedback(3, 2).hex_encode() == "21f8030092240900000000", "  Feedback from zone 3 strength 2: zones 0x03f8, 3 bits per zone")
	_check(DS.eff_vibration(3, 4, 11).hex_encode() == "26f80300b66d1b00000b00", "  Vibration from zone 3 amplitude 4 at 11 Hz: frequency in param 9")
	_check(DS.eff_off().hex_encode() == "0500000000000000000000", "  Off is mode 0x05 and nothing else")
	var A := [0x0C, 0x14, DS.eff_weapon(4, 6, 5), DS.eff_feedback(3, 2), Vector3i(120, 70, 8), 0x0A]
	var usb: PackedByteArray = DS.build_report(false, 0, A[0], A[1], A[2], A[3], A[4], A[5])
	_check(usb.size() == 63 and usb[0] == 0x02 and usb.hex_encode() == USB_A, "  USB report 0x02, 63 bytes, flags/R2/L2/lightbar/LEDs match the vector")
	_check(usb[11] == 0x25 and usb[22] == 0x21 and usb[44] == 0x0A and usb[45] == 120 and usb[47] == 8 and usb[1] == 0x0C and usb[2] == 0x14,
		"  USB: right trigger at 11, left at 22, player LEDs at 44, RGB at 45..47, flags at 1 and 2")
	var bt: PackedByteArray = DS.build_report(true, 5, A[0], A[1], A[2], A[3], A[4], A[5])
	_check(bt.size() == 78 and bt[0] == 0x31 and bt[1] == 0x50 and bt[2] == 0x10 and bt.hex_encode() == BT_A, "  Bluetooth report 0x31, 78 bytes, seq 5 in the high nibble, tag 0x10, CRC matches the vector")
	_check(bt[13] == 0x25 and bt[24] == 0x21 and bt[46] == 0x0A and bt[47] == 120, "  Bluetooth: everything shifted by two (R2 at 13, L2 at 24, LEDs at 46, RGB at 47..49)")
	var crc: int = bt[74] | (bt[75] << 8) | (bt[76] << 16) | (bt[77] << 24)
	_check(crc == DS.crc32(bt, 74, 0xA2), "  the last four bytes are the CRC32 of bytes 0..73 with seed 0xA2, little endian")
	_check(DS.build_report(false, 0, 0x04, 0, DS.eff_vibration(3, 4, 11), DS.eff_off(), Vector3i.ZERO, 0).hex_encode() == USB_C, "  a right-trigger-only report leaves the rest zero")
	_check(DS.reset_report(false).hex_encode() == USB_D and DS.reset_report(true, 0).hex_encode() == BT_D, "  the reset reports (triggers Off, lightbar blue, one LED) match, USB and Bluetooth")
	_check(DS.parse_hid_id("DRIVER=playstation\nHID_ID=0003:0000054C:00000CE6\nHID_NAME=x\n") == {"bus": 3, "vendor": 0x54C, "product": 0xCE6}
		and DS.parse_hid_id("HID_ID=0005:0000054C:00000DF2\n")["bus"] == 5 and DS.parse_hid_id("nothing").is_empty(), "  HID_ID is read: bus 3 USB, bus 5 Bluetooth, 0CE6 and 0DF2")
	var dev: Dictionary = DS.find_device()
	print("       (this machine: %s)" % [dev])
	var cmd: String = DS.shell_command("/dev/hidraw0", 63, DS.reset_report(false))
	_check(cmd.begins_with("dd bs=63 iflag=fullblock of='/dev/hidraw0'") and cmd.contains("\\002\\014\\024") and cmd.contains("\\377"), "  the child's shell line copies 63-byte blocks and ends with the reset report")

	print("== DualSense: the triggers per gun")
	_fresh_holder()
	_zm.active = true
	_zm.over = false
	var d := _make()
	var expect_right := {
		"pistol": DS.eff_weapon(4, 6, 5), "magnum": DS.eff_weapon(3, 6, 7), "shotgun": DS.eff_weapon(3, 7, 8),
		"sniper": DS.eff_weapon(2, 8, 8), "smg": DS.eff_feedback(4, 2), "ar": DS.eff_feedback(4, 3), "lmg": DS.eff_feedback(3, 4),
	}
	for id in expect_right:
		h.current = _gun(id)
		d._attach_holder()
		var got: Dictionary = d.desired_triggers()
		_check(got["r"] == expect_right[id], "  R2 %s: %s" % [id, got["r"].hex_encode()])
	_check(DS.right_for(_gun("pistol"), false, 1.0)[0] == 0x25 and DS.right_for(_gun("shotgun"), false, 1.0)[3] == 7, "  pistol is the Weapon effect (0x25); the shotgun's is at full strength 8 (7 on the wire)")
	var smg_fire: PackedByteArray = DS.right_for(_gun("smg"), true, 1.0)
	_check(smg_fire[0] == 0x26 and smg_fire[9] == 13, "  SMG while firing: Vibration (0x26) at rpm/60 = 13 Hz (%d)" % smg_fire[9])
	_check(DS.right_for(_gun("ar"), true, 1.0)[9] == 11 and DS.right_for(_gun("lmg"), true, 1.0)[9] == 10, "  AR 11 Hz, LMG 10 Hz")
	_check(DS.right_for(_gun("lmg"), true, 1.0).hex_encode() != DS.right_for(_gun("smg"), true, 1.0).hex_encode(), "  the amplitude differs by gun")
	_check(DS.right_for(_gun("knife"), false, 1.0) == DS.eff_off(), "  the knife has a free trigger")
	_check(DS.left_for(_gun("sniper"), 1.0) == DS.eff_feedback(2, 4) and DS.left_for(_gun("ar"), 1.0) == DS.eff_feedback(3, 2), "  L2: soft Feedback for the scope, stronger for the sniper")
	_check(DS.scaled(8, 0.5) == 4 and DS.scaled(2, 0.3) == 1 and DS.scaled(8, 1.0) == 8, "  the Trigger strength setting scales 1..8")
	# Through the holder: firing, empty, reloading, sprinting.
	h.current = _gun("smg")
	d._attach_holder()
	var t: Dictionary = d.desired_triggers()
	_check(t["r"] == DS.eff_feedback(4, 2), "  SMG held: light Feedback on R2")
	h.fired.emit()
	t = d.desired_triggers()
	_check(t["r"][0] == 0x26, "  after a shot R2 vibrates at the gun's rate")
	_run_for(d, 0.3)
	t = d.desired_triggers()
	_check(t["r"][0] == 0x21, "  0.3 s after the last round it is Feedback again")
	h.mag = 0
	t = d.desired_triggers()
	_check(t["r"] == DS.eff_off() and t["l"][0] == 0x21, "  empty magazine: R2 goes slack (Off), L2 still weighs")
	h.mag = 10
	h.reloading = true
	t = d.desired_triggers()
	_check(t["r"] == DS.eff_off() and t["l"] == DS.eff_off(), "  reloading: both triggers slack")
	h.reloading = false
	feel.sprint_blend = 0.8
	t = d.desired_triggers()
	_check(t["r"] == DS.eff_off() and t["l"] == DS.eff_off(), "  sprinting: both slack")
	feel.sprint_blend = 0.0
	h.current = _gun("sniper")
	h.aiming = true
	t = d.desired_triggers()
	_check(t["l"] == DS.eff_feedback(2, 4) and t["r"] == DS.eff_weapon(2, 8, 8), "  sniper aimed: heavy L2 weight, long heavy R2 pull")
	_gfx.ds_trigger_strength = 0.5
	t = d.desired_triggers()
	_check(t["r"] == DS.eff_weapon(2, 8, 4), "  Trigger strength 0.5 halves it (strength 4)")
	_gfx.ds_trigger_strength = 1.0
	h.aiming = false
	h.current = _gun("pistol")
	# Bursts: melee, damage.
	d.burst(0.15, 1.0)
	t = d.desired_triggers()
	_check(t["r"][0] == 0x26 and t["l"][0] == 0x26 and t["r"] == t["l"], "  a burst buzzes both triggers")
	_run_for(d, 0.2)
	t = d.desired_triggers()
	_check(t["r"][0] == 0x25, "  and passes (the pistol's Weapon effect is back)")
	d.free()

	print("== DualSense: reports through the frame loop")
	_gfx.ds_triggers = true
	_gfx.ds_lightbar = true
	_zm.active = true
	_zm.health = 100.0
	_fresh_holder()
	d = _make()
	h.mag = 8
	h.reloading = false
	_run_for(d, 0.2)
	_check(_sent.size() >= 1, "  the first frame writes the triggers, lightbar and LEDs")
	var first := _sent[0]
	_check(_flags(first, false) == [0x0C, 0x14] and _right(first) == DS.eff_weapon(4, 6, 5) and _left(first) == DS.eff_feedback(3, 2),
		"  with a pistol R2 is Weapon(4,6,5) and L2 Feedback(3,2); flags 0x0C / 0x14")
	_check(_rgb(first) == Vector3i(120, 69, 8) and first[44] == DS.round_leds(maxi(_zm.round, 1)), "  idle lightbar is a dim amber (%s), the LEDs show the round" % _rgb(first))
	var n := _sent.size()
	_run_for(d, 0.5)
	_check(_sent.size() == n, "  nothing changes, nothing is written (%d reports)" % (_sent.size() - n))
	h.mag = 0
	_run_for(d, 0.1)
	_check(_flags(_last(), false)[0] == 0x04 and _right(_last()) == DS.eff_off(), "  the magazine runs dry: one report, only R2 flagged, now Off")
	h.mag = 8
	_run_for(d, 0.1)
	d.free()

	print("== DualSense: lightbar")
	_fresh_holder()
	d = _make()
	_zm.health = 100.0
	_run_for(d, 0.2)
	var base := _rgb(_last())
	d._hp = 100.0
	_zm.health_changed.emit(60.0)
	_run_for(d, 0.05)
	var hurt := _rgb(_last())
	_check(hurt.x > 150 and hurt.y < 40 and hurt.z < 10 and hurt.x > base.x, "  hurt: the lightbar goes red (%s from %s)" % [hurt, base])
	var tr := _last()
	_run_for(d, 1.2)
	_check(_rgb(_last()) == base, "  and settles back to amber")
	# Triggers buzzed with the hit.
	_check(_sent.any(func(b: PackedByteArray): return _right(b)[0] == 0x26), "  taking a claw also buzzes the triggers")
	# Headshot flash.
	h.hit.emit("head", false)
	_run_for(d, 0.03)
	var flash := _rgb(_last())
	_check(flash.y > base.y + 40 and flash.z > base.z + 40, "  a headshot flashes the bar white (%s)" % flash)
	_run_for(d, 0.5)
	# Kill streak.
	for i in 3:
		h.hit.emit("torso", true)
	_run_for(d, 0.03)
	_check(_rgb(_last()).z > 100, "  three kills in 2.5 s flash it white")
	_run_for(d, 1.0)
	# Quake.
	_zm.surge_warning.emit()
	var seen := {}
	for i in 90:
		d.tick(1.0 / 60.0)
		seen[_rgb(_last())] = true
	_check(seen.size() >= 3, "  the build-up to a quake flickers it like the street lights (%d colours)" % seen.size())
	_zm.surge_started.emit()
	seen.clear()
	var dark := 255
	var bright := 0
	for i in 120:
		d.tick(1.0 / 60.0)
		var c := _rgb(_last())
		seen[c] = true
		dark = mini(dark, c.x)
		bright = maxi(bright, c.x)
	_check(seen.size() >= 8 and bright - dark > 60, "  in the quake it flickers hard (%d colours, %d..%d)" % [seen.size(), dark, bright])
	_check(_sent.any(func(b: PackedByteArray): return _left(b)[0] == 0x26), "  and the triggers shudder")
	_zm.surge_ended.emit()
	_run_for(d, 0.3)
	_check(_rgb(_last()) == base, "  the quake over, amber again")
	# Tsunami.
	var ts := FakeTsunami.new()
	root.add_child(ts)
	_zm.tsunami_active = true
	_run_for(d, 0.5)
	var teal_seen := false
	var low := 255
	var high := 0
	for i in 150:
		d.tick(1.0 / 60.0)
		var c := _rgb(_last())
		low = mini(low, c.z)
		high = maxi(high, c.z)
		if c.z > c.x + 40:
			teal_seen = true
	_check(teal_seen and high - low > 80, "  the tsunami: a cold blue-green pulse (blue %d..%d)" % [low, high])
	_check(DS.tsunami_rate(5.0, 120.0) > DS.tsunami_rate(60.0, 120.0) * 1.5 and DS.tsunami_rate(60.0, 120.0) > DS.tsunami_rate(115.0, 120.0), "  quicker as the sea comes, quickest in the last 10 s")
	_zm.tsunami_active = false
	ts.free()
	# Game over.
	_zm.over = true
	_run_for(d, 0.3)
	_check(_rgb(_last()).x < 90 and _right(_last()).size() == 11, "  game over: a dark red bar")
	_zm.over = false
	d.free()

	print("== DualSense: reset and settings")
	_fresh_holder()
	d = _make()
	_run_for(d, 0.2)
	n = _sent.size()
	_zm.active = false
	d.tick(0.016)
	_check(_sent.size() == n + 1 and _last().hex_encode() == USB_D, "  leaving the mode sends the reset report (triggers Off, lightbar default, LED)")
	_run_for(d, 0.5)
	_check(_sent.size() == n + 1, "  and nothing more")
	_zm.active = true
	_run_for(d, 0.2)
	n = _sent.size()
	d._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_sent.size() == n + 1 and _last().hex_encode() == USB_D, "  losing the window's focus resets it at once")
	_run_for(d, 0.5)
	_check(_sent.size() == n + 1, "  and holds still while unfocused")
	d._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_run_for(d, 0.2)
	_check(_sent.size() > n + 1 and _flags(_sent[n + 1], false)[0] != 0, "  focus back: it takes over again")
	n = _sent.size()
	d.shutdown()
	_check(_sent.size() == n + 1 and _last().hex_encode() == USB_D, "  shutting down (quit) resets it")
	d.free()
	# Paused: slack triggers.
	d = _make()
	d._attach_holder()
	paused = true
	var pt: Dictionary = d.desired_triggers()
	_check(pt["r"] == DS.eff_off() and pt["l"] == DS.eff_off(), "  paused: both triggers slack")
	paused = false
	d.free()
	# Settings off.
	_fresh_holder()
	d = _make()
	_gfx.ds_triggers = false
	_gfx.ds_lightbar = false
	_run_for(d, 1.0)
	h.fired.emit()
	h.hit.emit("head", true)
	_zm.surge_started.emit()
	_zm.health_changed.emit(10.0)
	_run_for(d, 1.0)
	_check(_sent.is_empty(), "  Adaptive triggers and Lightbar effects both off: nothing is ever written (%d)" % _sent.size())
	_gfx.ds_triggers = true
	_run_for(d, 0.3)
	_check(not _sent.is_empty() and _sent.all(func(b: PackedByteArray): return (b[2] & 0x14) == 0), "  triggers on, lightbar off: only the triggers are driven, the bar and LEDs are never touched")
	_gfx.ds_lightbar = true
	_gfx.ds_triggers = false
	_sent.clear()
	_zm.surge_ended.emit()
	_run_for(d, 0.3)
	_check(_right(_last()) == DS.eff_off() or _sent.any(func(b: PackedByteArray): return _rgb(b).x > 0), "  lightbar on, triggers off: the bar plays, the triggers stay slack")
	var all_off := true
	for b in _sent:
		if (b[1] & 0x04) != 0 and _right(b)[0] != 0x05 or (b[1] & 0x08) != 0 and _left(b)[0] != 0x05:
			all_off = false
	_check(all_off, "  with Adaptive triggers off, no trigger effect is sent")
	d.free()
	_gfx.ds_triggers = true
	_gfx.ds_lightbar = true

	print("== DualSense: BT stream, the hooks, the child process")
	_gfx.ds_trigger_strength = 1.0
	_fresh_holder()
	d = _make(true)
	_run_for(d, 0.2)
	_check(_sent.size() >= 1 and _sent[0].size() == 78 and _sent[0][0] == 0x31, "  a Bluetooth controller gets 78-byte 0x31 reports")
	var seqs := []
	d.burst(0.1, 1.0)
	_run_for(d, 0.3)
	for b in _sent:
		seqs.append(b[1] >> 4)
		var c: int = b[74] | (b[75] << 8) | (b[76] << 16) | (b[77] << 24)
		if c != DS.crc32(b, 74, 0xA2):
			_check(false, "  a report has a wrong CRC")
	var rising := true
	for i in range(1, seqs.size()):
		if seqs[i] != (seqs[i - 1] + 1) & 0x0F:
			rising = false
	_check(rising and seqs.size() >= 3, "  the sequence number counts up every report %s and every CRC checks out" % [seqs])
	d.free()
	# The real signals the hooks name exist on the game's own nodes.
	var wh_signals := []
	for s in load("res://player/WeaponHolder.gd").get_script_signal_list():
		wh_signals.append(s["name"])
	_check(wh_signals.has("fired") and wh_signals.has("hit") and wh_signals.has("melee_swung") and wh_signals.has("reload_started"), "  WeaponHolder has the signals DualSense listens to")
	var zm_signals := []
	for s in _zm.get_script().get_script_signal_list():
		zm_signals.append(s["name"])
	_check(zm_signals.has("health_changed") and zm_signals.has("surge_warning") and zm_signals.has("surge_started") and zm_signals.has("surge_ended"), "  ZombieMode has health_changed and the surge signals")
	# The child process really writes whole reports, in order, and ends with the reset.
	var out := ProjectSettings.globalize_path("res://dev-tools/_ds_out.bin")
	var r1: PackedByteArray = DS.build_report(false, 0, 0x04, 0x04, DS.eff_weapon(4, 6, 5), DS.eff_off(), Vector3i(1, 2, 3), 0)
	var r2: PackedByteArray = DS.build_report(false, 0, 0x08, 0x10, DS.eff_off(), DS.eff_feedback(3, 2), Vector3i.ZERO, 0x0A)
	var line: String = DS.shell_command(out, 63, DS.reset_report(false))
	var p := OS.execute_with_pipe("/bin/sh", ["-c", line])
	if p.is_empty():
		_check(false, "  could not start the child process")
	else:
		var io: FileAccess = p["stdio"]
		io.store_buffer(r1)
		io.flush()
		io.store_buffer(r2)
		io.flush()
		OS.delay_msec(150)
		io.close()
		var waited := 0
		while OS.is_process_running(int(p["pid"])) and waited < 3000:
			OS.delay_msec(50)
			waited += 50
		var got := FileAccess.get_file_as_bytes(out)
		_check(got.size() == 63 * 3 and got.slice(0, 63) == r1 and got.slice(63, 126) == r2 and got.slice(126) == DS.reset_report(false),
			"  the child wrote two reports as they came and the reset report when the pipe closed (%d bytes)" % got.size())
		DirAccess.remove_absolute(out)
