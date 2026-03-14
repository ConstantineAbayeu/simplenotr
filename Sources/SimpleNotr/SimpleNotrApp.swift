import SwiftUI
import AppKit

// Bring the app to the foreground when launched from the terminal.
// Without this, `swift run` opens the window but keyboard focus stays
// in the terminal session.
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct SimpleNotrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vaultManager = VaultManager()
    @AppStorage("sn.vimModeEnabled") private var vimModeEnabled = false
    @AppStorage("sn.fontSize")       private var fontSize: Double = 14
    @AppStorage("sn.showPreview")    private var showPreview = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Markdown Note") {
                    NotificationCenter.default.post(name: .newMarkdownNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Text Note") {
                    NotificationCenter.default.post(name: .newTextNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Mermaid Diagram") {
                    NotificationCenter.default.post(name: .newMermaidNote, object: nil)
                }

                Button("New Folder") {
                    NotificationCenter.default.post(name: .newFolder, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("Open Vault…") {
                    NotificationCenter.default.post(name: .openVault, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Toggle("Vim Mode", isOn: $vimModeEnabled)
                Divider()
                Toggle("Preview", isOn: $showPreview)
                    .keyboardShortcut("p", modifiers: .command)
                Divider()
                Button("Zoom In")      { fontSize = min(fontSize + 2, 48) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out")     { fontSize = max(fontSize - 2, 8) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size")  { fontSize = 14 }
                    .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Navigate") {
                Button("Next Tab") {
                    NotificationCenter.default.post(name: .nextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .previousTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command])

                Divider()

                Button("Focus File Tree") {
                    NotificationCenter.default.post(name: .focusSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command])
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newMarkdownNote  = Notification.Name("sn.newMarkdownNote")
    static let newTextNote      = Notification.Name("sn.newTextNote")
    static let newMermaidNote   = Notification.Name("sn.newMermaidNote")
    static let newFolder       = Notification.Name("sn.newFolder")
    static let openVault       = Notification.Name("sn.openVault")
    static let navigateToNote  = Notification.Name("sn.navigateToNote")
    static let saveAll         = Notification.Name("sn.saveAll")
    static let nextTab         = Notification.Name("sn.nextTab")
    static let previousTab     = Notification.Name("sn.previousTab")
    static let focusSidebar    = Notification.Name("sn.focusSidebar")
    static let closeTab        = Notification.Name("sn.closeTab")
}
