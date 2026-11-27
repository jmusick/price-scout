PriceScout {{VERSION}}
Fallout 76 vendor price history and suggested selling prices.
https://github.com/jmusick/price-scout

REQUIREMENTS
- xScal (https://www.nexusmods.com/fallout76/mods/4183), which PriceScout uses
  to save its data and for the F10 hotkey
- HUD Mod Loader (https://www.nexusmods.com/fallout76/mods/3144), which loads
  PriceScout into the HUD
- Optional: Better Containers (https://www.nexusmods.com/fallout76/mods/4485),
  for the price feed and market-price mode

INSTALL
1. Install xScal: put its dxgi.dll in the game folder, next to Fallout76.exe,
   not in Data. With a mod manager, make sure it doesn't end up in Data.
2. Install HUD Mod Loader as its page says: HUDModLoader.ba2 and
   hudmodloader.ini go in Data, and HUDModLoader.ba2 is added to the end of
   sResourceArchive2List in Fallout76Custom.ini.
3. Copy PriceScout.ba2 into your Fallout 76 Data folder, for example
   C:\Program Files (x86)\Steam\steamapps\common\Fallout76\Data
4. Open Documents\My Games\Fallout 76\Fallout76Custom.ini and add PriceScout.ba2
   to sResourceArchive2List under [Archive], before HUDModLoader.ba2, which has
   to stay last (or ChatMod.ba2 last if you use Text Chat):
     [Archive]
     sResourceArchive2List=OtherMod.ba2, PriceScout.ba2, HUDModLoader.ba2
5. Open Data\hudmodloader.ini and add this line:
     PriceScout
6. Start the game and open another player's vending machine.

AFTER A GAME PATCH
xScal needs a new Address Library file for each game version. Until it has
one, PriceScout can't save prices or read the F10 hotkey. With xScal's default
settings it offers the new file when you start the game; click Yes and restart.
If the file isn't published yet, start the game again later. See the xScal page
for details.

UPDATE
Replace PriceScout.ba2 in the Data folder. Your recorded prices are kept.

UNINSTALL
Delete Data\PriceScout.ba2 and remove PriceScout from both ini files.
Recorded prices and settings are in Data\modsdata\pricescout_*.json. If you used
the Better Containers feed or market-price mode, run tools\bcfeed.py remove from
the GitHub repository with the game closed before deleting those files, to take
PriceScout's prices out of Better Containers and put yours back.

SETTINGS
Settings are in Data\modsdata\pricescout_settings.json, not in an ini file.
PriceScout creates it with the defaults the first time the game loads it, and
adds back any setting that is missing. Edit it with the game closed. A value
outside its range is ignored and the default is used. The default file:

  {"version":1,"diagnostics":false,"noMarketMarkupPercent":30,
   "sellMethod":"percentile","sellPercentile":25,"undercutPercent":5,
   "itemValueWeight":0,"roundTo":5}

sellMethod - how the suggested sell price is worked out from vendors' prices:
  "percentile"   (default) the sellPercentile percentile. Lower sells faster,
                 higher earns more per sale.
  "undercut"     the cheapest vendor's price less undercutPercent. Sells fast,
                 but one lowball listing drags it down.
  "fencedMedian" the median after leaving out unusually low and high prices
                 (Tukey's fences), such as 9,999-cap anchor listings. Needs 4 or
                 more vendors to leave anything out.
  An unknown method falls back to "percentile".

sellPercentile (0-100, default 25)
  The percentile "percentile" uses. With 9 vendors, 25 is the 3rd cheapest,
  50 the median and 10 just above the cheapest.

undercutPercent (0-100, default 5)
  How far below the cheapest vendor "undercut" goes.

roundTo (1-1000, default 5)
  Sell prices are rounded to the nearest this many caps: 43 becomes 45. Prices
  below it are only rounded to whole caps, at least 1. "none" or 0 for whole
  caps.

noMarketMarkupPercent (0 or more, default 30)
  In market-price mode, items seen at fewer than 2 vendors are priced at their
  item value plus this percentage. itemValueWeight uses the same markup.

itemValueWeight (0 or more, default 0 = off)
  Blends the item value plus noMarketMarkupPercent into the sell price as if
  it were this many more vendors. With 3, the item value counts for 60% with 2
  vendors and 9% with 30. Only for items whose value PriceScout knows: items
  it has seen at your own vending machine, and the highlighted item.

diagnostics (true or false, default false)
  true writes full diagnostics to pricescout_diag.json, including the last
  vendor's name. Turn it on when reporting a bug.

More detail: https://github.com/jmusick/price-scout#prices
