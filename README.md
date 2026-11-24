# PriceScout

A Fallout 76 UI mod that records the prices you see in other players' vending machines
and suggests prices for selling your own.

- Records every listing you browse at other players' vending machines.
- At any vending machine, a panel shows the highlighted item's market price, and at other
  players' shops, that shop's best deals.
- Feeds suggested prices into Better Containers, so its Vendor manager starts from them.

## Requirements

- [xScal](https://www.nexusmods.com/fallout76/mods/4183), for saving data (`modStorage`)
  and the F10 hotkey (`Input`)
- HUDModLoader, which loads the mod into the HUD
- Optional: [Better Containers](https://www.nexusmods.com/fallout76/mods/4485), for the
  price feed and market-price mode
- To build: Python 3 and JPEXS Free Flash Decompiler (its AS3 compiler is used, so no
  Flex SDK)

## Build, install, uninstall

```powershell
.\build.ps1                # dist\PriceScout.ba2
.\install.ps1              # copy to Data, add to Fallout76Custom.ini and hudmodloader.ini
.\install.ps1 -Uninstall   # remove the archive and both ini entries; data files are kept
```

`install.ps1` backs up both ini files as `*.pricescout-backup` the first time. It
defaults to `C:\Games\Steam\steamapps\common\Fallout76`; pass `-GameDir` for another
install.

## Prices

### How they are worked out

From vendors' asking prices over the last 30 days, counting each vendor once per item (its
cheapest stack on the most recent day it was seen), leaving out free listings and 40000+
"not for sale" placeholders:

- **sell**: the lower quartile, a quarter of the way up from the cheapest vendor. This is
  the suggested selling price, what the Better Containers feed and market-price mode use,
  and what "vs market" and the deals compare with. Asking prices lean high, since cheap
  listings sell and expensive ones stay up, so the median is not a "will sell" price.
- **typical**: the median asking price.
- Items seen at only **one vendor** have no market: shown dimmed as "1 vendor only" and
  never used.

Legendary items are matched on name (base item, weapon mods and 1st-star effect) and star
count, at any level. Vendor lists never include their other effects; those only appear on
the item card of the highlighted item.

### In game

While a vending machine is open, a panel at the bottom centre shows:

- The highlighted item: `PRICESCOUT  Healing Salve (Forest)  sell 50  typical 115  11 vendors  20-333`.
  - At another player's shop, that shop's price: `here 100  +100%` (the shop itself is
    left out of the numbers).
  - At your own machine, where Better Containers' price comes from: `your BC price 265  +430%`,
    `BC price 50  from PriceScout`, `BC price: item value`, or `listed at 265  +430%`.
- At another player's shop, its best deals: non-legendary items at least 10% below the
  sell price of 2 or more other vendors, cheapest relative to market first. Plans and
  recipes you already know are left out.
- At your own machine, market-price mode and its F10 switch.

Better Containers' Vendor manager (M) keeps its own highlight that the game never sees, so
the panel keeps describing the item highlighted in the window underneath and names it.

### Better Containers feed

When no menu is open, PriceScout adds its sell price to Better Containers' remembered sale
prices (`bettercontainers_vendorprices.json`), which its Vendor manager uses as the
starting price when you put an item up for sale:

- Only non-legendary items seen at 2 or more vendors.
- A price you set in Better Containers is never changed. PriceScout records what it wrote
  in `pricescout_bcfeed.json` and only updates values that still hold what it wrote.

### Market-price mode (F10 at your own machine)

Press F10 while your own vending machine is open, before pressing M for the Vendor
manager. Every remembered price, and every item you have at the machine, is then set to
PriceScout's sell price, or to the **item value +30%** when fewer than 2 vendors had the
item (the markup is the `noMarketMarkupPercent` setting).
It stays on, and is reapplied whenever a menu closes, until you press F10 again.

- Better Containers reads remembered prices on the first M press of a machine visit. If
  you switch the mode after that, close and reopen the machine.
- Your own prices are saved in `pricescout_bcfeed.json` and put back when you switch the
  mode off.

### From the command line

```powershell
python -I tools\report.py                       # every item
python -I tools\report.py --filter "plan:"      # names containing "plan:"
python -I tools\report.py --min-vendors 2       # only items with a market
python -I tools\bcfeed.py preview               # what the feed would add or update now
python -I tools\bcfeed.py remove                # take PriceScout's prices out of Better Containers, restore yours (game closed)
```

## Data

Everything is in the game's `Data\modsdata\` folder, saved through xScal:

| File | Contents |
|---|---|
| `pricescout_history.json` | Recorded prices: time, price, quantity, a hash of the vendor's name, menu type. Entries older than 60 days are dropped at login. |
| `pricescout_bcfeed.json` | Prices written into Better Containers, your prices saved by market-price mode, item values of what you own, and whether the mode is on. |
| `pricescout_settings.json` | Settings, created on first run: `"diagnostics": false` (true for full diagnostics) and `"noMarketMarkupPercent": 30` (market-price mode's markup on the item value for items with no market price). |
| `pricescout_diag.json` | A short status summary, written at login and on errors. With `"diagnostics": true`, the full diagnostics instead: event log, data samples, legendary item cards and the last vendor's name. |

To purge everything, with the game closed: run `tools\bcfeed.py remove` first (it needs
`pricescout_bcfeed.json`), then delete `Data\modsdata\pricescout_*`.

## How it works

- `PriceScout.swf` loads into the HUD through HUDModLoader and reads the game's UI data
  providers through `Shared.AS3.Data.BSUIDataManager`.
- Player vending machines report `menuType` 3 in `OtherInventoryTypeData` and send their
  items in `CampVendingOfferData`; each item's asking price is `vendingData.price`.
- The HUD's watch on `CampVendingOfferData` only ever holds the first list it received in
  a game session, so PriceScout drops and re-creates it
  (`BSUIDataManager.RemoveWatchFromDataConnector`, then `Subscribe`) when a vendor opens,
  when the provider signals an update without a list, and when the highlighted item is not
  in its lists. A list already seen at a different vendor is never recorded again (lists
  are identified by their items' `serverHandleID`s).
- The highlighted item comes from `InventoryItemCardData` (its `serverHandleID`); open
  menus from `HUDModeData`.
- Items are keyed `name|level|stars`, the key Better Containers uses for its remembered
  prices.

## Layout

| Path | Purpose |
|---|---|
| `src/scripts/PriceScout.as` | The mod |
| `tools/make_skeleton.py` | Writes the starter SWF that JPEXS compiles into |
| `tools/ba2.py` | Lists, extracts and packs BA2 archives |
| `tools/report.py` | Price report from the history file |
| `tools/bcfeed.py` | Preview or undo the Better Containers feed |
| `build.ps1`, `install.ps1` | Build and install |
