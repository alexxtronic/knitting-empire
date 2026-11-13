# Knitting Empire

A cozy life-sim prototype built in Godot 4. Raise sheep, knit sweaters, grow crops, decorate your house, make friends in the town of Maple Grove and buy property to rent out.

![Rowan and Nora](tools/character_build/lineup.png)

## Play

1. Install [Godot 4.7+](https://godotengine.org/download) into `/Applications`.
2. Double-click `Play.command`, or run:

```bash
open -n -a /Applications/Godot.app --args --path .
```

Controls:
- Click the floor to walk. Hold the button down and she keeps walking toward the mouse until you let go.
- The map in the top right corner, under the coins, shows the land round you. Click it to walk there. The mouse wheel or its + and - buttons zoom it.
- Click objects and people to open a ring of actions round them. Click an option, or press its number (1 to 9).
- WASD or the arrow keys pan the camera.
- Q and E rotate the camera, and the scroll wheel or a trackpad pinch zooms.
- Space or the lock button locks the camera to your character.
- C toggles the walls.
- B toggles Build mode. In Build mode, R rotates a piece, X sells it and Esc cancels.
- P (or Menu > Cinematic camera) turns on cinematic mode, a free camera that leaves Nora where she is and stops the clock. WASD flies, the mouse looks round (the arrow keys or a two-finger swipe also work), E or Space climbs, Q or C sinks, Shift goes faster, Alt slower, and the scroll wheel sets the cruising speed. It goes right down to the grass and up to 300 m. F, Enter or a click takes a photo, H hides the hint, and Esc or P goes back to Nora. Photos are saved as PNGs in Godot's user folder (`user://photos/`), named by the date and the time in the game, and **Menu > Photo album** shows them as thumbnails, full size, and lets you delete them.
- V (or Menu > First person) plays in first person, through Nora's eyes. The mouse looks round (the arrow keys or a two-finger swipe also work), WASD walks her the way she looks, S steps back and Shift jogs. Look down and you see her own arms, hands, legs and feet. A click or E uses what's under the dot in the middle of the screen, with the same ring of actions as clicking it from above. Indoors there's a ceiling over her: every building's roof stays on in first person, while from above it lifts off whenever she's inside (and, for her house and the cottage, while you're building or placing furniture). V or Esc goes back to the overhead camera, and so does a story scene, bed, the knitting game, a chat, building mode, the dog (Tab) or the cinematic camera (P).

The game opens on a title screen (Continue, New Game, Settings, Quit) over the farm. **Settings** (also behind the Menu button, or Esc) has the picture quality, music and sound volumes, full screen, and switches for the frame counter and the on-screen camera buttons, all kept per computer in `user://settings.cfg`.

## What's in it

- **Act 1: Cast On.** A new game opens on the story. Nora steps off the last bus in the rain, running from something she won't name, and walks up to the Welcome to Maple Grove sign. The rain stops, the arrival music swells, and the camera takes in the town (Giorgio at his bakery stall, Barbara the postwoman on her round) before coming back to her: "I think I'm going to like it here." Wren the mayor, brisk and plainly stressed, gives her a ten-minute tour (Steve, Rosa, Giorgio, Gary and Sabrina) and leaves her at Gran's door. Gran is in Florida for her health, staying with her sister, and Nora looks after the farm while she's away. Inside, Gran's note on the coffee table goes into her bag, with 100 coins and a request: a little rent in Gran's tin each week (20c every 7 days, `data/economy.json` "story"). She buys yarn from Rosa at the Yarn Barn, knits her first sweater in the rocking chair (the first memory thread, a sepia flashback to the navy sweater her ex threw away), then follows the bleating to two stray sheep by the pond, where she meets Rowan. To keep them she buys wood from Steve at Builder's Delight, builds a pen panel by panel (**F**, or the Build pen button: click to lay a panel for 1 wood, right-click to take one up, drag to lay a run) and crafts a gate (**G**: 2 wood, `data/recipes.json`), then herds the strays in: they shy away from her. She sells the sweater to Rosa at the market stall, who gives her wool on credit, and ends the day on the porch with a voicemail from her lawyer and Rowan's lantern. Choices set flags and relationship stats for later. Memories and notes go into the **Journal** (Menu, or Esc). Old saves skip it; start a **New Game** to see it. The farm part is `scripts/homestead.gd`. A recording of the old opening is in [`docs/opening.mp4`](docs/opening.mp4).
- **Home and farm:** a house you can expand, furniture to place, sheep to shear, crops to plant, water and harvest, and a shipping bin.
- **Maple Grove:**
  - villagers with friendship hearts, gifts and dialogue (the cast Alex set on 2026-11-12, `data/villagers.json`):
    - **Rosa** Marchetti: the Yarn Barn (wool, sheep, and she buys sweaters), and the market stall on mornings (8 to 12)
    - **Gary**: the estate agent at Willow Homes, a snarky pretty boy. He calls at the farm on her second day to pitch three plots of land she can't afford (Eastfield Acres, Greyspine Hollow, Saltmeadow Point: `data/economy.json` "land", `data/scenes/town.scene`), then every two weeks to pitch trading up. Buying land isn't in yet
    - **Giorgio**: the baker at Heart Bakery, fatherly, kind, running from something
    - **Sabrina**: the Coffee Shop's snarky teenager (coffee warms Nora up). She starts cool (trust -20) and has to be won over
    - **Steve**: Builder's Delight (wood), gruff and few words, soft-hearted
    - **Wren**: the mayor, brisk, busy and always stressed
    - **Barbara**: the postwoman, kind and full of wise advice. At nine every morning she walks the post to every door in town and out to Nora's mailbox
    - **Rowan**: the shepherd (below)
  - The six new faces wear their Tripo models (`data/characters.json`), with painted eyes until their real eyes are made
  - daily market prices
  - a wool shop where you can also buy sheep
  - Rosewood Cottage, which you can buy, furnish and rent out
- **Life-sim UI:** actions open in a ring round whatever you click, with progress bars on things that take time (crops, wool, knitting). The screen is kept bare: a Menu button, her coins, the clock, and a hotbar along the bottom with what she carries (keys 1 to 9 pick a slot, I opens the bag of 27 more, and Build at its end opens Build & Buy). She owns six tools (hoe, watering can, shears, shovel, axe, scythe): with one in her hand a click uses it, so the hoe digs new beds on open ground, the shovel clears them, the axe takes wood from a tree once a day and the scythe cuts hay. Each tool has its own model (`assets/props/<tool>.glb`) and shows in her right hand while it is picked; the watering can hangs from its handle. Their hotbar pictures in `assets/icons` are cut from the reference sheet in `art/world_assets/tools` (`make_icons.py`). Energy, Hunger, Happiness, Love, Warmth and Fitness are bars with trend arrows, top left under the Menu button. Build mode shows furniture as picture cards rendered in the game.
- **The post:** Barbara fills the mailbox by Nora's porch on her nine o'clock round; the red flag goes up when there's something in it. Click the mailbox to take the post out and read it (or Menu > Letters). Gran writes from Florida (sometimes with a few coins or a little wool), Daniel writes asking Nora to come home, and customers far away order sweaters by post: put a sweater of the stars they asked for in the mailbox, Barbara takes it the next morning, and the payment comes the morning after (a tip for each star more than they asked). Letters are in `data/mail.json`; the code is `scripts/mail.gd` and `scripts/letters_panel.gd`.
- **Jobs:** a steady wage beside knitting. After Act 1, Giorgio offers Nora mornings at Heart Bakery; Sabrina takes her on at the Coffee Shop in the afternoons once she trusts her (trust 10); Barbara shares the morning post round. Nora holds one job at a time (taking another leaves the old one) and works one shift a day: she clocks in by talking to the boss in the job's hours, then walks from task to task (the oven, the flour, the shelves; the café terrace; every door in town) while the clock moves on and her needs drain, and is paid at the end, or in part if she stops early. Pay, hours, tasks and the bosses' lines are in `data/economy.json` "jobs", the offers in `data/scenes/jobs.scene`, the logic in `scripts/jobs.gd`. All drafts for Alex.
- **Needs:** Warmth follows the weather, the time of day, being indoors and the best sweater she owns (knitting gets better with practice). Love fills from time with people. Fitness grows with walking and farm work and makes her walk a little faster.
- **Rowan (romance v1):** after Act 1, talking to Rowan opens one new topic a day as he warms up: his sheep, Gran (and Nora's memory of Gran's burnt bread), the long evenings on the hill. Gifts land differently with each villager (loved, liked, anything else), and with Rowan they can grow romance; the first sweater you give him has its own scene. At three hearts he asks Nora up to the rock in the back field at sunset, where she darns the hat Gran knit him and decides how close to let him. Later, if he trusts her, he tells her about Anna.
- **Talking to villagers:** besides **Talk** (hand-written lines), **Chat...** lets you type to any villager, who answers in character (see [Chatting with villagers](#chatting-with-villagers)).
- **World:** real grass (tens of thousands of blades that sway in the wind and part round Nora, worn earth on paths), trees that move in the wind, a pond with ripples and rain rings, a sky with drifting clouds and stars, soft shadows, bounce light, a light haze for sunbeams and mist, and depth of field in close-ups.
- **Sound:** footsteps on grass and on wood floors, needle clicks while she knits, page turns for the journal, soft UI clicks, birdsong by day, crickets at night and rain that cross-fade with the clock and the weather (muffled indoors), and an original guitar and flute tune, "Cast On". During a memory flashback the music goes distant and muffled. Every sound is made by `tools/make_audio.py`, so there are no samples or licences to track; real recordings can replace them later under the same file names in `assets/audio/`.
- **Tips:** after Act 1, a one-time tip appears at the bottom of the screen the first time something becomes possible (shearing, knitting, selling, sleeping, Rowan, Build mode). Click it to dismiss.
- **Graphics setting:** the **Graphics** button in Settings cycles High, Medium and Low (saved per computer in `user://settings.cfg`). Medium drops the bounce light and reflections and thins the grass; Low also drops the haze, contact shading and lamp shadows and draws less grass, nearer. On every setting the 3D view is drawn at a fixed pixel budget and upscaled (MetalFX on Macs), so a bigger window looks sharper without getting slower.
- **Characters:** Nora (the heroine you play, working name) and Rowan (the shepherd in Maplewood) were first generated by the Blender script `tools/build_character.py`. Both now play with models made on [tripo.ai](https://www.tripo3d.ai) from their turnarounds and put on those rigs (`assets/nora_tripo.glb`, `assets/rowan_tripo.glb`); the generated bodies, and Nora's two earlier experiments (image-to-sculpt and TripoSR), are kept in `assets/` for comparison. Each is one skinned mesh on the same 22-bone humanoid skeleton, named to match Godot's humanoid profile, and both share the same loops: Idle, Walk, SitKnit, SitIdle, Work and Talk. Knitting needles and a swatch appear while knitting. Nora and Rowan move with motion capture: Idle, Walk, Talk, SitIdle and Work (kneeling, for chores) come from Quaternius's [Universal Animation Library](https://quaternius.itch.io/universal-animation-library) (CC0), retargeted onto our skeleton by `tools/retarget_anims.py`. They also have a Run loop, a light jog the player gets by holding Shift. SitKnit is still our own knitting loop. When they look at someone, the turn is shared between the upper chest, neck and head, and the head is skinned as one rigid piece from the jaw line up (`tools/rigid_head.py`, run by `rig_sculpt.py`), so faces don't bend. Nora walks at about 1.1 m/s and jogs at about 3 m/s (both rise a little with fitness); villagers stroll at 1 m/s.

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
| `scripts/hud.gd` | HUD, hotbar and bag, menus, camera pad, dialogue |
| `scripts/town.gd`, `villager.gd`, `dialogue.gd` | Maple Grove |
| `scripts/homestead.gd`, `play_ui.gd`, `data/recipes.json` | Act 1's farm: the pen builder, gate crafting, the strays and herding, Gran's note and rent |
| `scripts/player.gd` | the character you play and her activity states |
| `scripts/body.gd` | a skinned character body; picks and cross-fades animation loops |
| `scripts/story.gd`, `story_player.gd` | reads and plays the plain-text story scenes in `data/scenes/` |
| `scripts/pie_menu.gd` | the ring of actions |
| `scripts/thumbs.gd` | renders the Build mode picture cards |
| `scripts/ai_chat.gd`, `chat_panel.gd`, `data/personas.json` | typed chat with villagers |
| `scripts/mail.gd`, `letters_panel.gd`, `data/mail.json` | the post: the mailbox, letters and sweater orders, and the letters panel |
| `scripts/cinematic.gd`, `photo_album.gd` | cinematic mode (the free camera and its photos) and the photo album |
| `scripts/first_person.gd` | first person: the camera at Nora's eyes, her head hidden from it |
| `scripts/regions.gd`, `data/regions.json` | the lands round the farm: Mirewood Swamp, Greyspine Foothills and the mountains, Saltmeadow Beach and the sea, Eastfield Meadows, and the trails out to them |
| `scripts/god_mode.gd`, `data/world_layout.json` | the admin's world editor (Settings > God mode) and the map layout it saves |
| `scripts/audio.gd` | music, ambience and sound effects on three buses (Music, Ambience, SFX) |
| `tools/make_audio.py` | makes every sound in `assets/audio/` (footsteps, needles, UI, ambience loops, the music) |
| `scripts/rig.gd` | procedural motion on top of the loops: head turns to look at people, idle glances and weight shifts, leaning into turns, breathing |
| `scripts/grass.gd` | the ground and the grass blades |
| `scripts/lighting.gd`, `shaders/mist.gdshader` | the morning mist and its light shafts, SDFGI on High |
| `art/world_assets/light_bake/build.py` | Cycles light bake: each static prop's contact shadows and bounce light, baked into its GLB |
| `shaders/woolcore.gdshader` | the felt and knit look |
| `shaders/ground`, `grass_blade`, `foliage`, `water`, `sky` | ground, grass, trees, pond and sky |
| `docs/woolcore/` | style frames (ignored by Godot) |
| `tools/build_character.py` | Blender character generator: builds `assets/<id>.glb` |
| `tools/cutout_views.py`, `project_colors.py`, `run_triposr.py`, `rig_sculpt.py` | turnaround to sculpt to rigged character (see [Characters](#characters)) |
| `tools/retarget_anims.py` | motion-capture loops (Quaternius's CC0 library) onto a character's rig; see `AGENTS.md` for the command |
| `tools/rigid_head.py` | re-skins a rigged character so the head turns as one piece on a short band of neck (`rig_sculpt.py` runs it; can also fix an existing `.blend`) |
| `tools/import_asset.py` | brings any generated model (Tripo, etc.) into the Woolcore look: `assets/props/<id>.glb` |
| `tools/import_textured.py` | brings a textured model in looking like the original (its own texture and normal map, decimated and game-sized): the sheep |
| `tools/join_meshes.py` | joins a many-part model into one mesh (one draw call per material): the market stall and coffee table |
| `data/palette.json` | the 31 Woolcore colours every surface uses |
| `docs/STYLE_GUIDE.md` | the art rules: palette, materials, shapes, polygon budgets, UI, asset pipeline |

## Adding content without code

Prices, furniture, crops, villagers and their lines all live in `data/`. Edit the JSON and run the game.

- **A new price or limit:** change it in `economy.json`.
- **A letter or a sweater customer:** add it to `mail.json` (its `_about` lists every field: when it comes, what's enclosed, what an order wants and pays).
- **A job:** add it to `economy.json` "jobs" (its boss, building, hours, pay, tasks and lines; the `_about` there lists every field) and write its offer as a `job_<id>` scene in `data/scenes/jobs.scene`.
- **A new villager:** add an entry to `villagers.json`, then give them an intro, three tiers of lines and a loved-gift line in `dialogue.json`. Give them `"works_in": "shop"` (or `bakery`, `office`, `homegoods`) to put them behind that shop's counter, or `"at"` to stand them by a building that isn't walk-in (Sabrina on the Coffee Shop's terrace). The `_about` at the top of `villagers.json` lists every field.
- **A shop's furniture:** `interiors.json` lists what stands in each shop you can walk into (the Yarn Barn, Heart Bakery, Willow Homes, Builder's Delight), where the shopkeeper stands and where you stand to talk to them, all in the building's own space, so it all moves with the building in the world editor.
- **A new crop:** add it to `crops.json` and give it a sell price in `economy.json`.
- **Furniture:** add it to `furniture.json`. Either give it a `"model"` (a glb made with `tools/import_asset.py`, see [`docs/STYLE_GUIDE.md`](docs/STYLE_GUIDE.md)) or write a builder in `catalog.gd`.

The autotest checks the files against each other and names anything missing.

Story progress is kept as named flags (`Game.set_flag("met_rowan")`, `Game.flag("met_rowan")`) and saved with the game. Save files carry a version number. When the format changes, add a step to `Game.migrate()` so older saves still load.

When exporting, add `data/*` to the export preset's non-resource include filter, so the JSON and scene files ship with the game.

## God mode: arranging the world

The map is laid out in the game itself. Run the game from the project, open **Settings**, and under **God mode** switch on **Edit the world**. (The switch is for the admin only: it appears when the game runs from the project with the Godot editor build, and never in an exported game.)

- **Select & move:** click anything (a tree, a rock, a hedge, a lamp post, a shop, the fountain, a crop plot) and drag it. Hold Shift to snap to 25 cm.
- **Turn:** R turns the selected thing 15 degrees to the left, T to the right.
- **Resize:** + makes the selected thing bigger and - smaller (10% a press, from a fifth to five times its size). While placing, they resize the preview and everything set down after it. The Place list also has "Rock cluster (small)" and "Rock (small)", which start at half size.
- **Delete:** Delete, Backspace or X. **Copy:** Ctrl/Cmd+D (scenery, lamp posts, benches and other decor). **Undo:** Ctrl/Cmd+Z.
- **Place:** choose anything from the drop-down next to Place (every kind of tree, rock, plant and leaf, every model in `assets/props`, every catalog piece) and it appears under the pointer with a green outline. R and T turn it. Click to set one down, or hold the button and drag for a stream of them (Shift keeps the stream on a straight line; fences and hedges dragged along their length join end to end).
- **Roads:** pick Dirt road, Gravel road or Cobblestones and drag to paint. One click with a wide round brush makes a round patch (a cul-de-sac). Hold **Shift** while dragging for a straight line; it snaps to the nearest 45 degrees and follows the pointer until you let go. The brush can be round or square and up to 30 m across; `[` and `]` change its size. Erase road rubs out any road, including the plaza and paths the game starts with. Painting a road clears the grass, tufts and flowers under it.
- The camera works as usual (WASD, right-drag, wheel) and can go out to the far trees. The clock stops while you edit.
- **Done** saves. The layout goes to `data/world_layout.json`, which the game applies every time it starts: it is the map every player gets, so commit it. **Reset world** throws the saved layout away.

The sheep pen moves as one piece and turns in quarter turns; the sheep go with it. Nora's house and Rosewood Cottage can't be moved (the game's rules are tied to where they stand), nor can villagers or single sheep.

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
- `@music arrival` plays `assets/audio/music_arrival.ogg` over the scene (`@music off` fades it). `@farm note` hands over Gran's note and her 100 coins and starts the rent; `@farm strays` puts the two stray sheep out by the pond.
- `@time 21:30` sets the clock, `@sleep` ends the day, `give`/`take` also work with `coins`, and `@if has sweater -> label` branches on what's in the bag.
- `@when hearts rowan >= 3` (or any stat, `hour < 17`, `has sweater`) holds a scene back until it's true. `@daily` lets at most one such scene play a day, which paces a run of talk topics. `@trigger gift rowan sweater` plays after a gift.
- `@camera between rowan nora 4.5 low` drops the camera to a low, close angle for intimate moments.
- Rowan's romance is in `data/scenes/rowan.scene`. Gift reactions are `likes` and `romance` in `villagers.json` and `gift_lines` in `dialogue.json`.
- Staging commands set the goal shown at the top of the screen (with a marker on the map), make it rain, put down props like a bus or a suitcase, ring the phone, shake the camera, let the sheep out, and park a villager somewhere until a later scene sends them home.
- A scene plays when you talk to someone (`@trigger talk rowan`), on a new game (`@trigger start`), when you walk into a named place from `data/areas.json` (`@trigger area farm_gate`), or after an event such as finishing a knit (`@trigger event knit_done`). Act 1's farm fires `yarn_bought`, `wood_bought`, `pen_built` (a closed pen with a gate) and `sheep_penned`.
- Act 1 is in `data/scenes/act1.scene`, which is a good worked example.
- Relationships have three stats: **familiarity** (shown as hearts), **trust** and **romance**.
- The autotest checks every scene file, so a typo or a jump to a missing label shows up as a failed check.

## Woolcore style (v0)

The world is meant to look handmade: felt and knitting.

The full rules (palette, materials, shapes, polygon budgets, UI and how to bring in new models) are in [`docs/STYLE_GUIDE.md`](docs/STYLE_GUIDE.md), a draft waiting for sign-off.

![The farm](docs/woolcore/style_01_farm.png)

- **Shader:** `shaders/woolcore.gdshader`. Every solid surface is felt, with soft mottling, fine fibres and a fuzzy rim. The shader can also knit surfaces in stockinette stitches, but that overlay is switched off for now (`KNIT_STITCHES` in `scripts/catalog.gd`), so everything is plain felt. Textures are projected in world space, so the felt grain stays the same size on any shape.
- **Which surfaces would be knitted** (with `KNIT_STITCHES` on): the `KNIT` list in `scripts/catalog.gd` (a colour and a stitch width) and the `knit` widths in `data/palette.json`. Glass, water and glowing things stay plain. Set `Catalog.woolcore = false` to compare with the old look.
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

**Light.** Two halves. Live, in Godot: the sun moves through the day with soft shadows that are crisp where a thing touches the ground and blur further out, screen-space bounce light and contact shading, SDFGI on High (light bouncing across the whole scene, the sky shut out under the trees and indoors), and a morning mist (`scripts/lighting.gd`): a low, patchy volumetric fog that rises before first light, is thickest when Nora wakes at 6 and burns off by about 10, with the low sun's shadows through it as shafts of light between the trees. Baked, in Blender: `art/world_assets/light_bake/build.py` path-traces each static prop in Cycles under a white sky (the shade under a bench seat, the creases of a sofa, the foot of a wall, and the light bouncing back into them) and bakes it into an atlas inside the prop's GLB, which Godot reads as ambient occlusion. Only what is close to the prop counts, so the bake moves with it when it's moved in the world editor; the sun's shadows stay live because the sun moves.

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

Add `--only=photo` after it to check just cinematic mode and the photo album (about fifteen seconds), or `--only=fps` for just first person (about fifteen seconds). See `AGENTS.md` for the other quick checks.
