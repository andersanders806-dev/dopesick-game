extends RefCounted
## Dead Block's controls, Call of Duty's layout with no button doing two jobs:
##
##   keyboard: LMB fire, RMB aim, R reload, E use, 1 / 2 / mouse wheel swap, V knife,
##             C or Ctrl crouch (a slide, from a sprint), T inspect
##   pad:      R2 fire, L2 aim, Square reload (hold it at a board, the box or
##             the machine to buy), Triangle swap, R3 knife, Circle crouch / slide,
##             D-pad down inspect
##
## apply() is called when the mode begins (autoload/ZombieMode.gd) and again by
## the WeaponHolder (idempotent); restore() when the mode is left. It saves the
## story's events of every action it touches the first time, and puts them
## back exactly, erasing the actions only this mode has. Everything is bound
## for any device (-1): on Linux a DualSense is often not joypad 0.

## What the mode binds: action -> [events]. A pad button or axis is a
## [kind, index (, direction)] triple, built in _event().
const BINDINGS := {
	"fire": [["mouse", MOUSE_BUTTON_LEFT], ["axis", JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"aim": [["mouse", MOUSE_BUTTON_RIGHT], ["axis", JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"reload": [["key", KEY_R], ["button", JOY_BUTTON_X]],
	"interact": [["key", KEY_E]],
	"swap_weapon": [["mouse", MOUSE_BUTTON_WHEEL_UP], ["mouse", MOUSE_BUTTON_WHEEL_DOWN], ["button", JOY_BUTTON_Y]],
	"weapon_slot_1": [["key", KEY_1]],
	"weapon_slot_2": [["key", KEY_2]],
	"melee": [["key", KEY_V], ["button", JOY_BUTTON_RIGHT_STICK]],
	"crouch": [["key", KEY_C], ["key", KEY_CTRL], ["button", JOY_BUTTON_B]],
	"inspect": [["key", KEY_T], ["button", JOY_BUTTON_DPAD_DOWN]],
}
## Story controls with no use in Dead Block that would sit on a button the mode needs
## (the tapes on Triangle, the vehicle and steady actions on the triggers and Space).
const CLEARED := ["walkman", "walkman_next", "steady", "drift", "throttle", "brake"]
const DEADZONE := 0.3

## action -> the story's events (null while the mode is not applied).
static var _saved = null

static func applied() -> bool:
	return _saved != null

static func apply() -> void:
	if _saved == null:
		_saved = {}
		for a in BINDINGS.keys() + CLEARED:
			_saved[a] = InputMap.action_get_events(a) if InputMap.has_action(a) else null
	for a in CLEARED:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
	for a in BINDINGS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, DEADZONE)
		InputMap.action_erase_events(a)
		for spec in BINDINGS[a]:
			InputMap.action_add_event(a, _event(spec))

## The story's bindings back, the mode's own actions gone.
static func restore() -> void:
	if _saved == null:
		return
	for a in _saved:
		var events = _saved[a]
		if events == null:
			if InputMap.has_action(a):
				InputMap.erase_action(a)
			continue
		InputMap.action_erase_events(a)
		for ev in events:
			InputMap.action_add_event(a, ev)
	_saved = null

static func _event(spec: Array) -> InputEvent:
	var ev: InputEvent
	match spec[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = spec[1]
			ev = k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = spec[1]
			ev = m
		"button":
			var b := InputEventJoypadButton.new()
			b.button_index = spec[1]
			ev = b
		_:
			var j := InputEventJoypadMotion.new()
			j.axis = spec[1]
			j.axis_value = spec[2]
			ev = j
	ev.device = -1
	return ev
