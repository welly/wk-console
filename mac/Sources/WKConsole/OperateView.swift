import AppKit
import SwiftUI

struct OperateView: View {
    @EnvironmentObject private var model: KeyerModel
    @EnvironmentObject private var speed: LiveSpeed
    @Environment(\.textScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var announcement: Task<Void, Never>?
    /// Called to go to the Messages page.
    var editMessages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    TranscriptView()
                    TypeToSend()
                }
                MessageList(editMessages: editMessages)
                    .frame(width: 280 * scale)
            }
        }
        .padding(20)
        .navigationTitle("Operate")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(speed.wpm.map(String.init) ?? "–")
                    .appFont(.speed, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy, value: speed.wpm)
                Text("WPM")
                    .appFont(.title)
                    .foregroundStyle(Palette.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            .accessibilityValue(speed.wpm.map { "\($0) words per minute" } ?? "Unknown")
            .accessibilityAddTraits(.updatesFrequently)
            .onChange(of: speed.wpm) { _, wpm in
                // Announce the speed once the speed control has settled, for VoiceOver users.
                announcement?.cancel()
                guard let wpm else { return }
                announcement = Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    if !Task.isCancelled { VoiceOver.announce("\(wpm) words per minute") }
                }
            }
            // How the keyer is keying: mode, and Farnsworth when it's set.
            if let s = model.activeSettings {
                Text(s.keyMode.name + (s.farnsworth > 0 ? " · Farnsworth \(s.farnsworth) WPM" : ""))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The stored messages, in full as they'll be sent, beside the transcript.
/// Only filled-in messages are listed; the one being sent is highlighted.
struct MessageList: View {
    @EnvironmentObject private var model: KeyerModel
    var editMessages: () -> Void

    var body: some View {
        let slots = model.messages?.slots ?? []
        let filled = slots.prefix(12).indices.filter { !slots[$0].isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            Text("Messages")
                .appFont(.heading, weight: .semibold)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filled, id: \.self) { i in
                        MessageRow(index: i, label: model.label(for: i), text: model.expanded(slots[i]),
                                   isSending: model.isSending && model.sendingSlot == i) {
                            model.send(slot: i)
                        }
                        .disabled(!model.isConnected || model.isSending)
                    }
                    Button(action: editMessages) {
                        Label(filled.isEmpty ? "Add a message" : "Edit messages", systemImage: filled.isEmpty ? "plus" : "pencil")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct MessageRow: View {
    let index: Int
    let label: String
    let text: String
    let isSending: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("F\(index + 1)")
                    .appFont(.small, design: .monospaced)
                    .foregroundStyle(isSending ? Palette.accentText : Palette.secondaryText)
                    .padding(.horizontal, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSending ? Color.accentColor : .secondary.opacity(0.4), lineWidth: 0.5))
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(isSending ? Palette.accentText : .primary)
                    Text(text)
                        .appFont(.small, design: .monospaced)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSending {
                    Label("Sending", systemImage: "waveform")
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Palette.accentText)
                } else if hovering && isEnabled {
                    Image(systemName: "play.fill")
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSending ? Color.accentColor.opacity(0.15) : hovering && isEnabled ? Color.primary.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Send (F\(index + 1))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), F\(index + 1)")
        .accessibilityValue(isSending ? "Sending" : text)
        .accessibilityHint("Sends this message")
        .accessibilityAddTraits(.isButton)
    }
}

/// What the keyer has sent, from its echo, including paddle sending. Text still
/// waiting to go out follows it with a soft highlight that shrinks as it's sent.
struct TranscriptView: View {
    @EnvironmentObject private var model: KeyerModel
    @EnvironmentObject private var transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sent")
                    .appFont(.heading, weight: .semibold)
                Spacer()
                Button("Clear") { transcript.clear() }
                    .disabled(transcript.runs.isEmpty)
            }
            .appFont(.small)

            ScrollViewReader { proxy in
                ScrollView {
                    text
                        .appFont(.transcript, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: transcript.runs.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: transcript.pending) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .accessibilityLabel("Sent text")
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxHeight: .infinity)
    }

    /// Everything sent, from the paddle or from WK Console, in one style; text
    /// still waiting to go out is highlighted, and the highlight shrinks as the
    /// keyer sends each letter.
    private var text: Text {
        var waiting = AttributedString(transcript.pending)
        waiting.backgroundColor = Color.accentColor.opacity(0.22)
        return Text(AttributedString(transcript.runs.map(\.text).joined()) + waiting)
    }
}

struct TypeToSend: View {
    @EnvironmentObject private var model: KeyerModel
    @AppStorage("SendAsYouType") private var sendAsYouType = false
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        let bad = MorseText.unsupported(in: typed)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(sendAsYouType ? "Type to send as you go…" : "Type to send, then press Return…", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .appFont(.body, design: .monospaced)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: typed) { old, new in
                        guard sendAsYouType, new.hasPrefix(old), new.count > old.count else { return }
                        model.send(text: String(new.dropFirst(old.count)))
                    }
                Toggle("As you type", isOn: $sendAsYouType)
                    .toggleStyle(.checkbox)
                    .help("Send each character as you type it")
                Button(model.isSending ? "Stop" : "Send") {
                    if model.isSending { model.stopSending() } else { submit() }
                }
                .help(model.isSending ? "Stop sending (Esc)" : "Send (Return)")
            }
            if !bad.isEmpty {
                NoticeText("These won't be sent: \(bad.map { "“\($0)”" }.joined(separator: " "))")
            }
        }
        .disabled(!model.isConnected)
        .onAppear { focused = true }
    }

    private func submit() {
        if sendAsYouType {
            model.send(text: " ")
        } else if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
            model.send(text: typed + " ")
        }
        typed = ""
        focused = true
    }
}
