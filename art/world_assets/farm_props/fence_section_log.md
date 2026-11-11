# Fence (post, rails, section) — Production Log

## Config
- Type: prop (static), game asset for Knitting Empire (Godot 4.7)
- Target: glTF/GLB in assets/props/, uncompressed (Godot cannot import Draco)
- Tier: balanced
- Style: stylised, hand-painted, cozy
- Mode: auto

## Reference Image
- Path: in Alex's message of 2026-11-11 (not saved to disk)
- Brief: "Fence for things like the sheep pen and any future sheep pen expansions"
- Brief enrichment: Alex's reference art: chunky square posts with swirl end grain, two wavy rails, silver bolts.
- Visual comparison: close match (by eye, scripted build)

## Intent (written after the first build: kiln was adopted mid-way, on Alex's request)
- Palette: main warm orange-brown wood #c56f2c; secondary end grain #d38a48; metal silver bolts #c3c8cf
- Materials: painted plank wood (rough 0.6), end-grain cap (rough 0.6), steel bolts (rough 0.28)
- Finishes: bevelled superellipse posts and rails; swirl end grain on each post top; two bolts per rail on both faces

## Source
- Method: scripted (Blender farm_props/build.py, helpers in art/world_assets/craftlib.py and kelib.py)

## Pipeline
- Build / import: post 498, rails 624, section 1620 triangles; post 0.15 x 0.15 x 1.0 m; rails 1 m from x = 0 at 0.42 and 0.74 m; section 1.15 x 0.15 x 1.0 m; front -Y, origin at the centre of the base, 1 unit = 1 m
- Cleanup: built clean by script (no import); normals set per part
- Texturing: generated painted textures (numpy) saved to tex/, assigned per part
- UV check (kiln tools/uv_check.py): WARN only: overlap 100 % and stretch about 39 % come from tiled, unbaked wood textures (expected, nothing baked). Collapsed 5.7 % (FAIL) was the beam end caps' one-row fan UVs: fixed in craftlib.beam with planar cap UVs, now 0.0 %.
- Notes: Game: World.build_pen places fence_post at every post point (one per corner) and fence_rails stretched span to span; fence_section is the buyable 'Pen Fence' item.
- Review round 1 (review/fence_section/round1.png, round1_clay.png): pending the fresh reviewer
- Optimize: skipped for the game copy (no Draco, no WebP: Godot imports PNG textures from the GLB)
- Export: GLB, export_apply off, copied to assets/props/fence_section.glb

- Review round 1 (review/fence_section/round1.png, round1_clay.png), fresh reviewer + own reading:
  1. close/q tiles: the end-grain cap is a square lid that overhangs the rounded post, and its swirl doesn't read → a cap cut to the post's own rounded outline, with stronger rings (blocking)
  2. all tiles: one glossy saturated orange, reads as plastic → browner, rougher wood with stronger painted grain (blocking)
  3. front: posts seem to splay → argued: both posts are exactly vertical (x constant along each post); the 9-degree front camera's perspective keystones them
  4. post bottoms cut differently → same perspective, argued
  5. right post's lower bolt below its rail's centre → the rail wave now dies out at both ends, so rails meet the bolts level (detail)
  6. bolts don't pass through the rails → argued: the rails run into the posts to their centres, so the through-bolts do cross them; it matches the reference
  7. a curved highlight on the post face → shading of the rounded corner, accepted
  fixing the above, then round 2

- Round 1 fixes done (2026-11-11): end grain is now a flush cap cut to the post outline with a visible spiral; browner, rougher wood with stronger grain; the rail wave fades out at the posts. Splaying posts: camera perspective, accepted.
- Review round 2 sheets: review/fence_section/round2.png, round2_clay.png: sent to a fresh reviewer
- Review round 2 (fresh reviewer + own reading):
  1. close/q tiles: post tops plain peach, no swirl: the beam's own end cap sat over the end-grain disc → beam stops lower, disc raised (blocking)
  2. side: oval swirls on the post faces at rail height: the plank texture's knots read as glitches → knots off on the fence wood (blocking)
  3. clay front: rails darken where they meet the right post → rails end inside the posts (detail)
  4. bolts on post faces don't line up with the rails they hold: accepted (rails tenon into the posts; bolts pin the tenons)
  5. posts uniform saturated orange → darker base tone (detail)
  fixing the above, then round 3
- Review round 3 (fresh reviewer + own reading):
  1. post tops: the end-grain disc was drawn as its own outline and sat turned, overhanging the post → the cap is now a fan over the post's own top ring (blocking)
  2. no visible swirl on the tops → bolder spiral line; with the cap fixed it shows (blocking)
  3. rail ends at the right post: a dark squared band → rails end inside the posts (detail)
  4. bolts read as white plastic pearls → steel, metallic 0.85, a little bigger (detail)
  5. wood a little glossy → accepted (rough 0.82 already) (detail)
  fixing, then round 4
- Review round 4 (fresh reviewer + own top-down render at the game camera's angle): reviewer saw no swirl on the tops and a V-notch. Own render: the spiral shows clearly from 55 deg above; the V-notch was real: the post's own cap centre vertex got into the top ring and cut a wedge out of the end-grain fan → ring takes only outline vertices (blocking, fixed). Details: bolts beside the rail ends (accepted: they pin the tenons), dark band at the right rail ends (clay), wood plain, low rail 40% up (accepted: Alex's pen; sheep are bigger than the gap). Round 5.

### Round 5 (fresh reviewer)
The ring filter in `top_cap` was rebuilt: the wedge is gone.
Blocking (1): "no end grain on the post tops."
**Argued, with evidence:** the spiral is there. A top-down render from 55° above, the game's camera angle (`review/fence_section/round6_top.png`), shows a clear ring spiral with the pith. The sheet cameras sit low (about 15°), so the tops are seen nearly edge-on and only their pale average shows.
Details, for later:
- A dark band on the rail ends at the right post. It also shows in clay, so it is the post's cast shadow on the key-light side, not a texture.
- The post wood is plainer than the rails.
- The bolts sit beside the rail ends; they pin the tenons, as argued in round 2.
### Round 6
Same model. The sheet is round 5's plus `round6_top.png`, the raised view. To a fresh reviewer.

Round 6, fresh reviewer 1: nothing blocking. "The swirl end grain on the post top is clear and well placed from the 55° angle."
Round 6, fresh reviewer 2: nothing blocking ("I'd show it to the owner as is").
Shared details, for later: the shadow band where the rails meet the right post; post faces plainer than the rails; posts and rails the same tone; bolt heads read gunmetal in the dim review light; a hairline seam on the top edge. Height 0.85 m was checked against the 0.95 m sheep in game (round 1 placement).
Two fresh reviewers in a row found nothing blocking. **REVIEW ROUNDS done.**

## Licenses
- All geometry and textures generated by script in this repo. blender-kiln (MIT) used for review tooling.

## Checkpoint
- Last completed step: REVIEW ROUNDS (two clean readings on round 6)
- Timestamp: 2026-11-11 19:30
