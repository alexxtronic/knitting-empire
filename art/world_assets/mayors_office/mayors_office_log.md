# The Mayor's Office: build log

From `ref/mayors_office_concept.png` (Alex, 2026-11-12), with the blender-kiln pipeline: brief
(`asset-brief.md`), blockout, review rounds against the reference camera (`review.py`), export.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/mayors_office/build.py
    Blender -b art/world_assets/mayors_office/out/building_mayor.blend --python art/world_assets/mayors_office/review.py -- round3

About 51k triangles, one static mesh. It writes `assets/props/building_mayor.glb`; `scripts/town.gd` places it
(`MAYOR`, south of the road, turned to face it) and hangs the carved Mayors Office sign from the portico at
`SIGN_MOUNT` (0, 4.69, 4.07).

## Rounds

1. Blockout. The window glass was too pale and `place()` overwrote the box parts' positions (box parts keep
   their position in `location`): it now composes the matrix. The dormer hoods were huge cylinders.
2. Flattened dormer hoods, glass #e8913a with a little glow, brown frames and bars, a tighter camera
   (the concept's 10.6 m front is 1,150 of 1,254 px).
3. Accepted (`review/round3_compare.png`).

## Still different from the concept

- The dormer hoods are flatter than the concept's.
- The laurels round the crest are smaller.
- The pediment's roof reads a little large.
- The back and the far side are inferred (plain brick, windows repeated).
