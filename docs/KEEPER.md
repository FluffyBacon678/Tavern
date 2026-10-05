# Playing your keeper — 2026-10-04

The character the player creates at the start can step into the tavern in
person and do any of the work by hand, RuneScape-style. It's optional: a
tavern runs without them. It matters most at the start, with no money, and
when the money runs out and everyone has to be let go.

![The options menu on the bar, which takes payments (the coin)](images/polish_20261004/menu_after.png)

**Visual pass, 2026-10-05:** a candle-gold ground ring identifies the keeper
without changing their chosen clothes. Fishing shows a basic rod; keeper and
staff share work poses. The options menu now scrolls, wraps long action names
and keeps rows at least 48 screen pixels tall. See
[WORLD_VISUAL_POLISH.md](WORLD_VISUAL_POLISH.md) for screenshots and measured
limits; touch has been checked in a portrait window, not yet on a phone.

## Controls

| Action | Mouse | Phone |
|---|---|---|
| Step in / back to managing | **Take control** button, or **Tab** | the button |
| Walk, or do the first thing on offer | left-click | tap |
| Every option ("Choose option") | right-click | long press |
| Turn the view round the keeper | middle-drag, or the arrow keys / Q E | drag |
| Zoom | wheel | pinch |

- **Stepping in.** The first press calls the keeper in where the camera is
  looking. The view eases down to follow them.
- **Stepping out.** The management view comes back exactly where it was. The
  keeper stays in the world, draws no wage, takes no jobs, and is saved with
  the tavern, along with what they hold and whether you were playing them.
- **Managing shortcuts while playing.** Build, demolish, rooms and land step
  you back out first; panels such as Stores and Staff open in either mode.
- **The yellow cross** marks where a left-click sent the keeper.

## What the keeper can do now

| Click on | Options |
|---|---|
| Goods (yard, shelf, bench) | **Take** (up to a stack). A job nobody has set out on gives way. |
| Somewhere, holding goods | **Put … on …**: an ingredient goes where the bench uses it; a dish or drink goes on a bar or till counter, for sale. |
| A bench, the bar, the oven, the vat | **Make** any of its recipes by hand. Holding an ingredient puts it down there first. It takes the recipe's time; the batch is a little better than ordinary. |
| A fishing spot | **Fish (basic rod)**. The catch comes into your hands. |
| A table with dirty dishes | **Clear the table**. |
| A wash basin with dishes in it | **Wash up**. |
| A prep table or a Bar Table | **Take payments here / Stop taking payments here**. |
| Anything, anyone | **Examine** (opens its card). |

Ordering supplies is the Stores panel as before. With nobody to haul,
deliveries wait in the yard for the keeper.

## Tills: paying at the counter

A prep table or Bar Table set to **take payments** (a gold coin floats over
it) is a till.

- **With nobody on the staff who takes orders,** every guest who has read the
  menu walks up to the nearest bar or till holding what they want. They buy
  from what is on its counter, take it back to their table, and pay as they
  leave: no waiter, no bill, no tip.
- **With waiters,** only hurried guests wanting just drinks walk up. Everyone
  else gets table service and a bill (the receipt), as before.
- Goods on a till are never carried off to storage. Waiters may serve from it
  too.

## Measured

**Running it alone** (`dev/persona_playtest.tscn -- persona=solo`): the
sandbox house with every member of staff let go on day 1. The keeper keeps the
bar in lemons and water, presses lemonade by hand, clears tables and washes
up. It's a thin living, but a living: no wages, and it keeps the tavern open
until there's money to hire again.

| Day | Guests buying at the bar | Profit | Purse |
|---|---|---|---|
| 1 | 28 | +2g | 2002g |
| 2 | 26 | +114g | 2116g |
| 3 | 24 | +119g | 2235g |
| 4 | 26 | +117g | 2352g |

**Tests:**
- `dev/regressions.tscn -- group=keeper` covers spawning, stepping in and out,
  taking and putting down, a recipe by hand, fishing, the till and saving.
- The tutorial's last lesson, *Your keeper*, does it all end to end: step in,
  fish, clean the catch at the prep table, make the bar a till, step out.
- `dev/keeper_showcase.tscn` renders the pictures.

## Fixed along the way

- A player can now let the last member of staff go when the keeper is in the
  world. Before, the game kept one pair of hands.
- Unclaimed clearing and hauling jobs gave way to nobody, so dishes looked
  spoken for when no busser existed.
- The advice now mentions doing it yourself when nobody on the staff can.

## Next, as the owner described

- Lemon trees on the unbuildable land, with lemons picked by the keeper.
- Guests who prefer paying at the bar versus at the table, and hiring a waiter
  to offer table service with receipts.
- More for the keeper to do: take orders and serve tables, carry plates,
  greet guests. Work by hand could use the existing timing mini-game for
  quality.
