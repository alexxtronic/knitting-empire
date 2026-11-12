# shears: kiln log

Reference: ref_shears.png (cut from reference_sheet.png).

## Intent

hedge shears: two broad blades crossed on a steel pivot bolt, iron shanks into wooden grips bound in red cloth with a running stitch, a coil spring between the grips and an iron loop joining their ends. Built upright like the axe: the handle (or foot) at the origin, the working end up, toward +X.

## Rounds

Reviewed from the review sheets (review/shears/roundN.png and roundN_clay.png) against the reference by the building agent; no separate reviewer agents this time.

- round 1: blades long and thin like scissors, grips short -> shorter broader blades, longer grips
- round 1: the loop dipped under the floor and read as two hooks -> a shallow loop joining the grip ends
- round 2: reads as the reference; open: the spring sits behind the grips, smaller than the reference's

## Checks

- 8528 triangles, 0.157 x 0.06 x 0.413 m, materials tool_iron, tool_iron_plain, tool_wood, tool_endgrain, tool_rivet, tool_redcloth, tool_knot
- UV check (kiln tools/uv_check.py): overlap 100 % and stretch from tiled, unbaked textures (expected, as the axe); collapsed faces are the plates' thin rims, whose UVs come from x/z (about 1 cm wide, not visible)
- Export: GLB via kelib.finish, copied to assets/props/shears.glb; no Draco
- In the game: held by TOOL_HOLD in scripts/main.gd
