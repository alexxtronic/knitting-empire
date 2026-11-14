# rowan_tripo_eyes: build log

Real eyes for Rowan's in-game model, so the game can blink, turn the eyes and show moods (`data/characters.json`,
driven by `scripts/face.gd`). The model before real eyes is still `assets/rowan_tripo.glb` (`model_painted_eyes`).

Rebuilt on 2026-11-14 with the method the NPCs got on 2026-11-13 (Alex: "her eyes still look wonky, same with Rowan"):
a clean almond opening cut in the head, a plain sphere eyeball behind it, two thin lids on spheres round the same
centre. The first version (lids folded behind a ribbon of lashes) is in git history before that date.

## Config

- Source: `tools/character_build/rowan_tripo/rowan_tripo.blend` (not changed). His eyes sit 12.6 cm above the Head bone, so the tool has a `REGIONS` entry for him.
- Tool: `tools/add_eyes.py`, headless Blender 5.2, `EYES["rowan_tripo"]` (the outline measured by hand from `_front_map.png`, checked on `_overlay.png`).
- Review renders: `tools/add_eyes_review.py`, then `sheet.py` here.
- Output: `rowan_tripo_eyes.blend` (kept, the recovery point), `assets/rowan_tripo_eyes.glb`, `rowan_tripo_eyes_iris.png`, `rowan_tripo_eyes_skin.png`.
- No paid service, no downloaded asset: everything is made from the model's own mesh and albedo.

```bash
Blender -b tools/character_build/rowan_tripo/rowan_tripo.blend -P tools/add_eyes.py -- "$PWD" rowan_tripo
Blender -b tools/character_build/rowan_tripo_eyes/rowan_tripo_eyes.blend -P tools/add_eyes_review.py -- "$PWD/tools/character_build/rowan_tripo_eyes/review"
(cd tools/character_build/rowan_tripo_eyes && uv run --no-project --with pillow python sheet.py)
Blender -b --factory-startup -P tools/render_portraits.py -- "$PWD" rowan
```

## Numbers (2026-11-14 build)

- Old eyes painted out: 39,194 front pixels, the liner's soft fringe with them.
- Eyeballs 26.7 mm across, iris 12.4 mm, pupil 5.6 mm; lids 1.98 / 0.81 mm out, travel 39 / 22 degrees; rim 2.48 mm.
- Head: 30,000 -> 36,452 triangles. Cut edge 159 and 173 points, slid smooth to 0.3..0.9 mm past the rim.
- Stitch: 319 and 333 triangles, 2 and 6 lying face down from the front (tiny), wound like the head on every edge.
  The first build, stitched with Blender's bridge, had 169 folded under his left eye: dark notches under the lid.

## Looked at (review/sheet_eyes.png, review/sheet_face.png, the portraits)

Rest, half blink, closed, wink, looking left, right, up and down, happy, sleepy, angry, sad, three-quarter
and side. The notches under the lower lids are gone; at five times zoom a couple of faint pixel-sized marks are left
at the outer end of each lower lid. The eight portraits re-rendered from this model.
