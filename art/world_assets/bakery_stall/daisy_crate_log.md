# Daisy crate — Production Log

## Config
- Type: prop (static), game asset for Knitting Empire (Godot 4.7)
- Target: glTF/GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: balanced
- Style: stylised, hand-painted, cozy
- Mode: auto

## Reference Image
- Path: in Alex's message of 2026-11-11 (not saved to disk)
- Brief: "Bakery stall for outside the bakery (the crate of daisies and ivy beside it)"
- Brief enrichment: Alex's reference art: a wooden crate of daisies with ivy trailing over it.
- Visual comparison: close match (by eye, scripted build)

## Intent (written after the first build: kiln was adopted mid-way, on Alex's request)
- Palette: main crate wood #cf9a5e; secondary ivy greens #3f7a2e/#5f9a38/#86b84a; accent daisy white #fbf7ee and yellow #f2b51c; soil #4a3324
- Materials: crate wood, soil, three ivy greens, petal, daisy eye, stem
- Finishes: slats with gaps and corner blocks, ivy trailing over the front, eleven daisies at different heights

## Source
- Method: scripted (Blender bakery_stall/build.py, helpers in art/world_assets/craftlib.py and kelib.py)

## Pipeline
- Build / import: 3476 triangles; 0.56 x 0.40 x 0.40 m; front -Y, origin at the centre of the base, 1 unit = 1 m
- Cleanup: built clean by script (no import); normals set per part
- Texturing: generated painted textures (numpy) saved to tex/, assigned per part
- UV check (kiln tools/uv_check.py): see the check at review time
- Notes: 
- Review round 1 sheets (review/daisy_crate/round1.png, round1_clay.png): pending the fresh reviewer
- Optimize: skipped for the game copy (no Draco, no WebP: Godot imports PNG textures from the GLB)
- Export: GLB, export_apply off, copied to assets/props/daisy_crate.glb

- Review round 1 (review/daisy_crate/round1.png, round1_clay.png), fresh reviewer + own reading:
  1. leaves are five-pointed stars, not ivy → lobed, heart-based ivy leaves (blocking)
  2. top leaves render black: faces into the soil or reversed → leaves built facing up, lifted clear of the soil (blocking)
  3. loose leaf cards at random angles, some past the rim → leaves in clumps round the stems, inside the rim (blocking)
  4. daisy heads all face the front, edge-on from behind → heads face up with a little random tilt (blocking)
  5. stems identical, straight, thin; planting sparse → curved, thicker stems, more daisies at varied heights (detail)
  6. trailing ivy four identical straight strands → varied number, length and sway (detail)
  7. notches on the corner posts → accepted (slat ends)
  8. soil speckle → render noise, not the material (argued)
  fixing all of the above, then round 2

- Round 1 fixes done (2026-11-11): five-lobed ivy leaves with a stalk notch, cupped, facing up, in seven clumps inside the rim; four trailing strands of different lengths over the front and the side, leaves hanging face-out; sixteen daisies facing up on curving, thicker stems.
- Review round 2 sheets: review/daisy_crate/round2.png, round2_clay.png: sent to a fresh reviewer
- Review round 2 (fresh reviewer + own reading):
  1. daisies read as yellow dots on sticks: small heads, big eye, leggy stems → larger white petals (16), smaller eye, more daisies, shorter stems (blocking)
  2. ivy reads as clover; trailing strands stiff and clear of the slats → pointed lobes and a longer tip lobe; strands drape close to the crate face (blocking)
  3. some leaves render black in clay (back faces) → leaves and petals two-sided (blocking)
  4. seams at the corner posts → accepted (detail)
  5. soil a thin slab, crate hollow through the gaps → soil fills the crate (detail)
  6. stray blocks on the soil: the corner posts stand 4 cm proud of the soil → corner posts end at the soil line (detail)
  7. knot swirl on a slat → knots off (detail)
  8. no ivy on the back → a strand over the back (detail)
  fixing the above, then round 3
- Review round 3 (fresh reviewer + own reading of clay side):
  1. leaves and petals near-black in places: their undersides, seen from the side and lit from above → leaf and petal normals point up on both faces, so they shade as tops (blocking)
  2. ivy strands straight rods starting from a leaf on the rim → each strand grows from the soil, over the rim and down the slats in a loose S, leaves along all of it (blocking)
  3. ivy reads as maple/star → shallower lobes (detail)
  4. crate wood flat → darker grain, stronger relief (detail)
  5. seams on the corner posts → accepted (detail)
  6. daisy heads all at one height → heights spread more (detail)
  fixing, then round 4
- Review round 4 (fresh reviewer): blocking: petals dark from most angles (only the tips light), spiky wispy petals, long bare stems like pins. Details: notches on the corner posts, stretched texture on a post foot, one bare vine arc on the side, wood plain, a few trailing leaves stand off the slats.
  → petals rounder and wider (12 per head), a little self-lit so they stay white in shade; 17 daisies on shorter stems tucked into the leaves. Round 5.

### Round 5 (fresh reviewer)
The petals are rebuilt: 12 rounded petals per head, emit 0.35, 17 heads.
Blocking (1), "verify first": petals render near-black in clay. Check: petals and leaves are two-sided (an up copy and a down copy, 1020 faces each), but the materials had backface culling off. Both copies drew and fought, and the GLB was marked doubleSided, so Godot would have done the same. The lit close shows white petals.
Fix: backface culling on for every crate material (the GLB is no longer doubleSided). The clay sheet still shows the fight, because review_sheet's clay material has no culling.
Details, for later: a bare ivy runner at the top left of the side view; a stray leaf by the back corner post; ivy standing off the slats; seams in the corner posts; the daisy foliage is flat cards; the back is sparse.
### Round 6
A fresh reviewer, told about the clay culling.

Round 6, fresh reviewer 1: nothing blocking ("Yes. Only detail-level polish is left").
Round 6, fresh reviewer 2: nothing blocking ("Nothing a player would notice from the game camera").
Shared details, for later: seams and steps where the slats meet the corner posts; ivy standing slightly off the slats; a few loose ivy bits past the corner; daisy foliage uses the ivy leaf; the underside isn't shown (the crate has a floor and feet).
Two fresh reviewers in a row found nothing blocking. **REVIEW ROUNDS done.**

## Licenses
- All geometry and textures generated by script in this repo. blender-kiln (MIT) used for review tooling.

## Checkpoint
- Last completed step: REVIEW ROUNDS (two clean readings on round 6)
- Timestamp: 2026-11-11 19:30
