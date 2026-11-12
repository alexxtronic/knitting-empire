# Dog (golden retriever) — Production Log

## Config
- Type: character (creature, quadruped), playable, for Knitting Empire (Godot 4.7)
- Target: assets/props/dog.glb, uncompressed (Godot cannot import Draco)
- Tier: balanced (57k triangles, 2048 px colour and normal maps, 19 bones)
- Style: the Tripo export as Alex made it: stylised golden retriever, soft sculpted fur, red knitted scarf with Nordic stars
- Mode: auto

## Brief
- Alex, 2026-11-12: "add in the dog asset (this will be a playable character so rigging is important to give it a realistic walking and running pattern), note that the model gave the dog 5 legs so obviously remove one of the legs"
- Alex marked which leg goes with a crop of the raised right foreleg beside the scarf's tails: "cut this one".

## Source
- Method: AI generated (tripo.ai), Alex's export: `~/Downloads/stylized golden retriever 3d model (1).glb` (58 MB, not in the repo)
- One mesh, 1.97 M triangles, split along its UV seams; colour, roughness-metal and normal maps at 2048 px; head at +X, 0.6035 m tall, standing mid-stride

## Pipeline (all in tools/rig_dog.py, headless)
- Import, weld (1,010,917 → 984,822 vertices, manifold), turn the head to -Y, decimate to 60k, scale to 0.62 m
- The fifth leg: two right forelegs, one planted under the chest, one raised beside the scarf tails. Leg centre lines measured by rings of surface distance from each paw: the raised one stays ~7 cm thick for 0.24-0.26 m, then widens into the chest. Cut at 0.245 m along the surface: 1448 vertices; the 63-edge hole filled, subdivided and relaxed into the chest with three rings of the fur round it; the patch and two rings of fur round it take the median golden fur colour from the rings beyond, in a spare block of the texture. 0 open edges left.
- Rig: kiln's quadruped bone names (Hips, Spine1, Neck, Head, Tail1-3, {Left,Right}{Arm,ForeArm,Hand,UpLeg,Leg,Foot}), joints measured on the model; bone heat skin; everything ahead of the neck-top plane rigid on Head (fades over 5 cm); the scarf found by its colour and bound rigid, the wrap to Neck and the tails to Spine1
- Animation: scripted (kiln's rule: quadruped cycles scripted, never UniMate). Every paw follows a path over the ground and its leg is solved to it each frame; each loop finds its own body height, standing as tall as the legs allow with no leg past 95% straight (Idle 92%). Checked every frame: paws within 1 mm of their spot.
  - Idle 8 s: breathing, a weight shift, a long look and a glance, a head tilt, two bursts of wagging
  - Walk 0.6 s: four-beat lateral walk (LH, LF, RH, RF), duty 0.64
  - Trot 0.4 s: diagonal pairs, duty 0.44, a short flight between
  - Run 0.36 s: rotary gallop (LH 0, RH 0.14, RF 0.50, LF 0.64), duty 0.25, the back arching and stretching
- Export: GLB, JPEG textures, NLA tracks as clips, no Draco; 2.6 MB

## Review rounds
- Motion round 1 (fresh reviewer; sheets review/round1*.png, review/motion1_*.jpg, review/round1_cut_closeup.png):
  1. Run read as a paired bound, the paws of each pair overlapping (blocking) → lead offsets widened from 0.09 to 0.14 of the cycle
  2. Walk read low and short-stepped (blocking) → step 0.21 → 0.25 of the scale, paws lifted higher (7 and 5.5 cm), the head nodding twice as much
  3. Little flight in the trot and gallop → the trot's rise doubled, the gallop's two flights higher
  4. Run spine flat → arch 13° → 18°
  5. Scarf wrap pinched into a wedge by the shoulders → scarf bound rigid (wrap to Neck, tails to Spine1)
  6. Idle stance staggered (minor, from the paw shapes): left
  7. A smoother patch of fur behind the scarf tails at the cut (minor, hidden at game distance): left
- Motion round 2 (a new reviewer; review/motion2_*.jpg, review/round2_cut_closeup.png): four legs everywhere, the cut clean, the walk upright, the run reads as a gallop
  1. The scarf tails crumple into a streaked knot whenever a foreleg swings forward (blocking): the colour test found the red wool but not the cream snowflakes and stripes, which stayed on the leg → the red selection closed over the mesh (grown four rings, shrunk four) so every stitch of the tails is bound rigid
  2. Gallop torso stiff, no frame with all four paws off the ground (minor): left
  3. The neck wrap looks pinched from the side (minor): left (helped by 1)
  4. Tail and ears still in Walk and Trot; Idle stands in a half step (minor): left
  5. A hairline crease at the shoulder in one gallop frame, probably the cut (minor): left
  6. Walk and Trot look alike from the side; the trot's hind leg trails long (minor): left
  7. Golden fur close to the orange floor indoors (minor, the game's lighting): left
- Motion round 3 (a new reviewer; review/motion3_*.jpg): four legs everywhere, Walk and Trot natural, no crumpling
  1. The scarf tails vanish in two gallop side frames (marked blocking, "MINOR at game distance" by the same reviewer): the tails hang on his right side and the side camera looks at his left; the front tiles of the same frames show them hanging normally, so the near forelegs hide them. Not a skinning fault: left. The tails don't sway (rigid by design since round 2)
  2. A slit and a ragged end on the scarf roll, streaks on the chest fur, in rest close-ups only (minor, from the Tripo texture): left
  3. Gallop back still reads straight, no airborne frame sampled (minor): left
  4. Hind legs read as tubes, hock bend small (minor): left
  5. A flattened far hind paw in one walk frame (minor): left
  6. Fur tufts on the thigh slide over the leg (minor): left
  7-9. Little secondary motion (tail, ears), tail thin seen from behind, Idle nearly still (minor): left
- Stopped after round 3: no skinning fault left; the minor items above are the list for a polish pass
 the first loops crouched like a cat stalking (the body kept at its rest height, the steps too long) → each loop now finds its height; the cut showed scarf red and leg shading at its rim → the patch widened and coloured from golden fur only

## In the game
- scripts/dog.gd: follows Nora; Tab plays him (clicks walk him, Shift gallops, the camera follows); the loop is chosen by speed (Walk below 0.85 m/s, Trot to 2.5, Run above) and played at speed ÷ STRIDE
- STRIDE (rig_dog.py prints it): Walk 0.669, Trot 1.459, Run 3.424 m/s
- Autotest: `--only=dog`, `_dog_checks` in scripts/main.gd

## Not done
- Real eyes (tools/add_eyes.py is built for the humanoid rigs; the dog keeps his painted eyes)
- A story line for his arrival when the pen is built
