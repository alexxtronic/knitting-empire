# Shop signs: build log

Five hanging shop signs from Alex's references (`ref/sign_*.png`, 2026-11-12): Willow Homes,
Builder's Delight, The Yarn Barn, Heart Bakery, Mayors Office. Built the blender-kiln way: by
script, reviewed in rounds against the reference (`review/<sign>/round*_compare.png`, reference on
top), with clay renders, the `.blend` kept beside each GLB in `out/<sign>/`.

```bash
uv run --no-project --with numpy --with pillow python art/world_assets/shop_signs/make_faces.py
Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/shop_signs/build.py -- all
Blender -b art/world_assets/shop_signs/out/<sign>/sign_<sign>.blend --python art/world_assets/shop_signs/review.py -- <sign> <round>
```

## Rounds

- **Round 1** (Yarn Barn, all modelled): the board, border, studs, rod and rings, with the
  lettering as 3D text in Superclarendon Bold. Too wide a face, so the width cap shrank the letters
  to about 75 px high of the reference's 190. The wood was pale and stripy, the border hugged the
  board's ends, the sprigs were sparse, and the yarn strands were a straight grid.
- **Round 2/3**: Georgia Bold (The Yarn Barn) and Baskerville Bold Italic (the others), set to
  the reference's width. Border inset fixed at the ends, darker wood, fuller sprigs, curved strands.
  Close, but the letterforms were still not the reference's.
- **Round 4** (Alex: do the lettering the way the Maple Grove welcome sign does): the board's face is
  now the reference itself. `make_faces.py` cuts each board out of its square-on reference (no
  perspective warp needed), flood-fills the white backdrop in from the edges (and from just under
  the rod, where the hump, straps and rod wall in pockets of white), traces the board's outline
  from it, paints the backdrop round the board in the wood's colour (so filtering never pulls white
  onto the edge), and makes a normal map that raises the cream work. `build.py` extrudes the board
  from the traced outline and maps the face onto its front; the sides and back are planks, and the
  log, iron straps and wooden rings are modelled. The 3D text, emblems, sprigs and flourishes are
  gone. Each sign is about 9,200 triangles (it was 30 to 48 thousand).
- **Round 5**: review renders in Standard view (the face is the reference's own colour: AgX
  washed it out), and the rod lowered so its underside tucks behind the board's top edge.

## In the game

`scripts/town.gd` (`HANGING_SIGNS`) hangs The Yarn Barn on Woolly Goods, Heart Bakery on the
bakery and Willow Homes on the Land Office, at 0.82 scale (1.64 m across), the board's centre 3.03 m
up: above the timber band over the door (2.74), the log just under the eaves (3.4). It is a child of
the front wall, so it goes when the wall is cut down. Those three buildings no longer build the old
painted board (`HANGING_SIGN` in `town_buildings/build.py`).

Builder's Delight hangs on Gus's Home Goods (`homegoods`; its GLB keeps its old board until it is
rebuilt with `-- homegoods`). Mayors Office hangs from the portico of the new Mayor's Office
(`art/world_assets/mayors_office`) at the build script's `SIGN_MOUNT`, 0.9 scale (`HANGING_SIGN_AT`).

## Notes

- The references are 2000 x 667, the board 1,690 px end to end = 2.0 m (`PX`). The rod's
  underside is at 92 px; where the board's hump runs up behind the rod the outline stops there.
- The hanger's straps cross the board's top edge at x 455 and 1535 px: the trace bridges them.
- `make_faces.py`: `Image.fromarray` on a NumPy array shares a read-only buffer, so the flood fill
  silently did nothing until the mask was copied.

## The Mayor's apostrophe (2026-11-12)

Alex: the sign should read "Mayor's Office", as the game's text does. `add_apostrophe.py` paints a
carved apostrophe (cream face, bright lip top left, warm edge and soft shadow down right, matched
to the letters) between the r and the s of `ref/sign_mayors_office.png`, in the gap under the hat's
brim. The original reference had none. Then `make_faces.py` and `build.py -- mayors_office` as usual.
