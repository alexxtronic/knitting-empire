# Shop interiors: production log

## Config
- Type: nine static props, game assets for Knitting Empire (Godot 4.7)
- Target: glTF/GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: quick. Alex asked for these to be quick rather than hero props ("they don't need to be super high quality for the most part"), so the review used a lighter loop: stop at one clean reading, at most three review rounds, then my own check of the final fixes.
- Style: stylised, cozy, Woolcore palette (sweaters and yarn use `wool_*` palette materials, which the game swaps for its knitted felt)

## Brief
Alex, 2026-11-11: make the shops enterable, with the shopkeepers inside, "add assets to fill the building". No reference images, so each prop is designed for readability from the game camera (3/4 top-down, 10 to 14 m away).

| Prop | Shop | Size (m) | Triangles |
|---|---|---|---|
| shop_counter | Woolly Goods | 1.70 x 0.68 x 1.24 | 2.8k |
| yarn_shelf | Woolly Goods | 1.48 x 0.46 x 1.96 | ~15k |
| sweater_rack | Woolly Goods | 1.36 x 0.48 x 1.55 | ~3k |
| bakery_counter | bakery | 1.88 x 0.71 x 1.25 | ~4k |
| bread_rack | bakery | 1.76 x 0.49 x 1.75 | ~6k |
| brick_oven | bakery | 1.49 x 1.08 x 1.96 | ~2k |
| flour_sacks | bakery | 0.82 x 0.63 x 0.61 | ~2k |
| office_desk | land office | 1.40 x 0.71 x 1.20 | 1.8k |
| filing_cabinet | land office | 0.59 x 0.56 x 1.55 | 0.8k |

## Source
- Method: scripted (Blender `art/world_assets/interiors/build.py`, helpers in `kelib.py` and `craftlib.py`), generated wood, brick, burlap and wicker textures in `tex/`
- UV check (kiln `tools/uv_check.py`): every prop WARN only (overlap from box projection, expected), 0 FAIL, 0 % collapsed

## Review
Each round used a fresh reviewer with the brief and the lit and clay sheets (`review/<prop>/roundN.png`). The kiln sheet tool overlays several models when given more than one, so every prop got its own sheet.

### Round 1: 2 clean (shop_counter, filing_cabinet), 7 need fixes
- yarn_shelf: gap between the back panel and the cap; empty top bay. **Fixed:** back panel to the cap, top shelf removed so the top bay is full; two wrap bands on every ball.
- sweater_rack: the sweaters read as cushions; hooks floated over the rail. **Fixed:** a real sweater outline (V neck, sloping shoulders, sleeves hanging at the sides, ribbed hem and cuffs); hooks looped over the rail with a stem down to the hanger.
- bakery_counter: pastries tiny behind frosted glass; bags read as cards. **Fixed:** pastries 2x, clearer glass (alpha 0.12), upright bags.
- bread_rack: empty baskets under the top board, small loaves, flat shelves, stick baguettes. **Fixed:** filled baskets on top, loaves and buns bigger, shelves tilted 16 degrees, baguettes as long rounded loaves.
- brick_oven: no visible fire; flue floating. **Fixed:** the fire sat behind the dark mouth panel; moved in front. Flue lowered into the dome.
- flour_sacks: sacks read as jars; spill read as a plate. **Fixed:** slumped bodies, a tie and a ruffled neck, soft irregular spill.
- office_desk: quill feather detached. **Fixed:** vane along the shaft.

### Round 2: 4 clean (yarn_shelf, sweater_rack, brick_oven, office_desk), 3 need fixes
- bakery_counter: tarts read as coins; one bag hid the other. **Fixed:** tarts with a raised rim and domed jam; bags spaced apart; pastries 1.3x more.
- bread_rack: scoring stuck up like staples; back buns hovering. **Fixed:** scoring as shallow flush cuts, back row lowered, thicker shelves, darker crust.
- brick_oven (optional): fire pale. **Changed:** a more saturated orange.
- flour_sacks: tipped sack read as a toppled jar; scoop read as a mallet; label stood off. **Fixed:** soft mouth, open lathed scoop bowl with flour, label inset; coarser, lower-contrast burlap.

### Round 3: 1 clean (bread_rack), 3 small fixes (the last round under the lighter cap)
- bakery_counter: bags read as wooden canisters. **Fixed:** light kraft colour, uneven rolled tops.
- brick_oven: fire still salmon-pink (the emission was blowing out). **Fixed:** deeper orange with less emission.
- flour_sacks: the mouth read as a stack of buns; label poked out; scoop handle gap. **Fixed:** one flared, sagging lip with flour inside; label removed; handle joined to the bowl.
- bread_rack (optional): baguettes looked like carrots. **Fixed:** golden crust, rounder ends.

### Final check (mine, `review/<prop>/final_*.png`)
The fire reads orange in the arch, the bags read as paper, and the sacks have soft mouths. No fourth review round, by the lighter cap above.
