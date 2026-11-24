# PriceScout (test build)

A Fallout 76 UI mod that records the prices you see in other players' vending machines,
so you can price your own items from what the market is asking.

This first build is an experiment. It answers one question: can a HUD mod, loaded by
HUDModLoader, read the game's vendor data while you browse someone's vending machine?
If it can, the mod needs no replacement of game menus and no signed DLL.

## How it works

- `PriceScout.swf` loads into the HUD through HUDModLoader.
- It subscribes to the game's `OtherInventoryTypeData` and `OtherInventoryData` providers,
  the same data `securetrade.swf` (the container and vendor menu) uses.
  `PlayerInventoryData` is also counted, as a control.
- For each item with a player vending price (`vendingData.price`), it records the time,
  price, quantity, a hash of the vendor and the menu type. Each vendor, item and price
  is recorded once per day.
- Items are keyed `name|level|stars`, the same key Better Containers uses for its
  remembered sale prices.
- Your own vendors, containers and NPC vendors are skipped.
- Files are saved through xScal's `modStorage` to `Data\modsdata\`:
  - `pricescout_history.json`: the recorded prices
  - `pricescout_diag.json`: subscription results, event counts, and a sample of the
    fields the game sent (for working out the data shape)

## Requirements

- xScal (for `modStorage`)
- HUDModLoader
- To build: Python 3 and JPEXS Free Flash Decompiler (its AS3 compiler is used, so no Flex SDK)

## Build

```powershell
.\build.ps1
```

Output: `dist\PriceScout.ba2`.

## Install and uninstall

```powershell
.\install.ps1
```

This copies the archive to `Data`, adds `PriceScout.ba2` to `sResourceArchive2List` in
`Fallout76Custom.ini`, and adds `PriceScout` to `Data\hudmodloader.ini`. Both ini files
are backed up as `*.pricescout-backup` the first time.

```powershell
.\install.ps1 -Uninstall
```

## In-game test

1. Start the game and load into a world.
2. Look for a small line of text on a dark box on the left of the HUD:
   `PriceScout <version>: storage ok | vendor events 0 | prices 0`.
   It hides while the Pip-Boy, a container, a vendor or the map is open.
3. Open another player's vending machine and scroll through a few items. Close it.
4. Open one of your own containers (a stash box), and an NPC vendor if one is handy.
5. Check whether `vendor events` and `prices` went up.
6. Quit, and look at `Data\modsdata\pricescout_diag.json` and `pricescout_history.json`.

What the results mean:

Player vending machines report `menuType` 3 in `OtherInventoryTypeData` and send their
items in `CampVendingOfferData`; `OtherInventoryData` arrives empty for them. Each item's
asking price is `vendingData.price`.

The HUD's watch on `CampVendingOfferData` only ever holds the first list it received in
a game session. So the mod drops and re-creates the watch
(`BSUIDataManager.RemoveWatchFromDataConnector`, then `Subscribe`) when a vendor opens,
when the provider signals an update without a list (about 2 s after opening), and when
the highlighted item isn't in its lists. A list already seen at a different vendor is
never recorded again (lists are identified by their items' `serverHandleID`s).

| In the diag file | Meaning |
|---|---|
| `recorded` above 0 | It works. |
| `events.CampVendingOfferData` above 0, `recorded` 0 | Data arrives, but prices are elsewhere. `lastOffers.sampleItems` shows where. |
| `codeObject` says timeout | xScal storage isn't reachable from the HUD. |
| `statusText.textWidth` is 0 | The status line's font didn't load. |

`lastType.defaultHeaderText` in the diag file is the vendor's name; it stays on your PC.
The history file stores only a hash of it.

## Suggested prices

### How the price is worked out

From vendors' asking prices over the last 30 days, counting each vendor once per item (its
cheapest stack on the most recent day it was seen), leaving out free listings and 40000+
placeholders:

- **sell**: the lower quartile, a quarter of the way up from the cheapest vendor. This is
  the suggested selling price, what the Better Containers feed and market-price mode use,
  and what "vs market" and the deals compare with. Asking prices lean high, since cheap
  listings sell and expensive ones stay up, so the median is not a "will sell" price.
- **typical**: the median asking price.
- Items seen at only **one vendor** have no market: shown dimmed as "1 vendor only", never
  fed, and set to 0 in market-price mode.

### In game

While a vending machine is open, a panel at the bottom centre shows:

- The highlighted item: `PRICESCOUT  Healing Salve (Forest)  sell 50  typical 115  11 vendors  20-333`,
  then at your own machine where Better Containers' price comes from (`your BC price 265 +430%`,
  `BC price 50 from PriceScout`, `BC price: item value`, or `listed at 265 +430%`), and at
  another player's machine that shop's price (`here 100 +100%`, leaving that shop out of
  the numbers).
- At another player's machine, its best deals: non-legendary items at least 10% below the
  sell price of 2 or more other vendors, cheapest relative to market first, leaving out
  plans and recipes you already know.
- At your own machine, market-price mode and its F10 switch.

The status line in the top left only appears during normal play if xScal storage can't be
reached, since nothing would be saved then.

The mod finds the highlighted item from the game's `InventoryItemCardData` provider
(its `serverHandleID`) and looks it up in the vendor and player inventory lists.

Legendary items are matched on name (base item, weapon mods and 1st-star effect) and
star count, at any level. Vendor lists never include their other effects; those only
appear on the item card of the highlighted item.

### Better Containers

When no menu is open, the mod adds its suggestion to Better Containers' remembered sale
prices (`Data\modsdata\bettercontainers_vendorprices.json`), so its Sale Planner pre-fills
it when you list the item. Rules:

- Only non-legendary items seen at 2 or more vendors, at the sell price.
- A price you set in Better Containers is never changed. The mod records what it wrote in
  `pricescout_bcfeed.json` and only updates keys that still hold its own value.

#### Market-price mode (F10 at your own machine)

Press F10 while your own vending machine is open, before pressing M for the Vendor
manager. Every remembered price, and every item you have at the machine, is then set to
PriceScout's sell price, or **0 when fewer than 2 vendors had the item**. It stays on (and is
reapplied whenever a menu closes) until you press F10 again.

- Better Containers reads remembered prices on the first M press of a machine visit. If
  you switch the mode after that, close and reopen the machine.
- Your own prices are saved in `pricescout_bcfeed.json` and put back when you switch it off.
- Careful: with the mode on, "Check shown" and "Sell checked" would list items with no
  market data for 0 caps.

```powershell
python -I tools\bcfeed.py preview   # what it would add or update now
python -I tools\bcfeed.py remove    # take PriceScout's prices out, restore yours (game closed)
```

### From the command line

```powershell
python -I tools\report.py
python -I tools\report.py --days 14 --filter "plan:"
python -I tools\report.py --min-vendors 2
```

This prints the sell price, typical (median), low and high asking price and vendor count
per item, worked out as above.

## Layout

| Path | Purpose |
|---|---|
| `src/scripts/PriceScout.as` | The mod |
| `tools/make_skeleton.py` | Writes the starter SWF that JPEXS compiles into |
| `tools/ba2.py` | Lists, extracts and packs BA2 archives |
| `tools/report.py` | Price suggestions from the history file |
| `build.ps1`, `install.ps1` | Build and install |
