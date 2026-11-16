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

## The roof (2026-11-16)

Alex: "what about the roof". The slopes had been flat-coloured strips of felt. `shingles` (1 m a tile)
draws cedar shingles stained the old roof's red-brown: courses 0.25 m apart, each shingle its own
width and shade, thin under the course above and thick at its butt with a shadow on the course below,
gaps between, grain down the slope, a little moss. It's turned so the courses run along the ridge with
the butts toward +x of each slope's own space; `shingles_r` is its mirror for the other slope, built
from a mirrored height map so its normals are right. The ridge cap and fascia boards are dark oak.

## Every building (2026-11-16)

Alex: "all buildings in the game should have similar realistic textures to her main house ... apply
similar wood grain realistic textures to the barn, the coffee shop etc and give them realistic tiles
for the roof". Four more maps: `boards` (2 m, weathered vertical boards with grain, knots and dark
gaps), `tiles` (1 m, overlapping clay tiles in courses, each its own shade), `brick` (2 m, running
bond with recessed mortar) and `paintwood` (1 m, painted wood with faint grain and wear).
`scripts/building_skin.gd` dresses each shop, the Mayor's Office, the café and the barn when
`Catalog.model()` loads it: each surface is mapped by its material name to a kind, the map is tinted so
the surface keeps its average colour, and the light bake carries over. Roofs use
`shaders/roof_tiles.gdshader` (courses along each slope from the face's flat normal and the smooth
normal; the barn's smooth normals alone skewed them into diagonal bands). The Mayor's redwood
reads as boards; timber and paintwood relief turned down after they looked furry from above.
`--only=buildings` saves a picture of each (`review/in_game/` has copies).

## Arched dormers and chimneys (2026-11-16)

Alex: "these ball roofs look ugly fix them to be arches" (the Mayor's Office's squashed-ball dormer
hoods, the café's rounded hoods with a ball on top) and "add chimneys coming out of the roof
whenever there's a fireplace". `kelib.arch_hood()` builds an elliptical barrel roof for a dormer: a
tiled shell with UVs in metres (courses along the barrel, butts down both sides), an arched trim
board round its front and the arch filled behind it. Both buildings were rebuilt and their light bake
run again. Nora's house gets a fieldstone chimney with clay pots over every fireplace inside it
(`main._update_chimneys()`), rebuilt when one is moved. Pictures: `review/in_game/63_*` and `62_chimney.jpg`.
