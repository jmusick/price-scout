"""Preview or undo PriceScout's feed into Better Containers' remembered prices.

Usage:
  python -I tools/bcfeed.py preview   what the mod would add or update right now
  python -I tools/bcfeed.py remove    take PriceScout's prices back out (run with the game closed)

The mod itself does the feeding in game. Same rules here: non-legendary items seen at
FEED_MIN_VENDORS or more vendors, at the selling price (lower quartile, see report.py); a key is only added if Better Containers has no price
for it, and only updated if it still holds the value PriceScout last wrote.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from report import DAY, sell_price, vendor_prices  # noqa: E402

import time  # noqa: E402

MODSDATA = r"C:\Games\Steam\steamapps\common\Fallout76\Data\modsdata"
HISTORY = os.path.join(MODSDATA, "pricescout_history.json")
BC = os.path.join(MODSDATA, "bettercontainers_vendorprices.json")
FEED = os.path.join(MODSDATA, "pricescout_bcfeed.json")
FEED_MIN_VENDORS = 2
DAYS = 30
BC_MAX_PRICE = 40000


def load(path, default):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def preview():
    history = load(HISTORY, {"items": {}})["items"]
    prices = load(BC, {"prices": {}})["prices"]
    record = load(FEED, {"written": {}})
    written = record["written"]
    if record.get("marketMode"):
        print("Market-price mode is ON in game: every remembered price is set to market (0 = no data).")
        print(f"{len(record.get('originals', {}))} of your own prices are saved and come back when it is switched off.")
        return
    cutoff = time.time() - DAYS * DAY
    added, updated, yours = [], [], []
    for key, entries in sorted(history.items()):
        if int(key.rsplit("|", 1)[1]) > 0:
            continue
        found = vendor_prices(entries, cutoff)
        if len(found) < FEED_MIN_VENDORS:
            continue
        price = int(max(1, min(BC_MAX_PRICE, sell_price(found))))
        current = prices.get(key)
        if current is None:
            added.append((key, price))
        elif key in written and current == written[key]:
            if current != price:
                updated.append((key, current, price))
        else:
            yours.append((key, current, price))
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(f"would add {len(added)}, update {len(updated)}, keep {len(yours)} of your own prices")
    for key, price in added:
        print(f"  add     {key.lstrip(' ¶'):<55} {price}")
    for key, old, price in updated:
        print(f"  update  {key.lstrip(' ¶'):<55} {old} -> {price}")
    for key, current, price in yours:
        print(f"  yours   {key.lstrip(' ¶'):<55} {current} (suggestion {price})")


def remove():
    doc = load(BC, None)
    record = load(FEED, None)
    if doc is None or record is None:
        print("Nothing to remove.")
        return
    removed = restored = 0
    originals = record.get("originals", {})
    for key, value in record["written"].items():
        if doc["prices"].get(key) != value:
            continue  # changed since PriceScout wrote it: leave it
        if key in originals:
            doc["prices"][key] = originals[key]  # your price, replaced by market-price mode
            restored += 1
        else:
            del doc["prices"][key]
            removed += 1
    with open(BC, "w", encoding="utf-8") as f:
        f.write(json.dumps(doc, ensure_ascii=False, separators=(",", ":")))
    os.remove(FEED)
    print(f"Removed {removed} PriceScout prices and restored {restored} of yours in {os.path.basename(BC)}.")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "preview":
        preview()
    elif command == "remove":
        remove()
    else:
        raise SystemExit(__doc__)
