#!/usr/bin/env python3
"""Build data/testset.tsv: sentences typed without accents, with the correctly accented original.

Sources:
- Tatoeba French sentences (CC-BY 2.0 FR), filtered to those containing a "hard" word,
  i.e. one whose accent the dictionary alone cannot decide (a/à, parle/parlé...)
- test/handwritten.txt: professional-register sentences (emails, training material)

Columns: id, category, source, typed, gold
Usage: python3 test/build_testset.py
"""
import collections
import csv
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import build_dict  # noqa: E402

TATOEBA = ROOT / "data" / "fra_sentences.tsv"
HANDWRITTEN = ROOT / "test" / "handwritten.txt"
OUT = ROOT / "data" / "testset.tsv"

WORD = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿŒœÆæ]+")
MIN_FREQ = 1.0  # per million: a spelling must be this common to count as a real alternative

# How many Tatoeba sentences to draw per category
QUOTA = {"a/à": 30, "ou/où": 20, "la/là": 15, "du/dû": 10, "sur/sûr": 10, "des/dès": 8,
         "-e/-é": 50, "other": 25}
SHORT = {"a": "a/à", "ou": "ou/où", "la": "la/là", "du": "du/dû", "sur": "sur/sûr", "des": "des/dès"}


def hard_keys():
    """Keys with at least two common spellings (a/à, parle/parlé...). Depends on French only,
    not on the dictionary, so improving the dictionary doesn't move the goalposts."""
    french = build_dict.load_french()
    groups = collections.defaultdict(dict)
    for word, fq in french.items():
        groups[build_dict.strip(word)][word] = fq
    hard = {}
    for key, variants in groups.items():
        common = {v for v, f in variants.items() if f >= MIN_FREQ}
        if len(common) >= 2:
            hard[key] = common
    return hard


def category(key, variants):
    if key in SHORT:
        return SHORT[key]
    if any(v.endswith(("é", "ée", "és", "ées")) for v in variants) and key.endswith(("e", "es")):
        return "-e/-é"
    return "other"


def typed(sentence):
    return build_dict.strip(sentence)


def main():
    hard = hard_keys()
    rng = random.Random(42)

    by_cat = collections.defaultdict(list)
    with TATOEBA.open(encoding="utf-8") as f:
        for _, _, sentence in csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            words = WORD.findall(sentence)
            if not 5 <= len(words) <= 25:
                continue
            cats = {category(build_dict.strip(w.lower()), hard[build_dict.strip(w.lower())])
                    for w in words if build_dict.strip(w.lower()) in hard}
            accented = any(w != build_dict.strip(w) for w in words if build_dict.strip(w.lower()) in hard)
            for cat in cats:
                by_cat[cat].append((accented, sentence))

    rows, seen = [], set()
    for cat, quota in QUOTA.items():
        pool = by_cat[cat]
        rng.shuffle(pool)
        # Half with an accented hard word, half without, so "never change" can't score well.
        with_accent = [s for acc, s in pool if acc and s not in seen][: quota - quota // 2]
        without = [s for acc, s in pool if not acc and s not in seen][: quota // 2]
        seen.update(with_accent + without)
        rows += [(cat, "tatoeba", s) for s in with_accent + without]

    for line in HANDWRITTEN.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            rows.append(("handwritten", "handwritten", line.strip()))

    with OUT.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\")
        w.writerow(["id", "category", "source", "typed", "gold"])
        for i, (cat, src, s) in enumerate(rows, 1):
            w.writerow([i, cat, src, typed(s), s])

    counts = collections.Counter(c for c, _, _ in rows)
    print(f"{len(rows)} sentences -> {OUT}")
    for c, n in counts.items():
        print(f"  {c:12} {n}")


if __name__ == "__main__":
    main()
