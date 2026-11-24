"""Print suggested prices from PriceScout's history file.

Usage: python -I tools/report.py [path to pricescout_history.json] [--days N] [--filter text]
                                 [--min-vendors N] [--method M] [--percentile P]
                                 [--undercut P] [--item-value-weight W]

Prices are vendors' asking prices over the last N days (default 30), counting each vendor
once per item: its lowest price on the most recent day it was seen, which is what a buyer
would pay when a vendor lists the same item in several stacks. Free listings (0 caps)
and prices at or above 40000, the usual "not for sale" placeholder, are left out.

  sell     the suggested selling price, what the mod feeds Better Containers, by the
           sellMethod in pricescout_settings.json (next to the history file) unless
           --method is given:
             percentile    the --percentile percentile of those prices (default 25, the
                           lower quartile: asking prices lean high, since cheap listings
                           sell and expensive ones stay up)
             undercut      the cheapest vendor's price less --undercut percent (default 5)
             fencedMedian  the median, leaving out prices more than 1.5 interquartile
                           ranges outside the middle half (needs 4+ vendors to drop any)
           With --item-value-weight W above 0, blended with the item value plus
           noMarketMarkupPercent as if that were W vendors, for items whose value the mod
           has seen at your machine (pricescout_bcfeed.json).
  market   the lower quartile, what the in-game deals are measured against.
  typical  the median asking price.

Items seen at only one vendor show no sell price: one person's price is not a market.
"""

import argparse
import json
import os
import sys
import time

DEFAULT_PATH = r"C:\Games\Steam\steamapps\common\Fallout76\Data\modsdata\pricescout_history.json"
PLACEHOLDER = 40000
DAY = 86400
MARKET_QUANTILE = 0.25
MARKET_MIN_VENDORS = 2
TUKEY_K = 1.5
METHODS = ("percentile", "undercut", "fencedMedian")
# The mod's defaults for pricescout_settings.json.
DEFAULT_SETTINGS = {
    "noMarketMarkupPercent": 30,
    "sellMethod": "percentile",
    "sellPercentile": 25,
    "undercutPercent": 5,
    "itemValueWeight": 0,
}
# Allowed ranges; the mod uses its default for a value outside them.
LIMITS = {
    "noMarketMarkupPercent": (0, float("inf")),
    "sellPercentile": (0, 100),
    "undercutPercent": (0, 100),
    "itemValueWeight": (0, float("inf")),
}


def quantile(sorted_prices, q):
    """Linear-interpolated quantile, the same as the mod's."""
    pos = q * (len(sorted_prices) - 1)
    below = int(pos)
    above = min(len(sorted_prices) - 1, below + 1)
    return sorted_prices[below] + (sorted_prices[above] - sorted_prices[below]) * (pos - below)


def mod_round(value):
    """Rounds as the mod's Math.round does: halves go up (Python's round() goes to even)."""
    return int(value + 0.5) if value >= 0 else -int(-value + 0.5)


def load_settings(folder):
    """The mod's settings from pricescout_settings.json in folder, with its defaults for
    anything missing or out of range (the same checks as the mod)."""
    settings = dict(DEFAULT_SETTINGS)
    path = os.path.join(folder, "pricescout_settings.json")
    if not os.path.exists(path):
        return settings
    with open(path, encoding="utf-8") as f:
        stored = json.load(f)
    if stored.get("sellMethod") in METHODS:
        settings["sellMethod"] = stored["sellMethod"]
    for name, (low, high) in LIMITS.items():
        value = stored.get(name)
        if isinstance(value, (int, float)) and not isinstance(value, bool) and low <= value <= high:
            settings[name] = value
    return settings


def load_item_values(folder):
    """Item values of what the mod has seen at your machine (pricescout_bcfeed.json)."""
    path = os.path.join(folder, "pricescout_bcfeed.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f).get("ownedValues", {})


def method_price(sorted_prices, settings):
    """The selling price by settings["sellMethod"], before blending, the same as the mod's."""
    method = settings["sellMethod"]
    if method == "undercut":
        return sorted_prices[0] * (1 - settings["undercutPercent"] / 100)
    if method == "fencedMedian":
        # Tukey's fences: prices more than 1.5 interquartile ranges outside the middle half.
        q1 = quantile(sorted_prices, 0.25)
        q3 = quantile(sorted_prices, 0.75)
        fence = TUKEY_K * (q3 - q1)
        kept = [p for p in sorted_prices if q1 - fence <= p <= q3 + fence]
        return quantile(kept, 0.5)
    return quantile(sorted_prices, settings["sellPercentile"] / 100)


def sell_price(sorted_prices, settings=DEFAULT_SETTINGS, item_value=None):
    """Suggested selling price, or None with fewer than MARKET_MIN_VENDORS vendors.
    Blended with item_value (+noMarketMarkupPercent) when itemValueWeight is above 0."""
    if len(sorted_prices) < MARKET_MIN_VENDORS:
        return None
    price = method_price(sorted_prices, settings)
    weight = settings["itemValueWeight"]
    if weight > 0 and isinstance(item_value, (int, float)) and item_value > 0:
        fallback = item_value * (1 + settings["noMarketMarkupPercent"] / 100)
        price = (len(sorted_prices) * price + weight * fallback) / (len(sorted_prices) + weight)
    return max(1, mod_round(price))


def method_text(settings):
    """The selling method in words, as the mod's panel names it."""
    method = settings["sellMethod"]
    if method == "undercut":
        text = f"cheapest -{settings['undercutPercent']:g}%"
    elif method == "fencedMedian":
        text = "fenced median"
    else:
        text = f"percentile {settings['sellPercentile']:g}"
    if settings["itemValueWeight"] > 0:
        text += (f", blended with item value +{settings['noMarketMarkupPercent']:g}%"
                 f" as {settings['itemValueWeight']:g} vendors where it is known")
    return text


def vendor_prices(entries, cutoff):
    """Lowest price per vendor on that vendor's most recent day in the window."""
    best = {}  # vendor -> (day, price)
    for t, price, count, vendor, mode in entries:
        if t < cutoff or price <= 0 or price >= PLACEHOLDER:
            continue
        day = int(t // DAY)
        seen = best.get(vendor)
        if seen is None or day > seen[0] or (day == seen[0] and price < seen[1]):
            best[vendor] = (day, price)
    return sorted(price for _, price in best.values())


def grouped(items):
    """Legendary items (stars > 0) are grouped by name and stars, any level, like the
    in-game panel: vendor lists never show their other effects, so level adds little."""
    groups = {}
    for key, entries in items.items():
        name, level, stars = key.rsplit("|", 2)
        group = f"{name}|*|{stars}" if int(stars) > 0 else key
        groups.setdefault(group, []).extend(entries)
    return groups


def suggestions(items, days, text_filter, settings=DEFAULT_SETTINGS, item_values=None):
    """Rows of (key, sell, market, typical, low, high, vendors)."""
    cutoff = time.time() - days * DAY
    item_values = item_values or {}
    rows = []
    for key, entries in grouped(items).items():
        if text_filter and text_filter.lower() not in key:
            continue
        prices = vendor_prices(entries, cutoff)
        if not prices:
            continue
        rows.append((key, sell_price(prices, settings, item_values.get(key)),
                     mod_round(quantile(prices, MARKET_QUANTILE)), mod_round(quantile(prices, 0.5)),
                     prices[0], prices[-1], len(prices)))
    return sorted(rows, key=lambda row: display_name(row[0]))


def display_name(key):
    """The key without the leading sort-tag glyph some item-sorting mods add."""
    return key.lstrip(" \u00b6")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", nargs="?", default=DEFAULT_PATH)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--filter", default="")
    parser.add_argument("--min-vendors", type=int, default=1, help="only items seen at this many vendors or more")
    parser.add_argument("--method", choices=METHODS, help="selling method (default: sellMethod in the settings file)")
    parser.add_argument("--percentile", type=float, help="percentile for the percentile method, 0-100")
    parser.add_argument("--undercut", type=float, help="percent below the cheapest vendor for the undercut method")
    parser.add_argument("--item-value-weight", type=float, help="blend in the item value as this many vendors (0: off)")
    args = parser.parse_args()
    folder = os.path.dirname(os.path.abspath(args.path))
    settings = load_settings(folder)
    for name, value in (("sellMethod", args.method), ("sellPercentile", args.percentile),
                        ("undercutPercent", args.undercut), ("itemValueWeight", args.item_value_weight)):
        if value is None:
            continue
        if name in LIMITS and not LIMITS[name][0] <= value <= LIMITS[name][1]:
            parser.error(f"{name} must be between {LIMITS[name][0]:g} and {LIMITS[name][1]:g}")
        settings[name] = value
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    with open(args.path, encoding="utf-8") as f:
        data = json.load(f)
    rows = [r for r in suggestions(data.get("items", {}), args.days, args.filter, settings, load_item_values(folder))
            if r[6] >= args.min_vendors]
    if not rows:
        print("No prices recorded in that window.")
        return
    print(f"sell: {method_text(settings)}")
    width = min(60, max(len(display_name(r[0])) for r in rows))
    print(f"{'item (name|level|stars)':<{width}}  {'sell':>7}  {'market':>7}  {'typical':>7}  {'low':>7}  {'high':>7}  vendors")
    for key, sell, market, median, low, high, vendors in rows:
        name = display_name(key)
        sell_text = f"{sell:>7}" if sell is not None else f"{'-':>7}"
        print(f"{name[:width]:<{width}}  {sell_text}  {market:>7}  {median:>7}  {low:>7.0f}  {high:>7.0f}  {vendors:>7}")


if __name__ == "__main__":
    main()
