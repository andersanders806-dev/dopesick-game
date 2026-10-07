# Chapter 1: World Art Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the toy-kit buildings, box cars and box furniture on the street, in the apartment, the Dive Bar and the five stores with realistic CC0 models and PBR materials, without changing how the game plays.

**Architecture:** Street facades are assembled at load by a new `world/Facades.gd` (a City3D child, like `StreetDressing.gd`) from Poly Haven's modular facade kits, measured piece by piece. Everything else goes through the room generator `dev-tools/build_rooms_3d.gd`: props become Poly Haven instances (`_ph`), surfaces become PBR sets (`_pbr_mat`), and the scenes are regenerated. Colliders, zones, markers and doors keep their positions.

**Tech Stack:** Godot 4.7 (flatpak), GDScript, Python 3 fetch scripts, Poly Haven (CC0), ambientCG (CC0).

**Spec:** `docs/superpowers/specs/2026-10-07-chapter1-world-art-design.md`

## Global Constraints

- Gameplay untouched: colliders, sightline blockers, bounds, spawn markers, doors, interaction zones, guards and the navmesh keep their positions. Full smoke test (`smoke_test_3d`, 518 checks) green after every task.
- Performance budget: City3D and DiveBar3D on Medium at most ~10% slower GPU time per frame, measured by alternating A/B in one process.
- Licences: Poly Haven (CC0), ambientCG (CC0); credited in `assets/polyhaven/LICENSE.txt` and `assets/pbr/LICENSE.txt`.
- `GODOT` = `flatpak run org.godotengine.Godot`. Never run two Godot test processes at once. Flatpak Godot can't write `/tmp`: renders go to `.pilot/` or `mockup_tmp/`.
- Regenerate rooms with `timeout 900 $GODOT --headless --path . res://dev-tools/BuildRooms3D.tscn`; commit only the `.tscn` files the task changes (`git checkout --` the others: regeneration rewrites unique ids everywhere).
- Test runner: `bash .superpowers/sdd/2026-10-06-batch2-street-gets-dangerous/t.sh <script>` (fails on `  FAIL` or `SCRIPT ERROR`). Area runner for this plan: `smoke_world_art`.
- House style: tabs, `##` comments that say why. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings against the spec (made while planning)

- **Traffic and some parked cars stay on Kenney's car kit**, with muted paint and rougher materials. Realistic CC0 cars with direct downloads don't exist (searched Poly Haven, OpenGameArt, cinevva, Khronos samples); the free packs are all toy/low-poly. Parked cars mix in Poly Haven's realistic `covered_car`. Cost if wrong: traffic still reads as toy cars.
- **Electricity poles (200k tris), chain-link fence (89k) and gutters (16k) are dropped** from the street furniture: too heavy for the UHD 620 budget. The barrel stove, utility boxes and manhole covers are already in the game. Cost if wrong: a little less clutter overhead.
- **Heavy models rely on Godot's import LODs** (`meshes/generate_lods=true`, the default — verify in each new `.gltf.import`): at the camera's ~11 m the far LODs draw. `wine_bottles_01` (29k), `mounted_fluorescent_lights` (18k), `old_bed_frame` (50k), `WoodenChair_01` (20k), `bar_chair_round_01` (14k) are each gated by the A/B in their task; the fallback is fewer instances, then a lighter model or a built primitive.

## Review Focus

1. **Shops' shutters when loading a save at night** — a closed shop must show its shutter on load, not only after the next clock tick. Pinned in Task 2 (`state on load`).
2. **First person at street level** — no gaps between fronts and no signs, hour plates or posters hidden behind or inside the new facade (the facade's front face sits behind the sign plane at `street_z`). Pinned in Task 2 (`fronts sit behind the signs`).
3. **Posters and graffiti decals** from `StreetDressing.gd` still land on a wall — their projection box must reach the facade plane. Pinned in Task 2.
4. **Low preset on the laptop** — the facades must not drop Low below its current frame rate band; measured with the Medium A/B in Task 3.
5. **Belongings in the apartment** — a taken TV/radio/guitar/coat/ring must still disappear from the room with its new model (Belonging3D hides `prop_path`). Pinned in Task 4.

---

## File structure

- Create `dev-tools/fetch_ambientcg.py` — downloads ambientCG 1K-JPG sets into `assets/pbr/<set>_diff/_nor/_rough.jpg` (the format `_pbr_mat` reads).
- Modify `dev-tools/fetch_polyhaven_models.py` — more models.
- Create `world/Facades.gd` — builds every street front from kit pieces; storefront glass, glow and roller shutters by opening hours.
- Modify `world/City3D.gd` — adds the `Facades` child.
- Modify `dev-tools/build_rooms_3d.gd` — PBR sizes; city (no Kenney buildings/awnings, lamps, cars, ground); apartment; bar; store fixtures.
- Modify `world/StreetLife.gd` — muted traffic paint.
- Create `dev-tools/smoke_world_art.gd`; modify `dev-tools/smoke_test_3d.gd` (`_world_art_checks`).
- Modify `README.md`.

---

### Task 1: Assets

**Files:**
- Create: `dev-tools/fetch_ambientcg.py`
- Modify: `dev-tools/fetch_polyhaven_models.py` (MODELS list)
- Modify: `dev-tools/build_rooms_3d.gd:95-100` (PBR_SIZE)
- Create: `dev-tools/smoke_world_art.gd`
- Modify: `dev-tools/smoke_test_3d.gd` (append `_world_art_checks`, call it after `_cast_checks`)

**Interfaces:**
- Produces: PBR sets `road_worn`, `sidewalk_slabs`, `curb`, `tiles_white`, `tiles_beige`, `plaster_painted`, `bricks_old`, `wood_dark`, `leather_red`, `felt`, `metal_worn`, `metal_brushed` usable as `_tex_mat("pbr:<set>", ...)`/`_pbr_mat("<set>")`; Poly Haven ids below usable with `_ph()`.

- [ ] **Step 1: Write the failing test**

In `dev-tools/smoke_test_3d.gd`, add `await _world_art_checks(gs)` after `await _cast_checks(gs)` in `_run`, and append:

```gdscript
const WORLD_ART_PBR := ["road_worn", "sidewalk_slabs", "curb", "tiles_white", "tiles_beige", "plaster_painted",
	"bricks_old", "wood_dark", "leather_red", "felt", "metal_worn", "metal_brushed"]
const WORLD_ART_MODELS := ["modular_urban_apartments_facade", "modular_factory_facade", "modular_fire_escape",
	"street_lamp_01", "covered_car", "exterior_aircon_unit", "rollershutter_window_01", "security_camera_02",
	"old_bed_frame", "WoodenChair_01", "metal_trash_can", "pull_chain_light_socket", "wall_clock",
	"bar_chair_round_01", "metal_stool_01", "wine_bottles_01", "WoodenTable_01", "hanging_industrial_lamp",
	"steel_frame_shelves_01", "mounted_fluorescent_lights", "worn_metal_rack"]

func _world_art_checks(gs: Node) -> void:
	await _section("World art: real places, same game")
	var missing := []
	for s in WORLD_ART_PBR:
		for m in ["_diff.jpg", "_nor.jpg", "_rough.jpg"]:
			if not ResourceLoader.exists("res://assets/pbr/" + s + m):
				missing.append(s + m)
	for id in WORLD_ART_MODELS:
		if not ResourceLoader.exists("res://assets/polyhaven/%s/%s.gltf" % [id, id]):
			missing.append(id)
	_check(missing.is_empty(), "  every material and model is on disk (%s)" % [missing])
```

Create `dev-tools/smoke_world_art.gd`:

```gdscript
extends "res://dev-tools/smoke_test_3d.gd"
## Just the world-art checks.
func _run() -> void:
	await _world_art_checks(_gs())
```

- [ ] **Step 2: Run, expect FAIL** — `t.sh smoke_world_art` → `FAIL   every material and model is on disk ([...])`.

- [ ] **Step 3: Fetch.** Create `dev-tools/fetch_ambientcg.py`:

```python
#!/usr/bin/env python3
"""Download CC0 PBR materials from ambientCG (https://ambientcg.com) into
assets/pbr/ as <set>_diff.jpg, <set>_nor.jpg, <set>_rough.jpg -- the same
layout fetch_polyhaven.py writes, so build_rooms_3d.gd's _pbr_mat() reads
both. 1K JPG; OpenGL normal maps (Godot's convention).

    python3 -I dev-tools/fetch_ambientcg.py
"""
import io, pathlib, urllib.request, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "pbr"
UA = {"User-Agent": "dopesick-game-asset-fetch"}
# set name in the game -> ambientCG asset id
SETS = {
    "road_worn": "Road009C", "sidewalk_slabs": "PavingStones128", "curb": "Concrete047A",
    "tiles_white": "Tiles141", "tiles_beige": "Tiles139", "plaster_painted": "PaintedPlaster017",
    "bricks_old": "Bricks097", "wood_dark": "Wood066", "leather_red": "Leather037",
    "felt": "Fabric030", "metal_worn": "Metal055A", "metal_brushed": "Metal032",
}
MAPS = {"_Color.jpg": "diff", "_NormalGL.jpg": "nor", "_Roughness.jpg": "rough"}

def main():
    lines = []
    for name, aid in SETS.items():
        if all((OUT / f"{name}_{m}.jpg").exists() for m in MAPS.values()):
            lines.append(f"{name}: ambientCG {aid}")
            continue
        req = urllib.request.Request(f"https://ambientcg.com/get?file={aid}_1K-JPG.zip", headers=UA)
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(req, timeout=300).read()))
        for member in z.namelist():
            for suffix, short in MAPS.items():
                if member.endswith(suffix):
                    (OUT / f"{name}_{short}.jpg").write_bytes(z.read(member))
        lines.append(f"{name}: ambientCG {aid}")
        print("ok", name, aid)
    lic = OUT / "LICENSE.txt"
    text = lic.read_text() if lic.exists() else ""
    if "ambientCG" not in text:
        text += "\nMaterials from ambientCG (https://ambientcg.com), CC0 1.0 -- public domain:\n"
    for l in lines:
        if l not in text:
            text += l + "\n"
    lic.write_text(text)

main()
```

In `dev-tools/fetch_polyhaven_models.py` add to `MODELS` (after the existing entries):

```python
    # world art, chapter 1: street
    "modular_urban_apartments_facade", "modular_factory_facade", "modular_fire_escape",
    "street_lamp_01", "covered_car", "exterior_aircon_unit", "rollershutter_window_01",
    "security_camera_02",
    # apartment
    "old_bed_frame", "WoodenChair_01", "metal_trash_can", "pull_chain_light_socket", "wall_clock",
    # bar
    "bar_chair_round_01", "metal_stool_01", "wine_bottles_01", "WoodenTable_01", "hanging_industrial_lamp",
    # stores
    "steel_frame_shelves_01", "mounted_fluorescent_lights", "worn_metal_rack",
```

Run `python3 -I dev-tools/fetch_ambientcg.py && python3 -I dev-tools/fetch_polyhaven_models.py`, then `timeout 900 $GODOT --headless --path . --import`.

In `build_rooms_3d.gd` add to `PBR_SIZE` (real tile sizes from ambientCG's dimension fields; the plan uses: road 4.0, slabs 2.0, curb 2.0, tiles 1.0, plaster 2.0, bricks 2.0, wood 1.5, leather 1.0, felt 0.5, metals 1.0):

```gdscript
	"road_worn": 4.0, "sidewalk_slabs": 2.0, "curb": 2.0, "tiles_white": 1.0, "tiles_beige": 1.0,
	"plaster_painted": 2.0, "bricks_old": 2.0, "wood_dark": 1.5, "leather_red": 1.0, "felt": 0.5,
	"metal_worn": 1.0, "metal_brushed": 1.0,
```

- [ ] **Step 4: Run, expect PASS** — `t.sh smoke_world_art` → `PASS (0 failure(s))`. Check `du -sh assets/polyhaven assets/pbr` (record the growth in the commit message) and the triangle counts of the new models (`curl -s https://api.polyhaven.com/info/<id>` → `polycount`); any over 20k is used once at most or swapped for a lighter one in its task.

- [ ] **Step 5: Commit** — (after `grep -L "generate_lods=true" assets/polyhaven/*/*.gltf.import` prints nothing new) `git add dev-tools/fetch_ambientcg.py dev-tools/fetch_polyhaven_models.py dev-tools/build_rooms_3d.gd dev-tools/smoke_world_art.gd dev-tools/smoke_test_3d.gd assets/pbr assets/polyhaven` → "Fetch the world-art models and materials (Poly Haven, ambientCG)".

---

### Task 2: Facades

**Files:**
- Create: `world/Facades.gd`
- Modify: `world/City3D.gd` (add the child next to `StreetDressing`)
- Modify: `dev-tools/build_rooms_3d.gd` (city: stop emitting `<Name>Building` and `<Name>Awning`)
- Regenerate: `world/City3D.tscn`
- Test: `_world_art_checks` (City section)

**Interfaces:**
- Consumes: kits `res://assets/polyhaven/modular_urban_apartments_facade/...gltf`, `.../modular_factory_facade/...gltf`, `rollershutter_window_01`, `GameState.is_open(place)`, `GameState.clock_changed`.
- Produces: `City3D/Facades` (Node3D) with one child per front named `Front<Name>` (`FrontHome`, `FrontPharmacy`...), each with `Glass`, `Glow` and `Shutter` children for shops; `Facades.refresh()`.

Kit facts (measured): every wall module is 3.00 × 3.00 m, flat (depth 0–0.25); `window_centered_large_01` 2.12 × 2.30 (apartment) / 2.22 × 1.74 (factory); cornice 3.00 × 0.20; crown 3.00 × 0.75 (apartment, 684 tris) / 0.32 (factory). Fronts measured from today's Kenney buildings:

| Front | x from | x to | height | kit | floors | place |
|---|---|---|---|---|---|---|
| Police | -26.71 | -22.29 | 4.47 | apartment | 2 | "" |
| Home | -19.71 | -15.29 | 6.47 | apartment | 3 | "" |
| Pharmacy | -12.60 | -8.40 | 6.47 | apartment | 3 | pharmacy |
| Bar | -5.93 | -1.07 | 6.47 | apartment | 3 | bar |
| Shop | 1.40 | 5.60 | 6.47 | apartment | 3 | convenience |
| Liquor | 8.29 | 12.71 | 4.47 | apartment | 2 | liquor |
| Supermarket | 14.55 | 20.45 | 3.21 | apartment | 1 | supermarket |
| Electronics | 22.29 | 26.71 | 6.47 | apartment | 3 | electronics |
| Karts | -15.25 | -12.75 | 10.0 | factory | 4 | karts |
| Pawn | -1.25 | 1.25 | 10.0 | factory | 4 | pawn |
| Music | -8.25 | -5.75 | 11.13 | factory | 4 | music |
| Shelter | 5.75 | 8.25 | 11.13 | factory | 4 | shelter |

- [ ] **Step 1: Write the failing tests** (append inside `_world_art_checks`):

```gdscript
	var city := await _load("res://world/City3D.tscn")
	var kenney := city.find_children("*", "Node3D", false, false).filter(func(n): return String(n.scene_file_path).contains("kenney/city"))
	_check(kenney.is_empty(), "  no Kenney toy buildings left on the street (%s)" % [kenney.map(func(n): return n.name)])
	var fronts: Node = city.get_node_or_null("Facades")
	var names := ["Police", "Home", "Pharmacy", "Bar", "Shop", "Liquor", "Supermarket", "Electronics", "Karts", "Pawn", "Music", "Shelter"]
	_check(fronts != null and names.all(func(n): return fronts.get_node_or_null("Front" + n) != null), "  every building has a real front")
	# Gameplay stays: doors and the station door where they were.
	var doors := ["DoorToHome", "DoorToPharmacy", "DoorToBar", "DoorToShop", "DoorToLiquor", "DoorToSupermarket",
		"DoorToElectronics", "DoorToKarts", "DoorToPawn", "DoorToMusic", "DoorToShelter", "StationDoor"]
	_check(doors.all(func(d): return city.find_child(d, true, false) != null), "  every door is still there")
	# Fronts sit behind the signs: nothing of a facade pokes in front of z = -4.5.
	var poking := []
	for mi in fronts.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.end.z > -4.5 + 0.001:
			poking.append(mi.name)
	_check(poking.is_empty(), "  fronts sit behind the signs and plates (%s)" % [poking.slice(0, 5)])
	# Shutters by opening hours, right from load.
	gs.clock = 3 * 60
	city = await _load("res://world/City3D.tscn")
	var ph: Node = city.get_node("Facades/FrontPharmacy")
	_check(ph.get_node("Shutter").visible and not ph.get_node("Glow").visible, "  a closed shop has its shutter down on load (state on load)")
	gs.clock = 14 * 60
	gs.advance_clock(1)
	await _frames(2)
	_check(not ph.get_node("Shutter").visible and ph.get_node("Glow").visible, "  ...and up, lit, when it opens")
	# Posters still land on a wall: each decal's box reaches the facade plane.
	var short := city.find_children("*", "Decal", true, false).filter(func(d): return d.global_position.z > -4.8 and d.global_position.z - d.size.y / 2.0 > -4.5 - 0.02 and absf(d.global_rotation_degrees.x) > 45)
	_check(short.is_empty(), "  posters and graffiti still reach the wall (%s)" % [short.map(func(d): return d.name)])
```

- [ ] **Step 2: Run, expect FAIL** — `t.sh smoke_world_art` → FAIL on "no Kenney toy buildings" and "every building has a real front".

- [ ] **Step 3: Stop emitting the Kenney fronts.** In `_build_city()`, delete the `_model(_root, f["name"] + "Building", ...)` line and the `if f["name"] not in ["Home", "Police"]: _model(... "Awning" ...)` block. Keep signs, glows, hour plates, doors, the station door and everything else in the loop.

- [ ] **Step 4: Create `world/Facades.gd`:**

```gdscript
extends Node3D
## The block's buildings: real fronts assembled at load from Poly Haven's
## CC0 modular facade kits (brick apartment blocks for the shops, the
## factory kit for the tall narrow fillers), replacing Kenney's toy city.
## Pieces are 3 x 3 m modules, stretched to each front's measured width.
## The ground floor is what the top-down camera sees most: shop glass with
## a lit interior, and a roller shutter when the place is closed.
##
## Visual only: the street's colliders (BoundsNorth) and doors are the
## builder's and don't move. Fronts sit just behind the street_z plane the
## signs, hour plates and posters are on.

const APT := "res://assets/polyhaven/modular_urban_apartments_facade/modular_urban_apartments_facade.gltf"
const FACTORY := "res://assets/polyhaven/modular_factory_facade/modular_factory_facade.gltf"
const SHUTTER := "res://assets/polyhaven/rollershutter_window_01/rollershutter_window_01.gltf"
const STREET_Z := -4.5
const FACE_Z := STREET_Z - 0.03
const MODULE := 3.0
## name, x from, x to, kit, floors, place (GameState.OPENING_HOURS key, or "")
const FRONTS := [
	["Police", -26.71, -22.29, "apt", 2, ""], ["Home", -19.71, -15.29, "apt", 3, ""],
	["Pharmacy", -12.60, -8.40, "apt", 3, "pharmacy"], ["Bar", -5.93, -1.07, "apt", 3, "bar"],
	["Shop", 1.40, 5.60, "apt", 3, "convenience"], ["Liquor", 8.29, 12.71, "apt", 2, "liquor"],
	["Supermarket", 14.55, 20.45, "apt", 1, "supermarket"], ["Electronics", 22.29, 26.71, "apt", 3, "electronics"],
	["Karts", -15.25, -12.75, "factory", 4, "karts"], ["Pawn", -1.25, 1.25, "factory", 4, "pawn"],
	["Music", -8.25, -5.75, "factory", 4, "music"], ["Shelter", 5.75, 8.25, "factory", 4, "shelter"],
]
const KIT_PIECES := {
	"apt": {"wall": "wall_standard_standard_01", "bay": "wall_window_centered_large_01", "window": "window_centered_large_01",
		"band": "cornice_standard_standard_01", "crown": "crown_standard_standard_01", "base": "base_standard_01"},
	"factory": {"wall": "wall_standard_standard_01", "bay": "wall_window_centered_large_01", "window": "window_centered_large_01",
		"band": "cornice02_standard_standard_01", "crown": "crown_standard_standard_01", "base": "base_standard_standard_01"},
}

var _meshes := {}

func _ready() -> void:
	for f in FRONTS:
		_build_front(f)
	GameState.clock_changed.connect(_on_clock)
	refresh()

func _mesh(kit: String, piece: String) -> Mesh:
	if not _meshes.has(kit):
		var scene: Node = load(APT if kit == "apt" else FACTORY).instantiate()
		var by_name := {}
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			by_name[String(mi.name)] = mi.mesh
		scene.free()
		_meshes[kit] = by_name
	return _meshes[kit][piece]

## One kit piece, its left edge at x, bottom at y, its front face on FACE_Z,
## stretched along x by `sx`. Returns the MeshInstance3D.
func _piece(parent: Node3D, kit: String, piece: String, x: float, y: float, sx := 1.0, depth_offset := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kit, piece)
	parent.add_child(mi)
	var b: AABB = mi.mesh.get_aabb()
	mi.scale = Vector3(sx, 1.0, 1.0)
	mi.position = Vector3(x - b.position.x * sx, y - b.position.y, FACE_Z - b.end.z - depth_offset)
	return mi

func _build_front(f: Array) -> void:
	var front := Node3D.new()
	front.name = "Front" + f[0]
	add_child(front)
	var kit: String = f[3]
	var p: Dictionary = KIT_PIECES[kit]
	var x0: float = f[1]
	var width: float = f[2] - f[1]
	var bays := maxi(1, ceili(width / MODULE - 0.2))
	var sx := width / (bays * MODULE)
	var bay_w := MODULE * sx
	# Ground floor: plain wall behind the shop glass and the door.
	for i in bays:
		_piece(front, kit, p["wall"], x0 + i * bay_w, 0.0, sx, 0.02)
		_piece(front, kit, p["base"], x0 + i * bay_w, 0.0, sx)
	# Upper floors: window bays, a band between floors, the crown on top.
	for floor_i in range(1, f[4]):
		var y := floor_i * MODULE
		for i in bays:
			var bx := x0 + i * bay_w
			_piece(front, kit, p["bay"], bx, y, sx)
			var win := _mesh(kit, p["window"]).get_aabb()
			_piece(front, kit, p["window"], bx + (bay_w - win.size.x) / 2.0, y + (MODULE - win.size.y) / 2.0)
			_piece(front, kit, p["band"], bx, y - 0.1, sx)
	for i in bays:
		_piece(front, kit, p["crown"], x0 + i * bay_w, f[4] * MODULE, sx)
	if f[5] != "":
		_storefront(front, x0, width)
	front.set_meta("place", f[5])

## Shop glass either side of the door, a warm glow behind it while open,
## and a roller shutter over the whole front while closed.
func _storefront(front: Node3D, x0: float, width: float) -> void:
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.08, 0.1, 0.12, 0.55)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.05
	glass_mat.metallic = 0.3
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.86, 0.62)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.82, 0.55)
	glow_mat.emission_energy_multiplier = 1.4
	var door_gap := 1.3
	var pane_w := maxf(0.4, (width - door_gap) / 2.0 - 0.25)
	var glass := Node3D.new()
	glass.name = "Glass"
	front.add_child(glass)
	var glow := Node3D.new()
	glow.name = "Glow"
	front.add_child(glow)
	for side in [-1, 1]:
		var cx: float = x0 + width / 2.0 + side * (door_gap / 2.0 + 0.12 + pane_w / 2.0)
		var pane := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(pane_w, 1.6, 0.02)
		pm.material = glass_mat
		pane.mesh = pm
		glass.add_child(pane)
		pane.position = Vector3(cx, 1.45, FACE_Z - 0.01)
		var lit := MeshInstance3D.new()
		var lm := QuadMesh.new()
		lm.size = Vector2(pane_w, 1.6)
		lm.material = glow_mat
		lit.mesh = lm
		glow.add_child(lit)
		lit.position = Vector3(cx, 1.45, FACE_Z - 0.12)
	var shutter: Node3D = load(SHUTTER).instantiate()
	shutter.name = "Shutter"
	front.add_child(shutter)
	var sb := AABB()
	for mi in shutter.find_children("*", "MeshInstance3D", true, false):
		sb = mi.get_aabb() if sb.size == Vector3.ZERO else sb.merge(mi.get_aabb())
	# Only the plain shutter: the kit also ships a graffiti one.
	for mi in shutter.find_children("*graffiti*", "MeshInstance3D", true, false):
		mi.visible = false
	var ssx := (width - 0.2) / sb.size.x
	shutter.scale = Vector3(ssx, 2.4 / sb.size.y, 1.0)
	shutter.position = Vector3(x0 + 0.1 - sb.position.x * ssx, 0.1 - sb.position.y * shutter.scale.y, FACE_Z - sb.end.z + 0.0)

func _on_clock(_minute: int) -> void:
	refresh()

## Shutters down while closed, glass lit while open.
func refresh() -> void:
	for front in get_children():
		var place: String = front.get_meta("place", "")
		if place == "" or not front.has_node("Shutter"):
			continue
		var open: bool = GameState.is_open(place)
		front.get_node("Shutter").visible = not open
		front.get_node("Glow").visible = open
```

In `world/City3D.gd`, next to the `StreetDressing` lines in `_ready`, add:

```gdscript
	var facades: Node3D = preload("res://world/Facades.gd").new()
	facades.name = "Facades"
	add_child(facades)
```

Regenerate the rooms; keep only `world/City3D.tscn` (`git status`, then `git checkout -- <other .tscn>`).

- [ ] **Step 5: Run, expect PASS** — `t.sh smoke_world_art` → PASS. If "posters and graffiti still reach the wall" fails, extend those decals' projection depth in `StreetDressing.gd` (their `size.y`) by 0.1 and rerun.

- [ ] **Step 6: Look at it.** Pilot: `"clock 20:00" "preset High" "scene City3D" "wait 2" "shot street" "closeup Pharmacy"` is not a node — use `mockup_tmp/mockup.gd`'s street-level camera instead: copy its `_shot` block into a scratch `dev-tools/_street_shot.gd` (deleted after), render street level at 14:00 and 21:00, read the PNGs, fix stretched or floating pieces, rerender. Open the final images for the partner with `xdg-open`.

- [ ] **Step 7: Commit** — `world/Facades.gd world/City3D.gd dev-tools/build_rooms_3d.gd world/City3D.tscn dev-tools/smoke_test_3d.gd` → "Build the street's fronts from Poly Haven's facade kits".

---

### Task 3: Street furniture, cars, ground, performance

**Files:**
- Modify: `dev-tools/build_rooms_3d.gd` (`_streetlight`, `_car`, `_build_city` ground and props)
- Modify: `world/Facades.gd` (fire escapes, air-con units, cameras)
- Modify: `world/StreetLife.gd` (muted traffic paint)
- Regenerate: `world/City3D.tscn`

**Interfaces:**
- Consumes: `Facades.FRONTS`; `_ph()`; PBR sets `road_worn`, `sidewalk_slabs`, `curb`.
- Produces: `StreetlightN/Model` (street_lamp_01) with `StreetlightN/Light` unchanged; `CarA..` keep their collision.

- [ ] **Step 1: Failing tests** (append to `_world_art_checks`, City still loaded at 14:00):

```gdscript
	var lamps := city.find_children("Streetlight*", "StaticBody3D", false, false)
	_check(lamps.size() > 0 and lamps.all(func(l): return l.get_node_or_null("Model") != null and l.get_node_or_null("Light") != null and l.get_node_or_null("Pole") == null),
		"  street lamps are real lamps, same light (%d)" % lamps.size())
	var cars := city.find_children("Car*", "StaticBody3D", false, false)
	_check(cars.size() > 0 and cars.all(func(c): return c.get_node_or_null("Body") == null and c.find_children("*", "CollisionShape3D", false, false).size() > 0),
		"  parked cars are cars, not boxes, and still solid (%d)" % cars.size())
	var road := city.get_node("Road") as MeshInstance3D
	var walk := city.get_node("Sidewalk") as MeshInstance3D
	_check(String((road.mesh.material as StandardMaterial3D).albedo_texture.resource_path).contains("road_worn") and String((walk.mesh.material as StandardMaterial3D).albedo_texture.resource_path).contains("sidewalk_slabs"),
		"  worn asphalt and paving slabs underfoot")
	_check(city.get_node("Facades").find_children("FireEscape*", "Node3D", true, false).size() >= 2, "  fire escapes on the apartment blocks")
```

- [ ] **Step 2: Run, expect FAIL** on lamps, cars, ground, fire escapes.

- [ ] **Step 3: Implement.**

`_streetlight`: replace the `Pole` cylinder and `Head` box with
```gdscript
	_ph(sl, "Model", "street_lamp_01", Vector3.ZERO, 3.4 / 3.87, 180.0)
```
(street_lamp_01 is 3.87 m tall; scaled to the old 3.4 m so the existing `Light` at y 3.2 stays at the lamp head). Keep the collision cylinder, `Light` and `Buzz`.

`_car`: replace the box meshes with, by index of the call (pass a new `kind` argument: `"covered"` for `CarA` and `CarC`, `"sedan"` otherwise):
```gdscript
	if kind == "covered":
		_ph(car, "Model", "covered_car", Vector3.ZERO, 1.0, 90.0)
	else:
		var m := _model(car, "Model", "cars/sedan.glb", Vector3.ZERO, 1.0, 90.0)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = [Color(0.22, 0.24, 0.27), Color(0.32, 0.29, 0.25), Color(0.18, 0.2, 0.17)][name.length() % 3]
			mat.roughness = 0.55
			mi.material_override = mat
```
(`covered_car` is 4.38 × 1.79 m, like the old 3.8 × 1.7 box body; the collision box stays.) Remove `body.add_to_group("car_bodies", true)`; City3D's paint loop then finds none (check `world/City3D.gd` handles an empty group; it iterates the group).

Ground: `Sidewalk` → `_tex_mat("pbr:sidewalk_slabs", 1.0)`, `Road` → `_tex_mat("pbr:road_worn", 1.0)`; add a curb:
```gdscript
	_box_mesh(_root, "Curb", Vector3(w, 0.14, 0.25), Vector3(0, 0.03, street_z + 3.0), _tex_mat("pbr:curb", 1.0))
```

`Facades.gd`: after `_build_front`, for `Home` and `Liquor` add a fire escape on the upper floors, for every shop with 2+ floors one air-con unit, and a camera over each shop door:
```gdscript
const ESCAPE := "res://assets/polyhaven/modular_fire_escape/modular_fire_escape.gltf"
const AIRCON := "res://assets/polyhaven/exterior_aircon_unit/exterior_aircon_unit.gltf"
const CAMERA := "res://assets/polyhaven/security_camera_02/security_camera_02.gltf"

func _dress(front: Node3D, f: Array) -> void:
	var x0: float = f[1]
	var width: float = f[2] - f[1]
	if f[0] in ["Home", "Liquor"] and f[4] >= 2:
		var esc: Node3D = load(ESCAPE).instantiate()
		esc.name = "FireEscape" + f[0]
		front.add_child(esc)
		esc.position = Vector3(x0 + 0.3, MODULE + 0.2, FACE_Z)
	if f[3] == "apt" and f[4] >= 2:
		var ac: Node3D = load(AIRCON).instantiate()
		ac.name = "AirCon"
		front.add_child(ac)
		ac.position = Vector3(x0 + width - 0.9, MODULE * 1.2, FACE_Z)
	if f[5] != "" and f[5] != "bar":
		var cam: Node3D = load(CAMERA).instantiate()
		cam.name = "Camera"
		front.add_child(cam)
		cam.position = Vector3(x0 + width / 2.0 + 0.9, 2.7, FACE_Z)
```
and call `_dress(front, f)` at the end of `_build_front`. Fire escape, air-con and camera models are placed by their origin at the wall; check them in the render and nudge positions (they must not cross z > -4.5 — the test from Task 2 guards it).

`world/StreetLife.gd`: after the traffic car is instanced (`load("res://assets/kenney/cars/%s.glb" ...)`), mute its paint:
```gdscript
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.transparency = 0.0
		var base := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if base:
			var muted := base.duplicate() as StandardMaterial3D
			muted.albedo_color = muted.albedo_color.lerp(Color(0.25, 0.25, 0.27), 0.55)
			muted.roughness = maxf(muted.roughness, 0.55)
			mi.set_surface_override_material(0, muted)
```

Regenerate; keep only `world/City3D.tscn`.

- [ ] **Step 4: Run, expect PASS** — `t.sh smoke_world_art`.

- [ ] **Step 5: Performance A/B.** Scratch `dev-tools/_ab.gd` (from the earlier performance work): load City3D at 20:00 on Medium, freeze, measure GPU time 3× with `Facades`/new props visible vs hidden (`visible = false` on `Facades` and on every `Streetlight*/Model`, `Car*/Model`). Budget: visible ≤ hidden × 1.10. Also measure on Low. If over: set `cast_shadow = SHADOW_CASTING_SETTING_OFF` on upper-floor pieces and windows in `_piece` when `y > 0`, rerun; then drop window inserts on floors ≥ 2; rerun. Record the numbers in the commit message. Delete `_ab.gd`.

- [ ] **Step 6: Full regression** — `T=1700 t.sh smoke_test_3d` → `PASS`. Street-level and game-camera renders opened for the partner.

- [ ] **Step 7: Commit** — "Real street lamps, cars, paving and wall dressing on the block".

---

### Task 4: The apartment

**Files:**
- Modify: `dev-tools/build_rooms_3d.gd` `_build_apartment()` (lines ~467-725)
- Regenerate: `world/Apartment3D.tscn`

**Interfaces:**
- Consumes: `_ph()`; Poly Haven `old_bed_frame`, `sofa_02`, `WoodenChair_01`, `metal_trash_can`, `pull_chain_light_socket`, `wall_clock`, `Television_01`.
- Produces: nodes keep their names and positions: `Bed` (Area3D), `Couch`, `TV`, `RadioCrate/Radio`, `Guitar`, `CoatHook/Coat`, `RingBox`, `ChairOverturned`, `BoxStack`, `BareBulb`.

- [ ] **Step 1: Failing tests** (append):

```gdscript
	var apt := await _load("res://world/Apartment3D.tscn")
	var uses := func(node: Node, id: String) -> bool: return node.find_children("*", "Node3D", true, false).any(func(n): return String(n.scene_file_path).contains("/" + id + "/"))
	_check(uses.call(apt.get_node("Bed"), "old_bed_frame") and uses.call(apt.get_node("Couch"), "sofa_02") and uses.call(apt.get_node("ChairOverturned"), "WoodenChair_01"),
		"  apartment: a real bed frame, sofa and chair")
	_check(apt.get_node("Bed").get_node_or_null("Mattress") != null, "  ...the stained mattress still on the frame")
	_check(apt.find_children("*", "Node3D", true, false).filter(func(n): return String(n.scene_file_path).contains("kenney/furniture")).size() <= 2,
		"  ...and little left of the toy furniture")
	# A taken belonging still disappears with its new model (Review Focus 5).
	gs.take_belonging("tv")
	apt = await _load("res://world/Apartment3D.tscn")
	_check(not apt.get_node("TV").visible, "  a taken TV is gone from the room")
	gs.start_run()
```

- [ ] **Step 2: Run, expect FAIL** on bed/sofa/chair and toy furniture.

- [ ] **Step 3: Implement** in `_build_apartment()`:
- `Bed`: keep the Area3D, its zone collision, `_blocker` and `Mattress`; add `_ph(bed, "Frame", "old_bed_frame", Vector3(0, 0, 0), 1.0, 90.0)` and raise `Mattress`, `Pillow`, `BlanketA/B` by the frame's measured deck height (read `old_bed_frame` AABB in Godot once; the frame's mattress deck is the top of its side rails). Replace the Kenney `Pillow` with a `_box_mesh` pillow (0.5 × 0.12 × 0.32, `_tex_mat(ENV3D + "mattress_stained.png", 1.2, 0.95)`).
- `Couch`: keep the StaticBody3D and its collision; replace the six box meshes with `_ph(couch, "Model", "sofa_02", Vector3.ZERO, 1.0, 90.0)` (it faces east into the room) and keep `FallenCushion` on the floor.
- `ChairOverturned`: replace the Kenney chair with `var chair_model := _ph(chair, "Model", "WoodenChair_01", Vector3(0.35, 0.4, 0.4), 1.0)` with the same `rotation_degrees = Vector3(0, 30, 90)`.
- `Trashcan` → `_ph(_root, "Trashcan", "metal_trash_can", Vector3(2.7, 0, 3.0))`.
- `BareBulb`: replace the `Cord` cylinder with `_ph(bulb, "Socket", "pull_chain_light_socket", Vector3(0, 1.95, 0))`; keep `Glass`, `Light`, sounds.
- Add `_ph(_root, "WallClock", "wall_clock", Vector3(-2.6, 1.9, -3.47))` (north wall, stopped clock).
- `TV` keeps `Television_01` on its box; `RadioCrate/Radio` keeps the Kenney radio (no CC0 period radio fits) — the "≤ 2 toy pieces" check allows it plus the floor lamp.

Regenerate; keep only `world/Apartment3D.tscn`.

- [ ] **Step 4: Run, expect PASS**; pilot `"scene Apartment3D" "shot apt" "closeup Bed" "shot bed" "closeup Couch" "shot couch"`, read the PNGs, fix floating or sunk props, rerun.

- [ ] **Step 5: Full regression green, commit** — "Furnish the apartment with real, worn things".

---

### Task 5: The Dive Bar

**Files:**
- Modify: `dev-tools/build_rooms_3d.gd` `_booth()`, `_build_dive_bar()`
- Regenerate: `world/DiveBar3D.tscn`

**Interfaces:**
- Consumes: PBR `wood_dark`, `leather_red`, `felt`; Poly Haven `bar_chair_round_01`, `metal_stool_01`, `wine_bottles_01`, `WoodenTable_01`, `hanging_industrial_lamp`.
- Produces: unchanged names: `BarCounter`, `BoothA/B`, `PoolTable` (+ `PoolZone`), `HighTopA/B`, `Stool1..5`, `PoolLamp/Light`, `Jukebox`, `Patron1..3`, `Bartender`.

- [ ] **Step 1: Failing tests** (append):

```gdscript
	var bar := await _load("res://world/DiveBar3D.tscn")
	var stools := bar.find_children("Stool*", "Node3D", false, false)
	_check(stools.size() == 5 and stools.all(func(s): return String(s.scene_file_path).contains("polyhaven")), "  bar: real stools (%d)" % stools.size())
	var tex_of := func(mi: MeshInstance3D) -> String:
		var m := (mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)) as StandardMaterial3D
		return String(m.albedo_texture.resource_path) if m and m.albedo_texture else ""
	_check(tex_of.call(bar.get_node("BarCounter/WornTop")).contains("wood_dark") and tex_of.call(bar.get_node("BoothA/SeatN")).contains("leather_red") and tex_of.call(bar.get_node("PoolTable/Felt")).contains("felt"),
		"  ...wood, vinyl and felt that look like wood, vinyl and felt")
	_check(bar.find_children("BackBarBottles*", "Node3D", true, false).size() > 0 and bar.get_node_or_null("PoolLamp/Model") != null, "  ...real bottles behind the bar and a lamp over the pool table")
	_check(bar.get_node_or_null("PoolTable/PoolZone") != null and bar.get_node_or_null("Jukebox") != null, "  ...and the pool table and jukebox still play")
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement:**
- `_booth`: `vinyl := _tex_mat("pbr:leather_red", 1.0)`; `formica` stays a colour; `SeatBase` uses `_tex_mat("pbr:wood_dark", 1.0)`.
- `BarCounter/WornTop` material → `_tex_mat("pbr:wood_dark", 1.0)`.
- Back bar: keep the six `BackBar%d` Kenney bookcases' positions but replace the per-shelf Kenney bottles with one `_ph(_root, "BackBarBottles%d" % (i + 1), "wine_bottles_01", Vector3(bx + 0.45, shelf_y, -hd + 0.3), 1.0)` per shelf.
- Stools: `_ph(_root, "Stool%d" % (i + 1), "bar_chair_round_01" if i % 2 == 0 else "metal_stool_01", Vector3(-4.7 + i * 1.2, 0, -1.8), 1.0, i * 23.0)`; drop the duct-tape patches (they were sized to the Kenney seat).
- `HighTopA/B`: keep collision; replace `Top`/`Post`/`Foot` with `_ph(top, "Model", "WoodenTable_01", Vector3.ZERO, 1.0)` — if WoodenTable_01 is lower than 1.0 m, scale y so its top is at 1.0 (measure once).
- `PoolTable/Felt` → `_tex_mat("pbr:felt", 1.0)` with `albedo_color = Color(0.18, 0.42, 0.22)`; `Body`, `Leg`, `Rail*` → `_tex_mat("pbr:wood_dark", 1.0)`.
- `PoolLamp`: keep `Light`; replace `Shade`, `Glass*`, `Chain` with `_ph(lamp, "Model", "hanging_industrial_lamp", Vector3(0, -0.1, 0))` (two of them at x ±0.5 if one is too small for a 2.5 m table).

Regenerate; keep only `world/DiveBar3D.tscn`.

- [ ] **Step 4: Run, expect PASS**; pilot `"clock 21:00" "preset High" "scene DiveBar3D" "shot bar" "closeup BoothA" "shot booth" "closeup PoolTable" "shot pool"`; read and fix.

- [ ] **Step 5: Performance A/B** for DiveBar3D on Medium (new props visible vs Kenney equivalents isn't possible after the swap — compare against `master`'s DiveBar3D by running the same `_ab.gd` on a `git stash`-free worktree: `git worktree add ../ds-base master`, run there, then here). Budget ≤ 1.10×. Record numbers.

- [ ] **Step 6: Full regression green, commit** — "Give the Dive Bar real wood, vinyl, bottles and stools".

---

### Task 6: The stores

**Files:**
- Modify: `dev-tools/build_rooms_3d.gd` `_store_shell()`, `_fixture_shelf()`, `_fixture_bottles()`, `_fixture_cooler()`, `_fixture_glass_case()`, the five `_build_store_*()` floor calls
- Regenerate: `world/Store*3D.tscn`

**Interfaces:**
- Consumes: PBR `tiles_white`, `tiles_beige`, `plaster_painted`, `metal_worn`, `metal_brushed`; Poly Haven `steel_frame_shelves_01`, `mounted_fluorescent_lights`, `worn_metal_rack`, `WetFloorSign_01`, `security_camera_01`.
- Produces: `Fixture%d` StaticBody3D keep their collision shapes (2.0 × 2.2 × 0.63 for shelves — sight blockers), `item_offset`/`stock` meta and `Item%d`; `Strip%d_%d` lights keep positions.

- [ ] **Step 1: Failing tests** (append):

```gdscript
	for store in ["StoreConvenience3D", "StorePharmacy3D", "StoreSupermarket3D", "StoreLiquor3D", "StoreElectronics3D"]:
		var room := await _load("res://world/%s.tscn" % store)
		var toy := room.find_children("*", "Node3D", true, false).filter(func(n): return String(n.scene_file_path).contains("bookcaseOpen"))
		var tubes := room.find_children("StripFixture*", "Node3D", false, false)
		var blockers := room.find_children("Fixture*", "StaticBody3D", false, false).all(func(f): return f.find_children("*", "CollisionShape3D", false, false).size() > 0)
		_check(toy.is_empty() and tubes.size() > 0 and tubes.all(func(t): return String(t.scene_file_path).contains("mounted_fluorescent")) and blockers,
			"  %s: steel shelving, real tube lights, same sight blockers" % store)
```

- [ ] **Step 2: Run, expect FAIL** for all five.

- [ ] **Step 3: Implement:**
- `_store_shell`: walls `paint` → `_tex_mat("pbr:plaster_painted", 1.0)` with `albedo_color = wall_color`; replace each `StripFixture` box with `_ph(_root, "StripFixture%d_%d" % [ix, iz], "mounted_fluorescent_lights", Vector3(x, 2.4, z))` (scale to ~1.2 m long by its measured length); keep the `Strip` lights. Add `_ph(_root, "Camera", "security_camera_01", Vector3(w / 2 - 0.3, 2.3, -d / 2 + 0.3), 1.0, 225.0)`.
- `_fixture_shelf` and `_fixture_bottles`: replace the two Kenney `bookcaseOpen` instances with one `_ph(shelf, "Unit", "steel_frame_shelves_01", Vector3(0, 0, 0), 1.0)` scaled so it spans 2.0 × 2.2 m (measure its AABB once; scale x and y independently via the returned node's `scale`); move the stock rows onto its shelf heights (measured). Keep the collision box and meta exactly.
- `_fixture_cooler`: `Base`/`Back` → `_tex_mat("pbr:metal_brushed", 1.0)`.
- `_fixture_glass_case`: `Base` → `_tex_mat("pbr:metal_worn", 1.0)`.
- Floors: supermarket and pharmacy `"pbr:tiles_white"`, convenience and liquor `"pbr:tiles_beige"`, electronics keeps its floor.
- One `_ph(_root, "WetFloor", "WetFloorSign_01", ...)` in the supermarket aisle and a `worn_metal_rack` at the back of the convenience store, placed clear of every fixture layout (check `fixture_layouts` positions so nothing overlaps; the store layouts move fixtures at runtime).

Regenerate; keep the five store scenes.

- [ ] **Step 4: Run, expect PASS**; pilot each store `"clock 14:00" "scene StoreLiquor3D" "shot liquor"` etc.; read and fix.

- [ ] **Step 5: Performance A/B** for StoreSupermarket3D on Medium (the most tube fittings) against `master` in the `../ds-base` worktree from Task 5: budget ≤ 1.10×. Over budget: replace `mounted_fluorescent_lights` with a built fitting (a `metal_brushed` box housing 1.2 × 0.08 × 0.2 and two emissive `_cylinder` tubes) and change the test to look for those tubes; rerun.

- [ ] **Step 6: Full regression green, commit** — "Steel shelving, tube lights and real surfaces in the stores".

---

### Task 7: Finish

**Files:** `README.md`; delete `mockup_tmp/`.

- [ ] **Step 1:** README: replace the **Art** bullet's building sentence with the new facades (Poly Haven modular kits, `world/Facades.gd`), and add one bullet "**Real places**" summarising the street, apartment, bar and stores, the asset sources, the fetch scripts and the performance numbers measured in Tasks 3 and 5.
- [ ] **Step 2:** `rm -rf mockup_tmp` (gitignored scratch), remove its `.gitignore` line.
- [ ] **Step 3:** Full regression `T=1700 t.sh smoke_test_3d` → PASS; final before/after renders of street, apartment, bar and one store opened for the partner.
- [ ] **Step 4: Commit** — "Document chapter 1: real places".
