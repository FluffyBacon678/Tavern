# Current game vision — owner clarification, 2026-09-30

This document records the owner's latest direction, including a personal
character creator and future wearable collections. It takes precedence over
older demo assumptions and the pressure-focused recommendations in
`GAMEPLAY_CRITIQUE_2026_09_30.md`. It is a design brief and proposed work order;
the September 30 vision update itself implemented no gameplay, unlocks, prices
or content. Implementation status is tracked below and in the roadmap.

The next production plan is [PRODUCTION_ROADMAP.md](PRODUCTION_ROADMAP.md):
current readiness, the shared player/NPC character milestone, art targets from
the supplied references, and acceptance gates for the ownership-focused demo.

**Implemented follow-up, 2026-10-01:** [CHARACTER_FOUNDATION.md](CHARACTER_FOUNDATION.md)
records the shared appearance/profile pipeline, creator, Keeper editing, save
compatibility and measured tests. The functional foundation is usable; reference
art quality, minimal beer opening and the reward loop still need work.

## The intended experience

Start with the simplest viable business: selling basic beer. A garden stand
should be a valid beginning and a valid place to stay. Walls, a large kitchen,
a complete staff roster and a growing list of foods should not be prerequisites
for enjoying the game. The lemonade-stand example describes simplicity, not a
request to add a lemon recipe now.

The world outside feels like an MMO inspired by RuneScape: adventurers travel,
work, explore and return to rest. The tavern is the player's place in that
world. Building and autonomous physical jobs borrow from RimWorld and Prison
Architect; personal ownership, collecting, decorating and display borrow from
Animal Crossing.

The player can choose a small, cozy garden business, a profitable large tavern,
a specialist producer, or a collection/showcase destination. Getting richer
is an available ambition, not the only definition of success.

Eventually the player can switch into a controllable character and fish,
brew, serve or explore directly. Future visitors and hireable crew should be
individuals. These are later horizons; the current demo should establish a
business and a place the player wants to own before building the outside MMO.

The player also owns a recognizable personal character. A small character
creator belongs in the near-term design, even before free movement exists.
Clothes, hats, rings, capes and backpacks can later be collected, worn and
displayed. This is the owner's new request, not a requirement to implement
combat, RPG statistics or the external world first.

## Three connected reward loops

1. **Operate:** stock beer → prepare it → serve a visitor → earn money →
   replenish conveniently. The smallest version should be easy to understand
   and reliable enough to run while the player decorates.
2. **Progress:** choose something desirable → earn toward it → unlock/buy it →
   place or use it → see a meaningful new result. Results can include a new
   product, method, convenience, guest encounter or way to personalize the site.
3. **Own and collect:** discover something → acquire it → arrange/display it →
   watch people react → remember the place and want to improve it.

Decorating must be rewarding in its own right. It should not always lose to
the mathematically best production investment. Conversely, someone who enjoys
optimization should find useful choices in layout, labor, stock and methods.

## What the critique changes

The measured results remain valid. Repairing the current scenario once earns
enough to win its cash objective on day 3 without further changes. Under this
vision, steady automated income can be a success. The important question becomes
whether it funds interesting, optional projects and encounters afterward.

Withdraw the recommendation for mandatory cash-plus-service victory conditions
in the main cozy mode. Service and reputation should influence guest experiences,
appeal and optimization; poor efficiency should not invalidate the player's
small garden tavern. The current deadline scenario can remain an optional
management challenge, separate from the main progression experience.

Keep the findings about inaccurate teaching, unclear bottlenecks, manual-batch
races, uncertain workstation capacity, co-product surplus and recovery traps.
These make either a cozy or a demanding version harder to trust and enjoy.

Do not manufacture engagement through repeated manual restocking, mandatory
crises or an ever-larger wage bill. Automation gives the player time to pursue
ownership and discovery. Progression should supply reasons to use that time.

## Present implementation versus intended opening

| Current behavior | Implication for this vision |
|---|---|
| Stations and furniture can function outdoors; no wall/floor prerequisite for brewing | A garden beer business fits the underlying simulation. |
| Customer arrivals require a table/chair seat (`customer_director.gd:413`) | A true walk-up stand needs a counter-based visit/service path. Outdoor seating is possible already, but standing service is not. |
| Used dishes eventually block table seats unless cleared/washed | Decide the simple stand's cup/cleanup flow explicitly; do not quietly inherit a full restaurant's maintenance requirements. |
| Five opening staff, including two cooks, cost 58g/day | This start was balanced for the existing restaurant scenario, not for a basic beer stand. Re-measure a minimal helper/operator setup. |
| Tutorial teaches flooring and bread's prep/oven chain; main menu defaults to the broad tutorial | Introduce first beer income before optional construction, food and specialized staffing. |
| Almost the full catalog is available in the current prototype; the full-house sandbox has everything built | A player-selected acquisition/progression path is missing from the main start. Keep the full house as a developer/test sandbox. |
| Guest types already change patience, orders and review weights | Extend this into clear attraction/discovery feedback, rather than inventing a parallel guest system. |

## Progression principles

**Money buys ownership and capability.** Keep early purchases legible: practical
capacity or convenience versus something the player wants to display. Existing
items can demonstrate these choices before growing the catalog.

**Unlocks create understandable anticipation.** Show what is attainable next,
what it changes, and why it is unavailable. Use one clear early progression
measure. Money plus a small earned milestone is a proposal; XP and day-based
gates remain future options from the owner, not finalized requirements.

Avoid requiring money, XP, several elapsed days and reputation simultaneously
for every purchase. Day gates alone can create idle waiting; XP should reward
activities the player actually wants to perform, rather than repeating a task
solely to fill a bar.

**New guests are part of the reward.** A special visitor should have an
understandable reason to arrive and a visible personality or preference.
Attraction can later read menu, displays, style, services and reputation. It
should offer several identities for a tavern, rather than turn every property
into the same maximal checklist. Ordinary visitors remain worthwhile.

**Decorative expression remains optional and broad.** Buildings, gardens and
furniture collections should support different looks. Avoid a universal beauty
score that makes one expensive decoration arrangement the correct answer.
Some objects can be for expression alone; others can have explicit guest or
business effects. Show those effects clearly when they exist.

**Growing is a choice.** A stable small shop should remain viable while richer
and larger businesses have additional possibilities. Better automation should
free time instead of obligating expansion into every profession and recipe.

## Revised implementation order, proposed

1. **Establish a small, persistent owner identity.** Name and appearance choices
   with a preview and sensible defaults; preserve them per tavern save. Keep the
   creator brief and allow later wardrobe changes. Define equipment slots as
   future extension points, without building a full RPG inventory first.
2. **Make the minimal beer opening work.** Specify and validate walk-up versus
   seated service, the starter operator/helper, simple cleanup, initial stock
   and automatic replenishment. Require no walls or bread equipment. Teach
   first sale quickly. Preserve the full-house and deadline scenarios separately.
3. **Fix trust and comprehension.** Correct the shelf lesson, observation
   advancement, shared station-capacity rules and manual-batch ownership.
   Expose starter controls first; provide actionable shortages and service
   explanations. These fixes can proceed alongside the opening work.
4. **Give early income a purpose using the existing catalog.** Offer a small
   set of visible, optional goals: a practical improvement, a product/method
   expansion and a personal display/decorating project. Test whether players
   want the reward before adding a large unlock tree or balancing XP.
5. **Connect progression to existing adventurers.** Make the reason for a new
   visitor legible; connect its preference and reaction to the player's choices.
   Start with a small number of recognizable encounters, not a unique-character
   generation system for every traveler yet.
6. **Prove persistence and player ownership.** Save purchases, placements and
   progression. Make rearranging and displaying possessions convenient. Test
   both staying small and expanding, with enjoyable optional projects in each.
7. **Expand content after those loops work.** Add collections, furniture styles,
   products, methods and individually developed guests/crew according to the
   verified progression framework. Keep manual avatar/world exploration as a
   later milestone that consumes the same physical jobs and goods.

This revises the previous work order. It is a proposed sequence; exact unlock
rules and economic values still need design and measurement. The original
planning update did not change gameplay code. The October 1 character
implementation is recorded separately above.

## Personal character and wardrobe proposal

**First creator:** player name separate from tavern name, a small set of base
looks, skin tone, hairstyle/hair color and starter outfit colors. Show a clear
preview with rotation. A default appearance makes it quick to begin trading.
The same character can appear in the owner portrait/profile before its future
world-control mode is ready; do not represent an uncontrollable owner as a
selectable worker without explaining what it can do.

**Future equipment structure:** proposed slots are Head, Body, Legs, Feet,
Hands, Neck, Ring, Cape and Backpack. Keeping Cape and Backpack separately
addressable preserves the option to wear both; compatibility and clipping
rules can be defined when those assets exist. Held tools can be added with
manual work. Exact slot counts, including whether multiple rings can be worn,
remain design choices rather than finalized requirements.

**Collectible rewards:** early wearables can express personality. Later an
earned apron, a traveler's cape, an interesting hat or a themed ring can mark
an achievement or encounter. These examples are proposals, not new content
implemented or approved as specific rewards. Tools/backpacks may eventually
add convenience, but ordinary clothes need not all become productivity bonuses.
The player should be able to keep a favorite appearance without making their
business unviable. If mechanical gear exists later, displaying a preferred
look independently is an option to evaluate.

**Camera readability:** hats, outfit colors, capes and backpacks should read
at management-camera distance. Small jewelry such as rings needs a useful icon,
equipment description and close preview; it need not add visible geometry to
every distant pawn. Maintain the existing lightweight character rendering.

**Foundation in current code, October 1:** `CharacterAppearance` and
`CharacterProfile` now provide explicit selected cosmetics and a dedicated saved
owner. New games use the creator, Keeper edits the same profile, and staff/live
guests save their explicit appearances independently of behavior. `PawnMesh`
uses one pure build path for them all. The hat/cape/pack contract is exercised
without adding an acquisition loop. See the implementation report above.

**Continuity:** save an owner identifier, name, selected appearance, acquired
wearables and equipped choices with the tavern. Older saves should receive a
stable default owner while retaining every building, item and worker. Character
creation must never replace an existing world snapshot. Appearance randomness
must not alter the gameplay RNG sequence. Customer archetypes and worker roles
should remain separate from outfits, so changing a hat does not silently
change the person's identity or job rules.

The later controllable avatar should consume the same saved profile, physical
goods, job reservations and ledger. Creation, management portraits and direct
control should not become three unrelated versions of the player.

## Evidence required before expanding scope

- A newcomer reaches the first paid beer visit without building a restaurant.
- A no-wall business works; a true walk-up business is tested if that is the
  chosen starter flow.
- Players can see and explain what they want to buy next, and what it will do.
- At least two choices are attractive for different reasons; decorative
  ownership is represented alongside practical efficiency.
- The small-shop player can remain small without falling into an avoidable
  wage/restock trap; the expansion player sees new possibilities.
- A guest reacts to something the player chose, and the player notices why.
- Save/load preserves the player's place and earned progress.
- The creator's preview, owner portrait and resumed save agree on appearance;
  changing clothing preserves the business and the character's identity.

Use a short blind player session to measure first-sale time, voluntary purchase
choices, time spent decorating and desire to continue. A quiet business with
few interventions is not automatically a failure; watching and arranging one's
own tavern can be the intended pleasure. Meaningless waiting for a locked item
is different and should be identified in observation.
