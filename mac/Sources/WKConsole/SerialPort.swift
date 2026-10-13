import Darwin
import Foundation

struct KeyerError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Minimal POSIX serial port: 1200 baud, 8 data bits, no parity, 2 stop bits.
final class SerialPort {
    // ioctl request codes from <sys/ttycom.h>; the macros don't import into Swift.
    private static let TIOCEXCL: UInt = 0x2000_740D
    private static let TIOCMBIS: UInt = 0x8004_746C
    private static let TIOCMBIC: UInt = 0x8004_746B

    let path: String
    private var fd: Int32 = -1

    init(path: String) throws {
        self.path = path
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            let reason = errno == EBUSY ? "it is in use by another app" : String(cString: strerror(errno))
            throw KeyerError("Can't open \(path): \(reason)")
        }
        // Exclusive access, so other apps can't talk to the keyer while we hold it.
        _ = ioctl(fd, SerialPort.TIOCEXCL)

        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        cfsetispeed(&t, speed_t(B1200))
        cfsetospeed(&t, speed_t(B1200))
        t.c_cflag |= tcflag_t(CS8 | CSTOPB | CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(PARENB | CRTSCTS)
        // Blocking reads that return after at most 0.1 s with whatever has arrived.
        withUnsafeMutableBytes(of: &t.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 1
        }
        guard tcsetattr(fd, TCSANOW, &t) == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd)
            throw KeyerError("Can't configure \(path): \(reason)")
        }
        _ = fcntl(fd, F_SETFL, 0)

        // Many WinKeyer USB adapters misbehave unless DTR is set and RTS is clear.
        var dtr = TIOCM_DTR
        _ = ioctl(fd, SerialPort.TIOCMBIS, &dtr)
        var rts = TIOCM_RTS
        _ = ioctl(fd, SerialPort.TIOCMBIC, &rts)
    }

    deinit { close() }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                throw KeyerError("Write to \(path) failed: \(String(cString: strerror(errno)))")
            }
            offset += n
        }
    }

    func flushInput() {
        tcflush(fd, TCIFLUSH)
    }

    /// Read one byte, or nil if nothing arrives within `timeout` seconds.
    func readByte(timeout: TimeInterval) throws -> UInt8? {
        let deadline = Date().addingTimeInterval(timeout)
        var byte: UInt8 = 0
        repeat {
            let n = Darwin.read(fd, &byte, 1)
            if n == 1 { return byte }
            if n < 0 && errno != EINTR && errno != EAGAIN {
                throw KeyerError("Read from \(path) failed: \(String(cString: strerror(errno)))")
            }
        } while Date() < deadline
        return nil
    }

    func read(count: Int, timeout: TimeInterval, what: String) throws -> [UInt8] {
        var out: [UInt8] = []
        let deadline = Date().addingTimeInterval(timeout)
        while out.count < count {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, let b = try readByte(timeout: remaining) else {
                throw KeyerError("Timed out reading \(what) (got \(out.count)/\(count) bytes)")
            }
            out.append(b)
        }
        return out
    }

    /// Read until the line has been quiet for `quiet` seconds.
    func readUntilQuiet(quiet: TimeInterval) throws -> [UInt8] {
        var out: [UInt8] = []
        while let b = try readByte(timeout: quiet) {
            out.append(b)
        }
        return out
    }

    /// Likely WinKeyer ports (USB serial adapters) and all callout ports.
    static func availablePorts() -> (candidates: [String], all: [String]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let all = names.filter { $0.hasPrefix("cu.") }.sorted().map { "/dev/" + $0 }
        let candidates = all.filter { $0.contains("usbserial") || $0.contains("usbmodem") }
        return (candidates, all)
    }
}
