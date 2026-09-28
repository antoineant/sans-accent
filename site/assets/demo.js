// Sans-Accent's rules, in the browser: type without accents in #demo and they appear as words end.
// A small port of Sources/AccentCore/Engine.swift, using the most common words (demo-dict.json).
(() => {
  const script = document.currentScript;
  const field = document.getElementById("demo-input");
  const mirror = document.getElementById("demo-mirror");
  const choiceRow = document.getElementById("demo-choices");
  const choiceButtons = document.getElementById("demo-choice-buttons");
  if (!field) return;

  const LETTERS = "A-Za-zÀ-ÖØ-öø-ÿŒœÆæ";
  const LAST_WORD = new RegExp(`[${LETTERS}]+$`);
  const PREVIOUS = new RegExp(`([${LETTERS}]+)([ '’-]+)$`);
  const words = (s) => new Set(s.split(/\s+/));

  const AFTER = { grace: { a: "à" }, quant: { a: "à" }, face: { a: "à" }, jusqu: { a: "à" }, est: { a: "à" },
    pret: { a: "à" }, prete: { a: "à" }, d: { ou: "où" } };
  const A_LOCUTIONS = { cause: "cause", partir: "partir", travers: "travers", propos: "propos", peine: "peine",
    cote: "côté", nouveau: "nouveau", condition: "condition", droite: "droite", gauche: "gauche", demain: "demain" };
  const ETRE = words("suis es est sommes êtes sont étais était étions étiez étaient être été sera serait");
  const AUXILIARIES = new Set([...ETRE, ...words("a ai as avons avez ont eu avais avait avions aviez avaient aura aurait avoir déjà jamais bien")]);
  const AFTER_ETRE = { sure: "sûre", sures: "sûres", surs: "sûrs" };
  const SUBJECTS = words("je j tu il elle on ils elles ne me te se");
  const VERB_SUBJECTS = words("il elle on qui qu y n m t l ça cela");

  let dict = { auto: {}, participles: {}, choices: {} };
  let pending = null;  // { start, shown, options }: the word the choice row is about

  const key = (w) => w.toLowerCase().replace(/œ/g, "oe").replace(/æ/g, "ae")
    .normalize("NFD").replace(/[̀-ͯ]/g, "");
  const hasAccent = (w) => /[^\x00-\x7f]/.test(w);
  const applyCase = (typed, w) => {
    if (typed[0] !== typed[0].toUpperCase() || typed[0] === typed[0].toLowerCase()) return w;
    if (typed.length > 1 && typed === typed.toUpperCase()) return w.toUpperCase();
    return w[0].toUpperCase() + w.slice(1);
  };

  /** What to show for a finished word: { word, ambiguous }. */
  function decide(word, before) {
    if (hasAccent(word)) return { word, ambiguous: false };
    const k = key(word);
    const cased = (w) => applyCase(word, w);
    if (before) {
      const b = before.toLowerCase();
      const fixed = AFTER[key(b)]?.[k];
      if (fixed) return { word: cased(fixed), ambiguous: false };
      if (ETRE.has(b)) {
        if (AFTER_ETRE[k]) return { word: cased(AFTER_ETRE[k]), ambiguous: false };
        if (k === "sur") return { word, ambiguous: true };
      }
      if (AUXILIARIES.has(b)) {
        if (k === "du") return { word, ambiguous: true };
        if (dict.participles[k]) return { word: cased(dict.participles[k]), ambiguous: false };
      }
      if (SUBJECTS.has(b) && dict.participles[k]) return { word: dict.auto[k] ? cased(dict.auto[k]) : word, ambiguous: false };
      if (k === "a" && VERB_SUBJECTS.has(b)) return { word, ambiguous: false };
    }
    return { word: dict.auto[k] ? cased(dict.auto[k]) : word, ambiguous: k in dict.choices };
  }

  /** A word just ended at the caret (the boundary character is already typed). */
  function finishWord() {
    const caret = field.selectionStart;
    const head = field.value.slice(0, caret - 1);
    const match = LAST_WORD.exec(head);
    if (!match) return;
    const typed = match[0];
    const start = caret - 1 - typed.length;
    const prev = PREVIOUS.exec(field.value.slice(0, start));

    // "a cause" -> "à cause": the previous word changes too.
    const locution = A_LOCUTIONS[key(typed)];
    if (prev && prev[1].toLowerCase() === "a" && !hasAccent(typed) && locution) {
      const prevStart = start - prev[0].length;
      replace(prevStart, prev[0].length + typed.length, applyCase(prev[1], "à") + prev[2] + applyCase(typed, locution));
      hideChoices();
      return;
    }

    const { word, ambiguous } = decide(typed, prev ? prev[1] : null);
    if (word !== typed) replace(start, typed.length, word);
    if (ambiguous) showChoices(start, word); else hideChoices();
  }

  function replace(start, length, text) {
    field.setRangeText(text, start, start + length, "preserve");
    render(start, start + text.length);
  }

  // The mirror shows the same text as the field, with accents in red; fresh ones pop.
  function render(freshStart = -1, freshEnd = -1) {
    const text = field.value;
    let html = "";
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      const safe = c === "<" ? "&lt;" : c === "&" ? "&amp;" : c === ">" ? "&gt;" : c;
      if (hasAccent(c) && /\p{L}/u.test(c)) {
        html += `<span class="accent${i >= freshStart && i < freshEnd ? " fresh" : ""}">${safe}</span>`;
      } else {
        html += safe;
      }
    }
    mirror.innerHTML = html + "​";
    mirror.scrollTop = field.scrollTop;
  }

  function showChoices(start, shown) {
    const options = dict.choices[key(shown)].map((o) => applyCase(shown, o));
    pending = { start, shown, options };
    choiceButtons.innerHTML = "";
    for (const option of options) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = option;
      button.setAttribute("aria-pressed", String(option === shown));
      button.addEventListener("click", () => choose(option));
      choiceButtons.append(button);
    }
    choiceRow.hidden = false;
  }

  function hideChoices() {
    pending = null;
    choiceRow.hidden = true;
  }

  function choose(option) {
    if (!pending) return;
    const { start, shown } = pending;
    if (field.value.slice(start, start + shown.length) !== shown) return hideChoices();
    const caret = field.selectionStart;
    field.setRangeText(option, start, start + shown.length, "preserve");
    field.setSelectionRange(caret + option.length - shown.length, caret + option.length - shown.length);
    render(start, start + option.length);
    pending.shown = option;
    for (const b of choiceButtons.children) b.setAttribute("aria-pressed", String(b.textContent === option));
  }

  field.addEventListener("input", (event) => {
    stopAutoplay();
    const boundary = event.inputType === "insertLineBreak" ||
      (event.inputType === "insertText" && event.data && !new RegExp(`[${LETTERS}0-9]`).test(event.data));
    if (boundary) finishWord();
    render();
  });
  field.addEventListener("scroll", () => { mirror.scrollTop = field.scrollTop; });

  // One demonstration on load: types a sentence, picks "à" from the list, then hands over.
  let autoplay = null;
  const sentence = "je suis alle a l'ecole en velo, c'est deja ca. ";
  function stopAutoplay() {
    if (!autoplay) return;
    clearTimeout(autoplay.timer);
    autoplay = null;
    field.classList.remove("playing");
  }
  field.addEventListener("focus", () => {
    if (autoplay || field.dataset.demo === "done") {
      stopAutoplay();
      field.value = "";
      field.dataset.demo = "";
      hideChoices();
      render();
    }
  });

  function typeNext(i) {
    if (!autoplay) return;
    if (i >= sentence.length) {
      stopAutoplay();
      field.dataset.demo = "done";
      return;
    }
    const c = sentence[i];
    field.value += c;
    field.setSelectionRange(field.value.length, field.value.length);
    if (!new RegExp(`[${LETTERS}]`).test(c)) finishWord();
    render(field.value.length - 1, field.value.length);
    // Pause on the choice, then pick "à" like a person would.
    if (pending && pending.shown === "a" && c === " ") {
      autoplay.timer = setTimeout(() => {
        const button = [...choiceButtons.children].find((b) => b.textContent === "à");
        button?.classList.add("pressing");
        autoplay.timer = setTimeout(() => {
          choose("à");
          hideChoices();
          autoplay.timer = setTimeout(() => typeNext(i + 1), 500);
        }, 450);
      }, 900);
      return;
    }
    autoplay.timer = setTimeout(() => typeNext(i + 1), c === " " ? 160 : 70);
  }

  function startAutoplay() {
    field.value = "";
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      field.value = "je suis allé à l'école en vélo, c'est déjà ça. ";
      field.dataset.demo = "done";
      render();
      return;
    }
    autoplay = { timer: null };
    field.classList.add("playing");
    autoplay.timer = setTimeout(() => typeNext(0), 600);
  }

  fetch(new URL("demo-dict.json", script.src))
    .then((r) => r.json())
    .then((data) => {
      dict = data;
      field.disabled = false;
      if (document.activeElement !== field && field.value === "") startAutoplay();
    });
  render();
})();
