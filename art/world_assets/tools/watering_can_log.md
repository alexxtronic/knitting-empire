# watering_can: kiln log

Reference: ref_watering_can.png (cut from reference_sheet.png).

## Intent

a squat iron can with a flared foot, a lid and knob, a bail strap over the top with a striped cloth sleeve, a spout from low on the right with a rose and seven holes, a felt daisy with two leaves on the front and a running stitch round the foot. Built upright like the axe: the handle (or foot) at the origin, the working end up, toward +X.

## Rounds

Reviewed from the review sheets (review/watering_can/roundN.png and roundN_clay.png) against the reference by the building agent; no separate reviewer agents this time.

- round 1: close to the reference; the foot flared too far -> narrower
- open: the spout is longer and thinner than the reference's

## Checks

- 9452 triangles, 0.434 x 0.26 x 0.384 m, materials tool_iron_plain, tool_rivet, tool_band, tool_hole, tool_felt_petal, tool_felt_centre, tool_felt_leaf, tool_knot
- UV check (kiln tools/uv_check.py): overlap 100 % and stretch from tiled, unbaked textures (expected, as the axe); collapsed faces are the plates' thin rims, whose UVs come from x/z (about 1 cm wide, not visible)
- Export: GLB via kelib.finish, copied to assets/props/watering_can.glb; no Draco
- In the game: held by TOOL_HOLD in scripts/main.gd
