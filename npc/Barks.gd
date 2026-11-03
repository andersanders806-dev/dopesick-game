extends RefCounted
## What the crews shout in Ghetto Wars: street talk, profane when "Mature language" is on (the default) and
## clean when it is off. Text on the HUD (ui/GangHud.gd), not voiced. The hard lines of the writing: no slurs of any
## kind, nothing about race, origin, sexuality or religion, no real gangs, places or people, nothing sexual; the
## insults are about the fight, the gun and the corner. Each line is [mature, clean].

const LINES := {
	"spot": [
		["There he is! Shoot that fucker!", "There he is! Get him!"],
		["Contact! He's on the corner!", "Contact! He's on the corner!"],
		["Got you, you prick!", "Got you now!"],
		["Eyes on him! Light him up!", "Eyes on him! Light him up!"],
	],
	"reload": [
		["Reloading! Cover me, fuck!", "Reloading! Cover me!"],
		["Reloading, shit!", "Reloading, darn it!"],
		["I'm dry! Cover!", "I'm dry! Cover!"],
	],
	"mock_reload": [
		["He's reloading! Push, push!", "He's reloading! Push, push!"],
		["Click, click, you're fucked now!", "Click, click, now you've had it!"],
		["Out of ammo, asshole? Go!", "Out of ammo? Go!"],
	],
	"flank": [
		["Going around, keep that fucker busy!", "Going around, keep him busy!"],
		["I'm on his left, cover me!", "I'm on his left, cover me!"],
		["You won't see me coming, dickhead!", "You won't see me coming!"],
		["Pinch him, I'm moving up!", "Pinch him, I'm moving up!"],
	],
	"lost": [
		["He's behind the car!", "He's behind the car!"],
		["Where did that prick go?", "Where did he go?"],
		["He's in the wall! Watch the corner!", "He's behind the wall! Watch the corner!"],
		["Shit, I lost him!", "Oh no, I lost him!"],
	],
	"hit": [
		["Aargh! Fuck!", "Aargh! Ow!"],
		["I'm hit, shit, I'm hit!", "I'm hit, I'm hit!"],
		["Motherfucker shot me!", "He shot me!"],
		["Fuck, my arm!", "Ow, my arm!"],
	],
	"retreat": [
		["Fuck this, I'm out!", "Forget this, I'm out!"],
		["Fall back, fall back! He's insane!", "Fall back, fall back! He's too good!"],
		["Not dying for this corner, shit!", "Not dying for this corner!"],
	],
	"throw": [
		["Frag out! Move your ass!", "Frag out! Move!"],
		["Burn, you bastard!", "Burn, you rat!"],
		["Molotov! Get him out of there!", "Molotov! Flush him out!"],
	],
	"ally_down": [
		["Man down! Motherfucker!", "Man down! Get him!"],
		["They got Nico! Kill him!", "They got Nico! Get him!"],
		["That's one of ours! Fuck him up!", "That's one of ours! Get him!"],
	],
	"taunt": [
		["This is Dock Boys' corner now!", "This is Dock Boys' corner now!"],
		["Your stash is ours, dealer!", "Your stash is ours, dealer!"],
		["You're already dead, you know that?", "You're already finished, you know that?"],
		["Come out and play, asshole!", "Come out and play!"],
		["Nobody's coming to save you!", "Nobody's coming to save you!"],
	],
	"begging": [
		["Please — don't — I'm bleeding out!", "Please — don't — I'm hurt!"],
		["Fuck, it hurts. Help me. Help me!", "It hurts. Help me. Help me!"],
		["I got a kid. Don't...", "I got a kid. Don't..."],
	],
	"boss": [
		["You think you can hold my corner?", "You think you can hold my corner?"],
		["I own this block! You're done!", "I own this block! You're done!"],
	],
	"player_down_ally": [
		["Eastside! Hold the line, shit!", "Eastside! Hold the line!"],
	],
}

## A line for `event`, [text, index] (index for tests); mature or clean by the option. Any given line only
## comes up again once every other has had its turn.
static var _last := {}

static func pick(event: String, rng: RandomNumberGenerator = null) -> String:
	var set_: Array = LINES.get(event, [])
	if set_.is_empty():
		return ""
	var i := 0
	if rng != null:
		i = rng.randi() % set_.size()
	else:
		i = randi() % set_.size()
	if set_.size() > 1 and _last.get(event, -1) == i:
		i = (i + 1) % set_.size()
	_last[event] = i
	var pair: Array = set_[i]
	return String(pair[0] if ZombieMode.mature_language else pair[1])

## Every line, for the tests (they check the clean set is clean and nothing on the banned list is anywhere).
static func all_lines(mature: bool) -> Array[String]:
	var out: Array[String] = []
	for ev in LINES:
		for pair in LINES[ev]:
			out.append(String(pair[0] if mature else pair[1]))
	return out

## Words the clean set may never contain (the test reads this).
const PROFANITY := ["fuck", "shit", "bastard", "asshole", "dickhead", "motherfucker", "prick", "ass", "damn"]
