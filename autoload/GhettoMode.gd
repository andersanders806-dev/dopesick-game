extends Node
## Ghetto Wars' public face for the layers built on top of it (the story, the set dressing): signals to listen to
## and one call to put a crowd on the street. The state itself (waves, points, plates, health) is ZombieMode's,
## since the mode shares the round shell with Dead Block; `ZombieMode.gangs` says which of the two is running.

## A wave begins / is cleared (n: 1..).
signal wave_started(n: int)
signal wave_cleared(n: int)
## `e` died; `how`: "head", "body", "melee" or "explosion".
signal enemy_killed(e: Node, how: String)
## The player is down: the run is over.
signal player_downed
## A crewman was finished off (or let bleed out) while down; `finished` says which.
signal enemy_downed_resolved(e: Node, finished: bool)

var active: bool:
	get: return ZombieMode.active and ZombieMode.gangs

func _ready() -> void:
	ZombieMode.round_started.connect(func(r: int): if ZombieMode.gangs: wave_started.emit(r))
	ZombieMode.round_ended.connect(func(r: int): if ZombieMode.gangs: wave_cleared.emit(r))
	ZombieMode.game_over_started.connect(func(_s: Dictionary): if ZombieMode.gangs: player_downed.emit())

## Starts a run from the title (first person).
func start() -> void:
	ZombieMode.start_gangs()

## Crowd on the street now: {count: int, weapons: [gun ids], crew: String, from_points: [Vector3],
## drive_by: bool, heavy: bool}. Returns the Gangster3D nodes made ([] outside a run).
func spawn_wave(def: Dictionary) -> Array:
	var sp := get_tree().get_first_node_in_group("gang_spawner")
	if sp == null or not active:
		return []
	return sp.spawn_wave(def)

## How many of the crew are alive.
func alive() -> int:
	return get_tree().get_nodes_in_group("gangsters").size()
