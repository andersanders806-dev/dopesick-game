extends RefCounted
## Plays the locomotion clips that ship inside a character model. Usage:
##   var anim := CharacterAnimator.new(model_node)
##   anim.update(horizontal_speed)   # each physics frame
##   anim.play_once("pick-up")       # one-shot; update() waits for it
##
## Callers always ask for a *logical* clip -- "idle", "walk", "sprint",
## "sit", "pick-up" -- and never for a clip name that's baked into a
## particular art pack. `_resolve()` maps those onto whatever the loaded
## model actually ships, so the same call sites drive both the Kenney Mini
## Characters (clips literally named "idle"/"walk"/"sprint"/"sit") and the
## Quaternius realistic humans (clips named "HumanArmature|Man_Idle",
## "HumanArmature|Female_Walk", and so on, with the prefix differing by sex).
## Without this every NPC script would need to know which body it was wearing.

const BLEND_TIME := 0.2
## Ground speed (m/s, at the cast's 1.5 scale) each locomotion clip covers at
## playback speed 1, measured from the feet: update() plays them at the
## rate that keeps the feet planted instead of sliding.
const WALK_NATURAL := 2.0
const SPRINT_NATURAL := 5.6
const SHUFFLE_NATURAL := 1.0
const STRIDE_LIMITS := Vector2(0.4, 1.8)
const MOVING_THRESHOLD := 0.1
const LOGICAL_CLIPS := ["idle", "walk", "sprint", "sit", "pick-up", "interact", "collapse", "walk_sick", "idle_sick", "crouch"]
const LOOPING_CLIPS := ["idle", "walk", "sprint", "sit", "walk_sick", "idle_sick", "crouch"]

## Candidate real clip names per logical clip, best match first. Matched
## case-insensitively, first as an exact name and then as a suffix, so
## "HumanArmature|Man_Idle" is found by the bare "_idle" entry.
const CLIP_ALIASES := {
	"idle": ["idle", "_idle"],
	"walk": ["walk", "_walk"],
	"sprint": ["sprint", "_run", "_jog"],
	"sit": ["sit", "_sitting", "_sit"],
	# Quaternius' human pack has no grab clip. Its punch is a single forward
	# arm extension, which at the ~11 m the camera sits back reads as
	# reaching out and taking something off a shelf -- see play_once_timed(),
	# which stretches it to the duration the grab is meant to take. Kenney's
	# own "pick-up" wins when it's there.
	"pick-up": ["pick-up", "pickup", "_pickup", "_punch", "take"],
	# The pusher's hand-to-hand. Kenney has a dedicated reach; the Quaternius
	# clap brings both hands together in front of the chest, which passes for
	# handing something over at this distance.
	"interact": ["interact-right", "interact", "_interact", "_clapping", "take"],
	# Going over in the alley. Not looped, so as a rest clip it plays once
	# and holds the last frame.
	"collapse": ["death", "_death"],
	# The Rocketbox avatars' withdrawal clips: a bruised, hunched walk and a
	# nervous, fidgeting idle. Only those models ship them; has_clip() says.
	"walk_sick": ["walk_sick"],
	"idle_sick": ["idle_sick"],
	"crouch": ["crouch"],
}

var _player: AnimationPlayer
var _moving_clip: String
var _current := ""
var _one_shot := ""
var _rest_clip := "idle"
## Logical clip name -> the real clip on this model, or "" if it has none.
var _resolved := {}
## Everyone's idle runs at their own rate, from their own point in it, so a
## room of people standing about isn't breathing in step.
var _idle_rate: float = randf_range(0.88, 1.12)

## `moving_clip` is what plays while moving ("walk", or "sprint" for police).
func _init(model: Node, moving_clip := "walk") -> void:
	_moving_clip = moving_clip
	if model:
		_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null:
		return
	for logical in LOGICAL_CLIPS:
		_resolved[logical] = _resolve(logical)
	# Locomotion clips import with looping off in both packs.
	for logical in LOOPING_CLIPS:
		var real: String = _resolved.get(logical, "")
		if real != "":
			_player.get_animation(real).loop_mode = Animation.LOOP_LINEAR
	_player.animation_finished.connect(_on_animation_finished)
	play("idle", _idle_rate)
	var idle: String = _resolved.get("idle", "")
	if idle != "":
		_player.seek(randf() * _player.get_animation(idle).length, true)

## Finds the real clip on this model for a logical name. Exact matches win
## over suffix matches so a model that genuinely has "walk" never picks up
## something like "sidewalk" first.
func _resolve(logical: String) -> String:
	var available: Array = _player.get_animation_list()
	for alias in CLIP_ALIASES.get(logical, [logical]):
		for name in available:
			if String(name).to_lower() == alias:
				return String(name)
		for name in available:
			if String(name).to_lower().ends_with(alias):
				return String(name)
	return ""

## Picks idle vs. moving from horizontal speed. `anim_speed` scales playback,
## e.g. a slower shuffle when the player is in withdrawal.
## `anim_speed` < 0: worked out from the pace (feet planted) when moving,
## the person's own idle rate when not.
func update(horizontal_speed: float, anim_speed := -1.0) -> void:
	if _one_shot != "":
		return
	if horizontal_speed > MOVING_THRESHOLD:
		play(_moving_clip, anim_speed if anim_speed >= 0.0 else stride_rate(_moving_clip, horizontal_speed))
	else:
		play(_rest_clip, anim_speed if anim_speed >= 0.0 else _idle_rate)

func stride_rate(clip: String, ground_speed: float) -> float:
	var natural := WALK_NATURAL
	match clip:
		"sprint":
			natural = SPRINT_NATURAL
		"walk_sick":
			natural = SHUFFLE_NATURAL
	return clampf(ground_speed / natural, STRIDE_LIMITS.x, STRIDE_LIMITS.y)

## What the character does when not moving: "idle" (standing) by default,
## or e.g. "sit" for a patron in a booth. Takes effect immediately.
func set_rest_clip(clip: String) -> void:
	_rest_clip = clip
	if _one_shot == "":
		play(clip)

## Which clips update() uses for moving and for standing still, from now on
## -- without cutting off whatever's playing. Clips the model doesn't have
## are ignored, so callers can ask for "walk_sick" on any body.
func set_clips(moving: String, rest: String) -> void:
	if has_clip(moving):
		_moving_clip = moving
	if has_clip(rest):
		_rest_clip = rest

func has_clip(logical: String) -> bool:
	return _resolved.get(logical, "") != ""

func play(clip: String, anim_speed := 1.0) -> void:
	var real: String = _resolved.get(clip, "")
	if _player == null or real == "":
		return
	_player.speed_scale = anim_speed
	if clip != _current:
		_current = clip
		_player.play(real, BLEND_TIME)

## Plays a non-looping clip start to finish; locomotion updates are ignored
## until it ends, then blend back in. Returns the clip's real duration in
## seconds (0.0 if the model doesn't have it).
func play_once(clip: String, anim_speed := 1.0) -> float:
	var real: String = _resolved.get(clip, "")
	if _player == null or real == "":
		return 0.0
	var speed: float = anim_speed
	_one_shot = clip
	_current = clip
	_player.speed_scale = speed
	_player.play(real, BLEND_TIME)
	_player.seek(0.0, true)
	return _player.get_animation(real).length / speed

## Plays a one-shot stretched or squeezed to take exactly `seconds`, and
## returns that duration. Use this wherever the *timing* is what matters --
## a grab the player is rooted in place for, or a state machine waiting on a
## gesture -- because the source clips differ wildly in length between art
## packs (Kenney's grab is 0.33 s, the Quaternius stand-in is 0.917 s). A
## fixed speed multiplier tuned against one pack silently becomes a
## 3-second freeze against the other.
##
## Always returns `seconds`, even when the model has no such clip, so a
## caller using the result as a timer still waits the right amount of time
## instead of skipping the beat entirely.
func play_once_timed(clip: String, seconds: float) -> float:
	var real: String = _resolved.get(clip, "")
	if _player == null or real == "" or seconds <= 0.0:
		return max(seconds, 0.0)
	play_once(clip, _player.get_animation(real).length / seconds)
	return seconds

func is_playing_once() -> bool:
	return _one_shot != ""

func _on_animation_finished(clip: StringName) -> void:
	if String(clip) == _resolved.get(_one_shot, ""):
		_one_shot = ""

func current_clip() -> String:
	return _current
