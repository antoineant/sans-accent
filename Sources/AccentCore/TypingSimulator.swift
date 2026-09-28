/// A text field driven through the engine, for tests and the benchmark.
/// In `input`, "~" is a right ⌥ tap, "\u{8}" a backspace, "\n" return.
public final class TypingSimulator {
    public let engine: Engine
    /// How many times the engine asked to show the choice list, over all runs.
    public private(set) var offers = 0

    public init(engine: Engine) {
        self.engine = engine
    }

    /// Type `input` into an empty field, from a fresh state, and return what the field shows.
    public func run(_ input: String) -> String {
        engine.reset()
        engine.resetLanguage()
        var field = ""

        func apply(_ rewrite: Rewrite?) {
            guard let rewrite else { return }
            field.removeLast(min(rewrite.delete, field.count))
            field += rewrite.insert
        }

        for ch in input {
            switch ch {
            case "~":
                apply(engine.cycle())
            case "\u{8}":
                apply(engine.handle(.backspace))
                if !field.isEmpty { field.removeLast() }
            case "\n":
                apply(engine.handle(.returnOrTab))
                field.append(ch)
            default:
                apply(engine.handle(.char(String(ch))))
                field.append(ch)
                if engine.offerChoices { offers += 1 }
            }
        }
        return field
    }
}
