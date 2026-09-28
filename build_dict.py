#!/usr/bin/env python3
"""Build accent_dict.tsv, the app's dictionary, from Lexique 3.83 (French) + an English frequency list.

For every French word, the key is its accent-free form ("côté" -> "cote").
- auto:  key -> the accented word to substitute without asking
- cycle: key -> every spelling, most frequent first, the plain form always included

A key is auto-accented only when the plain form is not itself a common French word
(top variant share >= AUTO_SHARE). Then:
- auto:    also not a common English word (French freq >= EN_RATIO x English freq)
- auto_fr: an English word too ("grace", "present", "general"): accented only while
           the text around it is French (decided in Sources/AccentCore/Engine.swift)

Usage: python3 build_dict.py   (expects data/Lexique383.tsv and data/en_50k.txt)
"""
import collections
import csv
import unicodedata
from pathlib import Path

ROOT = Path(__file__).parent
LEXIQUE = ROOT / "data" / "Lexique383.tsv"
ENGLISH = ROOT / "data" / "en_50k.txt"
OUT = ROOT / "accent_dict.tsv"

AUTO_SHARE = 0.90
EN_RATIO = 10

# Final say, whatever the data says.
FORCE_AUTO = {"ca": "ça", "deja": "déjà", "voila": "voilà", "tres": "très", "apres": "après"}
NEVER_AUTO = {"a", "ou", "la", "des", "du", "sur", "sure", "mur", "age",
              "these", "hair", "sense", "sake", "peter", "hero", "lies", "male", "eve"}
PARTICIPLE_MIN_SHARE = 0.03  # "aime" -> "aimé" after an auxiliary; not "envie" -> "envié" (0.4%)
CHOICE_MIN_SHARE = 0.15  # show the choice list when the runner-up is at least this common
AGREE_MIN_FREQ = 1.0  # per million: spellings that count when looking for agreed accents
EN_TOO_COMMON = 1000  # per million: "the", "he", "be"... never auto, even in French text
FR_TOO_RARE = 1.0     # per million: "réal", "béer"... not worth an auto-accent

# Words newer than Lexique (2014), with a made-up frequency per million.
EXTRA_WORDS = {"présentiel": 5, "distanciel": 5, "présentielle": 2, "distancielle": 2,
               "télétravail": 10, "visioconférence": 5}

# Lexique writes "coeur", "soeur"... Words containing these stems get the ligature.
OE_STEMS = ("cœur", "sœur", "œil", "œuf", "œuvr", "bœuf", "nœud", "vœu", "mœurs", "chœur",
            "fœtus", "œsophag", "œcuméni", "œnolog", "œdème", "œstrog")


def ligature(word):
    lig = word.replace("oe", "œ")
    return lig if lig != word and any(stem in lig for stem in OE_STEMS) else word


def strip(word):
    word = word.replace("œ", "oe").replace("æ", "ae").replace("Œ", "Oe").replace("Æ", "Ae")
    return "".join(c for c in unicodedata.normalize("NFD", word) if unicodedata.category(c) != "Mn")


def load_french():
    freq = collections.Counter()
    with LEXIQUE.open(encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            word = row["ortho"]
            if word and word.isalpha():
                word = ligature(word)
                freq[word] += (float(row["freqfilms2"] or 0) + float(row["freqlivres"] or 0)) / 2
    freq.update(EXTRA_WORDS)
    return freq  # occurrences per million words


def load_english():
    counts = {}
    for line in ENGLISH.open(encoding="utf-8"):
        word, count = line.split()
        counts[word] = int(count)
    total = sum(counts.values())
    return {w: c / total * 1e6 for w, c in counts.items()}


def agreement(variants):
    """Accents every common spelling agrees on: {téléphone, téléphoné} -> "téléphone".
    Only returned when that is itself one of the spellings, so it's always a real word."""
    common = [v for v, f in variants.items() if f >= AGREE_MIN_FREQ]
    if len(common) < 2:
        common = list(variants)  # rare word: every spelling counts
    if len(common) < 2 or len({len(v) for v in common}) > 1:
        return None
    merged = "".join(cs[0] if len(set(cs)) == 1 else strip(cs[0]) for cs in zip(*common))
    return merged if merged in variants else None


def main():
    french = load_french()
    english = load_english()

    groups = collections.defaultdict(dict)
    for word, fq in french.items():
        groups[strip(word)][word] = fq

    auto, auto_fr, cycle, ambiguous, participles = {}, {}, {}, set(), {}
    for key, variants in groups.items():
        if all(v == key for v in variants):
            continue  # no accented spelling exists
        common = sorted((v for v, f in variants.items() if f >= AGREE_MIN_FREQ), key=lambda v: -variants[v])
        if len(common) >= 2 and variants[common[1]] >= CHOICE_MIN_SHARE * sum(variants[v] for v in common):
            ambiguous.add(key)
        ordered = sorted(variants, key=lambda v: -variants[v])
        if key not in ordered:
            ordered.append(key)  # always allow going back to what was typed
        cycle[key] = ordered

        top = ordered[0]
        total = sum(variants.values())
        share = variants[top] / total if total else (1.0 if len(variants) == 1 else 0.0)
        # Every spelling counts here, however rare: "mémorisé", "captivé" are real participles.
        ending = "és" if key.endswith("es") else "é" if key.endswith("e") else None
        forms = [v for v in ordered if ending and v.endswith(ending) and v != key]
        if forms and variants[forms[0]] >= PARTICIPLE_MIN_SHARE * total:
            participles[key] = forms[0]
        if share < AUTO_SHARE:
            top = agreement(variants) or key
        if top == key or key in NEVER_AUTO:
            continue
        en = english.get(key, 0)
        if en * EN_RATIO <= variants[top]:
            auto[key] = top
        elif en < EN_TOO_COMMON and variants[top] >= FR_TOO_RARE:
            auto_fr[key] = top

    auto.update(FORCE_AUTO)

    # One line per entry: A (auto) / F (auto in French text) / C (cycle) / P (show choices) /
    # E (past participle, after an auxiliary), key, value(s).
    with OUT.open("w", encoding="utf-8") as f:
        for k in sorted(auto):
            f.write(f"A\t{k}\t{auto[k]}\n")
        for k in sorted(auto_fr):
            f.write(f"F\t{k}\t{auto_fr[k]}\n")
        for k in sorted(cycle):
            f.write(f"C\t{k}\t" + "\t".join(cycle[k]) + "\n")
        for k in sorted(ambiguous):
            f.write(f"P\t{k}\t1\n")
        for k in sorted(participles):
            f.write(f"E\t{k}\t{participles[k]}\n")

    print(f"auto: {len(auto)}  auto_fr: {len(auto_fr)}  cycle: {len(cycle)}  ambiguous: {len(ambiguous)}  participles: {len(participles)}")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
