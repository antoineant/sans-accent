import Foundation

/// Erase `delete` characters before the caret, then type `insert`.
public struct Rewrite: Equatable {
    public let delete: Int
    public let insert: String
}

/// A key press, as the keyboard tap sees it.
public enum Key {
    case char(String)  // what the key typed, modifiers applied
    case backspace
    case returnOrTab   // ends the word; right ⌥ can't reach back over it
    case other         // arrows, escape, ⌘/⌃/⌥ shortcuts...: the caret may have moved
}

/// The spellings offered for the word just typed, `selected` being the one showing.
public struct Choices: Equatable {
    public let options: [String]
    public let selected: Int

    public init(options: [String], selected: Int) {
        self.options = options
        self.selected = selected
    }
}

/// Follows the word being typed and decides what to accent.
///
/// * Unambiguous words are accented when they end:  `ecole␣` -> `école␣`
/// * Grammar settles some ambiguous ones: `je suis decide` -> `décidé`, `je decide` -> `décide`
/// * Still ambiguous (`a/à`, `ou/où`...): `offerChoices` tells the app to show the choice list
/// * `cycle()` (right ⌥) rotates the word just typed: `cote` -> `côté` -> `côte` -> `coté` -> `cote`
/// * Unknown words: `cycle()` rotates the last letter: `Andre` -> `André`
public final class Engine {
    public let dictionary: AccentDictionary
    /// Off globally or in the frontmost app: right ⌥ still works.
    public var autoAccentEnabled = true
    /// Set when the word just finished is still ambiguous: the app shows `choices()`.
    public private(set) var offerChoices = false
    /// Offer the choices after every word that has an accented spelling, not just ambiguous ones.
    public var offerChoicesForEveryWord = false

    /// How many characters after a word right ⌥ can still reach back over (", " is 2).
    static let maxTrailing = 3

    /// The previous word settles an ambiguous one: "grâce a" -> "grâce à".
    static let after: [String: [String: String]] = [
        "grace": ["a": "à"], "quant": ["a": "à"], "face": ["a": "à"], "jusqu": ["a": "à"],
        "est": ["a": "à"], "pret": ["a": "à"], "prete": ["a": "à"], "prets": ["a": "à"], "pretes": ["a": "à"],
        "d": ["ou": "où"],
    ]
    /// "a cause" -> "à cause": after these, an uncertain "a" is the preposition (and the word is fixed).
    static let aLocutions: [String: String] = [
        "cause": "cause", "partir": "partir", "travers": "travers", "propos": "propos", "peine": "peine",
        "cote": "côté", "nouveau": "nouveau", "condition": "condition", "droite": "droite", "gauche": "gauche",
        "demain": "demain", "bientot": "bientôt", "force": "force", "mesure": "mesure", "vrai": "vrai",
    ]
    /// Forms of être (as shown on screen, accents included).
    static let etre = words("""
        suis es est sommes êtes sont étais était étions étiez étaient être été serai sera serais serait
        """)
    /// After these, a word that can end in -e or -é is the past participle: "il a mange" -> "mangé".
    static let auxiliaries = etre.union(words("""
        a ai as avons avez ont eu avais avait avions aviez avaient aurai auras aura aurons aurez auront
        aurais aurait avoir déjà jamais bien
        """))
    /// After être, these always take the accent: "je suis sure" -> "sûre".
    static let afterEtre = ["sure": "sûre", "sures": "sûres", "surs": "sûrs"]
    /// After these, it's the present tense: "je decide" -> "décide".
    static let subjects = words("je j tu il elle on ils elles ne me te se")
    /// After these, "a" is the verb avoir: "il a", "qu'on a", "n'a".
    static let verbSubjects = words("il elle on qui qu y n m t l ça cela")
    /// Only these keep two words together ("jusqu'a", "grâce a"); "." or "," break the pair.
    static let joiners: Set<String> = [" ", "'", "’", "-"]

    /// Words that tell which language the text is in. Words that are both English and French
    /// ("grace", "present") are only auto-accented while the text is French.
    static let englishMarkers = words("""
        the and is are was were you your of to it that this with for have has had what which would
        will be been not do does did they we he she my our their there can could should
        """)
    static let frenchMarkers = words("""
        le la les de des du et est un une je tu il elle nous vous ils elles que qui pour dans avec
        pas ce cette ces mais au aux en ne se son sa ses mon ma mes on sont suis
        """)

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    private var buffer = ""                              // word being typed
    private var keepAsIs: String?                         // chosen via right ⌥ / backspaced into: don't re-accent
    /// A finished word as it shows, what was typed after it, and whether its spelling is a sure thing.
    private struct Word {
        var shown: String
        var trailing: String
        var sure: Bool
    }
    private var last: Word?      // word just finished, while nothing but spaces/punctuation follows it
    private var previous: Word?  // word before the one being typed, if only joiners separate them
    private var english = false                           // the last language marker seen was English

    public init(dictionary: AccentDictionary) {
        self.dictionary = dictionary
    }

    /// The caret may have moved (click, arrows, app switch): forget the current word.
    public func reset() {
        buffer = ""
        keepAsIs = nil
        last = nil
        previous = nil
        offerChoices = false
    }

    /// New context (app switch): assume French again.
    public func resetLanguage() {
        english = false
    }

    /// Feed a key press. A non-nil result must be applied *before* the key itself reaches the app.
    public func handle(_ key: Key) -> Rewrite? {
        offerChoices = false
        switch key {
        case .backspace:
            backspace()
            return nil
        case .returnOrTab:
            return finishWord(boundary: nil)
        case .other:
            reset()
            return nil
        case .char(let c):
            guard c.count == 1, let ch = c.first, !ch.isNumber else {
                reset()  // digits: likely picking from the long-press accent menu
                return nil
            }
            if ch.isLetter {
                if buffer.isEmpty {
                    previous = last.flatMap { $0.trailing.allSatisfy { Self.joiners.contains(String($0)) } ? $0 : nil }
                }
                buffer.append(ch)
                last = nil
                return nil
            }
            return finishWord(boundary: c)
        }
    }

    // MARK: - Choosing a spelling

    /// The spellings of the word being typed, or of the one just finished.
    public func choices() -> Choices? {
        guard let (target, _) = currentTarget() else { return nil }
        var options = variants(of: target)
        if !options.contains(target) { options.insert(target, at: 0) }
        guard options.count > 1 else { return nil }
        return Choices(options: options, selected: options.firstIndex(of: target)!)
    }

    /// Show `replacement` instead of the word being typed / just finished.
    public func replace(with replacement: String) -> Rewrite? {
        guard let (target, trailing) = currentTarget(), replacement != target else { return nil }
        if !buffer.isEmpty {
            buffer = replacement
            keepAsIs = replacement
        } else {
            last?.shown = replacement
            last?.sure = true  // the user picked it
        }
        return Rewrite(delete: target.count + trailing.count, insert: replacement + trailing)
    }

    /// Right ⌥: next spelling of the word being typed, or of the one just finished.
    public func cycle() -> Rewrite? {
        guard let choices = choices() else { return nil }
        return replace(with: choices.options[(choices.selected + 1) % choices.options.count])
    }

    private func currentTarget() -> (word: String, trailing: String)? {
        if !buffer.isEmpty { return (buffer, "") }
        if let last { return (last.shown, last.trailing) }
        return nil
    }

    /// Dictionary spellings, most frequent first; for unknown words, the last letter's accents.
    func variants(of word: String) -> [String] {
        if let list = dictionary.cycle[accentKey(word)] {
            return list.map { applyCase(typed: word, to: $0) }
        }
        guard let lastChar = word.last,
              let base = accentKey(String(lastChar)).first,
              let family = letterFamilies[base] else { return [] }
        return family.map { word.dropLast() + (lastChar.isUppercase ? String($0).uppercased() : String($0)) }
    }

    // MARK: - Word logic

    /// What to show for a finished word, and whether that's a sure thing.
    func decide(_ word: String) -> (accented: String?, sure: Bool) {
        guard autoAccentEnabled, !hasAccent(word), word != keepAsIs else { return (nil, true) }
        let key = accentKey(word)
        let ambiguous = dictionary.ambiguous.contains(key)
        let cased = { (w: String) in applyCase(typed: word, to: w) }

        if let previous {
            // As shown: "à" (picked from the list) is not the verb, "a" is ("Tom a trouvé").
            // "a cause", "a cote"... were already caught by aLocutions.
            let before = previous.shown.lowercased()
            if let fixed = Self.after[accentKey(before)]?[key] {
                return (cased(fixed), true)
            }
            if Self.etre.contains(before) {
                if let fixed = Self.afterEtre[key] { return (cased(fixed), true) }
                if key == "sur" { return (nil, false) }  // "je suis sûr" or "il est sur la table"?
            }
            if Self.auxiliaries.contains(before) {
                if key == "du" { return (nil, false) }  // "il a dû" or "il a du travail"?
                if let participle = dictionary.participles[key] { return (cased(participle), true) }
            }
            if Self.subjects.contains(before), dictionary.participles[key] != nil {
                let present = dictionary.auto[key] ?? dictionary.autoFrench[key]  // French subject: French text
                return (present.map(cased), true)
            }
            if key == "a", Self.verbSubjects.contains(before) {
                return (nil, true)
            }
        }

        let accented = dictionary.auto[key] ?? (english ? nil : dictionary.autoFrench[key])
        return (accented.map(cased), !ambiguous || english)
    }

    private func finishWord(boundary: String?) -> Rewrite? {
        let word = buffer
        buffer = ""

        guard !word.isEmpty else {
            if let boundary, let l = last, l.trailing.count < Self.maxTrailing {
                last?.trailing += boundary
            } else {
                last = nil
            }
            return nil
        }

        // "a cause" -> "à cause": fix the previous word too.
        if autoAccentEnabled, word != keepAsIs, let p = previous, p.shown.lowercased() == "a", !p.sure,
           let fixed = Self.aLocutions[accentKey(word)] {
            keepAsIs = nil
            let shown = applyCase(typed: word, to: fixed)
            last = boundary.map { Word(shown: shown, trailing: $0, sure: true) }
            noteLanguage(shown)
            offerChoices = offerChoicesForEveryWord && last != nil
            return Rewrite(delete: p.shown.count + p.trailing.count + word.count,
                           insert: applyCase(typed: p.shown, to: "à") + p.trailing + shown)
        }

        let (accented, sure) = decide(word)
        keepAsIs = nil
        let shown = accented ?? word
        last = boundary.map { Word(shown: shown, trailing: $0, sure: sure) }
        noteLanguage(shown)
        let hasVariants = dictionary.cycle[accentKey(word)] != nil
        offerChoices = last != nil && autoAccentEnabled && (!sure || (offerChoicesForEveryWord && hasVariants))

        return accented.map { Rewrite(delete: word.count, insert: $0) }
    }

    private func backspace() {
        if !buffer.isEmpty {
            buffer.removeLast()
        } else if let l = last, !l.trailing.isEmpty {
            last?.trailing.removeLast()
            if last?.trailing.isEmpty == true {
                // Back inside the word: leave it as it is unless it gets edited.
                buffer = l.shown
                keepAsIs = l.shown
                last = nil
                previous = nil
            }
        } else {
            reset()
        }
    }

    private func noteLanguage(_ word: String) {
        if hasAccent(word) {
            english = false
            return
        }
        let key = accentKey(word)
        if Self.englishMarkers.contains(key) {
            english = true
        } else if Self.frenchMarkers.contains(key) {
            english = false
        }
    }
}
