# Knitting Empire: roadmap, playthrough and core loop

Written 10 November 2026 from a full read of the code at commit `87b924a` plus the work then uncommitted (sheep models, market stall, coffee table, brisk walk). **This is advice for Alex to approve, not a set of decisions.** Story beats and all player-facing text here are drafts.

It is written so that a coding agent can pick up any item without re-reviewing the codebase. Read `AGENTS.md` first (how to run, test and commit), then the section you are working on. Each task names the files it touches and how to tell it is done.

## 1. Where the game stands

**Strong**
- Content is data: `data/*.json` and the plain-text scene format in `data/scenes/*.scene` (grammar at the top of `scripts/story.gd`). New story needs no code.
- The Woolcore look: one palette (`data/palette.json`), one shader, an import tool that snaps generated models onto it.
- About ten minutes of story (Act 1) and a first romance arc (Rowan), versioned saves with migrations, and an autotest that plays the whole game.

**Weak, in order of how much it limits the game**

| # | Problem | Evidence |
|---|---|---|
| 1 | Knitting is not a mechanic | `_perform` "knit" in `scripts/main.gd` starts a 5-second timer; `_finish_knit` hands over a sweater |
| 2 | Quality means nothing | `Game.knit_quality()` (1–5 stars) only feeds warmth; `_ship` and `_rosa_price` pay a flat price |
| 3 | The economy is solved in one move | Rosa sells 3 wool for 36c, Rosa pays about 150c a sweater; a sheep costs 400c and grows about 1 wool a day; nothing limits buying wool |
| 4 | The day is 3 minutes | `HOUR_SECONDS := 10.0` in `scripts/game_state.gd`; the walk to town and back takes about a third of it |
| 5 | Nothing pulls the player into tomorrow | no orders, festivals, collections or goals after Act 1 |
| 6 | Thin content | 1 product, 2 crops, 4 villagers, 1 romance, 1 property |
| 7 | One 3,600-line file | `scripts/main.gd` holds world building, input, actions, saves and about 1,500 lines of tests; the map is hard-coded coordinates |
| 8 | Not shippable | raw key checks (no controller, Steam Deck or rebinding), no export preset, no translation hooks, no licence on a public repo |
| 9 | Performance | autotest measured 18 FPS in the town view on an M4 MacBook Air at 1280x800 |
| 10 | AI chat cost | needs each player's own Anthropic key (`scripts/ai_chat.gd`); shipping needs a proxy and a budget per player |
| 11 | Save risks (seen in code, not reproduced) | a save while moving furniture drops the piece (`ghost` is out of the `furniture` array); an autosave mid-scene does not store where the scene was |

**On "AAA".** AAA means budgets in the tens of millions and teams of hundreds. The target that fits this game is a premium indie hit (Stardew Valley, Spiritfarer, Unpacking): one clear hook, a distinct look, 20–40 hours of content, sold once for about $20–25. Everything below aims there.

## 2. Design pillars

Use these to say no to features.

1. **Knitting is the verb.** Every system either feeds knitting (wool, dye, patterns) or is fed by it (money, warmth, gifts, story).
2. **A sweater is a letter.** What Nora knits for someone says something. Gifts and commissions carry the relationships and the story.
3. **Healing is the arc.** Nora arrives closed and cold. The town, the craft and one person warm her up. Trauma is shown in small objects and actions, never lectured.
4. **Short sessions, long pull.** One in-game day is a complete, satisfying session of 12–15 minutes that always ends with a reason to play the next one.
5. **Kind by design.** No timers that punish, no fail states that lose progress, no paid currency. The pull comes from wanting to, not from fear of missing out.

## 3. The core loop

The audience (women 20–55 who play cozy games) stays for mastery, collection, relationships and self-expression. The loop gives one of each every day.

### The 30-second loop: one stitch row
Knitting becomes a short rhythm game.
- A needle marker sweeps along a row of stitches. Press (Space, click or controller A) as it crosses each stitch.
- Each press is Perfect, Good or Dropped. A streak of Perfects makes the needles click in time with the music and the yarn glow.
- A sweater is 3 rows of about 8 stitches, around 25 seconds. Patterns change the rhythm: ribbing is steady, cable has a held press, Fair Isle alternates two buttons for two colours.
- Result: 1–5 stars from accuracy, capped by skill (`knit_xp`). Dropped stitches lower the stars but never destroy the sweater.
- Accessibility: a "relaxed knitting" setting that widens the timing window or auto-knits at 3 stars.

### The 3-minute loop: make one thing
Gather (shear, pick dye plants) → prepare (spin, dye) → knit → place it (sell, gift, fill an order, wear, display). Each step is a few clicks and has its own small sound and animation reward.

### The 15-minute loop: one day
1. **Morning:** wake, read the order board note and the morning letter (rent, what grew, who is in town). Tend sheep and garden.
2. **Midday:** knit for today's order. Walk to Maplewood: sell to Rosa, buy wool from her, talk to one or two people, give a gift.
3. **Evening:** home by dusk. Decorate, cook, read. One story or relationship beat on most days.
4. **Bed:** a short end-of-day card: coins earned, best sweater, hearts gained, and **one teaser for tomorrow** ("Rowan said he'd bring the nails", "Market day", "Your pumpkins are nearly ready").

The teaser is the retention hook: every day closes with an unfinished thread.

### The week and season loop
- **Weekly:** Saturday market (better prices, a visiting buyer with a special request). Sunday is quiet: Rowan's hill, a memory thread.
- **Seasonal (28 days):** one festival that knitting matters for, one chapter of the main story, new patterns, new dye plants, the palette shift.
- **Year:** four chapters, ending at the Harvest Knit-Off. Then open-ended play.

### What keeps players coming back

| Pull | System | Why it works |
|---|---|---|
| Mastery | stitch game, star ratings, harder patterns | visible skill growth; "one more try for 5 stars" |
| Collection | pattern book, yarn colours, sheep breeds, a sweater wall at home | gaps in a book ask to be filled |
| Relationships | hearts, daily topics, commissions that reveal people, AI small talk | people remember and react |
| Expression | decorate house and shop, design sweaters (pattern × colour), dress Nora | players share screenshots; this is the marketing |
| Progress | cottage → shop → second property → brand | the "empire" in the title |
| Story | memory threads unlocked by knitting specific things | craft and plot move together |
| Tomorrow | end-of-day teaser, growing crops, regrowing wool, a pending order | open loops |

Avoid: energy that blocks play, real-time waits, daily login rewards, loot boxes. They would raise short-term numbers and cost the reviews this audience writes.

## 4. Suggested playthrough, beginning to end

**All of this is a draft for Alex.** One in-game year, four chapters, about 25–30 hours for the story, then open play. Names in use: Nora (heroine, working name), Daniel (ex-husband), Ellie (Gran), Rowan, Rosa, Gary, Giorgio, Sabrina, Steve, Wren, Barbara (the cast Alex set on 2026-11-12; Theo, Mabel, Hazel, Pip and Gus are gone).

### Chapter 1: Cast On (Autumn, hours 0–5)
*Theme: arriving. Mechanics: the basics.*
- **Existing Act 1:** the rain bus, Daniel's call, Wren's tour, Gran's basket and letter, first sweater, the fence and Rowan, first sale to Rosa, the porch voicemail.
- **Days 2–7:** tutorial by doing. The order board opens with Rosa's first commission. Rosa teaches spinning. First dye (onion skins from the garden). Nora knits herself out of the thin city coat.
- **Week 2:** Gran's pattern book is found with most pages missing; villagers each hold a page (the collection begins). Memory thread 2: Ellie teaching her to cast on.
- **Week 3:** (Alex, 2026-11-13: no legal fight over the house or the farm; Gran is alive, in Florida, and the farm is still hers. Daniel's visit at about four hours of play replaces the lawyer's letter: he comes to win her back, and whether she says yes or no, he shows his true colours and she sends him away.) Stakes: she needs to show the farm is a working business by year's end.
- **Chapter end, Harvest Fair (day 28):** first festival. She enters one sweater in the beginner's class. Whatever she places, the town claps. Rowan's first-date scene can land here.
- Player has by the end: stitch game, 3 patterns, 3 colours, orders, 2-heart friendships.

### Chapter 2: Purl (Winter, hours 5–12)
*Theme: letting people in. Mechanics: warmth, gifts, depth.*
- Snow. Warmth matters: the town is cold, and Nora's knitting is what keeps people warm. A winter drive: knit hats and scarves for villagers (new item types).
- New villagers arrive: 3–4 more, including a second romance choice and a rival-turned-friend knitter.
- Rosa's arc: the stall alone with two kids. Giorgio's arc: what he ran from, and helping Nora with hers. Sabrina's arc: winning her over, art school. Gary's arc: the caravan kid behind the blazer. Wren's arc: what she's so stressed about.
- Rowan's arc deepens: Anna. The darned hat. Evenings by the fire.
- Memory threads 3–4: the marriage, shown in objects (the navy sweater he threw away, the phone she wasn't allowed to silence). The player learns it slowly, as Alex specified.
- **Midwinter night (festival):** lanterns, gifts exchanged. The gift Nora knits for her chosen person is designed by the player.
- **Chapter end:** Daniel turns up in Maplewood in person. She does not fold. The town closes ranks, quietly.
- Player has: 8 patterns, dyeing, hats and scarves, buys Rosewood Cottage.

### Chapter 3: Pattern (Spring, hours 12–20)
*Theme: building. Mechanics: the empire.*
- Rosewood Cottage becomes her **shop** rather than only a rental: shelves, displays, opening hours. Customers walk in with tastes. Decorating now earns.
- Hire a first helper (a villager's teenager). Orders arrive by post from the city. A magazine writer visits.
- New breeds of sheep with different wool (soft, strong, dark). Lambing: a tender, low-stakes event.
- The romance reaches a real choice: commit, go slowly, or stay friends. All three are valid and stay playable.
- The legal thread: the hearing is set for autumn. Her accounts (the player's real numbers) are the evidence.
- **Spring Shearing Fair (festival):** speed and care contest with Rowan.
- **Chapter end:** memory thread 6, the worst night, told plainly and briefly. After it, she knits the navy sweater again, for herself.
- Player has: shop, helper, 14 patterns, 3 breeds, a second property available.

### Chapter 4: Bind Off (Summer into Autumn, hours 20–28)
*Theme: owning it. Mechanics: mastery.*
- Summer: the town's busiest season. A city boutique offers to buy the brand; she can sell, partner, or stay independent (changes the epilogue, not the ending's warmth).
- The hearing. Outcome depends on what the player built, but no path loses the farm; a weak year means a harder settlement, not a game over.
- **The Harvest Knit-Off, one year on:** the finale. A three-round stitch game against Rosa and the rival, using everything learned. Gran's last pattern page is the final piece.
- **Ending:** the porch again, a year after the voicemail. This time her lights are the ones people see from the hill. Wedding or partnership or a full house of friends, by the player's choices.

### After the credits
Open play: year 2 seasons with rotating festival themes, the remaining pattern pages, more properties, heart events for every villager, and seasonal content updates.

## 5. Six-hour plan (today)

Do these in order. Each is one commit. Run the autotest after each (`AGENTS.md`); add a check for each new behaviour in `scripts/main.gd` beside the existing ones.

### Hour 1: land what exists
- Commit and push the combined build (uncommitted sheep, stall, table and walk work, plus the autotest mouse fix).
- **Autotest mouse fix (already written):** the six failures seen on 10 Nov were a real mouse click on the test window sending Nora out of the door. `_ready` now sets `get_window().mouse_passthrough = true` in autotest mode and `_unhandled_input` ignores real mouse events. Done when: a full run ends with `AUTOTEST DONE` and no `FAIL`.
- Decide: make the repo private again or add a licence. A public repo with no licence is readable and buildable by anyone.

### Hours 2–3: the stitch game
- New file `scripts/knit_game.gd`: a `Control` that runs 3 rows of 8 stitches and emits `finished(accuracy: float)`. Draw it with the stitched-panel helpers in `scripts/hud.gd` (`_stitched`).
- In `scripts/main.gd`, `_perform` "knit": seat Nora (keep the `SitKnit` loop and needle clicks from `player.start_activity`), open the game, and call `_finish_knit(accuracy)` when it ends. Esc cancels and returns the wool.
- Stars: `clampi(roundi(accuracy * 5.0), 1, Game.knit_quality())`. Skill sets the ceiling, play sets the result.
- Autotest: add an `autoplay` flag on the game that presses perfectly, so `_autotest` and Act 1's knit beat (`@trigger event knit_done`) still pass. Check: a perfect run at `knit_xp` 0 gives 2 stars; a run with every stitch dropped gives 1.
- Setting: "Relaxed knitting" in the Settings panel (wider window). Save it in `user://settings.cfg` like the others.

### Hour 4: quality is money
- `scripts/game_state.gd`: add `var sweaters: Array = []` (one star value per sweater) and keep `inv["sweater"]` equal to its size so existing story commands (`@if has sweater`, `@take sweater`) keep working. `take_item("sweater")` removes the lowest-star one. Bump `SAVE_VERSION` to 6; in `migrate`, fill `sweaters` with 2s for the saved count.
- Price multiplier by stars in `data/economy.json`: `[0.6, 0.8, 1.0, 1.3, 1.7]`. Use it in `_ship`, `_rosa_price` and the sell action in `scripts/main.gd`. Gifts: 4–5 stars add friendship.
- Done when: a 5-star sweater sells for more than a 2-star one in a new autotest check, and a v5 save loads.

### Hour 5: fix the economy and the day
- `data/economy.json`: wool pack 36 → 75 and limit Rosa to 2 packs a day (new `wool_packs_per_day`), so sheep pay off in about a week. Sheep price 400 → 300.
- `scripts/game_state.gd`: `HOUR_SECONDS` 10 → 40 (a 12-minute day). Scale the need decay rates in `_process` and crop `hours` in `data/crops.json` by the same factor so balance per day is unchanged. Fix the time-based autotest waits this breaks by setting the clock directly rather than waiting.
- Done when: the autotest passes and a day from 6 AM to midnight takes about 12 minutes.

### Hour 6: tomorrow's hook
- End-of-day card in `scripts/hud.gd`, shown from `_go_to_sleep` in `scripts/main.gd`: coins earned today, best sweater, hearts gained, and one teaser line chosen from: a crop ready tomorrow, wool regrown, an unlocked Rowan topic, market day.
- A minimal order board: one order a day from a villager in `data/orders.json` (who, minimum stars, reward coins and familiarity). A new action on the price board in town; filling it uses the sell path.
- Done when: sleeping shows the card, and filling an order pays and raises that villager's familiarity in an autotest check.

## 6. Six-week plan (to a demo people can play)

Goal: a 60–90 minute Steam demo of Chapter 1, good enough for Steam Next Fest and for strangers to wishlist.

| Week | Focus | Deliverables | Done when |
|---|---|---|---|
| 1 | Foundations | Split `scripts/main.gd`: tests to `scripts/autotest.gd`, building to `build_mode.gd`, saves to `save.gd`, villager trade to `shop.gd`. All input through Godot input actions (controller and Steam Deck work). Atomic saves (write a temp file, then rename; keep one backup). Fix the two save risks in section 1. A headless unit-test run for pure logic (economy, migrations, story parser) that takes seconds; keep the windowed autotest for the rest. | no file over about 1,000 lines; the game is playable start to finish on a controller; quick tests run in under 30 seconds |
| 2 | Knitting depth | 3 pattern types with their own rhythm (rib, cable, Fair Isle). Dyeing: 6 colours from garden plants. Sweater = pattern × colour, shown on the model and in the inventory. Pattern book UI with missing pages. | a player can make 18 visibly different sweaters |
| 3 | Daily life | Full order board (villager tastes, deadlines of several days, never punishing). End-of-day card finished. Saturday market. Villager schedules (home, work, plaza by hour). 3 more crops and dye plants; generalise the crop code that names turnips and pumpkins. | adding a crop is a JSON edit only; a week of play has no two identical days |
| 4 | Chapter 1 content | Write and stage days 2–28 (section 4): about 12 new scenes, memory thread 2, Daniel's visit, the Harvest Fair as a playable festival. 2 new villagers with models through the Tripo pipeline (rigid heads, `AGENTS.md` rule). | Chapter 1 plays from the bus to the Fair with no dead days |
| 5 | Feel and performance | Find the town's 18 FPS cause with `--fpsprobe` and reach 60 FPS on the M4 Air at Medium and 30 FPS on Steam Deck settings. Animation pass on knitting, shearing, gifting. Real music (2–3 tracks) and replaced key sounds. UI pass: inventory, journal and pattern book in the stitched style. Onboarding without text walls. | a new player needs no explanation for the first 15 minutes |
| 6 | Ship the demo | Export presets for macOS and Windows; a GitHub Actions build. Steam page: capsule art, 5 screenshots, a 45-second trailer led by the stitch game. Playtest with 10 people from the target audience; fix the top 5 problems they hit. AI chat off in the demo unless the proxy exists. | a stranger can download, play 60 minutes and wishlist |

Decisions Alex needs to make in these weeks: final game name; the heroine's name and whether there is a character creator; repo visibility; whether AI chat ships at all (see section 8).

## 7. Six-month plan (to Early Access)

| Month | Milestone | Main work |
|---|---|---|
| 1 | Demo live | The six-week plan. Start a devlog and short clips of the stitch game and the Woolcore look; the art style is the marketing. |
| 2 | Chapter 2 | Winter: snow, warmth gameplay, hats and scarves, 3–4 new villagers, second romance, Midwinter festival. The map becomes separate scenes (farm, town, hill) loaded on travel, replacing the single hard-coded grid in `main.gd`. |
| 3 | The empire | Chapter 3 systems: Rosewood Cottage as a shop with customers, a helper, post orders, sheep breeds, a second property. Deep decorating: 100+ furniture pieces, wallpaper and floors, a photo mode. |
| 4 | Chapter 3 and 4 story | Spring and summer scenes, the legal thread, the Knit-Off finale, three endings. Full heart events (4 per villager). First outside playtest of the whole year; rebalance the economy from real play data. |
| 5 | Platform and polish | Steam Deck verified. Controller-first UI. Localisation hooks (`tr()` everywhere; all text out of code into data) and a first language pass. Accessibility: text size, colour-blind checks on the palette, relaxed knitting, hold-to-press options. Cloud saves, achievements. Optional opt-in analytics on where players stop. |
| 6 | Early Access launch | Content lock, two weeks of bug fixing only, a launch trailer, press and creator keys (cozy-game streamers are the channel that matters). Price around $20. Publish a roadmap: year 2 content, Switch, iPad. |

**Team and money, honestly.** One person with AI tools can reach the demo. Early Access quality across a full year of story realistically needs paid help in three places: a 3D artist to give generated models a consistent hand-finished look, a composer, and a writer or editor for the story, which carries a serious subject. A publisher or a platform fund becomes realistic once the demo has wishlists; 7,000–10,000 wishlists at launch is the usual bar for a healthy start.

**What "scaling up" means after launch.** Console ports (Switch is where this audience is), seasonal content updates, and only then considering co-op visiting of each other's shops. Multiplayer before launch would sink the schedule.

## 8. Risks to manage

| Risk | Why it matters | Mitigation |
|---|---|---|
| AI chat cost and safety | per-message cost on a one-time purchase; a model speaking freely inside a story about an abusive marriage | ship hand-written dialogue as the default; offer AI chat as an optional extra through a proxy with a spending cap per player, or leave it out of 1.0 |
| Generated assets | Steam requires disclosure of AI-generated content; some players and press react badly; style drifts between models | disclose plainly; pass every model through the Woolcore import tool and a human finish; check the licence terms of each generator for commercial use |
| The subject | divorce and coercive control must be handled with care for this audience | a sensitivity read of the script; content note at the start; never make the trauma a puzzle or a twist |
| Scope | a year of story, a shop sim and a romance game is three games | the pillars in section 2; cut anything that does not feed knitting; ship Chapter 1 before building Chapter 3 systems |
| Code structure | one 3,600-line file blocks a second contributor and slows every change | week 1 of the six-week plan, before any new content |
| Test speed | a 7-minute windowed autotest discourages running it | fast headless logic tests; split the autotest into sections that can run alone |
| Public repo, no licence | anyone can build the full game | make it private with collaborators, or choose a licence on purpose |
| Performance | 18 FPS in town on a current laptop | profile in week 5 at the latest; grass density and shadows are the first suspects (`--fpsprobe` measures each effect) |

## 9. For the agent picking this up

- Start with section 5, hour 1, unless Alex says otherwise. Do not start section 6 work before the stitch game exists; it is the game's reason to exist.
- Keep every change data-first: new tunables go in `data/economy.json`, new content in `data/`.
- Save format changes need a `SAVE_VERSION` bump and a new step in `Game.migrate`; never edit old steps.
- Player-facing words are drafts until Alex approves them. Mark new dialogue and scene files as drafts in the commit message.
- Only one autotest at a time, and only commit when it is green.
