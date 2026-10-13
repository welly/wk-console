# WK Console

A Mac app for the [K1EL WinKeyer](https://k1elsystems.com/WK3IC.html) Morse keyer. See your speed live, send messages and typed text, and edit the keyer's settings, messages and callsigns. It replaces most of what you'd otherwise do with paddle commands.

WK Console is an independent project. It isn't affiliated with or endorsed by K1EL Systems. "WinKeyer" is K1EL's name for its keyer and is used here only to say what the app works with.

## Features

- **Live speed.** Large WPM display that follows the speed knob, also shown in the menu bar.
- **Send messages.** Your stored messages with short labels, sent with a click or F1–F12. Esc stops sending.
- **Type to send.** Send a line at a time, or as you type.
- **Sent-text transcript.** What the keyer actually sent, from its echo. Paddle sending is underlined.
- **Practice mode.** Key outputs and PTT stay off, so sending only plays sidetone.
- **Keyer settings editor.** Both users' speed, paddle, keying, PTT and sidetone settings, plus messages, callsigns and the active user.
- **Safe writes.** Before every write the app checks the keyer hasn't been changed by another app and backs up its memory. After writing, it reads everything back to verify it.
- **Backups.** Every backup is listed and can be restored.
- **Accessibility.** Adjustable text size (View → Make Text Bigger, ⌘+), high-contrast text colours, VoiceOver labels and Reduce Motion support.

## Tested hardware

So far WK Console has been tested on **one keyer: a WinKeyer 3 IC, firmware 31.104** (it reports IC type 3, which isn't in K1EL's datasheet). It should work with other WinKeyer 3 versions, but that hasn't been checked. Reports from other keyers and firmware are very welcome. Please open an issue.

Some behaviour of firmware 31.104 differs from the [WinKeyer 3 datasheet](https://k1elsystems.com/files/WK3_Datasheet_v1.3.pdf):

- Dump and Load EEPROM use **288 bytes**, not 256.
- Settings byte 8 holds **First Extension**, not X2MODE.
- The Key 1 and Key 2 bits in the pin configuration are the other way round from the datasheet's table. WK Console follows K1EL's own WinKeyerTools app.

## Limitations

Some settings are stored somewhere other than the memory WK Console reads and writes:

- sidetone volume
- Mute
- paddle-only sidetone
- SO2R
- Cut 0/9
- fast command response
- serial number
- the FSK/RTTY options

WK Console can't show or change these yet, and its backups don't include them. Use K1EL's WinKeyerTools for them.

When WK Console sends a message, `/M` is replaced with your callsign. Other embedded commands (`/N`, `/B` etc.) only work when the keyer plays a message from its own memory.

## Safety

- **WK Console keys your transmitter** when it sends messages or text, just as the keyer's own message buttons do. Use practice mode or a dummy load while you get used to it.
- **Writing settings restarts the keyer.** Anything changed with paddle commands but not saved with `X S` is lost.

## Requirements

- macOS 15 or later
- The Xcode command line tools, to build (`xcode-select --install`). The full Xcode app isn't needed.

## Building

```sh
mac/build_app.sh
```

This builds `mac/build/WK Console.app`. Drag it to Applications if you want to keep it.

The app isn't signed with a Developer ID. The first time you open a downloaded copy, right-click it and choose **Open**.

## Command-line tool

`winkeyer_status.py` is a small Python tool used while developing the app. It can show settings and watch the speed. Its `snapshot` command saves the keyer's memory and shows which bytes changed since the last snapshot, which is how the memory layout was worked out.

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python winkeyer_status.py            # show settings
.venv/bin/python winkeyer_status.py watch      # live speed
.venv/bin/python winkeyer_status.py snapshot   # save memory and show changes
```

## Project layout

| Path | What it is |
|---|---|
| `mac/Sources/WKConsole/` | The app (SwiftUI) |
| `mac/Sources/WKConsole/WinKeyer.swift` | WinKeyer protocol and settings layout |
| `mac/Sources/WKConsole/Messages.swift` | Message storage format (Morse-encoded text) |
| `mac/Sources/WKConsole/KeyerModel.swift` | Connection, sending, writing and backups |
| `mac/build_app.sh` | Builds the `.app` bundle |
| `mac/tools/make_icon.swift` | Generates the app icon |
| `winkeyer_status.py` | Command-line tool |

## Licence

Copyright © 2026 Alastair Moore G3AJM

WK Console is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but **without any warranty**; without even the implied warranty of merchantability or fitness for a particular purpose. See [LICENSE](LICENSE) for details.
