extends SceneTree
## Z5: the zombie block's wet night is built: wet paving, lamp halos, rain with its setting, a cold sky and
## ground mist, sodium pools, and the quake's dust and cracks use the new materials.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_atmos.gd
var failures := 0

func _check(ok: bool, what: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	root.get_node("ZombieMode").begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 40:
		await process_frame
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	var a: Node = block.atmos
	_check(a != null and a.wet_count() >= 2, "  the paving is wet (%d materials)" % (a.wet_count() if a else 0))
	_check(a != null and a.halo_count() >= 6, "  the streetlights have a haze halo (%d)" % (a.halo_count() if a else 0))
	var env: Environment = block.city._env
	_check(env.fog_height_density > 0.0 and env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY, "  ground mist and a sky to reflect")
	_check(env.background_color.b > env.background_color.r and env.ambient_light_color.b > env.ambient_light_color.r, "  a cold blue night, no red wash")
	var lamp := current_scene.find_child("Streetlight1", true, false).get_node("Light") as OmniLight3D
	_check(lamp.light_color.r > lamp.light_color.b * 2.0 and lamp.omni_attenuation > 1.0, "  sodium lamps with a falloff")
	var gfx := root.get_node("Graphics")
	var rain: Node3D = a.rain
	gfx.set_rain_fx(true)
	await process_frame
	await process_frame
	_check(rain.visible and rain.streaks.emitting, "  rain on")
	gfx.set_rain_fx(false)
	await process_frame
	await process_frame
	_check(not rain.visible and not rain.streaks.emitting, "  Settings > rain off puts it out")
	gfx.set_rain_fx(true)
	var q = block.quake
	var m = q._bursts[0].mesh.material
	_check(m is ShaderMaterial, "  the dust is soft shader puffs, not flat discs")
	_check(q._decals[0].texture_normal != null and q._decals[0].texture_emission != null, "  the cracks have edges and only an ember glint")
	print("PASS (0 failure(s))" if failures == 0 else "FAIL (%d failure(s))" % failures)
	quit(1 if failures else 0)
