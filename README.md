# Knitting Empire

A cozy life-sim prototype built in Godot 4. Raise sheep, knit sweaters, grow crops, decorate your house, make friends in the town of Maplewood and buy property to rent out.

![Rowan and Nora](tools/character_build/lineup.png)

## Play

1. Install [Godot 4.7+](https://godotengine.org/download) into `/Applications`.
2. Double-click `Play.command`, or run:

```bash
open -n -a /Applications/Godot.app --args --path .
```

Controls:
- Click the floor to walk.
- Click objects and people to open a ring of actions round them. Click an option, or press its number (1 to 9).
- WASD or the arrow keys pan the camera.
- Q and E rotate the camera, and the scroll wheel or a trackpad pinch zooms.
- Space or the lock button locks the camera to your character.
- C toggles the walls.
- B toggles Build mode. In Build mode, R rotates a piece, X sells it and Esc cancels.

The game opens on a title screen (Continue, New Game, Settings, Quit) over the farm. **Settings** (also in the left menu) has the picture quality, music and sound volumes, and full screen, all kept per computer in `user://settings.cfg`.

## What's in it

- **Act 1: Cast On.** A new game opens on the story. Nora steps off the last bus into Maplewood in the rain, walks down the road to her late grandmother's farm, gets the keys from Mabel, finds Gran's knitting basket and a letter, and meets Rowan when three sheep get out. Fixing the fence with him brings back the first memory thread (a sepia flashback to the navy sweater her ex threw away). She sells her first sweater to Rosa at the market, where Theo pays her in wool, and ends the day on the porch with a voicemail from her lawyer and Rowan's lantern. It takes about ten minutes, with choices that set flags and relationship stats for later. Memories and notes go into the **Journal** (left menu). Old saves skip it; start a **New Game** to see it. A recording of the whole opening is in [`docs/opening.mp4`](docs/opening.mp4).
- **Home and farm:** a house you can expand, furniture to place, sheep to shear, crops to plant, water and harvest, and a shipping bin.
- **Maplewood:**
  - three villagers (Rosa, Theo, Mabel) with friendship hearts, gifts and dialogue
  - daily market prices
  - a wool shop where you can also buy sheep
  - Rosewood Cottage, which you can buy, furnish and rent out
- **Life-sim UI:** actions open in a ring round whatever you click, with progress bars on things that take time (crops, wool, knitting). A needs panel shows Energy, Hunger, Happiness, Love, Warmth and Fitness as bars with trend arrows. Build mode shows furniture as picture cards rendered in the game.
- **Needs:** Warmth follows the weather, the time of day, being indoors and the best sweater she owns (knitting gets better with practice). Love fills from time with people. Fitness grows with walking and farm work and makes her walk a little faster.
- **Rowan (romance v1):** after Act 1, talking to Rowan opens one new topic a day as he warms up: his sheep, Gran (and Nora's memory of Gran's burnt bread), the long evenings on the hill. Gifts land differently with each villager (loved, liked, anything else), and with Rowan they can grow romance; the first sweater you give him has its own scene. At three hearts he asks Nora up to the rock in the back field at sunset, where she darns the hat Gran knit him and decides how close to let him. Later, if he trusts her, he tells her about Anna.
- **Talking to villagers:** besides **Talk** (hand-written lines), **Chat...** lets you type to Rosa, Theo, Mabel and Rowan, who answer in character (see [Chatting with villagers](#chatting-with-villagers)).
- **World:** real grass (tens of thousands of blades that sway in the wind and part round Nora, worn earth on paths), trees that move in the wind, a pond with ripples and rain rings, a sky with drifting clouds and stars, soft shadows, bounce light, a light haze for sunbeams and mist, and depth of field in close-ups.
- **Sound:** footsteps on grass and on wood floors, needle clicks while she knits, page turns for the journal, soft UI clicks, birdsong by day, crickets at night and rain that cross-fade with the clock and the weather (muffled indoors), and an original guitar and flute tune, "Cast On". During a memory flashback the music goes distant and muffled. Every sound is made by `tools/make_audio.py`, so there are no samples or licences to track; real recordings can replace them later under the same file names in `assets/audio/`.
- **Tips:** after Act 1, a one-time tip appears at the bottom of the screen the first time something becomes possible (shearing, knitting, selling, sleeping, Rowan, Build mode). Click it to dismiss.
- **Graphics setting:** the **Graphics** button in Settings cycles High, Medium and Low (saved per computer in `user://settings.cfg`). Medium drops the bounce light and reflections and thins the grass; Low also drops the haze, contact shading and lamp shadows and draws less grass, nearer. On every setting the 3D view is drawn at a fixed pixel budget and upscaled (MetalFX on Macs), so a bigger window looks sharper without getting slower.
- **Characters:** Nora (the heroine you play, working name) and Rowan (the shepherd in Maplewood) were first generated by the Blender script `tools/build_character.py`. Both now play with models made on [tripo.ai](https://www.tripo3d.ai) from their turnarounds and put on those rigs (`assets/nora_tripo.glb`, `assets/rowan_tripo.glb`); the generated bodies, and Nora's two earlier experiments (image-to-sculpt and TripoSR), are kept in `assets/` for comparison. Each is one skinned mesh on the same 22-bone humanoid skeleton, named to match Godot's humanoid profile, and both share the same loops: Idle, Walk, SitKnit, SitIdle, Work and Talk. Knitting needles and a swatch appear while knitting. Nora and Rowan move with motion capture: Idle, Walk, Talk, SitIdle and Work (kneeling, for chores) come from Quaternius's [Universal Animation Library](https://quaternius.itch.io/universal-animation-library) (CC0), retargeted onto our skeleton by `tools/retarget_anims.py`. They also have a Run loop, a light jog the player gets by holding Shift. SitKnit is still our own knitting loop. Nora walks at about 1.1 m/s and jogs at about 3 m/s (both rise a little with fitness); villagers stroll at 1 m/s.

## Chatting with villagers

**Chat...** in a villager's ring opens a chat window. Type to them and they answer as themselves, voiced by Claude through the Anthropic API. Each one has a character bible in `data/personas.json`: who they are, how they talk, what they know, and personal things they only share once they trust Nora. Every message also tells them the time, the weather, how well they know her and what's happened in the story. The last 20 lines with each villager are saved with the game. The clock stops while you chat, and the first chat of the day fills Love a little.

It needs an Anthropic API key. **The key is never stored in the game or this repo.** Either:

- paste it into the box in the chat window. It's saved on your computer only, in `~/Library/Application Support/Godot/app_userdata/Knitting Empire/ai.cfg`; or
- set `ANTHROPIC_API_KEY` in the environment you launch Godot from.

Without a key, villagers smile and nod, and **Talk** works as before.

`ai.cfg` options (section `[ai]`): `api_key`, `model` (default `claude-haiku-5-5` at low effort, the cheapest current model at well under a tenth of a cent per reply; `claude-sonnet-5-5` or `claude-opus-5-5` write richer replies at 20 to 40 times the price), `enabled=false` to switch chat off, and `proxy_url` to send requests to your own server instead, which adds the key. A proxy is how this would ship to players, since a key inside a game build can be pulled out.

The autotest checks the chat offline with a stand-in for the API, so it never spends anything.

## Project layout

| Path | What |
|---|---|
| `data/*.json` | game content: furniture, crops, prices, villagers, dialogue |
| `scripts/data.gd` | loads and cross-checks the data files |
| `scripts/main.gd` | world, input, camera, actions, building, autotest |
| `scripts/game_state.gd` | autoloaded save data, economy and story flags |
| `scripts/hud.gd` | HUD, menus, camera pad, dialogue |
| `scripts/town.gd`, `villager.gd`, `dialogue.gd` | Maplewood |
| `scripts/player.gd` | the character you play and her activity states |
| `scripts/body.gd` | a skinned character body; picks and cross-fades animation loops |
| `scripts/story.gd`, `story_player.gd` | reads and plays the plain-text story scenes in `data/scenes/` |
| `scripts/pie_menu.gd` | the ring of actions |
| `scripts/thumbs.gd` | renders the Build mode picture cards |
| `scripts/ai_chat.gd`, `chat_panel.gd`, `data/personas.json` | typed chat with villagers |
| `scripts/audio.gd` | music, ambience and sound effects on three buses (Music, Ambience, SFX) |
| `tools/make_audio.py` | makes every sound in `assets/audio/` (footsteps, needles, UI, ambience loops, the music) |
| `scripts/rig.gd` | procedural motion on top of the loops: head turns to look at people, leaning into turns, breathing |
| `scripts/grass.gd` | the ground and the grass blades |
| `shaders/woolcore.gdshader` | the felt and knit look |
| `shaders/ground`, `grass_blade`, `foliage`, `water`, `sky` | ground, grass, trees, pond and sky |
| `docs/woolcore/` | style frames (ignored by Godot) |
| `tools/build_character.py` | Blender character generator: builds `assets/<id>.glb` |
| `tools/cutout_views.py`, `project_colors.py`, `run_triposr.py`, `rig_sculpt.py` | turnaround to sculpt to rigged character (see [Characters](#characters)) |
| `tools/retarget_anims.py` | motion-capture loops (Quaternius's CC0 library) onto a character's rig; see `AGENTS.md` for the command |
| `tools/import_asset.py` | brings any generated model (Tripo, etc.) into the Woolcore look: `assets/props/<id>.glb` |
| `data/palette.json` | the 31 Woolcore colours every surface uses |
| `docs/STYLE_GUIDE.md` | the art rules: palette, materials, shapes, polygon budgets, UI, asset pipeline |

## Adding content without code

Prices, furniture, crops, villagers and their lines all live in `data/`. Edit the JSON and run the game.

- **A new price or limit:** change it in `economy.json`.
- **A new villager:** add an entry to `villagers.json`, then give them an intro, three tiers of lines and a loved-gift line in `dialogue.json`.
- **A new crop:** add it to `crops.json` and give it a sell price in `economy.json`.
- **Furniture:** add it to `furniture.json`. Either give it a `"model"` (a glb made with `tools/import_asset.py`, see [`docs/STYLE_GUIDE.md`](docs/STYLE_GUIDE.md)) or write a builder in `catalog.gd`.

The autotest checks the files against each other and names anything missing.

Story progress is kept as named flags (`Game.set_flag("met_rowan")`, `Game.flag("met_rowan")`) and saved with the game. Save files carry a version number. When the format changes, add a step to `Game.migrate()` so older saves still load.

When exporting, add `data/*` to the export preset's non-resource include filter, so the JSON and scene files ship with the game.

## Writing story scenes

Scenes are plain text in `data/scenes/*.scene`. The full format is described at the top of `scripts/story.gd`. Here's a short example:

```
== rowan_town_chat
@trigger talk rowan
@once
@camera rowan 6
Rowan (wry): You've got hay on your sweater and a city coat over it.
? What do you say?
- I'm still figuring out which end of a sheep is which. -> honest | trust rowan +2
- I'll manage. I always do. -> guarded | set nora_guarded
@label honest
Rowan (happy): The end that bites is the front. Mostly.
@goto done
@label guarded
Rowan (neutral): Fair enough.
@label done
@set met_rowan
```

- A line is `Speaker (mood): text`. The mood picks a portrait from `assets/portraits/<id>_<mood>.png`: neutral, happy, warm, sad, wry, surprised, worried or angry.
- `> text` is narration.
- `?` starts a choice, followed by `- option -> label | effects`.
- Other commands move the camera, fade, show title cards, walk and animate characters, set flags, and change relationship stats.
- `@memory on` / `@memory off` fade the sepia flashback look in and out. `@journal memory Title | text` (or `note`) writes to the Journal.
- `@time 21:30` sets the clock, `@sleep` ends the day, `give`/`take` also work with `coins`, and `@if has sweater -> label` branches on what's in the bag.
- `@when hearts rowan >= 3` (or any stat, `hour < 17`, `has sweater`) holds a scene back until it's true. `@daily` lets at most one such scene play a day, which paces a run of talk topics. `@trigger gift rowan sweater` plays after a gift.
- `@camera between rowan nora 4.5 low` drops the camera to a low, close angle for intimate moments.
- Rowan's romance is in `data/scenes/rowan.scene`. Gift reactions are `likes` and `romance` in `villagers.json` and `gift_lines` in `dialogue.json`.
- Staging commands set the goal shown at the top of the screen (with a marker on the map), make it rain, put down props like a bus or a suitcase, ring the phone, shake the camera, let the sheep out, and park a villager somewhere until a later scene sends them home.
- A scene plays when you talk to someone (`@trigger talk rowan`), on a new game (`@trigger start`), when you walk into a named place from `data/areas.json` (`@trigger area farm_gate`), or after an event such as finishing a knit (`@trigger event knit_done`).
- Act 1 is in `data/scenes/act1.scene`, which is a good worked example.
- Relationships have three stats: **familiarity** (shown as hearts), **trust** and **romance**.
- The autotest checks every scene file, so a typo or a jump to a missing label shows up as a failed check.

## Woolcore style (v0)

The world is meant to look handmade: felt and knitting.

The full rules (palette, materials, shapes, polygon budgets, UI and how to bring in new models) are in [`docs/STYLE_GUIDE.md`](docs/STYLE_GUIDE.md), a draft waiting for sign-off.

![The farm](docs/woolcore/style_01_farm.png)

- **Shader:** `shaders/woolcore.gdshader`. Every solid surface is felt, with soft mottling, fine fibres and a fuzzy rim. The grass, the house walls, rugs and plaid fabrics are knitted in stockinette stitches. Textures are projected in world space, so stitches stay the same size on any shape.
- **Which surfaces are knitted:** the `KNIT` list in `scripts/catalog.gd` (a colour and a stitch width). Glass, water and glowing things stay plain. Set `Catalog.woolcore = false` to compare with the old look.
- **Grade:** plum-tinted shadows, warm cream highlights and a little extra contrast (`_setup_environment` in `main.gd`), plus a soft vignette. Rain greys it down.
- **UI:** bordered panels and buttons are felt patches with a running stitch sewn round the edge, drawn in code (`_stitched` in `hud.gd`), so there are no image files to keep in sync.

To record the opening again (the game plays Act 1 by itself at reading pace, then quits; `ffmpeg` turns the AVI into an MP4):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path "$PWD" --resolution 1280x800 --write-movie /tmp/opening.avi --fixed-fps 30 -- --capture
```

The three style frames in `docs/woolcore/` are made by the game itself:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path "$PWD" --resolution 1280x800 -- --styleframes="$PWD/docs/woolcore"
```

To see what each graphics effect costs, the frame-cost probe times the town at noon and the farm at night with each effect switched off in turn (vsync off; macOS sometimes turns it back on, and then every reading pins at the display's refresh time):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path "$PWD" --disable-vsync --always-on-top --resolution 1280x800 -- --fpsprobe
```

## Characters

**Sculpted characters (Nora).** The path from a turnaround to the game:
1. Five views (front, ¾ front, side, ¾ back, back) on plain white, cut out with `tools/cutout_views.py`.
2. image-to-sculpt fits a mesh to them (free and offline; the paid step adds face and surface detail).
3. `tools/project_colors.py` paints the mesh from the views.
4. `tools/rig_sculpt.py` puts it on the character's rig in Blender, with the same bones, loops and knitting props, and writes `assets/<id>.glb`:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b tools/character_build/nora/nora.blend -P tools/rig_sculpt.py -- "$PWD" painted.ply nora_sculpt --render /tmp/rig_check
```

5. Point `model` in `data/characters.json` at it. Nora's first sculpt (`model_sculpt`) came out too lumpy without the paid detail step, so for now she plays with her generated body.

**Tripo.ai (what Nora and Rowan use).** Export from tripo.ai as GLB with a 2K texture, no vertex colours and no Tripo rig. `rig_sculpt.py` takes the `.glb` directly: it welds the UV-seam splits, decimates to about 30k faces and keeps Tripo's own UVs and texture (scaled to `--tex`), so nothing is re-baked. The source export is about 60 MB and stays out of the repo; the rigged `assets/nora_tripo.glb` is what the game loads (Rowan: his own `tools/character_build/rowan/rowan.blend` and `rowan_tripo`):

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b tools/character_build/nora/nora.blend -P tools/rig_sculpt.py -- "$PWD" ~/Downloads/tripo_export.glb nora_tripo --faces 30000 --tex 2048 --render /tmp/rig_check
```

Pictures are in `art/turnarounds/nora/tripo/` and `art/turnarounds/rowan/tripo/`. For the next character, Tripo's Clean Topology (quad) mode should bend better at elbows and knees; Generate in Parts and 8K textures don't help here. A turnaround with the arms a little away from the body keeps hands from fusing to hips.

**TripoSR (one picture).** `tools/run_triposr.py` makes a mesh from a single cut-out picture with [TripoSR](https://github.com/VAST-AI-Research/TripoSR) in about a minute on the Mac GPU, and writes a `rig_ready.ply` for step 4. Nora's try is `assets/nora_tsr.glb` (`model_triposr`): a good silhouette at playing distance, but soft up close. Pictures are in `art/turnarounds/nora/triposr/`. The pictures, report and timelapse are in `art/turnarounds/nora/sculpt/`.

**Procedural characters.** `tools/build_character.py` holds a spec for each character: body proportions (height, shoulders, waist, hips, bust, limbs, head), face, hair style, palette and outfit. Every character gets the same skeleton and the same animations, so a loop added once works for everyone. A spec can also pick its own style for some loops (`"anim": "nora"`): Nora's Idle, Walk and Talk are lighter than Rowan's, with a softer arm swing and a little hip and shoulder sway. To add a character, add a spec and rebuild, list it in `data/characters.json`, and give a villager `"look": {"model": "<id>"}` in `data/villagers.json`.

Rebuild every character, and render turntables, pose sheets and a lineup:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/build_character.py -- "$PWD" --character all --render /tmp/character_render --poses
```

Run the automated smoke test, which writes screenshots and prints PASS/FAIL lines:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --autotest=/tmp/ke_shots
```
