extends RefCounted
## How each kind of gun is carried and worked: where it sits on the hip, how it is held when sprinting,
## and the hands' choreography for a reload (a tactical one with rounds left, an empty one that ends
## on the rack / slide release / pump / bolt) and for the first raise of a gun the first time you pick
## it up. Pure data and a few static functions: player/FPFeel.gd plays them, player/Viewmodel.gd
## moves what they say.
##
## A choreography is a Dictionary of tracks over progress 0..1:
##   gun   [t, px, py, pz, rx, ry, rz]       the gun's offset (m, camera space) and turn (degrees)
##   hand  [t, anchor, ox, oy, oz]            the support hand (anchors: Viewmodel.anchors, "belt", "hand")
##   open  [t, amount]                        the support hand open (1) or closed on something (0)
##   rhand [t, ox, oy, oz]                    the firing hand's shift off the grip (m, gun space)
##   ropen [t, amount]
##   mag   [t, shown, anchor, ox, oy, oz, rx, ry, rz]   the magazine / shell / round in the hand
##   cut   [[t0, t1], ...]                    the gun's own magazine is not drawn
##   slide / bolt  [t, back]                  a moving part of the model, metres to the back
##   ev    [t, sound, flag]                   sounds at their moments ("drop": the carried magazine falls)

# --- Where the gun sits on the hip (camera space) and how it turns [pos, rot degrees] ----------------
# Modern Warfare carries the gun low and right with the muzzle leaning to the centre of the screen:
# the receiver shows, the stock is out of the picture.
const HIP := {
	"pistol": [Vector3(0.1, -0.135, -0.32), Vector3(0.0, 0.0, 0.0)],
	"magnum": [Vector3(0.12, -0.155, -0.34), Vector3(0.0, 0.0, 0.0)],
	"smg": [Vector3(0.175, -0.175, -0.36), Vector3(0.0, 4.5, 0.0)],
	"ar": [Vector3(0.2, -0.185, -0.36), Vector3(0.0, 6.0, 0.0)],
	"lmg": [Vector3(0.215, -0.2, -0.38), Vector3(0.0, 7.0, 0.0)],
	"shotgun": [Vector3(0.2, -0.185, -0.38), Vector3(0.0, 5.5, 0.0)],
	"sniper": [Vector3(0.2, -0.19, -0.38), Vector3(0.0, 5.0, 0.0)],
	"wonder": [Vector3(0.19, -0.185, -0.36), Vector3(0.0, 5.0, 0.0)],
}

# --- The sprint pose, added to the hip's: [pos, rot degrees] ---------------------------------------------
const SPRINT := {
	"pistol": [Vector3(-0.06, 0.05, 0.07), Vector3(24.0, 10.0, -8.0)],
	"magnum": [Vector3(-0.06, 0.05, 0.07), Vector3(24.0, 10.0, -8.0)],
	"smg": [Vector3(-0.07, 0.0, 0.05), Vector3(-6.0, 34.0, -22.0)],
	"ar": [Vector3(-0.08, -0.01, 0.04), Vector3(-10.0, 32.0, -20.0)],
	"lmg": [Vector3(-0.10, -0.03, 0.05), Vector3(-6.0, 38.0, -28.0)],
	"shotgun": [Vector3(-0.07, 0.03, 0.05), Vector3(22.0, 24.0, -14.0)],
	"sniper": [Vector3(-0.08, 0.0, 0.04), Vector3(-4.0, 34.0, -18.0)],
	"wonder": [Vector3(-0.07, 0.0, 0.04), Vector3(-8.0, 30.0, -18.0)],
}

## How heavy a gun feels: a multiple of the sway, the lag when strafing and the landing.
const WEIGHT := {"pistol": 0.7, "magnum": 0.8, "smg": 0.85, "ar": 1.0, "lmg": 1.6, "shotgun": 1.1, "sniper": 1.3, "wonder": 1.0}
## Breathing of the sights when aimed (a multiple): a sniper's rises and falls the most.
const ADS_BREATH := {"pistol": 0.8, "magnum": 0.9, "smg": 0.9, "ar": 1.0, "lmg": 1.2, "shotgun": 1.0, "sniper": 1.8, "wonder": 1.0}

## Where the vest is in camera space (the dump pouch the support hand fetches magazines from).
const VEST := Vector3(-0.22, -0.42, -0.26)

## Where a spent case leaves and how: per family, the port (a fraction of the gun's box: x, y, z from the
## muzzle), the case's velocity in camera space (x right, y up, z back) as [lo, hi] boxes, its spin, its size
## (radius, length) and the kind (0 brass, 1 red shotgun hull).
const EJECT := {
	"pistol": {"port": Vector3(1.0, 0.92, 0.62), "lo": Vector3(1.5, 1.4, 0.1), "hi": Vector3(2.4, 2.2, 0.7), "spin": 38.0, "size": Vector2(0.0048, 0.019), "kind": 0},
	"magnum": {"port": Vector3(1.0, 0.82, 0.55), "lo": Vector3(0.0, 0.0, 0.0), "hi": Vector3(0.0, 0.0, 0.0), "spin": 0.0, "size": Vector2(0.006, 0.03), "kind": 0},
	"smg": {"port": Vector3(1.0, 0.82, 0.58), "lo": Vector3(1.8, 1.2, 0.1), "hi": Vector3(2.8, 2.0, 0.8), "spin": 46.0, "size": Vector2(0.0048, 0.019), "kind": 0},
	"ar": {"port": Vector3(1.0, 0.82, 0.56), "lo": Vector3(1.8, 1.0, 0.3), "hi": Vector3(2.9, 2.0, 1.1), "spin": 52.0, "size": Vector2(0.0056, 0.045), "kind": 0},
	"lmg": {"port": Vector3(1.0, 0.7, 0.58), "lo": Vector3(1.4, 0.2, 0.2), "hi": Vector3(2.2, 1.0, 0.8), "spin": 30.0, "size": Vector2(0.0075, 0.054), "kind": 0},
	"shotgun": {"port": Vector3(1.0, 0.62, 0.5), "lo": Vector3(1.2, 1.6, 0.2), "hi": Vector3(2.0, 2.6, 0.9), "spin": 24.0, "size": Vector2(0.0105, 0.07), "kind": 1},
	"sniper": {"port": Vector3(1.0, 0.72, 0.58), "lo": Vector3(1.4, 1.8, 0.3), "hi": Vector3(2.2, 2.8, 1.0), "spin": 22.0, "size": Vector2(0.0062, 0.056), "kind": 0},
	"wonder": {"port": Vector3(1.0, 0.8, 0.56), "lo": Vector3(0.0, 0.0, 0.0), "hi": Vector3(0.0, 0.0, 0.0), "spin": 0.0, "size": Vector2(0.005, 0.02), "kind": 0},
}

static func family_of(vm) -> String:
	var f: String = vm.data.family() if vm != null and vm.data != null else "ar"
	return f if HIP.has(f) else "ar"

static func hip(f: String) -> Array:
	return HIP.get(f, HIP["ar"])

# --- Evaluating a choreography -----------------------------------------------------------------------

## Piecewise smooth value between keys [[t, v], ...] (v a float).
static func _f(keys: Array, p: float) -> float:
	if keys.is_empty():
		return 0.0
	if p <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if p <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var u: float = (p - a[0]) / maxf(b[0] - a[0], 0.0001)
			return lerpf(a[1], b[1], smoothstep(0.0, 1.0, u))
	return keys[keys.size() - 1][1]

## Same for keys [t, x, y, z, ...] -> Vector3 of the entries from `from`.
static func _v(keys: Array, p: float, from := 1) -> Vector3:
	if keys.is_empty():
		return Vector3.ZERO
	var k0: Array = keys[0]
	if p <= k0[0]:
		return Vector3(k0[from], k0[from + 1], k0[from + 2])
	for i in range(1, keys.size()):
		var kb: Array = keys[i]
		if p <= kb[0]:
			var ka: Array = keys[i - 1]
			var u: float = (p - ka[0]) / maxf(kb[0] - ka[0], 0.0001)
			u = smoothstep(0.0, 1.0, u)
			return Vector3(ka[from], ka[from + 1], ka[from + 2]).lerp(Vector3(kb[from], kb[from + 1], kb[from + 2]), u)
	var kl: Array = keys[keys.size() - 1]
	return Vector3(kl[from], kl[from + 1], kl[from + 2])

static func _anchor(vm, name: String, xf: Transform3D) -> Vector3:
	if name == "belt":
		return xf.affine_inverse() * VEST
	return vm.anchors.get(name, vm.grip_l)

## The support hand at progress `t`.
static func _hand(vm, hk: Array, t: float, xf: Transform3D) -> Vector3:
	if hk.is_empty():
		return vm.grip_l
	var res: Array = []
	for k in hk:
		var v := _anchor(vm, k[1], xf) + Vector3(k[2], k[3], k[4])
		res.append([k[0], v.x, v.y, v.z])
	return _v(res, t, 1)

## The whole state at progress p: pos / rot (radians) for the gun, hand, open, rhand, ropen, mag (shown,
## pos, rot degrees), cut, parts.
static func eval(vm, def: Dictionary, p: float, base: Transform3D) -> Dictionary:
	var out := {}
	var gk: Array = def.get("gun", [])
	out["pos"] = _v(gk, p, 1)
	var rd := _v(gk, p, 4)
	out["rot"] = Vector3(deg_to_rad(rd.x), deg_to_rad(rd.y), deg_to_rad(rd.z))
	# Where the vest is depends on how the gun is turned: the hand's frame follows the pose.
	var xf := Transform3D(base.basis * Basis.from_euler(out["rot"]), base.origin + out["pos"])
	var hk: Array = def.get("hand", [])
	out["hand"] = _hand(vm, hk, p, xf)
	out["open"] = _f(def.get("open", []), p)
	out["rhand"] = _v(def.get("rhand", []), p, 1)
	out["ropen"] = _f(def.get("ropen", []), p)
	# The carried magazine.
	var mk: Array = def.get("mag", [])
	var shown := false
	var mpos: Vector3 = vm.magwell
	var mrot := Vector3.ZERO
	if not mk.is_empty():
		var seg := 0
		for i in range(mk.size()):
			if p >= mk[i][0]:
				seg = i
		var a: Array = mk[seg]
		shown = int(a[1]) == 1
		var pa := _mag_point(vm, a, out["hand"], xf)
		mpos = pa
		mrot = Vector3(a[6], a[7], a[8])
		if seg + 1 < mk.size():
			var b: Array = mk[seg + 1]
			var u: float = smoothstep(0.0, 1.0, (p - a[0]) / maxf(b[0] - a[0], 0.0001))
			mpos = pa.lerp(_mag_point(vm, b, out["hand"], xf), u)
			mrot = mrot.lerp(Vector3(b[6], b[7], b[8]), u)
	out["mag_shown"] = shown
	out["mag_pos"] = mpos
	out["mag_rot"] = mrot
	var cut := false
	for r in def.get("cut", []):
		if p >= r[0] and p <= r[1]:
			cut = true
	out["cut"] = cut
	var parts := {}
	for pn in ["slide", "bolt"]:
		if def.has(pn):
			parts[pn] = Vector3(0.0, 0.0, _f(def[pn], p))
	out["parts"] = parts
	return out

static func _mag_point(vm, key: Array, hand_now: Vector3, xf: Transform3D) -> Vector3:
	var off := Vector3(key[3], key[4], key[5])
	if key[2] == "hand":
		return hand_now + off
	return _anchor(vm, key[2], xf) + off

# --- The reloads ------------------------------------------------------------------------------------

## Builds the choreography for a family. `empty`: the magazine ran dry (adds the rack / slide release / pump / bolt);
## `n`: how many shells a shotgun takes in.
static func reload_plan(f: String, empty: bool, n := 4) -> Dictionary:
	match f:
		"pistol", "magnum":
			return _pistol(empty)
		"shotgun":
			return _shotgun(empty, n)
		"sniper":
			return _sniper(empty)
		"lmg":
			return _lmg(empty)
	return _rifle(empty, f)

## How the gun is turned up and over for a reload so the magazine well / port comes into the picture:
## [offset (m, camera space), turn (degrees)].
const CANTS := {
	"pistol": [Vector3(-0.05, 0.14, 0.0), Vector3(20.0, 0.0, -22.0)],
	"magnum": [Vector3(-0.05, 0.14, 0.0), Vector3(20.0, 0.0, -22.0)],
	"smg": [Vector3(-0.04, 0.11, -0.08), Vector3(16.0, 12.0, -22.0)],
	"ar": [Vector3(-0.04, 0.11, -0.08), Vector3(16.0, 12.0, -22.0)],
	"lmg": [Vector3(-0.08, 0.08, -0.02), Vector3(8.0, 6.0, -14.0)],
	"shotgun": [Vector3(-0.03, 0.1, -0.1), Vector3(18.0, 10.0, -20.0)],
	"sniper": [Vector3(-0.04, 0.095, -0.08), Vector3(14.0, 10.0, -20.0)],
	"wonder": [Vector3(-0.05, 0.12, -0.05), Vector3(16.0, 12.0, -22.0)],
}

## A gun key at time t: the family's cant scaled by k.
static func _g(t: float, f: String, k := 1.0) -> Array:
	var c: Array = CANTS.get(f, CANTS["ar"])
	var p: Vector3 = c[0] * k
	var r: Vector3 = c[1] * k
	return [t, p.x, p.y, p.z, r.x, r.y, r.z]

static func _rifle(empty: bool, f := "ar") -> Dictionary:
	var d := {}
	if not empty:
		d["gun"] = [_g(0.0, f, 0.0), _g(0.12, f), _g(0.62, f), _g(0.70, f, 0.8), _g(0.74, f, 0.7), _g(0.9, f, 0.0), _g(1.0, f, 0.0)]
		d["hand"] = [[0.0, "grip_l", 0, 0, 0], [0.12, "magwell", 0, -0.045, 0.0], [0.19, "magwell", 0, -0.045, 0.0],
			[0.27, "magwell", 0, -0.1, 0.03], [0.34, "belt", 0, 0, 0], [0.46, "belt", 0, 0, 0], [0.56, "magwell", 0, -0.1, 0.03],
			[0.64, "magwell", 0, -0.045, 0.0], [0.70, "magwell", 0, -0.04, 0.0], [0.74, "magwell", 0, -0.05, 0.0], [0.9, "grip_l", 0, 0, 0]]
		d["open"] = [[0.0, 0.0], [0.07, 0.9], [0.13, 0.0], [0.33, 0.0], [0.36, 0.8], [0.44, 0.7], [0.47, 0.0], [0.7, 0.0], [0.74, 0.7], [0.82, 0.2], [0.9, 0.0]]
		d["mag"] = [[0.0, 0, "magwell", 0, 0, 0, 0, 0, 0], [0.13, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.34, 1, "hand", 0, 0.05, 0, 0, 0, 40],
			[0.36, 0, "hand", 0, 0.05, 0, 0, 0, 40], [0.45, 0, "hand", 0, 0.05, 0, 0, 0, 30], [0.47, 1, "hand", 0, 0.05, 0, 0, 0, 30],
			[0.56, 1, "hand", 0, 0.05, 0, 0, 0, 10], [0.70, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.71, 0, "magwell", 0, 0, 0, 0, 0, 0]]
		d["cut"] = [[0.13, 0.71]]
		d["ev"] = [[0.20, "mag_out", ""], [0.64, "mag_in", ""]]
	else:
		d["gun"] = [_g(0.0, f, 0.0), _g(0.10, f), _g(0.50, f), _g(0.58, f, 0.6), _g(0.64, f, 0.25), [0.75, 0, 0, 0.02, 3, -2, -4], _g(0.80, f, 0.0), _g(1.0, f, 0.0)]
		d["hand"] = [[0.0, "grip_l", 0, 0, 0], [0.10, "magwell", 0, -0.045, 0.0], [0.15, "magwell", 0, -0.045, 0.0],
			[0.21, "magwell", 0, -0.1, 0.03], [0.30, "belt", 0, 0, 0], [0.38, "belt", 0, 0, 0], [0.47, "magwell", 0, -0.1, 0.03],
			[0.53, "magwell", 0, -0.045, 0.0], [0.57, "magwell", 0, -0.05, 0.0], [0.66, "charge", 0, 0.0, 0.0],
			[0.75, "charge", 0, 0.0, 0.1], [0.80, "charge", 0, 0.0, 0.0], [0.90, "grip_l", 0, 0, 0]]
		d["open"] = [[0.0, 0.0], [0.05, 0.9], [0.11, 0.0], [0.21, 0.0], [0.23, 0.9], [0.3, 0.8], [0.37, 0.6], [0.39, 0.0], [0.55, 0.0],
			[0.6, 0.8], [0.66, 0.4], [0.7, 0.0], [0.8, 0.0], [0.82, 0.6], [0.9, 0.0]]
		d["mag"] = [[0.0, 0, "magwell", 0, 0, 0, 0, 0, 0], [0.11, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.22, 1, "hand", 0, 0.05, 0, 0, 0, 20],
			[0.225, 0, "hand", 0, 0.05, 0, 0, 0, 20], [0.37, 0, "hand", 0, 0.05, 0, 0, 0, 30], [0.39, 1, "hand", 0, 0.05, 0, 0, 0, 30],
			[0.47, 1, "hand", 0, 0.05, 0, 0, 0, 10], [0.56, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.57, 0, "magwell", 0, 0, 0, 0, 0, 0]]
		d["cut"] = [[0.11, 0.57]]
		d["ev"] = [[0.17, "mag_out", ""], [0.215, "", "drop"], [0.53, "mag_in", ""], [0.75, "bolt", ""], [0.80, "rack", ""]]
	return d

static func _pistol(empty: bool) -> Dictionary:
	var d := {}
	var sl := 0.026
	if not empty:
		d["gun"] = [_g(0.0, "pistol", 0.0), _g(0.14, "pistol"), _g(0.58, "pistol"), _g(0.66, "pistol", 0.6), _g(0.72, "pistol", 0.35), _g(0.86, "pistol", 0.0), _g(1.0, "pistol", 0.0)]
		d["hand"] = [[0.0, "grip_l", 0, 0, 0], [0.14, "magwell", 0, -0.04, 0.0], [0.2, "magwell", 0, -0.045, 0.0],
			[0.28, "magwell", 0, -0.09, 0.03], [0.36, "belt", 0, 0, 0], [0.46, "belt", 0, 0, 0], [0.56, "magwell", 0, -0.09, 0.03],
			[0.62, "magwell", 0, -0.045, 0.0], [0.67, "magwell", 0, -0.04, 0.0], [0.72, "magwell", 0, -0.055, 0.0], [0.86, "grip_l", 0, 0, 0]]
		d["open"] = [[0.0, 0.0], [0.09, 0.9], [0.15, 0.0], [0.35, 0.0], [0.4, 0.8], [0.46, 0.5], [0.49, 0.0], [0.68, 0.0], [0.73, 0.7], [0.86, 0.0]]
		d["mag"] = [[0.0, 0, "magwell", 0, 0, 0, 0, 0, 0], [0.15, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.36, 1, "hand", 0, 0.05, 0, 0, 0, 30],
			[0.37, 0, "hand", 0, 0.05, 0, 0, 0, 30], [0.47, 0, "hand", 0, 0.05, 0, 0, 0, 30], [0.49, 1, "hand", 0, 0.05, 0, 0, 0, 20],
			[0.62, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.68, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.69, 0, "magwell", 0, 0, 0, 0, 0, 0]]
		d["ev"] = [[0.22, "mag_out", ""], [0.64, "mag_in", ""]]
		d["slide"] = [[0.0, 0.0], [1.0, 0.0]]
	else:
		d["gun"] = [_g(0.0, "pistol", 0.0), _g(0.12, "pistol"), _g(0.46, "pistol"), _g(0.54, "pistol", 0.6), _g(0.62, "pistol", 0.35), _g(0.78, "pistol", 0.0), _g(1.0, "pistol", 0.0)]
		d["hand"] = [[0.0, "grip_l", 0, 0, 0], [0.12, "magwell", 0, -0.04, 0.0], [0.17, "magwell", 0, -0.045, 0.0],
			[0.23, "magwell", 0, -0.09, 0.03], [0.30, "belt", 0, 0, 0], [0.38, "belt", 0, 0, 0], [0.46, "magwell", 0, -0.09, 0.03],
			[0.51, "magwell", 0, -0.045, 0.0], [0.55, "magwell", 0, -0.05, 0.0], [0.64, "grip_l", 0, 0.0, 0.0],
			[0.70, "grip_l", 0, 0.0, 0.0], [0.74, "grip_l", 0, 0.0, 0.0], [0.86, "grip_l", 0, 0, 0]]
		d["open"] = [[0.0, 0.0], [0.08, 0.9], [0.13, 0.0], [0.29, 0.0], [0.33, 0.8], [0.38, 0.5], [0.4, 0.0], [0.55, 0.0], [0.6, 0.7], [0.7, 0.4], [0.78, 0.0]]
		d["mag"] = [[0.0, 0, "magwell", 0, 0, 0, 0, 0, 0], [0.13, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.24, 1, "hand", 0, 0.05, 0, 0, 0, 20],
			[0.245, 0, "hand", 0, 0.05, 0, 0, 0, 20], [0.4, 0, "hand", 0, 0.05, 0, 0, 0, 30], [0.41, 1, "hand", 0, 0.05, 0, 0, 0, 30],
			[0.46, 1, "hand", 0, 0.05, 0, 0, 0, 10], [0.52, 1, "hand", 0, 0.05, 0, 0, 0, 0], [0.53, 0, "magwell", 0, 0, 0, 0, 0, 0]]
		# The slide is locked back from the last round; the thumb sends it home.
		d["slide"] = [[0.0, sl], [0.68, sl], [0.70, 0.0], [1.0, 0.0]]
		d["ev"] = [[0.19, "mag_out", ""], [0.245, "", "drop"], [0.49, "mag_in", ""], [0.69, "rack", ""]]
	return d

static func _shotgun(empty: bool, n: int) -> Dictionary:
	var d := {}
	n = clampi(n, 1, 6)
	var t0 := 0.12
	var t1 := 0.80 if empty else 0.9
	var gk := [_g(0.0, "shotgun", 0.0), _g(0.1, "shotgun"), _g(t1, "shotgun"), _g(t1 + 0.07, "shotgun", 0.25)]
	if empty:
		gk.append([0.9, 0.0, 0.0, 0.025, 2, -1, -2])
	gk.append(_g(1.0, "shotgun", 0.0))
	d["gun"] = gk
	var hand := [[0.0, "grip_l", 0, 0, 0]]
	var op := [[0.0, 0.0]]
	var mag := [[0.0, 0, "magwell", 0, 0, 0, 0, 0, 0]]
	var ev := []
	var cyc := (t1 - t0) / float(n)
	for i in n:
		var a := t0 + cyc * i
		# belt (take a shell) -> port (push it in) -> a little back out of the way
		hand.append([a + cyc * 0.05, "belt", 0, 0, 0])
		hand.append([a + cyc * 0.2, "belt", 0, 0, 0])
		hand.append([a + cyc * 0.62, "magwell", 0, -0.035, 0.02])
		hand.append([a + cyc * 0.78, "magwell", 0, -0.02, 0.0])
		op.append([a + cyc * 0.05, 0.8])
		op.append([a + cyc * 0.2, 0.0])
		op.append([a + cyc * 0.7, 0.0])
		op.append([a + cyc * 0.85, 0.6])
		mag.append([a + cyc * 0.2, 1, "hand", 0.0, 0.02, 0.0, 0, 0, 0])
		mag.append([a + cyc * 0.78, 1, "hand", 0.0, 0.0, 0.0, 0, 0, 0])
		mag.append([a + cyc * 0.8, 0, "hand", 0.0, 0.02, 0.0, 0, 0, 0])
		ev.append([a + cyc * 0.76, "shell_in", ""])
	if empty:
		hand.append([t1 + 0.02, "grip_l", 0, 0, 0])
		hand.append([t1 + 0.07, "grip_l", 0, 0, 0.0])
		hand.append([0.9, "grip_l", 0, 0, 0.16])
		hand.append([0.95, "grip_l", 0, 0, 0.0])
		ev.append([0.88, "pump", ""])
	else:
		hand.append([t1 + 0.07, "grip_l", 0, 0, 0])
	hand.append([1.0, "grip_l", 0, 0, 0])
	op.append([t1 + 0.05, 0.0])
	d["hand"] = hand
	d["open"] = op
	d["mag"] = mag
	d["ev"] = ev
	return d

static func _sniper(empty: bool) -> Dictionary:
	var d := {}
	d["gun"] = [_g(0.0, "sniper", 0.0), _g(0.1, "sniper"), _g(0.78, "sniper"), _g(0.9, "sniper", 0.0), _g(1.0, "sniper", 0.0)]
	# The right hand lets go of the grip for the bolt handle and goes back to it.
	var bolt_up := Vector3(0.0, 0.0, 0.0)
	d["rhand"] = [[0.0, 0, 0, 0], [0.12, 0, 0.02, -0.02], [0.2, 0.0, 0.04, 0.0], [0.3, 0.0, 0.04, 0.09], [0.62, 0.0, 0.04, 0.09], [0.7, 0.0, 0.04, 0.0], [0.76, 0.0, 0.0, 0.0], [1.0, 0, 0, 0]]
	d["ropen"] = [[0.0, 0.0], [0.1, 0.8], [0.2, 0.0], [0.66, 0.0], [0.76, 0.5], [0.84, 0.0]]
	d["bolt"] = [[0.0, 0.0], [0.2, 0.0], [0.3, 0.075], [0.62, 0.075], [0.7, 0.0], [1.0, 0.0]]
	var strokes := 2 if empty else 1
	var hand := [[0.0, "grip_l", 0, 0, 0], [0.12, "grip_l", 0, 0, 0]]
	var mag := [[0.0, 0, "magwell", 0, 0, 0, 0, 0, 0]]
	var ev := [[0.26, "bolt", ""]]
	var t := 0.3
	for i in strokes:
		var seg := 0.3 / float(strokes)
		hand.append([t, "belt", 0, 0, 0])
		hand.append([t + seg * 0.2, "belt", 0, 0, 0])
		hand.append([t + seg * 0.72, "magwell", 0, 0.03, 0])
		hand.append([t + seg * 0.9, "magwell", 0, 0.015, 0])
		mag.append([t + seg * 0.2, 1, "hand", 0, 0.0, -0.01, 90, 0, 0])
		mag.append([t + seg * 0.88, 1, "hand", 0, 0.0, 0, 90, 0, 0])
		mag.append([t + seg * 0.9, 0, "hand", 0, 0.0, 0, 90, 0, 0])
		ev.append([t + seg * 0.8, "shell_in", ""])
		t += seg
	hand.append([0.7, "grip_l", 0, 0, 0])
	hand.append([1.0, "grip_l", 0, 0, 0])
	ev.append([0.66, "bolt", ""])
	d["hand"] = hand
	d["mag"] = mag
	d["open"] = [[0.0, 0.0], [0.3, 0.0], [0.34, 0.7], [0.4, 0.0], [0.58, 0.0], [0.62, 0.7], [0.7, 0.0]]
	d["ev"] = ev
	return d

static func _lmg(empty: bool) -> Dictionary:
	var d := {}
	d["gun"] = [_g(0.0, "lmg", 0.0), _g(0.1, "lmg"), _g(0.86, "lmg"), _g(0.95, "lmg", 0.0), _g(1.0, "lmg", 0.0)]
	var up := 0.1
	d["hand"] = [[0.0, "grip_l", 0, 0, 0], [0.1, "magwell", -0.115, 0.03, 0.0], [0.18, "magwell", -0.115, 0.03, 0.0], [0.26, "magwell", -0.14, 0.07, 0.0],
		[0.36, "belt", 0, 0, 0], [0.5, "belt", 0, 0, 0], [0.6, "magwell", -0.14, 0.07, 0.0], [0.7, "magwell", -0.115, 0.07, 0.0],
		[0.76, "magwell", -0.115, 0.03, 0.0], [0.8, "magwell", -0.115, 0.04, 0.0], [0.9, "grip_l", 0, 0, 0], [1.0, "grip_l", 0, 0, 0]]
	d["open"] = [[0.0, 0.0], [0.06, 0.8], [0.11, 0.0], [0.35, 0.0], [0.39, 0.7], [0.48, 0.5], [0.52, 0.0], [0.78, 0.0], [0.82, 0.7], [0.9, 0.0]]
	# The real pan comes off the top with the hand, goes to the pouch, and the new one comes back.
	d["mag"] = [[0.0, 1, "magwell", 0, 0, 0, 0, 0, 0], [0.11, 1, "hand", 0.115, -0.03, 0, 0, 0, 0], [0.26, 1, "hand", 0.115, -0.03, 0, 0, 0, 0],
		[0.36, 0, "hand", 0.115, -0.03, 0, 0, 0, 0], [0.5, 0, "hand", 0.115, -0.03, 0, 0, 0, 0], [0.52, 1, "hand", 0.115, -0.03, 0, 0, 0, 0],
		[0.7, 1, "hand", 0.115, -0.03, 0, 0, 0, 0], [0.78, 1, "magwell", 0, 0.012, 0, 0, 0, 0], [0.8, 1, "magwell", 0, 0, 0, 0, 0, 0]]
	d["ev"] = [[0.2, "mag_out", ""], [0.64, "mag_in", ""]]
	if empty:
		d["ev"] = [[0.16, "mag_out", ""], [0.3, "", "drop"], [0.6, "mag_in", ""], [0.82, "bolt", ""]]
		# The right hand hauls the charging handle (on the right of the receiver) once the new pan is on.
		d["rhand"] = [[0.0, 0, 0, 0], [0.8, 0, 0, 0], [0.84, 0.04, 0.0, 0.0], [0.9, 0.04, 0.0, 0.08], [0.95, 0.04, 0.0, 0.0], [1.0, 0, 0, 0]]
		d["gun"] = [_g(0.0, "lmg", 0.0), _g(0.1, "lmg"), _g(0.9, "lmg"), _g(1.0, "lmg", 0.0)]
	return d

# --- The first raise: what MW does the first time you get a gun ---------------------------------------------

## Seconds of the flourish for each family.
const RAISE_TIME := {"pistol": 1.7, "magnum": 1.8, "smg": 1.8, "ar": 2.0, "lmg": 2.4, "shotgun": 2.0, "sniper": 2.2, "wonder": 1.8}

## The first raise: the gun comes up, is turned to show its side, and the support hand works the action.
static func raise(f: String) -> Dictionary:
	var d := {}
	var turn := [[0.0, 0.0, -0.06, 0.03, -20, 8, 18], [0.18, 0.0, 0.0, 0.0, 0, 0, 0], [0.34, 0.03, 0.02, -0.01, 6, -34, 14], [0.58, 0.03, 0.02, -0.01, 6, -34, 14], [0.78, 0, 0, 0, 0, 0, 0], [1.0, 0, 0, 0, 0, 0, 0]]
	d["gun"] = turn
	var act := "charge"
	var snd := "rack"
	var pull := 0.09
	match f:
		"shotgun":
			act = "grip_l"
			snd = "pump"
			pull = 0.16
		"sniper":
			act = "grip_l"
			snd = "bolt"
		"lmg":
			snd = "bolt"
	d["hand"] = [[0.0, "grip_l", 0, 0, 0], [0.5, "grip_l", 0, 0, 0], [0.6, act, 0, 0, 0], [0.7, act, 0, 0, pull], [0.78, act, 0, 0, 0], [0.88, "grip_l", 0, 0, 0], [1.0, "grip_l", 0, 0, 0]]
	d["open"] = [[0.0, 0.0], [0.52, 0.0], [0.58, 0.7], [0.72, 0.5], [0.8, 0.0], [1.0, 0.0]]
	if f == "pistol" or f == "magnum":
		d["slide"] = [[0.0, 0.0], [0.6, 0.0], [0.7, 0.028], [0.78, 0.0], [1.0, 0.0]]
	if f == "sniper":
		d["bolt"] = [[0.0, 0.0], [0.58, 0.0], [0.66, 0.075], [0.78, 0.0], [1.0, 0.0]]
		d["rhand"] = [[0.0, 0, 0, 0], [0.54, 0, 0, 0], [0.6, 0.0, 0.04, 0.0], [0.68, 0.0, 0.04, 0.09], [0.78, 0.0, 0.04, 0.0], [0.84, 0, 0, 0], [1.0, 0, 0, 0]]
	d["ev"] = [[0.64, snd, ""]]
	return d
