#!/usr/bin/env python3
"""Prepare site/: the demo dictionary, the icon, and what search engines and AI assistants read.

- assets/demo-dict.json: the most common entries of accent_dict.tsv, so the page stays light
- assets/icon-256.png, icon-512.png: from assets/make_icon.swift
- structured data (JSON-LD) in each page; the FAQ is read from the page's visible questions
- llms.txt, sitemap.xml, robots.txt

The download button points to the latest GitHub release (asset Sans-Accent.dmg, see package.sh).

Usage: python3 site/build_site.py
"""
import datetime
import html
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
sys.path.insert(0, str(ROOT))
import build_dict  # noqa: E402

SITE_URL = "https://sans-accent.com"
DOWNLOAD_URL = "https://github.com/antoineant/sans-accent/releases/latest/download/Sans-Accent.dmg"
REPO_URL = "https://github.com/antoineant/sans-accent"
STUDIO = {
    "@type": "Organization",
    "@id": "https://www.girafestudio.fr/#organization",
    "name": "Girafe Studio",
    "url": "https://www.girafestudio.fr",
    "address": {"@type": "PostalAddress", "addressLocality": "Toulouse", "addressCountry": "FR"},
}
# (file, language, kind, path, {language: path} of every version, this one included)
HOME = {"fr": "/", "en": "/en/"}
QWERTY_GUIDE = {"fr": "/accents-clavier-qwerty-mac/", "en": "/en/french-accents-qwerty-mac/"}
MISTAKES_GUIDE = {"fr": "/fautes-accent-frequentes/"}
PAGES = [
    ("index.html", "fr", "home", "/", HOME),
    ("en/index.html", "en", "home", "/en/", HOME),
    ("accents-clavier-qwerty-mac/index.html", "fr", "guide", "/accents-clavier-qwerty-mac/", QWERTY_GUIDE),
    ("en/french-accents-qwerty-mac/index.html", "en", "guide", "/en/french-accents-qwerty-mac/", QWERTY_GUIDE),
    ("fautes-accent-frequentes/index.html", "fr", "guide", "/fautes-accent-frequentes/", MISTAKES_GUIDE),
]
AI_CRAWLERS = ["GPTBot", "OAI-SearchBot", "ChatGPT-User", "ClaudeBot", "Claude-SearchBot", "Claude-User",
               "PerplexityBot", "Perplexity-User", "Google-Extended", "Applebot-Extended", "Bingbot"]

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

    version = plistlib.loads((ROOT / "Info.plist").read_bytes())["CFBundleShortVersionString"]
    seo_files(version)


def text(fragment):
    """Visible text of an HTML fragment."""
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", fragment)).replace("\u00a0", " ").split())


def meta(page, name):
    m = re.search(rf'<meta (?:name|property)="{name}" content="([^"]*)"', page)
    return html.unescape(m.group(1)).replace("\u00a0", " ") if m else ""


def structured_data(page, lang, kind, path, version):
    app = {
        "@type": "SoftwareApplication",
        "@id": f"{SITE_URL}/#app",
        "name": "Sans-Accent",
        "description": meta(page, "description"),
        "applicationCategory": "UtilitiesApplication",
        "operatingSystem": "macOS 14 or later",
        "softwareVersion": version,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"},
        "isAccessibleForFree": True,
        "downloadUrl": DOWNLOAD_URL,
        "url": f"{SITE_URL}/" if lang == "fr" else f"{SITE_URL}/en/",
        "image": f"{SITE_URL}/assets/icon-512.png",
        "inLanguage": ["fr", "en"],
        "license": "https://www.gnu.org/licenses/gpl-3.0.html",
        "codeRepository": REPO_URL,
        "sameAs": [REPO_URL],
        "author": {"@type": "Person", "name": "Antoine Barthès"},
        "publisher": {"@id": STUDIO["@id"]},
    }
    graph = [app, STUDIO]
    if kind == "home":
        faq = re.search(r'<div class="faq">(.*?)</div>', page, re.S).group(1)
        pairs = re.findall(r"<h3>(.*?)</h3>\s*<p>(.*?)</p>", faq, re.S)
        graph.append({
            "@type": "FAQPage",
            "inLanguage": lang,
            "url": SITE_URL + path,
            "mainEntity": [{"@type": "Question", "name": text(q),
                            "acceptedAnswer": {"@type": "Answer", "text": text(a)}} for q, a in pairs],
        })
    else:
        graph.append({
            "@type": "Article",
            "headline": text(re.search(r"<h1>(.*?)</h1>", page, re.S).group(1)),
            "description": meta(page, "description"),
            "inLanguage": lang,
            "url": SITE_URL + path,
            "image": meta(page, "og:image"),
            "dateModified": datetime.date.today().isoformat(),
            "author": {"@type": "Person", "name": "Antoine Barthès"},
            "publisher": {"@id": STUDIO["@id"]},
            "about": {"@id": app["@id"]},
        })
    return json.dumps({"@context": "https://schema.org", "@graph": graph}, ensure_ascii=False, indent=2)


def seo_files(version):
    today = datetime.date.today().isoformat()
    for file, lang, kind, path, _ in PAGES:
        target = SITE / file
        page = target.read_text(encoding="utf-8")
        data = structured_data(page, lang, kind, path, version)
        page = re.sub(r'(<script type="application/ld\+json" id="structured-data">).*?(</script>)',
                      lambda m: f"{m.group(1)}\n{data}\n  {m.group(2)}", page, flags=re.S)
        target.write_text(page, encoding="utf-8")

    urls = []
    for file, lang, kind, path, versions in PAGES:
        alternates = "".join(f'\n    <xhtml:link rel="alternate" hreflang="{l}" href="{SITE_URL}{p}"/>'
                             for l, p in versions.items()) if len(versions) > 1 else ""
        urls.append(f"""  <url>
    <loc>{SITE_URL}{path}</loc>
    <lastmod>{today}</lastmod>{alternates}
  </url>""")
    (SITE / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
        + "\n".join(urls) + "\n</urlset>\n", encoding="utf-8")

    robots = "User-agent: *\nAllow: /\n\n# AI assistants and search engines are welcome.\n"
    robots += "".join(f"User-agent: {bot}\nAllow: /\n" for bot in AI_CRAWLERS)
    robots += f"\nSitemap: {SITE_URL}/sitemap.xml\n"
    (SITE / "robots.txt").write_text(robots, encoding="utf-8")

    (SITE / "llms.txt").write_text(f"""# Sans-Accent

> Sans-Accent is a free macOS app that adds French accents as you type on a QWERTY keyboard, in every app.
> You type "ecole", it writes "école". Everything runs on the Mac: nothing you type is sent anywhere.
> Made in Toulouse, France, by Girafe Studio. Open source (GPL-3.0).

## Key facts

- Platform: macOS 14 or later. Mac only for now (no Windows, iPhone or Android version).
- Price: free, with optional support on Liberapay.
- How it works: unambiguous words are accented automatically when the word ends (more than 35,000 words),
  and grammar rules settle many others ("je suis allé", "à cause"). When French is ambiguous ("a" or "à",
  "ou" or "où"), a small list appears above the word; tapping the Option key (⌥) shows the other spellings
  of any word.
- Works in every app where you type text: Mail, Messages, Slack, Notion, Word, browsers, Terminal.
  Off by default in code editors; can be turned off per app.
- Privacy: it needs macOS Accessibility access to read and rewrite keystrokes; it sends nothing, stores
  nothing and contains no trackers. Signed by its developer and notarized by Apple.
- Interface in French and English.
- Download: {DOWNLOAD_URL}
- Source code: {REPO_URL}
- Publisher: Girafe Studio, https://www.girafestudio.fr

## Pages

- [Sans-Accent (français)]({SITE_URL}/): home page, live demo, FAQ
- [Sans-Accent (English)]({SITE_URL}/en/): home page, live demo, FAQ
- [Taper les accents français sur un clavier QWERTY (Mac)]({SITE_URL}/accents-clavier-qwerty-mac/): guide to
  the four methods (press and hold, Option shortcuts, text replacements, Sans-Accent)
- [How to type French accents on a Mac (QWERTY keyboard)]({SITE_URL}/en/french-accents-qwerty-mac/): the same
  guide in English
- [Les fautes d'accent les plus fréquentes]({SITE_URL}/fautes-accent-frequentes/): a ou à, ou ou où, la ou là,
  sur ou sûr, du ou dû, des ou dès, participles and capitals, with the rule and a simple trick for each (French)

## En français

Sans-Accent est une app Mac gratuite qui ajoute les accents quand vous écrivez en français sur un clavier
QWERTY, dans toutes vos apps : vous tapez « ecole », elle écrit « école ». Tout se passe sur votre Mac.
Slogan : « Tapez sans accents, écrivez sans fautes. »
""", encoding="utf-8")
    print("structured data, sitemap.xml, robots.txt, llms.txt")


if __name__ == "__main__":
    main()
