# Café props: kiln log

Alex, 2026-11-14: "a cozy little cafe of dreams, extremely cozy, candles and a fireplace and books on a book
shelf and a counter with an espresso machine behind it, cozy seating to read a book … make book asset like
this and candle assets (to be used all over the game, put some in her house) with soft glow. Use the cafe
mock for inspo." Three references: a pillar candle in a brass chamberstick, a chunky purple cloth book with
gold corners and a red ribbon, and the café mock-up.

Everything is script-built (`build.py`), textured with numpy maps (cloth weave, page edges, gold leaf, wax,
wood grain, chalkboard, tartan) and reviewed in Cycles against white (`review.py`, pictures in `review/`).

## Candle

- A chunky cream pillar (r 4.2 cm, 19 cm) with soft drips down its side, in a hammered brass dish with a ring
  handle, as in the reference. The game lights it (`Catalog.lit_candle`): flame, core, halo and light at
  `FLAME_Z` 0.218 m.
- The drips first read as sticks, then as strings of beads; joining them and the pillar and voxel-remeshing
  the lot (1.8 mm, smoothed, decimated to 9.2k triangles) fuses them into the wax. The lathe profile has to
  start on the axis, or the remesh drops the open-bottomed pillar.

## Books

- 16.5 × 22.5 × 6.6 cm, cloth over boards with a rounded spine, page block with gilt edges, gold corner caps
  and spine bands, a gold leaf emblem, a red ribbon out of the bottom. Five cloths: plum (the reference),
  forest, wine, navy, mustard; and a stack of three.

## Café furniture (from the mock-up)

- `cafe_counter`: green panelled, oak top, a glass case of croissants, cinnamon buns and muffins, a cake
  under a dome, a tip jar and a bag of coffee.
- `espresso_bar`: a red espresso machine (two group heads, a gauge, cups on top), a grinder, jars of beans,
  two shelves of cups and jars with trailing ivy, a chalkboard with a coffee cup.
- `cafe_bookshelf`: 1.5 × 2.2 m, crammed with cloth-bound books leaning here and there, a trailing plant on top.
- `cafe_table`: a round table with two spindle-back chairs and a jar of lavender.
- `cafe_coffee_table`: a planked low table with two books, a jug of daisies and a cup of coffee.
- `pouf`: tartan, tufted. `pendant_lamp`: a dark enamel dome on a cord, its bulb at 2.4 m.

## Still different from the mock-up

- No sofa or armchair of its own: the café uses the house's plaid armchair and sofa.
- No hanging macramé planter, framed pictures, globe or table lamp.
- The candles' light is real but small; the mock's warm haze comes from the fire, the lamps and the halos.
