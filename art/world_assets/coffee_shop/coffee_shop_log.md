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

## 2026-11-14: walk-in

Alex asked for the inside: "a cozy little cafe of dreams" (his café mock-up). The building is now in parts like
the other walk-in shops (`interiors.gd`): `base` (the plank floor, the threshold, the doorstep and the terrace),
each wall at full height and cut down to `LOW` (hollow, 0.2 m, with warm plank lining inside, the windows cut
through with EXACT booleans whose faces take the trim), the `door` hinged on its left jamb, and the `roof` (with
the fascia, a plank ceiling at 3.51 m and three beams under it, so first person sees a ceiling). The door is
1.15 m wide on the room's centre line, level with the floor.

- The room is x -2.95..2.95, Godot z -3.9..1.1; the terrace is in front of it (`interiors.json` "room").
- The left wall lost its lower window: the fireplace stands against it. The back has one window, between the
  bookshelf and the espresso bar.
- The furnishings are `art/world_assets/cafe_props` (see `cafe_props_log.md`); the layout is `interiors.json`.

## 2026-11-14: twice the size

Alex: "make the cafe 2x larger both inside and out, this will be the main hangout for people in the city".

- `W` 5.9 -> 11.8 and `D` 5.0 -> 10.0; the height and the front gable stay the concept's. The concept's front (its two shop windows, door, plaque and gable) is the middle of the façade; each wing adds a shop window, a dormer and a run of string lights, and the awning runs the whole front.
- Dormers are as deep as the shallower roof needs (`dd` from the slope), so they still reach back into the tiles.
- Ceiling beams spread over the width (six). Chimney moved to the left gable end, over the fireplace inside (Godot x -4.9, z -3.1).
- Side and back windows are lists: two arched windows a side, low enough to see out of, one at the back between the shelves and the espresso bars.
- Terrace: an oval 7 m out to the sides and 4 m deep, four bistro tables, the barrel and the big pot at the corners, the A-frame menu out by the path. `data/interiors.json` "cafe" "outside" blocks round each.
- Room: Godot x -5.9..5.9, z -7..3 (centre z -2). Review renders: `review/round5_*` (`review.py` now hides the `_low` walls, which the game shows only from inside, and renders every part).
- The world layout's town post box (`decor_mailbox@57.00,6.60`) now stands on the terrace, about x -1.8, z 4.3 in the café's own space: the bistro tables sit either side of it (x ±3.2 and ±5.6, 1.6 m out).
