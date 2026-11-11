# CH_Rowan: asset brief

Built with the `blender-image-to-3d` skill (`.claude/skills/blender-image-to-3d`). Draft for Alex's review.

```text
ASSET      CH_Rowan (assumed: the reference is Rowan the shepherd in a new outfit; rename if it is someone else)
CATEGORY   character, biped
VIEWS      ref/sheet.png, one image with five panels, all orthographic-looking, same scale, ground row 777 of 793:
           front.png      azimuth 0    subject fills 0.967 of the height
           tq_front.png   azimuth ~315 (he turns to his left)
           side.png       azimuth 90   (we see his left side, nose to image-left)
           tq_back.png    azimuth ~135
           back.png       azimuth 180
           The sheet is AI-painted: the panels disagree by a few percent, and the pose changes slightly between them.
           Measured from front and side only; the three-quarter panels are for likeness.
SCALE      1.80 m to the top of the hair (existing Rowan is 1.78 m on the shared rig). 0.002347 m per pixel.
PROPORTIONS (front view unless noted)
           head with hair 0.293 m = height / 6.1 (style guide says 1/5.5; the reference wins)
           hair width 0.256, face width at the eyes 0.172, neck width 0.121
           pupils 0.077 apart at z 1.657; brows 1.69; nose tip 1.612 (side: y -0.164); mouth 1.585; chin 1.52, beard 1.507
           shoulders: half width 0.153 at z 1.441, 0.235 at 1.368 (narrow, sloping)
           sleeve axis 21 degrees from vertical; wrist at x 0.313, z 0.936; fingertips z 0.75
           sweater width 0.336 at z 1.08, 0.364 at the hem (z 1.00); depth 0.30 (side)
           belt z 0.970 to 1.002; crotch z 0.72
           leg width 0.180 at z 0.645, 0.148 at the knee (0.50), 0.155 at the cuff; leg centres 0.110 to 0.128 from the middle
           cuff z 0.174 to 0.225; boot length 0.318 (side), width 0.125
PARTS      Body (one skin: torso, arms, hands, legs, feet)            deforming   nude, complete under the clothes
           Head (skin, ears, eyelids, lips)                           deforming   meets the body on the neck ring, same vertices
           Eye_L, Eye_R                                               rigid       pivot at the eyeball centre
           TeethUpper, TeethLower, Tongue, Mouth (inside)             rigid / jaw
           Beard, Brows, Hair                                         separate objects, follow Head (beard also Jaw)
           Sweater, Jeans, Belt, Boot_L, Boot_R                       separate objects over the body, never joined to it
SILHOUETTE wavy parted hair wider than the face; full beard; bulky sweater with sleeves bunched above ribbed cuffs;
           straight dark jeans with a pale turn-up; big round-toed boots
MATERIALS  skin (warm, rosy cheeks and nose); hair and beard (brown); sweater (charcoal chunky knit, matte, fuzzy);
           jeans (dark indigo twill) with pale grey turn-ups; boots (brown leather, tan sole and laces);
           belt (brown leather, brass buckle); eyes (blue)
ARTICULATION humanoid, the game's shared 22-bone skeleton plus Jaw, Eye_L, Eye_R (not built yet).
           Mouth opens on a hinge in front of the ear; eyes turn on their centres; loops at every joint.
INFERRED   the whole body under the clothes (outfit minus cloth and ease; doll-smooth, no anatomy detail);
           bare feet (simple, no separate toes); the inside of the mouth; the top of the ears (under the hair);
           the scalp; everything the sweater hides of the belt and jeans waistband
TARGET     Godot 4.7, GLB, one 2048 texture set (style guide), game camera about 10 m away looking down 50 degrees.
           Style guide budget is 24-30k triangles; this first pass is LOD0 and is over that (see review/report.md).
```

## Build

Each phase script opens the master, deletes what it owns, rebuilds it and saves. Run them in this order:

```bash
B=/Applications/Blender.app/Contents/MacOS/Blender
for s in 02_body 03_head 05_hair 04_outfit 06_materials; do
  $B --background --python build/$s.py -- --master CH_Rowan_master.blend
done
```

`build/common.py` holds the mesh builder and the signed-distance helpers, `build/spec.py` the joint positions.
Review renders: `review/look.py` (see its header). Skill gates: `scripts/review_render.py`, `compose_review.py`, `validate.py`.
