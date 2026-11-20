# Bretton Oaks house: kiln log (2026-11-17)

Alex: "Add a suburban area called Bretton Oaks ... We only really need one house asset created similar
to the attached as closely as possible ... Make house in same way you made the cafe with the kiln skill."
Reference: `ref/bretton_oaks_house.png` (his photo, from the webp in `Desktop/Knitting Game/refs/`).

## Pipeline

- `build.py` (Blender, script-built like the café): the house in walk-in parts, `base`, `wall_<side>`
  and `wall_<side>_low`, `door` hinged on its left jamb, `roof`. Writes `out/building_suburb_house.glb`
  and copies it to `assets/props/`. `-- plants` builds `arborvitae.glb` and `red_shrub.glb`.
- `review.py`: Cycles renders matched to the photo's camera (street level, 50 mm, slight shift),
  with the game's BuildingSkin brick and shingle maps projected on so the review looks like the game.
  `review/round5_compare.png` is the photo over the render; `first_compare.png` is where it started.
- The light bake (`art/world_assets/light_bake/build.py -- building_suburb_house arborvitae red_shrub`).

## Materials (named for `BuildingSkin.kind_for()`)

| material | in the game |
|---|---|
| `suburb_brick` | brick map, tinted per house |
| `suburb_roof_shake` | shingles, slope shader |
| `suburb_trim` | paintwood, tinted per house |
| `suburb_vinyl` | its own lap-siding texture (`tex/suburb_vinyl.png`), tinted per house |
| `suburb_pane` | its own dark glass; `scripts/suburb.gd` swaps in a warm lit pane at night |
| `suburb_door`, `suburb_floor`, `suburb_lining`, `suburb_paving`, `suburb_lamp_black`, `suburb_bulb`, wreath, bow, brass | their own |

## Rounds

1. Blockout from the photo: proportions off (the entry wing too short, the right wing narrow).
2. Re-measured: the entry wing runs on under the right wing; the right wing is wider; the centre gable moved right; a narrower picture window.
3. A dark gap at the back where the two roofs meet: `valley_fill()` and the left slab clipped at the valley.
4. Shingles came out red in review (the review's tint): tinted toward a target colour, as BuildingSkin does.
5. Arborvitae less tiered, red-leaf shrub larger. Accepted.

## Size

Door 2.05 m; the house built at 0.88 of the photo's ~15 m front, 13.1 x 8.6 m. About 5.2k triangles.
Footprint x -6.60..6.54, z -6.20..4.40 (the right and upper wings to -6.20, the entry wing to -4.20) (Godot, front toward +z); door hinge at (-3.0, 0, 2.94).

## Left out or inferred

- The photo's door has a sidelight; ours is a single door (narrower than the photo's opening).
- No porch bench or chairs; the porch is bare.
- The back and the sides aren't in the photo: windows and a back door are inferred, in the same style.
- The interior isn't furnished: nobody goes inside but the sleepers, who are hidden.

## Round 9 (2026-11-17): the garage and the entry wing's V

- Alex: "extend the bottom right part to become a garage for cars" and "put bottom angle line on leftmost roof to finish the upside-down V shape of the reference image".
- The entry wing's apex moved left of the upper wing (`LA`, x -2.1 at 3.8 m), just under that wing's eave corner, so its rake rises to it and comes down again to the right wing's rake; a short slope and rake board run on in front of the upper wing's front wall to where the two roofs meet (`slab(..., meet=)`), with the brick wedge under them (`valley_fill`). The porch is 1.45 m deep so that slope stands in front of the cream wall.
- First try: a two-car garage as its own block beside the right wing. Alex: "no i didn't want a whole new building part for the garage... the garage is just that existing bottom part extended out towards the street to fit a car".
- So the right wing `R` runs on toward the street: its front is `GARAGE_D` (5.6 m) in front of where the rooms end (`HOUSE_FRONT`, the old front, now the garage's plain back wall). A try with the garage door in the gable; Alex: "put garage door on the right hand side (by the door entrance) and put it back to how it was before in the front". So the gable is the photo's again (window in the cream strip, the three arborvitae before it), and a white sectional door 2.8 x 2.15 m with a lamp each side is in the garage's side facing the porch, an apron out to the driveway in front of the porch; a side door on the far side; a concrete floor. The houses still clear each other as Alex placed them in `data/world_layout.json`. Review: `review/round9_*.png` (`q_garage` shows the door).

## Round 10 (2026-11-20): more room upstairs, out the back

- Alex: "not enough room on upper floor, expand internally a bit to give more room for creation, shouldn't be visible from the street". Chosen: push out the back.
- The right wing `R` and the upper wing `M` run on `BACK_EXT` (2.0 m) past the entry wing's back wall; the entry wing is unchanged, so from the street nothing moves. The right wing's left wall runs on along the new stretch (brick, plastered inside), the right side has a third window, and the back wall, its windows and the back door move out with it.
- Marcus's bedroom floor (the baby's and kids' rooms), the basement's rec room and a nook behind the dining room are 2 m deeper (`data/split_house.json`).
