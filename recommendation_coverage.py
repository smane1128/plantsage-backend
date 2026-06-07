"""
Coverage report for recommendation_service.py plant knowledge base.
Run: python recommendation_coverage.py
"""
from collections import Counter
from services.recommendation_service import _PLANTS

def main():
    total = len(_PLANTS)
    cats = Counter(p["category"] for p in _PLANTS)
    sun  = Counter(p["sunlight"]   for p in _PLANTS)
    water= Counter(p["water"]      for p in _PLANTS)
    maint= Counter(p["maintenance"]for p in _PLANTS)
    flow = Counter(p["flowering"]  for p in _PLANTS)

    print("=" * 55)
    print(f"  PLANT KNOWLEDGE BASE COVERAGE REPORT")
    print("=" * 55)
    print(f"\n  Total plants: {total}\n")

    print("  By Category:")
    for cat, n in sorted(cats.items(), key=lambda x: -x[1]):
        bar = "#" * n
        print(f"    {cat:<30} {n:3d}  {bar}")

    print(f"\n  By Sunlight:   Full sun={sun['full_sun']}  Partial={sun['partial_shade']}  Shade={sun['full_shade']}")
    print(f"  By Water:      Low={water['low']}  Medium={water['medium']}  High={water['high']}")
    print(f"  By Maintenance: Easy={maint['easy']}  Medium={maint['medium']}  Hard={maint['hard']}")
    print(f"  Flowering:     Yes={flow[True]}  No={flow[False]}")

    print("\n  Top 10 landscape use tags:")
    all_tags = []
    for p in _PLANTS:
        all_tags.extend(p["landscape"])
    for tag, n in Counter(all_tags).most_common(10):
        print(f"    {tag:<20} {n}")

    print("\n  Coverage gap analysis:")
    if total < 150:
        gap = 150 - total
        print(f"    Need {gap} more plants to reach 150-plant target.")
        print("\n  Suggested additions:")
        suggestions = [
            ("Flowering Shrub", ["Jacobinia", "Eranthemum", "Russelia"]),
            ("Tropical Flowering Plant", ["Costus woodsonii", "Zingiber zerumbet"]),
            ("Indoor Foliage", ["Hoya", "Peperomia", "Alocasia"]),
            ("Fruit", ["Jackfruit", "Soursop", "Longan"]),
            ("Tree", ["Flame of the Forest", "African Tulip Tree"]),
            ("Herb", ["Thai Basil", "Ulam Raja", "Pegaga"]),
            ("Grass", ["Vetiver", "Buffalo Grass"]),
        ]
        for cat, plants in suggestions:
            print(f"    {cat}: {', '.join(plants)}")
    else:
        print(f"    Target of 150 plants reached! ({total} plants)")

    print("=" * 55)

if __name__ == "__main__":
    main()
