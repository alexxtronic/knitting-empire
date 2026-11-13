# coin — Production Log

## Config
- Type: prop (static), rendered to a picture: the game's coin icon (`assets/icons/coin.png`), shown on the HUD's coin chip and in the "+N" pop-up whenever Nora earns coins
- Target: a 256 px transparent PNG; the model itself (out/coin.glb) is for review only, not in `assets/props/`
- Tier: hero (a picture, so no triangle budget)
- Style: copy the reference closely (Alex's rule for props from a reference)
- Mode: auto

## Reference Image
- Path: ref/reference.png (Alex's message of 2026-11-13)
- Brief: "render this in blender with kiln as the new image for all coins in the game, you see these pop up with a cha ching sound and number of coins earned whenever you earn coin in the game"
- Assumptions: the coin is turned about 25° so its right edge shows, the camera nearly level; it is thick (about a fifth of its width, rim included); the back is not seen and mirrors the front; size doesn't matter (a picture), built 2 m across.

## Intent
- Palette (sampled from the reference): field gold #e9a21e, lit rim and highlights #ffe07a, shade #b86f05; one colour family, the light makes the rest
- Materials: polished gold (rim, edge, dollar sign; rough 0.2), satin gold (the recessed field; rough 0.36)
- Finishes: a broad rounded rim with a fine bead and groove inside it, a reeded edge (120 ridges) that stops short of the rim's bevel, a chunky dollar sign with rounded bevels standing out of the field

## Inventory (read from the reference)
- a thick disc with a broad rounded rim on the face
- a thin groove line just inside the rim, then the recessed, slightly matte field
- a heavy rounded "$" (one bar, showing above and below the S and through its counters), embossed and polished
- a reeded edge, its ridges catching the light on the right
- a soft shadow under it (not kept: the icon is transparent)

## Source
- Method: scripted (Blender, build.py), lathed profile, the dollar from Arial Rounded Bold (macOS system font, used only to shape the mesh; no font ships with the game)

## Pipeline
- Scene (headless build, rule 1): SM_Coin, SM_Dollar, SM_Dollar_Back; 2.0 x 0.34 x 2.0 (0.41 with the signs), front -Y; 218k triangles (a picture, no budget)
- Build: the coin lathed from a profile (field, bead, groove, rounded rim, bevel onto the edge, mirrored for the back), 720 segments, the edge reeded by moving its vertices (120 ridges); the dollar from Arial Rounded Bold, extruded and bevelled, scaled to 0.68 of the diameter
- Materials: values only (polished and satin gold, metallic), so the review GLB carries them whole
- Render: Cycles (Metal GPU), Blender's studio.exr for reflections plus three area lights, transparent film, Standard view; cropped to the coin and scaled to 256 px for the icon
- Round 1 (out/coin_render.png, 512 px): coin small in frame; deep mirror gold, slim dollar
- Round 2: camera closer; brighter, softer gold (an even white world added, rougher), a fatter dollar with a full bar: nearer the reference's flat toy gold
- Alex looked at both and picked round 1's look ("like this one better"): round 2's materials, world and fat dollar taken out again; the closer camera kept. Round 3 is that, at 1024 px, and is the icon
- Reviewers: Alex himself chose between the two renders; no fresh reviewer subagent rounds (as with the mailbox and other props)

## In the game
- `assets/icons/coin.png`: the HUD's coin chip, and `hud.coin_pop()`, the coin turning once and "+N" rising beside the chip whenever `Game.coins` goes up (`Game.coins_shown` is the count last shown; a new game and a loaded save set it, so a save's coins don't pop up)
- The cha-ching: `assets/audio/coins.wav`, `cha_ching()` in `tools/make_audio.py`
- Autotest: `--only=hud` checks the pop-up and saves `46_coin_pop.png`

## Checkpoint
- EXPORT done (icon and pop-up in the game), 2026-11-13
