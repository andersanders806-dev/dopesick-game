extends MultiMeshInstance3D
## A MultiMesh laid out by build_rooms_3d.gd (chain-link fences): the
## builder runs headless, where the renderer keeps no instance data for
## the scene to save, so the transforms ride along as an export and go
## into the buffer on load.

@export var transforms: Array[Transform3D] = []

func _ready() -> void:
	if multimesh.instance_count != transforms.size():
		multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
