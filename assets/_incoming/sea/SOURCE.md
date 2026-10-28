# Sea: tileable water normal maps (3 scales) + foam, procedurally generated

- URL: n/a (generated locally, script `gen_sea.py` in this folder; deterministic seeds)
- Author: generated for this project (numpy + Pillow); no third-party content
- Licence: CC0 1.0 / public domain (own work, no source material)
- Date: 2026-10-28
- Why generated: Poly Haven and ambientCG have no water normal maps; the free web sources found were AI-generated or under custom licences (AITextured FCL) or had unclear terms. A band-limited periodic spectral height field is seamless by construction (FFT wraps) and gives full control of scale.
- Files (1024x1024 PNG, tangent-space, OpenGL / +Y up normals, same convention Godot expects):
  - water_normal_swell_1k.png: long low swell; map so 1 tile ~ 64 m
  - water_normal_chop_1k.png: mid chop; 1 tile ~ 8 m
  - water_normal_ripple_1k.png: fine ripples, different direction; 1 tile ~ 3 m (scroll against the chop)
  - foam_1k.png: single-channel (L) lacy foam mask, tileable; use as albedo/alpha mix at the seawall and pile edges
- Godot import: normal maps -> Normal Map = Enabled (or Detect), Mipmaps on, repeat on; foam -> Lossless/VRAM, repeat on.
- Quality note: swell reads convincingly; chop/ripple are a little "grainy-isotropic" up close. Blending two scales scrolled in opposite directions hides it. If a real photographic/FFT-sim set is wanted later, the Godot "ocean waves" addon sims (MIT) generate better ones at runtime but cost GPU.
