# Townsfolk touch-ups (2026-11-17)

Run on a townsperson's `tools/character_build/tf_<id>_tripo_eyes/tf_<id>_tripo_eyes.blend` after `tools/add_eyes.py`.
Each one saves the blend and re-exports `assets/tf_<id>_tripo_eyes.glb`. A fresh `add_eyes.py` run starts from the
rig's blend, so it loses these: run them again after it.

- `handpatch.py`: deletes the torn slivers on the fingertips (where two people's hands touched in the Tripo lineup and
  `split_people.py` cut between them) and fills the holes. Marcus, Dev, Hank, Jake. It only saves; follow it with:
- `handsmooth.py -- "$PWD" tf_<id>_tripo --iters 8`: a gentle Taubin smooth of the fingers (`--dry` prints a spike score).
- `uvfix.py`: gives the filled faces the skin's UVs (Marcus picked up a stripe of his shirt).
- `handfix.py -- "$PWD" tf_marcus_tripo --th 0.65`: paints dark texels on the hands with the hand's skin (a mark on
  the back of Marcus's hand).

`Blender -b <blend> -P tools/character_build/townsfolk_touchups/<script>.py -- "$PWD" tf_<id>_tripo [...]`
