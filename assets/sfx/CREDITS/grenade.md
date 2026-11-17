# Credits: SHIP 16G, the Mk 2 frag grenade and the shared explosion

Dope Sick is a non-commercial project. Everything below was fetched 2026-11-17; the raw downloads are not redistributed, only the edited game
assets (48 kHz mono 16 bit WAVs cut, faded and level-matched with ffmpeg + numpy).

## Model (assets/models/grenade/mk2_grenade.glb, unchanged copy)
| Author | Licence | URL |
|---|---|---|
| LonesomeDucky -- "Mk2 Grenade" (pin, ring and spoon separate nodes, 2568 tris) | CC0 | https://opengameart.org/content/mk2-grenade |

## Explosion picture (assets/fx/explosion/)
| File | Author | Licence | URL |
|---|---|---|---|
| explosion_a_5x5.png (Explosion01), explosion_b_5x5.png (Explosion02), smoke_wispy_8x8.png (WispySmoke02), dust_cloud_8x8.png (Cloud01): flipbooks, TGA sheets read as image data | Unity Labs Paris (Houdini sims, published by Thomas Iche) | CC0 | https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks |
| scorch_albedo_1/2.png, scorch_normal_1/2.png, sparks_4x1.png, grit_4x2.png | generated for Dope Sick (numpy) | ours, CC0 | n/a |
| explosion_flipbook.gdshader | written for Dope Sick | ours | n/a |

## The blast itself (assets/sfx/grenade/real_A_taet.wav close, real_C_fjern.wav far): the user's pick, real hand-grenade recordings
| File | Source | Author | Licence |
|---|---|---|---|
| real_A_taet | https://archive.org/details/SSE_Library_EXPLOSIONS , REAL/EXPLReal_Grenade explodes_CHS_USC.flac (0-4.8 s) | USC Cinema / Sunset Editorial Collection (USC Sound Effect Archive) | CC0 |
| real_C_fjern | https://archive.org/details/GOLD_TAPE_33_Explosions_and_War , G33-03-Grenades Exploding.flac (one blast, 4.65-7.2 s) | USC Cinema / Sunset Editorial Collection | CC0 |

## Foley
| Output | Source | Author | Licence |
|---|---|---|---|
| pin_pull | "Grenade pin pull" https://freesound.org/people/CGEffex/sounds/93837/ | **CGEffex** | **CC BY 4.0** (attribution required) |
| bounce_concrete_1 | "Tossing grenade onto cement" https://freesound.org/people/CGEffex/sounds/93839/ | **CGEffex** | **CC BY 4.0** (attribution required) |
| bounce_concrete_2 | Mechanical Wave, Rock Brick and Dirt: Drop Rock On Rock Debris_RBD 03 | Mechanical Wave | Sonniss GDC (royalty-free) |
| bounce_concrete_3 | The Sound Pack Tree, Dropping Things: Drop Smartphone On Concrete 02 (pitched down) | The Sound Pack Tree | Sonniss GDC |
| bounce_metal_1..3 | Mechanical Wave, Undoing-Computer: Hit Impact Hard Metal Scrap Debris_UC 01 / Hit Impact Metal Scrap Debris_UC 06 / Drop Fall Metal Rattle Scrap Debris_UC 10 | Mechanical Wave | Sonniss GDC |
| bounce_wood_1, 2 | Double Trouble Audio, Wood Impacts and Debris: Drop Soft - Single Plank, Drop 02 / Impacts Hard - Short Wobbly Tail 01 | Double Trouble Audio | Sonniss GDC |
| bounce_wood_3 | Gamemaster Audio, Silenced Gun Sounds: bullet_shell_bounce_wood2_05 (pitched down) | Gamemaster Audio | Sonniss GDC |
| roll_concrete | Sound Ex Machina, Rolling Objects: Metallic ball rolling on concrete 02 | Sound Ex Machina | Sonniss GDC |
| spoon_ping_1 | Eiravaein Sound, Latchlocker: steel lever small close release squeak snap ring | Eiravaein Sound | Sonniss GDC |
| spoon_ping_3 | Sound Spark LLC, Metal Hits, Scrapes and Squeaks: Metal_Barrel_Bolt_Lock_Loose_Handling_03 | Sound Spark LLC | Sonniss GDC |
| throw_whoosh_1..3 | Mechanical Wave, Hits Whoosh: Fast Action Swish_HW 05 / Justsoundeffects, Transition Whooshes Vol. 1: WHSH_Whoosh Short 06 / Soundrangers, Whooshes And Transitions: texture_whoosh_02_fast_02 | Mechanical Wave, Justsoundeffects, Soundrangers | Sonniss GDC |
| debris_1 | Bluezone, Tank Explosion Sound Effects: debris_falling_rock_dust_002 | Bluezone Corporation | Sonniss GDC |
| debris_2 | BluezoneCorp, Building Collapse: debris_falling_rock_rubble_008 | Bluezone Corporation | Sonniss GDC |
| debris_3 | Tatak Audio, Rocks and Debris: Falling Heavy Dusty Debris | Tatak Audio | Sonniss GDC |
| slapback_street | Gamemaster Audio, Guns, Bullets and Explosions: explosion_large_07 (filtered, three baked echoes; used only as the street's echo, never as the boom) | Gamemaster Audio | Sonniss GDC |
| ear_ring, spoon_ping_2 | synthesised for Dope Sick (numpy sines and sweeps) | ours | CC0 |

Sonniss licence: royalty-free for commercial and non-commercial use in a game, no attribution required (credited anyway). Full source URLs per file:
the staging note CREDITS.md of SHIP 16G (/home/anders/dopesick-grenade-staging/CREDITS.md, appendix).
