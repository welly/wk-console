import SwiftUI

/// App preferences (⌘,). Keyer settings live in the main window.
struct AppSettingsView: View {
    @EnvironmentObject private var model: KeyerModel
    @AppStorage("ShowMenuBarItem") private var showMenuBarItem = true
    @AppStorage("SkipWriteWarning") private var skipWriteWarning = false
    @AppStorage("SendAsYouType") private var sendAsYouType = false
    @AppStorage(TextScale.key) private var textScale = 1.0

    var body: some View {
        Form {
            Section("Connection") {
                ConnectionPanel()
            }
            Section("While connected") {
                Toggle("Practice mode", isOn: $model.practiceMode)
                Text("Key outputs and PTT stay off, so sending only plays sidetone.")
                    .appFont(.small)
                    .foregroundStyle(Palette.secondaryText)
                Picker("Sidetone", selection: $model.sidetoneAlwaysOn) {
                    Text("Always on").tag(true)
                    Text("Follow saved setting").tag(false)
                }
                Toggle("Send as you type", isOn: $sendAsYouType)
            }
            Section("App") {
                Picker("Text size", selection: $textScale) {
                    ForEach(Array(zip(TextScale.levels, TextScale.names)), id: \.0) { level, name in
                        Text(name).tag(level)
                    }
                }
                Text("Also in the View menu: Make Text Bigger (⌘+), Make Text Smaller (⌘−) and Actual Size (⌘0).")
                    .appFont(.small)
                    .foregroundStyle(Palette.secondaryText)
                Toggle("Show speed in the menu bar", isOn: $showMenuBarItem)
                Toggle("Confirm before writing to the keyer", isOn: Binding(
                    get: { !skipWriteWarning },
                    set: { skipWriteWarning = !$0 }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460 * textScale)
        .fixedSize(horizontal: false, vertical: true)
    }
}
