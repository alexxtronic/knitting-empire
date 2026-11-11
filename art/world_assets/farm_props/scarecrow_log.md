# Scarecrow — Production Log

## Config
- Type: prop (static), game asset for Knitting Empire (Godot 4.7)
- Target: glTF/GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: balanced
- Style: stylised, hand-painted, cozy
- Mode: auto

## Reference Image
- Path: in Alex's message of 2026-11-11 (not saved to disk)
- Brief: "Scarecrow"
- Brief enrichment: Alex's reference art: straw hat with red band and sunflower; burlap head, closed happy eyes, stitched smile and seam; red/orange plaid shirt; blue overalls with pocket, buttons, green and orange patches; straw at cuffs, collar and hem; wooden post and arm pole.
- Visual comparison: close match (by eye, scripted build)

## Intent (written after the first build: kiln was adopted mid-way, on Alex's request)
- Palette: main plaid red/orange #cf4a2c/#ef8a33; secondary denim #5f6f9a; accent sunflower yellow #f7c21c; burlap #e3c48e; wood #c56f2c
- Materials: plaid flannel, denim, burlap face (texture with ink features), straw hat weave, straw, wood post, red band, buttons
- Finishes: straw at cuffs, collar, hem and under the hat; stitched seam and smile; X-stitched buttons; patches and pocket

## Source
- Method: scripted (Blender farm_props/build.py, helpers in art/world_assets/craftlib.py and kelib.py)

## Pipeline
- Build / import: 5772 triangles; about 1.5 m arm span x 1.75 m tall; front -Y, origin at the centre of the base, 1 unit = 1 m
- Cleanup: built clean by script (no import); normals set per part
- Texturing: generated painted textures (numpy) saved to tex/, assigned per part
- UV check (kiln tools/uv_check.py): WARN only (tiled cloth textures). Collapsed 9.9 % (FAIL) was tube end caps (sleeves, cuffs, legs): fixed in craftlib.tube with planar cap UVs, now 0.0 %.
- Notes: Before kiln: weave made finer (it read as a checkerboard), face features lowered and bolder, hair shortened so the eyes show.
- Review round 1 sheets (review/scarecrow/round1.png, round1_clay.png): pending the fresh reviewer
- Optimize: skipped for the game copy (no Draco, no WebP: Godot imports PNG textures from the GLB)
- Export: GLB, export_apply off, copied to assets/props/scarecrow.glb

- Review round 1 (review/scarecrow/round1.png, round1_clay.png), fresh reviewer + own reading:
  1. back tiles: the arm pole shows through the back of both sleeves, a stub at the neck → pole centred in the sleeves and thinner, post ends inside the head (blocking)
  2. front/close: the hat brim hides the eyes from a top-down camera → features lower and larger, hat raised (blocking)
  3. clay side: the bib floats off the chest, straps stop at the collar → bib shaped to the chest, straps over the shoulders to the back (blocking)
  4. all tiles: post and pole flat saturated orange, read as plastic → weathered brown wood with grain (blocking)
  5. knee patches stand off the legs → onto the leg surface (detail)
  6. straw at cuffs/collar/hem: big flat shards, a starburst at the cuffs → thinner, more, less splayed (detail)
  7. hat crown a smooth bowler dome → flatter-topped crown (detail)
  8. checker weave may shimmer → weaker weave on the hat (detail)
  9. cuff buttons not in the reference → removed (detail)
  10. back of head plain → accepted
  fixing all of the above, then round 2

- Round 1 fixes done (2026-11-11): pole centred in the sleeves (0.065 thick), post stops inside the head; face lower, hat raised 0.03; bib, pocket, straps (over the shoulders to the back) and patches laid on the cloth by ray casting; weathered brown wood; thinner, denser straw; flatter crown; cuff buttons removed.
- Review round 2 sheets: review/scarecrow/round2.png, round2_clay.png: sent to a fresh reviewer
- Review round 2 (fresh reviewer + own reading):
  1. front: the red hat band ends in a tapered spike standing off the crown (a closed tube's seam) → band rebuilt as a short cylinder round the crown (blocking)
  2. side: the cuff straw seen end-on makes a big spiky disc like a second sunflower → cuff straw droops downward and is shorter; pole shortened (blocking)
  3. front/close: pale wavy patch on the face (mottle too coarse) → mottle weaker and finer (detail)
  4. hat weave like graph paper, brim zigzag razor-sharp → finer weave, softer, fewer brim waves (detail)
  5. straw all one size → lengths and angles varied more (detail)
  6. post crisp box → rounder corners (detail)
  7. back of the overalls plain → a patch on the seat (detail)
  fixing the above, then round 3
- Review round 3 (fresh reviewer + own reading of the close tile and the face texture):
  1. darker patch with a curved edge on the upper right of the head, in clay too → argued: it is the hat brim's cast shadow (the key light is upper left); checked the face texture (clean, no patch) and the head mesh (a smooth lathe; the normal map is weave and ink only). Not a defect.
  2. brim edge faceted along the wave → 72 steps round the brim instead of 48 (detail)
  3. crumpled shoulder seams where sleeve meets shirt → accepted (detail)
  4. straw tufts are flat cards → accepted at this size (detail)
  5. side tile: the arm pole's end with straw round it reads as a disc → accepted: true geometry, one angle (detail)
  no blocking defect left; round 4 for the brim, then a fresh reading
- Review round 4 (fresh reviewer 1): nothing blocking. Details: pocket reads as a third patch (no stitching); dark line along the brim edge; straw spiky; side view shows the sleeve end like a badge; a few straw spikes under the brim; plain back of the head. Own reading: agree. Same sheets to fresh reviewer 2.

### Round 4, fresh reviewer 2 (same sheets)
Blocking (1): the head looks split, with a smooth lower face and a rough, darker top and back.
**Argued, with evidence:** this is the brim's cast shadow from the key light, not the texture. The same sheet, re-rendered with shadows off (`review/scarecrow/round4_noshadow_clay_close.png` and `round4_noshadow_close.png`), shows the head as one even surface. The "rough" look is EEVEE noise inside the shadow. Round 2 argued the same and checked the texture and the mesh then. The game's sun casts the same brim shadow, as a real hat would.
Details, for later: the crown is a plain cylinder; the straw tufts are cones with sharp tips; the collar tie isn't in the brief (kept, as it hides the neck join); a pale ragged band on the legs, side view; the foot of the post is a flat cut (it is sunk into the ground).
Two fresh reviewers in a row found nothing blocking that stands. **REVIEW ROUNDS done.**

## Licenses
- All geometry and textures generated by script in this repo. blender-kiln (MIT) used for review tooling.

## Checkpoint
- Last completed step: REVIEW ROUNDS (two clean readings on round 4)
- Timestamp: 2026-11-11 18:40
