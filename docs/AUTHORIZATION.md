# Virtual gamepad authorization — 2026-10-05

USB input works. The remaining gate is macOS permission to create a system-wide virtual HID gamepad. The iPhone's free Personal Team profile does not grant this Mac capability. CoreHID and IOHIDUserDevice do not avoid the entitlement requirement. Apple also cautions that some GameController clients filter virtual devices, so authorization does not itself establish Valheim compatibility. [Apple entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device), [compatibility guidance](https://developer.apple.com/forums/thread/812774).

## Candidate: LizardByte's signed broker

Reviewed release `v2026.1003.1215.38`, marked prerelease. Its universal Mac DMG is 10,826,773 bytes. Downloaded and mounted read-only for inspection; **not installed or executed**.

Local verification of `VirtualHIDBroker.app` passed `codesign --verify --deep --strict`. The signature identifies **LizardByte LLC (F8XQ7XCN2R)** under Apple's Developer ID certificate chain. The binary carries `com.apple.developer.hid.virtual.device = true`. This verifies the package signature and entitlement claim, not successful runtime device creation on this Mac.

The vendor requires a purchased machine license; price was not verified. Their installer creates a privileged LaunchDaemon, installs two apps and a client library, and requires administrator authentication. Device-control/Accessibility permission is also required. The broker has periodic license validation; yearly licenses require online validation after restart, while previously activated lifetime licenses allow one gamepad offline. No purchase or activation has occurred.

Pocket Pad needs a client adapter before it can use this broker. The packaged library provides the relevant interface; integration should preserve its response/error handling and close behavior. Next validation would be: licensed test-device creation, input report mapping, disconnect release, then Steam and native Valheim. This could avoid needing our own Apple Developer membership.

Sources: [vendor's Mac guide](https://docs.lizardbyte.dev/projects/libvirtualhid/master/md_docs_2macos-gamepad.html), [release](https://github.com/LizardByte/libvirtualhid/releases/tag/v2026.1003.1215.38), [client implementation](https://github.com/LizardByte/libvirtualhid/blob/master/src/platform/macos/macos_broker_client.cpp).

## Alternative: request our own entitlement

Confirm eligibility with Apple before purchasing membership. Paid membership is not itself entitlement approval. Apple's [System Extension request portal](https://developer.apple.com/contact/request/system-extension/) requires sign-in; ask Apple which category applies to the app-level IOHIDUserDevice entitlement. DriverKit-family entitlements are not interchangeable with the app-level entitlement.

The project's Gamepad configuration is already prepared for an authorized profile. Once Apple approves a Mac App ID, create a matching provisioning profile, sign that configuration, verify HID input, and test game recognition.

### Draft inquiry (not submitted)

Subject: Virtual HID entitlement for an iPhone-to-Mac gamepad companion

I am developing Pocket Pad, a native iPhone and Mac companion project. The iPhone provides a customizable touch gamepad and sends its state to the Mac over a trusted USB connection. The Mac needs to expose that input as a system-wide HID gamepad for native macOS games, initially Valheim.

The implementation uses IOHIDUserDeviceCreateWithProperties and IOHIDUserDeviceHandleReportWithTimeStamp. Please confirm the membership, request category, App ID configuration, and provisioning steps needed for com.apple.developer.hid.virtual.device. The prototype Mac bundle ID is dev.pocketpad.prototype.mac.

The descriptor contains buttons, a D-pad hat, two sticks, and trigger axes, with no keyboard/mouse collections. The user explicitly enables gamepad output. The app neutralizes input on disconnect/timeouts and removes the device when stopped. The initial scope is personal development; distribution would be considered separately.

I understand authorization does not guarantee GameController or per-game recognition. Is this approach supported, and what additional compatibility requirements should we address?

## Other candidates

OpenJoystickDriver describes a signed physical-controller compatibility app, but a reusable external state-injection interface and suitable downloadable release were not established. SillyUtility/VirtualController documents a retro NES prototype and has no releases on the reviewed release page. Neither is a verified free backend for this project's dual-stick controller. [OpenJoystickDriver](https://github.com/xsyetopz/OpenJoystickDriver), [VirtualController](https://github.com/SillyUtility/VirtualController).

No verified free, entitlement-free route has been found. No system security settings have been changed. Choosing a licensed broker or our own Apple authorization remains a user decision.
