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
| First-person gun sounds (assets/sfx/guns/*.wav): shots, reloads, brass, cloth, slide, hit ticks | Synthesized for this game by dev-tools/gen_gun_sfx.py and gen_gun_sfx_v2.py (shots, flesh, gore, impacts) from noise and sine sweeps; no recording or sample of any game or library | Ours | dev-tools/gen_gun_sfx.py |
| Zombie and finisher animation clips | Quaternius Universal Animation Library 1 and 2 (opengameart.org) | CC0 | assets/zombie_anims/LICENSE.md |
| Ghetto Wars animation clips (assets/gang_anims/gang_clips.res): pistol aim, idle, crouch, walk, jog, sprint, reload, throw, hits, death, retargeted onto the Rocketbox skeleton, plus "aim" composites (a gait's legs with the aim pose's arms) | Quaternius Universal Animation Library 1 and 2 (opengameart.org), via dev-tools/retarget_to_bip01.py (GANG=1) and build_gang_library.gd | CC0 | assets/gang_anims/LICENSE.md |
| Ghetto Wars sounds (bullet crack and whizz, grenade, glass, fire, helicopter, car pass in assets/sfx/guns/; the war's beat in assets/music/gangwar.wav) | Synthesized for this game by dev-tools/gen_gang_sfx.py from noise and sine sweeps; no sample, no borrowed melody | Ours | dev-tools/gen_gang_sfx.py |
| Kimodo-generated zombie/player clips (z_attack, z_attack2, z_attack3, z_crawl, z_scream, p_kick, z_walk3, z_hit_leg, z_death2), generated 2026-10-26 | NVIDIA Kimodo SOMA-RP v1.1 (github.com/nv-tlabs/kimodo) run through kimodo.cpp (github.com/localai-org/kimodo.cpp, Apache-2.0) | Weights: NVIDIA Open Model License (commercial use, outputs ours); code Apache-2.0; text encoder LocalAI-io/Llama-3-Kimodo-GGML (Meta Llama 3 Community License, built with Meta Llama 3, dev machine only, not shipped) | assets/zombie_anims/LICENSE.md |

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
