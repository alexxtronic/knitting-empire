# hoe: kiln log

Reference: ref_hoe.png (cut from reference_sheet.png).

## Intent

a long straight handle (0.78 m), a riveted iron collar near the top and a square blade hanging beside it with a big rounded far corner and a straight worn cutting edge; a striped cloth band tied with a knot near the foot. Built upright like the axe: the handle (or foot) at the origin, the working end up, toward +X.

## Rounds

Reviewed from the review sheets (review/hoe/roundN.png and roundN_clay.png) against the reference by the building agent; no separate reviewer agents this time.

- round 1: blade a little small against the reference -> bigger (to x 0.195, 0.195 m tall)
- round 1: blade faces had vertices only on their outline, so the worn colour bled over them -> plates are subdivided (all plate tools)
- round 2: reads as the reference; open detail: iron grain smears along the blade (u/v density differ)

## Checks

- 4696 triangles, 0.237 x 0.097 x 0.817 m, materials tool_wood, tool_endgrain, tool_iron_plain, tool_rivet, tool_iron, tool_band, tool_knot
- UV check (kiln tools/uv_check.py): overlap 100 % and stretch from tiled, unbaked textures (expected, as the axe); collapsed faces are the plates' thin rims, whose UVs come from x/z (about 1 cm wide, not visible)
- Export: GLB via kelib.finish, copied to assets/props/hoe.glb; no Draco
- In the game: held by TOOL_HOLD in scripts/main.gd
