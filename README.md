# Sans-Accent

*Tapez sans accents, écrivez sans fautes.*

Sans-Accent is a small Mac app for people who write French on a QWERTY keyboard. Type without
accents and it adds them as you write, in every app: Mail, Slack, your browser, the terminal.

- `ecole` becomes `école` as soon as you finish the word.
- Grammar settles many cases: `je suis decide` → `décidé`, `je decide` → `décide`, `a cause` → `à cause`.
- When French is ambiguous (`a`/`à`, `ou`/`où`), a small list appears above the word: choose with
  **↑ ↓** and confirm with **⏎**, or just keep typing.
- Tap **⌥** after any word to see its other spellings.

Everything happens on your Mac: nothing you type is sent anywhere, and the app contains no trackers.
It needs macOS Accessibility access to read and rewrite what you type.

**[Download for macOS 14 or later](https://github.com/antoineant/sans-accent/releases/latest/download/Sans-Accent.dmg)**
(free, signed and notarized) · [Website](https://sans-accent.com/)

## Support

Sans-Accent is free and will stay free. If it saves you time, you can support its development on
[Liberapay](https://liberapay.com/antoineant/donate) or [GitHub Sponsors](https://github.com/sponsors/antoineant).

## Build from source

Requires macOS 14 and Xcode (Swift 5.9 or later).

```sh
./build.sh      # builds, signs and installs /Applications/Sans-Accent.app
swift test      # end-to-end typing tests
```

Without the maintainer's Developer ID certificate, `build.sh` signs ad hoc: macOS will ask for
Accessibility access again after each build.

| Path | Role |
|---|---|
| `Sources/AccentCore` | word logic (`Engine`), dictionary loader, typing simulator |
| `Sources/SansAccent` | the app: keyboard tap, choice list, menu bar, welcome window |
| `Sources/AccentBench` | types the benchmark sentences through the engine |
| `Tests/AccentCoreTests` | end-to-end typing tests |
| `Localization/{en,fr}.lproj` | interface strings (French and English) |
| `build_dict.py` → `accent_dict.tsv` | the dictionary, built from Lexique 3.83 and English word frequencies |
| `test/build_testset.py` → `data/testset.tsv` | 208 benchmark sentences typed without accents |
| `test/eval.py` | scores a benchmark run |
| `assets/` | the icon, drawn by `make_icon.swift` (`build_icon.sh` → `AppIcon.icns`) |
| `site/` | the website (French at `/`, English at `/en/`) with a live demo |

### The dictionary and the benchmark

`build_dict.py` and `test/build_testset.py` need source data that isn't in the repository. Download it into `data/`:

```sh
curl -o data/Lexique383.tsv http://www.lexique.org/databases/Lexique383/Lexique383.tsv
curl -o data/en_50k.txt https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt
curl -L https://downloads.tatoeba.org/exports/per_language/fra/fra_sentences.tsv.bz2 | bunzip2 > data/fra_sentences.tsv
```

Then `python3 build_dict.py && ./build.sh`. To measure a change:
`swift run -c release AccentBench && python3 test/eval.py data/preds_swift.tsv --errors`.

### Website

`python3 site/build_site.py` refreshes the demo dictionary and icons.
Preview with `python3 -m http.server -d site 8765`, then open http://127.0.0.1:8765/.
Every push to `main` that touches `site/` publishes it to https://sans-accent.com (GitHub Pages, see
`.github/workflows/pages.yml`; the domain's DNS is at OVH).

### Release

`./package.sh` signs with the hardened runtime, notarizes the app and the disk image with Apple, and
writes `dist/Sans-Accent-<version>.dmg` plus `dist/Sans-Accent.dmg`. Publish with
`gh release create v<version> dist/Sans-Accent.dmg`. Bump `CFBundleShortVersionString` in `Info.plist` first.

## Credits

- The dictionary is derived from [Lexique 3.83](http://www.lexique.org) (New, Pallier et al.) and the English
  lists of [FrequencyWords](https://github.com/hermitdave/FrequencyWords), both under
  [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). `accent_dict.tsv` and
  `site/assets/demo-dict.json` are distributed under the same license.
- Benchmark sentences come from [Tatoeba](https://tatoeba.org) under
  [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/).

The code is under the [GNU GPL v3](LICENSE); see [NOTICE](NOTICE) for the data licenses and
[CONTRIBUTING](CONTRIBUTING.md) before sending a pull request. Made in Toulouse by Antoine Barthès, [Girafe Studio](https://www.girafestudio.fr).
