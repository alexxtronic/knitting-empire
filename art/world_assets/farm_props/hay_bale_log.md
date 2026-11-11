# Hay bale — Production Log

## Config
- Type: prop (static), game asset for Knitting Empire (Godot 4.7)
- Target: glTF/GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: balanced
- Style: stylised, hand-painted, cozy
- Mode: auto

## Reference Image
- Path: in Alex's message of 2026-11-11 (not saved to disk)
- Brief: "Hay bales for scattering around esp around the barn and any animal areas"
- Brief enrichment: Alex's reference art: dense feathery golden straw in layers, two twisted brown ropes.
- Visual comparison: close match (by eye, scripted build)

## Intent (written after the first build: kiln was adopted mid-way, on Alex's request)
- Palette: main golden straw #f0a51a; secondary deep core straw #c98a1c; accent rope brown #a3622a
- Materials: straw strands (rough 0.75, normal 0.7), shadowed core straw (rough 0.85), twisted rope (rough 0.8)
- Finishes: seven layered flakes round the sides with ragged tips; shingled flakes on top drooping over the ends; loose stalks; two plied ropes

## Source
- Method: scripted (Blender farm_props/build.py, helpers in art/world_assets/craftlib.py and kelib.py)

## Pipeline
- Build / import: 6446 triangles; 1.05 x 0.69 x 0.59 m (core 0.88 x 0.49 x 0.45); front -Y, origin at the centre of the base, 1 unit = 1 m
- Cleanup: built clean by script (no import); normals set per part
- Texturing: generated painted textures (numpy) saved to tex/, assigned per part
- UV check (kiln tools/uv_check.py): WARN only: overlap and stretch from the tiled straw texture; flipped 20 % on double-sided straw cards (no baked map). Collapsed 0.0 %.
- Notes: Round 0 (before kiln): the first tufts read as wooden shingles; rebuilt as layered fringe strips with a fine-strand straw texture.
- Review round 1 sheets (review/hay_bale/round1.png, round1_clay.png): pending the fresh reviewer
- Optimize: skipped for the game copy (no Draco, no WebP: Godot imports PNG textures from the GLB)
- Export: GLB, export_apply off, copied to assets/props/hay_bale.glb

- Review round 1 (review/hay_bale/round1.png, round1_clay.png), fresh reviewer + own reading:
  1. every tile: straw cards hang as regular triangles (icicles, torn paper) with dark gaps → many narrower columns, continuous random lengths, two staggered layers per flake (blocking)
  2. side/back: identical sawtooth along the top edge of the end face → random lengths, less top flare (blocking)
  3. side/close: straw texture reads as wood grain → straighter, finer strands with breaks along them (blocking)
  4. front/q_right corners: top flake flares out like eaves → flare 0.55 → 0.2 (blocking)
  5. ropes stand proud of the straw with wide corner arcs → sink them in, tighter corners (detail)
  6. proportions: end face too square → 1.0 x 0.5 x 0.4 m like a small square bale (detail)
  7. a strip of the core shows under the bottom flake → bottom flake reaches the ground (detail)
  8. renders murky → harness lighting, not the asset (argued: studio sheet only)
  fixing all of the above, then round 2

- Round 1 fixes done (2026-11-11): sides rebuilt as overlapping narrow straw bundles (seven rows) and shingled top flakes; strand texture nearly straight with tone varying along each stalk; ropes sunk into the straw; 10914 tris.
- Review round 2 sheets: review/hay_bale/round2.png, round2_clay.png: sent to a fresh reviewer
- Review round 2 (fresh reviewer + own reading of clay close):
  1. top: near-black slivers: the loose stalks on top, thin single-sided blades seen from behind → loose stalks removed from the top (blocking)
  2. side/front: long dark diagonal whiskers past the outline → loose side stalks shorter, hanging down, fewer (blocking)
  3. side: ruler-straight row of tips under the top rope → top row heights and lengths varied more (detail)
  4. rope joint on the back → accepted: the twist seam of a closed loop, on the back, small (detail)
  5. ropes sit on the straw → accepted: they are sunk 2 cm already; detail
  6. ends use the same cards as the sides → accepted (detail)
  7. renders dark → review lighting only; the in-game shot is the check
  fixing the above, then round 3
- Review round 3 (fresh reviewer + own reading):
  1. top: flat square-cut chips standing up in rows like confetti → inner bands lie over the outer bands' roots, roots tapered, lying flat (blocking)
  2. end face top edge: dark sawtooth gap between the rope and the end straw (the top side row's roots had been jittered below the top) → top row roots only go up (blocking)
  3. ropes stand proud → ropes sunk 8 mm further, the straw pinched in under them (detail)
  4. rope seam on the back → accepted (detail)
  5. side cards read as thatch more than flakes → accepted for now (detail)
  fixing 1-3, then round 4
- Review round 4 (fresh reviewer 1): nothing blocking. Details: rope join line on the back; ropes end at the base rather than passing under (underside never seen); a few stiff blades at the top corners; rope rides over the end face's top layer; top chips less dense than the sides; fine stripes may shimmer; no pinch. Own reading: agree. Same sheets to fresh reviewer 2.

### Round 4, fresh reviewer 2 (same sheets)
Verdict: "Yes, as a solid draft." No blocking defects. Details noted for a later pass:
- A few stray straw cards stand off the end outline.
- The top rope sits on the straw instead of biting in.
- A faint ring seam where two vertical rope segments meet (clay back).
- The flake layers read weakly up close.
- The underside isn't shown in any view; the rope rings are closed loops, built under the bale.
Two fresh reviewers in a row found nothing blocking on the round 4 sheets. **REVIEW ROUNDS done.**

## Licenses
- All geometry and textures generated by script in this repo. blender-kiln (MIT) used for review tooling.

## Checkpoint
- Last completed step: REVIEW ROUNDS (two clean readings on round 4)
- Timestamp: 2026-11-11 18:40
