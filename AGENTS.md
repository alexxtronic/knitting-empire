# AGENTS.md

Notes for AI coding agents (Codex, Claude Code and others) working on Knitting Empire. People should start with `README.md`, which explains the game, the project layout and how to add content.

## The project

- A cozy farm, knitting and life-sim game made in **Godot 4.7** (GDScript, Forward+). Main scene: `main.tscn`. Most of the game logic is in `scripts/main.gd`, and the UI is in `scripts/hud.gd`.
- Content is data, not code. Furniture, crops, prices, villagers, dialogue and areas are in `data/*.json`, and story scenes are plain-text files in `data/scenes/*.scene`. To add content, edit the data first. `README.md` ("Adding content without code" and "Writing story scenes") explains the formats.
- The owner is Alex D'Amore. The art style rules are in `docs/STYLE_GUIDE.md` (a draft; don't treat it as final).

## Run it

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

If you add or replace files under `assets/`, import them first. This writes their `.import` files:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
```

## Test it: the autotest must pass

Every change to the game's code or data must keep the autotest green. A change that only adds or rebuilds an asset (a model, its textures, its `model` line in `data/furniture.json`) doesn't need the full run (Alex, 2026-11-12: "we don't need autotests for every single asset we make"): import it, run the matching quick check if there is one (`--only=house`, `--only=bench` and so on, a few seconds each) and look at its screenshot. The autotest opens a real game window (the renderer is needed, so it can't run headless) and plays through the game: farming, building, the town, the story (Act 1) and Rowan's romance scenes, plus sound, the title screen, settings and tips. It prints a `PASS` or `FAIL` line for each check and saves screenshots to the folder you give it. A full run takes about 6 to 8 minutes.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1280x800 -- --autotest=/tmp/ke_shots > /tmp/ke_autotest.log 2>&1
grep -c '^PASS' /tmp/ke_autotest.log   # expect 196 at the time of writing
grep -E '^FAIL|SCRIPT ERROR|Parse Error' /tmp/ke_autotest.log   # expect nothing
```

- The log must end with `AUTOTEST DONE`. If it doesn't, the script crashed: look for `SCRIPT ERROR` in the log.
- The checks are in `scripts/main.gd`. `_autotest()` calls `_story_checks`, `_act1_checks`, `_romance_checks`, `_polish_checks` and others. When you add a feature, add a check for it there.
- To check only the park benches and trash cans (the models, the one-in-five short bench, sitting on each), add `--only=bench` after `--autotest=DIR`. It takes a few seconds and saves `43_bench.png`, `43_bench_short.png` and a `43_trash_can_N.png` for up to three cans.
- To check only the HUD (the hotbar and bag, the Esc menu, the need bars, the settings switches), and the six tools (each used once on the farm), add `--only=hud`. It takes about a minute and saves `46_hud.png`, `46_bag.png`, `47_tools_hotbar.png`, `47_tools_bed.png` and `47_tool_in_hand.png`. Make the folder you give `--autotest=` first, or the pictures aren't saved.
- To check only the barn (the model's parts, walking in and out, how it opens up) and the flock's bedtime (the sheep walk to their stalls at dusk and back to the pen at first light), add `--only=barn`. It saves `44_barn.png`, `44_barn_inside.png`, `45_flock_going_in.png` and `45_flock_in_stalls.png`. The rest of the autotest runs with bedtime off (`flock_bedtime`), so its sheep stay in the pen.
- To check only the walk-in shops (Woolly Goods, the bakery, the land office: walking in through each door, how it opens up, the shopkeeper behind the counter, Hazel's croissant), add `--only=shops`. It saves `46_<shop>.png` and `46_<shop>_inside.png` for `shop`, `bakery` and `office`.
- To check only the house furniture (the twelve models, the fire's flames and light, the lamp's light), add `--only=house`. That run also sets out the pieces a new house doesn't start with and saves `46_house.png` and three closer pictures.
- Only run one autotest at a time. Two Godot windows at once slow the machine down, and the time-based checks then fail at random.
- The test window ignores the real mouse (clicks pass through to whatever is behind it) and the real keyboard (the game only acts on the keys the test presses itself), so you can keep working while it runs.
- macOS stops drawing a window that is completely covered, and the test then waits forever at its next screenshot. If Alex has the game open, start the test where a strip of it stays visible and without taking focus: `open -g -n -a /Applications/Godot.app --stdout /tmp/ke_autotest.log --stderr /tmp/ke_autotest.log --args --path "$PWD" --resolution 1280x800 --position 0,30 -- --autotest=/tmp/ke_shots`, then wait for `AUTOTEST DONE` in the log.
- The autotest mutes all sound, never touches the network (AI chat uses a stand-in), and doesn't write the player's settings.
- The autotest's last step is the world editor (`_god_checks`): it builds the world again without the saved layout, edits it, saves a layout to its own file in Godot's user folder (never `data/world_layout.json`), then loads the scene again from that file. To run only that step (about a minute): `-- --godcheck=/tmp/ke_god`.

## The world layout: `data/world_layout.json`

Alex arranges the map himself in the game: Settings > God mode > "Edit the world" (`scripts/god_mode.gd`; the switch only shows when the game runs from the project with the Godot editor build, never in an exported game). He can move, turn, copy and delete scenery and buildings, and paint dirt, gravel and cobblestone roads. It saves to `data/world_layout.json`, which every launch applies on top of what the code builds, so that file is the final map.

- Don't hand-edit or delete `data/world_layout.json`, and commit it when it changes. It is Alex's work.
- The autotest runs with the layout applied, because that's the game players get. If a check fails only because of where something now stands (a bench the test sits on was moved, say), fix the check to find the thing rather than the layout. `-- --nolayout` runs the game as the code builds it, to tell the two apart.
- Once a kind of scenery (a tree kind, rocks, a bush kind, tufts) has been edited, its full list is in the file and replaces what `world.gd` and `nature.gd` scatter. Changing their random placement no longer moves that kind. Single things (shop fronts, fountain, stall, signposts, barn, bin, plots, lamp posts, benches) are stored as changes named by kind and original position (`decor_lantern@46.00,-5.40`). If you move one in code, its saved change no longer matches: the game prints a `world layout:` warning and keeps the entry in the file.
- Anything new you add to the world should be editable too: build it as its own node and register it in `GodMode.collect()`, or scatter it as a MultiMesh under `nature` (those are picked up automatically). Loose boxes added straight to the world root can't be selected (the sheep pen and the pond were built that way at first). Every model in `assets/props` shows up in the editor's Place list by itself.
- The sheep pen can be moved: use `main.pen_rect`, not the `PEN` constant, for where it is now.
- Painted roads replace `World.PATHS`, `Town.PATHS` and the plaza cobbles as soon as the file has a `roads` entry. Read `god.road_at(x, z)` rather than those constants if you need to know what's underfoot.

## GDScript gotchas

- `:=` can't infer a type from a Variant. `Game.flag(...)`, `Game.stat(...)` and anything read from a Dictionary return Variant, so give the variable an explicit type: `var done: bool = Game.flag("act1_done") == true`. If you don't, the whole of `main.gd` fails to parse and the game won't start.
- Indent with tabs, and use static types wherever you can.
- Commit each `.uid` and `.import` file together with its script, shader or asset. Godot needs them. Never commit `.godot/` (it's in `.gitignore`).

## Generated assets: don't hand-edit them

| What | Made by | Rebuild with |
|---|---|---|
| `assets/nora.glb`, `assets/rowan.glb` (procedural bodies, shared 22-bone rig and animation loops) | `tools/build_character.py` (Blender) | `Blender -b -P tools/build_character.py -- "$PWD" --character all` |
| `assets/nora_tripo.glb`, `assets/rowan_tripo.glb` (the models the game uses, from tripo.ai) | `tools/rig_sculpt.py` (Blender), then `tools/retarget_anims.py` for the mocap loops | the command in the README's Characters section (it needs the source export, which isn't in the repo), then the retarget command below |
| `assets/portraits/<id>_<mood>.png` (the faces beside story lines: eight moods each for Nora and Rowan, rendered from the models the game plays with, with the lid shapes of `scripts/face.gd`) | `tools/render_portraits.py` (Blender) | `Blender -b --factory-startup -P tools/render_portraits.py -- "$PWD"`, then import. Run it again whenever a character's model or face changes |
| `assets/textures/planks/wall_planks.png`, `floor_planks.png` and their `_n` normal maps (five boards each, side by side; `scripts/planks.gd` lays the houses' boarded walls and every building's plank floor from them, each floor in its own shade: `Planks.SHADES`) | `art/world_assets/planks/build.py` (Blender; the grain is `grain.py` beside it) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/planks/build.py`: it copies the atlases to `assets/textures/planks/`; then import |
| `assets/audio/*` (every sound and the music) | `tools/make_audio.py` | `uv run --no-project --with numpy --with scipy python tools/make_audio.py "$PWD"` |
| `assets/props/*.glb` (Woolcore palette props, e.g. `milk_churn`) | `tools/import_asset.py` | see `docs/STYLE_GUIDE.md` |
| `assets/props/sheep_woolly.glb`, `sheep_sheared.glb` (their own Tripo texture; rigged, with Idle, Walk and Graze loops) | `tools/rig_sheep.py` | `Blender -b --factory-startup -P tools/rig_sheep.py -- "$PWD" "<fluffy sheep 3d model.glb>" sheep_woolly --height 0.95 --yaw 90 --faces 40000`, and the same with the lamb plush export, `sheep_sheared --height 0.99 --faces 24000`. The source exports are in Alex's Downloads, not the repo. It prints each model's `STRIDE`: put it in `scripts/sheep.gd` (`STRIDE`) |
| `assets/props/building_shop.glb`, `building_bakery.glb`, `building_office.glb` (the shop fronts you can walk into, exported in parts like the barn: `base`, `wall_<side>` and `wall_<side>_low`, `door` hinged on its left jamb, `roof`; `scripts/interiors.gd` uses those names) | `art/world_assets/town_buildings/build.py` (Blender) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/town_buildings/build.py -- shop` (or `bakery`, `office`): it copies the GLB to `assets/props/`; then import |
| `assets/props/shop_counter.glb`, `yarn_shelf.glb`, `sweater_rack.glb`, `bakery_counter.glb`, `bread_rack.glb`, `brick_oven.glb`, `flour_sacks.glb`, `office_desk.glb`, `filing_cabinet.glb` (the shops' furniture; laid out per shop in `data/interiors.json`) | `art/world_assets/interiors/build.py` (Blender; reviewed with blender-kiln, log beside it) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/interiors/build.py -- <kind>` (or `all`): it copies the GLB to `assets/props/`; then import |
| `assets/props/bench_park.glb`, `bench_park_short.glb` (the park bench and its half-length single seat; shaders baked to textures) | `art/world_assets/bench_park/build.py` (Blender) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/bench_park/build.py`, then copy `out/bench_park.glb` and `out_short/bench_park_short.glb` to `assets/props/` and import |
| `assets/props/barn.glb` (the farm barn, exported in parts: `base`, `roof`, `interior`, `door_l`, `door_r`, the stall gates `gate_l0`, `gate_l1`, `gate_r0`, `gate_r1`, and each wall as `wall_<side>` and `wall_<side>_low`; `World.build_barn` and `World.update_barn` in `scripts/world.gd` use those names) | `art/world_assets/barn/build.py` (Blender) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/barn/build.py`, then copy `out/barn.glb` to `assets/props/` and import |
| `assets/props/rocking_chair.glb`, `fireplace.glb`, `kitchen.glb`, `sofa.glb`, `armchair.glb`, `spinning_wheel.glb`, `dining_table.glb`, `bookshelf.glb`, `wardrobe.glb`, `lamp.glb`, `plant.glb`, `rug_red.glb` (the furniture of Nora's house; the rug's knitted colourwork is drawn stitch by stitch by `knit.py` beside the build script; `Catalog.build` adds the fire and the lamp light; the sofa's throw is draped by cloth simulation during the build, and the tartan's wool comes from the CC0 scans in `art/world_assets/textures_web`) | `art/world_assets/house_furniture/build.py` (Blender) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/house_furniture/build.py [-- id ...]`, then copy each `<id>/out/<id>.glb` to `assets/props/` and import |
| `assets/props/trash_can.glb` (the barrel trash can; the bench's wood and iron shaders, baked) | `art/world_assets/trash_can/build.py` (Blender; it loads `bench_park/build.py` for the shaders) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/trash_can/build.py`, then copy `out/trash_can.glb` to `assets/props/` and import |
| `assets/props/fence_section.glb`, `fence_post.glb`, `fence_rails.glb` (the sheep pen's fence: `World.build_pen` uses the post and the rails), `hay_bale.glb`, `scarecrow.glb` | `art/world_assets/farm_props/build.py` (Blender; reviewed with blender-kiln, logs beside it) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/farm_props/build.py -- <kind>` (or `all`): it copies the GLB to `assets/props/`; then import (Godot extracts its textures beside it) |
| `assets/props/bakery_stall.glb`, `chalkboard_sign.glb`, `daisy_crate.glb` | `art/world_assets/bakery_stall/build.py` (Blender; reviewed with blender-kiln, logs beside it) | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/bakery_stall/build.py -- <kind>` (or `all`), then import |
| `assets/props/axe.glb` (the first of Nora's six hand tools; the others still show only their hotbar pictures) and `assets/icons/*.png` (the tools' hotbar pictures, cut from `art/world_assets/tools/reference_sheet.png`) | `art/world_assets/tools/build.py` (Blender; reviewed with blender-kiln, log beside it) and `art/world_assets/tools/make_icons.py` | `Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/tools/build.py -- axe` (it copies the GLB to `assets/props/`), then import. Icons: `uv run --no-project --with numpy --with scipy --with pillow python art/world_assets/tools/make_icons.py` |
| `assets/props/market_stall.glb`, `coffee_table.glb` (made by Codex, parts joined; the table's cloth was moved to the palette's `rug_wine` by renaming its material in the GLB, so a re-join from the source needs that again) | `tools/join_meshes.py` | `Blender -b --factory-startup -P tools/join_meshes.py -- <in.glb> assets/props/<id>.glb` |

Animation loops: the procedural bodies get theirs (Idle, Walk, SitKnit, SitIdle, Work, Talk) from Python pose functions in `build_character.py`. The Tripo models the game uses get motion-captured loops instead: `tools/retarget_anims.py` copies Idle, Walk, Brisk, Run (the Shift jog), Talk, SitIdle and Work from Quaternius's Universal Animation Library (CC0, free on itch.io, not in the repo) onto their rigs, and keeps their SitKnit. The order matters. Re-rigging a Tripo model with `rig_sculpt.py` brings back the procedural loops, so run the retarget after it:

```bash
Blender -b tools/character_build/nora_tripo/nora_tripo.blend -P tools/retarget_anims.py -- "$PWD" "<pack>/Unreal-Godot/UAL1_Standard.glb" nora_tripo
```

It prints each loop's stride speed. Put the Walk, Brisk and Run ones in `data/characters.json` (`walk_anim_speed`, `brisk_anim_speed`, `run_anim_speed`) so the feet don't slide. Brisk is the Walk clip with a longer stride (`Brisk=Walk_Loop*1.4`); `scripts/body.gd` changes to it above a stroll, so the player's 2 m/s walk isn't the stroll played at double speed. At `*1.7` it turns into a lunge.

Heads: both `build_character.py` and `rig_sculpt.py` run `tools/rigid_head.py`, which binds everything from the jaw line up to the Head bone alone and fades that over 6 cm of neck, so a turned head never shears the face. The look-at in `scripts/rig.gd` spreads the turn over the upper chest, neck and head, and turns then nods (no roll). To fix a model rigged before this without re-rigging it: `Blender -b tools/character_build/<id>/<id>.blend -P tools/rigid_head.py -- "$PWD" <id>`.

Seated story scenes: the seated loops put the seat at the character's origin, so `@place` takes a height after the yaw for anyone sitting on something above the ground (the date rock is 0.43).

## Rules

- **Never commit secrets.** That means API keys, tokens, `.env` files, passwords, certificates, and `.p8`/`.p12` keys. Villager chat needs an Anthropic API key, but it is never stored in the repo or the game. Players paste it into the game (it's saved in Godot's user folder) or set `ANTHROPIC_API_KEY`. Don't add a key, a default key or a key file to the project.
- **Every character model gets a rigid head.** Any new character, and any new tool that rigs or re-skins one, must run `tools/rigid_head.py` (`rigid_head.make_rigid(mesh, rig)`) before export, so the face turns in one piece. It stops with an error if anything above the jaw line still follows another bone. Check a new character with its head turned about 70°, close up.
- GitHub rejects files over 100 MB. Keep large source exports (Tripo GLBs, renders) out of the repo.
- Keep commits small, and write messages that say what changed and why.
- Text players will see (dialogue, story scenes, store or marketing copy) is a draft until Alex approves it.
