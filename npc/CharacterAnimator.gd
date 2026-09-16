extends RefCounted
## Plays the walk/idle clips that ship inside every Kenney Mini Character
## .glb. The clips import with looping off, so the locomotion ones are
## switched to loop here. Usage:
##   var anim := CharacterAnimator.new(model_node)
##   anim.update(horizontal_speed)   # each physics frame

const BLEND_TIME := 0.15
const MOVING_THRESHOLD := 0.1
const LOOPING_CLIPS := ["idle", "walk", "sprint"]

var _player: AnimationPlayer
var _moving_clip: String
var _current := ""

## `moving_clip` is what plays while moving ("walk", or "sprint" for police).
func _init(model: Node, moving_clip := "walk") -> void:
	_moving_clip = moving_clip
	if model:
		_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null:
		return
	for clip in LOOPING_CLIPS:
		if _player.has_animation(clip):
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	play("idle")

## Picks idle vs. moving from horizontal speed. `anim_speed` scales playback,
## e.g. a slower shuffle when the player is in withdrawal.
func update(horizontal_speed: float, anim_speed := 1.0) -> void:
	if horizontal_speed > MOVING_THRESHOLD:
		play(_moving_clip, anim_speed)
	else:
		play("idle")

func play(clip: String, anim_speed := 1.0) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	_player.speed_scale = anim_speed
	if clip != _current:
		_current = clip
		_player.play(clip, BLEND_TIME)

func current_clip() -> String:
	return _current
