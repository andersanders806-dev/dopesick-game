extends Node
## Dead Block: the zombie mode's own state. Rounds, points, the run's
## stats and its best, kept in user://zombies.cfg. It never reads or writes
## the story: not the save (SaveGame refuses while GameState.mode isn't
## "story"), not GameState's run fields (its clock and meters stand still
## in this mode), not progress.cfg.
##
## begin() sets a run up; start() does that and loads the block. The block
## (world/ZombieBlock.gd) starts round 1; later tasks' spawner ends each
## round with advance_round() once the last zombie is down. game_over() ends
## the run from anywhere (the downed player, tests) and shows the screen.

signal round_started(r: int)
signal round_ended(r: int)
## `amount` is what was earned (negative for a purchase).
signal points_changed(total: int, amount: int, reason: String)
signal game_over_started(summary: Dictionary)
signal health_changed(hp: float)
## The Richter 8.0 surge (npc/ZombieSurge.gd): the warning comes SURGE_WARNING seconds before the
## quake (the build-up: rumble, flicker), then it starts (the zombies erupt, double points) and
## ends (the last one is out; double points linger a few seconds more). fx/Quake.gd shows it.
signal surge_warning
signal surge_started
signal surge_ended
## Ghetto Wars: a round (wave) of the crews; a shot or blast at the player (`from` is where it came from, Vector3.INF if unknown);
## a plate on or off; the war's mood line for the banner.
signal player_damaged(from: Vector3, amount: float, armor_hit: bool)
signal armor_changed(armor: float)
signal bullet_snap(origin: Vector3, closest: Vector3)

const ZombieControls := preload("res://player/ZombieControls.gd")
const CITY_SCENE := "res://world/City3D.tscn"
const TITLE_SCENE := "res://ui/TitleScreen.tscn"
const REAL_PATH := "user://zombies.cfg"
## Tests and bots (Engine meta "sandbox") keep a file of their own.
const SANDBOX_PATH := "user://zombies_sandbox.cfg"
var PATH: String:
	get: return SANDBOX_PATH if Engine.get_meta("sandbox", false) else REAL_PATH

const START_POINTS := 500
## Alive at once; the rest of a round waits in reserve. The cap moves between these two with
## the frame time (npc/HordeBudget.gd, the spawner feeds it): `max_alive` is where it stands now.
const MAX_ALIVE_MIN := 24
const MAX_ALIVE_MAX := 48
## What a round's zombies come to before round 6, which the formula takes
## over from: 2.5 times the first design (15 in round 1).
const EARLY_ROUNDS := [15, 20, 32, 45, 60]
## Everything the horde and the surge may put on the block together.
const SURGE_HARD_CAP := 64
const HORDE_SCALE := 2.5
## Seconds between the warning and the quake.
const SURGE_WARNING := 2.5
## What things pay.
const POINTS_HIT := 10
const POINTS_KILL_BODY := 60
const POINTS_KILL_NECK := 70
const POINTS_KILL_HEAD := 100
const POINTS_KILL_MELEE := 130
const POINTS_BOARD := 10

## Ghetto Wars (npc/Gangster3D.gd): the same run, the same block, the same shell, but the enemy is a rival crew
## with guns. begin_gangs() sets it; leave() and begin() clear it. Everything the zombie mode shares keys off
## `active`; only the block, the spawner and the HUD look at this.
var gangs := false
## Ghetto Wars' story asks here before the run ends: true = it handles the end itself (world/GangBlock.gd).
var game_over_override := Callable()
## Options: "Mature language" swaps the crews' barks for clean ones.
var mature_language := true: set = set_mature_language
## Whether a zombie run is on (begin() .. leave()).
var active := false
var over := false
var round: int = 0
var points: int = START_POINTS
var kills := 0
var headshots := 0
## Seconds played this run.
var run_time := 0.0
## Power-up state (Double Points doubles what you earn, never a price).
var double_points := false
var insta_kill := false
## The surge: `surge_busy` from the warning to the last zombie of it coming out, `surge_active`
## (double points) from the quake to a few seconds after, `surge_count` how many it lets out.
var surge_busy := false
var surge_active := false
var surge_count := 0
## The tsunami's countdown is on (fx/Tsunami.gd), and what ended the run if it was not the dead ("" otherwise).
var tsunami_active := false
var death_cause := ""
## The alive cap now (HordeBudget moves it).
var max_alive := 32
## Options of the mode (the Zombies menu): gore on by default, floating damage numbers off.
var gore_enabled := true: set = set_gore_enabled
var damage_numbers := false: set = set_damage_numbers

var best_round := 0
var best_kills := 0
var best_headshots := 0
var best_time := 0.0
## Whether this run beat the saved best round (the screen says so).
var new_best := false

func _ready() -> void:
	load_best()

func _process(delta: float) -> void:
	if active and not over and not get_tree().paused:
		run_time += delta
		# Health comes back once nothing has clawed you for a while, as in COD.
		_since_hit += delta
		if _since_hit >= REGEN_DELAY and health < MAX_HEALTH:
			health = minf(MAX_HEALTH, health + REGEN_RATE * delta)
			health_changed.emit(health)

## The player's health (three claws and you are down; there is no revive yet).
const MAX_HEALTH := 100.0
const REGEN_DELAY := 3.0
const REGEN_RATE := 60.0
var health := MAX_HEALTH
var _since_hit := 0.0

## Armour plates (Ghetto Wars): each is PLATE_HP; they soak damage before health does, and do not regenerate.
const PLATE_HP := 50.0
const MAX_PLATES := 3
var armor := 0.0

func plates() -> int:
	return int(ceil(armor / PLATE_HP - 0.001))

## Puts a plate on. False when you wear all three.
func add_plate() -> bool:
	if plates() >= MAX_PLATES:
		return false
	armor = minf(armor + PLATE_HP, PLATE_HP * MAX_PLATES)
	armor_changed.emit(armor)
	return true

## A zombie's claw or a bullet landed on the player. `from` is where it came from (the red arc on the HUD).
func player_hit(dmg: float, from := Vector3.INF) -> void:
	if not active or over:
		return
	var soaked := 0.0
	if armor > 0.0:
		soaked = minf(armor, dmg)
		armor -= soaked
		dmg -= soaked
		armor_changed.emit(armor)
	health = maxf(0.0, health - dmg)
	_since_hit = 0.0
	health_changed.emit(health)
	player_damaged.emit(from, dmg + soaked, soaked > 0.0)
	if health <= 0.0:
		game_over()

# --- The run -------------------------------------------------------------------

## Sets a run up without changing scene (tests load the block themselves).
func begin(first_person: bool) -> void:
	gangs = false
	_begin(first_person)

## Ghetto Wars: the same, against the rival crew, in first person.
func begin_gangs() -> void:
	gangs = true
	_begin(true)

func _begin(first_person: bool) -> void:
	_reset()
	load_best()
	active = true
	GameState.mode = "zombies"
	ZombieControls.apply()
	Graphics.set_first_person(first_person)

## begin(), then the block.
func start(first_person: bool) -> void:
	begin(first_person)
	SceneLoader.go(CITY_SCENE)

## Ghetto Wars, straight in.
func start_gangs() -> void:
	begin_gangs()
	SceneLoader.go(CITY_SCENE)

## Another go, in the view and the mode you had.
func restart() -> void:
	if gangs:
		start_gangs()
	else:
		start(Graphics.first_person)

## Out of the mode, back to the story's footing. Quitting mid-run counts.
func leave() -> void:
	if active and not over:
		save_best()
	active = false
	over = false
	double_points = false
	insta_kill = false
	surge_busy = false
	surge_active = false
	surge_count = 0
	tsunami_active = false
	death_cause = ""
	health = MAX_HEALTH
	armor = 0.0
	gangs = false
	game_over_override = Callable()
	_since_hit = 0.0
	GameState.mode = "story"
	ZombieControls.restore()

func _reset() -> void:
	over = false
	game_over_override = Callable()
	new_best = false
	round = 0
	points = START_POINTS
	kills = 0
	headshots = 0
	run_time = 0.0
	double_points = false
	insta_kill = false
	surge_busy = false
	surge_active = false
	surge_count = 0
	tsunami_active = false
	death_cause = ""
	max_alive = 12 if gangs else 32
	health = MAX_HEALTH
	armor = 0.0
	_since_hit = 0.0

# --- Rounds --------------------------------------------------------------------

## Starts the next round (the first, from the block).
func start_round() -> void:
	if not active or over:
		return
	round += 1
	round_started.emit(round)

## The last zombie of the round is down: the round ends, the next begins.
func advance_round() -> void:
	if not active or over:
		return
	round_ended.emit(round)
	start_round()

## 150 at round 1, +100 a round to 950 at round 9, then x1.1 a round.
func zombie_health(r: int) -> int:
	r = maxi(r, 1)
	if r <= 9:
		return 150 + (r - 1) * 100
	return roundi(950.0 * pow(1.1, r - 9))

## How many come in round `r` (solo).
func zombies_in_round(r: int) -> int:
	r = maxi(r, 1)
	if r <= EARLY_ROUNDS.size():
		return EARLY_ROUNDS[r - 1]
	var mult := maxf(1.0, r / 5.0)
	if r >= 10:
		mult *= r * 0.15
	return roundi((24 + int(0.5 * 6.0 * mult)) * HORDE_SCALE)

# --- Ghetto Wars: the waves ---------------------------------------------------------

## Alive at once (they shoot, think and cost a lot more than the dead).
const GANG_MAX_ALIVE := 12
## A heavy with plates comes every this many waves.
const BOSS_EVERY := 5
const CREWS := ["Eastside Kings", "Dock Boys"]
## What the player's side is called, and who you hold the corner against.
const OWN_CREW := "Eastside Kings"

func is_boss_wave(r: int) -> bool:
	return r >= BOSS_EVERY and r % BOSS_EVERY == 0

## Who is against you in wave `r`: the Dock Boys, and from wave 6 the Dock Boys and a crew they brought in.
func enemy_crew(_r: int) -> String:
	return "Dock Boys"

## How many come in wave `r` (the boss counts as one).
func gangsters_in_wave(r: int) -> int:
	r = maxi(r, 1)
	return mini(5 + r * 2, 34) + (1 if is_boss_wave(r) else 0)

## A grunt's health in wave `r`: one headshot with anything kills it, a body takes a few.
func gang_health(r: int) -> int:
	return mini(100 + (maxi(r, 1) - 1) * 8, 190)

## What a plate carrier's vest soaks (from wave 4 some wear one).
func gang_vest(r: int) -> int:
	return 0 if r < 4 else mini(50 + (r - 4) * 10, 120)

## The gun a gangster wears in wave `r`: pistols first, then SMGs, rifles, shotguns.
func gang_gun(r: int, roll: float) -> String:
	if r <= 1:
		return "pistol"
	if r == 2:
		return "pistol" if roll < 0.6 else "smg"
	if r <= 4:
		return "smg" if roll < 0.55 else ("pistol" if roll < 0.8 else "ar")
	if r <= 6:
		return "ar" if roll < 0.45 else ("smg" if roll < 0.8 else "shotgun")
	return "ar" if roll < 0.45 else ("shotgun" if roll < 0.7 else "smg")

# --- Points --------------------------------------------------------------------

## Earnings, doubled under Double Points. Never negative: buying goes
## through try_spend().
func add_points(n: int, reason: String) -> void:
	if not active or n <= 0:
		return
	if double_points or surge_active:
		n *= 2
	points += n
	points_changed.emit(points, n, reason)

## Pays `cost` if you have it (exactly enough is enough); otherwise nothing
## happens. Prices don't change under any power-up.
func try_spend(cost: int) -> bool:
	if cost < 0 or cost > points:
		return false
	points -= cost
	if cost > 0:
		points_changed.emit(points, -cost, "spent")
	return true

## A zombie down, for the stats (the points come from add_points()).
func record_kill(headshot := false) -> void:
	kills += 1
	if headshot:
		headshots += 1

# --- The end -------------------------------------------------------------------

func summary() -> Dictionary:
	return {"round": round, "kills": kills, "headshots": headshots, "time": run_time,
		"best_round": best_round, "new_best": new_best, "cause": death_cause}

## The run is over: save the best and show the screen. Once per run.
func game_over() -> void:
	if not active or over:
		return
	# Ghetto Wars' story may take the end of the run (the bust, the ending cards) and call game_over() itself later.
	if game_over_override.is_valid() and bool(game_over_override.call()):
		return
	over = true
	new_best = round > best_round
	save_best()
	var s := summary()
	game_over_started.emit(s)
	var screen := preload("res://ui/ZombieGameOver.gd").new()
	screen.name = "ZombieGameOver"
	get_tree().root.add_child(screen)
	screen.show_summary(s)

func set_gore_enabled(on: bool) -> void:
	gore_enabled = on
	_save_options()

func set_damage_numbers(on: bool) -> void:
	damage_numbers = on
	_save_options()

func set_mature_language(on: bool) -> void:
	mature_language = on
	_save_options()

var _options_loaded := false

func _save_options() -> void:
	if not _options_loaded:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("options", "gore", gore_enabled)
	cfg.set_value("options", "damage_numbers", damage_numbers)
	cfg.set_value("options", "mature_language", mature_language)
	cfg.save(PATH)

## Dead Block and Ghetto Wars keep their bests apart.
func _best_section() -> String:
	return "best_gangs" if gangs else "best"

func load_best() -> void:
	best_round = 0
	best_kills = 0
	best_headshots = 0
	best_time = 0.0
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_options_loaded = true
		return
	gore_enabled = bool(cfg.get_value("options", "gore", true))
	damage_numbers = bool(cfg.get_value("options", "damage_numbers", false))
	mature_language = bool(cfg.get_value("options", "mature_language", true))
	_options_loaded = true
	var sec := _best_section()
	best_round = int(cfg.get_value(sec, "round", 0))
	best_kills = int(cfg.get_value(sec, "kills", 0))
	best_headshots = int(cfg.get_value(sec, "headshots", 0))
	best_time = float(cfg.get_value(sec, "time", 0.0))

## Writes the best of each stat, this run's against what's on file.
func save_best() -> void:
	best_round = maxi(best_round, round)
	best_kills = maxi(best_kills, kills)
	best_headshots = maxi(best_headshots, headshots)
	best_time = maxf(best_time, run_time)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var sec := _best_section()
	cfg.set_value(sec, "round", best_round)
	cfg.set_value(sec, "kills", best_kills)
	cfg.set_value(sec, "headshots", best_headshots)
	cfg.set_value(sec, "time", best_time)
	cfg.save(PATH)
