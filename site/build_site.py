#!/usr/bin/env python3
"""Prepare site/ assets: the demo dictionary and the icon.

- assets/demo-dict.json: the most common entries of accent_dict.tsv, so the page stays light
- assets/icon-256.png, icon-512.png: from assets/make_icon.swift

The download button points to the latest GitHub release (asset Sans-Accent.dmg, see package.sh).

Usage: python3 site/build_site.py
"""
import json
import subprocess
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
sys.path.insert(0, str(ROOT))
import build_dict  # noqa: E402

TOP_AUTO = 15000        # most frequent auto-accented words
TOP_PARTICIPLES = 4000  # most frequent -e/-é words, for "je suis allé"


def demo_dictionary():
    french = build_dict.load_french()
    freq = {}
    for word, f in french.items():
        key = build_dict.strip(word)
        freq[key] = freq.get(key, 0) + f
    by_freq = lambda keys: sorted(keys, key=lambda k: -freq.get(k, 0))

    auto, auto_fr, cycle, ambiguous, participles = {}, {}, {}, [], {}
    for line in (ROOT / "accent_dict.tsv").read_text(encoding="utf-8").splitlines():
        kind, key, *values = line.split("\t")
        if kind == "A":
            auto[key] = values[0]
        elif kind == "F":
            auto_fr[key] = values[0]
        elif kind == "C":
            cycle[key] = values
        elif kind == "P":
            ambiguous.append(key)
        elif kind == "E":
            participles[key] = values[0]

    keep_auto = set(by_freq(auto)[:TOP_AUTO]) | set(auto_fr)
    merged = {k: v for k, v in {**auto, **auto_fr}.items() if k in keep_auto}
    keep_part = by_freq(participles)[:TOP_PARTICIPLES]
    return {
        "auto": merged,
        "participles": {k: participles[k] for k in keep_part},
        "choices": {k: cycle[k] for k in ambiguous if k in cycle},
    }


def main():
    assets = SITE / "assets"
    assets.mkdir(exist_ok=True)
    data = demo_dictionary()
    (assets / "demo-dict.json").write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"demo-dict.json: {len(data['auto'])} auto, {len(data['participles'])} participles, "
          f"{len(data['choices'])} choices, {(assets / 'demo-dict.json').stat().st_size // 1024} KB")

    for size in (256, 512):
        subprocess.run(["swift", str(ROOT / "assets/make_icon.swift"), "tricolore",
                        str(assets / f"icon-{size}.png"), str(size)], check=True, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
