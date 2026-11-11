# bench_park — build log

Park bench copied from Alex's reference render (`ref/reference.png`). Built by script (`build.py`),
following the blender-kiln method: inventory from crops, intent before geometry, shaders baked to
textures, review rounds against the reference. The bench only, no ground, leaves or plants.

## Brief

"Copy the reference image as closely as possible. Use Blender, add shaders and textures (metal and
wood). Just the asset, no surrounding details." Waiting for Alex's review before it goes in the game.

## Assumptions (one image, no scale)

- Size: taken from the reference's proportions with the seat at 0.44 m: 2.0 m long, 0.83 m deep, 1.01 m tall.
- Camera of the reference: about 20° up, to the front right, wide lens. The image's perspective is not
  consistent (it shows the outer face of both ends), so the comparison render matches it only roughly.
- Unseen in the reference, so plain: the back, the underside. The back got one rivet per slat on each upright.

## Inventory (from enlarged crops)

- two cast-iron ends, one casting each: splayed legs on chamfered plinth feet, an arch between the legs
  with a raised bead, a seat rail with a rivet at each leg
- on each end: a lobe rising in front of the seat, carrying a wide armrest that ends in a big scroll;
  a back upright that leans with the slats and curls backwards at the top
- a centre leg frame under the seat (legs, arch, feet; no upright)
- seat: a deep bull-nosed front plank that stops inside the end castings, three boards behind it whose
  ends show past the castings; a flat steel bolt at each end of every board
- back: three wide, thick slats leaning 10.8°, a dome bolt at each end; the armrest runs into the end of
  the bottom slat, as it does in the reference
- wood: saturated orange, a few long flowing grain lines, pale upper edges, darker undersides
- iron: warm dark grey, softly mottled, pale rims where a rounded edge faces the light

## Intent

- Palette (sampled from the reference): wood #de6f25 (dark #b4531b, light #f18a3a, edge #ffab58);
  iron #614e4d (dark #473735, light #7f6a69, edge #aa9596); steel bolts #917f86.
- Materials: wood (roughness 0.62), cast iron (0.52), steel bolt heads painted into the iron texture.
  Nothing metallic or glossy, as the style guide asks.
- Finishes: every edge rounded; bolts and rivets at each joint; hand-cut boards (sections wander a
  millimetre or two, ends a touch off square); painted light on upper edges and shadow in the joints.

## Pipeline

- Geometry: castings as bevelled outlines and swept rounded bars (`sweep`, `spiral`), boards as lofted
  sections (`plank`). 10,298 triangles, two materials.
- UVs: Smart UV Project per material, stretched to fill the square. 0 collapsed faces.
- Shaders: procedural Cycles node trees (`wood_shader`, `iron_shader`), kept in
  `out/bench_park_shaders.blend`. Baked through Emission to a float image, converted to sRGB; relief
  baked to a tangent-space normal map. 1024 px, 36 samples.
- Export: `out/bench_park.glb` (3.3 MB, PNG textures). Re-imported to check: one mesh, two materials,
  four 1024 px images, base at z = 0.

## Review rounds

- Round 0 (first look): too slim. The reference is chunky: seat boards 9 cm thick, front plank 12 cm,
  back slats 7 cm, castings 10 cm thick, bigger feet, a longer bench. Grain too stripy. All rebuilt.
- Round 1 (`review/` sheets, colour and clay): arm and scroll too thin and faceted → thicker band, more
  turns, plain smooth shading; board ends shaded dished → sharp line round each sawn end; iron too
  dark and wood too pale against the reference → colours moved; back left plain → rivets on the uprights;
  bolts too white → darker steel.
- Round 2 (`review/round2/`): nothing blocking found in my own reading. No independent reviewer was
  used; Alex is the second reader.

## Still different from the reference

- The reference's castings are softer, more like modelled clay; these have flatter faces.
- Triangles are above the style guide's furniture range (1,500 to 4,000): 10,298 for the long bench,
  9,594 for the short one. The scrolls cost most of it.

## The short bench (2026-11-11)

Alex approved the bench ("looks perfect") and asked for a half-length one for single sitters.
`bench_park_short`: the same castings 0.8 m apart instead of 1.8 m, boards 1.0 m long, no centre legs,
its own bake (wood at 512 px, iron at 1024 px). Rendered and looked at from six angles
(`review/short/sheet.png`): nothing found.

## In the game (2026-11-11)

- `assets/props/bench_park.glb` and `bench_park_short.glb` (both now centred on their footprint in depth).
  The old slatted bench, its textures and its build code in `art/world_assets/street/` are gone.
- `data/furniture.json`: `bench` is 2.0 x 1.0 m (was 1.5 x 0.5); `bench_short` is 1.0 x 1.0 m and is not
  sold in the Build menu.
- `Catalog.world_bench(x, z)` picks the bench for a place on the map: the short one for one place in
  five, decided by the position alone so the map never changes. Of today's six benches one is short
  (the plaza's west bench).
- She sits 12 cm forward of the bench's centre, on the boards. The autotest checks all of this
  (`_bench_checks`).

## Licences

All geometry and textures generated by this script. No third-party assets.

## Checkpoint

EXPORT and install done, 2026-11-11. Both models are in the game.
