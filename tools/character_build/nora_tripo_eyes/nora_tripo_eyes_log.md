# nora_tripo_eyes: build log

Real eyes for Nora's in-game model, so the game can blink, turn the eyes and show moods. Used by the game
since 2026-11-12 (`data/characters.json`, driven by `scripts/face.gd`). The model before this is still
`assets/nora_tripo.glb` (`model_painted_eyes`).

## Config

- Source: `tools/character_build/nora_tripo/nora_tripo.blend` (not changed). Her eyes are in the default band above the Head bone.
- Tool: `tools/add_eyes.py`, headless Blender 5.2. Review renders: `tools/add_eyes_review.py`, then `sheet.py` here.
- Output: `nora_tripo_eyes.blend` (kept, the recovery point), `assets/nora_tripo_eyes.glb`, `nora_tripo_eyes_iris.png`.
- No paid service, no downloaded asset: everything is made from the model's own mesh and albedo.

```bash
Blender -b tools/character_build/nora_tripo/nora_tripo.blend -P tools/add_eyes.py -- "$PWD" nora_tripo
Blender -b tools/character_build/nora_tripo_eyes/nora_tripo_eyes.blend -P tools/add_eyes_review.py -- "$PWD/tools/character_build/nora_tripo_eyes/review"
(cd tools/character_build/nora_tripo_eyes && uv run --no-project --with pillow python sheet.py)
```

## Pipeline

1. **Front map.** Rays cast at the face from the front every 0.25 mm read the albedo: `_front_map.png`, registered to the mesh.
2. **Segmentation** (`_segments.png`): eye openings (green) 48.8 x 30.8 mm and 51.3 x 31.3 mm; upper lashes (magenta). The opening outlines are
   convex hulls of the white, iris and pupil pixels.
3. **Old eyes painted out.** Skin is grown in from round the eyes and lashes and written back into the albedo
   (`_front_map_clean.png`), so nothing painted shows round the new parts.
4. **Cut.** The triangles the opening outlines cross are refined three times, then the eye faces are deleted.
   Head: 29,999 -> 30,889 triangles. UVs and weights are kept.
5. **New mesh** (4,844 triangles, skinned to Head, LeftEye, RightEye):
   - eyeballs: caps of a 45 mm ball 2.5 mm behind the old painted eye, kept under the skin through the whole look
     range (12 degrees sideways, 8 up or down); texture rebuilt from the painted iris on a plain white;
   - lash line: a ribbon in the painted lashes' colour, 58 and 51 mm long, up to 11 mm thick, along the top of the opening;
   - upper and lower lid skins, folded away behind the rim at rest, coloured from the cleaned skin round the opening.
6. **Shape keys:** `blink_L`, `blink_R` (the lash line travels to the lower rim, the lid unfolds behind it),
   `lid_half`, `lid_angry`, `lid_sad`, `squint` (lower lids up). **Bones:** `LeftEye`, `RightEye` under `Head`.
7. **Export:** GLB with morph targets; the animation loops are unchanged.

## Looked at (review/sheet_eyes.png, review/sheet_face.png)

Rest, half blink, closed, wink, looking left/right 11 degrees and up/down 8 degrees, happy, sleepy, angry, sad;
front, three-quarter and side, flat-lit with the textures, two-sided like the game's materials.

## Known flaws

- The lids are a smooth skin colour: the painted shading that was round the eyes is gone inside the cleaned area,
  so closed eyes read a little pale and flat.
- The lash line is a plain ribbon; the painted lash strokes are not reproduced.
- The brows are still painted on, so moods only move the lids.

## Checkpoint

In the game: `--only=face` autotest check (blink, moods, asleep, gaze) and the full autotest. Next: brows, and
the same tool on each new character.
