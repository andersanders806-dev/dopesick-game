# CREDITS - the guns' recorded sounds (SHIP 16 phase B1)

Non-commercial project. Every source is CC0 or CC BY (nothing NC, nothing with an EU territory exclusion).
Staged and layered by the arsenal pass (SHIP 16a): the shot sets are our derivative work (slices of the real
takes, with pitch, filter, layering, level matching) of the recordings below.

## Where it sits
- assets/sfx/guns/<gun>/ for pistol, magnum, smg, ar, shotgun, sniper, lmg: fire_1..3, fire_up_1..3 (the upgraded gun's ringing take),
  distant_1..2 (heard far away: gangsters and NPC fire in Ghetto Wars, the far-off shots), tail_outdoor and tail_indoor (the street's and a room's
  answer), mech_1..2 (the action's click), dry.
- assets/sfx/guns/common/: reload and handling foley (magazines, slide, charging handle, bolt, pump, shells, LMG cover, break open/close).

## Shots
| pack | author | licence | URL |
|---|---|---|---|
| The Free Firearm Sound Library | Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (Still North Media) | CC0 | https://opengameart.org/content/the-free-firearm-sound-library |
| Light Machine Gun | KuraiWolf | CC BY 4.0 | https://opengameart.org/content/light-machine-gun |
| Gunshots | kurt | CC0 | https://opengameart.org/content/gunshots |

## Foley
| pack | author | licence | URL |
|---|---|---|---|
| Gun Reload Sounds | SpringySpringo | CC0 | https://opengameart.org/content/gun-reload-sounds |
| Gun Reload Sound Effects | BMacZero (Brian MacIntosh) | CC0 | https://opengameart.org/content/gun-reload-sound-effects |
| Handgun Reload Sound Effect | zer0_sol | CC0 | https://opengameart.org/content/handgun-reload-sound-effect |
| Shotgun Reload Sound Effects | zer0_sol | CC0 | https://opengameart.org/content/shotgun-reload-sound-effects |
| Equipment Clicks II and III | LFA | CC0 | https://opengameart.org/content/equipment-clicks-ii , https://opengameart.org/content/equipment-clicks-iii |
| 2 Metal Weapon Clicks | Michel Baradari | CC BY 3.0 | https://opengameart.org/content/2-metal-weapon-clicks |
| Shotgun Shoot / Reload | Mike Koenig (SoundBible) | CC BY 3.0 | https://opengameart.org/content/shotgun-shoot-reload |

## Still synthesised (nothing real fits)
The arc caster (wonder weapon) keeps its synthesised shots, fire_wonder_a/b.wav (dev-tools/gen_gun_sfx.py). Also synthesised, not replaced: the knife's
whoosh, dry click, draw, ADS cloth, inspect, slide, brass drops, hit ticks, impacts and gore (see weapons-real.md and LICENSES.md), and the
magazine/rack/pump/bolt/shell cues of the arc caster.

## SHIP 16 B2: the sixteen new guns and the melee weapons
- assets/sfx/guns/<glock, tec9, uzi, mp5, vector, ak, m16, sawnoff, deagle, aa12, dmr, amr, saw>/: the same 13-file layout, sliced and layered from
  The Free Firearm Sound Library (Still North Media, CC0) by the arsenal pass (SHIP 16a, staging sfx/<gun>/), copied unchanged.
- assets/sfx/guns/rpg/: the launcher's set in the same layout, built for this game from the launcher and explosion recordings below
  (common/rpg_fire, rocket_flight, rpg_explode, rpg_dry and their sources).
- assets/sfx/guns/common/: the launcher (rpg_fire, rocket_flight, rocket_load, rpg_dry, rpg_explode), the melee weapons (bat_swing_1..2,
  machete_swing_1..2, swing_light_1..3, swing_heavy_1..3, bat_hit_1..3, bat_hit_wall, machete_hit_1..4, machete_hit_wall, melee_kill_1..3) and
  more magazine and charging foley (mag_out_b, mag_in_b, charge_b, shell_chamber).

| pack | author | licence | URL |
|---|---|---|---|
| Rocket Launch Pack | dklon | CC BY 3.0 | https://opengameart.org/content/rocket-launch-pack |
| Chunky Explosion | Joth | CC0 | https://opengameart.org/content/chunky-explosion |
| Muffled Distant Explosion | NenadSimic | CC0 | https://opengameart.org/content/muffled-distant-explosion |
| Fleshy Fight Sounds | will_leamon | OGA-BY 3.0 | https://opengameart.org/content/fleshy-fight-sounds |
| Punch Slap n Kick | CGEffex | CC BY 3.0 | https://opengameart.org/content/punch-slap-n-kick |
| Swishes Sound Pack | artisticdude | CC0 | https://opengameart.org/content/swishes-sound-pack |
| 37 Hits/Punches | Independent.nu | CC0 | https://opengameart.org/content/37-hitspunches |
| Metal Interactions | qubodup | CC0 | https://opengameart.org/content/metal-interactions |

The rocket's blast also plays the Ghetto Wars grenade's synthesised boom (assets/sfx/guns/grenade_boom.wav, dev-tools/gen_gang_sfx.py, ours).

### Where each B2 common file comes from (recipe: the arsenal pass's build_foley.py in the staging folder; raw packs are in the table above)
| files | made from |
|---|---|
| mag_out_b, mag_in_b, charge_b | Shotgun Shoot / Reload (Mike Koenig, CC BY 3.0): Ejecting Magazine, Pop Clip In, Chambering A Round |
| shell_chamber, shell_insert_1..2, pump_2 | Shotgun Reload Sound Effects (zer0_sol, CC0): Shell in Chamber, First Shell, Subsequent Shells, Rack |
| shell_insert_3, clip_tick | Shotgun Reload Sound Effects (zer0_sol, CC0): singlebullet1, clipload2 |
| break_open, break_close, lmg_cover_open, lmg_cover_close, rocket_load | Metal Interactions (qubodup, CC0): metal_interaction1/2, metal_swing1, metal_button_press1 (rocket_load slowed to 0.8) |
| swing_light_1..3, swing_heavy_1..3, bat_swing_1..2, machete_swing_1..2 | Swishes Sound Pack (artisticdude, CC0): swish-2, -3, -7, -9, -12, -13, pitched and filtered per weapon |
| bat_hit_1..3 | Fleshy Fight Sounds (will_leamon, OGA-BY 3.0): hammer-1a, hammer-1b, hammer-arm-2a, with a low Metal Interactions thump under them |
| machete_hit_1..4 | Fleshy Fight Sounds (will_leamon, OGA-BY 3.0): sword-1a, sword-1b, sword-arm-2a, piercing-1a |
| bat_hit_wall, machete_hit_wall | Metal Interactions (qubodup, CC0): metal_interaction2 (lowered) and metal_interaction1 |
| melee_kill_1..3 | 37 Hits/Punches (Independent.nu, CC0): hits 05, 08, 11, slowed to 0.8 |
| rpg_fire | Rocket Launch Pack (dklon, CC BY 3.0) rocket_launch_1, with the low end of Muffled Distant Explosion (NenadSimic, CC0) and 2 Metal Weapon Clicks weapload (Michel Baradari, CC BY 3.0) |
| rocket_flight | Rocket Launch Pack (dklon, CC BY 3.0) rocket_launch_3, 0.6 s to 3.1 s |
| rpg_explode | Chunky Explosion (Joth, CC0) with Muffled Distant Explosion (NenadSimic, CC0), low-passed |
| rpg_dry | the synthesised dry click (dev-tools/gen_gun_sfx.py, ours), slowed to 0.7 |
| rpg/ shot set | fire_1 is rpg_fire (same length and peak), fire_2..3 and fire_up_1..3 are its speed and tail variants, distant_*, tail_* and mech_* are cut from rpg_explode, rocket_flight and rocket_load; dry.wav is rpg_dry. Built by the first B2 agent from those files; no other source. |
