import Foundation

/// "Côté" -> "cote", "cœur" -> "coeur": the dictionary key of a word.
public func accentKey(_ word: String) -> String {
    word.lowercased()
        .replacingOccurrences(of: "œ", with: "oe")
        .replacingOccurrences(of: "æ", with: "ae")
        .folding(options: .diacriticInsensitive, locale: nil)
}

func hasAccent(_ word: String) -> Bool {
    word.unicodeScalars.contains { !$0.isASCII }
}

/// Carry the typed word's capitalisation over to the replacement: "Ecole" -> "École", "ECOLE" -> "ÉCOLE".
func applyCase(typed: String, to word: String) -> String {
    guard let first = typed.first, first.isUppercase else { return word }
    let letters = typed.filter(\.isLetter)
    if letters.count > 1 && letters.allSatisfy(\.isUppercase) {
        return word.uppercased()
    }
    return word.prefix(1).uppercased() + word.dropFirst()
}

/// For words the dictionary doesn't know, right ⌥ rotates the last letter: "Andre" -> "André".
let letterFamilies: [Character: [Character]] = [
    "a": ["a", "à", "â", "ä"], "e": ["e", "é", "è", "ê", "ë"], "i": ["i", "î", "ï"],
    "o": ["o", "ô", "ö"], "u": ["u", "ù", "û", "ü"], "c": ["c", "ç"], "y": ["y", "ÿ"],
]
