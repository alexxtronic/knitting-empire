# Axe — Production Log

## Config
- Type: prop (static, hand-held tool), game asset for Knitting Empire (Godot 4.7)
- Target: glTF/GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: balanced
- Style: stylised, hand-painted, chunky and toy-like (Alex's style images: bakery stall, yarn, scarecrow)
- Mode: auto

## Reference Image
- Path: art/world_assets/tools/reference_sheet.png (the six tools), ref_axe.png (this tool's cell)
- Brief (Alex, 2026-11-12): "When making the tools first prompt chatgpt in my chrome tab for a reference image to base it on in the style of the attached then use that reference image to generate the tool using the blender-kiln skill"
- Brief enrichment: short chunky hatchet; honey-orange handle with painted grain, gently curved, swelling to a rounded foot; dark blue-grey iron head with a pale worn cutting edge and chipped rim, a domed rivet on the cheek; the handle's end grain shows above the head; a cream cloth band with two red stripes on the lower handle, tied with a twine bow.
- Assumptions (auto mode): 0.62 m tall (a hatchet, enlarged a little to read in the game's high camera); reference camera is a three-quarter from slightly above; the far side mirrors the near side.
- Visual comparison: partial match (shape and palette follow the reference; painted wear on the iron and the cloth wrap are simpler)

## Prompts (copy-paste ready)
- Concept art (ChatGPT image generation, with Alex's three style images attached): "Generate an image: a reference sheet of six hand tools for a cozy farm and knitting game, in exactly the art style of the three attached images (chunky, soft, rounded 3D toy-like forms; warm saturated hand-painted wood with visible soft grain and chips; soft dark iron with gentle highlights; felt and cloth details; soft studio lighting on a plain white background with a faint shadow). Show these six tools as separate objects in a 3 by 2 grid, each fully visible, not overlapping, each seen from the same slight three-quarter side view, with no text or labels: 1) a garden hoe, 2) a round metal watering can with a rose spout, 3) hand sheep shears (blade shears with a sprung bow), 4) a shovel with a D-grip handle, 5) a wood axe, 6) a scythe with a curved blade and two grips. Wooden handles in the same honey-brown wood as the market stall, metal parts in the same dark soft iron as the lantern, and a small strip of red or cream cloth or twine wrapped on each handle."

## Intent (before the first primitive)
- Palette: main honey wood #d07a2e (grain light #f0a252, dark #9a521f); secondary dark iron #57545f; metal highlight worn edge #c8b9a8; accent red #c9544a (the two stripes, used once); cream cloth and twine #ecdcbc
- Materials: painted wood (rough 0.55), forged iron (rough 0.6, metallic 0.55), woven cloth band (rough 0.9), twine (rough 0.95), steel rivet (rough 0.35, metallic 0.85)
- Finishes: every edge rounded (no razor edges on the head); a pale, ragged worn band along the cutting edge and chips on the head's rim; end grain on the handle's top and foot; a rivet on each cheek; the striped band tied with a twine bow

## Source
- Method: scripted (Blender, art/world_assets/tools/build.py, helpers in kelib.py and craftlib.py)

## Pipeline
- Build (headless, scripted): scene ['model']; 5264 triangles; 0.22 x 0.097 x 0.633 m; front -Y, origin at the centre of the foot, 1 unit = 1 m
- Cleanup: built clean by script; normals recalculated per part; joined to one mesh
- Texturing: generated painted textures (numpy) in tex/: wood, end grain, iron (colour, normal, roughness), cloth band, twine
- Review round 1 (review/axe/round1.png, round1_clay.png), own reading before the first outside reviewer:
  1. every tile: handle far thinner than the reference (a pole, not a chunky toy handle) → radii up a third (blocking)
  2. top and foot: the cap discs stand out as flared lips → removed; the tube's own ends round off (blocking)
  3. wood reads as flat orange plastic, no grain → more contrast in the grain map, rougher (blocking)
  4. iron and rivets render near black → lighter base, less metallic (blocking)
  5. head thin next to the reference's chunky wedge → thicker cheeks and poll, a little longer (detail)
  6. too much handle above the head → 0.60 m tall, head higher (detail)
  fixing all of the above, then round 2 with a fresh reviewer
- Round 1 fixes done: 0.253 x 0.116 x 0.601 m
- Review round 2 (review/axe/round2.png, round2_clay.png), fresh reviewer + own reading:
  1. handle still a slim, nearly straight stick (about 1:10; the reference is about 1:6 with an S and a bulging foot) → fatter, more S, bigger foot (blocking)
  2. cutting edge is three straight facets → 72 points round each section so the bow is one curve (blocking)
  3. iron reads violet with orange rust smears → neutral blue-grey, fine speckle, a hint of rust only (blocking)
  4. band flush and invisible in clay; tie is thin rope with wide loops below the band → a thick bulging wrap; a short fat cloth knot with two stubby tails on its lower edge (blocking)
  5. handle top a chamfered stub without end grain → domes of end grain on both ends, matched to the section (detail)
  6. wood grain is ruled stripes → four swirl knots in the map, one repeat round the handle (detail)
  7. pale edge band narrow and even, missing on the blade's top and bottom → wider, more ragged, rim wear stronger toward the blade (detail)
  8. rope tail hangs clear of the handle → gone with the rope (detail)
  9. rivet lavender, no seat → warmer pale metal, a dark seat ring (detail)
  10. band weave faint → kept: the stripes read at game distance; weave normal as is (argued)
  11. foot underside not shown → own check below after the rebuild
  (own) q_right: the poll's end cap shows a rectangular inset → it is the cap fan's UV strip; watch in round 3
  fixing, then round 3 with a new reviewer
- Round 2 fixes done: 7548 triangles, 0.274 x 0.148 x 0.629 m. Own look at round3.png before sending it out found two build errors, fixed first: the rivet seat rings lay flat (K.torus takes degrees), and the end domes overhung the handle as lips (the tube's oval was turned a quarter: wide across the blade). Rebuilt as round 4.
- Review round 4 (review/axe/round4.png, round4_clay.png), a new reviewer + own reading:
  1. knot reads as a ball on two thin legs, standing off the handle → a flat knot with two short wide tails lying on the wood (blocking)
  2. handle is a straight tube that kinks into a boot-like foot → one continuous curve, the foot swelling gradually (blocking)
  3. band is a thick hard cuff with a stepped lower tier → thin wrapped cloth following the handle (blocking)
  4. handle top shows a grid, no end-grain rings, stub too tall → planar-mapped dome of end grain, 15 mm less stub (detail)
  5. foot flat with a lip ring → a deeper dome of end grain (detail)
  6. blade edge a razor fin, chrome-bright, needle tip at the bottom → thicker last stations, the edge's height eased in, rougher (detail)
  7. black ring round the rivet (not in the reference) → removed (detail)
  8. head a clean saturated navy → greyer, speckled, more mottle and rust (detail)
  9. wood more saturated and glossier than the reference → less saturated, rough 0.82 (detail)
  10. oval flat patch on the poll's end → an extra small first station, so the end rounds over (detail)
  fixing, then round 5 with a new reviewer
- Round 4 fixes done: 0.278 x 0.117 x 0.619 m
- Review round 5 (review/axe/round5.png, round5_clay.png), a new reviewer + own reading:
  1. handle a near-uniform tube; the reference is slim under the head and swells into a fat, sweeping club → radius 36 mm under the head to 64 mm near the foot, a 46 mm sweep (blocking; the last reshaping round: kiln stops proportion changes here)
  2. foot a flat cut → a deep rounded dome (blocking)
  3. head small against the handle, lower corner too high → about 12 % bigger, the beard dropped (blocking)
  4. band reads as a sleeve with a groove at knot level → accepted for now: the groove is the knot's shadow line; small in the game (detail)
  5. band edges machine-clean → accepted (detail; frayed edges are below game resolution)
  6. knot like tiny trousers → tails splayed apart (detail)
  7. dark slot on the poll → the tiny first station folded in on itself: removed (detail)
  8. grain faint → darker grain lines (detail)
  9. head flat navy → argued: speckle and mottle are in the map; the studio sheet is dark. Checked in the game shot instead
  10. speckled strip on the handle under the head → render noise in the clay tile; not in the colour tile (argued)
  11. handle top a flat disc → deeper dome (detail)
  fixing, then round 6 with a new reviewer
- Round 5 fixes done: 6740 triangles, 0.306 x 0.119 x 0.649 m (the foot's dome reaches 41 mm below the origin)
- Review round 6 (review/axe/round6.png, round6_clay.png), a new reviewer + own reading:
  1. "handle a thick, nearly uniform cylinder and too short; head a third of the height, a quarter in the reference" (blocking, says the reviewer) → NOT changed. The proportions have had their correction rounds (2, 4 and 5; kiln stops reshaping to the picture after two) and the reviewers now pull opposite ways: round 2 found it too slim, round 4 a kinked boot, round 5 a uniform tube, round 6 too thick. Measured on the build: 36 mm radius under the head, 64 mm above the foot, a 46 mm sweep. Left for Alex to judge against the reference.
  2. foot looks flat-cut in the front tiles → the dome is there (41 mm deep); the sheet's camera looks down on it. Underside not in any tile (unverified by render)
  3. band reads as a rigid sleeve with a step and a dark line under its lower edge (detail) → open
  4. dark recessed oval on the poll's end (detail) → open: the end cap's fan shades inward
  5. dark groove beside the cutting edge in the side tile (detail) → open: the last stations' thickness steps
  6. iron flatter than the reference, top edge of the head sharp (detail) → open
  7. speckled strip on the handle under the head in the clay close-up (detail) → render noise, not in the colour tile
  8. back of the band plain (detail) → accepted
  Rounds stop here at six without two clean readings in a row: no reviewer has passed it. What is still open is listed above for the hand-over.
- UV check (kiln tools/uv_check.py): 0 FAIL, 1 WARN: overlap 100 % and stretch 56 % from tiled, unbaked textures (expected, nothing baked); flipped 25.8 % (mirrored halves of tiled maps); collapsed 0.2 %.
- Optimize: skipped for the game copy (no Draco, no WebP: Godot imports PNG textures from the GLB)
- Export: GLB via kelib.finish, copied to assets/props/axe.glb; out/axe/axe.blend kept
- In the game: held in her right hand (scripts/main.gd _update_held_tool), checked in 47_tool_in_hand.png

## Licenses
- Reference image: generated in Alex's ChatGPT account from his own style images; used as reference only, not shipped as the model. (The hotbar icons in assets/icons are cut from it as stand-ins.)
- Textures: generated by the build script (numpy); nothing third-party.

## Checkpoint
- Last completed step: EXPORT (review stopped at round 6 with open details; waiting for Alex's look)
- Timestamp: 2026-11-12
