"""Converts a Microsoft Rocketbox avatar (MIT) into one game-ready .glb for
Dope Sick: the mesh and its Bip01 skeleton, the textures shrunk to 1024 px,
and the clips the game asks for baked in under the names CharacterAnimator
resolves (idle, walk, sprint, sit, ...).

Run in Blender (headless):
  blender -b -P dev-tools/rocketbox_to_glb.py -- <avatar.fbx> <anim_dir> <out.glb> [m|f] [texture px]

<anim_dir> holds the Rocketbox animation FBXs, named as in the repo minus
".max" (m_walk_neutral_01.fbx, ...). Clips are taken from the "xy" set for
moving ones (motion extracted, so they walk on the spot) and "static" for
the rest; see dev-tools/fetch_rocketbox.py.
"""
import bpy, sys, os

args = sys.argv[sys.argv.index("--") + 1:]
avatar_fbx, anim_dir, out_glb = args[0], args[1], args[2]
sex = args[3] if len(args) > 3 else "m"

# Game clip name -> Rocketbox animation (prefix m_/f_ added per sex). The
# first one that exists is used.
CLIPS = {
    "idle": ["idle_neutral_01"],
    "walk": ["walk_neutral_01", "walk_neutral"],
    "sprint": ["run_neutral", "run_neutral_01"],
    "sit": ["sit_chair_idle_neutral_01"],
    # Withdrawal and a beating: the walks a sick or hurt body actually does.
    "walk_sick": ["walk_bruised", "walk_injured", "walk_drunk"],
    "idle_sick": ["idle_nervous_01"],
    "crouch": ["crouch_idle"],
    # Reaching out and taking something: lifting an item off a shelf, and
    # the pusher's hand-to-hand.
    "take": ["documents_take"],
}
TEXTURE_SIZE = int(args[4]) if len(args) > 4 else 1024
## Long idles are trimmed (frames at 30 fps): sitting at the bar for 36 s
## without repeating isn't worth 1.5 MB a character.
MAX_FRAMES = {"sit": 360, "idle_sick": 360, "crouch": 200}
## Slow clips keep every other frame (15 fps); walks and runs keep all 30.
SLOW = {"idle", "sit", "idle_sick", "crouch"}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=avatar_fbx)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
for o in list(bpy.data.objects):
    if o.type == "EMPTY":
        bpy.data.objects.remove(o)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
arm.animation_data_create()

# Each animation comes in on its own armature, whose rest pose is the
# clip's first frame -- not the avatar's A-pose -- so its action can't just
# be reassigned (the body stays in A-pose). Instead every avatar bone
# follows the clip's bone of the same name in world space (rotation; the
# pelvis also its position) and that's baked into a fresh action.
def fcurves_of(act):
    # Blender 5 keeps an action's curves in per-slot channel bags.
    if hasattr(act, "layers"):
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield bag
    else:
        yield act

def slim(act, step):
    """Only rotations move (and the pelvis's position): constant location
    and scale curves on 79 bones are two thirds of the data for nothing.
    Slow clips also drop every other key."""
    for bag in fcurves_of(act):
        for fc in list(bag.fcurves):
            keep = fc.data_path.endswith("rotation_quaternion") or fc.data_path.endswith("rotation_euler") \
                or (fc.data_path.endswith("location") and "Bip01 Pelvis" in fc.data_path)
            if not keep:
                bag.fcurves.remove(fc)
            elif step > 1:
                pts = fc.keyframe_points
                for i in range(len(pts) - 2, 0, -1):
                    if i % step:
                        pts.remove(pts[i])

def bake_clip(src_arm, clip, frames, step=1):
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    names = set(b.name for b in src_arm.pose.bones)
    for pb in arm.pose.bones:
        if pb.name not in names:
            continue
        c = pb.constraints.new("COPY_ROTATION")
        c.target = src_arm
        c.subtarget = pb.name
        if pb.name == "Bip01 Pelvis":
            c = pb.constraints.new("COPY_LOCATION")
            c.target = src_arm
            c.subtarget = pb.name
    arm.animation_data.action = None
    bpy.ops.nla.bake(frame_start=frames[0], frame_end=frames[1], only_selected=False, visual_keying=True,
        clear_constraints=True, use_current_action=False, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    act = arm.animation_data.action
    arm.animation_data.action = None
    slim(act, step)
    act.name = clip
    act.use_fake_user = True
    track = arm.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, frames[0], act)
    track.mute = True
    return act

for clip, names in CLIPS.items():
    for n in names:
        path = os.path.join(anim_dir, "%s_%s.fbx" % (sex, n))
        if not os.path.exists(path):
            continue
        before = set(bpy.data.objects)
        before_actions = set(bpy.data.actions)
        bpy.ops.import_scene.fbx(filepath=path)
        new_arm = next((o for o in set(bpy.data.objects) - before if o.type == "ARMATURE"), None)
        src = new_arm.animation_data.action if new_arm and new_arm.animation_data else None
        if src:
            frames = (int(src.frame_range[0]), int(src.frame_range[1]))
            if clip in MAX_FRAMES:
                frames = (frames[0], min(frames[1], frames[0] + MAX_FRAMES[clip]))
            act = bake_clip(new_arm, clip, frames, 2 if clip in SLOW else 1)
            print("CLIP", clip, "<-", n, frames)
        for a in [a for a in bpy.data.actions if a not in before_actions and a.name != clip]:
            bpy.data.actions.remove(a)
        for o in set(bpy.data.objects) - before:
            bpy.data.objects.remove(o)
        break
    else:
        print("MISSING CLIP", clip)

# Textures: smaller, and skin that isn't plastic. Rocketbox's specular maps
# aren't shipped with every avatar, so roughness is set flat.
for m in bpy.data.materials:
    if not m.node_tree:
        continue
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            img = n.image
            if img.size[0] == 0:
                # A texture path that doesn't resolve (the missing specular):
                # drop the node rather than export a broken image.
                m.node_tree.nodes.remove(n)
                continue
            # Normal maps carry fine detail nobody sees at 11 m: half size.
            size = TEXTURE_SIZE // 2 if "normal" in img.name.lower() else TEXTURE_SIZE
            if img.size[0] > size:
                img.scale(size, size)
        if n.type == "BSDF_PRINCIPLED":
            for link in list(n.inputs["Specular IOR Level"].links if "Specular IOR Level" in n.inputs else []):
                m.node_tree.links.remove(link)
            for link in list(n.inputs["Roughness"].links):
                m.node_tree.links.remove(link)
            n.inputs["Roughness"].default_value = 0.62
            n.inputs["Metallic"].default_value = 0.0
    if "opacity" in m.name:
        # Hair, lashes, brows: cut out, not blended, so they sort right.
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "DITHERED"
        m.blend_method = "CLIP" if hasattr(m, "blend_method") else None

bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(
    filepath=out_glb,
    export_format="GLB",
    use_selection=True,
    export_image_format="JPEG",
    export_jpeg_quality=88,
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_force_sampling=False,
    export_optimize_animation_size=True,
    export_def_bones=True,
    export_apply=False,
)
print("WROTE", out_glb, os.path.getsize(out_glb) // 1024, "KB")
