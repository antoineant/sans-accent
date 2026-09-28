import AppKit
import SwiftUI

/// Whether Sans-Accent can read the keyboard yet; the welcome window follows it live.
final class PermissionStatus: ObservableObject {
    @Published var granted = false
}

/// First-launch window: what the app does, why it needs Accessibility access, and a field to try it.
final class WelcomeWindow {
    private var window: NSWindow?
    private let status: PermissionStatus
    private let requestAccess: () -> Void

    init(status: PermissionStatus, requestAccess: @escaping () -> Void) {
        self.status = status
        self.requestAccess = requestAccess
    }

    func show() {
        if window == nil {
            let view = WelcomeView(status: status, requestAccess: requestAccess) { [weak self] in
                self?.window?.close()
            }
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Sans-Accent"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    @ObservedObject var status: PermissionStatus
    let requestAccess: () -> Void
    let done: () -> Void
    @State private var sample = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Sans-Accent").font(.title).bold()
                    Text(L("welcome.slogan")).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                step("keyboard", L("welcome.how.type"))
                step("list.bullet", L("welcome.how.choose"))
                step("option", L("welcome.how.option"))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("welcome.permission.title")).font(.headline)
                    Text(L("welcome.permission.body")).fixedSize(horizontal: false, vertical: true)
                    if status.granted {
                        Label(L("welcome.permission.granted"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(L("welcome.permission.button"), action: requestAccess)
                            .keyboardShortcut(.defaultAction)
                        Text(L("welcome.permission.waiting"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            if status.granted {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("welcome.try.title")).font(.headline)
                    TextField(L("welcome.try.placeholder"), text: $sample)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                // Not ⏎: that confirms choices while trying the field above.
                Button(L("welcome.done"), action: done)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.tint)
        }
    }
}
