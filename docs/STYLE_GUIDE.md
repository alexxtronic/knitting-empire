# Woolcore style guide

**Draft, waiting for Alex's sign-off.** These are the rules every model, colour and screen in Knitting Empire follows,
so that assets from Tripo, image-to-sculpt and hand-built code all look like they belong to one game.
The look already in the game (`docs/woolcore/style_*.png`) is the reference. Where this guide and the game
disagree, fix whichever one is wrong. Don't let them drift apart.

## The idea in one line

The whole world looks **hand-made from wool**: solid things are felt, fabrics and ground are knitted, light is
warm, and nothing is sharp, shiny or busy.

| | Woolcore is | Woolcore is not |
|---|---|---|
| Shapes | chunky, rounded, slightly oversized, readable from the camera at 10 m | thin, spiky, realistic, fussy |
| Surfaces | felt (soft, matte, fuzzy rim) or knit (visible stitches) | glossy plastic, metal sheen, photo textures |
| Colour | a small warm palette, muted, never pure black or white | neon, saturated primaries, grey-on-grey |
| Light | low warm sun, soft long shadows, gentle haze at dawn and dusk | flat noon light, hard black shadows, bloom |
| UI | felt patches with a running stitch, cream text, gold accents | glassy panels, thin sans-serif chrome, flat icons |

## Palette

The source of truth is `data/palette.json`. Every solid surface uses one of its 31 colours, and the import
tool snaps generated models onto them. To add a colour, add it there first and give it a family. Keep each
family to a few steps.

| Family | Colours (hex) | Used for |
|---|---|---|
| Wood | wood `#784d2e`, wood_dark `#4d301c`, wood_light `#b88a57` | furniture, fences, floors, beams |
| Textile (knit) | plaid `#a12b26`, plaid_dark `#5c1717`, cream `#edddbd`, rug_wine `#731f1c`, rug_oat `#e0cc9e`, rug_brick `#9e2b24`, denim `#596b8c`, clay `#9e5940` | cushions, rugs, quilts, clothes |
| Building | plaster `#ebdbbd` (knit, big stitch) | house and town walls |
| Stone | stone `#918c82`, stone_dark `#6b665e`, cobble `#80786b`, terracotta `#b8663f` | hearth, paths, pots, roofs |
| Metal | brass `#d9a84d`, gold `#f2cc75`, iron `#3d3a38` | lamps, handles, hinges. Felt-matte, never shiny |
| Plant | leaf `#548540`, grass `#6e9447` (knit), moss `#46653f`, sunflower `#e8b23a` | foliage, crops, lawn |
| Ground | path `#9e8057`, soil `#855c38`, soil_wet `#4d3321` | paths, farm plots |
| Accent | berry `#9a2a44`, sage `#9eae8f`, sky `#8fb3c7`, milk `#f4efe4`, charcoal `#2b2826` | details, the story's colour cues |

Rules:
- A prop uses **at most 6 colours**, and one should cover most of it.
- **Charcoal is the darkest colour and milk the lightest.** The colour grade lifts true black (the LUT black point is `#060309`).
- **Each season shifts the palette, not the shapes.** Autumn is the default; winter cools the ground colours and adds snow (milk).

## Materials

The Woolcore shader (`shaders/woolcore.gdshader`) projects its pattern in world space from three sides, so
models need **no textures or UVs** to look right.

- **Felt** is the default for every solid colour: matte (roughness 0.85–0.95), with a soft fuzz on the rim where light grazes it.
- **Knit** is for colours that are fabric or ground. Stitch widths: 0.07–0.08 m for fabric, 0.15 m for plaster walls, 0.24 m for grass. The palette's `knit` field sets this.
- **Plain** materials are only for glass, water and things that glow (flames, bulbs). Glowing meshes cast no shadow.
- **Characters** are the one exception: one 2048 px painted texture (knit sweater patterns, faces), still on the felt look.

## Shapes and sizes

- **Units are metres.** Models face **+Z in Godot** (−Y in Blender), sit centred on their footprint, and their base is at floor level. The import tool does all of this.
- **Proportions are a touch toy-like:** chairs a little chunkier, handles a little thicker, nothing thinner than about 2 cm except knitting needles.
- **Characters** have big heads: about 1/5.5 of their height (Nora 1.70 m, head 0.30 m). Every character uses the same 22-bone skeleton and the same animation set (`tools/build_character.py`).
- **The silhouette has to read from the game camera,** which looks down from about 10 m away. If a detail can't be seen from there, leave it out.

### Polygon budgets

| Kind | Triangles | Colours |
|---|---|---|
| Small prop (pot, churn, basket) | 500–2,500 | ≤ 4 |
| Furniture | 1,500–4,000 | ≤ 6 |
| Building | ≤ 15,000 | ≤ 6, plus the plaster knit |
| Character | 24,000–30,000 | one 2048 texture |

## Light and grade

The values set in `scripts/main.gd` are the reference:
- **Tone and exposure:** filmic tonemap, exposure 0.95, white point 6, so cream walls in the sun roll off softly instead of clipping.
- **Sun:** a low, warm sun with an angular size of 0.55° (soft shadow edges) and four shadow cascades.
- **Ambient light and depth:** ambient energy 0.38 to 0.5 through the day, plus SSAO for contact shadows.
- **Haze:** volumetric haze only in rain and at dawn or dusk.
- **Glow:** gentle, with no bloom.

## UI

Felt patches with a running stitch sewn around them (`scripts/hud.gd`, `_stitched`):

| Element | Colour |
|---|---|
| Panel | `#2b211c` |
| Raised panel | `#45362b` |
| Stitch thread | `#8c6b47` |
| Text | cream `#f7edd9` |
| Highlights and names | gold `#f2cc75` |

- **Stitches** have an 8 px period: 5 px of thread, then a 3 px gap.
- **Icons** are drawn in code, so they never depend on a font having the glyph.
- **Portraits** sit in their own stitched frame. Names go on a small felt tag.

## Making assets

### Props and furniture (Tripo or anything else)

1. **Generate** with a prompt in this shape:
   > *a chunky stylized \<thing\>, cozy handmade felt toy look, soft rounded shapes, simple flat colours, no fine
   > detail, no text, single object, no base or ground, centered*

   One object per generation, in front or three-quarter view.
2. **Import** it:
   ```bash
   Blender -b --factory-startup -P tools/import_asset.py -- . path/to/model.glb <id> --height <m> --faces 2500 --render preview.png
   ```
   The tool welds the mesh, scales and places it, snaps its colours to the palette, decimates it and writes `assets/props/<id>.glb`. Read its colour report. If a colour is snapped to the wrong palette entry, raise `--colors` or fix `data/palette.json`.
3. **Register** it: add an entry to `data/furniture.json` with `"model": "res://assets/props/<id>.glb"`. `Catalog.model` swaps in the Woolcore materials by name.
4. **Check** it in game, in Build mode and from the normal camera, by day and by night.

### Characters

The roadmap's character path runs from a turnaround to the game:
1. **Turnaround:** five views of the character (front, ¾ front, side, ¾ back, back) on plain white, cut out with `tools/cutout_views.py`.
2. **Sculpt:** run image-to-sculpt on the views. Offline it is free, but the face comes only from the painted colours; the paid step (about $2) adds real surface detail.
3. **Paint:** `tools/project_colors.py` paints the sculpt from the views.
4. **Rig:** `tools/rig_sculpt.py` puts the sculpt on the character's rig, with the same bones, animations and knitting props.
5. **Register:** point the character's `model` at the result in `data/characters.json`.

## Don't

- **Imported textures on props:** they break the hand-made look and cost memory. Use palette materials.
- **Shiny or metallic materials:** metal is felt in brass, gold or iron.
- **Pure black outlines, pure white, saturated primaries.**
- **Text baked into models,** like signs or labels: put it in the UI or in a Label3D in the UI font.
- **Logos or likenesses of real brands or games.**
- **New colours outside `data/palette.json`.**
