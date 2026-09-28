#!/usr/bin/env python3
"""Score predictions against data/testset.tsv.

A "hard" word is one the dictionary alone can't settle (a/à, parle/parlé...): that's what
an AI layer would be judged on. "Easy" words are everything else.

Usage: python3 test/eval.py data/preds_dict.tsv [more preds files...] [--errors]
"""
import csv
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_testset as bt  # noqa: E402

ROOT = bt.ROOT


def load(path, key="id"):
    with open(path, encoding="utf-8") as f:
        return {r[key]: r for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\")}


def score(rows, preds, hard, show_errors):
    hard_ok, hard_n = Counter(), Counter()
    easy_ok = easy_n = exact = 0
    errors = []
    for id_, row in rows.items():
        gold = bt.WORD.findall(row["gold"])
        pred = bt.WORD.findall(preds[id_]["pred"])
        if len(gold) != len(pred):
            errors.append((row["category"], "TOKENS", row["gold"], preds[id_]["pred"]))
            continue
        exact += gold == pred
        for g, p in zip(gold, pred):
            key = bt.build_dict.strip(g.lower())
            if key in hard:
                cat = bt.category(key, hard[key])
                hard_n[cat] += 1
                hard_ok[cat] += g == p
                hard_n["ALL"] += 1
                hard_ok["ALL"] += g == p
            else:
                easy_n += 1
                easy_ok += g == p
            if g != p:
                errors.append((row["category"], "hard" if key in hard else "easy", g, p))

    pct = lambda a, b: f"{100 * a / b:5.1f}%" if b else "   - "
    print(f"  sentences fully right: {pct(exact, len(rows))}   easy words: {pct(easy_ok, easy_n)} of {easy_n}")
    print(f"  hard words: {pct(hard_ok['ALL'], hard_n['ALL'])} of {hard_n['ALL']}")
    for cat in sorted(c for c in hard_n if c != "ALL"):
        print(f"    {cat:10} {pct(hard_ok[cat], hard_n[cat])} of {hard_n[cat]}")
    if show_errors:
        for cat, kind, g, p in errors:
            print(f"    [{kind}] {g!r:20} got {p!r}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show_errors = "--errors" in sys.argv
    rows = load(ROOT / "data" / "testset.tsv")
    hard = bt.hard_keys()

    print("typed as-is (no tool)")
    score(rows, {i: {"pred": r["typed"]} for i, r in rows.items()}, hard, False)
    for path in args:
        print(path)
        score(rows, load(path), hard, show_errors)


if __name__ == "__main__":
    main()
