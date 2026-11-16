# computer — Production Log

## Config
- Type: static furniture prop for Knitting Empire (Godot 4.7), `assets/props/computer.glb`
- Target: GLB, uncompressed (Godot cannot import Draco); light bake added after the build
- Tier: 12k triangles, one 2048 px colour and normal map (she uses it in first person, so closer up
  than a yard prop), plus the `screen` quad
- Style: Woolcore (docs/STYLE_GUIDE.md): chunky, rounded, felt-matte, warm wood, cream and brass

## Brief
- Alex, 2026-11-16 (docs/DIRECTION.md, "The guided opening and how the player scales"): a computer is a
  big, expensive purchase that opens an online store, like Etsy, which she uses in first person.
- Asked for: a desktop computer and monitor that sits on a desk in Nora's house, picture first in
  ChatGPT, then Tripo; the screen its own mesh and material named `screen` so the game can draw the
  store's page on it.
- Made as one piece with its own desk (a computer desk), so it stands on the floor like the rest of the
  catalogue. It sells at Builder's Delight (`"shop": "homegoods"`, draft price 2500c).

## Reference
- `ref/computer.png`: one ChatGPT picture, asked for in the look of `docs/woolcore/style_02_hearth.png`
  (attached): a chunky wooden desk with a drawer, a cream monitor with a thick soft bezel and a blank
  charcoal screen, a cream tower, keyboard and round mouse, three-quarter view on white.

## Source
- Tripo Studio, H3.1 Best Quality, 4K PBR textures with the lighting removed, 300k triangles: one
  generation, 55 credits. The export came back with 274k faces. It stays in Alex's Downloads
  (`desktop computer 3d model.glb`), not the repo.
- `build.py`: welds it, stands it facing -Y (it already did: `--yaw 0`, checked on `review/orient.png`),
  scales it so the desk top is 0.76 m high (the biggest flat upward area), thins to 12k triangles,
  bakes Tripo's colour and normal detail at 2048 px, finds the screen on the bake and lays the `screen`
  quad over it, exports.

## The screen
- Found as the dark (luminance < 0.16), front-facing faces above the desk top; the quad is fitted to
  their plane (the monitor stands 0.6° off vertical), trimmed to their 2nd..98th percentile extent, inset
  1.2% and set 2 mm in front.
- A separate node and mesh `screen` with its own material `screen` (charcoal, switched off).
  0.690 x 0.412 m, aspect 1.67 (about 5:3), centre at (-0.131, 0.079, 1.142) in Blender (x right,
  y back, z up), i.e. (-0.131, 1.142, -0.079) in Godot, facing +Z in Godot. UVs 0..1: in Blender u runs left
  to right and v bottom to top as you face it; glTF flips v, so in Godot (0,0) is the top-left corner
  and a store page's texture (a ViewportTexture) goes on upright with no flip.

## Size
- 1.32 x 0.85 x 1.41 m (desk top 0.76 m, monitor top 1.41 m): a touch chunky, as the style asks.
  `data/furniture.json`: size [1.4, 0.9], height 1.45.

## Gates
- `review/front.png`, `review/threeq.png` (Cycles): reads as the reference; the quad sits inside the
  bezel with no gap and nothing poking through.
- Light bake: `art/world_assets/light_bake/build.py -- computer` (added to `PROPS`, and to
  `Lighting.BAKED` in `scripts/lighting.gd`).

## Deviations
- No `wood` cost in the catalogue: it's a computer, and paying for it in wood would be odd.
- `"shop": "homegoods"` is what the brief asked for; the Build & Buy menu only lists `indoors` and
  `yard` pieces (`Data.furniture_ids`), so the computer session wires its sale to Steve.
