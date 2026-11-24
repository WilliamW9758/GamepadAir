<div align="center">

# PocketPad

**Your iPhone. Your Mac controller. Your layout.**

Xbox · PlayStation · Keyboard & mouse<br>
USB · Wi-Fi · Bluetooth

[Get started](docs/SETUP.md) · [Report a bug](https://github.com/WilliamW9758/PocketPad/issues) · [Roadmap](docs/RELEASE_PLAN.md)

</div>

![PocketPad on Mac, mirroring a PlayStation touch layout from a connected iPhone Air](docs/screenshots/mac-controller.png)

### Make it yours

- **Play your way.** Xbox or PlayStation emulation, or keyboard/mouse mappings with combos and tap/hold actions.
- **Build your controller.** Arrange buttons, sticks, four- or eight-way D-pads, and radial menus on Mac or iPhone.
- **See every input.** The Mac mirrors your phone’s layout and live controls. Layout changes sync between devices.
- **Feel the feedback.** Adjustable button haptics and supported game rumble, with floating or fixed sticks.
- **Keep your favorites.** Save, duplicate, switch, share, and delete layouts. No account needed for local play.

![PocketPad layout editor with the iPhone Air canvas and control settings](docs/screenshots/mac-layout-editor.png)

### Try it

**In development — no public download or TestFlight link yet.** The Mac companion has passed Developer ID signing and notarization; broader compatibility testing is ongoing.

To build from source, use **Xcode**, **macOS 15+**, and **iOS 17+**:

1. Open `iPhoneGamepad.xcodeproj` and configure your signing team using `Config/Local.xcconfig.example`.
2. Run **PhoneGamepad** on your iPhone and **MacGamepad** on your Mac.
3. Connect the phone and follow the setup flow. Start with USB.

[Full setup guide](docs/SETUP.md) · [Controls & connections](docs/KEYBOARD_MOUSE.md)

> Building virtual controller output requires Apple’s restricted virtual-HID entitlement. Keyboard/mouse output uses Accessibility permission. See [signing requirements](docs/AUTHORIZATION.md). Game compatibility and Steam Input settings vary.

### Coming next

Community layouts and game-based layout generation are planned. Their in-app screens are previews; online services are not live yet.

### For developers

Native Swift, SwiftUI, and UIKit. No third-party package dependencies.

```sh
swift test
swift run gamepad-host --monitor
```

[Architecture](docs/ARCHITECTURE.md) · [Layout format draft](docs/layout-format/README.md) · [AWS plan](docs/AWS_LAYOUT_SERVICE.md) · [Validation](docs/VALIDATION.md) · [Privacy](docs/PRIVACY.md)

---

[MIT licensed](LICENSE). Contributions and compatibility reports welcome. PocketPad is not affiliated with Apple, Microsoft, Sony, or the games used with it.
