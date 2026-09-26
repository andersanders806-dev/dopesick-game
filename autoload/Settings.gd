extends Node
## Player-facing options: look sensitivity, field of view, volume, display.
## Saved to user://settings.cfg and applied on boot, so they survive restarts.
## The main menu and the pause menu share one panel (ui/SettingsPanel.gd)
## that edits these and calls save_settings().

signal changed

const PATH := "user://settings.cfg"
## Radians of turn per pixel of mouse travel at sensitivity 1.0.
const BASE_SENSITIVITY := 0.0022

var mouse_sensitivity: float = 1.0
var fov: float = 80.0
var invert_y: bool = false
var master_volume: float = 0.8
var fullscreen: bool = false
var head_bob: bool = true
var show_fps: bool = false

func _ready() -> void:
	load_settings()
	apply()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	fov = cfg.get_value("video", "fov", fov)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	head_bob = cfg.get_value("video", "head_bob", head_bob)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "head_bob", head_bob)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(PATH)
	apply()

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	# The headless test runner has no window to resize.
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	changed.emit()

func look_radians_per_pixel() -> float:
	return BASE_SENSITIVITY * mouse_sensitivity
