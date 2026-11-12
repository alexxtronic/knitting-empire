# scythe: kiln log

Reference: ref_scythe.png (cut from reference_sheet.png).

## Intent

a crooked snath (0.84 m) with two side handles, twine near the foot, a red wrap, a riveted collar and a broad crescent blade swept out to the right, the cutting edge on its underside. Built upright like the axe: the handle (or foot) at the origin, the working end up, toward +X.

## Rounds

Reviewed from the review sheets (review/scythe/roundN.png and roundN_clay.png) against the reference by the building agent; no separate reviewer agents this time.

- round 1: blade a sliver -> broad as the collar is tall, tapering to the tip
- round 2: reads as the reference

## Checks

- 7388 triangles, 0.517 x 0.089 x 0.873 m, materials tool_wood, tool_endgrain, tool_knot, tool_redcloth, tool_iron_plain, tool_rivet, tool_iron
- UV check (kiln tools/uv_check.py): overlap 100 % and stretch from tiled, unbaked textures (expected, as the axe); collapsed faces are the plates' thin rims, whose UVs come from x/z (about 1 cm wide, not visible)
- Export: GLB via kelib.finish, copied to assets/props/scythe.glb; no Draco
- In the game: held by TOOL_HOLD in scripts/main.gd
