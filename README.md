# PocketPad

**Turn your iPhone into a customizable controller for your Mac.** Free and open source under the MIT license, built with Swift, SwiftUI, and UIKit. No third-party package dependencies.

PocketPad is in release preparation. Keyboard/mouse and virtual gamepad output work in local testing; the Mac companion has passed Developer ID signing and notarization. Clean-install testing and broader game compatibility checks remain before public release.

![Mac setup](docs/design/mac-connect.png)

## Features

- USB cable, local Wi-Fi, and Bluetooth connections, with guided first-time setup and a shorter reconnect flow. USB is the most exercised path; wireless needs broader testing.
- A live Mac view that mirrors the phone’s layout, screen proportions, buttons, sticks, D-pad, and radial input.
- A combined layout and mapping editor on Mac, plus touch editing on iPhone. Move, resize, rename, color, add, and remove controls, with undo/redo.
- Named layouts with creation, duplication, renaming, deletion, import/export, and selection/edit synchronization between connected devices. Clear saved layouts or erase local app data from Settings, with confirmation.
- Input type belongs to each layout: keyboard/mouse or controller. Converting a copy preserves straightforward mappings and flags controls that need manual remapping.
- Xbox and PlayStation emulation, including guide buttons. Default button labels follow the emulated controller; custom labels stay unchanged.
- Optional Aim/Cursor behavior for layouts that need it. Single-mode layouts hide the mode switch and other-mode outlines.
- Floating or fixed sticks, center-hold L3/R3 followed by dragging, stick-tap actions, hold-to-aim attack buttons, and a cursor trackpad.
- Four-direction or eight-direction D-pads, custom buttons, and radial controls with fewer than eight mapped directions. Unused radial directions share their space with adjacent mapped choices.
- Keyboard/mouse mappings with hold/tap behavior, editable combinations, scroll inputs, mouse sensitivity, and automatic running.
- Per-layout button haptics with adjustable strength, plus supported game rumble forwarded to the phone. Stick movement does not trigger button feedback.
- A movable phone Settings button: tap for settings, hold to edit, or drag to reposition.
- Native layered app icons with red, white, and graphite choices and system appearance support.
- Active-app or single-app targeting, input paused while editing without disconnecting, and release of held input on stale connections or disconnects.
- Bounded Mac input diagnostics: a rolling five-minute window capped at 512 KB. The last saved log can remain after quitting; see [privacy details](docs/PRIVACY.md).

Controller recognition, button prompts, rumble, and Steam Input requirements vary by game. Valheim and Stardew Valley have been exercised locally; this is not a guarantee of compatibility with every game or configuration.

## Community layouts and assisted discovery

Marketplace and assisted layout discovery currently have **local preview interfaces**, not live online services. The planned flow is to find a community layout by game or scenario, then offer a generated starting layout if no suitable result exists. Fine edits stay in the regular editor.

The [portable layout format draft](docs/layout-format/README.md) includes a schema and example designed for validation and readable authoring. It is not yet a replacement for the app’s existing JSON export format. The [AWS service plan](docs/AWS_LAYOUT_SERVICE.md) covers hosting, search, uploads, moderation, and generation; no service is deployed yet.

## Build and run

You need a Mac with Xcode, an iPhone, and your own Apple signing account. Deployment targets are macOS 15 and iOS 17; Xcode must support your actual devices.

1. Clone this repository and open `iPhoneGamepad.xcodeproj`.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, then set your team ID and unique bundle prefix. The local file is ignored by Git.
3. Run the **PhoneGamepad** scheme on your iPhone. Enable Developer Mode and trust your Mac/developer profile when prompted.
4. Run **MacGamepad** on your Mac.
5. Keep the phone app open. Choose USB cable on both devices, follow the Mac setup, select an app, and grant Accessibility permission for keyboard/mouse input.

Free signing works for local iPhone development but expires periodically. There is no prebuilt public release or TestFlight link yet.

See [setup and signing](docs/SETUP.md), [mappings and wireless connections](docs/KEYBOARD_MOUSE.md), and [validation status](docs/VALIDATION.md).

## Virtual gamepad status

The Mac backend uses `IOHIDUserDevice` and requires Apple's restricted `com.apple.developer.hid.virtual.device` entitlement in an authorized provisioning profile. Paid Developer Program membership alone does not grant it. This authorization is not bundled with the source code. See [authorization notes](docs/AUTHORIZATION.md).

## Development

```sh
swift test
swift run gamepad-host --monitor
```

The CLI also provides `--probe` and `--gamepad`; these require virtual-HID authorization. See [architecture](docs/ARCHITECTURE.md) for protocol details.

After adding Swift files, run `python3 Scripts/sync_project_sources.py`. Avoid rerunning the original project generator on a configured checkout; it replaces project settings.

## Release preparation

See [release readiness and product roadmap](docs/RELEASE_PLAN.md) for launch blockers, Community Layouts, and assisted layout discovery.

`Config/AppInfo.plist` supplies Bonjour declarations to the app Info.plists; it is not a privacy manifest. Required-reason API declarations are in `Config/PrivacyInfo.xcprivacy`. See the [submission packet](docs/SUBMISSION.md) for archive validation and outstanding release gates.

## Contributing

Bug reports, device compatibility reports, and pull requests are welcome. Include reproduction steps and OS versions. Do not commit signing certificates, provisioning profiles, pairing codes, personal layout exports, or device logs containing private information.

## License

[MIT](LICENSE). The native layered app icons use a clean vector controller symbol; source assets are included in `Assets/LayeredIcons/`. PocketPad is not affiliated with Apple, Microsoft, Sony, or the games used with it.
