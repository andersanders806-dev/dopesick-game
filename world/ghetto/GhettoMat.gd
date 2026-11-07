extends RefCounted
## Shared material cache for the Ghetto Wars set's scripts.

static var _mats := {}

static func mat(color: Color, rough := 0.85, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(true), rough, metal, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m

## A WAV as a forward-looping stream (the imported file's own loop flags are off); null if it is not there.
static func loop_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		var bytes := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / (bytes * (2 if w.stereo else 1))
		return w
	return s as AudioStream

## A 3D loop player at `pos` under `parent`, already playing.
static func loop_player(parent: Node, path: String, pos: Vector3, vol := 0.0, max_d := 30.0, unit := 6.0) -> AudioStreamPlayer3D:
	var st := loop_stream(path)
	if st == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	p.volume_db = vol
	p.max_distance = max_d
	p.unit_size = unit
	parent.add_child(p)
	p.position = pos
	p.play()
	return p
