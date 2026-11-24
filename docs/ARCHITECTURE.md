# Architecture

```text
UIKit multi-touch surface
  → canonical GamepadState
  → full-state binary frames, Network.framework loopback TCP listener
  → iPhone usbmux service → physical USB cable → macOS usbmuxd
  → serial CableSession worker → GamepadOutput
                                ├─ input monitor
                                ├─ keyboard/mouse mapper → CGEvent (Accessibility)
                                └─ IOHIDUserDevice (requires authorization)
```

The iPhone supplies a listening port; the Mac initiates the connection through `/var/run/usbmuxd`. USBMux ListDevices and Connect messages use its length-prefixed XML-plist protocol. Only `ConnectionType == USB` is eligible. The Connect port field is network byte order inside the plist. The implementation is independent code; the wire protocol is documented by [libusbmuxd](https://github.com/libimobiledevice/libusbmuxd) and Apple's running local service.

The listener is loopback-only and accepts one Mac connection. The host sends ASCII `IPGP/1\n`; the phone validates it before sending input. This is version negotiation, not cryptographic authentication. The existing iPhone/Mac USB trust relationship and loopback binding are the prototype's trust boundary. Wireless transports use separate pairing/authentication paths; see Wireless transport additions below.

## Input wire format

All integers are little-endian. Each frame is exactly 28 bytes; TCP packet boundaries are irrelevant.

| Offset | Size | Meaning |
| --- | --- | --- |
| 0 | 4 | ASCII IPGP |
| 4 | 1 | Version 1 |
| 5 | 1 | Type 1: complete state |
| 6 | 1 | Pause flag: 0 normal, 1 layout editor (all controls must be neutral) |
| 7 | 1 | Pointer mode: 0 Mac profile fallback, 1 desktop cursor, 2 relative aim |
| 8 | 4 | Sequence, increments by one with UInt32 wrapping |
| 12 | 2 | Buttons: south, east, west, north, LB, RB, back, start, L3, R3 |
| 14 | 1 | Hat: north=0, clockwise through northwest=7, released=8 |
| 15 | 1 | Reserved, zero |
| 16 | 8 | Int16 LX, LY, RX, RY, range -32767…32767; positive Y is down |
| 24 | 2 | LT, RT; v1 permits only 0 or 255 |
| 26 | 2 | Custom button bits 0–15 (slots 1–16) |

The sender emits changed state immediately, plus 60 Hz heartbeats. Only one send is in flight; queued frames preserve short button edges. A queue cap and 200 ms send deadline close stalled connections. The receiver requires a complete frame within 250 ms, validates all fields and sequence order, and closes/retries on malformed, missing, or out-of-order input. These are timeouts, not measured latency guarantees.

Every transport failure resets output. Stop, quit, and Mac sleep close the session and remove the virtual device or release generated keys; iPhone inactivity stops its listener. The worker owns HID writes, while get-report callbacks use a separate queue and locked snapshot. UI updates are dispatched to the main queue. Older receivers reject the newly used pause flag, so update both apps together.

## Keyboard/mouse output

The Mac saves a keyboard profile independently of the phone's Xbox/PS layout. Semantic controls map to up to four ordered keys/mouse buttons with hold or tap behavior. A pure state machine schedules presses, reverse-order releases, and reference-counted shared inputs. A serial output queue targets 1000 Hz (selectable 250/500/1000 Hz); right-stick mouse displacement depends on elapsed time, not incoming frame count. Exponential velocity smoothing is integrated over elapsed time, with configurable 0–80 ms response (25 ms default). Dead-zone entry and resets clear velocity immediately; long scheduling gaps are capped at 20 ms to avoid catch-up jumps. Movement events retain fractional pixel remainders and carry Core Graphics' non-coalesced movement flag.

The output gate checks Accessibility permission, selected application focus, the pause flag, and a 250 ms heartbeat deadline. A blocked gate cancels pending combos and releases active outputs. Recovery suppresses only controls held when output resumes, until each is released; new presses on other controls are accepted. Opening the Mac mapping editor stops the cable session. This backend posts CGEvents and does not create a virtual HID device. See [mapping behavior](KEYBOARD_MOUSE.md).

## HID contract

One Generic Desktop/Game Pad application collection, no Report ID. Input is 13 bytes: ten button bits plus six padding bits, a four-bit null-state hat plus four padding bits, four signed 16-bit stick axes, and two unsigned 8-bit trigger axes. A get-input-report request returns the current snapshot. Output and feature reports are unsupported; vibration is not advertised.

The local experimental vendor/product pair is FFFF:0001, transport Virtual. This is not a registered hardware identity or a shipping VID assignment, and does not impersonate Xbox/PS hardware. Some games may require mappings or a different, properly validated backend. CoreHID wraps the same underlying virtual-device mechanism; it does not avoid signing or recognition constraints.

## Release work

See [release readiness and product roadmap](RELEASE_PLAN.md) for current milestones and launch blockers.

Custom button labels and enabled slots are stored per phone layout. Stable numbered slots map to Mac keyboard bindings independently of display names. Existing receivers reject nonzero custom bits; install both updated apps. The HID descriptor remains unchanged and ignores custom bits.


Cursor trackpad actions use separate 28-byte type-2 pointer frames alongside type-1 state frames, sharing the same wrapping sequence counter. Byte 6 selects move/left-click/right-click (0/1/2); bytes 16–19 hold signed little-endian X/Y displacement in 1/16 phone points (limited to ±4096 units). Other payload bytes are zero. Click commands require zero displacement. These commands are never repeated by heartbeats. State heartbeats remain required for the output watchdog. Keyboard/mouse output accepts pointer actions only in Cursor mode with an active permission/focus/freshness gate; HID and monitor backends ignore them. Click pulses share mapper ownership with held trigger bindings. Scroll tokens post wheel events and repeat only while owned.


## Wireless transport additions

`InputLink` abstracts blocking framed reads, writes, and cancellation. USB uses the original `StreamSocket`; `WiFiLink` adapts Network.framework TLS and `BluetoothLink` adapts Core Bluetooth. `LinkInbox` assembles arbitrary notification/TCP fragmentation up to 8192 queued bytes and enforces a fixed read deadline. Session cancellation interrupts pending reads/setup and closes transports. Wi-Fi and BLE share the existing 28-byte frames and sequence guard; no keyboard mappings are transmitted to the phone. TLS pairing is covered by a live loopback integration test including wrong-code rejection. BLE MTU fragmentation has a unit test; on-air behavior is not yet verified.

`LayoutMode` gains optional radial fields for backward-compatible catalog decoding. Slot -1 means unused; otherwise slots are 0–15. Slot arrays, when present, must contain exactly eight valid entries. The radial helper chooses the nearest mapped angular direction, splitting unused sectors between their mapped neighbors, with a cancellation center. The touch view emits existing custom-button bits only on release. State-frame byte 15 carries preview-only radial telemetry: 0 idle, 1 center touch, and 2–9 for directions 0–7. Both apps must be updated together; older receivers required this byte to be zero. HID/keyboard output ignores this telemetry.

### Controller Guide button
`PadButton.guide` appends wire button bit 10, preserving the ten existing button IDs. State frames remain 28 bytes and accept bits 0–10. Matching phone/Mac builds are required for Guide input; older receivers reject that formerly reserved bit. Controller layouts expose a movable/removable center Xbox/PS button, named for their emulated controller identity. Guide is distinct from Menu/Options and supports normal gamepad remapping. Xbox wireless reports encode Guide at byte 15 bit 4; DS4 reports encode it at byte 7 bit 0 independently of the six-bit sequence. The receiving game, Steam, or OS determines whether Guide opens an overlay; it is not a guaranteed pause-menu shortcut.
