extends RefCounted
## What to call a control in Dead Block's prompts: the PlayStation button when the last input was the
## pad, the key when it was the keyboard or the mouse (GameState.using_pad, which flips live).
## The vocabulary is the zombie mode's actions (player/ZombieControls.gd) plus the menu ones.

## action -> the glyph name (ui/PadGlyph.gd) and the word for it.
const PAD := {
	"fire": ["R2", "R2"], "aim": ["L2", "L2"], "reload": ["Square", "Square"], "interact": ["Square", "Square"],
	"swap_weapon": ["Triangle", "Triangle"], "melee": ["R3", "R3"], "sprint": ["L3", "L3"],
	"crouch": ["Circle", "Circle"], "inspect": ["DpadDown", "D-pad down"], "pause": ["Options", "Options"],
	"cancel_ui": ["Circle", "Circle"], "accept": ["Cross", "Cross"], "move": ["LStick", "Left stick"],
	"look": ["RStick", "Right stick"], "back": ["Circle", "Circle"],
}
const KEY := {
	"fire": "Left click", "aim": "Right click", "reload": "R", "interact": "E", "swap_weapon": "Q / Wheel",
	"melee": "V", "sprint": "Shift", "crouch": "C", "inspect": "T", "pause": "Esc", "cancel_ui": "Esc",
	"accept": "Enter", "move": "WASD", "look": "Mouse", "back": "Esc",
}

static func is_pad() -> bool:
	return GameState.using_pad

## The glyph name for the pad ("Square"), "" if the action has none.
static func pad_glyph(action: String) -> String:
	return PAD[action][0] if PAD.has(action) else ""

## The words for it now: "Square" or "E".
static func name_of(action: String) -> String:
	if is_pad():
		return PAD[action][1] if PAD.has(action) else action
	return KEY.get(action, action)
