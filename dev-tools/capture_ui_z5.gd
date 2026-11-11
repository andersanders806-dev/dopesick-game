extends SceneTree
## Dev helper: the pro UI in a window -> .pilot/ui_*.png (title, settings, pause over the block, the HUD, game over).
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_ui_z5.gd
var out := ""

func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/ui_%s.png" % [out, label])

func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	await process_frame
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(3.0)
	await _snap("title")
	var title := current_scene
	title.call("_on_settings")
	await _wait(0.8)
	await _snap("settings")
	for n in root.get_children():
		if n is CanvasLayer and n.has_signal("closed"):
			n.queue_free()
	title.call("_choose_view", Callable(title, "_start_zombies"), true)
	await _wait(0.6)
	await _snap("title_zombies")
	var zm := root.get_node("ZombieMode")
	root.get_node("GameState").no_sickness = true
	zm.begin(true)
	change_scene_to_file("res://world/City3D.tscn")
	await _wait(2.0)
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	block.surge.enabled = false
	block.spawner.enabled = false
	zm.health = 1e9
	await _wait(4.0)
	await _snap("hud")
	var pm = load("res://ui/PauseMenu.gd").new()
	root.add_child(pm)
	pm.open()
	await _wait(0.8)
	await _snap("pause")
	pm._close()
	zm.health = 0.0
	zm.points = 1250
	zm.kills = 17
	zm.headshots = 6
	zm.game_over()
	await _wait(1.0)
	await _snap("game_over")
	quit()
