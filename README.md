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
  Flex SDK). `build.ps1 -Ffdec` takes `ffdec-cli.exe` or, with Java on PATH, `ffdec.jar`.

## Build, install, uninstall

```powershell
.\build.ps1                # dist\PriceScout.ba2
.\install.ps1              # copy to Data, add to Fallout76Custom.ini and hudmodloader.ini
.\install.ps1 -Uninstall   # remove the archive and both ini entries; data files are kept
```

`install.ps1` backs up both ini files as `*.pricescout-backup` the first time. It
defaults to `C:\Games\Steam\steamapps\common\Fallout76`; pass `-GameDir` for another
install.

## Releases and Nexus Mods

```powershell
.\package.ps1              # dist\PriceScout-<BUILD>.zip, after .\build.ps1
```

The zip is what goes on Nexus Mods: `PriceScout.ba2` and `PriceScout_README.txt` (from
`packaging\README.txt`, with the install steps for players) at its root, so the archive
root is the game's `Data` folder.

Pushing a `vX.Y.Z` tag (for example with `/release`) runs the Release workflow. It checks
that the tag matches `PriceScout.BUILD`, builds and packages on a Windows runner with a
pinned JPEXS, and publishes a GitHub Release with the zip attached, through the shared
[jmusick/ci](https://github.com/jmusick/ci) release workflow. Download the zip from the
release and upload it to the mod's Files tab on Nexus Mods, with the same version.

The CI workflow runs the jmusick/ci baseline (secret scan) and the same build on every push
to `main` and every pull request, and keeps the zip as a workflow artifact for 7 days.

## Prices

### How they are worked out

From vendors' asking prices over the last 30 days, counting each vendor once per item (its
cheapest stack on the most recent day it was seen), leaving out free listings and 40000+
"not for sale" placeholders:

- **sell**: the suggested selling price, what the Better Containers feed and market-price
  mode use, and what the panel's percentages compare with. By default it is the lower
  quartile, a quarter of the way up from the cheapest vendor. Asking prices lean high,
  since cheap listings sell and expensive ones stay up, so the median is not a "will
  sell" price. Other methods are below.
- **market**: always the lower quartile, whatever the sell method. The deals at other
  players' shops are measured against it.
- **typical**: the median asking price.
- Items seen at only **one vendor** have no market: shown dimmed as "1 vendor only" and
  never used.

### Sell methods

`sellMethod` in `pricescout_settings.json` picks how the sell price is worked out from the
vendors' prices. Settings are read when the mod loads, so change them with the game closed.

| `sellMethod` | Sell price | Use it to |
|---|---|---|
| `"percentile"` (default) | The `sellPercentile` percentile (default 25): with 9 vendors, 25 is the 3rd cheapest, 50 the median, 10 just above the cheapest. Linear between vendors. | Pick how patient you are: lower sells faster, higher earns more per sale. |
| `"undercut"` | The cheapest vendor's price less `undercutPercent` (default 5). | Sell fast by being the cheapest. One lowball listing drags it down. |
| `"fencedMedian"` | The median after leaving out prices outside Tukey's fences: more than 1.5 times the interquartile range below the lower quartile or above the upper quartile. | Price at the middle of the market without the 9,999-cap anchor listings. It needs 4 or more vendors to leave anything out. |

`itemValueWeight` (default 0, off) works with any method. It blends the item value plus
`noMarketMarkupPercent` into the sell price as if it were that many more vendors:

```
sell = (vendors × method price + itemValueWeight × item value × (1 + markup)) / (vendors + itemValueWeight)
```

With a weight of 3, the item value counts for 60% with 2 vendors and 9% with 30, so a
thin market leans on the item value and a busy one barely moves. It needs the item value,
which PriceScout knows for items it has seen at your machine and, in the panel, for the
highlighted item. Items without one get the method price alone. Items seen at one vendor
still have no sell price.

When the method is not the default 25th percentile, or the price was blended, the panel
names it after the price: `sell 48  cheapest -5%`, `sell 61  with item value`.

Sell prices, and market-price mode's item value +30%, are rounded to the nearest
`roundTo` caps (default 5), so 43 becomes 45 and 1,872 becomes 1,870. Prices below
`roundTo` are only rounded to whole caps, at least 1, so a 2-cap item isn't listed free
or at 5. `roundTo` takes any number of caps from 1 to 1000, such as 5, 10 or 25, or
`"none"` for whole caps. The market, typical, low and high figures are
never rounded.

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
  market price (lower quartile) of 2 or more other vendors, cheapest relative to market first. Plans and
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
item (the markup is the `noMarketMarkupPercent` setting), rounded to `roundTo`.
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
python -I tools\report.py --method undercut --undercut 10   # try a sell method without changing the settings
python -I tools\report.py --item-value-weight 3              # try blending in the item value
python -I tools\report.py --round-to none                    # sell prices in whole caps
python -I tools\report.py --round-to 10                      # try rounding to 10
python -I tools\bcfeed.py preview               # what the feed would add or update now
python -I tools\bcfeed.py remove                # take PriceScout's prices out of Better Containers, restore yours (game closed)
```

## Data

Everything is in the game's `Data\modsdata\` folder, saved through xScal:

| File | Contents |
|---|---|
| `pricescout_history.json` | Recorded prices: time, price, quantity, a hash of the vendor's name, menu type. Entries older than 60 days are dropped at login. |
| `pricescout_bcfeed.json` | Prices written into Better Containers, your prices saved by market-price mode, item values of what you own, and whether the mode is on. |
| `pricescout_settings.json` | Settings, created on first run, with missing ones added: `"diagnostics": false` (true for full diagnostics), `"noMarketMarkupPercent": 30` (the markup on the item value for items with no market price, and in blending), and the [sell method](#sell-methods) settings `"sellMethod": "percentile"`, `"sellPercentile": 25`, `"undercutPercent": 5`, `"itemValueWeight": 0` and `"roundTo": 5` (1 to 1000 caps, or `"none"`). A value out of range uses the default; an unknown `sellMethod` uses `"percentile"` and is reported in `pricescout_diag.json`. |
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
- Reopening the same vendor sends no new `OtherInventoryTypeData` or item card, since
  neither has changed. When a menu of the kind the last vendor used opens and they are
  still missing 300 ms later, PriceScout re-creates those watches too and reads them again.
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
| `package.ps1`, `packaging/README.txt` | The Nexus Mods zip and its player readme |
| `.github/workflows/` | CI and releases, through jmusick/ci |
| `.github/actions/setup-jpexs/` | Installs the pinned JPEXS on CI runners |
