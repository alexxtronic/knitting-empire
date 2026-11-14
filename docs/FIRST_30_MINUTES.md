# The first 30 minutes: a gameplay review

Written 2026-11-14 for Alex. It covers what a new player does in their first half hour, where it drags, and what changed in this pass. Every piece of player-facing text named here is a draft until Alex approves it.

A game hour is 10 real seconds (`HOUR_SECONDS`), so a game day is 4 minutes and the first 30 minutes are about seven game days.

## What the first half hour was

| Minutes (rough) | What happens | Coins |
|---|---|---|
| 0–4 | The bus, the welcome sign, Wren's tour of Maple Grove | 0 |
| 4–6 | The farmhouse, Gran's note and her tin | +100 |
| 6–10 | Rosa's yarn (36c), the first knit | ~64 |
| 10–12 | The strays, Rowan | |
| 12–18 | Gran's first letter (+25c on day 2), wood from Steve (~30c), the pen panel by panel | ~60 |
| 18–25 | Herding the strays in, the market stall | +60 |
| 25–30 | The porch, rent starts | ~100 |

## Where it drags

1. **Money is slow and has only one source.** Before Act 1 ends, the only income is Gran's 100c, her 25c letter and the market's 60c. Jobs and sweater orders open only after Act 1. A player who spends badly can get stuck: under 15c she can't buy wood for the pen, and under 36c she can't buy yarn.
2. **Nothing grows in the first half hour.** Seeds cost coins she needs for the story, so most players never plant before the porch. Farming should be the quickest win in the game, because turnips take one real minute.
3. **The house is never put in front of her.** The Build catalogue had 28 pieces in two tabs ("Indoors", "Yard & Garden"). No scene, goal or letter points at it, and nothing says that making the house nicer does anything.
4. **No sense of tools or progress.** She started with all six tools, so there was nothing to earn, and the axe gave 2 wood a day per tree. That made it a chore, not a resource.
5. **The story is clear but quiet about the long game.** The first half hour establishes that Gran is in Florida, that Nora is minding the farm, and that she left something behind in the city. It doesn't hint at what Nora is building toward: a home of her own and a business from her knitting.

## What changed in this pass

- **She starts with only Gran's shears.** Builder's Delight (Steve) sells everything else over the counter: hoe 25c, watering can 40c, shovel 45c, scythe 60c, axe 80c (`data/economy.json` "store"). The hoe is priced to be her first tool. Old saves keep all six tools (save version 8).
- **Seeds are things she carries.** Planting takes one seed instead of coins. She gets them from three places:
  - Gran's seed tin on the kitchen counter: 6 turnip and 2 pumpkin, with a note from Gran that points her to Steve for a hoe. Gran's main note now mentions the tin.
  - Townsfolk who give them in talk, once each, after the tour: Giorgio (pumpkin), Barbara and Lars (turnip). These are in `data/scenes/seeds.scene`.
  - Packets from Steve: 5 turnip seeds for 40c, 3 pumpkin seeds for 75c.
- **The shears trim plants.** Clicking a bush, a clover patch, a tuft or a flower clump on the farm takes it down for leaves (3 from a bush, 1 from the others). It grows back in two game days. Three leaves mulch a growing bed and bring the crop on by a quarter of its growing time.
- **The axe fells trees.** A farm tree comes down for 8 wood and grows back in 14 game days. The town's trees are off limits. Felling also counts for Act 1's wood step, so she can build the pen either way.
- **Wooden furniture can be built from her wood.** Each wooden piece has a wood cost of about a quarter of its coin price. When she has the wood, she pays in wood; otherwise she pays in coins. The catalogue shows both prices ("160c or 40 wood"). Buying wood from Steve to build saves a quarter of the coin price. Selling a piece back still gives half its coin price, so felling trees is a modest income of its own.
- **Builder's Delight's catalogue is bigger, with a tab for each room.** The tabs are Living, Kitchen, Bed & Study, Crafts, Garden and Farm, and the catalogue has grown from 28 to 53 pieces. The new pieces use models already in the game:
  - Garden: four shrubs, four flower beds, a box hedge, three rock pieces, a garden fountain, a short garden seat and a garden bin.
  - Farm: a farm stand and a chalkboard sign.
  - Kitchen: a pantry shelf, a bread oven and flour sacks.
  - Bed & Study: a writing desk and oak drawers.
  - Crafts: a yarn shelf, a sweater rack and a craft counter.
- **Act 1 text, all drafts:**
  - On the tour, Steve gets a line about tools and seeds ("Hoes are cheap").
  - The wood goal now says she can buy wood or fell a tree.

## The new first half hour

She reads Gran's note, finds the seed tin, and learns from it that she needs a hoe. She has 100c, so the 25c hoe is an easy first purchase on the way to Rosa's. By minute 10 she can have six beds of turnips in the ground, each watered from its menu (the watering can only saves the clicks). Each bed gives two turnips a minute or so later, which comes to twelve turnips and about 450c at Rosa's. That's more than twice what Act 1 paid before, and it pays for the yarn, the wood and her first furniture. If that turns out to be too generous, the tin's count is `store.seed_tin` in `data/economy.json`.

## What I'd do next (not done yet)

1. **A home score.** Each piece in the house adds comfort and beauty. A higher score lifts her happiness and her sleep. Villagers who visit could comment on it, and Gran's letters could ask after the house. This is the clearest way to make decorating matter.
2. **Make house expansion the first big goal.** Show "Expand House" in a goal after Act 1, with the price and what it adds (a room, more floor). The first expansion costs 800c (`expand_costs`). A cheaper first step, around 300c, would fall inside the first half hour and give a strong sense of growth.
3. **An Act 1 goal for the first crop.** Add "Plant Gran's seeds" between the knit and the strays, so every player plants once, with a toast when the first harvest sells.
4. **More uses for leaves.** For example, a dye for yarn (green-tinted designs), wreaths and garlands as house decorations built from leaves, or bedding for the barn.
5. **New furniture models.** The catalogue still needs real house pieces: beds, curtains, shelves, wall art, a dresser, chairs, kitchen sets, a bathtub, windows. That's a job for the kiln asset pipeline, one piece at a time, in its own session.
6. **Recipes that use wood beyond the catalogue.** Planter boxes, bird houses, a wood store, and fences she can make herself.
7. **Check the money curve with a timed play-through** once these changes settle, and set the prices in `data/economy.json` so she can afford something new about every five minutes.
