import AppKit
import SwiftUI

@main
struct WKConsoleApp: App {
    @StateObject private var model = KeyerModel()
    @AppStorage("ShowMenuBarItem") private var showMenuBarItem = true

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--self-test-write"), i + 1 < args.count {
            KeyerModel.runWriteSelfTest(port: args[i + 1])
        }
    }

    var body: some Scene {
        Window("WK Console", id: "main") {
            MainWindow()
                .environmentObject(model)
                .environmentObject(model.speed)
                .environmentObject(model.transcript)
                .modifier(TextScaling())
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            TextSizeCommands()
            SendCommands(model: model)
        }

        Settings {
            AppSettingsView()
                .environmentObject(model)
                .modifier(TextScaling())
        }

        MenuBarExtra(isInserted: $showMenuBarItem) {
            MenuContent()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model, speed: model.speed)
        }
    }
}

/// The Send menu: F1–F12 send messages 1–12, Esc stops (N1MM conventions).
struct SendCommands: Commands {
    @ObservedObject var model: KeyerModel

    var body: some Commands {
        CommandMenu("Send") {
            ForEach(0..<12, id: \.self) { i in
                let text = model.messages?.slots[i] ?? ""
                Button(text.isEmpty ? "Message \(i + 1)" : model.label(for: i)) {
                    model.send(slot: i)
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(UInt32(NSF1FunctionKey + i))!)), modifiers: [])
                .disabled(text.isEmpty || !model.isConnected)
            }
            Divider()
            Button("Stop Sending") { model.stopSending() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!model.isSending)
            Toggle("Practice Mode", isOn: $model.practiceMode)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: KeyerModel
    @ObservedObject var speed: LiveSpeed

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.isSending && !model.practiceMode
                  ? "antenna.radiowaves.left.and.right.circle.fill"
                  : "antenna.radiowaves.left.and.right")
            Text(title).monospacedDigit()
        }
    }

    private var title: String {
        switch model.state {
        case .connected: speed.wpm.map { "\($0) WPM" } ?? "– WPM"
        case .connecting: "– WPM"
        case .needsPort: "WK ?"
        case .disconnected, .failed: "WK –"
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: KeyerModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        if let s = model.activeSettings, model.isConnected {
            Text("User \(s.user) · \(s.keyMode.name)")
        }

        Divider()

        if model.isConnected, let messages = model.messages {
            if model.isSending {
                Button("Stop Sending") { model.stopSending() }
            } else {
                Menu("Send Message") {
                    ForEach(0..<12, id: \.self) { i in
                        let text = messages.slots[i]
                        if !text.isEmpty {
                            Button("F\(i + 1)  \(model.label(for: i))") { model.send(slot: i) }
                        }
                    }
                }
                .disabled(messages.slots[0..<12].allSatisfy(\.isEmpty))
            }
            Toggle("Practice Mode", isOn: $model.practiceMode)
            Divider()
        }

        Button("Open WK Console") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()
        Button("Quit WK Console") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch model.state {
        case .connected: "Connected to \((model.selectedPort as NSString?)?.lastPathComponent ?? "WinKeyer")"
        case .connecting: "Connecting…"
        case .needsPort: "No WinKeyer port selected"
        case .disconnected: "Not connected"
        case .failed(let message): message
        }
    }
}
