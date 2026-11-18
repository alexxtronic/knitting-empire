# Marcus's house props: kiln log (2026-11-17)

Props for the walk-in 1990s back-split in Bretton Oaks. Built by hand through the kiln method: a
reference, one build script, review renders against the reference, fixes, export.

## References (ChatGPT, Alex's account, 2026-11-17)

- `ref/lineup_1.jpg`: a 3 x 3 sheet with the kitchen counter, island, fridge, toilet, vanity,
  tub/shower, pinball machine, CRT TV on its stand, and workbench.
- `ref/lineup_2.jpg`: a 3 x 3 sheet with the teddy bear (front and side), the alphabet blocks,
  dump truck, rocking horse, ball, toy train (three-quarter and side), and garage shelf.
- `ref/lineup_3.jpg`: a 2 x 2 sheet with the six-panel door, sliding patio door, counter with
  sink, and counter with cooktop. This sheet was for Alex's second batch.

All three use the same prompt style: a plain light grey background, a front three-quarter view,
and a chunky hand-painted cozy-game look. They're saved at 1024 px as JPEG.

## Build

`build.py -- <kind> | all` writes `out/<kind>/` (gitignored) and copies the GLB to
`assets/props/`. The textures are painted in numpy (as in `cafe_props`) and packed into the GLB.
There's no Draco. `make()` re-centres each piece (origin on the floor under the middle; the door
keeps its hinge edge) and stops if a size is more than 12% off `TARGET` or a piece is over budget
(6k triangles, 12k for the pinball and kitchen pieces).

`review.py -- <kind>` renders `review/<kind>.png`. `review.py -- lineup` renders
`review/lineup.png`, with every piece at real size in three rows. The review PNGs are quantised
to keep them small.

## Sizes (w x d x h, metres) and triangles

| id | size | tris |
|---|---|---|
| kitchen_counter_90s | 2.40 x 0.62 x 2.14 | 2616 |
| kitchen_counter_sink | 2.40 x 0.62 x 1.17 | 2296 |
| kitchen_counter_stove | 2.40 x 0.62 x 1.01 | 3860 |
| kitchen_island_90s | 1.60 x 0.90 x 0.94 | 2872 |
| fridge_90s | 0.80 x 0.80 x 1.73 | 688 |
| toilet | 0.50 x 0.66 x 0.80 | 1044 |
| bathroom_vanity | 0.92 x 0.56 x 1.56 | 1230 |
| bathtub | 1.53 x 0.75 x 1.93 | 1888 |
| pinball_machine | 0.76 x 1.40 x 1.90 | 1568 |
| crt_tv | 0.90 x 0.50 x 1.06 | 1322 |
| workbench | 1.80 x 0.66 x 1.87 | 2162 |
| garage_shelf | 1.21 x 0.46 x 1.80 | 2084 |
| door_interior | 0.86 x 0.19 x 2.03 (slab 0.85 x 0.04; knobs make the depth) | 1212 |
| sliding_door | 1.80 x 0.13 x 2.05 | 708 |
| teddy_bear | 0.27 x 0.22 x 0.35 | 1896 |
| toy_blocks | 0.21 x 0.08 x 0.20 | 1336 |
| toy_truck | 0.36 x 0.19 x 0.21 | 1014 |
| rocking_horse | 0.86 x 0.32 x 0.71 | 3326 |
| toy_ball | 0.25 x 0.25 x 0.25 | 528 |
| toy_train | 0.52 x 0.11 x 0.21 | 1692 |

## Nodes

- `door_interior`: one node, `door`. Its origin is at the bottom of the hinge edge, and the slab
  runs along +X, so turning it about Godot's Y axis swings it open. The hinge knuckles reach 9 mm
  past the origin, to -X.
- `sliding_door`: two nodes. `frame` holds the frame and the fixed left panel. `slide` is the
  right panel in the front track, with its origin at its own bottom centre; it opens by moving
  along -X, about 0.85 m. The glass material is named `glass`.
- Everything else is one `model` node. The truck, train and horse run along X, nose to -X.

## Review against the references (round 1, then fixes)

- **Oak:** the knots read as burl, and the grain was too coarse. Knots are off, the uvs are
  finer and the contrast is lower. It's now closer to the even honey oak on the sheets.
- **Teddy:** the tan belly patch isn't on the reference, so it's gone.
- **Blocks:** I had a loose heap of plain coloured cubes. They're now the reference's pyramid
  (D E F, then B C, then A), each a coloured block with cream face panels and raised letters.
- **Truck:** the tyres were 20% too small next to the reference, so they've gone from r 0.04 to
  0.048.
- **Rocking horse:** it was thin. The body, legs, neck and head are 15 to 40% thicker. I made the
  rockers honey wood with yellow dots, the coat cream with orange spots, the yarn mane blond and
  in strands, and the saddle red with a yellow trim, all as on the sheet.
- **Ball:** I had six gores, but the reference has three bands (red, yellow, blue), so it has
  bands now.
- **Train:** the colours now follow the sheet: a red boiler, green cab, yellow roof, blue chimney
  and cowcatcher, then blue and red open wagons.
- **Garage shelf:** I swapped the gas can for the sheet's red toolbox and green bin.
- **Bathtub:** this is the reference's alcove unit, with back and end walls, the shower on the
  left wall and the curtain gathered on the right.

## Inferred (the sheets show one view)

The backs and the hidden sides are inferred:

- the island's back doors (plain panels, no knobs)
- the pinball's right-side art (it mirrors the left)
- the fridge's back
- the CRT's tapered tube
- the back face of the door, which mirrors the front

`kitchen_counter_sink` and `kitchen_counter_stove` are the base-cabinet run of `lineup_3`
(2.4 m, the same width, depth and height as `kitchen_counter_90s`) without the wall cabinets. The
uppers float on `kitchen_counter_90s` and need a wall behind them.

## Not done

- No Godot import (`.import` files): another session is using Godot. Import these before use.
- No light bake: registering in the bake's `PROPS` and in `Lighting.BAKED` is outside this
  folder.
- `data/furniture.json` hasn't been touched.
