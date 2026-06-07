"""
pet_safety_audit.py — Coverage audit and test suite for pet_safety_service.

Usage:
    cd C:\myplants\backend
    .\venv\Scripts\Activate.ps1
    python pet_safety_audit.py
"""
from __future__ import annotations
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Suppress debug prints from lookup
import services.pet_safety_service as _svc
import builtins
_real_print = builtins.print
def _silent_print(*a, **kw):
    msg = " ".join(str(x) for x in a)
    if msg.startswith("[pet_safety]"):
        return
    _real_print(*a, **kw)
builtins.print = _silent_print

from services.pet_safety_service import lookup_pet_safety, _SAFETY, _ALIASES

# ─── Required test cases ──────────────────────────────────────────────────────
TESTS = [
    # (scientific_name, common_name, expected_status)
    ("Rosa indica",                       "Rose",                 "safe"),
    ("Hibiscus rosa-sinensis",            "Hibiscus",             "safe"),
    ("Narcissus pseudonarcissus",         "Daffodil",             "toxic"),
    ("Tulipa gesneriana",                 "Tulip",                "toxic"),
    ("Hyacinthus orientalis",             "Hyacinth",             "toxic"),
    ("Crocus sativus",                    "Crocus",               "caution"),
    ("Crossandra infundibuliformis",      "Firecracker Flower",   "safe"),
    ("Selenicereus grandiflorus",         "Queen of the Night",   "safe"),
    ("Cycas revoluta",                    "Sago Palm",            "toxic"),
    # bonus cases
    ("Codiaeum variegatum",               "Croton",               "toxic"),
    ("Euphorbia tirucalli",               "Pencil Cactus",        "toxic"),
    ("Zamioculcas zamiifolia",            "ZZ Plant",             "caution"),
    ("Monstera deliciosa",                "Swiss Cheese Plant",   "caution"),
    ("Aglaonema commutatum",              "Chinese Evergreen",    "caution"),
    ("Anthurium andraeanum",              "Flamingo Flower",      "caution"),
    ("Dendrobium sp.",                    "Orchid",               "safe"),
    ("Phalaenopsis amabilis",             "Moth Orchid",          "safe"),
]

# ─── Run tests ────────────────────────────────────────────────────────────────
print("=" * 72)
print(f"  {'Plant':<30} {'Expected':<10} {'Got':<10} {'Source':<10}  Result")
print("=" * 72)
passed = failed = 0
for sci, com, expected in TESTS:
    r = lookup_pet_safety(sci, com)
    ok = r["status"] == expected and r["source"] == "database"
    mark = "PASS" if ok else "FAIL"
    if ok:
        passed += 1
    else:
        failed += 1
    status_got = r["status"]
    source_got = r["source"]
    _real_print(f"  {com:<30} {expected:<10} {status_got:<10} {source_got:<10}  {mark}")

print("=" * 72)
_real_print(f"  Tests: {passed + failed}   Passed: {passed}   Failed: {failed}")

# ─── Coverage audit ───────────────────────────────────────────────────────────
_real_print()
_real_print("=" * 72)
_real_print("  COVERAGE AUDIT")
_real_print("=" * 72)
_real_print(f"  _SAFETY entries : {len(_SAFETY)}")
_real_print(f"  _ALIASES entries: {len(_ALIASES)}")

# Group by status
from collections import Counter
c = Counter(v["status"] for v in _SAFETY.values())
_real_print(f"  safe   : {c['safe']}")
_real_print(f"  caution: {c['caution']}")
_real_print(f"  toxic  : {c['toxic']}")

# Aliases that resolve to a known key
covered = sum(1 for v in _ALIASES.values() if v in _SAFETY or v.split()[0] in _SAFETY)
_real_print(f"  Alias coverage : {covered}/{len(_ALIASES)} aliases resolve to a database entry")

_real_print()
_real_print("  Top missing common names (aliases with no _SAFETY match):")
missing = [k for k, v in _ALIASES.items() if v not in _SAFETY and v.split()[0] not in _SAFETY]
if missing:
    for m in sorted(missing):
        _real_print(f"    - {m!r} → {_ALIASES[m]!r}")
else:
    _real_print("    (none — all aliases resolve)")

_real_print()
_real_print("Done.")
