#!/usr/bin/env python3
"""Rebuild the pinned offline catalog from ccusage's models-dev-pricing.json.
Usage: python3 scripts/update-community-prices.py /path/to/ccusage/.../models-dev-pricing.json
Review upstream license/revision and update Resources/ThirdParty/NOTICE.md with every refresh.
"""
import json
import math
import pathlib
import sys

source = json.loads(pathlib.Path(sys.argv[1]).read_text())
rates = {}
for key, entry in source.items():
    cost = entry.get('cost', {})
    if cost.get('tiers') or not all(type(cost.get(k)) in (int, float) and 0 <= cost[k] <= 1e6 for k in ('input', 'output')):
        continue
    rate = dict(input=cost['input'], output=cost['output'],
                cacheWrite=cost.get('cache_write', cost['input']),
                cacheRead=cost.get('cache_read', cost['input']))
    if all(type(n) in (int, float) and math.isfinite(n) and 0 <= n <= 1e6 for n in rate.values()):
        rates[key] = rate
output = pathlib.Path(__file__).resolve().parents[1] / 'Sources/MacPulse/AIUsage/CommunityPrices.json'
output.write_text(json.dumps(rates, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n')
print(f'{len(rates)} entries written; {len(source)-len(rates)} skipped (tiers/invalid prices).')
