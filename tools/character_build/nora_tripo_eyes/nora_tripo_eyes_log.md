# nora_tripo_eyes: build log

Experiment, 2026-11-12: real eyes for Nora's in-game model (`assets/nora_tripo.glb`), so the game can
blink and show emotion. Draft for Alex's review. Nothing in the game uses the result yet.

## Config

- Source: `tools/character_build/nora_tripo/nora_tripo.blend` (not changed).
- Tool: `tools/add_eyes.py`, headless Blender 5.2. Review renders: `tools/add_eyes_review.py`, then `sheet.py` here.
- Output: `nora_tripo_eyes.blend` (kept, the recovery point), `assets/nora_tripo_eyes.glb`, `nora_tripo_eyes_iris.png`.
- No paid service, no downloaded asset: everything is made from her own mesh and albedo.

```bash
Blender -b tools/character_build/nora_tripo/nora_tripo.blend -P tools/add_eyes.py -- "$PWD" nora_tripo
Blender -b tools/character_build/nora_tripo_eyes/nora_tripo_eyes.blend -P tools/add_eyes_review.py -- "$PWD/tools/character_build/nora_tripo_eyes/review"
(cd tools/character_build/nora_tripo_eyes && uv run --no-project --with pillow python sheet.py)
```

## Pipeline

1. **Front map.** Scene: `KnitProps`, `Nora` (armature, 22 bones, 8 actions), `nora_tripoMesh` (29,999 triangles, one 2048 albedo).
   Rays cast at the face from the front every 0.25 mm read the albedo: `_front_map.png`, registered to the mesh.
2. **Segmentation** (`_segments.png`): eye openings (green) 48.8 x 30.2 mm and 51.3 x 31.0 mm; upper lashes with a
   1.5 mm margin of skin (magenta). The outlines are convex hulls of the white/iris/pupil pixels, so the dark top of
   the iris does not notch them.
3. **Cut.** Triangles the outlines cross are refined three times, then the eye faces are deleted and the lash faces
   moved to the new mesh. Head: 29,999 -> 32,513 triangles. UVs and weights are kept.
4. **New mesh `NoraEyes`** (6,437 triangles, skinned to Head, LeftEye, RightEye):
   - eyeballs: caps of a 45 mm ball set 2.5 mm behind the painted eye, 16 mm bigger than the opening all round,
     kept 6 mm under the skin outside it; texture rebuilt from her painted iris (the half hidden under the lid is
     mirrored from the visible half) on a plain white, `nora_tripo_eyes_iris.png`;
   - lash line: the faces cut from the head, still on the painted albedo;
   - upper and lower lid skins: folded away behind the rim at rest, coloured from the skin just above and below the eye.
5. **Shape keys:** `blink_L`, `blink_R` (the lash line travels to the lower rim, the lid unfolds behind it),
   `lid_half`, `lid_angry` (more closed at the nose side), `lid_sad` (more closed at the outer side),
   `squint` (lower lids up). **Bones:** `LeftEye`, `RightEye`, children of `Head`, at the ball centres.
6. **Export:** GLB with morph targets; the 8 actions are unchanged.

## Looked at (review/sheet_eyes.png, review/sheet_face.png)

Rest, half blink, closed, wink, looking left/right 11 degrees and up/down 8 degrees, happy, sleepy, angry, sad;
front, three-quarter and side. Rendered flat-lit with the textures, two-sided like the game's materials.

- Rest matches the painted face; the eyes turn without showing gaps up to 11 degrees sideways and 8 degrees up or down.
- Closed: the lash line sits along the lower rim, the lids cover the opening.

## Known flaws

- The rim of the opening shows as a faint line when the lids are closed, and the lid skin is a flat colour.
- The lash line is ragged where it was cut (1 mm steps), most visible mid-blink; a few dark specks stay on the upper rim.
- The closed lash line runs up both sides of the opening, which reads as heavy eyeliner.
- The brows are still painted on, so emotions only move the lids.
- +8,951 triangles (head 2,514, eyes 6,437); the lash pieces are unwelded (10,012 vertices).

## Checks

- GLB read back: mesh `NoraEyes` has 6 morph targets with the names above; the skin has 24 joints, `LeftEye` and
  `RightEye` under `Head`; 8 animations; 2 images.
- Not done: loading it in Godot (another session's autotest was running), the `.import` file, any game code,
  the autotest.

## Checkpoint

Review with Alex. If he likes it: clean the lash cut, lid shading and brows; then a blink/emotion driver in
`scripts/body.gd` or `scripts/rig.gd`, a check in the autotest, and the same tool run on Rowan.
