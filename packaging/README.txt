PriceScout {{VERSION}}
Fallout 76 vendor price history and suggested selling prices.
https://github.com/jmusick/price-scout

REQUIREMENTS
- xScal (https://www.nexusmods.com/fallout76/mods/4183)
- HUDModLoader
- Optional: Better Containers (https://www.nexusmods.com/fallout76/mods/4485),
  for the price feed and market-price mode

INSTALL
1. Copy PriceScout.ba2 into your Fallout 76 Data folder, for example
   C:\Program Files (x86)\Steam\steamapps\common\Fallout76\Data
2. Open Documents\My Games\Fallout 76\Fallout76Custom.ini and add PriceScout.ba2
   to sResourceArchive2List under [Archive], after a comma if other archives are
   listed:
     [Archive]
     sResourceArchive2List=OtherMod.ba2, PriceScout.ba2
3. Open Data\hudmodloader.ini and add this line:
     PriceScout
4. Start the game and open another player's vending machine.

UPDATE
Replace PriceScout.ba2 in the Data folder. Your recorded prices are kept.

UNINSTALL
Delete Data\PriceScout.ba2 and remove PriceScout from both ini files.
Recorded prices and settings are in Data\modsdata\pricescout_*.json. If you used
the Better Containers feed or market-price mode, run tools\bcfeed.py remove from
the GitHub repository with the game closed before deleting those files, to take
PriceScout's prices out of Better Containers and put yours back.

SETTINGS
Data\modsdata\pricescout_settings.json is created on first run. Change it with the
game closed. The sell methods, rounding and other settings are described at
https://github.com/jmusick/price-scout#prices
