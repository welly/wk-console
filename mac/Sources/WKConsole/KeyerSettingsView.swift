import SwiftUI

struct KeyerSettingsView: View {
    @EnvironmentObject private var model: KeyerModel
    @State private var user = 1

    var body: some View {
        VStack(spacing: 0) {
            Picker("User", selection: $user) {
                Text("User 1").tag(1)
                Text("User 2").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 12)

            if model.drafts.count == 2 {
                UserEditor(settings: $model.drafts[user - 1])
            }
        }
        .disabled(!model.canEdit)
        .navigationTitle("Keyer Settings")
        .navigationSubtitle(user == model.activeUser ? "User \(user) · active" : "User \(user)")
    }
}

/// Editor for one user's settings block.
struct UserEditor: View {
    @Binding var settings: UserSettings

    var body: some View {
        Form {
            Section("Speed") {
                NumberRow("Favourite speed", value: $settings.favoriteWPM, range: 5...99, unit: "WPM")
                NumberRow("Minimum WPM", value: $settings.minWPM, range: 5...99, unit: "WPM",
                          note: "Lowest speed on the speed control")
                NumberRow("WPM range", value: $settings.wpmRange, range: 0...31, unit: "WPM",
                          note: "The speed control covers \(settings.minWPM)–\(settings.maxWPM) WPM")
                NumberRow("Command speed", value: $settings.commandWPM, range: 5...99, unit: "WPM",
                          note: "Speed of the keyer's replies in command mode")
                NumberRow("Farnsworth", value: $settings.farnsworth, range: 0...99, unit: "WPM",
                          note: "0 = off")
            }

            Section("Paddle") {
                Picker("Mode", selection: $settings.keyMode) {
                    ForEach(UserSettings.KeyMode.allCases) { Text($0.name).tag($0) }
                }
                Picker("Ultimatic priority", selection: $settings.ultimaticPriority) {
                    Text("Normal").tag(0)
                    Text("Dah").tag(1)
                    Text("Dit").tag(2)
                }
                Picker("Hang time", selection: $settings.hangTime) {
                    Text("Wordspace + 1 dit").tag(0)
                    Text("Wordspace + 2 dits").tag(1)
                    Text("Wordspace + 4 dits").tag(2)
                    Text("Wordspace + 8 dits").tag(3)
                }
                NumberRow("Switchpoint", value: $settings.paddleSwitchpoint, range: 10...90, unit: "%")
                NumberRow("Letterspace", value: $settings.letterspace, range: 0...31)
                Toggle("Auto space", isOn: $settings.autospace)
                Toggle("Swap paddles", isOn: $settings.paddleSwap)
                Toggle("Disable paddle watchdog", isOn: $settings.watchdogDisabled)
            }

            Section("Keying") {
                NumberRow("Weight", value: $settings.weight, range: 10...90, unit: "%")
                NumberRow("Ratio", value: $settings.ratio, range: 33...66,
                          note: String(format: "Dit:dah 1:%.2f (50 = 1:3)", 3.0 * Double(settings.ratio) / 50.0))
                NumberRow("Compensation", value: $settings.keyComp, range: 0...250, unit: "ms")
                NumberRow("First extension", value: $settings.firstExtension, range: 0...250, unit: "ms")
                Toggle("Contest (CT) spacing", isOn: $settings.contestSpacing)
                Toggle("Key 1 output", isOn: $settings.key1Enabled)
                Toggle("Key 2 output", isOn: $settings.key2Enabled)
                Toggle("Tune at 50% duty", isOn: $settings.tune50)
            }

            Section("Push to talk") {
                Toggle("Enable PTT", isOn: $settings.pttEnabled)
                NumberRow("Lead-in", value: $settings.leadIn, range: 0...250, unit: "× 10 ms")
                NumberRow("Tail", value: $settings.tail, range: 0...250, unit: "× 10 ms")
            }

            Section {
                Toggle("Enable sidetone", isOn: $settings.sidetoneEnabled)
                SidetoneRow(settings: $settings)
            } header: {
                Text("Sidetone")
            } footer: {
                Text("Not available yet: sidetone volume, Mute, paddle-only sidetone, SO2R, Cut 0/9, fast command response, serial number and FSK. The keyer keeps these outside the memory WK Console reads, so use WinKeyerTools for them for now.")
                    .appFont(.small)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .formStyle(.grouped)
    }
}

struct NumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String = ""
    var note: String?

    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String = "", note: String? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.unit = unit
        self.note = note
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 56)
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
                Text(unit)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(minWidth: 60, alignment: .leading)
            }
        } label: {
            Text(title)
            if let note {
                Text(note).appFont(.small)
            }
        }
    }
}

/// Sidetone pitch in 10 Hz steps. The keyer can only make 62500 ÷ n Hz, so the
/// app picks the nearest pitch it can make and shows it rounded to 10 Hz.
struct SidetoneRow: View {
    @EnvironmentObject private var model: KeyerModel
    @Binding var settings: UserSettings

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button {
                    model.previewSidetone(settings)
                } label: {
                    Image(systemName: "play.fill")
                }
                .accessibilityLabel("Preview sidetone")
                .buttonStyle(.borderless)
                .help("Play two dits at this pitch (sidetone only)")
                .disabled(model.isSending)
                TextField("Frequency", value: $settings.sidetoneDisplayHz, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 56)
                Stepper("Frequency") {
                    settings.stepSidetone(up: true)
                } onDecrement: {
                    settings.stepSidetone(up: false)
                }
                .labelsHidden()
                Text("Hz")
                    .foregroundStyle(Palette.secondaryText)
                    .frame(minWidth: 60, alignment: .leading)
            }
        } label: {
            Text("Frequency")
        }
    }
}
