# house_exterior — build log

## Brief (2026-11-15)

Alex: "textures on the exterior of the house are flat and dull, add textures in our style to both
floor and exterior walls." The house's outside had been flat-coloured boxes: cream plaster, dark
timber posts and rails, a grey slab round it and a brown doormat at the door.

## What was made

- `build.py` (numpy only) draws three tiling maps with their normal maps, nothing from photographs:
  - **plaster** (2 m a tile): lime plaster over daub, laid on in ~260 overlapping trowel swipes, each a
    smooth sweep with a soft ridge where the blade lifted, warm and cool limewash patches, sand, a few
    pits and hairline cracks. Base `#e8d7b6`, close to the house's old `PLASTER`.
  - **timber** (1 m): hand-hewn oak, grain down the image, slow rings, adze facets across, drying
    checks. `timber_h` is the same turned a quarter, for rails and lintels.
  - **stone** (2 m): fieldstone in rough courses (a wrapped Voronoi), each stone its own grey or buff
    from the palette's stone family, pale lime mortar set back, a few lichen flecks.
- `review/sheet.png` shows each tiled 2 x 2 (no seams) beside it lit from the upper left.

## In the game

`scripts/house_skin.gd` puts them on the house's boxes with triplanar mapping in each box's own space:
plaster on the walls, the door lintel and the gables; oak on the posts, rails, window frames and sills
and the door leaf (lighter); stone on the slab round the house and a new 30 cm fieldstone footing
along the outside of every outer wall. The doormat became a porch step of weathered boards
(`Planks` floor, shade `porch`) on a dark oak frame, with a red knitted mat on it (`world.gd`).
