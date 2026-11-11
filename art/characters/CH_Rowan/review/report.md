# CH_Rowan: review pass 2 (likeness polish)

Draft for Alex. Still a forms-and-materials pass: built, measured against the reference and proved to
articulate, but not rigged, baked or exported. Sheets:

- `01_compare_turnaround.png`: reference above, build below, same scale and ground line
- `02_head_and_face_test.png`: reference head beside the build at rest; jaw opened 16 degrees, eyes turned 22 degrees
- `03_body_and_topology.png`: the body with the outfit hidden; wireframes of body and head

## Changed in this pass

- Face: the jaw tapers to the chin, the mouth is a wide closed smile (corners 8 mm up, a painted mouth line and
  lower lip), cheeks and nose are rosier, the nose is rounder and wider, the ears are larger and show.
- Eyes: opening 48 x 34 mm (was 43 x 25), iris 28 mm, grey-blue as in the reference, a dark upper lash line.
  The lid loop is now 28 vertices.
- Brows: thick with a gentle arch, 3 mm above the lid.
- Beard: thinner on the cheeks, lower cheek line, lighter brown, and its edge is painted into the skin as stubble
  so it fades instead of ending in a hard step.
- Hair: curtains that lift off the forehead from the parting, sweep out and back and flick up; the ears show.
- Sweater: ribbed collar, cuffs and hem; a lower crew collar; three folds where the sleeve is pushed up.
- Jeans: tan topstitching painted in the UVs (`textures/CH_Rowan_JeansStitch.png`): fly, front pockets, yoke,
  back pockets, side seams, inseams.

## Measured against the reference

| View | Silhouette IoU | Widest band error (of height) | Skill gate |
|---|---|---|---|
| Front | 0.890 | 0.027 | blockout 0.85 pass; forms 0.90 just short |
| Side | 0.921 | 0.008 | pass |
| Back | 0.909 | 0.020 | pass |

Validation (`gate/validate.json`): 0 failures, 49,936 triangles.

## Deviations that remain

- Front IoU 0.890 against 0.90: the arms hang a little further out and lower than the reference
  (fingertips z 0.72, reference 0.75), and the sleeves are fuller.
- Hair reads as chunky combed locks, not the reference's fine wavy strands; the lock ends are blunt.
- Beard is one soft shell with a fur texture, not short individual hairs; it is still a little wide at the chin.
- Eyes sit a touch wide and the whites show more than in the reference; no lower lash line.
- Sweater has no raglan seam lines and no cable pattern; one stocking-stitch knit plus the ribs.
- Jeans have no rivets or hem stitching. Boots: plain laces (no bow),
  no stitching, a flat sole with no heel step.
- The body is still a smooth mannequin: no anatomical detail, no separate toes.
- Triangles: 49,936 at LOD0 against the style guide's 24-30k (hair 11.5k, body 9.6k, sweater 6.9k, head 5.8k,
  boots 5.4k, jeans 4.6k).
- Validation warnings, all known: 32 five-sided faces where the head's 64 columns meet the neck's 32;
  13 doubled vertices on head and beard (the two lips, on purpose); zero-area faces on belt loops and boot soles.

## Inferred (the reference does not show it)

The entire body under the clothes, the bare feet, the inside of the mouth, the top of the ears, the scalp and
the waistband under the sweater. The three-quarter panels disagree with front and side by a few percent, so
they were used for likeness only. Barefoot, the body stands 2.8 cm above the ground (the feet sit on the boot soles).

## Not done yet

Rig (shared 22 bones plus Jaw and two eye bones), blink, weights for the body and clothes, the rigid-head pass
(`tools/rigid_head.py`), UV atlas and bake to one 2048 set, LODs, GLB export and the in-game check.
The autotest was not run: nothing in the game was changed.
