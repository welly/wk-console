import Foundation

/// How the keyer stores message text: one byte per character, holding its Morse
/// elements least-significant bit first (dit = 0, dah = 1) followed by a 1 marker
/// bit. Bit 7 flags the last character of a message. Word spaces are 0x1C.
/// Embedded commands such as /M are stored as ordinary characters.
enum MorseText {
    static let space: UInt8 = 0x1C
    static let endFlag: UInt8 = 0x80

    private static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.",
        "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.",
        "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-",
        "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.", "=": "-...-",
        "+": ".-.-.", "-": "-....-", "(": "-.--.", ")": "-.--.-", "'": ".----.",
        "\"": ".-..-.", ":": "---...", "@": ".--.-.",
    ]

    private static let encodeMap: [Character: UInt8] = table.mapValues { code in
        var v: UInt8 = 0
        for (i, e) in code.enumerated() where e == "-" { v |= 1 << UInt8(i) }
        return v | (1 << UInt8(code.count))
    }

    private static let decodeMap: [UInt8: Character] = {
        var m = Dictionary(uniqueKeysWithValues: encodeMap.map { ($1, $0) })
        m[space] = " "
        return m
    }()

    /// Characters in `text` that can't be stored.
    static func unsupported(in text: String) -> [Character] {
        var seen: [Character] = []
        for c in text.uppercased() where c != " " && encodeMap[c] == nil && !seen.contains(c) {
            seen.append(c)
        }
        return seen
    }

    static func encode(_ text: String) throws -> [UInt8] {
        let bad = unsupported(in: text)
        guard bad.isEmpty else {
            throw KeyerError("Can't store \(bad.map { "“\($0)”" }.joined(separator: ", ")) in a message.")
        }
        var bytes = text.uppercased().map { $0 == " " ? space : encodeMap[$0]! }
        if !bytes.isEmpty {
            bytes[bytes.count - 1] |= endFlag
        }
        return bytes
    }

    static func decode(_ bytes: [UInt8]) -> String {
        String(bytes.map { decodeMap[$0 & ~endFlag] ?? "\u{FFFD}" })
    }
}

/// The 12 messages and 2 callsigns stored in EEPROM.
///
/// Layout observed on firmware 31.104:
///   0x20         next free offset (relative to 0x20)
///   0x21...0x2C  offsets of messages 1–12 (0 = empty)
///   0x2D, 0x2E   offsets of the user 1 and user 2 callsigns
///   0x2F...      text, packed in slot order with no gaps
/// Offsets are single bytes, so text can extend to 0x11F: 240 bytes in all.
struct MessageStore: Equatable {
    static let slotCount = 14
    static let tableStart = 0x20
    static let dataOffset = 0x0F
    static let capacity = 0xFF - dataOffset
    static let user1Call = 12
    static let user2Call = 13

    /// Message 1–12 text, then the user 1 and user 2 callsigns.
    var slots: [String]
    /// Bytes as read, reused when a slot's text is unchanged so that anything
    /// this app doesn't decode survives a write untouched.
    private let original: [String: [UInt8]]

    init(eeprom: [UInt8]) {
        var slots: [String] = []
        var original: [String: [UInt8]] = [:]
        for i in 0..<Self.slotCount {
            let offset = Int(eeprom[Self.tableStart + 1 + i])
            var bytes: [UInt8] = []
            if offset != 0 {
                var p = Self.tableStart + offset
                while p < eeprom.count {
                    bytes.append(eeprom[p])
                    if eeprom[p] & MorseText.endFlag != 0 { break }
                    p += 1
                }
            }
            let text = MorseText.decode(bytes)
            slots.append(text)
            original[text] = bytes
        }
        self.slots = slots
        self.original = original
    }

    static func == (a: MessageStore, b: MessageStore) -> Bool { a.slots == b.slots }

    private func bytes(for text: String) throws -> [UInt8] {
        if let b = original[text] { return b }
        return try MorseText.encode(text)
    }

    /// Characters used, counting unsupported characters as one each.
    var used: Int { slots.reduce(0) { $0 + $1.count } }

    /// Rewrite the message area of `image` with the current slots.
    func apply(to image: inout [UInt8]) throws {
        let encoded = try slots.map(bytes(for:))
        let total = encoded.reduce(0) { $0 + $1.count }
        guard total <= Self.capacity else {
            throw KeyerError("Messages and callsigns use \(total) characters; the keyer holds \(Self.capacity).")
        }
        var offset = Self.dataOffset
        for (i, bytes) in encoded.enumerated() {
            image[Self.tableStart + 1 + i] = bytes.isEmpty ? 0 : UInt8(offset)
            image.replaceSubrange(Self.tableStart + offset..<Self.tableStart + offset + bytes.count, with: bytes)
            offset += bytes.count
        }
        image[Self.tableStart] = UInt8(offset)
        for p in (Self.tableStart + offset)..<min(image.count, Self.tableStart + 0x100) {
            image[p] = 0
        }
    }
}
