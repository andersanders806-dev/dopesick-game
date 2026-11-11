# Credits: assets/sfx/sick, and the guards' barks

Withdrawal's body noises and the dose sounds (`assets/sfx/sick/*.wav`) are cut by
`dev-tools/build_sick_sounds.py` (ffmpeg and numpy: cut, lowpass for the stifled ones,
pitch, fades, loudness) from the **BBC Sound Effects archive** (BBC Rewind,
https://sound-effects.bbcrewind.co.uk/), (c) BBC, under the **RemArc licence** (personal,
educational or research use; non-commercial). Dope Sick is a non-commercial project; credit line
for the title screen: "Sound effects (c) BBC, BBC Sound Effects archive, RemArc licence".
Source file for each ID: `https://sound-effects-media.bbcrewind.co.uk/wav/<ID>.wav`.

| Output file(s) | BBC source (and cut) | Description in the archive |
|---|---|---|
| `cough_1..4`, `cough_fit_1..2`, `cough_stifled_1..2` | [07071005](https://sound-effects.bbcrewind.co.uk/search?q=07071005) (single coughs at 0.3, 6.4, 9.1 and 25.4 s; runs of coughing at 11.7 and 28.4 s; the stifled ones are the same coughs lowpassed at ~900 Hz and pitched down) | One male coughing - 1980 (169B, reprocessed) |
| `sniff_1..2` | [07034127](https://sound-effects.bbcrewind.co.uk/search?q=07034127) (0.8 s and 13.6 s) | Man blowing nose |
| `breath_catch`, `stifle_strain`, `exhale_flat` | [07034133](https://sound-effects.bbcrewind.co.uk/search?q=07034133) (one breath at 28.9 s; the strain is the same lowpassed and slowed; the flat exhale is one at 31.8 s, lowpassed, slowed, long fade) | Heavy breathing, man breathing into woman breathing |
| `retch_1..2` | [07034131](https://sound-effects.bbcrewind.co.uk/search?q=07034131) (the belches at 11.0 s and 16.1 s) | Six belches |
| `drop_1..2` | [07002106](https://sound-effects.bbcrewind.co.uk/search?q=07002106) (the 2nd and 1st of the three drops) | A bucket dropped three times |

`dose_swell.wav` is the decaying chord at 34.8 s of `assets/music/shelter_piano.ogg` ("Emotional
Piano" by Centurion_of_war, CC0, see assets/music/CREDITS.txt), run backwards into itself so it blooms
and settles, lowpassed at 3.2 kHz.

The guards' barks ("Hm?", "Huh?", "Who's there?", "What was that?", `assets/voice/684_*.wav` for the
clerks and `720_*.wav` for security) are made like the rest of the game's speech: Piper
(https://github.com/rhasspy/piper, MIT) with the LibriTTS-R model, speakers 684 and 720, baked by
`dev-tools/bake_barks.py` under the names autoload/Voice.gd looks them up by.

The sounds are also mapped in autoload/SFX.gd (`SICK`); the existing `patron_sigh.wav` (BBC 07071004, see
world-real.md) is the warm sigh of a dose that felt good.
