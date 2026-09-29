import AccentCore
import AppKit

/// What an extension (such as Sans-Accent Pro) can see of the running app.
public struct ExtensionContext {
    public let engine: Engine
}

/// Adds features to Sans-Accent without changing its code. Today: menu items and a launch hook;
/// more hooks come as features need them.
public protocol SansAccentExtension: AnyObject {
    /// Called once, when the app has finished launching.
    func didLaunch(_ context: ExtensionContext)
    /// Items shown in the menu bar menu, between the settings and the language menu.
    /// Called each time the menu opens, so they can reflect the current state.
    func menuItems() -> [NSMenuItem]
}
