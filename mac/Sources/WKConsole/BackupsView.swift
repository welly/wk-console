import AppKit
import SwiftUI

struct BackupsView: View {
    @EnvironmentObject private var model: KeyerModel
    @State private var restoring: Backup?

    var body: some View {
        Group {
            if model.backups.isEmpty {
                ContentUnavailableView(
                    "No backups yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("WK Console backs up the keyer's memory every time it writes to it."))
            } else {
                List(model.backups) { backup in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(backup.date.formatted(date: .abbreviated, time: .standard))
                            Text(backup.url.lastPathComponent)
                                .appFont(.small)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([backup.url])
                        }
                        Button("Restore…") { restoring = backup }
                            .disabled(!model.canEdit)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Backups hold the keyer's settings, messages and callsigns. They don't include sidetone volume, Mute, FSK or serial number, which the keyer stores elsewhere.")
                .appFont(.small)
                .foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .navigationTitle("Backups")
        .onAppear { model.loadBackups() }
        .confirmationDialog(
            "Restore the backup from \(restoring?.date.formatted(date: .abbreviated, time: .shortened) ?? "")?",
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            presenting: restoring
        ) { backup in
            Button("Restore") { model.restore(backup) }
        } message: { _ in
            Text("This replaces the keyer's settings, messages and callsigns. Its current memory is backed up first.")
        }
    }
}
