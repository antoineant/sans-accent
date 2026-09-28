@testable import AccentCore
import Foundation
import XCTest

/// End-to-end: typed input -> what the text field shows. "~" = right ⌥ tap, "\u{8}" = backspace.
final class EngineTests: XCTestCase {
    static let dictionary: AccentDictionary = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("accent_dict.tsv")
        return try! AccentDictionary(contentsOf: url)
    }()

    func testTyping() {
        let sim = TypingSimulator(engine: Engine(dictionary: Self.dictionary))
        let cases: [(String, String)] = [
            ("ecole ", "école "),
            ("Ecole ", "École "),
            ("ECOLE ", "ÉCOLE "),
            ("ca va, tres bien. ", "ça va, très bien. "),
            ("peut-etre ", "peut-être "),
            ("l'ecole ", "l'école "),
            ("coeur ", "cœur "),
            ("il a ", "il a "),
            ("il a~ ", "il à "),  // cycle mid-word
            ("il a ~", "il à "),  // cycle after the space
            ("il a ~~", "il a "),  // and back
            ("cote ~", "côté "),
            ("cote ~~", "côte "),
            ("cote ~~~~", "cote "),
            ("ecole ~", "ecole "),  // right ⌥ undoes an auto-accent
            ("ecole ~~", "école "),
            ("the present ", "the present "),  // English left alone
            ("present ~", "present "),  // undo the French-context accent
            ("Andre~ ", "André "),  // unknown word: last letter
            ("ecole\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}cole ", "cole "),
            ("ecole \u{8} ", "école "),  // backspace into word, not re-accented
            ("ecole \u{8}~ ", "ecole "),
            ("tres, ~", "tres, "),  // reaches back over ", "
            ("ou ~", "où "),
            ("deja\n", "déjà\n"),
            ("premiere fois.", "première fois."),
            ("allees \u{8}\u{8}\u{8}\u{8}ees ", "allées "),  // edited after backspacing in: accented again
            ("allees \u{8}\u{8}s ", "allées "),  // fix the last letter: accent kept
            ("Grace a dieu ", "Grâce à dieu "),
            ("grace a toi", "grâce à toi"),
            ("jusqu'a demain ", "jusqu'à demain "),
            ("c'est a moi ", "c'est à moi "),
            ("d'ou vient ", "d'où vient "),
            ("il a mange ", "il a mangé "),  // after an auxiliary: past participle
            ("je suis decide a ", "je suis décidé a "),
            ("je decide ", "je décide "),  // after a subject: present tense
            ("tu es passe par la ", "tu es passé par la "),
            ("il a envie ", "il a envie "),
            ("je suis decide a ne pas etre aime ", "je suis décidé a ne pas être aimé "),  // aimé: rare, but sure here
            ("il a porte ", "il a porté "),
            ("je porte ", "je porte "),
            ("je suis decide a cause de toi ", "je suis décidé à cause de toi "),  // fixes the "a" too
            ("il a cause ", "il a causé "),  // but "il a" is the verb
            ("A cote ", "À côté "),
            ("je suis sure ", "je suis sûre "),
            ("Marie a memorise ", "Marie a mémorisé "),  // rare verb, still a participle  // envié is too rare to be a candidate
            ("elle a ", "elle a "),
            ("grace. a ", "grâce. a "),  // punctuation breaks the pair
            ("the present ", "the present "),  // English text: left alone
            ("thank you for the grace ", "thank you for the grace "),
            ("je suis present ", "je suis présent "),  // French text: accented
            ("present ", "présent "),  // no context yet: French by default
            ("ecole ~\u{8} ", "ecole "),  // undone on purpose, stays undone
        ]
        for (input, expected) in cases {
            XCTAssertEqual(sim.run(input), expected, "typing \(input.debugDescription)")
        }
    }

    func testChoiceList() {
        let engine = Engine(dictionary: Self.dictionary)
        let sim = TypingSimulator(engine: engine)

        _ = sim.run("je suis decide a ")
        XCTAssertTrue(engine.offerChoices)  // "a" after "décidé": a or à?
        XCTAssertEqual(engine.choices(), Choices(options: ["à", "a"], selected: 1))
        XCTAssertEqual(engine.replace(with: "à"), Rewrite(delete: 2, insert: "à "))
        XCTAssertEqual(engine.choices(), Choices(options: ["à", "a"], selected: 0))

        _ = sim.run("il a ")
        XCTAssertFalse(engine.offerChoices)  // "il a": the verb, no question
        _ = sim.run("ecole ")
        XCTAssertFalse(engine.offerChoices)
        _ = sim.run("Ou ")
        XCTAssertEqual(engine.choices(), Choices(options: ["Où", "Ou"], selected: 1))
        _ = sim.run("il a du ")
        XCTAssertTrue(engine.offerChoices)  // "il a dû" or "il a du travail"?

        // Picked "à" from the list: it's not the verb, so "cause" stays a noun.
        _ = sim.run("decide a ")
        _ = engine.replace(with: "à")
        let rewrites = "cause ".map { engine.handle(.char(String($0))) }
        XCTAssertEqual(rewrites.compactMap { $0 }, [])

        _ = sim.run("the passe ")
        XCTAssertFalse(engine.offerChoices)  // English text: don't pester
    }

    func testChoicesForEveryWord() {
        let engine = Engine(dictionary: Self.dictionary)
        engine.offerChoicesForEveryWord = true
        let sim = TypingSimulator(engine: engine)
        XCTAssertEqual(sim.run("ecole "), "école ")  // still accented, and offered
        XCTAssertTrue(engine.offerChoices)
        _ = sim.run("il a ")
        XCTAssertTrue(engine.offerChoices)
        _ = sim.run("maison ")
        XCTAssertFalse(engine.offerChoices)  // no accented spelling at all
    }

    func testAutoAccentOffStillCycles() {
        let engine = Engine(dictionary: Self.dictionary)
        engine.autoAccentEnabled = false
        let sim = TypingSimulator(engine: engine)
        XCTAssertEqual(sim.run("ecole "), "ecole ")
        XCTAssertEqual(sim.run("ecole ~"), "école ")
    }
}
