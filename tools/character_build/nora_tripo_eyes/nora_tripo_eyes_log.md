# nora_tripo_eyes: build log

Real eyes for Nora's in-game model, so the game can blink, turn the eyes and show moods (`data/characters.json`,
driven by `scripts/face.gd`). The model before real eyes is still `assets/nora_tripo.glb` (`model_painted_eyes`).

Rebuilt on 2026-11-14 with the method the NPCs got on 2026-11-13 (Alex: "her eyes still look wonky, same with Rowan"):
a clean almond opening cut in the head, a plain sphere eyeball behind it, two thin lids on spheres round the same
centre. The first version (lids folded behind a ribbon of lashes) is in git history before that date.

## Config

- Source: `tools/character_build/nora_tripo/nora_tripo.blend` (not changed). Her eyes are in the default band above the Head bone.
- Tool: `tools/add_eyes.py`, headless Blender 5.2, `EYES["nora_tripo"]` (the outline measured by hand from `_front_map.png`, checked on `_overlay.png`).
- Review renders: `tools/add_eyes_review.py`, then `sheet.py` here.
- Output: `nora_tripo_eyes.blend` (kept, the recovery point), `assets/nora_tripo_eyes.glb`, `nora_tripo_eyes_iris.png`, `nora_tripo_eyes_skin.png`.
- No paid service, no downloaded asset: everything is made from the model's own mesh and albedo.

```bash
Blender -b tools/character_build/nora_tripo/nora_tripo.blend -P tools/add_eyes.py -- "$PWD" nora_tripo
Blender -b tools/character_build/nora_tripo_eyes/nora_tripo_eyes.blend -P tools/add_grip.py -- "$PWD" nora_tripo   # her fists and knitting hands, again
Blender -b tools/character_build/nora_tripo_eyes/nora_tripo_eyes.blend -P tools/add_eyes_review.py -- "$PWD/tools/character_build/nora_tripo_eyes/review"
(cd tools/character_build/nora_tripo_eyes && uv run --no-project --with pillow python sheet.py)
Blender -b --factory-startup -P tools/render_portraits.py -- "$PWD" nora
```

## Numbers (2026-11-14 build)

- Old eyes painted out: 59,781 front pixels, her liner with them (`reach=18`: it flicks 17 mm past the outline).
- Eyeballs 31.6 mm across, iris 15.1 mm, pupil 6.8 mm; lids 2.35 / 0.91 mm out, travel 40 / 22 degrees; rim 2.85 mm.
- Head: 29,999 -> 37,338 triangles. Cut edge 206 and 200 points, slid smooth to 0.3..1.1 mm past the rim.
- Stitch: 366 and 360 triangles, 1 and 0 lying face down from the front, wound like the head on every edge.
- One edge with three faces near the eyes was in the model before the cut (`check start`), and is left as it was.

## Looked at (review/sheet_eyes.png, review/sheet_face.png, the portraits)

Rest, half blink, closed, wink, looking left, right, up and down, happy, sleepy, angry, sad, three-quarter
and side. The blink closes cleanly over the whole eye; no dark marks under the lower lids. Her new lash line keeps a
small flick at each outer corner where the painted one was. The eight portraits re-rendered from this model.
