# Validation status

PocketPad is a working prototype, not a finished consumer release.

- 78 Swift package tests passed during the latest core-feature validation: wire framing, mappings, focus/freshness gates, pointer gestures, layout compatibility, linked placements, undo/redo, and profile transfer.
- Mac and physical-iPhone builds have succeeded. USB keyboard/mouse play has been exercised during development.
- Wi-Fi encryption is covered by loopback tests. Real-network Wi-Fi and Bluetooth reliability still need broader testing. Guest networks may isolate devices.
- The virtual HID backend exists but has not been authorized or validated in games. Its presence does not establish Xbox/PlayStation identity or game compatibility.
- Native Mac setup screens were rendered and visually checked. See `docs/design/` for UI previews; connected-state previews use fixtures.
- Physical haptics, profile sharing, and behavior across different devices need further hands-on testing.

Run `swift test` to validate the current checkout. Report your OS versions, transport, and reproduction steps when filing an issue; remove pairing codes, device identifiers, and unrelated personal data from logs.
