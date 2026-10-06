"""Downloads the Microsoft Rocketbox avatars the game casts (MIT licence,
github.com/microsoft/Microsoft-Rocketbox) and converts each into
assets/rocketbox/<Name>.glb with the game's clips baked in.

  python3 -I dev-tools/fetch_rocketbox.py [Name ...]

Needs Blender on the PATH (5.x; `blender -b`). Downloads go to
~/.cache/rocketbox (about 70 MB an avatar -- the 2048 px TGA textures --
skipping the specular maps the game doesn't use). Run from the project root.
"""
import json, os, subprocess, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

RAW = "https://raw.githubusercontent.com/microsoft/Microsoft-Rocketbox/master/"
TREE = "https://api.github.com/repos/microsoft/Microsoft-Rocketbox/git/trees/master?recursive=1"
CACHE = os.path.expanduser("~/.cache/rocketbox")
OUT = "assets/rocketbox"

# Avatar -> texture size. 1024 for anyone you talk to; 512 for people who
# only walk past.
CAST = {
    "Male_Adult_20": 1024, "Male_Adult_18": 1024, "Female_Adult_12": 1024, "Male_Adult_17": 1024,
    "Business_Male_07": 1024, "Police_Male_03": 1024, "Police_Male_01": 1024, "Security_Male_01": 1024,
    "Male_Adult_09": 1024, "Medical_Female_01": 1024, "Medical_Male_01": 1024, "Medical_Female_02": 1024,
    "Female_Adult_08": 1024, "Male_Adult_16": 1024, "Male_Adult_14": 1024, "Male_Adult_11": 1024,
    "Business_Male_04": 1024, "Female_Adult_02": 1024, "Female_Adult_14": 1024,
    "Female_Adult_09": 1024, "Male_Adult_04": 1024, "Male_Adult_05": 1024, "Female_Adult_04": 1024,
    "Male_Adult_03": 1024, "Construction_Male_08": 1024, "Male_Adult_10": 1024, "Female_Adult_07": 1024,
    "Male_Adult_13": 1024, "Female_Adult_03": 1024, "Wood_Male_01": 1024, "Male_Adult_08": 1024,
    "Female_Adult_13": 1024, "Gardener_Male_01": 1024,
    "Business_Male_02": 512, "Business_Female_01": 512, "Female_Adult_01": 512, "Female_Adult_05": 512,
    "Male_Adult_06": 512, "Male_Adult_01": 512, "Business_Female_03": 512, "Male_Adult_12": 1024, "Business_Female_02": 512, "Male_Adult_02": 512,
}
CLIPS = {
    "static": ["idle_neutral_01", "sit_chair_idle_neutral_01", "idle_nervous_01", "crouch_idle", "documents_take"],
    "xy": ["walk_neutral_01", "walk_neutral", "run_neutral", "run_neutral_01", "walk_bruised", "walk_injured", "walk_drunk"],
}

def fetch(rel, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 1000:
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(RAW + urllib.request.quote(rel), timeout=300) as r, open(dest + ".part", "wb") as f:
        f.write(r.read())
    os.replace(dest + ".part", dest)
    return dest

def main():
    names = sys.argv[1:] or list(CAST)
    tree = json.load(urllib.request.urlopen(TREE, timeout=60))["tree"]
    paths = [e["path"] for e in tree if e["type"] == "blob"]
    jobs = []
    for sex in "mf":
        for folder, clips in CLIPS.items():
            for c in clips:
                rel = "Assets/Animations/all_animations_max_motextr_%s/%s_%s.max.fbx" % (folder, sex, c)
                if rel in paths:
                    jobs.append((rel, os.path.join(CACHE, "anims", "%s_%s.fbx" % (sex, c))))
    for name in names:
        base = next(p.rsplit("/", 2)[0] for p in paths if p.endswith("/Export/%s.fbx" % name))
        jobs.append((base + "/Export/%s.fbx" % name, os.path.join(CACHE, name, name + ".fbx")))
        for p in paths:
            if p.startswith(base + "/Textures/") and "specular" not in p:
                jobs.append((p, os.path.join(CACHE, name, "Textures", os.path.basename(p))))
    with ThreadPoolExecutor(8) as pool:
        list(pool.map(lambda j: fetch(*j), jobs))
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        sex = "f" if "Female" in name else "m"
        glb = os.path.join(OUT, name + ".glb")
        subprocess.run(["blender", "-b", "-P", "dev-tools/rocketbox_to_glb.py", "--",
            os.path.join(CACHE, name, name + ".fbx"), os.path.join(CACHE, "anims"), glb, sex, str(CAST.get(name, 1024))],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([sys.executable, "-I", "dev-tools/slim_glb.py", glb], check=True)
        imp = glb + ".import"
        if not os.path.exists(imp):
            # Real size with the scenes' 1.5x ModelRoot: the .glb is in metres.
            open(imp, "w").write('[remap]\n\nimporter="scene"\n\n[params]\n\nnodes/root_scale=0.6667\nnodes/apply_root_scale=true\n')

main()
