# Nexus Mods listing

The text for https://www.nexusmods.com/fallout76 (the mod page). Keep it in step with
`packaging/README.txt` and the README when the install steps or settings change.

## Mod name

PriceScout - Vendor Price Tracker

## Category

User Interface

## Short description (350 characters at most)

Records the prices you see in other players' vending machines and suggests what to charge for your own. At any vending machine a panel shows the highlighted item's market price and, at other players' shops, their best deals. Feeds suggested prices into Better Containers' Vendor manager. Requires xScal and HUD Mod Loader.

## Requirements

- xScal, https://www.nexusmods.com/fallout76/mods/4183: saving data and the F10 hotkey
- HUD Mod Loader, https://www.nexusmods.com/fallout76/mods/3144: loads PriceScout into the HUD
- Optional: Better Containers, https://www.nexusmods.com/fallout76/mods/4485: the price feed and
  market-price mode

## Tags

User Interface, Utilities for Players, English

## Description (BBCode)

```bbcode
[size=4][b]PriceScout[/b][/size]
Records the prices you see in other players' vending machines and suggests what to charge for your own.

[size=3][b]Features[/b][/size]
[list]
[*]Records every listing you browse at other players' vending machines.
[*]At any vending machine, a panel at the bottom centre shows the highlighted item's suggested sell price, its typical (median) price, how many vendors had it and their price range.
[*]At another player's shop, it shows how that shop's price compares and lists the shop's best deals: items at least 10% below the market price of 2 or more other vendors. Plans and recipes you already know are left out.
[*]Feeds suggested prices into [url=https://www.nexusmods.com/fallout76/mods/4485]Better Containers[/url], so its Vendor manager starts from them. A price you set yourself is never changed.
[*]Market-price mode (F10 at your own vending machine) sets everything you sell to PriceScout's price, or to the item value +30% when it has too little market data. Press F10 again to put your own prices back.
[/list]

[size=3][b]How prices are worked out[/b][/size]
From vendors' asking prices over the last 30 days, counting each vendor once per item and leaving out free listings and 40,000+ "not for sale" placeholders. By default the suggested price is the lower quartile, a quarter of the way up from the cheapest vendor, because cheap listings sell and expensive ones stay up. It is rounded to 5 caps. Items seen at only one vendor get no market price.

All of this can be changed: see Settings below.

[size=3][b]Settings[/b][/size]
PriceScout's settings are in [i]Data\modsdata\pricescout_settings.json[/i], not in an ini file. PriceScout creates the file with the defaults the first time the game loads it, and adds back any setting that is missing. Settings are read when the game starts, so edit the file with the game closed. A value outside its range is ignored and the default is used.

The default file:
[code]
{"version":1,"diagnostics":false,"noMarketMarkupPercent":30,"sellMethod":"percentile","sellPercentile":25,"undercutPercent":5,"itemValueWeight":0,"roundTo":5}
[/code]

[b]Sell price method[/b]
[i]sellMethod[/i] picks how the suggested sell price is worked out from the vendors' prices. It is the price the panel shows as "sell", the one fed to Better Containers and the one market-price mode uses.
[list]
[*][b]"percentile"[/b] (default): the [i]sellPercentile[/i] percentile of the vendors' prices. Use it to pick how patient you are: lower sells faster, higher earns more per sale.
[*][b]"undercut"[/b]: the cheapest vendor's price less [i]undercutPercent[/i]. Sells fast by being the cheapest, but one lowball listing drags it down.
[*][b]"fencedMedian"[/b]: the median after leaving out unusually low and high prices (more than 1.5 times the interquartile range below the lower quartile or above the upper quartile), such as 9,999-cap "anchor" listings. It needs 4 or more vendors to leave anything out.
[/list]
An unknown method falls back to "percentile" and is reported in [i]pricescout_diag.json[/i]. When the method isn't the default 25th percentile, the panel names it after the price, for example [i]sell 48  cheapest -5%[/i].

[b]Method options[/b]
[list]
[*][b]sellPercentile[/b] (0 to 100, default 25): the percentile "percentile" uses. With 9 vendors, 25 is the 3rd cheapest, 50 the median and 10 just above the cheapest. Prices between vendors are interpolated.
[*][b]undercutPercent[/b] (0 to 100, default 5): how far below the cheapest vendor "undercut" goes.
[/list]

[b]Other settings[/b]
[list]
[*][b]roundTo[/b] (1 to 1000, default 5): sell prices, and market-price mode's item value prices, are rounded to the nearest this many caps, so with 5, 43 becomes 45 and 1,872 becomes 1,870. Prices below [i]roundTo[/i] are only rounded to whole caps, at least 1, so a 2-cap item isn't listed free or at 5. Use 10 or 25 for rounder prices, or "none" (or 0 or 1) for whole caps. The typical, low and high figures are never rounded.
[*][b]noMarketMarkupPercent[/b] (0 or more, default 30): in market-price mode, an item seen at fewer than 2 vendors is priced at its item value plus this percentage. [i]itemValueWeight[/i] uses the same markup.
[*][b]itemValueWeight[/b] (0 or more, default 0 = off): blends the item value plus [i]noMarketMarkupPercent[/i] into the sell price as if it were this many more vendors. With 3, the item value counts for 60% with 2 vendors and 9% with 30, so a thin market leans on the item value and a busy one barely moves. It only applies to items whose value PriceScout knows: items it has seen at your own vending machine, and the highlighted item in the panel. Blended prices are marked [i]with item value[/i] in the panel.
[*][b]diagnostics[/b] (true or false, default false): true writes full diagnostics to [i]pricescout_diag.json[/i] instead of a short summary: an event log, data samples, legendary item cards and the last vendor's name. Turn it on when reporting a bug.
[/list]

The 30-day price window, the 60 days of history kept, the 10% threshold for best deals and the F10 key are fixed.

[size=3][b]Requirements[/b][/size]
[list]
[*][url=https://www.nexusmods.com/fallout76/mods/4183]xScal[/url], for saving data and the F10 hotkey
[*][url=https://www.nexusmods.com/fallout76/mods/3144]HUD Mod Loader[/url], which loads PriceScout into the HUD
[*]Optional: [url=https://www.nexusmods.com/fallout76/mods/4485]Better Containers[/url], for the price feed and market-price mode
[/list]

[size=3][b]Installation[/b][/size]
[list=1]
[*]Install xScal: its [i]dxgi.dll[/i] goes in the game folder, next to [i]Fallout76.exe[/i], not in Data.
[*]Install HUD Mod Loader as its page says.
[*]Copy [i]PriceScout.ba2[/i] into your [i]Fallout76\Data[/i] folder.
[*]In [i]Documents\My Games\Fallout 76\Fallout76Custom.ini[/i], add [i]PriceScout.ba2[/i] to [i]sResourceArchive2List[/i] under [i][Archive][/i], before [i]HUDModLoader.ba2[/i], which has to stay last (or [i]ChatMod.ba2[/i] last, with Text Chat):
[code]
[Archive]
sResourceArchive2List=OtherMod.ba2, PriceScout.ba2, HUDModLoader.ba2
[/code]
[*]Add a line with [i]PriceScout[/i] to [i]Data\hudmodloader.ini[/i].
[*]Start the game and open another player's vending machine.
[/list]

[size=3][b]After a game patch[/b][/size]
xScal needs a new Address Library file for each game version. Until it has one, PriceScout can't save prices or read the F10 hotkey. With xScal's default settings it offers the new file when the game starts: click Yes and restart.

[size=3][b]Your data[/b][/size]
Everything stays on your PC, in [i]Data\modsdata\pricescout_*.json[/i]. PriceScout records the time, price and quantity of each listing and a hash of the vendor's name, not the name itself. Entries older than 60 days are dropped. Only with [i]diagnostics[/i] turned on does the diagnostics file hold the last vendor's name. PriceScout sends nothing anywhere.

[size=3][b]Uninstalling[/b][/size]
Delete [i]Data\PriceScout.ba2[/i] and remove PriceScout from both ini files. If you used the Better Containers feed or market-price mode, first run [i]tools\bcfeed.py remove[/i] from the GitHub repository with the game closed, to take PriceScout's prices out of Better Containers and restore yours.

[size=3][b]Source[/b][/size]
[url=https://github.com/jmusick/price-scout]github.com/jmusick/price-scout[/url]. Bug reports and suggestions are welcome there or in the Bugs tab.
```
