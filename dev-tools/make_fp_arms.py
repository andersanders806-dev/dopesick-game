"""Cuts the first-person arms out of a Rocketbox avatar (Male_Adult_20, the
player's own body), in headless Blender:

  blender -b --python dev-tools/make_fp_arms.py -- assets/rocketbox/Male_Adult_20.glb assets/viewmodel/arms.glb

Keeps the mesh vertices that belong (by skin weight) to the upper arms,
forearms, hands and fingers, drops the Icosphere helper and everything else
(head, torso, legs), and keeps the whole Bip01 armature so the arms still
share the skeleton of the other Rocketbox bodies. Microsoft Rocketbox, MIT.
"""
import sys
import bpy
import bmesh

src, dst = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

KEEP = ("UpperArm", "Forearm", "Hand", "Finger")

for o in list(bpy.data.objects):
    if o.type == "MESH" and not o.vertex_groups:
        bpy.data.objects.remove(o, do_unlink=True)

body = next(o for o in bpy.data.objects if o.type == "MESH")
keep_groups = {g.index for g in body.vertex_groups if any(k in g.name for k in KEEP)}

# The upper arms are not wanted in a first-person picture (the shoulder end would
# fill the screen at the camera's plane): keep the forearm, the hand and a hand's
# width of the upper arm above each elbow. Positions are tested in world space
# against the elbow-shoulder line of the armature's bones.
armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
UPPER_KEEP = 0.12  # of the upper arm's length, measured up from the elbow
cuts = []
for side in ("L", "R"):
    ua = armature.data.bones["Bip01 %s UpperArm" % side]
    fa = armature.data.bones["Bip01 %s Forearm" % side]
    shoulder = armature.matrix_world @ ua.head_local
    elbow = armature.matrix_world @ fa.head_local
    axis = shoulder - elbow
    cuts.append((side, elbow, axis.normalized(), axis.length * UPPER_KEEP))

bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="EDIT")
bm = bmesh.from_edit_mesh(body.data)
deform = bm.verts.layers.deform.verify()
doomed = []
for v in bm.verts:
    w = v[deform]
    total = sum(w.values()) or 1.0
    arm = sum(val for gi, val in w.items() if gi in keep_groups)
    if arm / total < 0.5:
        doomed.append(v)
        continue
    # the side of the body this vertex belongs to (the nearer elbow), and whether it is above the cut
    world = body.matrix_world @ v.co
    side, elbow, axis, keep = min(cuts, key=lambda c: (world - c[1]).length)
    if (world - elbow).dot(axis) > keep:
        doomed.append(v)
bmesh.ops.delete(bm, geom=doomed, context="VERTS")
bmesh.update_edit_mesh(body.data)
bpy.ops.object.mode_set(mode="OBJECT")
print("ARMS verts left", len(body.data.vertices), "polys", len(body.data.polygons))

# Only the materials still used.
used = {p.material_index for p in body.data.polygons}
print("ARMS materials used", sorted(used), [m.name if m else None for m in body.data.materials])

# What each vertex wears, in a second UV map (the viewmodel shader reads UV2): x = glove (the
# hand and the first fingers' segments), y = sleeve (the arm). Both 0 is a bare fingertip
# (fingerless gloves: the last segment of each finger and thumb).
me = body.data
vg_name = {g.index: g.name for g in body.vertex_groups}
mask = {}
for v in me.vertices:
    glove = sleeve = 0.0
    total = 0.0
    for g in v.groups:
        n = vg_name.get(g.group, "")
        total += g.weight
        if "Finger" in n and n.endswith("2"):
            pass
        elif "Hand" in n or "Finger" in n:
            glove += g.weight
        elif "Forearm" in n or "UpperArm" in n:
            sleeve += g.weight
    total = total or 1.0
    mask[v.index] = (min(glove / total, 1.0), min(sleeve / total, 1.0))
layer = me.uv_layers.new(name="Mask")
for loop in me.loops:
    m = mask[loop.vertex_index]
    layer.data[loop.index].uv = (m[0], 1.0 - m[1])  # the exporter flips V
print("ARMS mask uv written", [u.name for u in me.uv_layers])

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_skins=True, export_animations=False,
                          export_apply=False, export_yup=True)
print("ARMS wrote", dst)
