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
## rate that keeps the feet planted instead of sliding. The walk was 2.0
## while the clips still carried the hips forward; walking in place
## (_in_place) it's 1.25.
const WALK_NATURAL := 1.25
const SPRINT_NATURAL := 5.6
const SHUFFLE_NATURAL := 1.0
const STRIDE_LIMITS := Vector2(0.4, 1.8)
const MOVING_THRESHOLD := 0.1
## The dead and the player's finishers (assets/zombie_anims/, built by
## dev-tools/retarget_to_bip01.py). They live in an AnimationLibrary that
## install_zombie_library() adds to a Rocketbox avatar's AnimationPlayer
## *before* the CharacterAnimator is made. A clip nobody has produced yet
## resolves to the Rocketbox clip next best (see ZOMBIE_ALIASES), so every
## name below always plays something.
const ZOMBIE_LIBRARY := "res://assets/zombie_anims/zombie_clips.res"
const ZOMBIE_LIBRARY_NAME := "zombie"
const ZOMBIE_CLIPS := ["z_idle", "z_scratch", "z_walk", "z_walk2", "z_walk3", "z_run", "z_crawl",
	"z_attack", "z_attack2", "z_attack3", "z_hit_head", "z_hit_chest", "z_hit_leg", "z_hit_knockback",
	"z_death", "z_death2", "z_standup", "z_scream", "z_climb", "p_kick", "p_stab",
	"z_rise", "z_land", "z_hit_leg_l", "z_hit_arm_l", "z_hit_arm_r", "z_stumble", "z_walk4", "z_limp_l",
	"z_walk_hurt_l", "z_walk_hurt_r", "z_lunge", "z_bite", "z_smash"]
const ZOMBIE_LOOPING := ["z_idle", "z_walk", "z_walk2", "z_walk3", "z_run", "z_crawl", "z_walk4", "z_limp_l", "z_walk_hurt_l", "z_walk_hurt_r"]
## Ghetto Wars' armed humans (assets/gang_anims/gang_clips.res, dev-tools/retarget_to_bip01.py with GANG=1):
## g_* are plain human clips, ga_* the same gaits with the pistol-aim upper body (a gun at the shoulder).
const GANG_LIBRARY := "res://assets/gang_anims/gang_clips.res"
const GANG_LIBRARY_NAME := "gang"
const GANG_LOOPING := ["g_aim", "g_idle", "g_crouch_idle", "g_crouch_walk", "g_walk", "g_jog", "g_sprint", "g_stand",
	"ga_stand", "ga_walk", "ga_jog", "ga_crouch", "ga_crouch_walk", "ga_sprint"]
const GANG_CLIPS := GANG_LOOPING + ["g_shoot", "g_reload", "g_roll", "g_throw", "g_hit_chest", "g_hit_head", "g_hit_knock", "g_death",
	"g_aim_up", "g_aim_down"]
const LOGICAL_CLIPS := ["idle", "walk", "sprint", "sit", "pick-up", "interact", "collapse", "walk_sick", "idle_sick", "crouch"] + ZOMBIE_CLIPS + GANG_CLIPS
const LOOPING_CLIPS := ["idle", "walk", "sprint", "sit", "walk_sick", "idle_sick", "crouch"] + ZOMBIE_LOOPING + GANG_LOOPING

## Zombie clip -> candidates, best first: its own clip, a sibling that does
## the same job, then what every Rocketbox avatar ships (walk_sick, idle_sick,
## crouch, sprint, take, sit). "z_x" is found as the library's "zombie/z_x".
const ZOMBIE_ALIASES := {
	"z_idle": ["z_idle", "idle_sick", "idle"],
	"z_scratch": ["z_scratch", "z_idle", "idle_sick", "idle"],
	"z_walk": ["z_walk", "walk_sick", "walk"],
	"z_walk2": ["z_walk2", "z_walk", "walk_sick", "walk"],
	"z_walk3": ["z_walk3", "z_walk2", "z_walk", "walk_sick", "walk"],
	"z_run": ["z_run", "sprint", "walk_sick", "walk"],
	"z_crawl": ["z_crawl", "crouch", "walk_sick"],
	"z_attack": ["z_attack", "take"],
	"z_attack2": ["z_attack2", "z_attack", "take"],
	"z_attack3": ["z_attack3", "z_attack2", "z_attack", "take"],
	"z_hit_head": ["z_hit_head", "z_hit_chest", "z_hit_knockback", "crouch", "idle_sick"],
	"z_hit_chest": ["z_hit_chest", "z_hit_head", "z_hit_knockback", "crouch", "idle_sick"],
	"z_hit_leg": ["z_hit_leg", "z_hit_chest", "z_hit_head", "z_hit_knockback", "crouch", "idle_sick"],
	"z_hit_knockback": ["z_hit_knockback", "z_hit_chest", "crouch", "idle_sick"],
	"z_death": ["z_death", "death", "_death", "crouch", "sit"],
	"z_death2": ["z_death2", "z_death", "death", "_death", "crouch", "sit"],
	"z_standup": ["z_standup", "crouch", "idle_sick", "idle"],
	"z_scream": ["z_scream", "z_idle", "idle_sick", "idle"],
	"z_climb": ["z_climb", "walk_sick", "walk"],
	"z_rise": ["z_rise", "z_standup", "z_climb", "crouch"],
	"z_land": ["z_land", "z_hit_leg", "crouch", "idle_sick"],
	"z_hit_leg_l": ["z_hit_leg_l", "z_hit_leg", "z_hit_chest", "crouch"],
	"z_hit_arm_l": ["z_hit_arm_l", "z_hit_chest", "z_hit_head", "idle_sick"],
	"z_hit_arm_r": ["z_hit_arm_r", "z_hit_chest", "z_hit_head", "idle_sick"],
	"z_stumble": ["z_stumble", "z_hit_knockback", "z_hit_chest", "idle_sick"],
	"z_walk4": ["z_walk4", "z_walk3", "z_walk", "walk_sick", "walk"],
	"z_limp_l": ["z_limp_l", "z_walk3", "z_walk", "walk_sick", "walk"],
	"z_walk_hurt_l": ["z_walk_hurt_l", "z_walk3", "z_walk", "walk_sick", "walk"],
	"z_walk_hurt_r": ["z_walk_hurt_r", "z_walk3", "z_walk", "walk_sick", "walk"],
	"z_lunge": ["z_lunge", "z_attack", "take"],
	"z_bite": ["z_bite", "z_attack3", "z_attack", "take"],
	"z_smash": ["z_smash", "z_attack2", "z_attack", "take"],
	"p_kick": ["p_kick", "take"],
	"p_stab": ["p_stab", "take"],
}

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
var _skeleton: Skeleton3D
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
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for logical in LOGICAL_CLIPS:
		_resolved[logical] = _resolve(logical)
	# Locomotion clips import with looping off in both packs.
	for logical in LOOPING_CLIPS:
		var real: String = _resolved.get(logical, "")
		if real != "":
			_player.get_animation(real).loop_mode = Animation.LOOP_LINEAR
			_in_place(_player.get_animation(real))
	_player.animation_finished.connect(_on_animation_finished)
	play("idle", _idle_rate)
	var idle: String = _resolved.get("idle", "")
	if idle != "":
		_player.seek(randf() * _player.get_animation(idle).length, true)

## The Rocketbox clips walk the hips forward (~1.2 m a walk loop, more for
## the sprint; the sick idle drifts too) and the loop snaps them back, so
## everyone lurched back a step per stride on top of moving. The body's
## own movement does the travelling: take the steady drift out of each
## position track, across the ground only, keeping the bob and sway. The
## clips are shared by every copy of a model, so once per clip.
##
## Their first frame is also a stall -- the hips sit at the origin for one
## key before moving off -- which was a hitch per loop (6.5 cm in the run).
## So the pace is taken from the second key to the last, and the first key
## is set to the last, which is where the loop comes round to.
static func _in_place(a: Animation) -> void:
	if a.has_meta("in_place"):
		return
	a.set_meta("in_place", true)
	var travel := 0.0
	for t in a.get_track_count():
		var n := a.track_get_key_count(t)
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or n < 3:
			continue
		var t1 := a.track_get_key_time(t, 1)
		var span := a.track_get_key_time(t, n - 1) - t1
		var drift: Vector3 = a.track_get_key_value(t, n - 1) - a.track_get_key_value(t, 1)
		drift.y = 0.0
		if span <= 0.0 or drift.length() < 0.01:
			continue
		var pace := drift / span
		travel = maxf(travel, pace.length())
		for k in range(1, n):
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, v - pace * (a.track_get_key_time(t, k) - t1))
		var last: Vector3 = a.track_get_key_value(t, n - 1)
		var first: Vector3 = a.track_get_key_value(t, 0)
		a.track_set_key_value(t, 0, Vector3(last.x, first.y, last.z))
	# What the hips covered, per second in skeleton units: the pace that
	# keeps this clip's feet planted (natural_speed()).
	a.set_meta("travel", travel)

## Finds the real clip on this model for a logical name. Exact matches win
## over suffix matches so a model that genuinely has "walk" never picks up
## something like "sidewalk" first.
func _resolve(logical: String) -> String:
	var available: Array = _player.get_animation_list()
	for alias in ZOMBIE_ALIASES.get(logical, CLIP_ALIASES.get(logical, [logical])):
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

## Steps the clip on by hand, for a body whose node isn't processing (a far
## walker the camera can still see: animated at a lower rate instead of
## gliding in a frozen pose).
func advance(seconds: float) -> void:
	if _player != null and _player.is_inside_tree():
		_player.advance(seconds)

## Where in its clip the player is, seconds (for tests).
func clip_position() -> float:
	return _player.current_animation_position if _player != null else 0.0

func stride_rate(clip: String, ground_speed: float) -> float:
	return clampf(ground_speed / natural_speed(clip), STRIDE_LIMITS.x, STRIDE_LIMITS.y)

## Ground speed (m/s) this body's clip covers at playback speed 1: from
## the hips' travel that _in_place took out, so each model plants its own
## feet (the women's walk covers a fifth more than the men's). The
## constants are for a body not yet in the world, or a clip without travel.
func natural_speed(clip: String) -> float:
	var real: String = _resolved.get(clip, "")
	if _player and _skeleton and real != "" and _skeleton.is_inside_tree():
		var travel: float = _player.get_animation(real).get_meta("travel", 0.0)
		if travel > 0.0:
			return travel * _skeleton.global_transform.basis.get_scale().x
	match clip:
		"sprint":
			return SPRINT_NATURAL
		"walk_sick":
			return SHUFFLE_NATURAL
	return WALK_NATURAL

## Seconds of clip between footfalls at playback speed 1: a loop is two.
func step_time(clip: String) -> float:
	var real: String = _resolved.get(clip, "")
	if _player == null or real == "":
		return 0.615
	return _player.get_animation(real).length * 0.5

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

## The clip on this model that a logical name plays ("" if none): for a zombie
## clip, "zombie/z_walk" when produced, else the fallback Rocketbox clip.
func resolved_clip(logical: String) -> String:
	return _resolved.get(logical, "")

## Adds the zombie clips to a model's AnimationPlayer (once; the library
## resource is shared by every zombie). Call before CharacterAnimator.new().
## Returns false if the model has no player or the library isn't built, in
## which case every zombie clip still resolves, to its Rocketbox fallback.
static func install_zombie_library(model: Node) -> bool:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return false
	if player.has_animation_library(ZOMBIE_LIBRARY_NAME):
		return true
	var lib := load(ZOMBIE_LIBRARY) as AnimationLibrary
	if lib == null:
		return false
	return player.add_animation_library(ZOMBIE_LIBRARY_NAME, lib) == OK

## The same for the armed humans' clips (Gangster3D calls it before CharacterAnimator.new()).
static func install_gang_library(model: Node) -> bool:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return false
	if player.has_animation_library(GANG_LIBRARY_NAME):
		return true
	var lib := load(GANG_LIBRARY) as AnimationLibrary
	if lib == null:
		return false
	return player.add_animation_library(GANG_LIBRARY_NAME, lib) == OK

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

## A one-shot that handed over to the next clip while still running (the crossfade out of it
## needs a live player): its finish signal will not come, so let go of it.
func end_once() -> void:
	_one_shot = ""

func is_playing_once() -> bool:
	return _one_shot != ""

func _on_animation_finished(clip: StringName) -> void:
	if String(clip) == _resolved.get(_one_shot, ""):
		_one_shot = ""

func current_clip() -> String:
	return _current
