import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var model: KeyerModel

    var body: some View {
        Group {
            if let drafts = model.messageDrafts {
                MessagesEditor(store: Binding(
                    get: { drafts },
                    set: { model.messageDrafts = $0 }
                ), labels: $model.labels, canEditKeyer: model.canEdit)
            }
        }
        .navigationTitle("Messages")
    }
}

struct MessagesEditor: View {
    @Binding var store: MessageStore
    @Binding var labels: [String]
    /// Messages and callsigns live on the keyer; labels live in the app and
    /// can be edited at any time.
    var canEditKeyer: Bool

    var body: some View {
        Form {
            Section("Callsigns") {
                callsignField("User 1", MessageStore.user1Call)
                callsignField("User 2", MessageStore.user2Call)
            }
            .disabled(!canEditKeyer)

            Section("Bank 1") {
                bank(0..<6)
            }

            Section {
                bank(6..<12)
            } header: {
                Text("Bank 2")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(min(store.used, MessageStore.capacity)),
                                 total: Double(MessageStore.capacity))
                    Text("\(store.used) of \(MessageStore.capacity) characters used. Type embedded commands such as /M (your callsign) as ordinary text.")
                        .appFont(.small)
                        .foregroundStyle(store.used > MessageStore.capacity ? Palette.danger : Palette.secondaryText)
                    Text("Labels are short names for the Operate page and menus. Leave one blank to use the message's first word. They're kept by WK Console and save straight away; messages are saved to the keyer with Write to Keyer.")
                        .appFont(.small)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.top, 4)
                }
            }

            Section {
                DisclosureGroup {
                    EmbeddedCommandsReference()
                } label: {
                    Label("Embedded commands", systemImage: "command")
                }
                .disclosureGroupStyle(FullRowDisclosureStyle())
            }
        }
        .formStyle(.grouped)
    }

    /// A small table: key, label, message.
    private func bank(_ slots: Range<Int>) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Key")
                Text("Label")
                Text("Message")
            }
            .appFont(.small, weight: .medium)
            .foregroundStyle(Palette.secondaryText)
            ForEach(slots, id: \.self) { i in
                GridRow(alignment: .firstTextBaseline) {
                    Text("F\(i + 1)")
                        .appFont(.body, design: .monospaced)
                        .foregroundStyle(Palette.secondaryText)
                    TextField(KeyerModel.defaultLabel(for: store.slots[i]), text: $labels[i])
                        .labelsHidden()
                        .frame(width: 110)
                    messageField(i)
                        .disabled(!canEditKeyer)
                }
            }
        }
    }

    private func callsignField(_ label: String, _ index: Int) -> some View {
        LabeledContent(label) {
            messageField(index)
        }
    }

    private func messageField(_ index: Int) -> some View {
        let text = Binding(
            get: { store.slots[index] },
            set: { store.slots[index] = $0.uppercased() }
        )
        let value = store.slots[index]
        let bad = MorseText.unsupported(in: value)
        let commands = index < 12 ? KeyerModel.unsupportedCommands(in: value) : []
        return VStack(alignment: .leading, spacing: 2) {
            TextField(index < 12 ? "Empty" : "Callsign", text: text)
                .labelsHidden()
                .appFont(.body, design: .monospaced)
            if !bad.isEmpty {
                NoticeText("Can't store \(bad.map { "“\($0)”" }.joined(separator: " "))", kind: .error)
            } else if !commands.isEmpty {
                NoticeText("\(commands.joined(separator: " ")) works when the keyer plays this message itself, but not when WK Console sends it.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Commands that can be typed into a message (from the WinKeyer 3 datasheet's
/// standalone embedded command table).
struct EmbeddedCommandsReference: View {
    private static let commands: [(String, String)] = [
        ("/M", "Your callsign (the active user's)"),
        ("/N", "Serial number, then add one"),
        ("/D", "Take one off the serial number"),
        ("/R", "Join the next two letters into a prosign"),
        ("/P", "Pause for paddle sending, then carry on after a word space"),
        ("/Wnn", "Wait nn seconds (00–99)"),
        ("/Snn", "Change speed to nn WPM (5–59)"),
        ("/Yn", "Speed up by n WPM (0–9)"),
        ("/Zn", "Slow down by n WPM (0–9)"),
        ("/X", "Cancel a /S, /H or /Q speed change"),
        ("/Inn", "Extra letter spacing (00–31)"),
        ("/Knn", "Key the transmitter for nn seconds (00–99)"),
        ("/Un", "PTT off (0) or on (1)"),
        ("/O", "Switch between key outputs 1 and 2"),
        ("/Bnn", "Repeat as a beacon every nn seconds (00–99)"),
        ("/Cn", "Play message n, then come back"),
        ("/1 … /6", "Jump to message 1–6"),
        ("/E", "Swap message banks"),
        ("/V", "Send the supply voltage"),
        ("/Hn", "High-speed CW, rate n: 0 = 1,000 lpm … 5 = 6,000 lpm"),
        ("/Qn", "QRSS, dit length n: 0 = 3 s … 5 = 60 s"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type these straight into a message. They run when the keyer plays the message itself (from its buttons or memory). When WK Console sends a message, only /M works; the others are sent as plain text.")
                .appFont(.small)
                .foregroundStyle(Palette.secondaryText)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(Self.commands, id: \.0) { command, meaning in
                    GridRow {
                        Text(command)
                            .appFont(.body, design: .monospaced)
                            .textSelection(.enabled)
                        HStack(spacing: 6) {
                            Text(meaning)
                            if command == "/M" {
                                Text("Works from WK Console")
                                    .appFont(.small)
                                    .foregroundStyle(Palette.success)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

/// A disclosure group whose whole header row toggles it, with the chevron on
/// the right, as in System Settings.
struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        FullRowDisclosure(configuration: configuration)
    }
}

private struct FullRowDisclosure: View {
    let configuration: DisclosureGroupStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { configuration.isExpanded.toggle() }
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Palette.secondaryText)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
