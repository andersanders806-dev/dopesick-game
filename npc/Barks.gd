extends RefCounted
## What the crews shout in Ghetto Wars: street talk, profane when "Mature language" is on (the default) and
## clean when it is off. Spoken, not written: baked Piper takes (fx/GhettoVoice.gd), scared under the bravado. The hard lines of the writing: no slurs of any
## kind, nothing about race, origin, sexuality or religion, no real gangs, places or people, nothing sexual; the
## insults are about the fight, the gun and the corner. Each line is [mature, clean].

const LINES := {
	"spot": [
		["Oh shit, it's him! It's him! Shoot! Shoot him!", "Oh no, it's him! It's him! Shoot! Shoot him!"],
		["He's right there, man! Fuck! Somebody do something!", "He's right there, man! Somebody do something!"],
		["Contact! Oh God, he's on the corner!", "Contact! Oh God, he's on the corner!"],
		["I see him, I see him! Shit, he sees me!", "I see him, I see him! And he sees me!"],
	],
	"reload": [
		["Reloading! Cover me, please, fuck, cover me!", "Reloading! Cover me, please, cover me!"],
		["Come on, come on, go in! Shit, my hands!", "Come on, come on, go in! My hands are shaking!"],
		["I'm dry! I'm dry! Don't let him come!", "I'm dry! I'm dry! Don't let him come!"],
	],
	"mock_reload": [
		["He's reloading! Go, go, before he's done!", "He's reloading! Go, go, before he's done!"],
		["He's out! Now, now, while we can, fuck!", "He's out! Now, now, while we can!"],
		["Rush him! Don't give him time, please!", "Rush him! Don't give him time, please!"],
	],
	"flank": [
		["I'll go around... just keep him off me, man!", "I'll go around... just keep him off me, man!"],
		["I'm going left! Don't stop shooting, don't stop!", "I'm going left! Don't stop shooting, don't stop!"],
		["Why's it always me? Fuck. Fine. Moving up!", "Why's it always me? Fine. Moving up!"],
		["Cover me! If he turns, I'm dead! Cover me!", "Cover me! If he turns, I'm done! Cover me!"],
	],
	"lost": [
		["Where'd he go? Where the fuck did he go?", "Where'd he go? Where did he go?"],
		["I can't see him! I can't see him, man!", "I can't see him! I can't see him, man!"],
		["He's behind the car... I think. Oh God.", "He's behind the car... I think. Oh God."],
		["Shit, he's gone. He's coming round. I know it.", "Oh no, he's gone. He's coming round. I know it."],
	],
	"hit": [
		["Aargh! Fuck! I'm hit! I'm hit!", "Aargh! I'm hit! I'm hit!"],
		["Oh God, there's blood! There's so much blood!", "Oh God, there's blood! There's so much blood!"],
		["He shot me! He fucking shot me!", "He shot me! He really shot me!"],
		["My arm! I can't feel my arm!", "My arm! I can't feel my arm!"],
	],
	"retreat": [
		["Fuck this! I'm out! I'm out!", "Forget this! I'm out! I'm out!"],
		["Run! Run! He's killing everybody!", "Run! Run! He's taking everybody down!"],
		["I'm not dying here! Not for this shit!", "I'm not dying here! Not for this!"],
	],
	"throw": [
		["Take it! Take it! Just die already!", "Take it! Take it! Just go down already!"],
		["Fire, fire! Burn him out, please burn!", "Fire, fire! Burn him out, please burn!"],
		["Molotov! Get away from him, he's crazy!", "Molotov! Get away from him, he's crazy!"],
	],
	"ally_down": [
		["Man down! Oh fuck, man down!", "Man down! Oh no, man down!"],
		["They got Nico! They got Nico, oh God!", "They got Nico! They got Nico, oh God!"],
		["He's not moving. He's not moving, man!", "He's not moving. He's not moving, man!"],
	],
	"taunt": [
		["This is... this is Dock Boys' corner now!", "This is... this is Dock Boys' corner now!"],
		["Your stash is ours, dealer! Just... just give it up!", "Your stash is ours, dealer! Just... just give it up!"],
		["You hear me? You're dead! I swear you're dead!", "You hear me? You're finished! I swear you're finished!"],
		["Stay over there! Stay the fuck over there!", "Stay over there! Just stay over there!"],
		["Nobody's coming for you! Nobody... right?", "Nobody's coming for you! Nobody... right?"],
	],
	"begging": [
		["Please. Please, don't. I'm bleeding out!", "Please. Please, don't. I'm hurt bad!"],
		["Fuck, it hurts. Mom... Mom, help me!", "It hurts. Mom... Mom, help me!"],
		["I got a kid. Please. I got a kid...", "I got a kid. Please. I got a kid..."],
	],
	"boss": [
		["You think you scare me? You... you don't scare me!", "You think you scare me? You... you don't scare me!"],
		["Kill him! What am I paying you for? Kill him!", "Get him! What am I paying you for? Get him!"],
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
