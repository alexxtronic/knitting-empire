# Asset brief: the coffee shop

```text
ASSET      AR_building_cafe (assets/props/building_cafe.glb)
CATEGORY   architecture, a single static building with its terrace (not walk-in for now)
VIEWS      ref/coffee_shop_concept.png (Alex, 2026-11-12), 1448 x 1086: a concept, front
           three-quarter, camera about 12 deg right of front (the right gable wall shows,
           x 1105..1235), elevation about 12 deg, a long lens. The front wall's foot is at y 985;
           the terrace's cobbles run down to y 1060.
SCALE      136 px = 1 m, from the door (285 px tall = 2.1 m, the shops' doors are 2.15). The front
           wall is 805 px = 5.9 m across (the shops are 5.5 to 6 m); the eaves 3.5 m up, the ridge
           6.5 m, the front gable's apex 6.8 m, the chimney's top 7.1 m.
PROPORTIONS (front, px)
           1 front width / eave height 805 / 480 = 1.68
           2 ridge over the eaves 410 px: a steep roof (about 47 deg)
           3 front gable 455 px wide (3.35 m), apex just above the main ridge
           4 shop windows 205 x 130 px either side of the door, their tops level with the door's
           5 awning from y 535 (3.3 m) to its scalloped edge at y 640 (2.55 m), 860 px across
           6 the plaque over the awning 340 x 125 px (2.5 x 0.9 m)
           7 dormers 160 px wide either side of the gable, sitting on the roof's lower half
           8 chimney 150 px wide at the right end of the ridge
           9 terrace: cobbles out to about 2.8 m in front, 10 m across
PARTS      walls: green vertical boards, cream corner posts and fascia, a low stone footing
           roof: a gable roof (ridge along the front), big rounded terracotta tiles; a front
           cross-gable with cream bargeboards and a little truss, its big arched window and a
           flower box; two dormers with arched windows and tiled hoods; a stone chimney
           front: the green door (arched glass top) in a cream frame, two steps and a mat; two
           glowing shop windows with wooden glazing bars and flower boxes; a striped green and
           cream awning with a scalloped edge and string lights under it; two wall lanterns;
           the plaque (the coffee cup between sprigs) over the awning
           right side: an arched window up in the gable, a small window below, a hanging basket
           on a bracket
           ivy with autumn leaves up the left corner and along the gable's left edge
           terrace: cobbles; two round bistro tables, each with two bentwood chairs, a candle
           lantern and a little vase; plaid throws on two chairs; a barrel of hydrangeas, two
           pots of lavender, a pot of hydrangeas; an A-frame chalkboard; fallen leaves
SILHOUETTE the steep tiled roof with the front gable rising in the middle; the chimney at the
           right; the striped awning across the front; the terrace furniture
MATERIALS  boards: painted green wood (#4f6a3c), matte; trim: cream (#f0dfc0); tiles: terracotta
           (#b0562e) with darker edges; stone: warm grey (#b9ab98); door: green (#4c693b); window
           frames, furniture: warm wood (#a8612e); glass: glowing warm (#f0a548); awning: green
           (#55703f) and cream stripes; ivy: greens, yellows and oranges; hydrangea: cream;
           lavender: violet (#8d6fb5); plaid: red and cream
           The plaque's face and the chalkboard's face are lifted from the reference as textures
           (the shop signs' method), so the cup and sprigs are exactly the reference's.
ARTICULATION none
INFERRED   the depth (5.0 m), the back (plain boards, two windows each storey's worth, no door),
           the left gable wall (copies the right without the basket), the roof's back slope and
           the far side of the chimney
TARGET     Godot 4.7, GLB, standard tier (60k triangles), the game's three-quarter overhead
           camera. Placed by scripts/town.gd (building(), model "cafe") near Nora's farmhouse,
           south of the path to town, facing the path; Alex places it finally in god mode.
```
