# Setup and signing

## iPhone

1. Sign into your Apple Account in Xcode → Settings → Accounts.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and replace its placeholders with your team ID and a unique bundle prefix.
3. Open `iPhoneGamepad.xcodeproj`. Select **PhoneGamepad**, use automatic signing, and choose your connected iPhone.
4. Enable Developer Mode, unlock the phone, and trust the Mac/developer profile if prompted. Run the app.
5. Keep PocketPad in the foreground in landscape orientation.

A free Personal Team supports local development with short-lived provisioning. Use Xcode to renew expired profiles. Your Xcode version must support the installed iOS version.

## Mac

Run **MacGamepad** in the Debug configuration. Follow the two-step setup:

1. Choose the same transport as the phone. USB requires a data cable; Wi-Fi/Bluetooth require the phone's six-digit code.
2. Choose an app (or explicitly choose any active app), enable Accessibility permission, and start playing.

The settings gear contains mappings, profile import/export, and troubleshooting. Test-only input is available under **Other control modes** and does not send keyboard/mouse input.

For USB, no Personal Hotspot or third-party proxy is required. If several phones are connected, disconnect the others or use the CLI's `--device` selector.

## Customize controls

Tap the phone's menu button to open settings, or hold it to enter the editor. Drag controls, select one to resize it, and open **Button options** for color, haptics, and mode linking. Double-tap to rename. Undo/redo is available for the current app session.

Existing modes remain independent until you enable position linking for a control. Back up layouts from **Profiles & backups**. Imports create copies; exporting a phone profile and importing it on the Mac lets you bundle it with Mac mappings.

## SDK-only iPhone installer

If Xcode asks for a large simulator component even though a compatible device SDK is installed, a direct device build may work. First create a valid signing profile through Xcode, then run:

```sh
python3 Scripts/install_iphone.py \
  --profile "/path/to/PhoneGamepad.mobileprovision" \
  --device "YOUR_DEVICE_IDENTIFIER"
```

Use `xcrun devicectl list devices` for the identifier. The script validates the profile, uses the installed SDK and signing identity, and installs without clearing app data. `--build-only` skips installation. It does not renew expired profiles or install SDK components.

## Virtual gamepad

The experimental backend requires `com.apple.developer.hid.virtual.device`. Request Apple's approval for your Mac App ID before attempting the **Gamepad** build configuration. Merely adding an entitlement file or buying membership is insufficient.

After approval, configure the Mac signing team and an authorized provisioning profile, select the Gamepad configuration, verify the signed entitlement, and test device creation and game recognition. Debug and Release omit the restricted entitlement. See [authorization notes](AUTHORIZATION.md).
