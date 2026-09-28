import AccentCore
import CoreGraphics
import Foundation

/// Watches every key press system-wide, feeds the engine, and types its rewrites.
///
/// A rewrite is N backspaces followed by the new text as Unicode key events, which works in
/// any app (native, Chrome, Electron, terminals) without relying on accessibility APIs.
///
/// Tapping ⌥ (either one) opens the choice list on the word just typed; while it's up, ⌥ or ↑/↓
/// change the word in place, ⏎/⇥ confirm, esc puts it back. Any other key closes the list and
/// keeps what's showing.
final class KeyboardTap {
    let engine: Engine
    /// Open the choice list by itself after an ambiguous word (⌥ always opens it).
    var showChoicesAutomatically = true
    private var tap: CFMachPort?
    private var cycleDownAt: TimeInterval?

    private let panel = ChoicePanel()
    /// `engaged`: opened with ⌥ or moved through, so ⏎ confirms instead of reaching the app.
    private var picking: (choices: Choices, original: String, engaged: Bool)?
    private var pendingShow = 0  // bumped by every key: a list scheduled before it is stale

    /// Tags our own synthetic events so the tap lets them through untouched.
    private static let mark: Int64 = 0x4143_4345
    private static let optionKeys: Set<Int64> = [58, 61]  // left, right
    private static let cycleMaxHold: TimeInterval = 0.35  // a longer press is a normal ⌥ use

    private enum KeyCode {
        static let delete: Int64 = 51
        static let returnKeys: Set<Int64> = [36, 76, 48]  // return, enter, tab
        // escape, forward delete, home, end, page up/down, arrows: the caret moves
        static let navigation: Set<Int64> = [53, 117, 115, 119, 116, 121, 123, 124, 125, 126]
        static let escape: Int64 = 53
        static let up: Int64 = 126
        static let down: Int64 = 125
    }

    init(engine: Engine) {
        self.engine = engine
    }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Fails until the app has Accessibility access.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                let me = Unmanaged<KeyboardTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Events

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // macOS disables a tap it finds too slow; turn it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.mark { return pass }

        switch type {
        case .keyDown:
            cycleDownAt = nil
            pendingShow += 1
            if picking != nil, pickerKey(event, proxy: proxy) { return nil }

            let rewrite = engine.handle(key(for: event))
            if engine.offerChoices && showChoicesAutomatically { scheduleChoices() }
            guard let rewrite else { return pass }
            // Rewrite first, then let the key that ended the word through.
            for ev in Self.events(for: rewrite) { ev.tapPostEvent(proxy) }
            if let original = event.copy() {
                original.setIntegerValueField(.eventSourceUserData, value: Self.mark)
                original.tapPostEvent(proxy)
            }
            return nil

        case .flagsChanged:
            guard Self.optionKeys.contains(event.getIntegerValueField(.keyboardEventKeycode)) else {
                cycleDownAt = nil
                return pass
            }
            let now = ProcessInfo.processInfo.systemUptime
            if event.flags.contains(.maskAlternate) {
                cycleDownAt = now
            } else if let down = cycleDownAt, now - down < Self.cycleMaxHold {
                cycleDownAt = nil
                if picking == nil {
                    if let choices = engine.choices() { openChoices(choices, engaged: true) }
                } else if let rewrite = move(by: 1) {
                    // After the ⌥ release has gone through, so apps don't see ⌥ + char.
                    DispatchQueue.main.async {
                        for ev in Self.events(for: rewrite) { ev.post(tap: .cgSessionEventTap) }
                    }
                }
            }
            return pass

        default:  // a click may have moved the caret
            cycleDownAt = nil
            closeChoices()
            engine.reset()
            return pass
        }
    }

    // MARK: - Choice list

    /// A key pressed while the list is up. Returns true if the list used it up.
    private func pickerKey(_ event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        guard let current = picking else { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let plain = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        var rewrite: Rewrite?
        switch code {
        case KeyCode.up where plain, KeyCode.down where plain:
            rewrite = move(by: code == KeyCode.down ? 1 : -1)
        case KeyCode.escape:
            rewrite = engine.replace(with: current.original)
            closeChoices()
        case _ where KeyCode.returnKeys.contains(code) && current.engaged:
            closeChoices()  // confirms the choice; the key itself doesn't reach the app
        default:
            closeChoices()  // anything else: keep what's showing, and let the key through
            return false
        }
        if let rewrite { for ev in Self.events(for: rewrite) { ev.tapPostEvent(proxy) } }
        return true
    }

    /// Show the list shortly after the word ends, unless typing has moved on by then.
    private func scheduleChoices() {
        let token = pendingShow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, token == self.pendingShow, self.picking == nil,
                  let choices = self.engine.choices() else { return }
            self.openChoices(choices, engaged: false)
        }
    }

    private func openChoices(_ choices: Choices, engaged: Bool) {
        picking = (choices, choices.options[choices.selected], engaged)
        panel.show(choices.options, selected: choices.selected)
    }

    private func move(by step: Int) -> Rewrite? {
        guard let current = picking else { return nil }
        let options = current.choices.options
        let index = (current.choices.selected + step + options.count) % options.count
        picking = (Choices(options: options, selected: index), current.original, true)
        panel.select(index)
        return engine.replace(with: options[index])
    }

    func closeChoices() {
        picking = nil
        panel.hide()
    }

    private func key(for event: CGEvent) -> Key {
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return .other
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == KeyCode.delete { return .backspace }
        if KeyCode.returnKeys.contains(code) { return .returnOrTab }
        if KeyCode.navigation.contains(code) { return .other }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let text = String(utf16CodeUnits: chars, count: length)
        // Function keys and dead keys type nothing printable (control or private-use characters).
        guard let scalar = text.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !(0xE000...0xF8FF).contains(scalar.value) else {
            return .other
        }
        return .char(text)
    }

    // MARK: - Synthetic typing

    private static let source = CGEventSource(stateID: .privateState)

    private static func events(for rewrite: Rewrite) -> [CGEvent] {
        var events: [CGEvent] = []
        func add(_ key: CGKeyCode, _ text: String? = nil) {
            for down in [true, false] {
                guard let ev = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
                ev.flags = []
                if let text {
                    let utf16 = Array(text.utf16)
                    ev.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                }
                ev.setIntegerValueField(.eventSourceUserData, value: mark)
                events.append(ev)
            }
        }
        for _ in 0..<rewrite.delete { add(CGKeyCode(KeyCode.delete)) }
        for ch in rewrite.insert { add(0, String(ch)) }
        return events
    }
}
