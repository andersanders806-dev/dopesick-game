#!/usr/bin/env python3
"""Paints the dialogue portraits (assets/portraits/) through AI Horde
(dev-tools/horde.py), in the same 35mm film-still look as the cutscenes:
head and shoulders, each person in their own place -- the bar, the street
corner, behind a pharmacy counter -- under that place's light, not cut out
onto a studio grey the way the old Pollinations + rembg pass did
(Pollinations now answers 402 Payment Required).

    python3 dev-tools/gen_portraits.py            # every portrait
    python3 dev-tools/gen_portraits.py pusher     # just some

Needs Pillow (.venv-portraits has it).
"""
import os
import sys

from horde import paint_all

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "portraits")
SIZE = 200

# Descriptions are grounded in real clinical/visible signs of long-term
# substance use (researched via addiction-medicine sources, not guessed):
# heroin/opioid use shows as gauntness, hollow cheeks, sunken dark-circled
# eyes, and a sallow/grayish skin tone; benzodiazepine use shows as
# droopy, "glazed" or unfocused eyes and a dull complexion rather than
# gauntness; long-term heavy drinking (the dive bar's barflies) shows as
# facial flushing and broken capillaries across the nose and cheeks.
# Kept humanizing, not a caricature -- these are headshots of tired
# people, not gore.
CHARACTERS = {
    "bartender": "a weathered middle-aged bartender with a short greying beard, rolled-up sleeves, tired but kind eyes, faint broken capillaries across his nose from years spent around drink",
    "wiry_guy": "a gaunt wiry man in his late 20s, hollow sunken cheeks, deep dark circles under bloodshot eyes, sallow grayish skin, stubble, restless nervous expression",
    "tired_woman": "an exhausted woman in her 40s, droopy heavy-lidded eyes with a glazed unfocused look, dark circles, dull sallow complexion, messy flat hair, slack tired expression",
    "big_eddie": "a big heavyset barfly in his 50s, broad flushed face with broken capillaries across his nose and cheeks, short cropped grey hair, puffy tired eyes",
    "quiet_kid": "a young quiet teenager in a worn hoodie, pale thin face just starting to hollow out, faint dark circles, downcast anxious eyes",
    "old_sailor": "an old grizzled sailor in his 60s, deeply weathered wrinkled skin, a red bulbous nose with broken veins, a white beard, watery bloodshot eyes, a knit cap",
    "nervous_dave": "a nervous balding man in his 40s, sweaty forehead, glazed heavy-lidded eyes struggling to focus, sallow complexion, wide anxious expression",
    # The pusher: street-level sellers blend in rather than looking like a
    # movie villain, and are often users themselves; what gives them away is
    # behaviour -- constantly checking the street -- not appearance.
    "pusher": "an ordinary-looking man in his 30s in a plain grey zip-up hoodie with the hood down and a faded t-shirt, tired skin with faint dark circles, stubble, eyes glancing sideways as if checking the street behind the camera, tense guarded expression, standing under harsh streetlight",
    "pharmacist": "a tired pharmacist in her 40s in a white lab coat with a name badge, glasses pushed up on her head, polite but wary expression, fluorescent-lit",
    "cashier": "a bored young supermarket cashier in his early 20s in a red store polo shirt with a name tag, slouched, indifferent half-lidded expression",
    "liquor_clerk": "a stern liquor store clerk in his 50s, heavy-set, grey stubble, flannel shirt, arms folded, suspicious narrowed eyes, standing behind scratched plexiglass",
    "security_guard": "a bulky retail security guard in his 30s in a black uniform shirt with a SECURITY patch, radio clipped to his shoulder, buzz cut, alert unimpressed stare",
    "jailer": "a weary middle-aged booking officer at a police station in a dark blue uniform, reading glasses, grey moustache, flat bored expression of someone who has seen it all",
    "shopkeeper": "a tired middle-aged convenience shop owner in a plain apron over a flannel shirt, alert watchful eyes, deep worry lines, arms crossed, wary guarded expression",
}

## Where each of them is when you talk to them.
PLACES = {
    "bartender": "behind a dive bar counter, bottles and red neon behind him",
    "pusher": "on a dark street corner under a sodium streetlight",
    "pharmacist": "behind a pharmacy counter under fluorescent light",
    "cashier": "at a supermarket checkout under fluorescent light",
    "liquor_clerk": "behind scratched plexiglass in a liquor store",
    "security_guard": "inside a store entrance under fluorescent light",
    "jailer": "at a police booking desk under fluorescent light",
    "shopkeeper": "behind a cluttered corner shop counter",
}
BAR = "in a dim dive bar, red neon and a jukebox glow behind"

STYLE = ("cinematic film still, 35mm photograph, head and shoulders portrait of {desc}, {place}, "
         "low-key moody lighting, muted desaturated colours with teal shadows, film grain, "
         "gritty 1990s American inner city, looking at the camera, no text")
NEGATIVE = "text, watermark, logo, cartoon, anime, illustration, 3d render, gore, blood, nudity, bright, overexposed"


def main() -> None:
    wanted = set(sys.argv[1:])
    jobs = []
    for i, (name, desc) in enumerate(CHARACTERS.items()):
        if wanted and name not in wanted:
            continue
        jobs.append((name, STYLE.format(desc=desc, place=PLACES.get(name, BAR)), 100 + i))

    def save(name, img):
        # Square, a little above centre so the face sits in the frame.
        w, h = img.size
        side = min(w, h)
        top = max(0, int((h - side) * 0.3))
        img.crop(((w - side) // 2, top, (w - side) // 2 + side, top + side)).resize((SIZE, SIZE)).save(
            os.path.join(OUT, name + ".png"), optimize=True)

    ok = paint_all(jobs, NEGATIVE, 768, 768, save)
    print(f"\n{ok}/{len(jobs)} portraits painted into {OUT}")


if __name__ == "__main__":
    main()
