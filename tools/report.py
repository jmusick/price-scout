"""Print suggested prices from PriceScout's history file.

Usage: python -I tools/report.py [path to pricescout_history.json] [--days N] [--filter text]
                                 [--min-vendors N]

Prices are vendors' asking prices over the last N days (default 30), counting each vendor
once per item: its lowest price on the most recent day it was seen, which is what a buyer
would pay when a vendor lists the same item in several stacks. Free listings (0 caps)
and prices at or above 40000, the usual "not for sale" placeholder, are left out.

  sell     the lower quartile of those prices: competitive without matching the cheapest.
           Asking prices lean high (cheap listings sell, expensive ones stay up), so this
           is the suggested selling price, and what the mod feeds Better Containers.
  typical  the median asking price.

Items seen at only one vendor show no sell price: one person's price is not a market.
"""

import argparse
import json
import statistics
import sys
import time

DEFAULT_PATH = r"C:\Games\Steam\steamapps\common\Fallout76\Data\modsdata\pricescout_history.json"
PLACEHOLDER = 40000
DAY = 86400
SELL_QUANTILE = 0.25
MARKET_MIN_VENDORS = 2


def quantile(sorted_prices, q):
    """Linear-interpolated quantile, the same as the mod's."""
    pos = q * (len(sorted_prices) - 1)
    below = int(pos)
    above = min(len(sorted_prices) - 1, below + 1)
    return sorted_prices[below] + (sorted_prices[above] - sorted_prices[below]) * (pos - below)


def sell_price(sorted_prices):
    """Suggested selling price, or None with fewer than MARKET_MIN_VENDORS vendors."""
    if len(sorted_prices) < MARKET_MIN_VENDORS:
        return None
    return round(quantile(sorted_prices, SELL_QUANTILE))


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


def suggestions(items, days, text_filter):
    cutoff = time.time() - days * DAY
    rows = []
    for key, entries in grouped(items).items():
        if text_filter and text_filter.lower() not in key:
            continue
        prices = vendor_prices(entries, cutoff)
        if not prices:
            continue
        rows.append((key, sell_price(prices), statistics.median(prices), prices[0], prices[-1], len(prices)))
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
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    with open(args.path, encoding="utf-8") as f:
        data = json.load(f)
    rows = [r for r in suggestions(data.get("items", {}), args.days, args.filter) if r[5] >= args.min_vendors]
    if not rows:
        print("No prices recorded in that window.")
        return
    width = min(60, max(len(display_name(r[0])) for r in rows))
    print(f"{'item (name|level|stars)':<{width}}  {'sell':>7}  {'typical':>7}  {'low':>7}  {'high':>7}  vendors")
    for key, sell, median, low, high, vendors in rows:
        name = display_name(key)
        sell_text = f"{sell:>7}" if sell is not None else f"{'-':>7}"
        print(f"{name[:width]:<{width}}  {sell_text}  {median:>7.0f}  {low:>7.0f}  {high:>7.0f}  {vendors:>7}")


if __name__ == "__main__":
    main()
