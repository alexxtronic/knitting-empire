# Chalkboard sign — Production Log

## Config
- Type: prop (static), game asset for Knitting Empire (Godot 4.7)
- Target: glTF/GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: balanced
- Style: stylised, hand-painted, cozy
- Mode: auto

## Reference Image
- Path: in Alex's message of 2026-11-11 (not saved to disk)
- Brief: "Bakery stall for outside the bakery (its A-frame chalkboard)"
- Brief enrichment: Alex's reference art: A-frame chalkboard reading 'Fresh Croissants' with a croissant drawn on it.
- Visual comparison: close match (by eye, scripted build)

## Intent (written after the first build: kiln was adopted mid-way, on Alex's request)
- Palette: main slate #2e3a36; secondary frame wood #b5672e; accent chalk #f2eee2; metal hinge #2f2c2b
- Materials: slate (rough 0.95), frame wood (rough 0.65), chalk (rough 0.95), hinge iron (rough 0.5)
- Finishes: frame legs and rails on both boards, iron hinge across the top, chalk lettering and a croissant doodle

## Source
- Method: scripted (Blender bakery_stall/build.py, helpers in art/world_assets/craftlib.py and kelib.py)

## Pipeline
- Build / import: 6120 triangles; 0.56 x 0.51 x 0.86 m; front -Y, origin at the centre of the base, 1 unit = 1 m
- Cleanup: built clean by script (no import); normals set per part
- Texturing: generated painted textures (numpy) saved to tex/, assigned per part
- UV check (kiln tools/uv_check.py): Collapsed 2.4 % (FAIL) was the beam caps and the font mesh (no UVs): beam caps fixed in craftlib, lettering box-projected; now 0.0 %. WARN only.
- Notes: 'Fresh Croissants' is player-facing draft text from the reference, awaiting Alex's approval.
- Review round 1 sheets (review/chalkboard_sign/round1.png, round1_clay.png): pending the fresh reviewer
- Optimize: skipped for the game copy (no Draco, no WebP: Godot imports PNG textures from the GLB)
- Export: GLB, export_apply off, copied to assets/props/chalkboard_sign.glb

- Review round 1 (review/chalkboard_sign/round1.png, round1_clay.png), fresh reviewer + own reading:
  1. lettering is raised extruded type, reads as vinyl not chalk → flat, grainy chalk texture, slightly see-through (blocking)
  2. the croissant doodle is a symmetric arch with flat-cut ends → a crescent with pointed horns curling down (blocking)
  3. frame one flat glossy orange, reads as plastic → browner, rougher wood with visible grain (blocking)
  4. bottom of the board empty → accepted (room for the chalk smudges), drawing moved down a little (detail)
  5. frame stock round dowels → boxier stock (detail)
  6. stiles cross past each other at the apex → stop at the hinge (detail)
  7/8. back board blank, no smudges → chalk ghosting on the slate texture (detail)
  fixing all of the above, then round 2

- Round 1 fixes done (2026-11-11): chalk lettering is a near-flat streaky chalk texture; crescent doodle with sharp horns curling down; chalk dust smudges and wipe marks in the slate; browner, rougher square stock; stiles stop at the apex under the hinge.
- Review round 2 sheets: review/chalkboard_sign/round2.png, round2_clay.png: sent to a fresh reviewer
- Review round 2 (fresh reviewer + own reading):
  1. lettering is clean typeset font, reads as vinyl → each letter placed separately with a wobble in angle, size and baseline, chalk texture (blocking)
  2. croissant doodle hair-thin, reads as a frown → bigger, thicker strokes, plumper, lower on the board (blocking)
  3. glossy black rod across the top → removed; two small matte iron hinges at the stile tops (blocking)
  4. clay: sawtooth along the board's edge where the slate meets the leg → slate kept clear inside the frame (detail)
  5. back face blank → a croissant doodle and stars on the back (no words) (detail)
  6. frame thin for the style → thicker stock (detail)
  7. nothing holds the legs apart → a cord between the frames each side (detail)
  8. bottom third empty → drawing lower and bigger (detail)
  9. rails stick past the stiles as lips → rails end at the stiles (detail)
  fixing the above, then round 3
- Review round 3 (fresh reviewer 1): nothing blocking. Details: the croissant doodle has relief and reads as wire up close while the letters are flat; lettering still fairly clean; a dark strip where the board meets the right stile and the top rail (clay); hinge caps show as dark specks. Own reading: agree; the lettering now wobbles per letter and reads the right way round. Same sheets sent to fresh reviewer 2.
- Review round 3 (fresh reviewer 2): blocking: the croissant doodle is raised tubes that catch highlights like wire, and a flat-bottomed arch reading as a moustache; its relief poked through to the inner face of the back board. Details: lettering still a font; dark strip at the board's right edge; wood flat; hinge blocks stick up past the top rail.
  → doodle and stars redrawn as flat chalk ribbons on the board (no relief, nothing through the board); a pale rubbed-chalk fill inside the crescent; deeper crescent with a curved underside; hinges lowered below the rail top. Lettering and wood accepted (detail). Round 4.
- Review round 4 (fresh reviewer): blocking: the croissant still reads as a frown or moustache, and the fill looked blotchy; the close tile cuts the drawing off (the review tool's framing). Details: lettering still a clean typeface, raised in clay; jagged seam at the board's right edge; small nubs at the top corners; cord ends on the back board's face; wood plain.
  → croissant redrawn as five overlapping rounded rolls along a downturned arc, the middle one biggest, with pointed tips (the usual chalk-drawn croissant), each roll outlined and lightly filled; letters made flat (no extrusion) with a shaky outline. Round 5.

### Round 5 (fresh reviewer)
Blocking (1): the croissant doodle (five rolls on an arc) read as a crown, balloons or lollipops.
Details: the clay sheet shows faint shapes that look like a stale bump map. There is no bump map on the slate: these are the outlines of the flat chalk geometry, catching light in clay. Also noted: the lettering is a little even; there are no visible hinges (there are tabs); the cords look like rungs; the bottom rail ends are boxy; the wood is clean.
Fixes for round 6: the croissant is redrawn as one crescent. Its fat middle tapers to thin horns that curl in and down, and four bowed fold lines split it into five rolls, with a brighter rub-in (fill 0.45). It is 25% bigger on the front and 17% bigger on the back. Two intermediate tries were checked and dropped: a smooth dome read as a frown, and tall scallops read as a tiara.

Round 6, fresh reviewer 1: nothing blocking. The croissant was its most visible weakness ("could pass for a crown, a shell or a bell").
Round 6, fresh reviewer 2: blocking (1). Without the caption the croissant reads as a dome, crown or jellyfish: an open arch, with no line closing the base and tips flicking outward. Details: the lettering looks typeset, an empty band between text and drawing, the wood is plain, a speck and a jagged slate edge in clay only.
Fixes for round 7:
- The belly is closed and bowed slightly down, so the croissant is a lens, not an arch.
- Each horn curls down and back in under the body.
- The front drawing moves up (0.33 to 0.38 of the board) to close the empty band.

### Round 7 (two fresh reviewers in parallel)
Reviewer A found nothing blocking. Reviewer B: blocking (1). The croissant is a dome on a straight base line with little curls, and without the caption (back face) it reads as a cloud, a loaf or a shell. It needs a crescent whose horns taper and curve down, and no straight base.
Shared details: the lettering looks typeset (even strokes); the wood is plain; specks and a jagged slate edge show in clay only; the bottom rail ends read as stubs from the side.
Fix for round 8 (the last round allowed for a prop): a true crescent, the band inside circle A (r 0.1) and outside circle B (r 0.085, 0.05 lower). It is fattest on top and tapers to two downward horns where the circles cross, with no base line. Four bowed folds split it into five rolls, the outer edge is scalloped per roll, and the whole is squashed (x 1.1, y 0.72) so it lies wider than tall rather than reading as a horseshoe.

### Round 8 (two fresh reviewers in parallel; the last round allowed for a prop)
Reviewer A found nothing blocking: "with the caption covered, the scalloped arch still reads as a croissant". Its notes: pointed tips would settle it, the stars look like pentagrams, the lettering looks typeset.
Reviewer B: blocking (2). The horns end bluntly, so the drawing reads as a rainbow or a crescent moon; and on the back, the moon with crossed-line stars reads as moon-and-pentagrams.
Fixes after the cap (`review/chalkboard_sign/round8b.png`, checked by me, not by a fresh reviewer):
- Each horn now carries on round circle A, down and in, narrowing to a point (`flat_stroke(taper=True)`).
- The stars are plain ten-point outlines with no crossing lines.
**Stopped at the round cap with a split verdict.** Open for Alex: is the croissant doodle clear enough? Also the lettering, which every reviewer called "typeset, not hand-chalked". Both are listed in the hand-off.

### Owner
2026-11-11: Alex approved the round 8b croissant drawing ("Keep it"). Later the same day he OK'd the "Fresh Croissants" wording and the shop names (Pen Fence, Bakery Stall, Chalkboard Sign, Daisy Crate).

## Licenses
- All geometry and textures generated by script in this repo. blender-kiln (MIT) used for review tooling.

## Checkpoint
- Last completed step: REVIEW ROUNDS stopped at the 8-round cap (split verdict; post-cap fixes in round8b)
- Timestamp: 2026-11-11 20:05
