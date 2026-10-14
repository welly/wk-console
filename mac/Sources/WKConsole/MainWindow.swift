import AppKit
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case operate, messages, settings, backups
    var id: String { rawValue }

    var title: String {
        switch self {
        case .operate: "Operate"
        case .messages: "Messages"
        case .settings: "Keyer"
        case .backups: "Backups"
        }
    }

    var icon: String {
        switch self {
        case .operate: "dot.radiowaves.left.and.right"
        case .messages: "text.bubble"
        case .settings: "slider.horizontal.3"
        case .backups: "clock.arrow.circlepath"
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject private var model: KeyerModel
    @SceneStorage("page") private var page: Page = .operate
    @Environment(\.textScale) private var scale

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: Binding(get: { page }, set: { page = $0 ?? .operate })) { p in
                Label(p.title, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180 * scale, ideal: 200 * scale)
        } detail: {
            Group {
                if model.device == nil {
                    ConnectPrompt()
                } else {
                    switch page {
                    case .operate: OperateView { page = .messages }
                    case .messages: MessagesView()
                    case .settings: KeyerSettingsView()
                    case .backups: BackupsView()
                    }
                }
            }
            .toolbar { MainToolbar() }
            .safeAreaInset(edge: .bottom, spacing: 0) { ChangesBar() }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onDisappear { AppPresence.windowClosed() }
        .alert("Couldn't write to the keyer", isPresented: Binding(
            get: { model.writeError != nil },
            set: { if !$0 { model.writeError = nil } }
        )) {
            Button("OK") { model.writeError = nil }
        } message: {
            Text(model.writeError ?? "")
        }
    }
}

struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ConnectionPill()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ActiveUserPicker()
            PracticeToggle()
            TransmitIndicator()
        }
    }
}

// MARK: Connection

struct ConnectionPill: View {
    @EnvironmentObject private var model: KeyerModel
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(colour).frame(width: 8, height: 8)
                Text(title).lineLimit(1)
            }
        }
        .help("Connection")
        .accessibilityLabel("Connection: \(title)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ConnectionPanel().padding(16).frame(width: 340)
        }
    }

    private var colour: Color {
        switch model.state {
        case .connected: .green
        case .connecting: .orange
        case .disconnected, .needsPort: .secondary
        case .failed: .red
        }
    }

    private var title: String {
        switch model.state {
        case .connected: (model.selectedPort as NSString?)?.lastPathComponent ?? "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Not connected"
        case .needsPort: "Choose port"
        case .failed: "Connection problem"
        }
    }
}

/// Port choice and connection actions, used in the toolbar popover and the
/// prompt shown when there's no keyer.
struct ConnectionPanel: View {
    @EnvironmentObject private var model: KeyerModel
    @State private var picked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .failed(let message) = model.state {
                NoticeText(message, kind: .error)
            }
            HStack {
                Picker("Port", selection: $picked) {
                    if picked == nil { Text("Choose…").tag(String?.none) }
                    ForEach(model.ports, id: \.self) { Text($0).tag(Optional($0)) }
                }
                Button {
                    model.rescanPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Rescan ports")
                .help("Rescan ports")
            }
            HStack {
                if model.isConnected && picked == model.selectedPort {
                    Button("Reload Settings") { model.reload() }
                        .disabled(!model.canEdit)
                        .help("Re-read everything from the keyer, discarding unsaved changes")
                    Button("Release Port") { model.disconnect() }
                        .help("Disconnect so another app can use the keyer")
                } else {
                    Button(model.isConnected ? "Switch Port" : "Connect") {
                        if let picked { model.connect(to: picked) }
                    }
                    .disabled(picked == nil || model.state == .connecting)
                    .keyboardShortcut(.defaultAction)
                }
            }
            if let d = model.device, model.isConnected {
                Divider()
                LabeledContent("Firmware", value: d.firmware)
                if let v = d.supplyVoltage { LabeledContent("Supply", value: v) }
                LabeledContent("Port", value: d.port)
            }
        }
        .onAppear {
            model.rescanPorts()
            picked = model.selectedPort ?? SerialPort.availablePorts().candidates.first
        }
    }
}

struct ConnectPrompt: View {
    @EnvironmentObject private var model: KeyerModel

    var body: some View {
        VStack(spacing: 16) {
            if model.state == .connecting {
                ProgressView("Connecting to your WinKeyer…")
            } else {
                Image(systemName: "cable.connector")
                    .appFont(.icon)
                    .foregroundStyle(Palette.secondaryText)
                Text(model.state == .needsPort ? "Choose your WinKeyer's port" : "Connect your WinKeyer")
                    .appFont(.title)
                ConnectionPanel().frame(width: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Toolbar items

struct ActiveUserPicker: View {
    @EnvironmentObject private var model: KeyerModel

    var body: some View {
        if model.drafts.count == 2 {
            Picker("Active user", selection: $model.drafts[0].selectsUser2) {
                Text("User 1").tag(false)
                Text("User 2").tag(true)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!model.canEdit)
            .help("Which user the keyer uses in standalone mode (saved with Write to Keyer)")
        }
    }
}

struct PracticeToggle: View {
    @EnvironmentObject private var model: KeyerModel

    var body: some View {
        // The toolbar hides control labels, so show "Practice mode" as its own text.
        HStack(spacing: 6) {
            Text("Practice mode")
                .onTapGesture { model.practiceMode.toggle() }
                .accessibilityHidden(true)
            Toggle("Practice mode", isOn: $model.practiceMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
        .help("Practice mode: key outputs and PTT stay off, so sending only plays sidetone")
    }
}

struct TransmitIndicator: View {
    @EnvironmentObject private var model: KeyerModel

    /// Always shown, so the toolbar doesn't shift: dim normally, red while the
    /// transmitter is actually keyed (never in practice mode).
    var body: some View {
        let transmitting = model.isSending && !model.practiceMode
        Text("TX")
            .appFont(.small, weight: .bold)
            .foregroundStyle(transmitting ? Color.white : Palette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(transmitting ? Color.red : Palette.secondaryText.opacity(0.15), in: Capsule())
            .help(transmitting ? "Sending: your transmitter is keyed" : "Lights up red while your transmitter is keyed")
            .accessibilityLabel(transmitting ? "Transmitting" : "Not transmitting")
    }
}

/// A bar along the bottom of the window, shown only when there's something to
/// save: the number of unsaved changes with Revert and Write to Keyer, then
/// progress while writing, then "Saved" for a few seconds. It's the one place
/// that shows writing progress.
struct ChangesBar: View {
    @EnvironmentObject private var model: KeyerModel
    @AppStorage("SkipWriteWarning") private var skipWriteWarning = false
    @State private var confirming = false
    @State private var showSaved = false

    private var isVisible: Bool {
        model.activity != nil || model.hasUnsavedChanges || showSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                Divider()
                HStack(spacing: 12) {
                    status
                    Spacer()
                    if model.activity == nil && model.hasUnsavedChanges {
                        Button("Revert") { model.revertChanges() }
                        Button("Write to Keyer") {
                            if skipWriteWarning { model.writeChanges() } else { confirming = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                        .disabled(!model.canWrite)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .confirmationDialog("Write these changes to the keyer?", isPresented: $confirming) {
            Button("Write to Keyer") { model.writeChanges() }
        } message: {
            Text("The keyer restarts afterwards to load them. Anything changed with paddle commands but not saved with X S — such as sidetone switched on with A — will be lost. A backup of the keyer's memory is taken first.")
        }
        .dialogSuppressionToggle(isSuppressed: $skipWriteWarning)
        .onChange(of: model.lastSaved) {
            showSaved = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                showSaved = false
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.activity {
        case .writing:
            ProgressView().controlSize(.small)
            Text("Writing to the keyer…")
        case .reloading:
            ProgressView().controlSize(.small)
            Text("Reloading from the keyer…")
        case nil:
            if model.hasUnsavedChanges {
                Label(model.changeCount == 1 ? "1 unsaved change" : "\(model.changeCount) unsaved changes",
                      systemImage: "pencil.circle")
            } else {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
            }
        }
    }
}
