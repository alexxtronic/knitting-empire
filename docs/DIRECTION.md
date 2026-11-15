# Knitting Empire: the direction (15 November 2026)

Alex narrowed the game's scope on 2026-11-15. This file is the current direction. Where it disagrees with `docs/ROADMAP.md` (10 November) or older notes, this file wins. Player-facing names, lines and prices here are drafts until Alex approves them.

## The game in one line

A Sims-like life on a farm with a Pokémon-like hunt: go out with your dog, find animals, round them up into your pen, knit their fibre into sweaters of varying quality, and reinvest the money until you own a knitting empire.

## The core loop

1. **Find animals.** Common ones (sheep, rabbits) live by the farm. Rare ones live far out: the swamp, the foothills, the far meadows, the mountains' foot. The rarer, the fewer and the further.
2. **Round them up with the dog.** Play the dog and bark (right click). Each bark frightens the animals nearby and fills their fright meter; they bolt, so he has to keep after them. At full fright an animal gives in and follows the dog, up to three at a time. He leads them home to a pen. A pen holds four animals, and she can build as many pens as she can afford.
3. **Comb or shear them** for fibre, every few days.
4. **Knit.** The rhythm game sets the sweater's quality. Rare fibre and better needles lift the least it can be.
5. **Sell.** Anyone in town may buy one face to face, haggled over. Rosa and the mailbox pay a plain price. A local's request for a particular fibre pays far more. Later: online orders and Nora's own shop.
6. **Reinvest.** Better needles, a bigger pen, rented stalls, a bigger house, land, a shop with a worker, and at the very end a city of her own with Nora as mayor.

Two rules sit over all of it:

- **Money is always meaningful and hard to get.** Early on she earns a little, pays Gran's rent and buys supplies. She grows her own food from Steve's seeds so she doesn't have to buy it.
- **Sweaters are the economy** (Alex, 2026-11-15). Every coin comes from a sweater: sold face to face to anyone in town (ask if they're looking; some days they aren't; haggle with a meter showing how likely they are to say yes), to Rosa, through the mailbox, by mail order, or for a local's request. Crops, wool and fibre can't be sold. In the beginning she scrapes by: Gran's coins build the pen, the dog herds the strays in, and their wool makes her first Common sweaters.
- **Comfort or risk is the player's choice.** Stay in town and grow slowly, or go out for rare animals, which are worth much more.

## What is parked

- **Buildings as places to work or just visit.** The town's buildings stay, but each one's purpose is the story or the business: Rosa's Yarn Barn (wool, needles, selling), Builder's Delight (tools, seeds, wood, the lantern), Lars's barn (stalls for rent), Willow Homes (land and houses), a shop front for Nora's own shop later.
- **Rosewood Cottage** stays hidden, as before.

## Phases

### Phase 1: the loop exists (done on 2026-11-15)

| Piece | Where |
|---|---|
| A day is 20 real minutes: 14 of daytime (6:00 to 20:00), 6 of night | `Game.hour_seconds()` in `scripts/game_state.gd` |
| The darkest night still has light to see by | `scripts/sky_bodies.gd` (moonlight floor), `scripts/lighting.gd` (night fill) |
| A lantern from Steve: after dark she carries it in her left hand and it lights her way | `scripts/empire.gd`, `data/economy.json` "gear", `art/world_assets/lantern/` |
| Better needles from Rosa, a step at a time: steel, rosewood, silver | `scripts/empire.gd`, `data/economy.json` "gear" |
| A right click barks as the dog; a bark fills a wild animal's fright meter; at full fright it follows him home, three at a time | `scripts/wildlife.gd`, `scripts/wild_animal.gd`, `scripts/dog.gd`, `main.dog_bark()` |
| A pen holds four animals, and every closed, gated patch of fence is a pen; Lars's barn adds four places while its rent is paid | `homestead.pens`, `wildlife.pen_capacity()`, `data/wildlife.json` "pen_size", "barn_stalls" |
| Locals ask for a sweater of a rare fibre; a goal sends her to find the animal; delivery pays well | `scripts/empire.gd`, `data/requests.json` |
| Jobs back for friendship, not money: petty cash, trust, a random drop (wool, angora, seeds, furniture) | `scripts/jobs.gd`, `data/economy.json` "jobs" |
| Sweaters the only income; anyone in town may buy one, haggled over with a meter | `scripts/sweater_sale.gd`, `data/economy.json` "haggle" |
| Requests come once a local likes her (hearts), from plain-wool sweaters early to rare fibres later | `scripts/empire.gd`, `data/requests.json` |

### Phase 2: money and space

1. **Economy pass for the 20-minute day.** A first pass is in (2026-11-15, `data/economy.json` "_about_balance"): a fleece a day per sheep, two packs of wool a day from Rosa, a plain sweater at 90c, crops priced for eating, Gran's rent at 90c a week, one full bar of hunger a day. It was set by arithmetic, not by play: it needs a played first week to check that the week is tight and the first needles take about three days.
2. **Pens and stalls.** Each pen holds four and the barn's rent already buys four more places. Next: pens that can be upgraded to hold more, more stalls for more rent, the animals actually sleeping in them, and fence panels priced so another pen is a real purchase.
3. **Selling online.** The post already carries sweater orders. Grow it into a steady order book: more customers, pickier wants (fibre, design, stars), a reputation that raises pay.
4. **Rare animals matter more.** Per-fibre sweater prices at Rosa's and the mailbox, so a mink sweater is worth more even without a request. Requests that repeat with new fibres once the first nine are done.

### Phase 3: the shop

5. **Nora's sweater shop downtown.** Buy or rent a shop front, stock it from her bag, hire a worker. It sells a few sweaters every day on its own, and a morning note says what sold and for how much.
6. **Sweater powers.** Some designs do something: one glows (a lantern she wears), warm ones let her into the cold land by the mountains, others might quiet her steps near shy animals or make her faster. This turns the fifty designs into a reason to chase particular knits.
7. **A cold land.** The mountains' foot is too cold to stay in without a warm enough sweater. The best animals live there.

### Phase 4: the empire

8. **Real estate.** Bigger houses, land for more pens, more shops.
9. **Her own city.** The end game: found a town and be its mayor.

## Advice given with this direction

- **The loop is a good one.** Each step feeds the next and every purchase makes the next sweater better or the next trip longer. The risk is balance: if rare fibre isn't worth much more than wool, nobody leaves town.
- **Lantern and glowing sweaters: do both.** The lantern is cheap and early, so no player is ever stuck in the dark. Glowing and warming sweaters come later as rewards, and give the designs a purpose.
- **Warm sweaters gating a cold land is the strongest idea of the three.** It ties knitting quality straight to exploration, and it already fits the story idea of a rare animal in the cold mountains.
- **Catching should stay a little uncertain.** Rarer animals take more barks, run faster and calm down if the dog lets up, so he can lose them. That keeps a mink feeling like a prize.
