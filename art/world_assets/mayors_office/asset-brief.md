# Asset brief: the Mayor's Office (Maple Grove town hall)

```text
ASSET      AR_building_mayor (assets/props/building_mayor.glb)
CATEGORY   architecture, a single static building (not walk-in for now)
VIEWS      ref/mayors_office_concept.png (Alex, 2026-11-12), 1254 x 1254: a concept, near-front
           three-quarter, camera az about 8 deg to the right (the right side wall shows as a
           sliver, x 1175..1225), elevation about 10 deg, a long lens (verticals stay parallel).
           The building fills about 0.9 of the image height; the ground line (foot of the plinth)
           is at y 1095. Measured as if front-on: perspective is mild.
SCALE      108 px = 1 m, from the double door (220 px tall = 2.05 m, against the shops' 2.15 m
           doorways, and two leaves of 0.84 m). The front, pilaster to pilaster, is 1150 px =
           10.6 m; the cornice is 5.0 m up, the roof ridge 6.9 m, the flag's top 10 m.
PROPORTIONS (checked at the blockout gate, front view, px of the reference)
           1 front width / cornice height 1150 / 540 = 2.13
           2 plinth height / wall height 105 / 435 = 0.24
           3 storey band at 0.47 of the wall's height (y 775)
           4 roof rise / front width 190 / 1150 = 0.165
           5 pediment span / front width 605 / 1150 = 0.53
           6 pediment apex over ground 780 px = 7.2 m; it rises above the roof's ridge
           7 column centres 380 px apart (3.5 m); shaft 85 px across (0.8 m)
           8 cupola drum 305 px across (2.8 m), dome 230 px (2.1 m) wide, 90 px tall
           9 window (with surround) 85 x 135 px; four per storey on the front, two each side of
             the portico
           10 door arch 275 px wide (2.55 m) with its top at y 645 (4.2 m)
           11 chimneys 105 px wide, tops at y 255 (7.8 m), x -3.2 and +4.0 m
PARTS      (all one static mesh; order of overlap, front to back)
           paving slabs on the ground in front; stairs (3 steps) with cheek blocks either side,
           an urn of white flowers on each; bushes either side of the stairs
           portico: podium at the floor's height, two Doric-ish columns on square bases, the
           entablature, the pediment (red tympanum, cream raking cornice), the crest (navy shield,
           gold rim, cream maple leaf) between two laurel sprigs; a lantern hanging over the door
           front wall: double door in an arched surround with a fanlight, two banners (navy, maple
           leaf, swallowtail) on rods, arched windows with cream surrounds and keystones, glowing
           main block: stone plinth, red vertical boards, cream corner pilasters, the storey band,
           the cornice; side walls with two windows a storey
           roof: a hipped roof of brown shingles, two dormers with arched windows, two cream brick
           chimneys; the cupola on the ridge: red base, an octagonal drum of arched windows, a
           cornice, a shingled dome, a gold ball and the flagpole with a red maple-leaf flag
SILHOUETTE the pediment rising in front of the roof; the cupola and flag on top; the two columns;
           the two chimneys at the roof's ends; the wide two-storey block with its hip roof
MATERIALS  boards: painted red wood (#a33a2e), matte, vertical grain; trim, columns, pediment
           cornice, pilasters: cream painted stone (#efdcb8), soft satin; plinth, steps, paving:
           grey-beige dressed stone (#a99c8f); roof and dome: brown shingles (#5d433b); doors:
           warm wood (#a5582c); windows: glowing warm glass (#ffd27a, emissive); banners: navy
           cloth (#3f4b6e) with gold trim (#d4a24a); flag: red cloth (#c0443a); brass rings, ball
           and finial: gold metal; leaves: #5f8a3a; flowers: cream (#f5ecd6)
ARTICULATION none (static); the flag does not move (could later be a cloth shader)
INFERRED   the depth (6.8 m main block, the portico 1.6 m deep, the stairs 1.05 m): the
           reference shows only a sliver of the right side; the back and the left side copy the
           right (two windows a storey, no door); the roof's back slope mirrors the front; the
           cupola's hidden faces repeat the visible ones
TARGET     Godot 4.7, GLB, standard tier (budget 60k triangles), the game's three-quarter
           overhead camera, the building about 300 px tall on screen at its usual distance.
           Placed by scripts/town.gd (building(), model "mayor"), facing the road and plaza;
           Alex places it finally in god mode. The Mayors Office hanging sign hangs from the
           portico's entablature, between the columns.
```
