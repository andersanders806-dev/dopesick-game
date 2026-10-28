extends RefCounted
## A real recording under every room, so each place sounds like where you
## are: traffic on the street, chatter in the bar, freezer hum and a till in
## the supermarket, the jail's echo. CC0 field recordings from Freesound --
## see assets/sfx/places/CREDITS.txt. The rooms' own positional sounds (the
## bulb, the cooler, the TV, the jukebox) still play on top; the generic
## synthesised room tone some rooms had is replaced, not doubled.

const DIR := "res://assets/sfx/places/"
## Scene name: [recording, volume dB on the Ambience bus]. All are
## normalised to -26 LUFS, so these set the mix, not the level.
const PLACES := {
	"Apartment3D": [DIR + "apartment.ogg", -9.0],
	"City3D": [DIR + "city.ogg", -4.0],
	"DiveBar3D": [DIR + "bar.ogg", -7.0],
	"Jail3D": [DIR + "jail.ogg", -8.0],
	"Backyard3D": [DIR + "backyard.ogg", -6.0],
	"Pawn3D": [DIR + "pawn.ogg", -11.0],
	"Shelter3D": [DIR + "shelter.ogg", -9.0],
	"MusicStore3D": [DIR + "music.ogg", -11.0],
	# The track's outside the office window: low, so it reads as through a wall.
	"KartCenter3D": [DIR + "karts.ogg", -16.0],
	"StoreConvenience3D": [DIR + "convenience.ogg", -10.0],
	"StoreLiquor3D": [DIR + "liquor.ogg", -10.0],
	"StorePharmacy3D": [DIR + "pharmacy.ogg", -11.0],
	"StoreSupermarket3D": [DIR + "supermarket.ogg", -9.0],
	"StoreElectronics3D": [DIR + "electronics.ogg", -11.0],
}

static func apply(room: Node) -> void:
	var key := room.scene_file_path.get_file().get_basename()
	if not PLACES.has(key) or room.get_node_or_null("PlaceAmbience"):
		return
	var tone := room.get_node_or_null("RoomTone") as AudioStreamPlayer
	if tone:
		tone.stop()
		tone.autoplay = false
	var stream: AudioStream = load(PLACES[key][0])
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	var p := AudioStreamPlayer.new()
	p.name = "PlaceAmbience"
	p.set_meta("track", PLACES[key][0])
	p.set_meta("street", stream)
	p.set_meta("street_db", PLACES[key][1])
	p.stream = stream
	p.volume_db = PLACES[key][1]
	p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	room.add_child(p)
	# Start somewhere in the loop, so walking back into a room doesn't
	# restart the same car going past.
	p.play(randf() * maxf(stream.get_length() - 1.0, 0.0))

## The recordings of the shops you can walk into from the street: preloaded
## (nothing loads while you walk), looped on first use.
const SHOP_TRACKS := {
	"convenience": [preload("res://assets/sfx/places/convenience.ogg"), "convenience.ogg", -10.0],
	"liquor": [preload("res://assets/sfx/places/liquor.ogg"), "liquor.ogg", -10.0],
	"pawn": [preload("res://assets/sfx/places/pawn.ogg"), "pawn.ogg", -11.0],
	"music": [preload("res://assets/sfx/places/music.ogg"), "music.ogg", -11.0],
}
static var _looped := {}

## Walking into a shop on the street swaps the street's recording for the
## shop's; `place` "" swaps it back.
static func indoors(room: Node, place: String) -> void:
	var p := room.get_node_or_null("PlaceAmbience") as AudioStreamPlayer
	# (Not while the street is being torn down: bodies leave its shops then.)
	if p == null or not p.is_inside_tree():
		return
	var stream: AudioStream = p.get_meta("street")
	var db: float = p.get_meta("street_db")
	var track := DIR + "city.ogg"
	if SHOP_TRACKS.has(place):
		var t: Array = SHOP_TRACKS[place]
		if not _looped.has(place):
			var src: AudioStream = t[0]
			if src is AudioStreamOggVorbis:
				src = src.duplicate()
				src.loop = true
			_looped[place] = src
		stream = _looped[place]
		db = t[2]
		track = DIR + t[1]
	if String(p.get_meta("track")) == track:
		return
	p.set_meta("track", track)
	p.stream = stream
	p.volume_db = db
	p.play(randf() * maxf(stream.get_length() - 1.0, 0.0))
