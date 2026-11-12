# wren_tripo_eyes: build log

Wren, the mayor (2026-11-12). Alex made her on tripo.ai with the Clean Topology option and asked for her to be
rigged like Nora and Rowan, with real eyes. `assets/wren_tripo_eyes.glb` is what the game loads
(`data/characters.json`, id `wren`; the `mayor` villager's `look.model`). `assets/wren_tripo.glb` is the
rigged body with the painted eyes (`model_painted_eyes`).

## Commands

The source export is `tripo_convert_4319bf8d-….glb` in Alex's Downloads (1.6 MB, not in the repo). She uses
Nora's rig (the female skeleton, 22 bones).

```bash
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b tools/character_build/nora/nora.blend -P tools/rig_sculpt.py -- "$PWD" <export>.glb wren_tripo --faces 30000 --tex 2048 --coat 0.16
$B -b tools/character_build/wren_tripo/wren_tripo.blend -P tools/retarget_anims.py -- "$PWD" "<pack>/Unreal-Godot/UAL1_Standard.glb" wren_tripo
$B -b tools/character_build/wren_tripo/wren_tripo.blend -P tools/add_eyes.py -- "$PWD" wren_tripo --region -0.085 0.085 1.50 1.548 --lash-reach 4
$B -b tools/character_build/wren_tripo_eyes/wren_tripo_eyes.blend -P tools/add_eyes_review.py -- "$PWD/tools/character_build/wren_tripo_eyes/review"
(cd tools/character_build/wren_tripo_eyes && python3 sheet.py)
```

Loop stride speeds (`data/characters.json`): Walk 1.01, Brisk 1.18, Run 3.04 m/s.

## What her model needed that Nora's and Rowan's did not

- **Binding.** Clean Topology gives a mesh in 34 loose shells (10,210 triangles). Blender's bone heat failed on
  every vertex, so `rig_sculpt.py` now falls back to nearest-bone weights when heat leaves skin bare or a limb
  unbound (left bones only on the left, the three strongest kept, smoothed along the mesh), before the usual
  arm/body split and rigid head.
- **Centring.** The mayor's crest on her chest is dense geometry and pulled the old median-based centre 8 cm to
  her right, which put her right leg nearer the left thigh bone. The torso slice is now centred on its outline.
- **The blazer.** Its hem hangs 16 cm below the hip joint; with plain nearest-bone weights it followed the thighs
  and crumpled. `--coat 0.16` fades the thighs' pull out over that band and gives it to the Hips.
- **Eyes.** A lock of hair touches her right eye's outer corner and was read as pupil and white of the eye:
  `add_eyes.py` now keeps dark "pupil" pixels only near an iris, drops thin strands with a morphological opening,
  and `--lash-reach` caps how far lashes grow from the lid. Her painted irises are nearly whole, so they are used
  as painted instead of mirroring the bottom half. Her head also has a second layer of mesh under each painted
  eye; it hid the eyeballs and pushed them back, so faces under the opening (up to 5 cm deep) are cut too.

## Known flaws

- The lid skins are a smooth skin colour; the brows are still painted on, so moods only move the lids.
- Her hair locks are thin single-sided strips from Tripo; they read fine at play distance.
