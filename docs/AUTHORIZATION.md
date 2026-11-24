# Virtual gamepad authorization

Last verified in the Apple Developer portal: November 11, 2026.

- Developer Program membership is active.
- HID Virtual Device: **Assigned**. Enabled on the Mac App ID by the account owner.
- HID Virtual Device (development): **Assigned**. The enabled HID Virtual Device capability is included in the generated Mac development profile.
- The request was submitted October 14, 2026. Account-specific correspondence remains outside the repository.

PocketPad uses `IOHIDUserDevice` with `com.apple.developer.hid.virtual.device`. The Gamepad build configuration declares this entitlement; a declaration alone does not authorize it. Paid membership and development access do not establish distribution approval.

## Next validation

1. Enable the assigned HID Virtual Device capability on the Mac App ID and generate a matching development provisioning profile.
2. Sign a development build and inspect its embedded profile and entitlements.
3. Verify device creation, neutral input on disconnect, and device removal on stop.
4. Test recognition and controls in native Valheim and another native Mac game, including Steam where applicable.
5. Verify the distribution provisioning profile and a distributable signed build before advertising gamepad support.

Authorization does not guarantee that GameController, Steam, or individual games will recognize the descriptor. Xbox and PlayStation are touch-layout presets, not emulated hardware identities.

Keyboard/mouse input is an independent path using Accessibility permission. No third-party HID broker is bundled or required by that path.

References: [Apple entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device), [capability requests](https://developer.apple.com/help/account/capabilities/capability-requests/), [request portal](https://developer.apple.com/contact/request/system-extension/).

## Local implementation and testing

Select the shared **MacGamepad-HID** Xcode scheme to use the Gamepad signing configuration. In the Mac app, select Virtual gamepad on the control step. Gamepad mappings are saved separately under gamepad-profile-v1; existing keyboard mappings and phone layouts are unchanged. Custom/radial slots can map to standard controller buttons, triggers or D-pad directions. Gamepad mappings currently remain on this Mac and are not included in portable profile exports.

Use Aim mode on the phone for analog right-stick input. Cursor trackpad packets are not controller axes and are ignored in gamepad mode. Games must support a generic HID gamepad; physical Xbox/PlayStation identities are not emulated.

November 11 local checks: 84 Swift tests passed, including gamepad remapping, shared button ownership, paused-state release, and heartbeat expiration while pointer packets continue. The unsigned universal Mac Gamepad configuration built successfully. These checks do not validate signed virtual-device creation or game compatibility. No build was uploaded or published.

## Signed runtime validation — November 11, 2026

Xcode registered this Mac and generated a development provisioning profile containing com.apple.developer.hid.virtual.device. The universal Gamepad build succeeded and passed codesign verification. Installed locally at ~/Applications/Pocket Pad.app, with the previous app backed up as Pocket Pad.before-HID.app.

Launching the installed app through Launch Services with --hid-self-test successfully created the device and submitted neutral reports. IORegistry listed PocketPad Gamepad with Generic Desktop/Gamepad usage (1/5) while running and no PocketPad device after exit. A direct executable launch through the automation shell was denied by local TCC attribution; launch the app normally.

Actual phone-to-game controls and native Valheim/Steam recognition still require gameplay testing. This development build is not a distributable release. Nothing was uploaded or published.
