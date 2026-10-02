# Production roadmap — a tavern that is yours

Lead-development assessment, 2026-09-30. Planning only; this document changes no
gameplay, prices, saves or artwork. Read with [CURRENT_GAME_VISION.md](CURRENT_GAME_VISION.md).
The owner's latest vision takes precedence over the historical restaurant/demo
scope. The two supplied images are art targets, not evidence of the current game.

**Implementation update, 2026-10-01:** [CHARACTER_FOUNDATION.md](CHARACTER_FOUNDATION.md)
records the first functional character slice: shared appearance data, saved
owner/wardrobe references, creator and Keeper editing. Old and new saves and the
unchanged economy pass measured tests. The base art still needs refinement toward
the supplied reference; the full art gate and later roadmap orders remain open.

## The game we are making

You own a little place beside an adventurer's road. Start by selling basic beer,
earn toward something you want, and turn the plot into your particular tavern.
Travelers make the wider world feel alive through their equipment, preferences,
stories and return visits. A profitable garden stand is a valid destination;
a busy restaurant, brewery or collection showroom is another.

The main loop should be:

**Make and sell beer → choose a desirable purchase → earn it → build, equip or
display it → see your place change and someone respond → choose the next project.**

Physical work and grid building provide the simulation. Personal expression
and anticipation provide reasons to keep playing once automation works.
Character creation introduces the person who owns this place; shared character
technology later makes the crew and visiting adventurers feel like its people.

The future controllable avatar is part of this vision. A playable external MMO,
combat, a quest campaign and multiplayer are not prerequisites for this demo.
The outside world can first be convincing through the people entering the tavern.

## Where we actually are

The project is a working physical simulation prototype. It is not yet a complete
demo of this newly clarified ownership/progression loop. Existing content is
enough to prove that loop; the next work should connect it before expanding it.

| Area | Current evidence | Distance to the intended demo |
|---|---|---|
| Grid building and logistics | Placement, construction, navigation, carrying, storage, rotations and cutaways exist. | Strong foundation. Improve rearrangement and the clarity of blocked work; prove persistent possession when collections arrive. |
| Brewing and service | Production, autonomous work, ordering, serving, billing, dishes, wages and restocking run together. | Strong foundation for a seated tavern. A minimal business and standing counter service need their own design and validation. |
| Farming, fishing and water | These systems already produce goods; the full-house soak reconciles them. | Existing expansion options, not missing features. Their economic purpose and surplus behavior need measured comparisons. |
| Saving | Atomic writes, backups and fresh-process restoration have been exercised, including copies of real player worlds. | Existing world persistence is established in the tested Windows cases. New appearance, purchases, unlocks and visitor memories still need save coverage. |
| Characters | One shared six-bone rig, explicit owner/staff/guest appearance, saved owner and wardrobe references, creator and Keeper editing now exist (October 1). | Functional foundation verified. Refine adult proportions and animation toward the art reference; wearable acquisition and direct avatar control remain future work. |
| Adventurers | Six guest classes influence orders, patience, tips and review weighting. | Behavior is present. Explainable attraction, recognizable return visitors and persistent personal history are not a complete loop yet. |
| Progression and collecting | The current demo has a cash goal; much of the catalog is immediately available. | A player-selected purchase/ownership/reaction loop is missing. Earning money alone does not establish it. |
| Art and atmosphere | Furniture detail, textures, terrain, day/night, weather, fire and lanterns exist. | The supplied references demand another pass on shape, proportions, lighting balance and composition. More variants alone will not close that gap. |
| Onboarding and presentation | Responsive HUD work and a broad 61-step tutorial exist. | The tutorial still introduces service at step 31 and has a reproduced shelf-filter defect. Controls need to reveal complexity gradually. |

These are status judgments, not completion percentages. The eventual game has
no finite approved content budget, so a percentage would hide more than it tells
us. The bounded next demo can be assessed against the gates below.

The September 30 measurements help explain the gap:

- Repairing the inherited tavern once, with built-in auto-supply and no later
  purchases or hires, reaches **1,319g on day 3**, clearing its 1,100g goal, and
  **2,203g after day 6**. All recorded goods and gold reconcile. Under the cozy
  vision this stable income is useful; it needs desirable projects to fund.
- The full-house fixture produces bread, beer, fish, water and crops. Across
  three days it serves **153** patrons and loses **40**. It ends with **38 fish
  heads** and **62 wheat**. These are reasons to examine service and surplus,
  not evidence that the goods disappeared or the game completely deadlocked.
- The shelf lesson can accept a flour-only filter that excludes the yeast it
  tells the player to allow. Scripted tutorial completion cannot prove that
  a new player understood the opening.

Source measurements: [GAMEPLAY_CRITIQUE_2026_09_30.md](GAMEPLAY_CRITIQUE_2026_09_30.md)
and `.verification/gameplay_critique_20260930/`. These are existing runs,
not new playtests performed for this planning document.

## Order of work

| Order | Deliverable | What this adds to the experience | Completion gate |
|---|---|---|---|
| 1 | Shared character foundation, approved base character, small creator and persistence | The player owns a recognizable person; crew and visitors use the same character pipeline. | Creator, profile, NPC rendering and resumed saves agree; cosmetic edits preserve behavior and economy. |
| 2 | Minimal beer opening and reliable starter controls | The simplest business is enjoyable before a restaurant is required. | First paid beer visit without walls or bread equipment; sustainable small-shop run; newcomer can diagnose a shortage. |
| 3 | One complete purchase and ownership loop | Automated income buys something the player actually wants. | A practical purchase and an expressive purchase can be acquired, used, rearranged/equipped and resumed without loss or duplication. |
| 4 | A small set of recognizable visitors and reactions | Products and decoration connect the tavern to the surrounding world. | A player can explain why a particular visitor came and remember one encounter. Return visits keep identity and useful history. |
| 5 | Coherent demo, presentation pass and blind playtests | The systems form a game worth continuing, rather than a feature demonstration. | Players complete the opening, choose an improvement, notice its result and want another project; persistence and books still reconcile. |

Fix the known teaching, reservation and diagnosis problems alongside orders 1
and 2, before treating the new opening as complete. Character art should not
become a reason to leave those defects indefinitely. New recipes and furniture
families follow the first complete reward loop; they should extend its choices.

### 1. Build characters as a shared product

Start with the data/rendering boundary and one character art test, then the UI.
Building an elaborate creator around today's fixed primitive shapes would
commit the interface before the underlying character is good enough.

**Separate three responsibilities:**

- Identity: stable person ID and name. Persistent owner, crew and selected
  recurring visitors can share this structure; every transient visitor does
  not need a permanent biography or a growing save record.
- Appearance: versioned body, skin, face/hair selections and dye choices, plus
  references to equipped pieces. Renderers consume these explicit choices.
- Behavior: worker role, work priorities, visitor archetype and visit state.
  Behavior chooses suitable outfit presets; clothing does not choose behavior.

The October 1 implementation separates appearance generation from pure mesh
building and stores guest archetype independently. `Pawn.set_appearance()`
preserves that archetype, job role and RNG. The character smoke exercises a live
guest outfit edit and resumed preferences. A ranger changing a hat must continue
to retain its guest preferences as the wardrobe grows.

**Art test:** make one excellent ordinary traveler in a simple shirt, trousers
and boots. Test a second body silhouette on the same compatible skeleton, then
representative staff, armored and robed presets. Refine torso shape, face planes,
hair masses, tapered limbs, hands and boots before adding dozens of garments.
Natural adult proportions with slight exaggeration should follow the supplied
reference; the current block-like limbs and shoulders need attention.

Approve it from front, rear and side; walking, carrying and seated; in a close
creator view and a busy tavern at normal management zoom. Test existing furniture
and carried-item fit as proportions change. Keep the efficient shared rig and
merged rendering approach where it serves the art. If a better authored base
mesh is needed, it should implement the same appearance contract rather than
create a separate player-only model system.

**First creator:** name, body silhouette, skin tone, hairstyle, hair color,
top/trouser colors and boots, with sensible defaults and randomize. Use one
large rotating live preview and front/back controls. The reference's timber,
brass, parchment and green confirmation button provide a useful visual language;
three simultaneous previews are not necessary for the first version.

Keep the owner's name separate from the tavern's. Create a draft profile and
commit it only when the new game begins; cancel/back should not write a save or
replace an existing tavern. Continue/Load bypasses creation. A later wardrobe
entry reopens the same appearance, not a second owner. Until direct control
exists, make the owner visible through the profile/portrait rather than promise
that it is an available worker in the world.

**Equipment groundwork:** stable IDs for Head, Body, Legs, Feet, Hands, Neck,
Ring, Cape and Backpack; reserve held tools for later direct work. Cape and
Backpack remain independently addressable, with explicit visibility/compatibility
rules. Define owned possessions separately from equipped references. Use a
small hat/cape/pack test set to exercise this contract; a large equipment catalog,
RPG stat system and animated cloth simulation are unnecessary for this slice.
Rings can initially be visible in an equipment icon and close view.

**Persistence is part of this milestone:** save owner ID, name, appearance
version, selected choices, owned wearables and equipped IDs per tavern. Preserve
explicit staff appearances when profiles replace generation by seed alone.
Older saves receive stable default owner/profile data without resetting any
world contents. Missing optional cosmetic definitions need a safe visual
fallback that preserves ownership and does not make the tavern unreadable.

Character milestone gates:

1. One appearance descriptor drives creator, portrait and world rendering.
2. Existing staff role and guest preferences survive an outfit change; cosmetic
   generation does not change subsequent simulation randomness.
3. Hat/hair, robe/seating, cape/pack and carry poses have no obvious penetration
   in the approved combinations; staff remain recognizable in a crowd.
4. Creator choices survive a real process restart, and older saves retain their
   buildings, goods, gold and crew. Canceling creation leaves slots untouched.
5. Fresh and resized creator layouts fit 1280x720, 1024x768, 16:10 and ultrawide;
   keyboard focus, back, randomize and confirmation work. Touch targets and
   Android performance require real device validation before claiming support.
6. Re-run the current character and fixed tavern rendering benchmarks. Record
   frame time, draws and geometry; do not assume the preview's detail is free
   when used by a whole crowd. Render hidden previews only when needed.

### 2. Make the smallest business a real opening

The immediate low-risk proof is a **seated garden beer business** using existing
service. A true walk-up stand is a separate service change: current arrivals
require a seat, and order/serve behavior assumes one. If standing service is
the opening we choose, implement queue positions, ordering, delivery/payment,
cup/cleanup flow, reservations and abandonment explicitly; a smaller tutorial
cannot supply those missing rules.

Start with basic beer, essential equipment/stock and the smallest proven helper
arrangement. Do not assume the current five-person 58g/day crew works at this
scale. Before an owner avatar exists, helpers execute physical work; the creator
does not silently create a free worker. Show starter actions first and defer
the full priority matrix, farming and food chains to optional learning.

Proposed target: first paid beer visit within **five minutes after entering the
world**, excluding time the player voluntarily spends customizing. Measure it
with fresh players. Demonstrate three ordinary-length trading days, normal
replenishment, no walls or bread equipment, and reconciled money/goods. Keep a
small reserve for a recoverable mistake; propose balance changes with evidence
before changing design-note prices, wages or yields.

Fix the exact shelf lesson, require meaningful acknowledgment/fresh events for
observation teaching, define station concurrency deliberately, and secure AI
versus manual batches. Explain where an order is blocked and what action helps.
The existing timing interaction should work reliably before an avatar takes it
over. Preserve the full-house test fixture and inherited-tavern challenge as
separate starts rather than use either as the main cozy opening.

### 3. Give profit a purpose

Build one small, complete reward board/catalog using mostly existing content.
Show the next purchase, its price or one understandable milestone, its visible
result and any actual business effect. The early choices should include a
capacity/convenience improvement, an optional product/method, and an expressive
object or wearable. Players can pursue one without collecting everything.

Acquire → own → place/equip → move/change → save/resume must all work. Distinguish
a catalog definition, a purchased possession and its displayed/equipped instance.
Collection items should be rearrangeable without repeatedly charging for the
same possession. Prevent duplicate ownership/sale on reload and invalid equipped
references. Build tools should make experimentation easy through clear previews,
undo and convenient repositioning.

Prefer money plus a small legible achievement initially. XP and elapsed-day
gates are options to test later, not several mandatory locks on every item.
Avoid a universal decoration score or giving every garment a work bonus.
Gardening and buying inputs can each be appealing for different reasons; measure
their payback, labor and surplus before promising that farming is an upgrade.

### 4. Give the wider world a human face

Use the shared pipeline to generate coherent people, not unrelated randomly
colored equipment. Tie clothing presets to plausible travel, trade and personal
taste while keeping behavior separately defined. Staff can have individual hair,
faces and accents while retaining recognizable uniforms.

Start with a few recurring visitors: a memorable name/appearance, a preference,
a brief factual response and a reason to return. Make an arrival cause visible:
a menu item, a displayed discovery or a particular service experience. Save the
identity and useful visit history. Ordinary patrons should remain rewarding,
so special guests do not make the little beer garden obsolete.

Let equipment, travel wear, notices and short lines hint at original roads,
ruins, trades, rivalries and expeditions. The tavern receives signs of a bigger
world before that world is playable. One remembered crew contribution and one
visitor encounter are a better first test than hundreds of biographies.

### 5. Prove the demo is worth returning to

Combine the creator, simple opening, purchase loop and visitor feedback into one
normal new-game route. Polish the pacing, presentation and existing item/furniture
silhouettes around that route. A day summary should celebrate something the
player made or acquired and give a useful next opportunity without imposing
another mandatory chore.

Use five fresh players for 20–30 minute blind sessions. Proposed gates: at least
four reach a paid visit without rescue, can explain a chosen improvement and
notice its consequence. Record what they want next, whether they spend voluntary
time arranging their place, and why they choose to continue or stop. Run matched
small and expanding taverns across several days. Automated correctness tests
remain necessary; they cannot establish enjoyment.

## Art direction derived from the images

Aim for original, crafted old-school fantasy: faceted people, readable equipment,
warm timber/plaster and a slightly eccentric world. The inspiration is a style
and sensibility, not borrowed Jagex models, item icons, place names or lore.
The existing handoff excludes OSRS cache/rimshare assets from shipping.

| Reference quality | What to improve in this project |
|---|---|
| Appealing face and adult silhouette | Shape head, cheeks, jaw, torso and limbs deliberately. Use readable hair clumps and restrained eyes/brows; avoid solving faces with extra random facets. |
| Clothing feels constructed | Make necklines, cuffs, belts, garment overlap and boots describe a cut. Details should follow forms; keep large cloth/metal/leather masses distinct. |
| Warmth without bleaching | Preserve cream and skin detail under daylight; strengthen contact/shadow cues and warm local pools at night. Check pale and dark outfits in every lighting state. |
| Calm room composition | Reduce repeated floor/table noise and overly bright surfaces. Leave visual priority to people, products and important interactions; inspect furniture-to-person scale. |
| A believable busy tavern | Improve seating fit, head turns, idle variety and hand/cup placement with a small reusable pose set. Test walking lanes and cutaway readability in a populated room. |
| Equipment implies a story | Build coherent travel kits, wear and original emblems; rare accents should have a reason. Silhouette and color are more useful than tiny jewelry at management distance. |
| Crafted creator framing | Use timber/brass sparingly, parchment for short explanations and a clear primary action. Responsive layout and contrast take precedence over ornamental borders. |

The current saved captures show useful colorful outfits and atmosphere, but
characters remain more block-like, and pale materials receive stronger light
than the concept references. This assessment is qualitative; no screenshot can
prove gameplay correctness or guarantee matching a concept illustration.
Approve one character and one populated room comparison before scaling variants.
Day/night/weather/fire already exist; another effects layer is lower priority
than improving these underlying shapes, values and poses.

## What follows the focused demo

Expand furniture families, menus, wearable collections, recognizable visitors
and crew development through the proven acquisition framework. Collections can
come from merchants, achievements and encounters without every object needing
a simulation bonus. Save and migration coverage grow with each new possession.

Then build a contained direct-avatar experiment inside the existing tavern:
switch views, move, and perform one existing job. Use the same saved person,
inventory, reservations, production and ledger as AI staff. Do not create a
second free-goods or duplicate-payment path. Prove camera/input and switching
back before adding external fishing grounds or exploration. The wider world
comes after this boundary works, and need not begin as a multiplayer project.

## The next concrete job

Begin **order 1** with a shared appearance/identity contract, one approved base
character and backward-compatible persistence. Then add the small creator and
adapt representative crew/visitor presets to it. The result is a saved owner
and reusable character system, with evidence that clothing is cosmetic and the
tavern still works. After that, order 2 makes the owner's first beer business
the main playable opening.

This roadmap makes no runtime changes. The art references have been compared
with September 28–29 saved game captures; current source and existing September
30 gameplay reports were read. Godot and gameplay suites were not rerun for a
documentation-only update.
