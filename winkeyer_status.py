#!/usr/bin/env python3
"""Read and display the settings of a K1EL WinKeyer (WK2/WK3) over its serial port.

Protocol reference: K1EL "WinKeyer 3.1 IC Interface & Operation Manual" rev 1.3.
The keyer talks 1200 baud, 8 data bits, no parity, 2 stop bits.

Settings are read from the keyer's EEPROM (Admin:Dump EEPROM) because the
Admin:Get Values command is not supported on WK3. Nothing is written to the
keyer; the only state change is a brief Host Open/Close to read the speed pot.
"""

import argparse
import json
import os
import signal
import sys
import time

import serial
from serial.tools import list_ports

BAUD = 1200

# Admin commands are <0x00><n>.
ADMIN = 0x00
ADMIN_HOST_OPEN = 0x02
ADMIN_HOST_CLOSE = 0x03
ADMIN_ECHO = 0x04
ADMIN_FW_MAJOR = 0x09
ADMIN_DUMP_EEPROM = 0x0C
ADMIN_READ_VCC = 0x15
ADMIN_FW_MINOR = 0x17
ADMIN_IC_TYPE = 0x18
ADMIN_SET_WK3_MODE = 0x14

CMD_SIDETONE = 0x01
CMD_SET_WPM = 0x02
CMD_SET_WEIGHT = 0x03
CMD_SETUP_SPEED_POT = 0x05
CMD_GET_SPEED_POT = 0x07
CMD_SET_MODE = 0x0E
CMD_GET_STATUS = 0x15
CMD_SET_RATIO = 0x17

# Settings block as listed in the datasheet's "Versions Compared" table (WK3 v30).
# EEPROM holds one block per standalone user: user 1 at 0x00, user 2 at 0x10.
USER_BLOCK_SIZE = 16
SETTING_NAMES = [
    "MODEREG", "WPM", "SIDETONE", "WEIGHT", "LEADIN", "TAIL", "MINWPM",
    "WPMRANGE", "X2MODE", "KCOMP", "FARNSWPM", "PADDLE_SETPOINT", "RATIO",
    "PINCFG", "X1MODE", "CMDWPM",
]

KEY_MODES = {0: "Iambic B", 1: "Iambic A", 2: "Ultimatic", 3: "Bug"}
ULTIMATIC_PRIORITY = {0: "Normal", 1: "Dah priority", 2: "Dit priority", 3: "Undefined"}
HANG_TIME = {0: "1 wordspace + 1 dit", 1: "1 wordspace + 2 dits",
             2: "1 wordspace + 4 dits", 3: "1 wordspace + 8 dits"}
WK12_SIDETONE_HZ = {1: 4000, 2: 2000, 3: 1333, 4: 1000, 5: 800,
                    6: 666, 7: 571, 8: 500, 9: 444, 10: 400}


class WinKeyerError(Exception):
    pass


class WinKeyer:
    def __init__(self, port, timeout=1.0):
        try:
            self.ser = serial.Serial(port, BAUD, bytesize=8, parity="N",
                                     stopbits=2, timeout=timeout)
        except serial.SerialException as e:
            raise WinKeyerError(f"cannot open {port}: {e}") from e
        # Many WinKeyer USB adapters reset or misbehave without DTR/RTS set.
        self.ser.dtr = True
        self.ser.rts = False
        time.sleep(0.2)
        self.ser.reset_input_buffer()

    def close(self):
        self.ser.close()

    def _read(self, n, what):
        data = self.ser.read(n)
        if len(data) != n:
            raise WinKeyerError(f"timeout reading {what} (got {len(data)}/{n} bytes)")
        return data

    def admin(self, cmd, nbytes=1, what="admin response"):
        self.ser.reset_input_buffer()
        self.ser.write(bytes([ADMIN, cmd]))
        return self._read(nbytes, what)

    def echo_test(self):
        self.ser.reset_input_buffer()
        self.ser.write(bytes([ADMIN, ADMIN_ECHO, 0x55]))
        return self.ser.read(1) == b"\x55"

    def dump_eeprom(self):
        # The datasheet says 256 bytes, but some firmware (e.g. 31.104) sends
        # 288, so read until the keyer goes quiet rather than a fixed count.
        self.ser.reset_input_buffer()
        self.ser.write(bytes([ADMIN, ADMIN_DUMP_EEPROM]))
        old = self.ser.timeout
        self.ser.timeout = 0.5
        data = bytearray()
        try:
            while True:
                chunk = self.ser.read(64)
                if not chunk:
                    break
                data += chunk
        finally:
            self.ser.timeout = old
        if len(data) < 2 * USER_BLOCK_SIZE:
            raise WinKeyerError(f"EEPROM dump too short ({len(data)} bytes)")
        return bytes(data)

    def read_unsolicited(self, mask, tag, what, timeout=1.0):
        """Wait for a byte whose top bits match tag, skipping echo/other bytes."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            b = self.ser.read(1)
            if b and (b[0] & mask) == tag:
                return b[0]
        raise WinKeyerError(f"timeout waiting for {what}")

    def host_session_read(self):
        """Open host mode briefly to read the speed pot and status byte."""
        self.ser.reset_input_buffer()
        self.ser.write(bytes([ADMIN, ADMIN_HOST_OPEN]))
        version = self._read(1, "host open version")[0]
        try:
            self.ser.write(bytes([CMD_GET_SPEED_POT]))
            pot = self.read_unsolicited(0xC0, 0x80, "speed pot byte") & 0x3F
            self.ser.write(bytes([CMD_GET_STATUS]))
            status = self.read_unsolicited(0xE0, 0xC0, "status byte")
        finally:
            self.ser.write(bytes([ADMIN, ADMIN_HOST_CLOSE]))
            self.ser.flush()
            time.sleep(0.1)
        return version, pot, status


def find_ports():
    ports = [p.device for p in list_ports.comports()]
    # macOS: prefer the callout (cu.*) devices from USB serial adapters.
    candidates = [p for p in ports if "usbserial" in p or "usbmodem" in p
                  or "ttyUSB" in p or "ttyACM" in p]
    if sys.platform == "darwin":
        candidates = [p for p in candidates if "/cu." in p] or candidates
    return candidates, ports


def decode_settings(eeprom, user):
    base = (user - 1) * USER_BLOCK_SIZE
    return dict(zip(SETTING_NAMES, eeprom[base:base + USER_BLOCK_SIZE]))


def describe(raw, wk3=True):
    out = {}
    mode = raw["MODEREG"]
    out["Favourite speed (WPM)"] = "speed pot" if raw["WPM"] == 0 else raw["WPM"]
    out["Speed pot range"] = f'{raw["MINWPM"]}-{raw["MINWPM"] + raw["WPMRANGE"]} WPM'
    out["Command speed (WPM)"] = raw["CMDWPM"]
    out["Farnsworth (WPM)"] = raw["FARNSWPM"] or "off"

    st = raw["SIDETONE"]
    if wk3:
        out["Sidetone frequency"] = f"{62500 // st} Hz" if st else "off"
    else:
        hz = WK12_SIDETONE_HZ.get(st & 0x0F)
        out["Sidetone frequency"] = f"{hz} Hz" if hz else f"unknown (0x{st:02X})"
        out["Paddle-only sidetone"] = bool(st & 0x80)

    out["Key mode"] = KEY_MODES[(mode >> 4) & 0x03]
    out["Paddle swap"] = bool(mode & 0x08)
    out["Autospace"] = bool(mode & 0x02)
    out["Contest spacing"] = bool(mode & 0x01)
    out["Paddle watchdog"] = not (mode & 0x80)
    out["Paddle echoback"] = bool(mode & 0x40)
    out["Serial echoback"] = bool(mode & 0x04)

    out["Weight (%)"] = raw["WEIGHT"]
    out["Dit/dah ratio"] = f'1:{3 * raw["RATIO"] / 50:.2f} (setting {raw["RATIO"]})'
    out["Key compensation (ms)"] = raw["KCOMP"]
    out["Paddle switchpoint (%)"] = raw["PADDLE_SETPOINT"]
    out["PTT lead-in (ms)"] = raw["LEADIN"] * 10
    out["PTT tail (ms, + 3 dits)"] = raw["TAIL"] * 10

    pin = raw["PINCFG"]
    out["PTT enabled"] = bool(pin & 0x01)
    out["Sidetone enabled"] = bool(pin & 0x02)
    # The datasheet's PINCFG table has these the other way round, but K1EL's
    # WinKeyer 3 settings app shows bit 2 as Key 1 and bit 3 as Key 2.
    out["Key out 1 enabled"] = bool(pin & 0x04)
    out["Key out 2 enabled"] = bool(pin & 0x08)
    out["Paddle hang time"] = HANG_TIME[(pin >> 4) & 0x03]
    out["Ultimatic priority"] = ULTIMATIC_PRIORITY[(pin >> 6) & 0x03]

    if wk3:
        x1, x2 = raw["X1MODE"], raw["X2MODE"]
        out["Message bank"] = 2 if x1 & 0x40 else 1
        out["Tune 50% duty"] = bool(x1 & 0x20)
        out["Letterspace adjust (%)"] = (x1 & 0x1F) * 2
        out["Paddle-only sidetone"] = bool(x2 & 0x08)
        out["Paddle mute"] = bool(x2 & 0x02)
        out["SO2R mode"] = bool(x2 & 0x04)
        out["Cut 0 -> T"] = bool(x2 & 0x10)
        out["Cut 9 -> N"] = bool(x2 & 0x20)
        out["Fast command response"] = bool(x2 & 0x40)
    return out


def describe_status(status):
    return {
        "Waiting": bool(status & 0x10),
        "Key down": bool(status & 0x08),
        "Busy sending": bool(status & 0x04),
        "Paddle break-in": bool(status & 0x02),
        "Buffer XOFF": bool(status & 0x01),
    }


def hexdump(data):
    lines = []
    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        hx = " ".join(f"{b:02X}" for b in chunk)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{i:02X}: {hx:<47}  {asc}")
    return "\n".join(lines)


def fmt(v):
    if v is True:
        return "yes"
    if v is False:
        return "no"
    return str(v)


def print_section(title, items):
    print(f"\n{title}")
    print("-" * len(title))
    width = max(len(k) for k in items)
    for k, v in items.items():
        print(f"  {k:<{width}}  {fmt(v)}")


def cmd_ports(_args):
    candidates, ports = find_ports()
    if not ports:
        print("No serial ports found.")
    for p in ports:
        print(("* " if p in candidates else "  ") + p)
    if candidates:
        print("\n* = likely USB serial device")


def resolve_port(args):
    if args.port:
        return args.port
    candidates, _ = find_ports()
    if not candidates:
        raise WinKeyerError("no USB serial port found; plug in the WinKeyer or pass --port")
    if len(candidates) > 1:
        raise WinKeyerError("several USB serial ports found, pick one with --port: "
                            + ", ".join(candidates))
    return candidates[0]


def connect(port):
    wk = WinKeyer(port)
    # Make sure we start with the host interface closed (admin-only state).
    wk.ser.write(bytes([ADMIN, ADMIN_HOST_CLOSE]))
    time.sleep(0.2)
    if not wk.echo_test():
        wk.close()
        raise WinKeyerError(f"no echo from {port}; is this a WinKeyer?")
    return wk


def cmd_watch(args):
    # Treat SIGTERM like Ctrl-C so the keyer is always returned to standalone mode.
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    port = resolve_port(args)
    wk = connect(port)
    try:
        is_wk3 = wk.admin(ADMIN_FW_MAJOR, what="firmware major")[0] >= 30
        eeprom = wk.dump_eeprom()
        user = 2 if is_wk3 and eeprom[14] & 0x80 else 1
        raw = decode_settings(eeprom, user)
        min_wpm, max_wpm = raw["MINWPM"], raw["MINWPM"] + raw["WPMRANGE"]

        wk.ser.reset_input_buffer()
        wk.ser.write(bytes([ADMIN, ADMIN_HOST_OPEN]))
        wk._read(1, "host open version")
        try:
            # Host mode starts from defaults, so carry over the saved settings
            # that affect how the paddles sound, and let the pot set the speed.
            if is_wk3:
                wk.ser.write(bytes([ADMIN, ADMIN_SET_WK3_MODE]))
            wk.ser.write(bytes([
                CMD_SET_MODE, raw["MODEREG"],
                CMD_SIDETONE, raw["SIDETONE"],
                CMD_SET_WEIGHT, raw["WEIGHT"],
                CMD_SET_RATIO, raw["RATIO"],
                CMD_SETUP_SPEED_POT, min_wpm, raw["WPMRANGE"], 0,
                CMD_SET_WPM, 0,
            ]))
            print(f"Watching {port} (speed pot range {min_wpm}-{max_wpm} WPM). "
                  "Ctrl-C to stop.", flush=True)
            watch_loop(wk, min_wpm, args.interval,
                       log=args.log or not sys.stdout.isatty())
        finally:
            wk.ser.write(bytes([ADMIN, ADMIN_HOST_CLOSE]))
            wk.ser.flush()
            time.sleep(0.1)
    except KeyboardInterrupt:
        print()
    except serial.SerialException as e:
        raise WinKeyerError(f"lost connection to {port}: {e}") from e
    finally:
        wk.close()


def watch_loop(wk, min_wpm, interval, log):
    """Show the speed whenever it changes.

    On a terminal the speed is redrawn in place; with `log` (or when output is
    piped) each change is printed on its own timestamped line.

    The keyer sends a speed pot byte by itself when the knob moves; polling
    every `interval` seconds is a fallback in case one is missed.
    """
    wk.ser.timeout = 0.1
    last_wpm = None
    next_poll = 0.0
    while True:
        now = time.monotonic()
        if now >= next_poll:
            wk.ser.write(bytes([CMD_GET_SPEED_POT]))
            next_poll = now + interval
        b = wk.ser.read(1)
        if not b or (b[0] & 0xC0) != 0x80:
            continue  # nothing, or a status/echo byte
        wpm = min_wpm + (b[0] & 0x3F)
        if wpm != last_wpm:
            if log:
                print(f"{time.strftime('%H:%M:%S')}  {wpm:3d} WPM", flush=True)
            else:
                print(f"\r\033[K  {wpm:3d} WPM", end="", flush=True)
            last_wpm = wpm


SNAPSHOT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "snapshots")


def diff_bytes(old, new):
    """Return [(offset, old, new)] for every byte that differs."""
    n = max(len(old), len(new))
    pad = lambda b: b + bytes(n - len(b))
    return [(i, a, b) for i, (a, b) in enumerate(zip(pad(old), pad(new))) if a != b]


def cmd_snapshot(args):
    port = resolve_port(args)
    wk = connect(port)
    try:
        eeprom = wk.dump_eeprom()
    finally:
        wk.close()

    os.makedirs(SNAPSHOT_DIR, exist_ok=True)
    previous = sorted(f for f in os.listdir(SNAPSHOT_DIR) if f.endswith(".bin"))
    name = time.strftime("%Y%m%d-%H%M%S") + (f"-{args.label}" if args.label else "") + ".bin"
    path = os.path.join(SNAPSHOT_DIR, name)
    with open(path, "wb") as f:
        f.write(eeprom)
    print(f"Saved {len(eeprom)} bytes to snapshots/{name}")

    if not previous:
        return
    with open(os.path.join(SNAPSHOT_DIR, previous[-1]), "rb") as f:
        old = f.read()
    changes = diff_bytes(old, eeprom)
    print(f"Compared with {previous[-1]}: ", end="")
    if not changes:
        print("no changes")
        return
    print(f"{len(changes)} byte(s) changed")
    for off, a, b in changes:
        print(f"  0x{off:03X}: 0x{a:02X} ({a:3d}) -> 0x{b:02X} ({b:3d})")


def cmd_status(args):
    port = resolve_port(args)
    wk = connect(port)
    try:

        fw_major = wk.admin(ADMIN_FW_MAJOR, what="firmware major")[0]
        is_wk3 = fw_major >= 30
        info = {"Port": port, "Firmware": str(fw_major)}
        if is_wk3:
            fw_minor = wk.admin(ADMIN_FW_MINOR, what="firmware minor")[0]
            info["Firmware"] = f"{fw_major}.{fw_minor:02d}"
            ic = wk.admin(ADMIN_IC_TYPE, what="IC type")[0]
            info["IC package"] = {0: "DIP", 1: "SMT"}.get(ic, f"unknown ({ic})")
            vcc = wk.admin(ADMIN_READ_VCC, what="Vcc")[0]
            if vcc:
                info["Supply voltage"] = f"{26214 / vcc / 100:.2f} V"

        eeprom = wk.dump_eeprom()
        active_user = 2 if is_wk3 and eeprom[14] & 0x80 else 1
        user = args.user or active_user
        raw = decode_settings(eeprom, user)
        settings = describe(raw, wk3=is_wk3)
        info["Active user"] = active_user

        live = {}
        if not args.no_pot:
            _version, pot, status = wk.host_session_read()
            live["Speed pot (WPM)"] = raw["MINWPM"] + pot
            live.update(describe_status(status))
    finally:
        wk.close()

    if args.json:
        print(json.dumps({"device": info, "user": user, "settings": settings, "live": live,
                          "raw": raw, "eeprom": eeprom.hex()}, indent=2))
        return

    print_section("WinKeyer", info)
    print_section(f"Saved settings, user {user} (EEPROM)", settings)
    if live:
        print_section("Live", live)
    print("\nnote: sidetone volume can't be read; WK3 has no read-back command and "
          "changing it (X W, X S) did not alter the EEPROM dump on firmware 31.104.")
    if args.raw:
        print_section("Raw settings bytes", {k: f"0x{v:02X} ({v})" for k, v in raw.items()})
        print("\nEEPROM dump")
        print("-----------")
        print(hexdump(eeprom))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Show the settings of a K1EL WinKeyer.")
    ap.add_argument("-p", "--port", help="serial port (default: auto-detect)")
    sub = ap.add_subparsers(dest="command")
    sub.add_parser("ports", help="list serial ports")
    sn = sub.add_parser("snapshot", help="save the EEPROM to snapshots/ and show changes since the last one")
    sn.add_argument("label", nargs="?", help="optional label, e.g. what you just changed")
    wt = sub.add_parser("watch", help="continuously show WPM as the speed pot changes")
    wt.add_argument("--interval", type=float, default=0.5,
                    help="seconds between speed pot polls (default: 0.5)")
    wt.add_argument("--log", action="store_true",
                    help="print each change on a new timestamped line")
    st = sub.add_parser("status", help="show keyer settings (default)")
    for p in (ap, st):
        p.add_argument("--json", action="store_true", help="output JSON")
        p.add_argument("--raw", action="store_true", help="also show raw bytes and EEPROM dump")
        p.add_argument("--user", type=int, choices=(1, 2),
                       help="show this standalone user's settings (default: active user)")
        p.add_argument("--no-pot", action="store_true",
                       help="skip host-mode read of speed pot and status")
    args = ap.parse_args(argv)

    try:
        if args.command == "ports":
            cmd_ports(args)
        elif args.command == "snapshot":
            cmd_snapshot(args)
        elif args.command == "watch":
            cmd_watch(args)
        else:
            cmd_status(args)
    except (WinKeyerError, serial.SerialException) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
