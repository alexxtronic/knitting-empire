# wildlife — Production Log

## Config
- Type: creatures (rigged, animated), game assets for Knitting Empire (Godot 4.7)
- Target: GLB in assets/wildlife/, uncompressed (Godot cannot import Draco)
- Tier: balanced (about 13.7k triangles per animal, 7.7k per bird; one 1024 px colour and normal
  map per animal, one 512 px colour map per bird)
- Style: stylised, soft and fluffy, cozy (the farm dog and the sheep are the template)
- Mode: auto

## Brief
- Alex, 2026-11-14: "I want birds that fly away whenever you walk near them. I want animals that will
  be using to make wool of different rarities ... sheep have to be the most common ... Scale the
  rarities like any other game with the ultra rare, common, rare, legendary mythic as the most rare.
  Use the screenshot for inspiration generate the assets with ChatGPT as images in our style, and then
  render them in blender using the kiln skill ... scattered them throughout the game world in order of
  their rarity".
- The screenshot was a list of fur animals: mink, fox, chinchilla, coyote, rabbit, raccoon, beaver,
  sable, lynx. Rarities chosen here (Alex left them to us): Common sheep and rabbit; Rare fox and
  raccoon; Ultra Rare beaver, coyote and mink; Legendary sable and lynx; Mythic wild chinchilla.

## Reference images
- ref/<id>.png: one ChatGPT sheet per animal (side view on the left, front three-quarter on the
  right, white ground), asked for in the game's style: chunky, soft, big friendly eyes, fluffy fur.
- ref/birds.png: a house sparrow, a robin and a herring gull standing in side view, and the sparrow
  in flight.
- Assumptions: real sizes from the animals (fox 0.68 m to the ear tips, rabbit 0.42 m, lynx 0.9 m,
  chinchilla 0.32 m; sparrow and robin 0.2 m, gull 0.42 m: birds a little over real size so they read
  from the game camera). The backs and far sides are not shown; they mirror the near side.

## Source
- Method: scripted (Blender 5.2, build.py with species.py, gait.py and review.py; birds.py for the
  birds). No hand edits: every number is in species.py or birds.py.
- Bodies: metaball ellipsoids and tapered leg capsules measured on each reference's side view (u from
  the nose, v up from the ground, in units of the figure's height), converted, thinned and roughed into
  fur clumps. Ears, eyes (glossy, lined), nose, teeth and the beaver's paddle are their own parts.
- Paint: per point, by part and position (species.py), baked in Cycles to colour (with a share of
  the ambient occlusion) and a fur-clump normal map.
- Rig: kiln bone names, bone heat, rigid head (only the head, snout, cheeks and neck). Loops Idle,
  Walk and Run, every paw solved to its spot on the ground (gait.py); each loop prints its STRIDE, which
  data/wildlife.json holds so the game plays it at the rate that keeps the paws planted.
- Birds: body and head metaballs, cone beak, tail fan, stick legs and toes, open wings as their own
  meshes on wing bones (spread and flapping in Fly, scaled to nothing in the shoulder in Idle; the
  folded wings are painted on the sides). Loops Idle (looks about, pecks, flicks its tail) and Fly.

## Gates (side view on the reference's own grid, review/<id>/gate_side.png)
| Animal | IoU | Walk / Run STRIDE m/s | Notes |
|---|---|---|---|
| fox | 0.869 | 0.515 / 1.705 | passes the 0.85 blockout bar |
| raccoon | 0.836 | 0.465 / 1.542 | mask band sloped to the reference's |
| beaver | 0.838 | 0.274 / 0.779 | paddle seen edge-on from the side (see deviations) |
| sable | 0.837 | 0.404 / 2.193 | |
| mink | 0.820 | 0.380 / 2.060 | |
| chinchilla | 0.818 | 0.516 / 1.277 | |
| rabbit | 0.792 | 0.591 / 1.463 | ears turned out and widened in round 2 |
| coyote | 0.784 | 0.673 / 2.229 | legs near straight at rest: the Run crouches 0.116 m |
| lynx | 0.735 | 0.681 / 2.257 | the reference's legs and ruff are fuller than metaballs give |

## Review rounds
- Round 1: ears were thin spikes seen edge-on → a `turn` (yaw outward), broader pointy and long
  profiles, bases set on the head's surface. A white sheet hung from the fox's tail tip: the rigid head
  plane caught tail points → the rigid head now takes only head, snout, cheek and neck points.
- Round 2: rabbit Run missed a paw by 10 mm (hind crouched too deep) → shorter hop. One failing
  animal stopped the batch → each builds on its own and the batch fails at the end.
- Round 3 (lynx, chinchilla): lynx ears horn-like and its ruff white → broad cat ears with black
  tips, a warm cream ruff; the chinchilla's ears small → big round discs turned out to the side.
- Birds round 1: tails read as sticks from the side, a shadow line on every flank (the spread wings cut
  the body during the occlusion bake), bodies too round → tails given depth at the rump, wings moved
  out of the way for the bake, lower longer bodies with a fuller neck. Round 2: the robin's orange
  stopped at a band (the back paint covered its face) → orange face and breast with a grey edge.
- Reviewers: my own reading each round against the reference sheets, no fresh reviewer subagents (as
  with the earlier props).

## Deviations
- The reference "side" views are drawn in slight perspective, a little from the front; the gates
  measure against them as if orthographic, which costs a few points on every animal.
- The beaver's flat paddle is edge-on in a true side view, so it shows as a thin line where the
  reference (seen a little from above) shows its scales.
- No whiskers: single-pixel strands shimmer at the game camera's distance.
- Birds' folded wings are paint, not geometry.

## Optimize
- Skipped for the game copy (no Draco, no WebP), as with every Godot asset.

## Tripo rebuild (2026-11-14)
Alex found the metaball animals above "terrible, low poly" and asked for the sheep's quality, made in
Tripo, five animals to an image to save credits. `build.py`, `species.py` and `birds.py` no longer make
the game's models; `gait.py` still keys the loops.

- Pictures: three ChatGPT lineups in `tripo/ref/` (one row, all facing left, plain background):
  coyote, lynx, fox, raccoon, beaver; rabbit, sable, mink, chinchilla, gull; and lynx again (its first
  ear tufts came out of Tripo as antlers), a sparrow, a robin and a sparrow and a gull in flight.
- Tripo Studio: H3.1 Best Quality, Ultra mesh, 4K PBR textures with the lighting removed, 300k
  triangles; three generations at 55 credits each. Each animal got 42k to 80k faces.
- `tripo_split.py`: welds the export, cuts it into its five loose parts, turns each to face -Y (Tripo
  keeps the three-quarter pose it was drawn in: lined up by the long axis of the feet, with `YAW`
  corrections for the raccoon and the chinchilla), scales it to its game height and renders grid views.
- `tripo_build.py`: thins to 30k triangles, bakes Tripo's colour and normal detail at 2048 px, places
  the joints from `HAND` (read off the grid views; the automatic tail and trunk tracing ran across the
  body), skins by bone heat with a rigid head, keys Idle, Walk and Run with `gait.py`, exports.
- `tripo_birds.py`: one rig carries the standing bird (Body, Head) and the bird in flight (FlyBody,
  WingL, WingR); Idle scales the flier to nothing and pecks, Fly scales the stander to nothing and
  beats the wings. The robin flies on the sparrow's wings with its pale feathers turned orange.

Rounds:
- Rabbit, sable, mink: the bounding Run's crouch left a lifted paw too close to the shoulder to reach
  (missed by 2 to 15 mm) → the stride and lift shorten 12% at a time until every paw lands.
- Rabbit: its long ears made it bounce like a 42 cm animal and its near-straight legs crouched it flat
  → motion scaled by the hips (`U = min(H, hips / 0.35)`), a shorter higher hop, elbows and knees bent
  further off the line to the paw (`bend`).
- Gull: the beak tip lay outside the head's weights and bent when it pecked → the head reaches past
  the beak tip. Robin in flight: the first recolour caught 2% of the map → 16%.
- In the game (`--only=wildlife`, 16 checks pass): the lynx's short tufts still read a little twiggy
  close up; the fox's inner ear is dark where the bake reached into the fold.

## Shorn forms (2026-11-16)
Alex asked for every shearable animal "in naked form as well for after she sheers them for wool",
made in one large sheet to save Tripo credits. Wild sheep reuse `sheep_sheared.glb`.

- Picture: a 3 x 3 grid of the furry animals' own renders went to ChatGPT, which drew each one shorn
  in the same pose and facing (`tripo/ref/shorn_1.png`: coyote, lynx, fox; raccoon, beaver, rabbit;
  sable, mink, chinchilla). One Tripo generation, 55 credits, same settings as the lineups.
- `tripo_split.py --rows 3`: the parts are grouped into rows by whichever axis (z or y) leaves the
  widest gaps, then read left to right. `level()` stands each animal on its four paws (a plane fitted
  through the lowest point in each quarter of its footprint): Tripo had tipped the fox 1 to 2 cm onto
  its forepaws, which pushed its right hind paw out of the ground band, both hind legs onto one side
  and the Idle's leg past its full length. Each shorn animal is scaled to its furry self's height to
  the ear tips (`SHORN_HEIGHT` for a factor where that doesn't fit; none needed).
- `tripo_build.py`: a `<id>_shorn` takes its species' settings from the furry id; its joints are its
  own `HAND` entry, read off its own grid views (the bodies are slimmer). All nine built first time
  after the fox's tilt was fixed: legs at most 95% straight, paws within 0.75 mm.
- In the game: `wild_animal.gd` loads both models, shows one and stops the other's loops, and swaps
  on a comb, on being penned, on coming into view and every couple of seconds (the day turning over
  grows the coat back). The shorn model plays its own strides (`shorn_stride`).
