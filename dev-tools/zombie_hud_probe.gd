extends SceneTree
## Dev helper: opens a zombie run, pushes the round and points high, shows the
## round banner and saves the screen at a few window sizes, so the HUD can be
## checked for anything outside the window.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/zombie_hud_probe.gd
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 768), Vector2i(2560, 1080), Vector2i(800, 600)]

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	change_scene_to_file(zm.CITY_SCENE)
	for i in 90:
		await process_frame
	zm.points = 1234567
	zm.round = 104
	zm.start_round()
	for i in 40:
		await process_frame
	for s in SIZES:
		root.size = s
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.pilot/zhud/hud_%dx%d.png" % [s.x, s.y]))
	quit()
