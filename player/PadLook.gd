extends RefCounted
## The right stick as Call of Duty reads it, for the first-person look.
##
##   radial deadzone   inside `inner` (Settings > Deadzone) the stick is at rest, out at OUTER it is
##                     full tilt; the span between is rescaled to 0..1, so there is no jump at the edge.
##   response curve    that 0..1 is raised to CURVE (2): a small push is a fine, slow aim, a full push
##                     is the whole turn rate.
##   turn acceleration held at full tilt for ACCEL_AFTER seconds the yaw (only) ramps up to ACCEL_MAX
##                     over ACCEL_RAMP seconds, so a flick turns you round fast while the same stick
##                     held half-way stays precise. Letting the stick off full tilt starts it over.
##   sensitivity       horizontal and vertical apart, and a multiplier while aiming down the sights.
##
## Everything is per second (rate x delta), so it turns the same at 30 and 144 frames. step() takes the
## raw stick (no deadzone) and gives the turn in radians: x to the right, y up.

## Radians per second at full tilt with sensitivity 1: 195 and 140 degrees.
const RATE_YAW := 3.4
const RATE_PITCH := 2.45
const OUTER := 0.98
const CURVE := 2.0
const ACCEL_AFTER := 0.15
const ACCEL_RAMP := 0.25
const ACCEL_MAX := 1.6
## The stick counts as "full tilt" for the acceleration above this (after the deadzone is taken off).
const FULL_TILT := 0.92

## Seconds the stick has been at full tilt.
var full_time := 0.0
## The yaw multiplier the acceleration gives now (1 .. ACCEL_MAX).
var boost := 1.0
## The stick after the deadzone and before the curve (0..1) the last step saw.
var tilt := 0.0

## The raw right stick: Input's own strengths, which the actions' deadzone has not touched.
static func raw_stick() -> Vector2:
	return Vector2(
		Input.get_action_raw_strength("look_right") - Input.get_action_raw_strength("look_left"),
		Input.get_action_raw_strength("look_down") - Input.get_action_raw_strength("look_up"))

## The stick rescaled past a radial deadzone: same direction, length 0..1.
static func deadzoned(raw: Vector2, inner: float, outer := OUTER) -> Vector2:
	var m := raw.length()
	if m <= inner or m <= 0.0:
		return Vector2.ZERO
	return raw / m * clampf((m - inner) / maxf(outer - inner, 0.01), 0.0, 1.0)

## 0..1 in, 0..1 out: slow near the middle, full at the edge.
static func curve(t: float, exponent := CURVE) -> float:
	return pow(clampf(t, 0.0, 1.0), exponent)

## The yaw multiplier after `t` seconds at full tilt.
static func boost_at(t: float) -> float:
	return lerpf(1.0, ACCEL_MAX, smoothstep(0.0, 1.0, clampf((t - ACCEL_AFTER) / ACCEL_RAMP, 0.0, 1.0)))

## One frame of look. `scale` is the multiplier for aiming (the field-of-view ratio and the ADS setting
## together; 1 at the hip); `invert` flips up and down.
func step(raw: Vector2, delta: float, scale := 1.0, invert := false) -> Vector2:
	var v := deadzoned(raw, Graphics.pad_deadzone)
	tilt = v.length()
	if tilt >= FULL_TILT:
		full_time += delta
	else:
		# Off full tilt the build-up is lost fast, not at once: a wobble at the edge does not reset it.
		full_time = maxf(full_time - delta * 6.0, 0.0) if tilt > 0.5 else 0.0
	boost = boost_at(full_time)
	if tilt <= 0.0:
		return Vector2.ZERO
	var shaped := v.normalized() * curve(tilt)
	var out := Vector2(shaped.x * RATE_YAW * Graphics.pad_sens_h * boost, -shaped.y * RATE_PITCH * Graphics.pad_sens_v)
	if invert:
		out.y = -out.y
	return out * delta * scale

func reset() -> void:
	full_time = 0.0
	boost = 1.0
	tilt = 0.0
