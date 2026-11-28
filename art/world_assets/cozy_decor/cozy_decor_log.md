# Cozy furnishings: kiln log (2026-11-28)

Thirty small furnishings for her house, each in colours she can pick in Build & Buy. Alex,
2026-11-28: "Small, cute things like different kinds of lamps, different kinds of lounging chairs,
things to help people customize their house and make it their own. Everything should be able to
have a different color if they choose it. Maybe like three or four color options."

## References (ChatGPT, Alex's account, 2026-11-28)

- `ref/lineup_1.jpg`: a 5 x 3 sheet.
  - Lamps: toadstool, paper lantern, tripod, arc, pleated.
  - Lounging: chaise, papasan, wingback, egg chair, shell chair.
  - Soft things: floor lounger, knit pouf, cushion pile, bunny stool, and the lily-bell lamp.
- `ref/lineup_2.jpg`: a 5 x 3 sheet.
  - Rugs and plants: scallop rug, checker rug, rainbow arch rug, pampas vase, cactus trio.
  - Plants and wall pieces: fiddle-leaf fig, plant stand, heart clock, floating shelf, rainbow print.
  - The rest: arched mirror, baskets, candelabra, toadstool table, tulip table.

Both use the marcus_props prompt style: a plain light grey background, a front three-quarter view,
and a chunky hand-painted cozy-game look. They're screenshots of the image viewer, cropped
(about 1100 px wide).

## Build

`build.py -- <kind> ... | all` writes `out/<kind>/` (gitignored) and copies the GLB to
`assets/props/`. Then run `light_bake/build.py -- <kind>` (every floor piece is in its `PROPS` and
`Lighting.BAKED`) and import. `review.py -- lineup` renders `review/lineup.png`.

Textures are painted in numpy:
- velvet sheen;
- chunky stockinette knit;
- tufted pile;
- the wavy checker;
- the tonal rainbow arch;
- the clock face;
- the print;
- toadstool spots;
- rice paper.

The rattan and woods come from craftlib.

**Colours.** Each piece's recolourable part is a material of its own, named `<id>_<part>`. It's
listed in `data/furniture.json` "colors" "parts" with one of the new four-colour palettes:
- `soft`: blush, sage, sky, butter;
- `velvet`: teal, rust, mustard, plum;
- `glaze`: cream, terracotta, celadon, cobalt;
- `lacquer`: chalk, ink, mint, coral;
- `wicker`: natural, honey, whitewash, espresso.

Trim, wood, brass, glass and plants are separate materials and keep their colour. Textured parts
keep their pattern under a tint: `Furniture.set_color()` greys the texture first. A tonal
texture (the arch rug, the checker) stays two-tone in any colour.

Glowing shades (the toadstool cap, the paper, the shades, the lily bells) are emissive.
`furniture.gd recolored()` now tints the glow with the colour, so a blue shade glows blue.

**Lights.** A piece's light is `"light": [x, y, z]` in furniture.json (Godot axes), which
`Catalog.build` turns into a warm omni light with no shadow. The candelabra's three candles are
`"candles"`, the game's own lit candle. The wall pieces (clock, shelf, print) have their origin
at the back and `"hang"` lifts them, like the paintings. They're `flat`, as are the rugs.

## Changes after review

- **Papasan:** the bowl tipped the wrong way, and its rim turned about its own centre instead of
  the bowl's. Now it's built round a pivot and tipped back 18° as one piece, as a wider, shallower
  dish.
- **Floor lounger:** remade as on the sheet, as a folding floor chair (a tufted pad and a
  leaning backrest) instead of a pad and roll.
- **Lily-bell lamp:** the sheet has bells hanging from curved stems, not tulips facing up.
- **Toadstool table:** taller (0.62 m).
- **Tulip table:** its brass edge was a full disc, which turned the whole top gold. It's now a
  ring.

## Sizes (w x d x h, metres) and triangles

| id | size | tris |
|---|---|---|
| mushroom_lamp | 0.66 x 0.66 x 0.75 | 908 |
| paper_lantern_lamp | 0.54 x 0.55 x 1.46 | 1344 |
| tripod_lamp | 0.60 x 0.58 x 1.59 | 1208 |
| arc_lamp | 0.48 x 1.39 x 1.79 | 1748 |
| pleated_lamp | 0.47 x 0.47 x 1.50 | 1536 |
| tulip_lamp | 0.64 x 0.48 x 1.33 | 2608 |
| chaise_longue | 1.75 x 0.62 x 0.90 | 2792 |
| papasan_chair | 1.40 x 1.33 x 0.90 | 2680 |
| wingback_chair | 0.89 x 0.80 x 1.14 | 1240 |
| egg_chair | 0.84 x 0.80 x 1.98 | 4736 |
| scallop_chair | 0.73 x 0.73 x 0.93 | 2696 |
| floor_lounger | 1.00 x 1.15 x 0.83 | 2448 |
| knit_pouf | 0.63 x 0.63 x 0.37 | 480 |
| cushion_pile | 0.75 x 0.75 x 0.39 | 2120 |
| bunny_stool | 0.42 x 0.46 x 0.68 | 1724 |
| rug_scallop | 1.60 x 1.58 x 0.02 | 1296 |
| rug_checker | 1.73 x 1.10 x 0.01 | 460 |
| rug_arch | 1.70 x 0.85 x 0.01 | 195 |
| floor_vase | 0.57 x 0.53 x 1.60 | 1962 |
| cactus_trio | 0.60 x 0.30 x 0.59 | 3664 |
| fiddle_fig | 0.45 x 0.44 x 1.69 | 4252 |
| plant_stand | 0.78 x 0.51 x 1.01 | 2642 |
| wall_clock | 0.40 x 0.07 x 0.40 | 776 |
| wall_shelf | 0.70 x 0.22 x 0.30 | 1540 |
| rainbow_print | 0.50 x 0.03 x 0.62 | 448 |
| arch_mirror | 0.68 x 0.28 x 1.75 | 565 |
| basket_trio | 0.85 x 0.63 x 0.46 | 3504 |
| candle_stand | 0.51 x 0.33 x 1.20 | 2384 |
| mushroom_table | 0.72 x 0.72 x 0.62 | 608 |
| pedestal_table | 0.56 x 0.56 x 0.55 | 1448 |

## Checked

`--only=cozy` (`scripts/cozy_check.gd`, about a minute) passes 7 of 7:
- every piece is its model with a catalogue picture;
- every part it names is on the model;
- each comes in 3 or 4 colours;
- a colour tints exactly those parts, and her own colour puts them back;
- the lamps have their lights and the candelabra its candles;
- Build mode places all 30 in her cleared house, 8 at a time.

It saves:
- `84_cozy_<n>.png` and `84_cozy_<n>_recolor.png`;
- `84_cozy_lamps_night.png`;
- `84_cozy_catalog.png`.

`--only=light`: the 82 baked props carry their bake.

**Drafts.** Names, prices and palette colours are drafts until Alex approves them.

**Not built.** The pieces stand on the floor or hang on a wall. None of them can be set on a
table or a shelf yet.
