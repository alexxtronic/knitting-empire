# The coffee shop: build log

From `ref/coffee_shop_concept.png` (Alex, 2026-11-12), with the blender-kiln pipeline: brief
(`asset-brief.md`), blockout, review rounds against the reference camera (`review.py`), export.

    uv run --no-project --with pillow --with numpy python art/world_assets/coffee_shop/make_faces.py
    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/coffee_shop/build.py
    Blender -b art/world_assets/coffee_shop/out/building_cafe.blend --python art/world_assets/coffee_shop/review.py -- round4

About 40k triangles, one static mesh with its terrace (10 x 7.8 m). It writes `assets/props/building_cafe.glb`.
The plaque's face (the cup between two sprigs) and the chalkboard's face are the concept itself, cut out by
`make_faces.py` like the shop signs; the plaque's outline is traced off its cream frame.
`scripts/town.gd` places it by the farmhouse (`CAFE`, facing the farm path) and adds no painted label
(`OWN_SIGN`).

## Rounds

1. Blockout. The cross-gable's bargeboards leaned the wrong way, the front roof came down over the awning,
   the awning's stripes were a third of the concept's width, the dormer hoods were huge, the ivy leaves big.
2. The roof's front edge at the fascia (y 480 px), stripes and scallops at the concept's 14, flatter hoods,
   smaller and denser ivy. The plaque's middle was cut away: the trace started inside its hump.
3. The cross-gable's eaves level with the main roof's.
4. The plaque traced from above its hump: accepted (`review/round4_compare.png`).

## Still different from the concept

- The roof tiles are a texture, not the concept's chunky separate tiles; the ridge is a plain roll.
- The dormers' hoods are rounder and bulkier, their cream fronts smaller.
- The flower boxes and the hydrangeas are simpler (round heads on leafy mounds), the ivy is star leaves.
- The bentwood chairs are thinner; the lanterns are plain boxes.
- The depth (5 m), the back and the left side are inferred.
