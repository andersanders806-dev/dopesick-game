extends SceneTree
## Pre-generates every NPC's small talk as speech (autoload/Voice.gd) by
## loading each room -- NPCs and guards queue their own lines as they load
## -- and waiting for Piper to work through the queue. Lines that depend on
## the moment (prices, item names) are still generated the first time
## they come up in play.
##   godot --headless --path . -s res://dev-tools/bake_voices.gd

const ROOMS := ["Apartment3D", "City3D", "DiveBar3D", "StoreConvenience3D", "StorePharmacy3D",
	"StoreSupermarket3D", "StoreLiquor3D", "StoreElectronics3D", "Jail3D", "Shelter3D", "Pawn3D", "Backyard3D"]

func _initialize() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var voice := root.get_node("Voice")
	gs.clock_running = false
	for clock in [8 * 60, 14 * 60, 22 * 60]:
		gs.clock = clock
		for room in ROOMS:
			change_scene_to_file("res://world/%s.tscn" % room)
			for i in 20:
				await process_frame
	while true:
		voice._mutex.lock()
		var left: int = voice._jobs.size()
		voice._mutex.unlock()
		print("lines left: ", left)
		if left == 0:
			break
		await create_timer(2.0).timeout
	await create_timer(2.0).timeout
	print("baked: ", DirAccess.get_files_at("res://assets/voice").size(), " lines")
	quit()
