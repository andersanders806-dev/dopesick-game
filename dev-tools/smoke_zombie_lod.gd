extends "res://dev-tools/smoke_test_3d.gd"
## The far LOD of the dead (Task Z4c): a zombie far from the player updates its pose, its brain and its
## shadow less often; a near one is untouched; the hit zones are right at any distance.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_lod.gd
func _run() -> void:
	await _zombie_lod_checks(_gs())

## How many times a left-thigh bone changes pose over `n` rendered frames.
func _pose_changes(z: Node, n: int) -> int:
	var sk: Skeleton3D = z._skeleton
	var bone := sk.find_bone("Bip01 L Thigh")
	var last := sk.get_bone_pose_rotation(bone)
	var changes := 0
	for i in n:
		await process_frame
		var q := sk.get_bone_pose_rotation(bone)
		if not q.is_equal_approx(last):
			changes += 1
			last = q
	return changes

func _zombie_lod_checks(_gs_node: Node) -> void:
	await _section("Dead LOD: far zombies are cheaper, near ones are not, hits stay right")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	DirAccess.remove_absolute(zm.PATH)
	zm.begin(false)
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	var spawner: Node = city.get_node("ZombieBlock").spawner
	spawner.enabled = false
	for old in get_nodes_in_group("zombies"):
		old.free()
	var player := _player()
	player.global_position = Vector3(-40.0, 0.0, -1.0)
	player.velocity = Vector3.ZERO
	spawner.round_no = 1
	var Z: GDScript = load("res://npc/Zombie3D.gd")
	var Hit: GDScript = load("res://npc/ZombieHitboxes.gd")

	# --- The tiers, with hysteresis ---
	_check(Z.lod_for(5.0, 0) == 0 and Z.lod_for(20.0, 0) == 1 and Z.lod_for(40.0, 0) == 2 and Z.lod_for(70.0, 0) == 3,
		"  tiers by distance: 5 m 0, 20 m 1, 40 m 2, 70 m 3")
	_check(Z.lod_for(14.0, 1) == 1 and Z.lod_for(14.0, 0) == 0 and Z.lod_for(12.5, 1) == 0 and Z.lod_for(31.0, 2) == 2 and Z.lod_for(31.0, 1) == 1,
		"  a tier is held 2 m past its edge (no flicker)")
	_check(Z.lod_period(0) == 1 and Z.lod_period(1) == 2 and Z.lod_period(2) == 4 and Z.lod_period(3) == 8, "  pose period 1, 2, 4, 8 frames")

	# --- Live zombies at 5, 20, 40 and 70 m, standing in place ---
	var by := {}
	for e in [[5.0, "near"], [20.0, "mid"], [40.0, "far"], [70.0, "vfar"]]:
		var zz = spawner.spawn_one("walker", Vector3(-40.0 + e[0], 0.0, 1.0))
		zz.speed = 0.0
		by[e[1]] = zz
	await _frames(40)
	for k in by:
		by[k]._anim_player.seek(0.0, true)
	var tiers := {"near": by["near"]._lod, "mid": by["mid"]._lod, "far": by["far"]._lod, "vfar": by["vfar"]._lod}
	_check(tiers == {"near": 0, "mid": 1, "far": 2, "vfar": 3}, "  the physics tick puts them on tiers 0, 1, 2, 3 (%s)" % [tiers])
	var shadow_of := func(zz): return (zz.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).cast_shadow
	_check(shadow_of.call(by["near"]) == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and shadow_of.call(by["mid"]) == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and shadow_of.call(by["vfar"]) == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"  near ones cast a shadow, 20 m and beyond do not")
	_check(by["near"]._anim_player.callback_mode_process == AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE and not by["near"].is_processing()
		and by["vfar"]._anim_player.callback_mode_process == AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL and by["vfar"].is_processing(),
		"  near: the AnimationPlayer runs itself, no hand stepping; far: stepped by hand")
	var near_mi: MeshInstance3D = by["near"]._lod_meshes[0]
	var far_mi: MeshInstance3D = by["far"]._lod_meshes[0]
	var mid_mi: MeshInstance3D = by["mid"]._lod_meshes[0]
	_check(float(near_mi.get_instance_shader_parameter("far_lod")) == 0.0 and float(mid_mi.get_instance_shader_parameter("far_lod")) == 0.0
		and float(far_mi.get_instance_shader_parameter("far_lod")) == 1.0,
		"  the cheaper rot shader only from 32 m (near and 20 m look as before)")

	# How often the pose changes over 64 rendered frames.
	var n := 64
	var counts := {}
	for k in by:
		counts[k] = 0
	var sks := {}
	for k in by:
		var sk: Skeleton3D = by[k]._skeleton
		sks[k] = [sk, sk.find_bone("Bip01 L Thigh"), sk.get_bone_pose_rotation(sk.find_bone("Bip01 L Thigh"))]
	for i in n:
		await process_frame
		for k in by:
			var q: Quaternion = (sks[k][0] as Skeleton3D).get_bone_pose_rotation(sks[k][1])
			if not q.is_equal_approx(sks[k][2]):
				counts[k] += 1
				sks[k][2] = q
	print("    pose changes in %d frames: %s" % [n, counts])
	_check(counts["near"] >= n * 0.85, "  a near zombie's pose changes nearly every frame (%d of %d)" % [counts["near"], n])
	_check(absi(counts["mid"] - n / 2) <= 6, "  at 20 m about every 2nd frame (%d of %d)" % [counts["mid"], n])
	_check(absi(counts["far"] - n / 4) <= 4, "  at 40 m about every 4th frame (%d of %d)" % [counts["far"], n])
	_check(absi(counts["vfar"] - n / 8) <= 3, "  at 70 m about every 8th frame (%d of %d)" % [counts["vfar"], n])

	# The walk keeps its pace: a far zombie's clip time moves as fast as a near one's (owed time is paid).
	var clip_t := func(zz): return zz._anim_player.current_animation_position
	var cur: String = by["near"]._anim_player.current_animation
	for k in by:
		by[k]._anim_player.play("z_walk" if by[k]._anim_player.has_animation("z_walk") else cur)
		by[k]._anim_player.seek(0.0, true)
	var t0 := Time.get_ticks_msec()
	for i in 24:
		await process_frame
	var el := (Time.get_ticks_msec() - t0) / 1000.0
	var pos := {}
	for k in by:
		pos[k] = clip_t.call(by[k])
	# (the idle/walk rate is set by the brain each tick, so compare far to near, which share the clip)
	_check(absf(pos["vfar"] - pos["near"]) < 0.25 + el * 0.25 and absf(pos["far"] - pos["near"]) < 0.25 + el * 0.25,
		"  a far zombie's clip time keeps up with a near one's (near %.2f, 40 m %.2f, 70 m %.2f after %.2f s)" % [pos["near"], pos["far"], pos["vfar"], el])

	# --- The brain thins out with distance ---
	var ticks := {}
	for e in [[10.0, "near"], [40.0, "mid"], [70.0, "far"]]:
		var tz = by["near"]
		var c := 0
		for f in 8:
			tz._frame = f
			if tz._think_now(e[0] * e[0]):
				c += 1
		ticks[e[1]] = c
	_check(ticks == {"near": 8, "mid": 4, "far": 2}, "  the brain runs on 8, 4, 2 of 8 ticks at 10, 40, 70 m (%s)" % [ticks])
	# ... and still covers the ground.
	for k in by:
		by[k].free()
	player.global_position = Vector3(-60.0, 0.0, 1.0)
	var runner = spawner.spawn_one("walker", Vector3(15.0, 0.0, 1.0))
	runner.speed = 1.6
	var walker = spawner.spawn_one("walker", Vector3(-45.0, 0.0, 1.0))
	walker.speed = 1.6
	await _frames(20)
	var p0: Vector3 = runner.global_position
	var q0: Vector3 = walker.global_position
	var f0 := Engine.get_physics_frames()
	await _frames(150)
	var secs := (Engine.get_physics_frames() - f0) / float(Engine.physics_ticks_per_second)
	var far_went: float = Vector2(runner.global_position.x - p0.x, runner.global_position.z - p0.z).length()
	var near_went: float = Vector2(walker.global_position.x - q0.x, walker.global_position.z - q0.z).length()
	_check(runner._lod == 3 and walker._lod <= 1 and far_went > near_went * 0.8 and far_went > 1.6 * secs * 0.6,
		"  a zombie at 75 m covers the ground a near one does (%.1f m vs %.1f m in %.1f s, tiers %d and %d)" % [far_went, near_went, secs, runner._lod, walker._lod])
	runner.free()
	walker.free()

	# --- Hit zones at any distance ---
	player.global_position = Vector3(-40.0, 0.0, -1.0)
	var hz = spawner.spawn_one("walker", Vector3(30.0, 0.0, 1.0))
	hz.speed = 0.0
	hz.set_physics_process(false)
	hz.set_lod(3)
	hz._model_root.rotation.y = 0.0
	await _frames(30)
	hz.sync_hitboxes()
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var bad := []
	for p in Hit.PARTS:
		var c: Vector3 = (hz.hitboxes[p].get_child(0) as Node3D).global_position
		var others: Array[RID] = []
		for o in Hit.PARTS:
			if o != p:
				others.append((hz.hitboxes[o] as Area3D).get_rid())
		var q2 := PhysicsRayQueryParameters3D.create(c + Vector3(0.0, 0.0, 2.0), c)
		q2.collide_with_areas = true
		q2.collide_with_bodies = false
		q2.collision_mask = Hit.HITBOX_LAYER
		q2.exclude = others
		var r := space.intersect_ray(q2)
		if r.is_empty() or r["collider"].get_meta("part") != p or r["collider"].get_meta("zombie") != hz:
			bad.append(p)
	_check(bad.is_empty(), "  at 70 m (tier 3, pose stepped by hand) every hit zone is hit at its own centre (wrong: %s)" % [bad])
	# The zones sit on the bones of the pose on screen.
	var sk: Skeleton3D = hz._skeleton
	var off := 0.0
	for p in Hit.PARTS:
		var area := hz.hitboxes[p] as Area3D
		var want: Transform3D = sk.global_transform * sk.get_bone_global_pose(int(area.get_meta("bone")))
		off = maxf(off, (area.global_transform.origin - want.origin).length())
	_check(off < 0.001, "  ... and on the bones as the skeleton has them (worst offset %.4f m)" % off)
	# A real shot through WeaponHolder's path: take_hit at 70 m works and the death plays at full rate.
	hz.set_physics_process(true)
	hz.take_hit("head", hz.max_health * 2.0, Vector3.FORWARD, null)
	await _frames(4)
	_check(not hz.is_alive() and hz._lod == 0 and not hz.is_processing() and hz._anim_player.callback_mode_process == AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE,
		"  a far one shot dead goes back to the AnimationPlayer running itself (lod %d, mode %d)" % [hz._lod, hz._anim_player.callback_mode_process])
	hz.free()
	player.global_position = Vector3(-17.5, 0.0, -3.0)
