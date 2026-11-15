# lantern — Production Log

## Config
- Type: prop (hand-held, static mesh), game asset for Knitting Empire (Godot 4.7)
- Target: GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: balanced (under about 12,000 triangles, one 1024 px texture set)
- Style: stylised, hand-painted, chunky and toy-like (the park bench and the mailbox are the template)
- Mode: auto (built headless by script; no Blender MCP session, so the build prints its scene line)

## Reference Image
- Path: ref/lantern.png (725 x 724 px, white background, one three-quarter view)
- Brief: a hand-held storm lantern Nora carries, copied from the reference as closely as possible; 0.30 m
  from the bottom of the base to the top of the ring, about 0.15 m wide; origin at the inside top of the
  ring handle so it hangs below her hand; globe, vent slots and flame emissive.
- Assumptions (one photo cannot say them):
  - Real size: 0.300 m tall (given). Read at 0.424 mm a pixel across and 0.4455 mm a pixel of image
    height up the axis (the camera looks down, so heights are foreshortened by cos 18 deg).
  - Camera: about 18 deg above (the ellipses of the base, burner ring and cap read 14 to 21 deg, lowest
    at the top: a camera roughly 2.5 m away and 0.9 m up), turned about 18 deg to the lantern's left
    (the left arm sits 28 px lower in the picture than the right; the block shows its left face).
  - Unseen: the back, the underside, and the right side behind the knob. The back repeats the front
    (rivets on both faces of each arm and of the block, wires crossing behind as in front, slots all
    round). The underside is a plain closed disc. Nothing else is invented.
- Visual comparison: scripted build, measured against the reference from its own camera (review.py)

## Intent
- Palette (sampled from enlarged crops of the reference, 10th / 50th / 90th luminance percentiles):
  - main: cast iron, dark purplish brown #40302f, mid #58444a, lit tops a purple grey #7a6670
  - secondary: wear, a warm orange on edges and scuffed tops #8e4f2c to #d6905a
  - metal accent: polished brass / gold #b06c1e, #d28f33, #f8c964 (rivets, burner, knob, wick tube)
  - light: amber glass #d97f2d to #ffcb58; flame #fff3a6 core, #fca21c tip; slots #ffe14a to #f07f0e
- Materials (one per physical material): painted cast iron (rough 0.56, worn edges smoother), brass
  (metallic, rough 0.27), amber glass (its own surface: glossy, emissive), flame and slot light (emissive).
- Finishes: every edge rounded (fillets on all turned profiles, 3-segment bevels on arms and block);
  orange wear along edges and scuffed over the cap, base steps, arms and ring; dome brass rivets at both
  ends of each arm and on the block; a knurled wick knob; a stepped brass burner under the flame.

## Inventory (read from 3x and 4x crops of the reference; how each part meets the next)
- base: a fat round foot (130 mm across, rounded rim), a narrower second step, a shallow cone up to a
  short collar with a bead round its foot → Base (one turned profile, closed underneath)
- burner: a brass lip ring on the collar, two smaller stepped discs inside it, a wick tube standing in
  the middle → Burner, WickTube; the lip sits on the collar, the tube enters the top disc
- globe: fat amber glass, widest below its middle (104 mm), narrowing to the top; its foot sits in the
  brass lip, its neck enters the flange above → Globe
- flame: a teardrop on the wick tube, pale yellow core, orange tip → Flame, wraps the tube's top
- flange: a thick rounded ring over the globe → Flange (closed underneath, the globe enters it)
- vent collar: a short drum with stadium slots all round (three show), each a pocket with a glowing
  back → VentStrip (10 slots, real pockets), VentGlow
- cap: a low dome with a thick rounded rim that overhangs the collar → Cap
- block: a small upright block with rounded top corners on the cap's crown, a brass rivet on its face;
  SUNK into the dome → Block, BlockRivet (front and back)
- ring handle: a big round ring (84 mm across, 14 mm thick) standing in the arms' plane, passing
  THROUGH the block → Ring
- side arms: two thick flat bars with rounded edges; each leaves the vent collar as a short shoulder,
  turns down round a soft corner, bows outward to its widest beside the globe's widest, then sweeps in
  round a big curve to a foot that ENTERS the base collar; a dome brass rivet at the top corner and on
  the foot, front (and back) → Arm_L, Arm_R, 8 rivets
- wires: two thin iron wires crossing in an X in front of the globe (and behind it), each a tilted loop
  from high on one arm to low on the other; ends ENTER the arms' inner faces; one passes over the
  other at the crossing → Wire_A, Wire_B
- wick knob: a brass boss on the collar, a short stem, a knurled wheel; low on the right, turned about
  36 deg toward the front → KnobBoss, KnobStem, KnobWheel

## Source
- Method: scripted (Blender 5.2 headless, build.py; helpers in ../kelib.py and ../bench_park/build.py).
  Kiln's texturing phase proposes scanned Poly Haven sets first; this project's approved look is
  hand-painted procedural shaders baked to the UVs (bench, mailbox), so that is what is used. Nothing
  downloaded, no AI generation.

## Pipeline
- Scene (headless build, rule 1; the script prints it): 29 parts: base, burner, wick_tube, flame, globe,
  liner (the glass's far wall), flange, vent, vent_glow, cap, block, ring, 2 arms, 10 rivets, 2 wires,
  knob boss, stem and wheel. Joined into one mesh, `lantern`.
- SOURCE / IMPORT (the script builds at size): 0.163 x 0.131 x 0.300 m; front -Y; 1 unit = 1 m; origin
  at the inside top of the ring (base at z = -0.285, ring top at +0.015). Turned parts are lathed from
  profiles with every corner filleted; arms and block are outlines given depth and a 3-segment bevel;
  the vent drum has ten real slot pockets; the wires are tubes laid on the glass.
- CLEANUP: built clean by script (no import to clean): transforms applied on join, no merge needed,
  normals out on every part (checked in clay, where a face seen from behind renders red). Attachment
  check (kiln, reference-fidelity 3, extended to count a part that cuts into another as attached):
  "every part touches another". Rivets, arm ends, block, ring, wick tube and knob all ENTER their
  neighbour; the wires rest on the glass 0.3 mm off it (a real lantern's globe guard does the same).
- Measured rounds against the reference (review.py renders out/lantern.glb from the reference's camera:
  18 deg above, 18 deg to its left, 2.5 m; outlines cut to the same height; drafts at 512 px):
  - v0: silhouette IoU 0.877 with the ring's hole wrongly counted as lantern in the reference's
    cut-out; with the holes seeded as background the same shape reads 0.916. Top band +1.7 %, second
    (cap) -6.6 %, the rest within 3 %.
  - v1 (correction round 1): cap dome 3 mm taller with a thinner rim, arms 2 mm wider inward and 2 mm
    deeper, ring tube 15 mm, rivets 12 mm, knob wheel 25 mm: 0.918. Kept.
  - v2 (correction round 2): arms 1.5 mm wider inward again, 22 mm deep: 0.921. Kept. Reshaping to the
    photo stops here (two rounds). What is left in the overlay is the reference leaning about 1 deg to
    its right (its cap and ring sit 5 to 8 px right of its base); the model stands straight.
- TEXTURING: one procedural Cycles node tree paints everything, each material where its parts are
  tagged (point attributes on the parts before the join): cast iron (blotched dark purple-brown, lit
  tops lighter, brush strokes that run round the turned parts, up the arms and round the ring, wear to
  orange along edges broken into long dashes), brass, amber glass, the flame, the slots' light. Baked on
  the CPU to a 1024 px colour (with the glass's alpha), normal, emission and ORM map on one Smart UV
  atlas. Two materials read them: lantern_mat (opaque) and lantern_glass (alpha blend).
  - Where the wear goes: Cycles' Bevel node gives the arms' and block's edges; on the turned parts it
    answered weakly on the big fillets and at inside corners too (and with few samples its own noise
    read as wear), so their outward corners are marked on the mesh instead (`wearv`, from the profile)
    and only what stands open (AO) wears.
  - The glass: tried as one alpha-blended shell (the flame washed out over a white background, pale
    peach), then double-sided, then as built: a see-through near wall (alpha 0.34 at the flame's height
    to 0.64 above and below, more where the window shines) over an opaque, emissive far wall facing
    inward (`liner`, part of lantern_mat). Through the near wall you always end on amber, never on the
    background, and the flame, wick and burner stand in front of it. What gives light is painted nearly
    black and carried by the emission map, so it reads the same by day and by night.
- UV check (kiln tools/uv_check.py, round 1 build): ok, used 41.5 %, overlap 0.0 %, stretch 0.0 %,
  collapsed 0.0 %, flipped 0.0 %; 0 FAIL, 0 WARN.
- Review round 1 (review/round1: sheet.png, sheet_clay.png, side_by_side.png, kiln_sheet.png), my own
  reading, clay first:
  1. clay top tile: a red (back-facing) hairline between the vent drum and the flange, a bright ring
     there in colour. Ray-probed: the drum's bottom edge was a straight chord across each 36 deg sector,
     1.6 mm inside the drum (the triangulator had joined the extra points along the edge into slivers)
     → each sector rebuilt as three flat panels; probe finds no back face.
  2. ref and low tiles: the flame is a pale cream blob with a nipple, against the reference's yellow
     teardrop with a hot core → fuller teardrop; foot orange, body yellow, small pale core, orange tip;
     the flame's and the slots' paint dimmed to 10 % so daylight doesn't bleach their emission.
  3. ref and low tiles: wear too heavy and too even on the base and flange (a striped copper look)
     → more breakup (dashes and patches start from nothing), a duller orange.
  4. side tile: the arms read thin from the side (20 mm) against the reference's pillowy bars → 22 mm.
  5. kiln_sheet.png: kiln's sheet puts its floor at z = 0 and this model hangs below its origin, so the
     floor cut it off at the ring (it did show the emission working in the dark) → from round 2 the kiln
     sheet is rendered from a floor-standing copy made for the review only.
  6. back tile (detail): the wires cross off-centre at the back, as at the front seen square on: the
     cage is turned 18 deg to face the reference's camera. Kept, see "could not match".
  fixed, rebuilt at 1024 px; round 2 next

- Review round 2 (review/round2: sheet.png, sheet_clay.png, sheet_night.png, side_by_side.png, and
  kiln_sheet.png / kiln_sheet_clay.png from the floor-standing copy), my own reading, clay first:
  checked in clay: ring centred on the block, block on the crown, rivets level on both arms and on
  both faces, knob square on the collar, slots evenly spaced, no red (back-facing) face in any tile,
  nothing poking through. Found:
  1. night tiles: the window's reflection painted on the glass glows as a pale grey patch in the dark
     → where it shines the near wall now gives the far wall's amber light, and the shine is paint only.
  2. ref tile against the reference: the wires are thin and dark (3.8 mm, the reference's about 5)
     → 5 mm, the upper wire 4.8 mm clear of the lower at the crossing.
  3. top tile: the cap's top is plain where the reference is brushed through to orange in from the rim;
     front and q tiles: the arms' faces are plain between their edges → the cap's wear carried further
     up the dome, and a few long scuffs along the brush strokes out on every iron face.
  4. side_by_side: the glass reads golden against the reference's deeper orange → amber a shade deeper.
  5. uv check and export audit repeated on this build: ok, 0 FAIL, 0 WARN; AUDIT PASS.
  fixed, rebuilt at 1024 px; round 3 next

- Review round 3 (review/round3, rendered from the shipped file: sheet.png, sheet_clay.png,
  sheet_night.png, side_by_side.png, overlay.png, under.png, under_clay.png, kiln_sheet.png,
  kiln_sheet_clay.png), my own reading, clay first. Checked: silhouette from front and three-quarter;
  proportions against the reference (IoU 0.921, the same as before the surface rounds, so nothing
  drifted); every material present and none left grey; no razor edge; the finishes in the close-ups
  (wear, rivets, knurling, burner steps); the palette (one accent, brass); nothing floating or poking
  through; the clay sheet's assembly (centred, level, mirrored); the back (rivets, slots, the wires'
  second crossing); the underside (closed, painted, no back face). Nothing blocking found.
  Details left as they are:
  1. night tiles: the window's reflection is still a slightly brighter patch of amber in the dark.
  2. the flame is a turned teardrop coloured by height (orange foot, yellow body, pale core, orange
     tip); the reference's has a separate bright core inside it and a soft halo on the glass.
  3. the glass is a little more golden and less see-through-looking than the reference's.
- Inventory, ticked on the ref tile beside the same crop of the reference: base (foot, second step,
  cone, collar and bead) present; burner (lip, two discs, wick tube) present; globe present, 104 mm;
  flame present, simpler than drawn; flange present; vent collar with three slots showing present; cap
  present; block and its rivet present; ring through the block present; both arms with a rivet top and
  bottom present; the X of wires present and centred from the reference's camera; knob (boss, stem,
  knurled wheel) present, low on the right.
- Reviewers: my own reading each round, no fresh reviewer subagents (as with the earlier props, and as
  the brief for this asset allowed). Kiln asks for a new reviewer who knows nothing of the build each
  round: that part of the method was NOT followed.
- Optimize: skipped for the game copy (no Draco, no WebP, no simplify): Godot cannot import Draco.
- Export audit (audit.py, reads the GLB without Blender): AUDIT PASS. No extensions used (no Draco, no
  emissive-strength), one node `lantern` with identity transform, 11,164 triangles (lantern_mat 10,460,
  lantern_glass 704), bounding box 0.163 x 0.300 x 0.131 m in glTF's axes (y from -0.285 to +0.015),
  both materials single-sided with the emission map at factor 1, lantern_glass alphaMode BLEND; four
  1024 px PNGs embedded (colour RGBA, normal, emission, ORM). No procedural node left in the exported
  materials (rule 19): they read image textures only. export_apply is off (rule 18; every modifier is
  applied by the script before the join).
- UV check on the shipped file: ok, used 41 %, overlap 0.0 %, stretch 0.0 %, collapsed 0.0 %,
  flipped 0.0 %; 0 FAIL, 0 WARN.
- Export: out/lantern.glb, 2.8 MB, copied by the script to assets/props/lantern.glb (identical bytes).
  out/lantern.blend and out/lantern_shaders.blend kept (rule 7). Not imported into Godot and not wired
  into the game by this session: no .import file, no light bake, no furniture.json line.
- Naming: the project's own (object `lantern`, materials `lantern_mat` and `lantern_glass`, maps
  `lantern_colour`, `lantern_n`, `lantern_emit`, `lantern_orm`), not kiln's PascalCase prefixes.

## Could not match in the reference
- The reference is not one consistent object: its arms and block are seen from about 18 deg to the left
  of the front, but its X of wires and its middle slot face the camera. The model keeps the arms and
  the ring in one plane (left and right of the front) and turns the wire cage 18 deg (WIRE_TURN) so the
  X is centred from the reference's camera; seen square on from the front the X sits about 17 mm left
  of centre. The slots are not turned (one faces the front).
- The reference leans about 1 deg to its right; the model stands straight.
- The wires lie on the glass all the way round (a globe guard); in the reference their ends vanish
  behind the arms, and where they go is not shown.
- Truly transparent glass with the painted highlights and the soft halo round the flame: the globe is a
  see-through near wall over an opaque glowing far wall instead.
- The reference's left arm reads thinner than its right (56 px against 65); both are the same here.

## For whoever wires it into the game
- Parent it at its origin: the inside top of the ring. It hangs along -Y in Godot (Z up in Blender).
- lantern_glass is alpha-blended. If it sorts badly against something, switching its transparency off
  in Godot gives a painted amber globe (the flame then hides behind it).
- Emission is at glTF's plain factor 1: raise `emission_energy_multiplier` on both materials for more
  glow; an OmniLight at about (0, -0.175, 0) in Godot's axes sits in the flame.
- If it joins the baked props (Lighting.BAKED), run art/world_assets/light_bake for it after any rebuild.

## Licences
All geometry and textures generated by the script. No third-party assets.

## Checkpoint
- Step: EXPORT done (CONFIG, BRIEF, SOURCE/IMPORT, CLEANUP, TEXTURING, three review rounds, export
  audit, UV check); OPTIMIZE skipped by design; RIG and ANIMATE do not apply. Waiting for the wiring
  session and for Alex's review.
- Time: 2026-11-15
