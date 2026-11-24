# Virtual gamepad authorization

Historical portal check: November 11, 2026. See the November 23 distribution gate below; development authorization is not sufficient for shipping.

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

## Developer ID distribution gate — November 23, 2026

The signed MacGamepad-HID archive 1.0 (6) succeeds. Export with Config/ExportOptions-DeveloperID.plist and automatic provisioning fails: “The HID Virtual Device (development) capability is not available for Developer ID provisioning profiles.” No matching Developer ID provisioning profile can be created.

Check the Mac App ID's distribution HID capability assignment and enablement, then obtain a Developer ID profile containing com.apple.developer.hid.virtual.device. A prior Assigned status is not proof of a usable distribution profile. If the portal does not offer the distribution capability, ask Apple Developer Support to clarify distribution authorization for this App ID. Do not delete the entitlement or ship a development profile to bypass this gate.

Runtime implementation has advanced since the historical notes above: layouts now carry controller style and profiles, Xbox/PlayStation emulation is implemented, and the user exercised Valheim and Stardew Valley. These gameplay observations do not establish public distribution approval or universal game compatibility.

Portal recheck November 23: the Mac App ID has HID Virtual Device checked and HID Virtual Device (development) unchecked. A manual Developer ID profile flow permits choosing the Mac App ID but stops at “No Certificates are available.” Create an authorized Developer ID Application certificate, then retry a manual profile before assuming distribution permission is missing.

### Explicit distribution profile issued

With the user's approval, created a Developer ID Application certificate and imported its identity into the login keychain. The portal issued “PocketPad Mac Developer ID 2026-11.” Decoding the downloaded Developer ID profile confirms com.apple.developer.hid.virtual.device=true, the correct Mac application identifier, and no get-task-allow entitlement. This resolves the profile-issuance blocker without removing HID or requesting additional capability approval. Config/ExportOptions-DeveloperID.plist now uses this explicit profile and Developer ID signing; contributors must replace the profile mapping with their own.

Manual-profile Mac export succeeded after keychain authentication. codesign verification passes: Developer ID Application identity, universal arm64/x86_64 executable, hardened runtime, secure timestamp, HID entitlement true, and debug entitlement absent. Apple notarization subsequently succeeded; exportNotarizedApp produced a stapled app, stapler validate passed, and Gatekeeper reports accepted / Notarized Developer ID. Clean-machine runtime validation remains outstanding.
