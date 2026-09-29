import AccentCore
import AppKit
import ServiceManagement

/// Menu bar item (the "Sa" logo), settings, per-app exclusions and the Accessibility permission.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let extensions: [SansAccentExtension]
    private var statusItem: NSStatusItem!
    private var engine: Engine!
    private var tap: KeyboardTap!
    private var permissionTimer: Timer?
    private let permission = PermissionStatus()
    private lazy var welcome = WelcomeWindow(status: permission) { [weak self] in self?.requestAccess() }

    /// Auto-accent is off in these apps (right ⌥ still works). Add more from the menu.
    private static let defaultExcluded: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "dev.zed.Zed",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.1password.1password",
        "com.bitwarden.desktop",
    ]

    private let defaults = UserDefaults.standard

    /// `extensions` add features (menu items, hooks) on top of the free app.
    public init(extensions: [SansAccentExtension] = []) {
        self.extensions = extensions
        super.init()
    }
    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled"); refresh() }
    }
    /// When the choice list opens by itself (⌥ always opens it).
    private enum ChoiceMode: String, CaseIterable {
        case never, ambiguous, every

        var title: String { L("choices.\(rawValue)") }
    }
    private var choiceMode: ChoiceMode {
        get { defaults.string(forKey: "choiceMode").flatMap(ChoiceMode.init) ?? .ambiguous }
        set { defaults.set(newValue.rawValue, forKey: "choiceMode"); refresh() }
    }
    private var userExcluded: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedApps") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "excludedApps"); refresh() }
    }

    private var frontmostApp: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }

    private func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.defaultExcluded.contains(bundleID) || userExcluded.contains(bundleID)
    }

    // MARK: - Launch

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let url = Bundle.main.url(forResource: "accent_dict", withExtension: "tsv"),
              let dictionary = try? AccentDictionary(contentsOf: url) else {
            fatalError("accent_dict.tsv missing from the app bundle")
        }
        engine = Engine(dictionary: dictionary)
        tap = KeyboardTap(engine: engine)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        startTap()
        refresh()
        extensions.forEach { $0.didLaunch(ExtensionContext(engine: engine)) }
        // First launch, or still no permission: explain before macOS asks.
        if !tap.isRunning || !defaults.bool(forKey: "welcomeShown") {
            defaults.set(true, forKey: "welcomeShown")
            welcome.show()
        }
    }

    @objc private func appActivated() {
        tap.closeChoices()
        if let app = frontmostApp { ChoicePanel.enableAccessibility(for: app) }
        engine.reset()
        engine.resetLanguage()
        refresh()
    }

    /// Without Accessibility access the tap can't be created: retry until it's granted.
    private func startTap() {
        if tap.start() {
            permissionTimer?.invalidate()
            permissionTimer = nil
            permission.granted = true
            refresh()
            return
        }
        if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.startTap()
            }
        }
        refresh()
    }

    /// Lists the app in System Settings → Accessibility (with macOS's own prompt) and opens that pane.
    private func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    private func refresh() {
        guard let button = statusItem?.button else { return }
        let on = tap.isRunning && enabled && !isExcluded(frontmostApp?.bundleIdentifier)
        button.image = MenuBarIcon.image
        button.imagePosition = .imageLeading
        button.title = tap.isRunning ? "" : "⚠︎"
        button.appearsDisabled = tap.isRunning && !on  // dimmed: off in this app
        button.toolTip = tap.isRunning ? "Sans-Accent" : L("tooltip.needsAccess")
        engine.autoAccentEnabled = on
        tap.showChoicesAutomatically = on && choiceMode != .never
        engine.offerChoicesForEveryWord = choiceMode == .every
    }

    // MARK: - Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !tap.isRunning {
            menu.addItem(item(L("menu.grantAccess"), #selector(showWelcome)))
            menu.addItem(.separator())
        }

        menu.addItem(item(L("menu.autoAccent"), #selector(toggleEnabled), checked: enabled))
        let choices = NSMenu()
        for mode in ChoiceMode.allCases {
            let entry = item(mode.title, #selector(setChoiceMode(_:)), checked: mode == choiceMode)
            entry.representedObject = mode.rawValue
            choices.addItem(entry)
        }
        menu.addItem(submenu(L("menu.showChoices"), choices))

        if let app = frontmostApp, let id = app.bundleIdentifier {
            let name = app.localizedName ?? id
            if Self.defaultExcluded.contains(id) {
                let entry = item(L("menu.alwaysOffIn", name), nil)
                entry.isEnabled = false
                menu.addItem(entry)
            } else {
                let entry = item(L("menu.offIn", name), #selector(toggleExcluded(_:)), checked: userExcluded.contains(id))
                entry.representedObject = id
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let hint = item(L("menu.hint"), nil)
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let extensionItems = extensions.flatMap { $0.menuItems() }
        if !extensionItems.isEmpty {
            extensionItems.forEach(menu.addItem)
            menu.addItem(.separator())
        }

        let languages = NSMenu()
        for language in InterfaceLanguage.allCases {
            let entry = item(language.title, #selector(setLanguage(_:)), checked: language == .current)
            entry.representedObject = language.rawValue
            languages.addItem(entry)
        }
        menu.addItem(submenu(L("menu.language"), languages))
        menu.addItem(item(L("menu.launchAtLogin"), #selector(toggleLaunchAtLogin),
                          checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(item(L("menu.welcome"), #selector(showWelcome)))
        menu.addItem(item(L("menu.support"), #selector(openSupport)))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.quit"), #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func item(_ title: String, _ action: Selector?, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        item.state = checked ? .on : .off
        return item
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
    }

    @objc private func setChoiceMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = ChoiceMode(rawValue: raw) {
            choiceMode = mode
        }
    }

    @objc private func toggleExcluded(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var excluded = userExcluded
        if excluded.contains(id) { excluded.remove(id) } else { excluded.insert(id) }
        userExcluded = excluded
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// The site's support section, in the interface language (the URL is localized).
    @objc private func openSupport() {
        if let url = URL(string: L("support.url")) { NSWorkspace.shared.open(url) }
    }

    @objc private func showWelcome() {
        welcome.show()
    }

    /// macOS picks the language at launch, so relaunch in the new one.
    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = InterfaceLanguage(rawValue: raw),
              language != .current else { return }
        InterfaceLanguage.current = language
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
