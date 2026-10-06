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
	p.stream = stream
	p.volume_db = PLACES[key][1]
	p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	room.add_child(p)
	# Start somewhere in the loop, so walking back into a room doesn't
	# restart the same car going past.
	p.play(randf() * maxf(stream.get_length() - 1.0, 0.0))
