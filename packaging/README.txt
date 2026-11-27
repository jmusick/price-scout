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
Data\modsdata\pricescout_settings.json is created on first run. Change it with the
game closed. The sell methods, rounding and other settings are described at
https://github.com/jmusick/price-scout#prices
