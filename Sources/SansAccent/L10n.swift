import Foundation

/// Localized string from Localization/<lang>.lproj/Localizable.strings (French or English, English by default).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ argument: String) -> String {
    String(format: L(key), argument)
}

/// The interface language: the system's, unless overridden from the Language menu.
enum InterfaceLanguage: String, CaseIterable {
    case system = "", english = "en", french = "fr"

    var title: String {
        switch self {
        case .system: L("language.system")
        case .english: "English"
        case .french: "Français"
        }
    }

    /// Stored as this app's own AppleLanguages, which macOS reads at launch.
    static var current: InterfaceLanguage {
        get {
            let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            let languages = domain?["AppleLanguages"] as? [String]
            return languages?.first.flatMap(InterfaceLanguage.init) ?? .system
        }
        set {
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            }
        }
    }
}
