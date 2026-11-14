# wardrobe — kiln log

The oak wardrobe in Nora's house, rebuilt on 2026-11-14 to its full reference and with doors that open
and a rail inside, for the wardrobe view (`scripts/wardrobe_view.gd`: "Choose a sweater…" opens it from
her eyes, with every sweater she has knit on its own hanger).

## Brief

- Alex: "make a render in blender of this wardrobe as close to the source image as possible using kiln
  skill", with `ref/wardrobe.png` (the whole image; the old one was a screenshot of its top half).
- And, for the game: the doors open, a rail inside for the hangers.

```text
ASSET      PR_wardrobe
CATEGORY   prop, hinged (two doors)
VIEWS      ref/wardrobe.png: three-quarter from the front left, perspective, 1024 x 1536, level camera
SCALE      2.32 m to the top of the hat box, 1.15 m wide, 0.60 m deep (Nora is 1.65 m; the door knobs at her hip)
PROPORTIONS width : height of the carcass 0.58; doors 0.49 m each with 0.084 m posts; the cornice
           stands 0.078 m out; plinth 0.245 m with 0.16 m bracket feet; hat box 0.50 m across, 0.25 m tall
PARTS      carcass (posts, sides with rails, back, floor, ceiling, face frame) | cornice (bead, cove, band,
           bullnose, swept round three sides) | plinth on bracket feet with a quarter-round lip | two doors
           (separate meshes door_l, door_r, origins on their hinge lines: stiles, rails, an arched top rail,
           raised fields, brass knob, hinge leaves) | brass rail inside | hat box (box, lid, piping, strap, buckle)
SILHOUETTE the stepped cornice, the arched door tops, the bracket feet, the round hat box on top
MATERIALS  warm orange oak (fine wandering grain, low normal), a slightly brighter oak for the fields,
           a darker one inside; brass (metallic); maroon leather with cream piping
ARTICULATION door_l, door_r swing about their hinge lines (z up in Blender, y in Godot)
INFERRED   the back, the inside (floor, ceiling, rail, darker wood), the sides' panelling, the hat box's far side
TARGET     Godot, GLB, about 7.5k triangles, the game's overhead camera and her own eyes at 1.5 m
```

## Camera solve

The reference is a perspective render, so it was matched from its own camera, solved from its converging
lines: level (the uprights are vertical), eye 1.07 m up, turned 24 degrees to the left, focal length
3,760 px (58.7 mm on a 24 mm sensor), the carcass's front left corner 5.89 m deep and 0.42 m left of the
middle; the horizon 54 px under the middle of the frame. `wardrobe_review.py` renders from it (Cycles,
white background), `wardrobe_iou.py` measures the silhouette against the reference in the same frame.

## Rounds

| Round | Silhouette IoU | What changed |
|---|---|---|
| 1 | 0.696 | first build; the camera was a guess and too close |
| 2 | 0.936 | the solved camera; the widths had left out the 24 degree turn (1.04 → 1.15 m), depth 0.60 |
| 3 | 0.977 | doors back flush with the frame after the depth change; cornice profile, plinth lip, foot coves |
| 4 | 0.977 | fine grain in place of the fluted look, deeper orange oak, flat-shaded raised fields |
| 5 | 0.977 | hat box size and strap, knob height; the open and inside views for the game (`review/wardrobe/round5/sheet.png`) |

The left over difference is the reference's soft painted edges and its ground shadow.

## In the game

- `assets/props/wardrobe.glb`: the meshes `model`, `door_l` and `door_r`; the rail at 1.80 m, 0.005 m
  behind the middle (`WardrobeView.RAIL_Y`, `RAIL_Z`). Light-baked by `light_bake/build.py -- wardrobe`.
- The light bake sees it with the doors shut, so the inside bakes dark; the wardrobe view lights it with
  a small lamp of its own while the doors are open.
- Its footprint in `data/furniture.json` is still 1.5 x 0.5 m; the model is 0.60 m deep plus the cornice.
