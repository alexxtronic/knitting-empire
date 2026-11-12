# shovel: kiln log

Reference: ref_shovel.png (cut from reference_sheet.png).

## Intent

a D grip at the foot (crossbar between two arms), a straight shaft with a red wrap and twine with a knot, an iron socket with a rivet running on as a ridge down a dished spade blade with a worn rim. Built upright like the axe: the handle (or foot) at the origin, the working end up, toward +X.

## Rounds

Reviewed from the review sheets (review/shovel/roundN.png and roundN_clay.png) against the reference by the building agent; no separate reviewer agents this time.

- round 1: blade read white (worn colour everywhere, see hoe) -> plate subdivision
- round 1: the socket ridge stood off the blade as a dark spike -> flatter (0.45), lying on the blade
- round 2: worn band a third of the blade -> depth 0.05 (round 3)
- open: the D grip's arms are round where the reference's are flat boards

## Checks

- 6172 triangles, 0.196 x 0.088 x 0.802 m, materials tool_wood, tool_endgrain, tool_rivet, tool_iron_plain, tool_iron, tool_redcloth, tool_knot
- UV check (kiln tools/uv_check.py): overlap 100 % and stretch from tiled, unbaked textures (expected, as the axe); collapsed faces are the plates' thin rims, whose UVs come from x/z (about 1 cm wide, not visible)
- Export: GLB via kelib.finish, copied to assets/props/shovel.glb; no Draco
- In the game: held by TOOL_HOLD in scripts/main.gd
