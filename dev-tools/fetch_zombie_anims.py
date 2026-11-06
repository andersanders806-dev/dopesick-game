"""Fetches the animation sources for the zombies, then (separately) generates
the clips no free library has.

  python3 -I dev-tools/fetch_zombie_anims.py            # Quaternius UAL1 + UAL2 (CC0)
  python3 -I dev-tools/fetch_zombie_anims.py --kimodo   # + build kimodo.cpp, generate BVH (see below)

Everything lands in ~/.cache/dopesick/ (not the repo): each archive in its own
directory, unzipped into its own. Next step: dev-tools/retarget_to_bip01.py.

Sources and licences (recorded in assets/LICENSES.md, assets/zombie_anims/LICENSE.md):
  Universal Animation Library      by Quaternius, CC0 1.0  https://opengameart.org/content/universal-animation-library
  Universal Animation Library 2    by Quaternius, CC0 1.0  https://opengameart.org/content/universal-animation-library-2

--kimodo [clip ...]: NVIDIA Kimodo (SOMA-RP v1.1 text-to-motion) through kimodo.cpp
(Apache-2.0, https://github.com/localai-org/kimodo.cpp) with the ungated GGUF weights
(LocalAI-io/Kimodo-SOMA-RP-v1.1-GGML, NVIDIA Open Model License: outputs are ours;
text encoder LocalAI-io/Llama-3-Kimodo-GGML Q4_K_M, Meta Llama 3 Community License).
Never the SMPL-X checkpoint (research-only). It clones/builds (CPU only; ~6 GB of
weights; cmake and ninja from a venv in the cache), then keeps ONE `kmd-generate
--server` running and queues every variant x seed of KIMODO_CLIPS: one take dir
~/.cache/dopesick/kimodo/takes/<clip>_<variant>_s<seed>/ with take.bvh (30-joint SOMA,
30 fps, cm) and take.json (prompt, seed, seconds). About 35-50 s per 2 s take on 8 cores.
Look at the takes (retarget_to_bip01.py take:<name> + zombie_anim_probe.gd), then
  python3 -I dev-tools/fetch_zombie_anims.py --kimodo-pick=z_attack=z_attack_e_s3
copies the chosen take to ~/.cache/dopesick/kimodo/best/z_attack.{bvh,json} for the
retarget. HY-Motion/Hunyuan stay out (EU territory exclusion).
"""
import array
import hashlib
import importlib.util
import json
import math
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile

CACHE = os.path.expanduser("~/.cache/dopesick")
ARCHIVES = {
    "ual1": "https://opengameart.org/sites/default/files/universal_animation_librarystandard.zip",
    "ual2": "https://opengameart.org/sites/default/files/universal_animation_library_2standard.zip",
}
KIMODO_REPO = "https://github.com/localai-org/kimodo.cpp"
KIMODO_COMMIT = "ed8a931aedb132f768190f6931c365855caba74c"   # the head the build was done against (2026-10-26)
KIMODO_STEPS = 10   # DDIM steps; the model is distilled enough that 10 reads fine (see the notes in kimodo())

# Zombie attacks: clip -> {variant: [(frames at 30 fps, prompt), ...]}. A variant with
# several segments becomes a multi-prompt --sequence (the model blends between them).
# Kimodo has no real grip on "zombie", so these describe the body mechanics.
# Every variant is tried with every seed in KIMODO_SEEDS; the best take per clip is
# picked by eye (dev-tools/zombie_anim_probe.gd) with --kimodo-pick.
KIMODO_SEEDS = [int(x) for x in os.environ.get("KIMODO_SEEDS", "1,2,3").split(",")]   # KIMODO_SEEDS=1,2 for a quicker pass
KIMODO_EXTRA_SEEDS = {("z_attack", "e"): [4, 5, 6], ("z_attack2", "m"): [4, 5, 6, 7, 8], ("z_crawl", "c"): [4, 5, 6, 7, 8, 9], ("z_crawl", "f"): [4, 5, 6]}   # promising variants get more seeds
# Rounds 1-3 (the log of what was tried): "reaching ... shoulder height" put the hands over
# the head; "lunge" in a two-segment sequence made the body dive and fly; "stands upright ...
# arms straight out at chest height" gave flapping arms or hands on the head. What worked is
# "lunges one step forward ... hands grabbing/clawing at the air at chest level" as ONE prompt.
KIMODO_CLIPS = {
    # --- the other zombie clips (Z2a fix round 1) ---
    "z_crawl": {
        "a": [(90, "A person lies face down on the ground and crawls forward by pulling themselves with both arms, dragging the limp legs behind.")],
        "b": [(90, "A person lying on their stomach drags their body forward using only their arms, pulling with one arm and then the other, legs limp and trailing behind.")],
        # a/b barely moved (lying nearly still, half on the back); c-e ask for known crawl moves.
        "c": [(90, "A soldier does a low crawl forward on the ground, forearms and elbows pulling the body along, one arm reaching forward and then the other, legs dragging behind.")],
        "f": [(90, "A soldier low-crawls forward on their belly, alternately pulling with the left and then the right forearm, dragging the legs behind.")],
        "d": [(90, "A person crawls forward on their hands and knees.")],
        "e": [(90, "A person lying face down on the ground reaches forward with one hand, claws at the ground and pulls the whole body after it, then reaches with the other hand, dragging themselves forward.")],
    },
    "z_scream": {
        "a": [(75, "A person stands hunched, throws their head back and screams with their mouth wide open, arms hanging, chest heaving.")],
        # a: hands over the mouth, hunched (reads as retching); b/c avoid anything near the face.
        "b": [(75, "A person leans the head and torso back, opens both arms wide out to the sides and roars at the sky.")],
        "c": [(75, "A person roars, tilting the head back with the chest pushed out and arms hanging straight down, then snaps the head forward.")],
    },
    "p_kick": {
        "a": [(45, "A person plants their left foot and drives a hard front push kick forward with the right leg, then steps back.")],
        # a was a walk. b-d name the kick itself.
        "b": [(45, "A fighter throws a powerful front kick, lifting the right knee high and snapping the leg straight forward.")],
        "c": [(45, "A person kicks forward with the right foot as hard as they can, like kicking down a door.")],
        "d": [(45, "A person lifts the right knee up and thrusts the foot out in a straight kick.")],
        # b-d kick in a fighter's guard but the take ends mid-extension: e gets 60 frames to recover.
        "e": [(60, "A fighter in a guard stance throws a front kick with the right leg, snapping the leg straight forward, then pulls it back and returns to the guard stance.")],
    },
    "z_walk3": {
        "a": [(90, "A person shambles forward, dragging the right foot, torso hunched forward, arms hanging and swaying, head tilted.")],
    },
    "z_hit_leg": {
        "a": [(45, "A person is struck in the right thigh, the leg buckles and they stumble and drop down onto one knee.")],
    },
    "z_death2": {
        "a": [(75, "A person falls forward onto their face and lies still on the ground.")],
    },
    # --- Z5: bodies that move like bodies (entrances, hurt walks, more attacks, hit reactions) ---
    "z_rise": {   # out of the ground: the hand comes first, the body is dragged after it, then up
        "a": [(120, "A person lies face down on the ground, one hand reaches forward and claws at the dirt, the other hand follows, they drag the chest forward, push up onto the knees and slowly rise to a hunched stand.")],
        "b": [(120, "A person lying on their stomach pushes both hands against the ground, heaves the chest up, pulls one knee under the body, then the other, and stands up slowly, hunched, arms hanging.")],
    },
    "z_land": {   # a drop from a fire escape or roof: heavy crouch, then up
        "a": [(60, "A person drops down from a height and lands heavily in a deep crouch, one hand pressed on the ground, then straightens up slowly, hunched.")],
        "b": [(60, "A person lands from a jump in a low crouch, knees bent deep, torso bent forward, then rises and staggers a step forward.")],
    },
    "z_hit_leg_l": {"a": [(45, "A person is struck in the left thigh, the leg buckles and they stumble and drop down onto one knee.")]},
    "z_hit_arm_r": {"a": [(45, "A person is struck in the right shoulder, the upper body spins to the right with the right arm thrown back, then they steady themselves.")]},
    "z_hit_arm_l": {"a": [(45, "A person is struck in the left shoulder, the upper body spins to the left with the left arm thrown back, then they steady themselves.")]},
    "z_stumble": {"a": [(60, "A person is shoved hard in the chest, staggers backwards several steps with the arms flailing, nearly falls and catches their balance.")]},
    "z_walk4": {   # lurching, uneven
        "a": [(90, "A person lurches forward unevenly, slow then sudden quicker steps, swaying from side to side, the head lolling, the arms swinging loosely.")],
    },
    "z_limp_l": {
        "a": [(90, "A person shambles forward, dragging the left foot, torso hunched forward, arms hanging and swaying, head tilted.")],
    },
    "z_walk_hurt_r": {
        "a": [(90, "A person walks slowly leaning heavily to the right, the right arm hanging limp and motionless, the left arm swinging, head tilted to the right.")],
    },
    "z_walk_hurt_l": {
        "a": [(90, "A person walks slowly leaning heavily to the left, the left arm hanging limp and motionless, the right arm swinging, head tilted to the left.")],
    },
    "z_lunge": {
        "a": [(45, "A hunched person suddenly breaks into a fast lunging stride forward, both arms thrown out in front, hands clawing.")],
        "b": [(45, "A person leaps forward off the back foot with both arms outstretched in front, grabbing, and lands on the front foot.")],
    },
    "z_bite": {
        "a": [(60, "A person grabs someone in front by the shoulders with both hands, pulls them in close and jerks the head forward to bite, then shakes the head from side to side.")],
        "b": [(60, "A person reaches both hands forward, seizes someone, drags them toward the chest and bites down at their neck, then pulls back.")],
    },
    "z_smash": {
        "a": [(60, "A person raises both fists together high above the head and slams them down hard in front of the body, bending forward.")],
        "b": [(60, "A person clasps both hands together, swings them up over the right shoulder and brings them down across the body in a heavy two-handed blow.")],
    },
    # --- the attacks ---
    "z_attack": {
        "b": [(30, "A hunched person steps forward and stretches both arms out in front at shoulder height, hands open like claws, leaning in."),
              (30, "The person grabs and pulls both arms in toward the chest while the head and torso lunge forward to bite.")],
        "c": [(60, "A zombie lurches forward with both arms stretched out straight in front of the body, then grabs and bites.")],
        "e": [(60, "A person lunges one step forward with both arms stretched out horizontally in front, hands grabbing at the air at chest level, then pulls the hands back to the chest.")],
        "h": [(60, "A person lunges one step forward, both arms stretched out in front at chest level, hands clawing and grabbing at the air, then pulls both arms back to the chest and bends forward.")],
    },
    "z_attack2": {
        "a": [(60, "A hunched person swings one arm in a low to mid clawing swipe across the body, raking sideways, then reaches forward with both hands and lunges the head forward to bite.")],
        "h": [(60, "A person lunges one step forward and swipes one arm across the body at chest level, clawing at the air from low to high, then grabs forward with both hands.")],
        "i": [(60, "A person steps forward and rakes the right arm in a wide sideways clawing swipe at waist to chest height, then grabs at the air with both hands in front.")],
        # j/k/l (round 5) read as a boxer's guard and jab, or a standing scratch: not used.
        "m": [(60, "A person lunges one step forward and drags the right arm low across the body at hip height in a wide sideways raking arc, fingers hooked like claws, then both arms reach forward grabbing at the air.")],
        "n": [(60, "A person lunges one step forward, the right arm sweeping from low on the right side up across the body to chest level on the left side with the fingers hooked, the left arm held out in front, then both hands grab forward.")],
        "o": [(60, "A person lunges one step forward and rakes the left arm across the body from low to mid height with open hooked fingers, like a bear swiping with a paw, then grabs forward with both hands.")],
        "j": [(60, "A person takes a step forward and swings the right arm from low at the right hip across the body at waist height to the left in a sweeping slap, then reaches forward with both hands.")],
        "k": [(60, "A person steps forward and swipes the right hand in a wide horizontal arc at chest height from right to left, fingers curled like claws.")],
        "l": [(60, "A person lunges forward and scratches downward and across with the right hand, clawing from the shoulder down to the opposite hip.")],
    },
    "z_attack3": {
        "a": [(60, "A hunched person lunges forward with both arms wide open, then sweeps both arms inward in a big hugging tackle around someone in front, pulling them in and bending the head forward to bite.")],
        "h": [(60, "A person lunges one step forward with both arms spread wide, then wraps both arms around someone in front, hugging and pulling them in tight.")],
        "i": [(60, "A person tackles forward with both arms outstretched wide, grabbing and hugging a person in front and pulling them in.")],
    },
}

def download(name, url):
    box = os.path.join(CACHE, name + "_zip")
    dest = os.path.join(box, name + ".zip")
    os.makedirs(box, exist_ok=True)
    if not os.path.exists(dest) or os.path.getsize(dest) < 100000:
        with urllib.request.urlopen(url, timeout=300) as r, open(dest + ".part", "wb") as f:
            f.write(r.read())
        os.replace(dest + ".part", dest)
    print("%s: %d KB sha256 %s" % (name, os.path.getsize(dest) // 1024, hashlib.sha256(open(dest, "rb").read()).hexdigest()[:16]))
    out = os.path.join(CACHE, name)
    os.makedirs(out, exist_ok=True)
    with zipfile.ZipFile(dest) as z:
        for member in z.namelist():
            target = os.path.realpath(os.path.join(out, member))
            if not target.startswith(os.path.realpath(out) + os.sep):
                raise SystemExit("unsafe path in archive: " + member)
        z.extractall(out)
    licence = [os.path.join(d, f) for d, _, fs in os.walk(out) for f in fs if f.lower().startswith("license")]
    text = open(licence[0], encoding="utf-8", errors="replace").read() if licence else ""
    if "CC0" not in text:
        raise SystemExit("%s: no CC0 licence text found; do not use this pack until checked" % name)
    print("%s: CC0 confirmed in %s" % (name, os.path.relpath(licence[0], out)))


class KimodoServer:
    """kmd-generate --server: loads the motion model and text encoder once, then
    answers one tab-separated request per line (transition, steps, seed, out_dir,
    then FRAMES<TAB>PROMPT.txt pairs) with OK/ERR."""

    def __init__(self, gen, motion, text):
        self.p = subprocess.Popen([gen, "--server", motion, text], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def generate(self, segments, seed, out_dir, steps=KIMODO_STEPS, transition=6):
        os.makedirs(out_dir, exist_ok=True)
        fields = [str(transition), str(steps), str(seed), out_dir]
        for i, (frames, prompt) in enumerate(segments):
            ptxt = os.path.join(out_dir, "prompt%d.txt" % i)
            open(ptxt, "w").write(prompt)
            fields += [str(frames), ptxt]
        self.p.stdin.write("\t".join(fields) + "\n")
        self.p.stdin.flush()
        reply = self.p.stdout.readline().strip()
        if not reply.startswith("OK"):
            raise RuntimeError("kimodo: " + reply)

    def close(self):
        self.p.stdin.close()
        self.p.wait()


def kimodo_paths():
    src = os.path.join(CACHE, "src", "kimodo.cpp")
    return src, os.path.join(src, "build", "release", "kmd-generate"), \
        os.path.join(src, "models", "kimodo-soma-rp-v1.1-f32.gguf"), os.path.join(src, "Llama-3-Kimodo-Q4_K_M.gguf")


def kimodo_build():
    """Clone at the pinned commit, fetch the SOMA-RP v1.1 weights + Q4_K_M text encoder
    (~6 GB, no login), build the CPU backend (no Vulkan: the UHD 620 gains little and the
    headers are not installed). Needs only python3, git and a C++23 compiler; cmake and
    ninja come from a venv."""
    src, gen, motion, text = kimodo_paths()
    venv = os.path.join(CACHE, "kvenv")
    if not os.path.isdir(os.path.join(src, "ggml", "src")):
        os.makedirs(os.path.dirname(src), exist_ok=True)
        if not os.path.isdir(src):
            subprocess.run(["git", "clone", KIMODO_REPO, src], check=True)
        subprocess.run(["git", "-C", src, "checkout", KIMODO_COMMIT], check=True)
        subprocess.run(["git", "-C", src, "submodule", "update", "--init", "--recursive"], check=True)
    if not os.path.isdir(venv):
        subprocess.run([sys.executable, "-m", "venv", venv], check=True)
        subprocess.run([venv + "/bin/pip", "install", "-q", "cmake", "ninja", "huggingface_hub"], check=True)
    env = dict(os.environ, PATH=venv + "/bin:" + os.environ["PATH"])
    if not (os.path.exists(motion) and os.path.exists(text)):
        # The script's final manifest check trips over a duplicate tokenizer path
        # ("generated/llm2vec-text-bundle/tokenizer.gguf") AFTER all hashes of the real
        # files passed; the files are checked below against the manifests instead.
        subprocess.run(["scripts/download_gguf_weights.sh", "--output", src, "--model", "soma-rp-v1.1",
                        "--text-quantization", "q4_k_m"], cwd=src, env=env, check=False)
        for repo, rel in (("LocalAI-io__Kimodo-SOMA-RP-v1.1-GGML", "models/kimodo-soma-rp-v1.1-f32.gguf"),
                          ("LocalAI-io__Llama-3-Kimodo-GGML", "Llama-3-Kimodo-Q4_K_M.gguf"),
                          ("LocalAI-io__Llama-3-Kimodo-GGML", "tokenizer.gguf")):
            manifest = json.load(open(os.path.join(src, ".kimodo-manifests", repo, "MANIFEST.json")))
            want = next(e for e in manifest["files"] if e["path"] == rel)
            h = hashlib.sha256()
            with open(os.path.join(src, rel), "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            if h.hexdigest() != want["sha256"]:
                raise SystemExit("checksum mismatch: " + rel)
    if not os.path.exists(gen):
        subprocess.run(["cmake", "--preset", "release", "-DKIMODO_ENABLE_VULKAN=OFF", "-DKIMODO_BUILD_TESTS=OFF"], cwd=src, env=env, check=True)
        subprocess.run(["cmake", "--build", "--preset", "release", "-j", str(os.cpu_count() or 4)], cwd=src, env=env, check=True)


def export_bvh(take, out, fps=30.0, scale=100.0):
    """Raw Kimodo streams (root_positions.f32, local_rotations_xyzw.f32) -> 30-joint SOMA BVH (cm, Y up).

    kimodo.cpp's own scripts/export_bvh.py is NOT used for the motion: it extracts Euler
    angles for R = Ry*Rx*Rz but writes the channels as "Zrotation Xrotation Yrotation",
    which every BVH reader (Blender included) composes as R = Rz*Rx*Ry. The two agree for a
    single-axis turn and drift apart as soon as turns combine -- a prone body rolled from
    20 to 80 degrees over a crawl. Only its skeleton (names, parents, offsets) is reused."""
    src = kimodo_paths()[0]
    spec = importlib.util.spec_from_file_location("kimodo_export_bvh", os.path.join(src, "scripts", "export_bvh.py"))
    ex = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ex)
    pos, rot = array.array("f"), array.array("f")
    with open(os.path.join(take, "root_positions.f32"), "rb") as f:
        pos.frombytes(f.read())
    with open(os.path.join(take, "local_rotations_xyzw.f32"), "rb") as f:
        rot.frombytes(f.read())
    n_joints = len(ex.SOMA30_NAMES)
    frames = len(pos) // 3
    lines = [ex.build_bvh_hierarchy(ex.SOMA30_NAMES, ex.SOMA30_PARENTS, ex.SOMA30_OFFSETS, scale=scale),
             "MOTION", "Frames: %d" % frames, "Frame Time: %.6f" % (1.0 / fps)]
    for fr in range(frames):
        row = ["%.4f" % (pos[fr * 3 + k] * scale) for k in range(3)]
        for j in range(n_joints):
            x, y, z, w = rot[(fr * n_joints + j) * 4:(fr * n_joints + j) * 4 + 4]
            n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
            x, y, z, w = x / n, y / n, z / n, w / n
            m01, m10, m00 = 2 * (x * y - z * w), 2 * (x * y + z * w), 1 - 2 * (y * y + z * z)
            m11, m20 = 1 - 2 * (x * x + z * z), 2 * (x * z - y * w)
            m21, m22 = 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)
            # R = Rz(a) Rx(b) Ry(c):  m21 = sin b, m20/m22 = -tan c, m01/m11 = -tan a
            b = math.asin(max(-1.0, min(1.0, m21)))
            if abs(b) < math.pi / 2 - 1e-4:
                a, c = math.atan2(-m01, m11), math.atan2(-m20, m22)
            else:
                a, c = math.atan2(m10, m00), 0.0
            row += ["%.4f" % math.degrees(v) for v in (a, b, c)]
        lines.append(" ".join(row))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def kimodo(only=None):
    """Generate every KIMODO_CLIPS variant x seed into ~/.cache/dopesick/kimodo/takes/<clip>_<variant>_s<seed>/
    (raw .f32 + SOMA30 .bvh + take.json with prompt, seed, seconds). Existing takes are kept."""
    kimodo_build()
    src, gen, motion, text = kimodo_paths()
    takes = os.path.join(CACHE, "kimodo", "takes")
    server = KimodoServer(gen, motion, text)
    try:
        for clip, variants in KIMODO_CLIPS.items():
            if only and clip not in only:
                continue
            for var, segments in variants.items():
                for seed in KIMODO_SEEDS + KIMODO_EXTRA_SEEDS.get((clip, var), []):
                    take = os.path.join(takes, "%s_%s_s%d" % (clip, var, seed))
                    if os.path.exists(take + "/take.bvh"):
                        continue
                    t0 = time.time()
                    server.generate(segments, seed, take)
                    secs = time.time() - t0
                    export_bvh(take, take + "/take.bvh")
                    json.dump({"clip": clip, "variant": var, "seed": seed, "steps": KIMODO_STEPS, "seconds": round(secs, 1),
                               "segments": segments, "model": "Kimodo-SOMA-RP-v1.1 (kimodo.cpp %s), text encoder Q4_K_M" % KIMODO_COMMIT[:7]},
                              open(take + "/take.json", "w"), indent=1)
                    print("%s_%s_s%d  %.0f s" % (clip, var, seed, secs), flush=True)
    finally:
        server.close()


def kimodo_pick(spec):
    """--kimodo-pick z_attack=z_attack_a_s2: make that take the one retarget_to_bip01.py bakes."""
    clip, take = spec.split("=")
    box = os.path.join(CACHE, "kimodo")
    best = os.path.join(box, "best")
    os.makedirs(best, exist_ok=True)
    shutil.copy(os.path.join(box, "takes", take, "take.bvh"), os.path.join(best, clip + ".bvh"))
    shutil.copy(os.path.join(box, "takes", take, "take.json"), os.path.join(best, clip + ".json"))
    print("picked", take, "->", clip)


if __name__ == "__main__":
    if "--kimodo-reexport" in sys.argv:   # rewrite every take's BVH from its raw streams (see export_bvh)
        takes = os.path.join(CACHE, "kimodo", "takes")
        for name in sorted(os.listdir(takes)):
            if os.path.exists(os.path.join(takes, name, "local_rotations_xyzw.f32")):
                export_bvh(os.path.join(takes, name), os.path.join(takes, name, "take.bvh"))
        print("re-exported", len(os.listdir(takes)), "takes")
        sys.exit(0)
    picks = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--kimodo-pick=")]
    if picks:
        for spec in picks:
            kimodo_pick(spec)
    else:
        for name, url in ARCHIVES.items():
            download(name, url)
        if "--kimodo" in sys.argv:
            kimodo([a for a in sys.argv[1:] if not a.startswith("-")])
