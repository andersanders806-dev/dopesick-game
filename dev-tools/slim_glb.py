"""Slims a character .glb's animations in place: keeps only rotation
channels (plus the pelvis's translation, which carries the bob of a walk),
drops every other key on slow clips, and repacks the binary buffer.

Blender's glTF exporter writes translation, rotation and scale for every
bone of a skeletal animation even when only the rotations move, which on a
Rocketbox avatar is two thirds of the animation data for nothing.

  python3 -I dev-tools/slim_glb.py <file.glb> [slow,clip,names]
"""
import json, struct, sys

KEEP_TRANSLATION = {"Bip01 Pelvis", "Bip01"}
SLOW = set((sys.argv[2] if len(sys.argv) > 2 else "idle,sit,idle_sick,crouch").split(","))
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

path = sys.argv[1]
data = open(path, "rb").read()
jlen = struct.unpack("<I", data[12:16])[0]
gltf = json.loads(data[20:20 + jlen])
bin_off = 20 + jlen
blen = struct.unpack("<I", data[bin_off:bin_off + 4])[0]
blob = data[bin_off + 8:bin_off + 8 + blen]
views, accessors = gltf["bufferViews"], gltf["accessors"]

def acc_bytes(i):
    a = accessors[i]
    v = views[a["bufferView"]]
    n = COMPONENTS[a["type"]] * a["count"] * 4  # all animation data is float32
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    return blob[start:start + n]

new_blob = bytearray()
new_views = []
def add_view(raw, target=None):
    while len(new_blob) % 4:
        new_blob.append(0)
    v = {"buffer": 0, "byteOffset": len(new_blob), "byteLength": len(raw)}
    if target:
        v["target"] = target
    new_blob.extend(raw)
    new_views.append(v)
    return len(new_views) - 1

# Everything that isn't animation keeps its bytes, re-laid out.
anim_accessors = set()
for anim in gltf.get("animations", []):
    for s in anim["samplers"]:
        anim_accessors.update((s["input"], s["output"]))
view_map = {}
for i, a in enumerate(accessors):
    if i in anim_accessors or "bufferView" not in a:
        continue
    bv = a["bufferView"]
    if bv not in view_map:
        v = views[bv]
        raw = blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        view_map[bv] = add_view(raw, v.get("target"))
        if "byteStride" in v:
            new_views[view_map[bv]]["byteStride"] = v["byteStride"]
for img in gltf.get("images", []):
    bv = img["bufferView"]
    if bv not in view_map:
        v = views[bv]
        view_map[bv] = add_view(blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])
for a in accessors:
    if "bufferView" in a and a["bufferView"] in view_map:
        a["bufferView"] = view_map[a["bufferView"]]
for img in gltf.get("images", []):
    img["bufferView"] = view_map[img["bufferView"]]

def new_accessor(floats_raw, template, count):
    a = {k: v for k, v in template.items() if k not in ("bufferView", "byteOffset", "min", "max")}
    a["bufferView"] = add_view(floats_raw)
    a["count"] = count
    if template["type"] == "SCALAR":
        vals = struct.unpack("<%df" % count, floats_raw)
        a["min"], a["max"] = [min(vals)], [max(vals)]
    accessors.append(a)
    return len(accessors) - 1

nodes = gltf["nodes"]
before = after = 0
for anim in gltf.get("animations", []):
    step = 2 if anim["name"] in SLOW else 1
    samplers, channels, cache = [], [], {}
    for ch in anim["channels"]:
        before += 1
        target = ch["target"]
        name = nodes[target["node"]].get("name", "")
        if target["path"] == "scale" or (target["path"] == "translation" and name not in KEEP_TRANSLATION):
            continue
        s = anim["samplers"][ch["sampler"]]
        if s.get("interpolation", "LINEAR") == "CUBICSPLINE":
            step_here = 1
        else:
            step_here = step
        inp, out = accessors[s["input"]], accessors[s["output"]]
        count = inp["count"]
        keep = list(range(0, count, step_here))
        if keep[-1] != count - 1:
            keep.append(count - 1)
        if s["input"] not in cache:
            times = struct.unpack("<%df" % count, acc_bytes(s["input"]))
            cache[s["input"]] = new_accessor(struct.pack("<%df" % len(keep), *[times[i] for i in keep]), inp, len(keep))
        comps = COMPONENTS[out["type"]]
        vals = struct.unpack("<%df" % (count * comps), acc_bytes(s["output"]))
        kept = [v for i in keep for v in vals[i * comps:(i + 1) * comps]]
        out_i = new_accessor(struct.pack("<%df" % len(kept), *kept), out, len(keep))
        samplers.append({"input": cache[s["input"]], "output": out_i, "interpolation": s.get("interpolation", "LINEAR")})
        channels.append({"sampler": len(samplers) - 1, "target": target})
        after += 1
    anim["samplers"], anim["channels"] = samplers, channels

# Drop the old animation accessors, renumbering the rest.
old = sorted(anim_accessors)
remap, kept_acc = {}, []
for i, a in enumerate(accessors):
    if i in anim_accessors:
        continue
    remap[i] = len(kept_acc)
    kept_acc.append(a)
gltf["accessors"] = kept_acc
def fix(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ("indices", "inverseBindMatrices", "input", "output") and isinstance(v, int):
                obj[k] = remap[v]
            elif k == "attributes" or k == "targets":
                if isinstance(v, dict):
                    for ak in v:
                        v[ak] = remap[v[ak]]
                else:
                    for t in v:
                        for ak in t:
                            t[ak] = remap[t[ak]]
            else:
                fix(v)
    elif isinstance(obj, list):
        for x in obj:
            fix(x)
for key in ("meshes", "skins", "animations"):
    fix(gltf.get(key, []))

gltf["bufferViews"] = new_views
gltf["buffers"] = [{"byteLength": len(new_blob)}]
while len(new_blob) % 4:
    new_blob.append(0)
js = json.dumps(gltf, separators=(",", ":")).encode()
while len(js) % 4:
    js += b" "
total = 12 + 8 + len(js) + 8 + len(new_blob)
out = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(new_blob), 0x004E4942) + bytes(new_blob)
open(path, "wb").write(out)
print("slimmed %s: %d -> %d channels, %d -> %d KB" % (path, before, after, len(data) // 1024, len(out) // 1024))
