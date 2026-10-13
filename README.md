# WK Console

A Mac app for the [K1EL WinKeyer](https://k1elsystems.com/WK3IC.html) Morse keyer. See your speed live, send messages and typed text, and edit the keyer's settings, messages and callsigns. It replaces most of what you'd otherwise do with paddle commands.

WK Console is an independent project. It isn't affiliated with or endorsed by K1EL Systems. "WinKeyer" is K1EL's name for its keyer and is used here only to say what the app works with.

## Features

- **Live speed.** Large WPM display that follows the keyer's speed control, also shown in the menu bar.
- **Send messages.** Your stored messages with short labels, sent with a click or F1–F12. Esc stops sending.
- **Type to send.** Send a line at a time, or as you type.
- **Sent-text transcript.** What the keyer actually sent, from its echo, including your paddle sending. Messages waiting to go out are highlighted, and the highlight shrinks as each letter is sent.
- **Practice mode.** Key outputs and PTT stay off, so sending only plays sidetone.
- **Keyer setup.** Edit both users' speed, paddle, keying, PTT and sidetone settings, plus messages, callsigns and the active user.
- **Safe writes.** Before every write the app checks the keyer hasn't been changed by another app and backs up its memory. After writing, it reads everything back to verify it.
- **Backups.** Every backup is listed and can be restored.
- **Accessibility.** Adjustable text size (View → Make Text Bigger, ⌘+), high-contrast text colours, VoiceOver labels and Reduce Motion support.

## Settings explained

### Keyer

These are stored in the keyer and used whenever it works on its own (standalone). The keyer holds a full set for each of two users; the **Active user** picker in the toolbar chooses which set it uses. Changes are saved to the keyer with **Write to Keyer** (in the bar at the bottom of the window), which backs up the keyer's memory first and restarts the keyer afterwards.

Descriptions are based on K1EL's [WinKeyer 3 datasheet](https://k1elsystems.com/files/WK3_Datasheet_v1.3.pdf).

#### Speed

| Setting | What it does |
|---|---|
| Favourite speed | With the keyer's favourite speed mode on, the speed used when the speed control is turned fully anticlockwise; above that, the speed control works normally. The mode is switched with the paddle command `X` `D`, which WK Console can't change yet. When it's off, the speed control covers its whole range and this setting isn't used. |
| Minimum WPM | The lowest speed the speed control gives. |
| WPM range | How far the speed control goes above the minimum. A minimum of 15 and a range of 15 gives 15–30 WPM. Up to 31. |
| Command speed | The speed of the keyer's own Morse replies in command mode (the `R`, `E` and `?` you hear after pressing the command button). It doesn't affect sending speed. |
| Farnsworth | For code practice. Letters are sent at this speed, with the gaps between them stretched to match your normal sending speed. 0 turns it off; it also has no effect when sending faster than the Farnsworth speed. |

#### Paddle

| Setting | What it does |
|---|---|
| Mode | How the paddles behave. **Iambic A** and **Iambic B** send alternating dits and dahs while both paddles are held; in mode B one extra dit or dah is sent after you let go. **Ultimatic** sends a continuous stream of whichever paddle was pressed last. **Bug** sends dits automatically and dahs by hand; it also works as a straight key on the dah paddle. |
| Ultimatic priority | In Ultimatic mode, what happens when both paddles are pressed: **Normal** (last pressed wins), or always **Dah** or always **Dit**. |
| Hang time | How long PTT stays on after you stop sending with the paddles: a word space plus 1, 2, 4 or 8 dits. Because it's measured in dits, it scales with your speed. |
| Switchpoint | How soon after a dit or dah the keyer starts listening for the next paddle press, as a percentage of a dit (50 = one dit). Too low can send unwanted dits or dahs; too high stops you sending ahead. Faster operators often prefer a little below 50. |
| Letterspace | Extra space between letters, from 0% (standard) to 62% in steps of 2%. Useful with auto space if its timing feels strict. |
| Auto space | If you pause for more than a dit between elements, the keyer treats it as the end of a letter and holds the next one until a full letter space has passed, giving evenly spaced sending. |
| Swap paddles | Swaps the dit and dah sides, e.g. for left-handed operators or a reversed cable. |
| Disable paddle watchdog | The watchdog turns the key output off after 128 dits or dahs in a row, in case a paddle sticks or something rests on it. Sidetone carries on so you notice. Tick this only if you need to send very long runs. |

#### Keying

| Setting | What it does |
|---|---|
| Weight | The length of dits and dahs relative to the spaces between them, from 10% to 90%. 50 is standard; higher sounds heavier, lower sounds lighter. Sending speed doesn't change. |
| Ratio | The length of a dah compared with a dit. 50 is the standard 1:3; 33 gives 1:2 and 66 gives 1:4. |
| Compensation | A fixed number of milliseconds added to every dit and dah, to make up for transceivers that shorten them when switching to transmit (often noticeable at high speed with QSK). Unlike weight, it doesn't scale with speed, so large values can run elements together at high speed. |
| First extension | Milliseconds added to the first dit or dah of a transmission only, for radios that clip the start of keying while switching from receive to transmit. |
| Contest (CT) spacing | Shortens the space between words from seven dits to six, as some contesters prefer. |
| Key 1 output / Key 2 output | Which of the keyer's two key outputs (radio connections) is used. Most setups use Key 1. |
| Tune at 50% duty | When you tune (hold the key down), send a 50% on/off pattern instead of a continuous carrier, to reduce the load on the transmitter or amplifier. |

#### Push to talk

| Setting | What it does |
|---|---|
| Enable PTT | Turns on the PTT output, which switches a transmitter or amplifier to transmit before keying starts. |
| Lead-in | How long PTT is on before keying starts, in milliseconds (steps of 10 ms, up to 2,500 ms). |
| Tail | How long PTT stays on after messages and sending from WK Console finish: three dits plus this many milliseconds (steps of 10 ms). Paddle sending uses hang time instead. |

#### Sidetone

| Setting | What it does |
|---|---|
| Enable sidetone | Whether the keyer's sidetone (its own audio) sounds while you send. Command mode replies always sound. |
| Frequency | The sidetone pitch. The keyer can only make certain pitches, so WK Console picks the nearest and shows it to the nearest 10 Hz. **▶** plays a short preview without keying the radio. |

### Messages

| Setting | What it does |
|---|---|
| Callsigns | One per user. Insert it in any message with `/M`. |
| Messages F1–F12 | Twelve stored messages in two banks of six. The keyer holds up to 240 characters across all messages and both callsigns. |
| Labels | Short names shown on the Operate page and in the menus. They're kept by WK Console rather than the keyer, and save straight away. Leave one blank to use the message's first word. |
| Embedded commands | Codes such as `/N` (serial number) or `/W05` (wait 5 seconds) typed into a message. The full list is at the bottom of the Messages page. When WK Console sends a message, only `/M` is expanded; the others work when the keyer plays the message itself. |

### App settings (WK Console → Settings, ⌘,)

These only affect WK Console, not the keyer.

| Setting | What it does |
|---|---|
| Connection | Which serial port the keyer is on. WK Console finds it automatically when there's only one USB serial device. |
| Practice mode | While WK Console is connected, keeps the key outputs and PTT off, so anything sent only plays sidetone. Also in the Send menu and on the Operate page. |
| Sidetone | **Always on** gives you sidetone while connected even if the keyer's saved setting has it off. **Follow saved setting** uses the keyer's own setting. |
| Send as you type | Sends each character as you type it, instead of a line at a time when you press Return. |
| Text size | Makes all the app's text larger: Standard to Largest. Also View → Make Text Bigger (⌘+) / Smaller (⌘−) / Actual Size (⌘0). |
| Show speed in the menu bar | Shows the live WPM in the menu bar, with quick access to your messages. |
| Confirm before writing to the keyer | Asks before each write, as a reminder that writing restarts the keyer. |

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
