import Foundation

/// K1EL WinKeyer protocol, per the "WinKeyer 3.1 IC Interface & Operation Manual" rev 1.3.
/// Admin commands are <0x00><n>; everything else is a host-mode command.
enum WK {
    static let admin: UInt8 = 0x00
    static let reset: UInt8 = 0x01
    static let hostOpen: UInt8 = 0x02
    static let hostClose: UInt8 = 0x03
    static let echo: UInt8 = 0x04
    static let fwMajor: UInt8 = 0x09
    static let dumpEEPROM: UInt8 = 0x0C
    static let loadEEPROM: UInt8 = 0x0D
    static let setWK3Mode: UInt8 = 0x14
    static let readVcc: UInt8 = 0x15
    static let fwMinor: UInt8 = 0x17
    static let icType: UInt8 = 0x18

    static let sidetone: UInt8 = 0x01
    static let setWPM: UInt8 = 0x02
    static let setWeight: UInt8 = 0x03
    static let setupSpeedPot: UInt8 = 0x05
    static let getSpeedPot: UInt8 = 0x07
    static let setPinConfig: UInt8 = 0x09
    static let clearBuffer: UInt8 = 0x0A
    static let setMode: UInt8 = 0x0E
    static let loadDefaults: UInt8 = 0x0F
    static let setFirstExtension: UInt8 = 0x10
    static let getStatus: UInt8 = 0x15
    static let setRatio: UInt8 = 0x17
}

struct DeviceInfo {
    var port: String
    var firmware: String
    var isWK3: Bool
    var icPackage: String?
    var supplyVoltage: String?
}

/// One standalone user's settings block from EEPROM (user 1 at 0x00, user 2 at 0x10).
///
/// Byte layout as observed on firmware 31.104 (it differs from the datasheet,
/// which lists byte 8 as X2MODE; on this keyer it holds First Extension).
struct UserSettings: Equatable {
    static let blockSize = 16

    enum KeyMode: Int, CaseIterable, Identifiable {
        case iambicB = 0, iambicA, ultimatic, bug
        var id: Int { rawValue }
        var name: String { ["Iambic B", "Iambic A", "Ultimatic", "Bug"][rawValue] }
    }

    let user: Int
    var raw: [UInt8]

    init(eeprom: [UInt8], user: Int) {
        let base = UserSettings.offset(user: user)
        self.user = user
        self.raw = Array(eeprom[base..<base + UserSettings.blockSize])
    }

    static func offset(user: Int) -> Int { (user - 1) * blockSize }

    private func byte(_ i: Int) -> Int { Int(raw[i]) }
    private mutating func setByte(_ i: Int, _ v: Int, _ range: ClosedRange<Int>) {
        raw[i] = UInt8(min(max(v, range.lowerBound), range.upperBound))
    }
    private func bit(_ i: Int, _ mask: UInt8) -> Bool { raw[i] & mask != 0 }
    private mutating func setBit(_ i: Int, _ mask: UInt8, _ on: Bool) {
        raw[i] = on ? raw[i] | mask : raw[i] & ~mask
    }
    private func field(_ i: Int, shift: Int, mask: UInt8) -> Int { Int((raw[i] >> UInt8(shift)) & mask) }
    private mutating func setField(_ i: Int, shift: Int, mask: UInt8, _ v: Int) {
        raw[i] = (raw[i] & ~(mask << UInt8(shift))) | ((UInt8(v) & mask) << UInt8(shift))
    }

    // MARK: Speed
    var favoriteWPM: Int { get { byte(1) } set { setByte(1, newValue, 5...99) } }
    var minWPM: Int { get { byte(6) } set { setByte(6, newValue, 5...99) } }
    var wpmRange: Int { get { byte(7) } set { setByte(7, newValue, 0...31) } }
    /// 0 (off) or 10–99: the keyer doesn't accept 1–9. Moving into that gap goes
    /// to 10 when increasing from off, and to 0 when decreasing.
    var farnsworth: Int {
        get { byte(10) }
        set {
            let v = (1...9).contains(newValue) ? (newValue > byte(10) ? 10 : 0) : newValue
            setByte(10, v, 0...99)
        }
    }
    var commandWPM: Int { get { byte(15) } set { setByte(15, newValue, 5...99) } }
    var maxWPM: Int { minWPM + wpmRange }

    // MARK: Mode register (byte 0)
    var modeReg: UInt8 { raw[0] }
    var keyMode: KeyMode {
        get { KeyMode(rawValue: field(0, shift: 4, mask: 0x03))! }
        set { setField(0, shift: 4, mask: 0x03, newValue.rawValue) }
    }
    /// Mode bit 7 is "disable paddle watchdog".
    var watchdogDisabled: Bool { get { bit(0, 0x80) } set { setBit(0, 0x80, newValue) } }
    var paddleSwap: Bool { get { bit(0, 0x08) } set { setBit(0, 0x08, newValue) } }
    var autospace: Bool { get { bit(0, 0x02) } set { setBit(0, 0x02, newValue) } }
    var contestSpacing: Bool { get { bit(0, 0x01) } set { setBit(0, 0x01, newValue) } }

    // MARK: Keying
    var weight: Int { get { byte(3) } set { setByte(3, newValue, 10...90) } }
    var ratio: Int { get { byte(12) } set { setByte(12, newValue, 33...66) } }
    var keyComp: Int { get { byte(9) } set { setByte(9, newValue, 0...250) } }
    var firstExtension: Int { get { byte(8) } set { setByte(8, newValue, 0...250) } }
    var paddleSwitchpoint: Int { get { byte(11) } set { setByte(11, newValue, 10...90) } }

    // MARK: PTT (lead-in and tail are in 10 ms units)
    var leadIn: Int { get { byte(4) } set { setByte(4, newValue, 0...250) } }
    var tail: Int { get { byte(5) } set { setByte(5, newValue, 0...250) } }

    // MARK: Pin configuration (byte 13)
    var pinConfig: UInt8 { raw[13] }
    var pttEnabled: Bool { get { bit(13, 0x01) } set { setBit(13, 0x01, newValue) } }
    var sidetoneEnabled: Bool { get { bit(13, 0x02) } set { setBit(13, 0x02, newValue) } }
    // The datasheet's PINCFG table has these the other way round, but K1EL's
    // WinKeyer 3 settings app shows bit 2 as Key 1 and bit 3 as Key 2.
    var key1Enabled: Bool { get { bit(13, 0x04) } set { setBit(13, 0x04, newValue) } }
    var key2Enabled: Bool { get { bit(13, 0x08) } set { setBit(13, 0x08, newValue) } }
    /// 0...3: wordspace + 1, 2, 4 or 8 dits.
    var hangTime: Int { get { field(13, shift: 4, mask: 0x03) } set { setField(13, shift: 4, mask: 0x03, newValue) } }
    /// 0 normal, 1 dah priority, 2 dit priority.
    var ultimaticPriority: Int { get { field(13, shift: 6, mask: 0x03) } set { setField(13, shift: 6, mask: 0x03, newValue) } }

    // MARK: Sidetone (WK3 mode: value = 62500 / Hz)
    var sidetone: UInt8 { raw[2] }
    /// The keyer can only make 62500 ÷ n Hz, for whole n from 16 to 125. Shown
    /// rounded down, as K1EL's WinKeyerTools does; setting picks the nearest.
    static let sidetoneDivisors = 16...125
    static func sidetoneHz(divisor n: Int) -> Int { 62500 / n }

    var sidetoneHz: Int {
        get { raw[2] == 0 ? 0 : Self.sidetoneHz(divisor: Int(raw[2])) }
        set { raw[2] = UInt8(Self.nearestDivisor(to: newValue)) }
    }

    static func nearestDivisor(to hz: Int) -> Int {
        sidetoneDivisors.min { abs(sidetoneHz(divisor: $0) - hz) < abs(sidetoneHz(divisor: $1) - hz) }!
    }

    /// The pitch rounded to 10 Hz, which is how the app presents it: the real
    /// pitch is within a few Hz in the usual 400–1,000 Hz range.
    var sidetoneDisplayHz: Int {
        get { (sidetoneHz + 5) / 10 * 10 }
        set { sidetoneHz = newValue }
    }

    /// Move to the next available pitch at least 10 Hz up (or down).
    mutating func stepSidetone(up: Bool) {
        let start = raw[2]
        var target = sidetoneDisplayHz
        repeat {
            target += up ? 10 : -10
            sidetoneHz = target
        } while raw[2] == start && target > 400 && target < 4000
    }

    // MARK: X1MODE (byte 14)
    var x1Mode: UInt8 { raw[14] }
    var letterspace: Int { get { field(14, shift: 0, mask: 0x1F) } set { setField(14, shift: 0, mask: 0x1F, newValue) } }
    var tune50: Bool { get { bit(14, 0x20) } set { setBit(14, 0x20, newValue) } }
    /// Only meaningful in user 1's block: which user the keyer uses in standalone mode.
    var selectsUser2: Bool { get { bit(14, 0x80) } set { setBit(14, 0x80, newValue) } }
}

/// How the app adjusts the user's saved settings while it holds the keyer in host mode.
struct HostOptions: Equatable {
    /// Key outputs and PTT off, so sending only plays sidetone.
    var practice = false
    /// Sidetone on even if the saved settings have it off.
    var sidetoneAlwaysOn = true

    /// Mode register bits 6 (paddle echo) and 2 (serial echo).
    static let echoBits: UInt8 = 0x44

    func pinConfig(for s: UserSettings) -> UInt8 {
        var pin = s.pinConfig
        if practice { pin &= ~0x0D }         // PTT (bit 0), Key 1 (bit 2), Key 2 (bit 3)
        if sidetoneAlwaysOn { pin |= 0x02 }
        return pin
    }
}

/// Talks to a WinKeyer over an open serial port. Not thread-safe; use from one thread.
final class Keyer {
    let port: SerialPort

    init(port: SerialPort) {
        self.port = port
    }

    func admin(_ cmd: UInt8, what: String) throws -> UInt8 {
        port.flushInput()
        try port.write([WK.admin, cmd])
        return try port.read(count: 1, timeout: 1, what: what)[0]
    }

    /// Put the keyer in its admin-only state and check that it answers.
    func handshake() throws {
        try port.write([WK.admin, WK.hostClose])
        Thread.sleep(forTimeInterval: 0.2)
        port.flushInput()
        try port.write([WK.admin, WK.echo, 0x55])
        guard try port.readByte(timeout: 1) == 0x55 else {
            throw KeyerError("No response from \(port.path). Is this a WinKeyer, and is another app using it?")
        }
    }

    func identify() throws -> DeviceInfo {
        let major = try admin(WK.fwMajor, what: "firmware version")
        var info = DeviceInfo(port: port.path, firmware: "\(major)", isWK3: major >= 30)
        if info.isWK3 {
            let minor = try admin(WK.fwMinor, what: "firmware minor version")
            info.firmware = String(format: "%d.%02d", major, minor)
            let ic = try admin(WK.icType, what: "IC type")
            info.icPackage = [0: "DIP", 1: "SMT"][ic] ?? "Unknown (\(ic))"
            let vcc = try admin(WK.readVcc, what: "supply voltage")
            if vcc > 0 {
                info.supplyVoltage = String(format: "%.2f V", 26214.0 / Double(vcc) / 100.0)
            }
        }
        return info
    }

    /// The datasheet says 256 bytes, but firmware 31.104 sends 288, so read until quiet.
    func dumpEEPROM() throws -> [UInt8] {
        port.flushInput()
        try port.write([WK.admin, WK.dumpEEPROM])
        let data = try port.readUntilQuiet(quiet: 0.5)
        guard data.count >= 2 * UserSettings.blockSize else {
            throw KeyerError("EEPROM dump too short (\(data.count) bytes)")
        }
        return data
    }

    /// Enter host mode with the user's saved settings, leaving speed on the pot,
    /// so the paddles and sent messages behave as they do in standalone mode.
    /// Echo is always on in host mode so the app can show what's being sent.
    func openHost(with s: UserSettings, options: HostOptions, isWK3: Bool) throws {
        port.flushInput()
        try port.write([WK.admin, WK.hostOpen])
        _ = try port.read(count: 1, timeout: 1, what: "host open response")
        if isWK3 {
            try port.write([WK.admin, WK.setWK3Mode])
        }
        // Load Defaults takes 15 values in this order. X2MODE isn't stored where
        // we can read it, so it's left at its reset value of 0.
        try port.write([
            WK.loadDefaults,
            s.modeReg | HostOptions.echoBits, 0 /* speed from pot */, s.sidetone, UInt8(s.weight),
            UInt8(s.leadIn), UInt8(s.tail), UInt8(s.minWPM), UInt8(s.wpmRange),
            0 /* X2MODE */, UInt8(s.keyComp), UInt8(s.farnsworth), UInt8(s.paddleSwitchpoint),
            UInt8(s.ratio), options.pinConfig(for: s), s.x1Mode,
            WK.setFirstExtension, UInt8(s.firstExtension),
        ])
    }

    /// Write a full EEPROM image (Admin:Load EEPROM). Firmware 31.104 expects
    /// exactly as many bytes as Dump EEPROM returns (288), not the documented 256.
    func loadEEPROM(_ image: [UInt8]) throws {
        port.flushInput()
        try port.write([WK.admin, WK.loadEEPROM] + image)
        // The keyer doesn't acknowledge; wait for it to finish storing, then check it answers.
        Thread.sleep(forTimeInterval: 1.0)
        port.flushInput()
        try port.write([WK.admin, WK.echo, 0x55])
        guard try port.readByte(timeout: 3) == 0x55 else {
            throw KeyerError("The keyer didn't respond after writing its memory.")
        }
    }

    func closeHost() {
        try? port.write([WK.admin, WK.hostClose])
        Thread.sleep(forTimeInterval: 0.1)
    }
}
