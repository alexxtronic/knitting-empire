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
Footprint x -6.60..6.54, z -4.20..4.40 (Godot, front toward +z); door hinge at (-3.0, 0, 2.94).

## Left out or inferred

- The photo's door has a sidelight; ours is a single door (narrower than the photo's opening).
- No porch bench or chairs; the porch is bare.
- The back and the sides aren't in the photo: windows and a back door are inferred, in the same style.
- The interior isn't furnished: nobody goes inside but the sleepers, who are hidden.
