# CH_Rowan: first review pass

Draft for Alex. The model is a forms-and-materials pass: built, measured against the reference and
proved to articulate, but not rigged, baked or exported yet. Sheets:

- `01_compare_turnaround.png`: reference above, build below, same scale and ground line
- `02_head_and_face_test.png`: head at rest; jaw opened 16 degrees and eyes turned 22 degrees
- `03_body_and_topology.png`: the body with the outfit hidden; wireframes of body and head

## What matches

- Overall read: build, stance, outfit pieces, colours (sampled from the reference), parted wavy hair, full beard.
- Silhouette against the reference panels (skill gate, `gate/compare_*.png`):

| View | IoU | Widest band error (of height) | Gate |
|---|---|---|---|
| Front | 0.894 | 0.027 | blockout 0.85 pass; forms 0.90 just short |
| Side | 0.919 | 0.008 | pass |
| Back | 0.914 | 0.023 | pass |

- Structure: one continuous nude body (torso, arms, hands, legs, feet). The head meets it on a shared
  neck ring, vertex for vertex, so no seam shows. Sweater, jeans, belt, each boot, hair, beard and brows
  are separate objects, none joined to the body.
- Face: eyeballs are separate with their pivot at the centre; eyelids are loops round each eye; the mouth
  is a real slit with lip loops, upper and lower teeth with gums, a tongue and a dark mouth interior.
  The Head / Jaw vertex groups are written; the test opens the mouth on a hinge in front of the ear.
- Validation (`gate/validate.json`): 0 failures.

## Measured deviations that remain

- Front IoU 0.894 against a 0.90 forms tolerance: the arms hang a little further out and lower than the
  reference (fingertips at z 0.72, reference 0.75), and the hair is less wavy at the sides.
- Hair: smoother and more helmet-like than the reference, whose locks curl and flick; width 0.244 against 0.256.
- Face likeness is partial: the reference smiles more, the eyes are a little larger and closer to the brows,
  and the beard there is short fur rather than one soft mass.
- Sweater: no ribbed bands at collar, cuffs and hem, no raglan seam lines, no folds on the forearms. One knit
  pattern covers everything.
- Jeans: no stitching, pockets, fly or rivets. Boots: plain laces (no bow), no stitching, flat sole with no heel step.
- Triangles: 50,444 at LOD0 (body 9.6k, head 5.8k, hair 12.7k, sweater 6.9k, jeans 4.6k, boots 5.4k, rest 5.4k).
  The style guide's budget is 24-30k; the hair and the outfit are where a LOD1 would cut.
- Validation warnings, all known: 32 five-sided faces where the head's 64 columns meet the neck's 32;
  13 doubled vertices on head and beard (the two lips, on purpose); a few zero-area faces on the belt loops and boot soles.
- Mouth-open test: a thin crack shows at the mouth corner of the beard at a three-quarter angle.

## Inferred (the reference does not show it)

- The entire body under the clothes: outfit measurements minus cloth and ease. It is a smooth mannequin with
  no anatomical detail and no separate toes.
- The inside of the mouth, the top half of the ears, the scalp, the waistband under the sweater.
- The three-quarter panels of the reference disagree with front and side by a few percent, so they were used
  for likeness only.
- Barefoot, the body stands 2.8 cm above the ground: the feet sit on the boot soles.

## Not done yet

Rig (shared 22 bones plus Jaw and two eye bones), blink, weights for the body and clothes, the rigid-head
pass (`tools/rigid_head.py`), UV atlas and bake to one 2048 set, LODs, GLB export and the in-game check.
The autotest was not run: nothing in the game was changed.
