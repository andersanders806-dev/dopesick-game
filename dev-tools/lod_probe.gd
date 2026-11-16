extends SceneTree
## Headless check: what a zombie's AnimationPlayer carries (clips and tracks).
func _initialize() -> void:
	var Z = load("res://npc/Zombie3D.gd")
	var CC = load("res://npc/CharacterCast.gd")
	var CA = load("res://npc/CharacterAnimator.gd")
	var inst: Node = CC.scene_for(Z.MODEL_DIR + Z.BODIES[0] + ".glb").instantiate()
	var p := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var report := func(tag: String):
		var clips := 0
		var tracks := 0
		for lib in p.get_animation_library_list():
			var l := p.get_animation_library(lib)
			for n in l.get_animation_list():
				clips += 1
				tracks += l.get_animation(n).get_track_count()
		print("%s: libraries %s clips %d tracks %d" % [tag, p.get_animation_library_list(), clips, tracks])
	report.call("glb")
	CA.install_zombie_library(inst)
	report.call("+zombie")
	CA.install_gang_library(inst)
	report.call("+gang")
	quit()
