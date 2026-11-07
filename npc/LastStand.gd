extends Node
## The last men of a wave (Dead Block's "last ones run", COD's last-enemy reveal): when two or fewer are left and
## the player has had none of them in his sights for a while, the wave must not be allowed to stall.
##   15 s: they leave cover and come at the player along a way they can walk (a man the navmesh cannot get to
##         the player from is put back on a spawn point out of sight instead);
##   25 s: they shout and a marker shows where they are (HUD ping and a blip), again every 9 s while hidden;
##   40 s: a man still hidden is put back on the spawn point nearest the player that is out of his sight.
## "In his sights" is a clear line from the player's eye (chain-link does not block it); nothing to do with the
## frustum: a man behind you with a clear line can be shot too.

const PUSH_AFTER := 15.0
const REVEAL_AFTER := 25.0
const RELOCATE_AFTER := 40.0
const REVEAL_EVERY := 9.0
const RE_HUNT_EVERY := 12.0
const SIGHT_RANGE := 90.0
const CHECK_EVERY := 0.25

var spawner: Node
## Seconds none of the last men has been in the player's sights.
var hidden_t := 0.0
var pushed := false
var reveals := 0
var relocations := 0
var _reveal_t := 0.0
var _hunt_t := 0.0
var _acc := 0.0

func _process(delta: float) -> void:
	_acc += delta
	if _acc < CHECK_EVERY:
		return
	var dt := _acc
	_acc = 0.0
	var crew := _last_men()
	if crew.is_empty():
		_reset()
		return
	for g in crew:
		if _in_sights(g):
			_reset()
			return
	hidden_t += dt
	_reveal_t -= dt
	_hunt_t -= dt
	if hidden_t >= PUSH_AFTER and _hunt_t <= 0.0:
		_hunt_t = RE_HUNT_EVERY
		pushed = true
		for g in crew:
			if not g.hunt():
				_put_back(g)
	if hidden_t >= REVEAL_AFTER and _reveal_t <= 0.0:
		_reveal_t = REVEAL_EVERY
		_reveal(crew)
	if hidden_t >= RELOCATE_AFTER:
		for g in crew:
			_put_back(g)
		# Back on his way: the clock runs on from the push (so the marker comes again, the next relocation later).
		hidden_t = PUSH_AFTER
		_hunt_t = RE_HUNT_EVERY

func _reset() -> void:
	hidden_t = 0.0
	pushed = false
	_reveal_t = 0.0
	_hunt_t = 0.0

## The men left, when it is the end of the wave: nobody more to come, two or fewer on their feet.
func _last_men() -> Array:
	if spawner == null or not ZombieMode.active or ZombieMode.over or int(spawner.get("round_no")) == 0:
		return []
	if int(spawner.get("released")) < int(spawner.get("total")):
		return []
	var out: Array = []
	for g in get_tree().get_nodes_in_group("gangsters"):
		if is_instance_valid(g) and g.is_alive() and not g.downed and not bool(g.get_meta("prewarm", false)):
			out.append(g)
	return out if out.size() <= 2 else []

## A clear line from the player's eye to the man's head or chest (nothing but chain-link between).
func _in_sights(g: Node3D) -> bool:
	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if cam == null or player == null:
		return true
	if cam.global_position.distance_to(g.global_position) > SIGHT_RANGE:
		return false
	var space := g.get_world_3d().direct_space_state
	var ex: Array[RID] = [g.get_rid(), player.get_rid()]
	for h in [1.45, 0.9]:
		if g.first_wall(space, cam.global_position, g.global_position + Vector3(0, h, 0), ex).is_empty():
			return true
	return false

func _reveal(crew: Array) -> void:
	reveals += 1
	var hud := get_tree().get_first_node_in_group("zombie_hud")
	for g in crew:
		g.bark("taunt", true)
		if hud != null and hud.has_method("reveal"):
			hud.reveal(g.global_position + Vector3(0, 1.0, 0))
	SFX.play("blip", -5.0, 0.62)

## Back on a spawn point out of sight, and on his way. (Nowhere out of sight right now: tried again later.)
func _put_back(g: Node3D) -> void:
	if spawner != null and spawner.relocate(g):
		relocations += 1
		g.hunt()
