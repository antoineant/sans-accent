// Types every sentence of data/testset.tsv through the engine and writes what came out.
// Run from the repo root: swift run -c release AccentBench && python3 test/eval.py data/preds_swift.tsv
import AccentCore
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dictionary = try AccentDictionary(contentsOf: root.appendingPathComponent("accent_dict.tsv"))
let sim = TypingSimulator(engine: Engine(dictionary: dictionary))

let testset = try String(contentsOf: root.appendingPathComponent("data/testset.tsv"), encoding: .utf8)
var out = "id\tpred\n"
for line in testset.split(whereSeparator: \.isNewline).dropFirst() {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    let (id, typed) = (fields[0], fields[3])
    var pred = sim.run(typed + " ")
    pred.removeLast()
    out += "\(id)\t\(pred)\n"
}
let outURL = root.appendingPathComponent("data/preds_swift.tsv")
try out.write(to: outURL, atomically: true, encoding: .utf8)
print("wrote \(outURL.path)")
let words = testset.split(whereSeparator: \.isNewline).dropFirst()
    .map { $0.split(separator: "\t", omittingEmptySubsequences: false)[3] }
    .reduce(0) { $0 + $1.split(whereSeparator: { !$0.isLetter }).count }
print("choice list, ambiguous words: \(sim.offers) times over \(words) words (1 every \(words / max(sim.offers, 1)))")

// Same run with the list after every word that has an accented spelling.
let every = TypingSimulator(engine: Engine(dictionary: dictionary))
every.engine.offerChoicesForEveryWord = true
for line in testset.split(whereSeparator: \.isNewline).dropFirst() {
    _ = every.run(String(line.split(separator: "\t", omittingEmptySubsequences: false)[3]) + " ")
}
print("choice list, every word:      \(every.offers) times over \(words) words (1 every \(String(format: "%.1f", Double(words) / Double(max(every.offers, 1)))))")
