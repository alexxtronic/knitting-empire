# sweater — build log

One knitted sweater that every character can wear, with the designs swapped on it as textures.

## Brief (Alex, 2026-11-13)

"Flesh out the sweater system. Basically we'll have around 50 sweaters that can be 'knit' in the game of
various rarities. 20 common, 15 rare, 10 ultra rare and 5 legendary (give them 1-4 star system). These
sweaters can be 'worn' by any character in the game. We'll produce one core sweater asset and just apply
different patterns to that asset to save on time. Try to recreate this core sweater model in blender,
apply fabric textures and fabric physics, then apply 50 patterns to it and assign them rarities."

Then: "proceed, make 5 first as a test".

Reference: `ref_sweater.png`, a plain red crew-neck pullover, a little oversized, dropped shoulders, roomy
sleeves gathered into deep ribbed cuffs, a ribbed hem and a ribbed collar.

## Config

| | |
|---|---|
| Type | clothing (a skinned garment on the shared 22-bone rig) |
| Style | the game's stylised Tripo characters; chunky hand knit |
| Target | glTF for Godot 4.7, no Draco |
| Method | scripted (`build.py`), no AI generation |
| First character | Nora (`tools/character_build/nora_tripo_eyes/nora_tripo_eyes.blend`), rest pose |
| Real size | fitted to the character: Nora's is 0.64 m from collar to hem |

## Method

1. **Shape** (`torso_rows`, `sleeve_rows`). The body is 64 points round, the sleeves 32, so every
   character's sweater has the same mesh and the same UVs. Each ring is the convex outline of that slice
   of the body (only skin that follows the torso's bones for the body, only that arm's for a sleeve), so
   it bridges hollows the way knit does, plus ease. Above the chest the rings become a dome of rays from
   the chest's centre up to a crew collar round the base of the neck, dipping at the front. Each sleeve
   follows the upper and lower arm bones, centred on the arm's own outline (the Tripo arm bones sit near
   the outside of the arm), a little out from the body so the sleeve stands as its own tube. The hem,
   collar and cuffs turn under inside (`LIP`) so the openings have depth.
2. **Drape.** The folds are built in, not simulated: the knit blouses over the hem rib in soft folds,
   gathers into each cuff, and creases in the crook of the elbow. A Blender cloth simulation (`settle()`,
   `--sim`) is in the script, but on this coarse a mesh it crumpled the sleeves against the body
   (review/pass1), so it is off. Revisit with a finer copy simulated and its shape carried back.
3. **Knit.** Two tiling stitch tiles shared by every design, drawn stitch by stitch (`patterns.py`,
   from the rug's `knit.py`): stockinette (columns of knit Vs) and knit-two purl-two rib, each a grey
   shade and a normal map, 4 stitches a tile, with the fleece scan's fibre speckle
   (`../textures_web/knitted_fleece`, CC0). They go on a second UV set, `Stitches`, so they stay sharp
   however small the design maps are. A shared mask says which parts are rib (hem, collar, cuffs).
4. **Designs** (`patterns.py`). Each design is a grid of stitches per part (body, sleeve, hem, collar,
   cuff) coloured from a small palette, saved as one 1024 x 512 colour map, 4 pixels a stitch. The UVs
   are laid flat by arc length, so a stitch is the same size everywhere (the body's island narrows up
   the yoke, as a real yoke's rows do) and a motif drawn in stitches lands as drawn. `layout.json`
   records each part's rectangle and size in stitches, from Nora; every other character reuses it.
5. **Skin.** Every point takes the bone weights of the nearest skin of the same part of the body (eight
   nearest, by distance; four bones at most). The body gets an `under_sweater` shape key that pulls the
   skin the sweater covers in by `TUCK` (more on the forearms and hips, where Nora's own sculpted sweater
   is bulkiest), for the game to turn on with the sweater.

## The fifty designs (names and stars are drafts)

Alex: "proceed, make 5 first as a test", then "Yes, make the designs". 20 common (★), 15 rare (★★), 10 ultra
rare (★★★), 5 legendary (★★★★); `patterns.py` asserts the counts. Each design function says what it
draws in its docstring; several commons share one (a plain colour, a tweed, stripes) with their own
palette. Common is plain colours, tweeds and stripes; rare, allover repeats and single bands; ultra rare,
pictures (sheep, sunflowers, foxes, the lighthouse, Gran's cottage); legendary, the whole sweater as one
picture or many Fair Isle bands, in five or more colours.

| Stars | id | Name | Drawn by | Colours |
|---|---|---|---|---|
| ★ | cranberry | Cranberry Classic | `cranberry` | #c0261d |
| ★ | oatmeal_stripe | Oatmeal Stripe | `oatmeal_stripe` | #dccdb0 #5b3a26 |
| ★ | forest | Forest Green | `solid` | #2f5a3a |
| ★ | harbour_navy | Harbour Navy | `solid` | #22304f |
| ★ | mustard | Mustard Seed | `solid` | #c99a2e |
| ★ | lavender | Lavender | `solid` | #a493c4 |
| ★ | pumpkin | Pumpkin | `solid` | #cf6a2a |
| ★ | heather_tweed | Heather Tweed | `_tweed` | #8c8b88 #b8322a #d8a83a #4a7a9a #efe3c8 |
| ★ | bark_tweed | Bark Tweed | `_tweed` | #6b4a33 #d8c7a6 #a0522d #557a46 |
| ★ | cream_forest | Cream and Forest | `contrast_ribs` | #efe6d2 #2f5a3a |
| ★ | charcoal_tipped | Charcoal Tipped | `tipped` | #3a3a3c #b8322a |
| ★ | breton | Breton | `breton` | #f2ece0 #4f7fb8 |
| ★ | rust_stripe | Rust Stripe | `wide_stripe` | #a8492a #e9dcc2 |
| ★ | mint_candy | Mint Candy | `candy_stripe` | #9fd3bf #fbf7ee #7d8c88 |
| ★ | rose_block | Rose Block | `colourblock` | #d98a95 #7a2a3a #f3e7d3 |
| ★ | sage_cream | Sage and Cream | `other_sleeves` | #8fa58a #efe6d2 |
| ★ | denim | Denim Pinstripe | `pinstripe` | #3b5a80 #9fb4cc |
| ★ | butter_dots | Buttercup Dots | `pin_dots` | #f1d77a #fffaf0 |
| ★ | plum_stripe | Plum Stripe | `chest_stripe` | #5e2f55 #efe3c8 #e0b43c |
| ★ | dusk_ombre | Dusk Ombre | `ombre` | #1f3b4d #2f5d73 #4f8a99 #86b8bc #c7e0d9 |
| ★★ | snowfall_yoke | Snowfall Yoke | `snowfall_yoke` | #1f2c4a #efe3c8 #b8322a |
| ★★ | argyle | Argyle | `argyle` | #2d4a3e #b98f57 #c9372f |
| ★★ | gingham | Picnic Gingham | `gingham` | #f6f0e4 #e4958f #c43b35 |
| ★★ | houndstooth | Houndstooth | `houndstooth` | #efe6d2 #2a2724 |
| ★★ | chevron | Chevron | `chevron` | #2a7f7a #f1e8d6 #e2725b |
| ★★ | polka | Navy Polka | `polka` | #22304f #f1e8d6 |
| ★★ | lattice | Cornflower Lattice | `lattice` | #6a8fd0 #f4eee0 #e0b43c |
| ★★ | raindrops | April Showers | `raindrops` | #7d93a8 #f7f7f4 #cfe3f0 #4c5e70 |
| ★★ | strawberries | Strawberry Patch | `strawberries` | #f3ead6 #c8302c #4f8a3a #f2d36b |
| ★★ | heart_band | Sweetheart | `heart_band` | #f3e7d3 #c8302c #e79aa6 |
| ★★ | peerie_bands | Peerie Bands | `peerie_bands` | #e3d3b4 #5b3a26 #a8322a #3f6a4a |
| ★★ | pine_band | Winter Pines | `pine_band` | #2f5a3a #f1e8d6 #6b4a33 |
| ★★ | tulip_border | Tulip Border | `tulip_border` | #a9cfe6 #d9434a #e98aa8 #f2c94c #4f8a3a |
| ★★ | greyspine | Greyspine Peaks | `mountains` | #7fa3c4 #8a8f99 #f6f4ee #2f4a3a |
| ★★ | daisy_chain | Daisy Chain | `daisy_chain` | #b6a3d1 #fbf7ee #f2c94c #5f8a4a |
| ★★★ | flock | Flock of Friends | `flock` | #7f9a6d #f3ead6 #2f2a26 #3f5a3a |
| ★★★ | sunflowers | Sunflower Field | `sunflowers` | #8cc3e0 #f2c12e #5a3a1e #3f7a3f |
| ★★★ | autumn_leaves | Falling Leaves | `autumn_leaves` | #4a2e2a #e0782a #b8322a #e2b23c |
| ★★★ | fox_forest | Fox in the Pines | `fox_forest` | #2b4a35 #d2691e #f3ead6 #2a2320 #5f8a5a |
| ★★★ | reindeer | Reindeer | `reindeer` | #a52a2a #f3e7d3 |
| ★★★ | honeycomb | Honeycomb | `honeycomb` | #e0a92a #b07a14 #2a2320 #f6f2e6 #f8dc5a |
| ★★★ | mushrooms | Toadstools | `mushrooms` | #6d8a52 #c8302c #f3ead6 #3f5a32 #8a5a32 |
| ★★★ | lighthouse | Saltmeadow Light | `lighthouse` | #cfe3ec #c23a30 #f6f1e6 #f2c94c #2b2f3a #2f6f9a #1f4a6e |
| ★★★ | cottage | Home Sweet Home | `cottage` | #bcd7e6 #a83a2c #f3ead6 #f2c94c #6b4226 #7a6a5a #f4f4f2 #6a9a5a #3f6a3f |
| ★★★ | rainbow | After the Rain | `rainbow` | #9cc9e6 #d6453d #ee8a3a #f2cf4a #5fae5a #4a86c8 #7a5aa8 #fafafa |
| ★★★★ | midnight_moon | Midnight Moon | `midnight_moon` | #22204a #e0b43c #f4ead0 #3a3870 |
| ★★★★ | golden_fleece | Golden Fleece | `golden_fleece` | #1d4a4f #e2b23c #2a2320 #f3e7c8 #a8761c |
| ★★★★ | northern_lights | Northern Lights | `northern_lights` | #141a33 #3fd08a #2a8f8a #8a5cd0 #f4ead0 #0b1f19 |
| ★★★★ | grans_heirloom | Gran's Heirloom | `grans_heirloom` | #e3d3b4 #5b3a26 #a8322a #d1a23a #3f6a4a #33507a |
| ★★★★ | four_seasons | Four Seasons | `four_seasons` | #f1e8d4 #a8d5b5 #8cc3e0 #b5532b #22304f #e07a95 #f0c43a #5a3a22 #3f7a3f #fafafa #e08a2a |

Flat check: `patterns.py OUT_DIR` writes each design's body. Catalogue: `SW_VIEWS=front,back` on the
`--render` build, then `sheet.py nora` writes `review/nora_catalogue.jpg`.

## Checkpoints

### Pass 1 (no sim)
- The body's outline took in skin weighted to the thighs that bulges out at the hips, and the upper arms:
  the sweater hung like a poncho over the arms. Fixed: thigh skin only below the hip joint and within
  0.16 m of the middle; the upper arms only for the dome over the shoulders.
- Sleeve rings were lopsided and too wide: skin on the torso's side follows the arm bones. Fixed: arm skin
  within 8.5 cm of the bone, rings centred on the slice's own outline.
- Collar too high (a turtleneck on Nora's short neck): lowered, front dip deepened.
- Cloth sim (`--sim`): crumpled sleeves; turned off (see Method 2).

### Pass 2
- 8 px a stitch could not draw a V: the knit read as dots on a grid. Changed to small per-stitch design
  maps and shared high-resolution stitch tiles on a second UV set (Method 3, 4).
- Cycles rendered the generated maps black: they are now read back from their files.
- Colour washed out to salmon (white sheen, bright fill): sheen tinted by the wool's own colour, fill
  lowered, Standard view transform.

## Out

- `out/nora_sweater.glb`: the sweater skinned to Nora's rig (no animations). Not in the game yet.
- `out/textures/`: `<design>.png` (one per design), `knit_stockinette(_n).png`, `knit_rib(_n).png`,
  `sweater_rib_mask.png`.
- `review/`: `nora_<design>_front/back/close.png`, `alone_front/side.png`.

## Steve and Barbara (2026-11-13)

Alex: "put this over Steve, and the mailman as a test". The mailman is Barbara.

- First fit: Steve's sweater stopped flat at the chest (his neck bone sits well below where his neck
  meets his shoulders, so the collar was inside his shoulders), and his hem rib showed up on his
  stomach (his longer body ran past Nora's rectangle in the shared layout). Barbara's hung like a
  poncho: her satchel is weighted to the hips and the outline took it in.
- Fixes, all general:
  - The collar's height is the top of the shoulders just beside the neck, never lower than the neck
    bone gives. The collar is a round crew neck of 6 cm round the torso's middle (`neck` per
    character: Steve's is 7.5 cm).
  - Below the chest the body is no wider than 1.15 x the chest, so a bag or a flared jacket stays
    under the knit.
  - Each character's stitches are stretched to fit the shared layout, so every design fits everyone.
  - `under_sweater` is now a shrink-wrap: covered skin goes in by `TUCK`, and anything still within
    `MARGIN` of the knit (a satchel, braces, a jacket collar) is pulled in under it.
- Left: the ends of Steve's overall straps peek out at the collar; Barbara's sleeves merge into the
  body (her arms hang against her sides); both look boxy, since they trace bulky outfits.
