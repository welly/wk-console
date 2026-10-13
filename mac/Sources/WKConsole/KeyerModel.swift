import AppKit

/// One connection, run on its own thread until stopped or it fails.
/// The UI talks to the worker only through these lock-protected queues.
private final class Session {
    let port: String
    /// Host options at the time of connecting; later changes arrive as commands.
    let options: HostOptions
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _stopped = false
    /// Commands to send straight away.
    private var commands: [UInt8] = []
    /// Morse text, fed to the keyer a few characters at a time.
    private var text: [UInt8] = []
    /// Sent once the keyer next goes idle (used to undo a preview).
    private var afterIdle: [UInt8]?

    init(port: String, options: HostOptions) {
        self.port = port
        self.options = options
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    var stopped: Bool { locked { _stopped } }
    func stop() { locked { _stopped = true } }

    func command(_ bytes: [UInt8]) { locked { commands += bytes } }
    func takeCommands() -> [UInt8] { locked { defer { commands = [] }; return commands } }

    func queueText(_ bytes: [UInt8]) { locked { text += bytes } }
    var hasQueuedText: Bool { locked { !text.isEmpty } }
    func takeText(max n: Int) -> [UInt8] {
        locked {
            let chunk = Array(text.prefix(n))
            text.removeFirst(chunk.count)
            return chunk
        }
    }

    /// Drop queued text and stop the keyer.
    func clear() { locked { text = []; commands += [WK.clearBuffer] } }

    func setAfterIdle(_ bytes: [UInt8]) { locked { afterIdle = bytes } }
    func takeAfterIdle() -> [UInt8]? { locked { defer { afterIdle = nil }; return afterIdle } }
    /// A preview is playing; its echo isn't shown.
    var isPreviewing: Bool { locked { afterIdle != nil } }
}

/// The live speed, kept apart from KeyerModel so that speed changes don't
/// redraw the menu while it's open.
final class LiveSpeed: ObservableObject {
    @Published var wpm: Int?
}

/// What the keyer has sent, from its echo, and what's still waiting to go.
final class Transcript: ObservableObject {
    enum Source { case sent, paddle }

    struct Run: Identifiable {
        let id = UUID()
        let source: Source
        var text: String
    }

    @Published private(set) var runs: [Run] = []
    /// Text queued by the app but not yet echoed by the keyer.
    @Published private(set) var pending = ""

    private static let limit = 4000

    func append(_ c: Character, from source: Source) {
        if let last = runs.indices.last, runs[last].source == source {
            runs[last].text.append(c)
        } else {
            runs.append(Run(source: source, text: String(c)))
        }
        if source == .sent, !pending.isEmpty {
            pending.removeFirst()
        }
        var count = runs.reduce(0) { $0 + $1.text.count }
        while count > Self.limit, !runs.isEmpty {
            count -= runs[0].text.count
            runs.removeFirst()
        }
    }

    func queued(_ text: String) { pending += text }
    func clearPending() { pending = "" }
    func clear() { runs = []; pending = "" }
}

struct Backup: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
}

final class KeyerModel: ObservableObject {
    enum State: Equatable {
        case disconnected
        case needsPort
        case connecting
        case connected
        case failed(String)
    }

    /// Something the app is doing with the keyer that blocks editing.
    enum Activity: Equatable {
        case writing
        case reloading
    }

    private enum Keys {
        static let port = "SelectedPort"
        static let practice = "PracticeMode"
        static let sidetoneAlwaysOn = "SidetoneAlwaysOn"
        static let labels = "MessageLabels"
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var activity: Activity?
    let speed = LiveSpeed()
    let transcript = Transcript()
    @Published private(set) var device: DeviceInfo?
    /// Settings as last read from the keyer, and the user's unsaved edits.
    @Published private(set) var users: [UserSettings] = []
    @Published var drafts: [UserSettings] = []
    @Published private(set) var messages: MessageStore?
    @Published var messageDrafts: MessageStore?
    @Published private(set) var activeUser = 1
    @Published private(set) var lastSaved: Date?
    @Published var writeError: String?
    /// True while the keyer is sending, or the app has text queued for it.
    @Published private(set) var isSending = false {
        didSet { if !isSending { sendingSlot = nil } }
    }
    /// The stored message being sent (0–11), if any.
    @Published private(set) var sendingSlot: Int?
    @Published private(set) var backups: [Backup] = []
    @Published private(set) var ports: [String] = []
    @Published var selectedPort: String? {
        didSet { UserDefaults.standard.set(selectedPort, forKey: Keys.port) }
    }
    @Published var practiceMode: Bool {
        didSet {
            UserDefaults.standard.set(practiceMode, forKey: Keys.practice)
            applyHostOptions()
        }
    }
    /// Short names for messages 1–12. The keyer can't store these, so the app
    /// keeps them; an empty label means "use the message's first word".
    @Published var labels: [String] {
        didSet { UserDefaults.standard.set(labels, forKey: Keys.labels) }
    }
    @Published var sidetoneAlwaysOn: Bool {
        didSet {
            UserDefaults.standard.set(sidetoneAlwaysOn, forKey: Keys.sidetoneAlwaysOn)
            applyHostOptions()
        }
    }

    /// The full EEPROM image the settings were read from.
    private var eeprom: [UInt8] = []
    private var session: Session?
    private var reconnectTimer: Timer?
    private var justWrote = false

    var hostOptions: HostOptions { HostOptions(practice: practiceMode, sidetoneAlwaysOn: sidetoneAlwaysOn) }
    var activeSettings: UserSettings? { users.first { $0.user == activeUser } }
    var isConnected: Bool { state == .connected }
    var canEdit: Bool { isConnected && activity == nil }

    /// Number of changed settings bytes plus changed message slots.
    var changeCount: Int {
        let settings = zip(drafts, users).reduce(0) { n, pair in
            n + zip(pair.0.raw, pair.1.raw).filter { $0 != $1 }.count
        }
        let slots = zip(messageDrafts?.slots ?? [], messages?.slots ?? []).filter { $0 != $1 }.count
        return settings + slots
    }
    var hasUnsavedChanges: Bool { changeCount > 0 }
    var canWrite: Bool { hasUnsavedChanges && canEdit }

    static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WK Console/Backups", isDirectory: true)
    }

    /// The port to use at launch: the saved one if it's present, else the only
    /// USB serial port. Nil means the user has to choose.
    static func initialPort() -> String? {
        Migration.run()
        let (candidates, all) = SerialPort.availablePorts()
        if let saved = UserDefaults.standard.string(forKey: Keys.port), all.contains(saved) {
            return saved
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    init() {
        Migration.run()
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.sidetoneAlwaysOn: true])
        practiceMode = defaults.bool(forKey: Keys.practice)
        sidetoneAlwaysOn = defaults.bool(forKey: Keys.sidetoneAlwaysOn)
        selectedPort = defaults.string(forKey: Keys.port)
        let saved = defaults.stringArray(forKey: Keys.labels) ?? []
        labels = (0..<12).map { $0 < saved.count ? saved[$0] : "" }
        // However the app quits, hand the keyer back to standalone mode first.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.disconnect()
        }
        rescanPorts()
        loadBackups()
        if let port = Self.initialPort() {
            connect(to: port)
        } else {
            state = .needsPort
        }
    }

    // MARK: Connection

    func rescanPorts() {
        ports = SerialPort.availablePorts().all
    }

    /// Connect and read the keyer's settings. A quiet reconnect (after a write
    /// or reload) keeps the current values on screen until the new ones arrive.
    func connect(to port: String, quietly: Bool = false) {
        stopSession()
        selectedPort = port
        if !quietly {
            state = .connecting
            speed.wpm = nil
        }
        let session = Session(port: port, options: hostOptions)
        self.session = session
        let thread = Thread { [weak self] in self?.run(session) }
        thread.name = "WinKeyer"
        thread.start()
    }

    /// Release the serial port, e.g. so K1EL's settings app can use the keyer.
    func disconnect() {
        stopSession()
        activity = nil
        state = .disconnected
        speed.wpm = nil
    }

    /// Re-read settings from the keyer, discarding unsaved edits.
    func reload() {
        guard let port = selectedPort, isConnected else { return }
        activity = .reloading
        connect(to: port, quietly: true)
    }

    private func applyHostOptions() {
        guard let session, let s = activeSettings else { return }
        session.command([WK.setPinConfig, hostOptions.pinConfig(for: s)])
    }

    // MARK: Sending

    /// Send a stored message, as if its button on the keyer were pressed. /M is
    /// replaced with the active user's callsign; other embedded commands only
    /// work when the keyer plays a message from its own memory.
    func send(message text: String) {
        send(text: expanded(text))
    }

    /// Send stored message `slot` (0–11).
    func send(slot: Int) {
        guard let text = messages?.slots[slot], !text.isEmpty, isConnected else { return }
        send(message: text)
        sendingSlot = slot
    }

    /// The label shown for message `slot`: the user's own, or the first word.
    func label(for slot: Int) -> String {
        let custom = labels[slot].trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty { return custom }
        return Self.defaultLabel(for: messages?.slots[slot] ?? "")
    }

    static func defaultLabel(for text: String) -> String {
        text.split(separator: " ").first.map(String.init) ?? ""
    }

    /// Message text as it will be sent: /M replaced with the active user's callsign.
    func expanded(_ text: String) -> String {
        let call = messageDrafts?.slots[activeUser == 1 ? MessageStore.user1Call : MessageStore.user2Call] ?? ""
        return text.uppercased().replacingOccurrences(of: "/M", with: call)
    }

    /// Queue text to be sent in Morse.
    func send(text: String) {
        guard isConnected, let session else { return }
        let clean = String(text.uppercased().filter { $0 == " " || MorseText.unsupported(in: String($0)).isEmpty })
        guard !clean.isEmpty else { return }
        session.queueText(Array(clean.utf8))
        transcript.queued(clean)
        isSending = true
    }

    func stopSending() {
        session?.clear()
        transcript.clearPending()
        isSending = false
    }

    /// Play two dits at a draft sidetone pitch, with key outputs off, then put
    /// the live pitch back.
    func previewSidetone(_ draft: UserSettings) {
        guard canEdit, let session, let live = activeSettings, !isSending else { return }
        var practice = hostOptions
        practice.practice = true
        practice.sidetoneAlwaysOn = true
        // Set the undo first, so the preview's echo is already muted when it arrives.
        session.setAfterIdle([WK.setPinConfig, hostOptions.pinConfig(for: live), WK.sidetone, live.sidetone])
        session.command([WK.setPinConfig, practice.pinConfig(for: live), WK.sidetone, draft.sidetone]
                        + Array("EE".utf8))
    }

    /// Embedded commands in `text` that the app can't reproduce when sending it.
    static func unsupportedCommands(in text: String) -> [String] {
        let upper = text.uppercased()
        var found: [String] = []
        var i = upper.startIndex
        while let slash = upper[i...].firstIndex(of: "/") {
            let next = upper.index(after: slash)
            guard next < upper.endIndex else { break }
            if upper[next] != "M" {
                found.append("/" + String(upper[next]))
            }
            i = next
        }
        return found
    }

    // MARK: Writing

    func revertChanges() {
        drafts = users
        messageDrafts = messages
    }

    /// Write the edited settings and messages to the keyer.
    func writeChanges() {
        guard canWrite else { return }
        var image = eeprom
        for d in drafts {
            let base = UserSettings.offset(user: d.user)
            image.replaceSubrange(base..<base + UserSettings.blockSize, with: d.raw)
        }
        if let m = messageDrafts, m != messages {
            do {
                try m.apply(to: &image)
            } catch {
                writeError = error.localizedDescription
                return
            }
        }
        write(image, expecting: eeprom)
    }

    /// Write a backup back to the keyer.
    func restore(_ backup: Backup) {
        do {
            let image = [UInt8](try Data(contentsOf: backup.url))
            guard image.count == eeprom.count else {
                writeError = "That backup is \(image.count) bytes; this keyer uses \(eeprom.count)."
                return
            }
            write(image, expecting: nil)
        } catch {
            writeError = error.localizedDescription
        }
    }

    /// Leave host mode, back up the keyer's memory, write `image`, read it back to
    /// verify, reset the keyer so it uses the new settings, then reconnect quietly.
    /// If `expecting` is given, refuse to write when the keyer's memory no longer
    /// matches it (e.g. it was changed by another app since we read it).
    private func write(_ image: [UInt8], expecting expected: [UInt8]?) {
        guard let path = selectedPort, canEdit else { return }
        activity = .writing
        writeError = nil
        stopSession()

        Thread.detachNewThread { [weak self] in
            var error: String?
            do {
                _ = try Self.performWrite(image, expecting: expected, port: path)
            } catch let e {
                error = e.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.writeError = error
                self.justWrote = error == nil
                self.loadBackups()
                self.connect(to: path, quietly: true)
            }
        }
    }

    /// `WKConsole --self-test-write <port>`: write the keyer's memory back
    /// unchanged through the normal write path, verify it, and exit.
    static func runWriteSelfTest(port path: String) -> Never {
        do {
            let port = try SerialPort(path: path)
            let keyer = Keyer(port: port)
            try keyer.handshake()
            let current = try keyer.dumpEEPROM()
            port.close()
            let backup = try performWrite(current, expecting: current, port: path)
            print("OK: wrote and verified \(current.count) bytes; backup at \(backup.path)")
            exit(0)
        } catch {
            print("FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func performWrite(_ image: [UInt8], expecting expected: [UInt8]?, port path: String) throws -> URL {
        let port = try SerialPort(path: path)
        defer { port.close() }
        let keyer = Keyer(port: port)
        try keyer.handshake()

        let current = try keyer.dumpEEPROM()
        if let expected, current != expected {
            throw KeyerError("The keyer's memory changed since it was read (another app?). Nothing was written; the settings have been reloaded.")
        }
        guard current.count == image.count else {
            throw KeyerError("Unexpected memory size (\(current.count) bytes, expected \(image.count)). Nothing was written.")
        }

        let backup = try saveBackup(current)
        try keyer.loadEEPROM(image)
        let check = try keyer.dumpEEPROM()
        guard check == image else {
            throw KeyerError("Verification failed: the keyer's memory doesn't match what was written. A backup from before the write is in Backups.")
        }
        // Restart the keyer so standalone mode picks up the new settings.
        try port.write([WK.admin, WK.reset])
        Thread.sleep(forTimeInterval: 2)
        return backup
    }

    // MARK: Backups

    private static let backupFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_GB_POSIX")
        return f
    }()

    private static func saveBackup(_ image: [UInt8]) throws -> URL {
        let dir = backupDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("winkeyer-\(backupFormat.string(from: Date())).bin")
        try Data(image).write(to: url)
        return url
    }

    func loadBackups() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.backupDirectory, includingPropertiesForKeys: nil)) ?? []
        backups = urls.filter { $0.pathExtension == "bin" }.compactMap { url in
            let stamp = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "winkeyer-", with: "")
            guard let date = Self.backupFormat.date(from: stamp) else { return nil }
            return Backup(url: url, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: Worker

    private func stopSession() {
        isSending = false
        transcript.clearPending()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        guard let session else { return }
        session.stop()
        // Wait for the keyer to be returned to standalone mode and the port closed.
        _ = session.done.wait(timeout: .now() + 2)
        self.session = nil
    }

    private func publish(_ session: Session, _ update: @escaping (KeyerModel) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session === session else { return }
            update(self)
        }
    }

    private func run(_ session: Session) {
        defer { session.done.signal() }
        do {
            let port = try SerialPort(path: session.port)
            defer { port.close() }
            let keyer = Keyer(port: port)
            try keyer.handshake()
            let info = try keyer.identify()
            let eeprom = try keyer.dumpEEPROM()
            let users = [UserSettings(eeprom: eeprom, user: 1), UserSettings(eeprom: eeprom, user: 2)]
            let active = info.isWK3 && users[0].selectsUser2 ? 2 : 1
            let settings = users[active - 1]
            try keyer.openHost(with: settings, options: session.options, isWK3: info.isWK3)
            defer { keyer.closeHost() }
            publish(session) {
                $0.device = info
                $0.eeprom = eeprom
                $0.users = users
                $0.drafts = users
                $0.messages = MessageStore(eeprom: eeprom)
                $0.messageDrafts = $0.messages
                $0.activeUser = active
                $0.state = .connected
                $0.activity = nil
                if $0.justWrote {
                    $0.justWrote = false
                    $0.lastSaved = Date()
                }
            }
            try workerLoop(session, port: port, settings: settings)
        } catch {
            let message = error.localizedDescription
            publish(session) { $0.connectionFailed(message) }
        }
    }

    private func workerLoop(_ session: Session, port: SerialPort, settings: UserSettings) throws {
        // The keyer sends speed pot and status bytes itself when they change;
        // polling is a fallback, and doubles as a check that it's still there.
        var nextPoll = Date.distantPast
        var lastHeard = Date()
        var lastWPM: Int?
        var lastSent = Date.distantPast
        var inFlight = 0          // characters sent to the keyer but not yet echoed
        var xoff = false
        var breakIn = false

        while !session.stopped {
            let now = Date()
            // Don't poll while text is in the keyer's buffer: on this firmware a
            // poll arriving mid-send occasionally makes it drop a character.
            // It still reports status and speed changes on its own.
            if now >= nextPoll && inFlight == 0 {
                try port.write([WK.getSpeedPot, WK.getStatus])
                nextPoll = now.addingTimeInterval(0.5)
            }
            let commands = session.takeCommands()
            if !commands.isEmpty {
                if commands.contains(WK.clearBuffer) { inFlight = 0 }
                try port.write(commands)
                lastSent = Date()
            }
            // Keep only a few characters in the keyer's buffer, so Stop is quick
            // and nothing is lost if the buffer fills.
            if !xoff && inFlight < 4 {
                let chunk = session.takeText(max: 4 - inFlight)
                if !chunk.isEmpty {
                    try port.write(chunk)
                    inFlight += chunk.count
                    lastSent = Date()
                }
            }

            guard let b = try port.readByte(timeout: 0.05) else {
                if Date().timeIntervalSince(lastHeard) > (inFlight > 0 ? 8 : 3) {
                    throw KeyerError("The keyer stopped responding.")
                }
                continue
            }
            lastHeard = Date()
            if b & 0xC0 == 0x80 {
                let value = settings.minWPM + Int(b & 0x3F)
                if value != lastWPM {
                    lastWPM = value
                    publish(session) { $0.speed.wpm = value }
                }
            } else if b & 0xE0 == 0xC0 {
                let busy = b & 0x04 != 0
                breakIn = b & 0x02 != 0
                xoff = b & 0x01 != 0
                // Ignore "idle" replies to polls sent just before new text started.
                guard busy || Date().timeIntervalSince(lastSent) > 1 else { continue }
                if !busy {
                    inFlight = 0
                    if let restore = session.takeAfterIdle() {
                        try port.write(restore)
                    }
                }
                let sending = busy || session.hasQueuedText
                publish(session) {
                    if $0.isSending != sending { $0.isSending = sending }
                    if !sending { $0.transcript.clearPending() }
                }
            } else if b < 0x80 {
                // Echo of a character the keyer has just sent.
                if breakIn {
                    publish(session) { $0.transcript.append(Character(UnicodeScalar(b)), from: .paddle) }
                } else {
                    inFlight = max(0, inFlight - 1)
                    if !session.isPreviewing {
                        publish(session) { $0.transcript.append(Character(UnicodeScalar(b)), from: .sent) }
                    }
                }
            }
        }
    }

    private func connectionFailed(_ message: String) {
        session = nil
        isSending = false
        activity = nil
        speed.wpm = nil
        guard let port = selectedPort else { return }
        rescanPorts()
        if !ports.contains(port) {
            // Unplugged: wait for the port to come back, then reconnect.
            state = .failed("WinKeyer disconnected. Waiting for it to come back…")
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.rescanPorts()
                if self.ports.contains(port) {
                    self.connect(to: port)
                }
            }
        } else {
            state = .failed(message)
        }
    }
}

/// One-off moves from the app's earlier name, "WinKeyer Status".
enum Migration {
    private static let doneKey = "MigratedFromWinKeyerStatus"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        if let old = UserDefaults(suiteName: "local.winkeyer-status") {
            for key in ["SelectedPort", "SkipWriteWarning"] where defaults.object(forKey: key) == nil {
                if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
            }
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDir = support.appendingPathComponent("WinKeyer Status/Backups", isDirectory: true)
        let newDir = KeyerModel.backupDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) else { return }
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        for file in files where !fm.fileExists(atPath: newDir.appendingPathComponent(file.lastPathComponent).path) {
            try? fm.copyItem(at: file, to: newDir.appendingPathComponent(file.lastPathComponent))
        }
    }
}
