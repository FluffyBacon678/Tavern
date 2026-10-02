# Current gameplay critique — 2026-09-30

**Updated after the owner's clarification:**
[`CURRENT_GAME_VISION.md`](CURRENT_GAME_VISION.md) records the intended cozy
beer-stand → personal tavern progression. The measured findings below remain
valid, but mandatory service/cash victory conditions and added operating
pressure are withdrawn as recommendations for the main mode. Profitable
automation is desirable when it funds optional collecting, building and
discovery. Use the revised work order in that vision document; the earlier
recommendations below retain the assumptions of the initial critique.

This review used three independent GPT-6.1 Sol reviewers at maximum reasoning:
the operating loop and progression, economy and logistics, and player experience.
They read the current implementation and full design notes. The coordinating
review measured current gameplay with isolated saves. No production source,
prices, recipes, wages, goals, or player save files were changed.

## Assessment

The game has a credible physical tavern simulation and enough existing content
to build a compelling demo. Its largest weakness is sustained decision-making.
The opening asks the player to discover necessary repairs; after those repairs,
the financial objective can complete with very little further management. The
next milestone should strengthen a 20–30 minute operating session using the
current furniture, meals, workers and guests.

Passing reconciliation establishes that the simulation accounts for its goods
and money. It does not establish that the choices are interesting, the tutorial
teaches them, or players can identify why service is failing. This critique
separates fresh observations, source-confirmed behavior, and design proposals.

## Fresh measurements

All runs used the actual 870-second day and fixed-step test acceleration. The
acceleration changes wall time, not recipe costs or day length. These are
script-assisted measurements, not a blind human mouse/keyboard playtest.

| Run | Result | What it establishes |
|---|---|---|
| Unrepaired demo; built-in auto restock only | 260g → -10g by day 6; lost the objective; reputation 0 | Missing washing and the other opening faults can stop the business. |
| Repair the demo's prep table, wash basin and shelf once; built-in auto restock only | Repairs cost 65g. No further hires, construction, manual deliveries or target changes. 1,319g at close of day 3: won. 2,203g at close of day 6; reputation 48.4 | Correct initial diagnosis largely solves the current cash objective. This was an informed opening, not a novice difficulty test. |
| Full test house, three unattended days | 2,000g → 3,679g. 153 served, 40 lost: 39 to service and one to menu availability. Daily unserved losses 7 → 11 → 21; final reputation 48 | Profit can coexist with worsening service. This start has free buildings, stock and 12 staff; it cannot establish normal-start balance. |
| All 61 tutorial steps, then six trading days | 260 served during the follow-up, 18 lost to service, 12 to unavailable menu, no seat losses; 1,144g → 3,635g | The taught tavern trades profitably, but still has meaningful operational faults. The harness hires a waiter when advice recommends one, so this is assisted operation. |
| Actual worker observation in the test house | Two cooks simultaneously working at one prep table; two at one oven | Station throughput currently allows different recipes in parallel at a single placement. |
| Actual shelf checkbox probe | All boxes initially unticked. Ticking only Flour rejects Yeast, yet completes the lesson | A current, reproducible tutorial defect. |

Goods and gold reconciled in every trading measurement. Current regressions
passed. The shelf probe deliberately exits 1 when it reproduces the defect.
Logs and the two observation scenes are under
`.verification/gameplay_critique_20260930/`.

## What is already worth preserving

- Physical goods, carrying, ingredient reservations, storage space, work
  priorities and pathfinding make layout a real source of operational cost.
- Dirty tables, serving, billing and washing create a connected service chain.
- Meal-based restock removes repeated ingredient bookkeeping while retaining
  wages, delivery fees, cooldowns and hauling constraints. Keep this convenience.
- Guest classes already affect orders, patience, tips and review weighting.
  They are mechanically distinct, as well as visually recognizable.
- Reputation changes footfall, and reviews explain several causes of a visit's
  result. There is an existing feedback loop to strengthen.
- The save and reconciliation infrastructure supports trustworthy iteration.

## Main weaknesses, in recommended order

### 1. The demo's objective rewards cash more reliably than running a good tavern

**Measured:** repairing once won on day 3 without another management decision.
On day 6 that tavern still lost 12 guests to service, nine to menu availability
and two to seating, with reputation below 50. The full-house run also accumulated
money while service deteriorated.

**Current rule:** the scenario checks archived end-of-day purse against 1,100g
before the day-6 deadline. Service quality and business sustainability are not
part of that decision. See `src/world/levels/level_def.gd:72` and
`src/world/levels/level_catalog.gd:74`.

The problem is an incentive mismatch. A cash goal encourages withholding
investment once income is positive, even when improving the dining experience
would be the satisfying next decision. Selling stock and recovering money from
inherited buildings can also feed a purse objective; deliberate liquidation as
a winning strategy was not tested here.

**Recommended improvement:** define success using the existing business
measures: trading profitability, a sustainable reserve, and an acceptable guest
experience over a short span. Give the player clear intermediate operating
goals and explain which one their latest change improved. Retune the scenario
against actual built-in auto restock, rather than a perfect-replenishment fixture.
Do not simply increase the gold target or add arbitrary disasters.

**Validation:** compare a repaired tavern left alone with one actively improving
service. The improved tavern should have a clear, attainable advantage in the
demo outcome. A player should still be able to recover after a poor day.

### 2. Capacity and investment tradeoffs need explicit rules

**Measured:** at 09:10 on day 1, Make Dough and Clean Trout were both being
worked at the same prep table. At 09:28, Grill Fish and Bake Bread were both
being worked at the same oven. This is actual concurrent work, not merely two
posted jobs. The production key includes recipe identity, so different recipes
can coexist at one station (`src/world/jobs/job_generator.gd:335`).

Multiple operations may be a legitimate design choice for a large workstation.
However, the game currently needs an explicit capacity contract. Otherwise
adding recipes also changes how much work one piece of furniture can perform,
and hiring cooks can increase throughput without a corresponding station
investment. That weakens the player's ability to reason about kitchen size.

The opening budget has also drifted from its stated design. The catalog says
the 260g start only closes two of three gaps. Current costs are prep 25g,
wash basin 22g, shelf 18g: all three cost 65g. Add the 115g standard delivery
and 58g opening payroll and the total is 238g, leaving 22g. The discovery
puzzle remains, but that particular forced spending choice does not.

**Recommended improvement:** define bench work slots and ingredient/output
capacity as data, show occupancy and queues, then retune the existing starting
budget, staffing and repair alternatives together. Preserve meaningful choices
between an extra cook, another bench, nearby storage and more dining space.

**Validation:** compare two layouts and three staffing/station combinations
under the same demand. A player should predict the bottleneck and see that
their investment changed it. Decide capacity before adding more recipes.

### 3. Diagnosis is weaker than the underlying simulation

The header combines several stages into one waiting total. Customer service
losses also combine delays that can originate in the kitchen, pass or waiter.
Billing delays affect reviews and tips; guests who exhaust bill patience still
pay and count as served. Once the service-loss count reaches three, Trouble recommends more Serve work
or a waiter without establishing that the current blockage is waiter capacity
(`src/world/sim/trouble.gd:99`).

There are useful detailed explanations in Kitchen details, inspections and
staff status, but the player has to connect them across screens. An overloaded
porter or ingredient layout may look like a waiter shortage. Hiring another
waiter because the warning said so can add wages without addressing the cause.

**Recommended improvement:** show where waiting occurs, explain the currently
blocked link, and make the explanation open/select its relevant station or
worker. The day summary should separate losses by cause and group the important
complaints. After a change, show enough before/after service and work information
to tell whether it helped. Use current simulation data, not another management
screen requiring more configuration.

There is also hidden unmet demand: new guests are not spawned while no menu
stock exists (`src/world/customers/customer_director.gd:408`). Sold-out periods
can look like a quiet road without counting the missed business. Show sold-out
time or unavailable demand without requiring the player to interpret silence.

**Validation:** give a new player a missing-input problem, an uncollected-order
problem and a dirty-table problem. They should identify the right stage and
take a useful action without unnecessary hiring or moderator explanations.

### 4. The tutorial delays the central payoff and can validate the wrong lesson

The current tutorial has 61 steps across ten lessons, is advertised as about
an hour, and introduces service at step 31. It introduces a broad collection
of controls and systems before the player has completed the core customer
experience.

**Confirmed defect:** the shelf lesson says to untick everything except Flour
and Yeast, even though an empty allow-list shows every box unticked and accepts
everything. Its completion condition accepts any nonempty filter. Selecting
only Flour completes it while rejecting Yeast
(`src/tutorial/tutorial_plan.gd:415`, `src/ui/inspector_panel.gd:291`).

Some observational lessons check lifetime production/service totals; an event
that already happened can advance the lesson at the director's next 0.25-second
check. The automated log has zero simulated seconds for several service
lessons. Automated completion therefore does not prove a newcomer saw or
understood the event.

**Recommended improvement:** fix the exact filter instructions and condition;
give observational steps an acknowledgment or a fresh event. Reorder the
opening around buying, making, serving and collecting the first payment.
Introduce the existing fishing, farming, expanded work matrix and other
controls after that reward, with optional follow-up lessons. The full test
house should remain a testing/sandbox option, not substitute for onboarding.

**Validation:** use fresh players at ordinary speed, not only scripted actions.
They should explain the production/service chain and make one useful
improvement after teaching ends. Set a short first-sale target and measure it.

### 5. Demand does not yet create strong specialization choices

Guest classes already change behavior. Rangers are impatient, warriors drink
more, wizards care about menu breadth, pilgrims about cleanliness, and duelists
select the dearest food (`src/world/customers/guest_type.gd:53`).

However, ordering is built from currently available products. When there is
only drink or only food, the missing category forces a fallback toward the
available category (`src/world/customers/customer_brain.gd:328`). There is no
current price/budget decision or strong dish-specific preference to make the
player think hard about which existing products suit their guests. Review
penalties and smaller baskets still mean a short menu has consequences; this
is not proof that a beer-only tavern is optimal.

**Recommended improvement:** make the existing preferences and unmet needs
legible and consequential, then test whether a brewery-focused tavern and a
food-focused tavern can both work through different staffing, space and guest
tradeoffs. Do this before adding foods or a large pricing interface.

**Validation:** run matched-demand specialization tests including service,
footfall and staffing costs. More dishes should introduce a considered choice,
not automatically improve every tavern or silently dilute useful demand.

There is another route that needs a deliberate role: `sell_stack()` immediately
sells to an unlimited external buyer at half value
(`src/world/world3d/world_3d.gd:902`). A beer batch has 16g wholesale proceeds
against 9g ingredient cost; a fish converted to one grill and two soup has 16g
wholesale proceeds against 2g purchased water, assuming the two soup are sold
together. These estimates exclude labor, fees and other costs. A wholesale-only
operation might bypass seating, serving, billing, cleaning and reputation; it
has not been tested as a winning strategy. The spec allows surplus trading, so
clarify whether the present action is emergency salvage or a viable specialization
and measure it, rather than automatically removing it.

### 6. Production, surplus and self-sufficiency need an economic purpose

Current recipe accounting, before tips, delivery fees, walking or wages:

| Chain | Purchased input cost | Retail output value | Contribution | Station work |
|---|---:|---:|---:|---:|
| Dough → two bread | 7g | 20g | 13g | 8.5s across two stages |
| Four beer | 9g | 32g | 23g | 7s |
| One fish → one grill plus two soup | 2g water | 32g | 30g | 10s cooking, plus fishing and carrying |

These are static recipe estimates, not measured net returns. Beer earns about
2.15 times bread's contribution per cooking work-second before travel. Fish
has high material margin but needs additional labor and an unbalanced pair
of co-products. Those costs need measured comparisons.

In the fresh house, 65 fish heads were made, 27 used and 38 remained. Wheat
also accumulated faster than the small flour target consumed it. Fish heads
have zero sale value, so the sell-stock escape route does not clear them. This
is surplus management pressure, not lost goods or a proven deadlock.

Farm crops grow over 1,300 simulated seconds, a little over two played days.
One wheat plot yields three sheaves, equivalent to 1.5 flour and 6g of avoided
merchant inputs; one hops plot yields two hops, avoiding 4g. A farmer costs
8g per day, before plot cost, planting, harvest trips and milling labor. A
small demonstration field can be educational without being an economically
good investment. Buying should remain a valid choice, but the reason to expand
into farming needs visible scale/payback information.

**Recommended improvement:** measure contribution per occupied worker minute,
not only ingredient cost. Explain buy-versus-produce costs and time to first
harvest. Handle or intentionally constrain co-product surplus using the existing
production/storage rules before adding more chains. Any price, yield or wage
changes should be proposed and reviewed rather than silently applied.

**Validation:** compare matched small taverns buying inputs, farming them and
fishing. Include startup costs, idle wages, hauling, useful output and leftovers.
Each intended strategy should have an understandable situation where it wins.

Restock recovery also needs a narrower fallback. A source-derived example, not
an executed playtest: with 70g and the opening crew's 58g payroll, only 12g is
available for a safe cart. An empty bread/beer target of 10/12 asks for 67g of
ingredients and fee. `_fit()` halves every line together until the all-ingredient
cart bottoms out at 19g, then refuses it (`src/world/sim/auto_supply.gd:90`).
A bread-only batch needs flour, yeast and water for 7g plus the 5g fee: exactly
12g, retaining payroll and yielding 20g of retail bread. Test a fallback that
funds one completable meal chain, rather than keeping at least one of every
requested ingredient. This preserves useful automation and improves recoverability.

### 7. Direct intervention must guarantee a dependable result

The existing cooking timing game can produce better quality, but opening it
does not reserve its ingredients/batch. AI continues processing. Completion
rechecks the station and can say it could not finish because somebody else
completed the work (`src/ui/hands_on_panel.gd:244`). Its bar uses real time
while workers use simulation speed. The scripted tutorial instead calls
`perform_by_hand(..., 0.8)` directly and does not validate this race or the
timing controls.

**Recommended improvement:** name the recipe action, keep it discoverable with
an unavailable reason, secure the batch while playing, and show the operational
benefit as well as quality. Decide how simulation speed behaves during manual
work. Polish one reliable intervention before adding more minigames or roles
the player can perform.

**Validation:** actually complete the timing game with an AI cook active at
1x and 5x. A completed action should not lose its batch to a competing worker.
The player should understand what they made and which shortage it helped.

### 8. UI complexity and character memory limit ownership

The staff screen exposes all work categories, role permissions and cyclic
priorities together. Some labels describe distinct but easily confused work:
Clear versus Clean, Gather versus Haul. Hire and Staff lead to the same screen.
The C key is both camera view and build undo, with a permanent hint that does
not explain the current precedence. These are conceptual clarity issues;
the current HUD fitting on screen does not resolve them.

Adventurer outfits and class rules give the tavern identity, but reviews lose
class context. The rolling reputation/ledger review list clears on reload;
current-day reviews persist and restore into the day summary. Existing
workers have role identity, yet little persistent personal development to
turn an efficient operation into the player's particular tavern. This is a
design opportunity, not a request to add RPG quest/combat systems now.

**Recommended improvement:** simplify the initial staff view, explain work
headings and when priorities take effect, and make control hints match context.
Carry existing guest types and service incidents into readable reviews and
retain useful recent history. Highlight who solved an actual service problem.
Small factual stories from the existing simulation should precede more lore
or character variants.

**Validation:** after a day, a player should recall one staff member and one
guest, explain what happened to them, and identify a decision influenced by it.

## Recommended next work sequence

| Order | Work using existing systems | Completion evidence |
|---|---|---|
| 1 | Fix teaching/trust defects; define bench capacity and dependable manual batches | Exact tutorial conditions; readable observation lessons; capacity tests; real timing interaction with AI |
| 2 | Connect bottleneck symptoms to causes and actions; simplify initial controls | New players correctly diagnose kitchen, waiter and dirty-table problems |
| 3 | Rebuild the scenario's operating goals and pressure curve; retune existing budget | Repair-only baseline no longer settles the whole intended challenge; efficient service and investment visibly improve outcomes |
| 4 | Compare existing menu, staffing, wholesale and buy/produce strategies; resolve surplus and recovery traps | Measured viable alternatives including fees, labor, capital and leftovers |
| 5 | Shorten the opening around first service; defer advanced lessons | A blind 20–30 minute session includes first sale, one rush, a recovered mistake and a deliberate improvement |
| 6 | Strengthen guest/worker outcomes and continuity | Players remember a service incident and want to improve their tavern the next day |

Do not add furniture, recipes, weather systems, combat, quest systems or large
progression trees to compensate for these weaknesses. More content will be
valuable once current decisions produce clear, distinct consequences.

## What would justify calling the next demo compelling

Use five fresh players for a short blind playtest. These are proposed acceptance
criteria, not results already achieved:

- At least four complete a first paid visit without moderator rescue.
- At least four identify and fix one current bottleneck.
- At least four explain why they chose a staffing, layout or menu investment.
- Two different operating strategies succeed in matched automated measurements.
- Players can describe a visible consequence of a change they made.
- After the target is reached, several choose to continue or replay to improve
  their operation; record their reasons rather than relying on a numerical
  satisfaction rating alone.

Run this at actual player speeds, include at least one smaller PC window, and
keep game-state correctness checks alongside it. Android input/performance and
long-term replayability remain unvalidated. The central unresolved question is
whether players enjoy anticipating, diagnosing and improving the tavern after
it first works.
