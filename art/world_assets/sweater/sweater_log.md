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

## The five test designs (names and stars are drafts)

| Stars | id | Name | What it is |
|---|---|---|---|
| ★ | cranberry | Cranberry Classic | the reference: plain red |
| ★ | oatmeal_stripe | Oatmeal Stripe | oatmeal with pairs of chocolate stripes |
| ★★ | snowfall_yoke | Snowfall Yoke | navy, a cream Fair Isle snowflake band round the yoke, red seeds, peerie bands above the cuffs |
| ★★★ | flock | Flock of Friends | sage, a flock of cream sheep across the chest, daisies below, a sheep on each sleeve |
| ★★★★ | midnight_moon | Midnight Moon | indigo, gold stars, the moon's eight phases across the chest |

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
