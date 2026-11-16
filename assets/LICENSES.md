# Asset licences

Every third-party asset, its licence, and where the full text or credit
list sits. Credits shown in the game: ui/TitleScreen.gd (CREDITS).

| Assets | Source | Licence | Details |
|---|---|---|---|
| Kenney kits and sounds | kenney.nl | CC0 | assets/kenney/*/LICENSE.txt, assets/sfx/kenney*/LICENSE.txt |
| Poly Haven models and textures | polyhaven.com | CC0 | assets/polyhaven/LICENSE.txt, assets/pbr/LICENSE.txt |
| Gun models: Service Pistol and Bolt Action Rifle 7.62 | polyhaven.com | CC0 | assets/guns/LICENSE.md |
| Microsoft Rocketbox avatars | github.com/microsoft/Rocketbox | MIT | assets/rocketbox/LICENSE.md |
| Music | OpenGameArt | CC-BY / CC0 per track | assets/music/CREDITS.txt |
| Car models (12) | Sketchfab | CC BY 4.0 | assets/cars/LICENSE.md |
| Gun models: MPX SMG (nebula075), Mossberg500 Shotgun low-poly (AK), FPS Red Dot Sight (Michael Makivic), HK 416 Low Poly (Derek Flanagan), Low Poly Magnum Revolver (austincford), DP28 LMG Low-poly PBR (MaX3Dd) | Sketchfab | CC BY 4.0 | assets/guns/LICENSE.md, assets/guns/*/license.txt |
| First-person arms (assets/viewmodel/arms.glb): the forearms and hands cut from the Rocketbox Male_Adult_20 avatar by dev-tools/make_fp_arms.py | Microsoft Rocketbox | MIT | assets/rocketbox/LICENSE.md |
| Blood and impact decals (assets/decals/blood_*, impact_*): procedurally generated for Dope Sick, no third-party material | n/a | Ours | assets/decals/ |
| Zombie voices (assets/sfx/zombie/*.wav): groans, rasps, snarls, lunge roars, pain grunts | Synthesized for this game by dev-tools/gen_zombie_voice.py (a glottal pulse train, formant filters and noise); no recording, sample or speech model | Ours | dev-tools/gen_zombie_voice.py |
| Gun models, SHIP 16 B2: OWK 19 Pistol 9mm (OKacin Creative), Tec-9 (wallon), UZI (creationwasteland), HK MP5 (quick_loop), KRSV VECTOR (h1ggs), AK-47 Game Ready (Billy Jackman), low-poly M16A4 (notcplkerry), Sawed-Off Dirty / Double Barrel (HenRi), Desert Eagle (ELIZION), low-poly AA-12 and low-poly Barrett M82 A1 (D_U), M14 RIFLE (Ecler), M249 saw (yeetuseleetus), RPG 7 Free Model (javadbayat), Baseball bat (DVLT), Machete (Belonosoff) | Sketchfab | CC BY 4.0 | assets/guns/LICENSE.md, assets/guns/*/license.txt |
| Gun and melee sounds, SHIP 16 B2 (assets/sfx/guns/<glock, tec9, uzi, mp5, vector, ak, m16, sawnoff, deagle, aa12, dmr, amr, saw, rpg>/, the bat, machete, launcher and explosion files in assets/sfx/guns/common/) | The Free Firearm Sound Library (Still North Media, CC0); dklon -- Rocket Launch Pack (CC BY 3.0); Joth, NenadSimic -- explosions (CC0); will_leamon -- Fleshy Fight Sounds (OGA-BY 3.0); CGEffex -- Punch Slap n Kick (CC BY 3.0); artisticdude, Independent.nu, qubodup (CC0); layered and level-matched for this game | CC0 / CC BY / OGA-BY | assets/sfx/CREDITS/guns-recorded.md |
| First-person gun sounds, recorded (assets/sfx/guns/<pistol, magnum, smg, ar, shotgun, sniper, lmg>/ and assets/sfx/guns/common/): shots, far shots, room and street tails, action, dry fire, reload foley | The Free Firearm Sound Library (Still North Media: Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney), kurt, SpringySpringo, BMacZero, zer0_sol, LFA (all CC0); KuraiWolf (CC BY 4.0); Michel Baradari, Mike Koenig (CC BY 3.0); layered and level-matched for this game | CC0 / CC BY | assets/sfx/CREDITS/guns-recorded.md |
| First-person gun sounds (assets/sfx/guns/*.wav): the arc caster's shots, reloads, brass, cloth, slide, hit ticks | Synthesized for this game by dev-tools/gen_gun_sfx.py and gen_gun_sfx_v2.py (shots, flesh, gore, impacts) from noise and sine sweeps; no recording or sample of any game or library | Ours | dev-tools/gen_gun_sfx.py |
| Door sounds (assets/sfx/doors/: bell, chime, slams, rattles, hinge creaks, latch, panic bar, steel scrape, automatic sliding door), cut from the previews | Freesound (freesound.org) by ryuuzan, NachtmahrTV, TiesWijnen, contramundum, hisoul, klangfabrik, Profispiesser, oganesson, MarcusGraham325, Ryding, shelbyshark, rambler52, Rudmer_Rotteveel, Taykiraro, _stubb, magnuswaker, Krokulator | CC0 | assets/sfx/doors/CREDITS.txt, dev-tools/cut_door_sfx.py |
| Door glass textures (assets/doors/glass_*.png: street reflection by day and night, smudge film) and the aisle pictures seen through open doors (assets/doors/interior_*.png) | Generated for this game by dev-tools/gen_door_glass.py and gen_door_interiors.py (the out-of-focus glass_street_*_soft.png copies by gen_door_soft.py) from shapes and noise; no third-party material | Ours | dev-tools/gen_door_glass.py |
| Zombie and finisher animation clips | Quaternius Universal Animation Library 1 and 2 (opengameart.org) | CC0 | assets/zombie_anims/LICENSE.md |
| Kimodo-generated zombie/player clips (z_attack, z_attack2, z_attack3, z_crawl, z_scream, p_kick, z_walk3, z_hit_leg, z_death2; and z_rise, z_land, z_hit_leg_l, z_hit_arm_l/r, z_stumble, z_walk4, z_limp_l, z_walk_hurt_l/r, z_lunge, z_bite, z_smash), generated 2026-10-26 and 2026-11-02 | NVIDIA Kimodo SOMA-RP v1.1 (github.com/nv-tlabs/kimodo) run through kimodo.cpp (github.com/localai-org/kimodo.cpp, Apache-2.0) | Weights: NVIDIA Open Model License (commercial use, outputs ours); code Apache-2.0; text encoder LocalAI-io/Llama-3-Kimodo-GGML (Meta Llama 3 Community License, built with Meta Llama 3, dev machine only, not shipped) | assets/zombie_anims/LICENSE.md |
| Ghetto Wars animation clips (assets/gang_anims/gang_clips.res): pistol aim, idle, crouch, walk, jog, sprint, reload, throw, hits, death, retargeted onto the Rocketbox skeleton, plus "aim" composites (a gait's legs with the aim pose's arms) | Quaternius Universal Animation Library 1 and 2 (opengameart.org), via dev-tools/retarget_to_bip01.py (GANG=1) and build_gang_library.gd | CC0 | assets/gang_anims/LICENSE.md |
| Ghetto Wars sounds (bullet crack and whizz, grenade, glass, fire, helicopter, car pass in assets/sfx/guns/; the war's beat in assets/music/gangwar.wav) | Synthesized for this game by dev-tools/gen_gang_sfx.py from noise and sine sweeps; no sample, no borrowed melody | Ours | dev-tools/gen_gang_sfx.py |
| Ghetto Wars set textures (assets/ghetto/: crew tags, window cracks, glass, police tape) and sounds (assets/sfx/ghetto/) | Generated for this game by dev-tools/gen_ghetto_decals.py and gen_ghetto_sfx.py from shapes, noise and sine sweeps; the Kings' crown and the Dock Boys' anchor are our own marks. The police helicopter is built in code. No third-party material | Ours | dev-tools/gen_ghetto_decals.py |
| Parked-car props (assets/decals/car_shadow, car_ticket, car_forsale, car_pine; assets/sfx/hazard_relay_loop.wav): contact shadow, parking notice, FOR SALE card, air freshener and the hazard relay's tick, generated by dev-tools/gen_car_props.py from shapes, noise and sine bursts. The notice and the card carry no real authority, brand or phone number. No third-party material. No new car models were added: the models are those credited under the car section | n/a | Ours | dev-tools/gen_car_props.py |
| Ghetto Wars set pass 2 (assets/ghetto/: tag_krait/volt/oxblood/nova/hollow/zar, tape_crime_scene, burn_soot, blood_smear and their _n normals; assets/sfx/ghetto/: car_fire_loop, heli_pass, siren_wail_loop, siren_yelp_loop, flashbang_a, door_ram_a, glass_shatter_big, bullhorn_whoop/double, burning_block_loop, crowd_dogs_loop) | Synthesised with numpy/scipy (gw-assets/gen/*.py); the crew names KRAIT, VOLT, OXBLOOD, NOVA, HOLLOW and ZAR are invented; tape text in DejaVu Sans Bold (Bitstream Vera licence). No third-party samples | Ours | gw-assets/gen/ |
| Ghetto Wars fire and laundry (assets/ghetto/fire_flipbook_5x5.png, smoke_atlas_3x3.png, ember.png, laundry/*.obj) | Flame flipbook "Animated flame/fire sprite sheet" by Luca Pixel (https://opengameart.org/content/animated-flame-fire-sprite-sheet); smoke puffs and spark from Kenney's Particle Pack (kenney.nl, via https://opengameart.org/content/particle-pack-80-sprites), smoke sheet and spark re-packed; washer, dryer and washerDryerStacked from Kenney's Furniture Kit (https://opengameart.org/content/furniture-kit) | CC0 | OpenGameArt / kenney.nl |

## Car models (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/)

Modified for the game: decimated, turned to face +X and scaled to real size,
materials merged, wheels split, textures re-encoded. Downloaded 2026-10-21.

- "2001 Crown Victoria Taxi Game Prop" by 8sianDude (https://sketchfab.com/3d-models/2001-crown-victoria-taxi-game-prop-2429a825ff1646568e8e6e1453f9c501)
- "2001 Crown Victoria Police Interceptor Game Prop" by 8sianDude (https://sketchfab.com/3d-models/2001-crown-victoria-police-interceptor-game-prop-9f30d360cee343efb5a441978ddb57bd)
- "Shvan '92 - Low poly model" by Daniel Zhabotinsky (https://sketchfab.com/3d-models/shvan-92-low-poly-model-09d718c9cf72401b8534d265a06a803f)
- "Generic passenger car pack" by Comrade1280 (https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5): the sedan, hatchback, wagon, minivan and SUV
- "Abandoned Generic Sedan 2 - Game Ready" by Rashad Ibrahimli (https://sketchfab.com/3d-models/abandoned-generic-sedan-2-game-ready-db2df46c49f9441286c84c66208ef7ac)
- "Crashed Abandoned Car - Game Ready" by Rashad Ibrahimli (https://sketchfab.com/3d-models/crashed-abandoned-car-game-ready-66ef51a84c9843dda53bf0b4b9020011)
- "Burned-out Cars" by Renafox (https://sketchfab.com/3d-models/burned-out-cars-701066df6b914fd08318524c7ccd96a7): both burnt-out wrecks

## Gun models (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/)

Fetched by dev-tools/fetch_guns.py on 2026-10-27; textures scaled to 1024 px max, nothing else changed. The pistol and the sniper rifle are Poly Haven (CC0); the wonder weapon is built in code.

- "MPX SMG" by nebula075 (https://sketchfab.com/3d-models/mpx-smg-238fa4b18f1247e99231529f98d11a61): the submachine gun
- "Mossberg500 Shotgun low-poly" by AK (https://sketchfab.com/3d-models/mossberg500-shotgun-low-poly-5ae38a34bfed4c91a3dbe78aaea51790): the shotgun
- "FPS Red Dot Sight (Game Model)" by Michael Makivic (https://sketchfab.com/3d-models/fps-red-dot-sight-game-model-0cf999d9363940c2b149dcd80c448554): the red dot on the rifle and the SMG
- "HK 416 Assault Rifle - Low Poly" by Derek Flanagan (https://sketchfab.com/3d-models/hk-416-assault-rifle-low-poly-fbdf159836224d67b193ca527d4f4333): the assault rifle
- "Low Poly Magnum Revolver" by austincford (https://sketchfab.com/3d-models/low-poly-magnum-revolver-9191c62d1cec4087809102dcc81493bb): the magnum
- "DP28 Light Machine Gun Low-poly PBR" by MaX3Dd (https://sketchfab.com/3d-models/dp28-light-machine-gun-low-poly-pbr-03978b66f0c646f19e9502634f0ad20a): the LMG
- assets/sfx/ghetto/gw/*.wav and assets/sfx/ghetto/amb/*.ogg: Ghetto Wars raid sounds (door ram, bullhorn, flashbang, helicopter pass, siren) and the night-street and burning-block beds, synthesised for this project (CC0), see the generator scripts in gw-assets/gen

## Gun models, SHIP 16 B2 (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/)

Staged by the arsenal pass (SHIP 16a) on 2026-11-16; textures at 1024 px max, nothing else changed in the files. The full list with links and the
gun each one is: assets/guns/LICENSE.md.

- "OWK 19 Pistol 9mm (G19)" by OKacin Creative (https://sketchfab.com/3d-models/owk-19-pistol-9mm-g19-3a773b0f46f246dc855742ef413bf4a6)
- "Tec-9" by wallon (https://sketchfab.com/3d-models/tec-9-fed8b9bad25242b8ba7c81d675ff050f)
- "UZI" by creationwasteland (https://sketchfab.com/3d-models/uzi-fde60adc8aff4c61b6a8bea1f9e0743f)
- "HK MP5 (9mm submachine gun)" by quick_loop (https://sketchfab.com/3d-models/hk-mp5-9mm-submachine-gun-c503d96157614fb78b5953d49e643b78)
- "KRSV VECTOR" by h1ggs (https://sketchfab.com/3d-models/krsv-vector-609166faf8e5416f957c88e0af657e09)
- "AK-47 - Game Ready Assault Rifle Weapon" by Billy Jackman (https://sketchfab.com/3d-models/ak-47-game-ready-assault-rifle-weapon-dc58144409534abbb60970638d171f9f)
- "low-poly M16A4 [remade from scratch]" by notcplkerry (https://sketchfab.com/3d-models/low-poly-m16a4-remade-from-scratch-ccfef9f2093c46ba95e71d4a0f417c74)
- "Sawed-Off Dirty / Double Barrel" by HenRi (https://sketchfab.com/3d-models/sawed-off-dirty-double-barrel-907aa49d5ae94bfc952d37f686f26ad1)
- "Desert Eagle" by ELIZION (https://sketchfab.com/3d-models/desert-eagle-cabde59f5cf24effaf80536e35d04e95)
- "low-poly AA-12" by D_U (https://sketchfab.com/3d-models/low-poly-aa-12-6b26f9d65d8c4838a12918d8e232510a)
- "M14 RIFLE" by Ecler (https://sketchfab.com/3d-models/m14-rifle-94920332fc7a4d63939b88a8a54baead)
- "low-poly Barrett M82 A1" by D_U (https://sketchfab.com/3d-models/low-poly-barrett-m82-a1-bb0831f237494699b6651da9177d36e4)
- "M249 saw" by yeetuseleetus (https://sketchfab.com/3d-models/m249-saw-e43c7b0b261c4e31bb753791794a9bf9)
- "RPG 7 ( Free Model )" by javadbayat (https://sketchfab.com/3d-models/rpg-7-free-model-99c0af8a1803490a86edc48cd3bfc700)
- "Baseball bat" by DVLT (https://sketchfab.com/3d-models/baseball-bat-2669cf86386747449611396c0409db47)
- "Machete" by Belonosoff (https://sketchfab.com/3d-models/machete-340a3bed238f48b0aa169c38e1e75066)
