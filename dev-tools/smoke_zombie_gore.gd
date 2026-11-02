extends "res://dev-tools/smoke_test_3d.gd"
## Dead Block's gore checks (zombie mode, task Z6): wounds, severed limbs, head pops, legless crawlers,
## decals / gibs / pools within their caps, one payout for a blast that takes several parts, the option.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_gore.gd
func _run() -> void:
	await _zombie_gore_checks(_gs())
