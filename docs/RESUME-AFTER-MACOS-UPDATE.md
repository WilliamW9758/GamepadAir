# Resume after macOS update — 2026-11-23

## Current task
Finish native iPhone Duo support after updating macOS and Xcode. User authorized the update and confirmed there is no other active work; save all project work before restart.

## System update
- Downloaded Apple's macOS Tahoe 26.7.3 full installer to `/Applications/Install macOS Tahoe.app`.
- User authorized Apple license acceptance. On the next inspection the installer had already advanced to installation preparation on Macintosh HD, estimating 59 minutes. No agent-triggered restart yet.
- Before update: macOS 26.5.2, Xcode 26.5 (17F42), iOS SDK 26.5. Around 21 GiB free at checkpoint.
- After restart, verify macOS with `sw_vers`. Install Xcode 27.1 or later from Apple, then verify selected SDK/toolchain. Native Duo full-display behavior needs iOS 27.1+ SDK; merely changing device-family flags does not fix the old-SDK compatibility box.
- Apple references: https://developer.apple.com/iphone-duo/prepare/ and https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes

## Devices and signing
- Duo UDID: 00008160-000A64E13E70000A; CoreDevice ID: 7805C1DC-3B59-59A2-8DA8-CFDE2B900EFC; hardware iPhone19,4, iOS 27.3 beta. Old Xcode calls it iPhone 4. Developer Mode enabled.
- Original Air UDID: 00008150-000228880A00401C; CoreDevice ID: C696AFE6-576C-5001-9882-E830B755E97B; iPhone18,4.
- Both devices are named WW.iPhoneAir; avoid confusing them.
- Updated development profile including both: `/Users/williamwu/Downloads/PocketPad_iPhone_Development_2026-11 (1).mobileprovision`. Team 48T6PH4KSL. Bundle ID dev.pocketpad.prototype.iphone.
- Old Xcode DDI lacks Duo hardware variant (boardID14/chipID33120). Standard install via pymobiledevice3 installation_proxy succeeded without DDI. User opens app manually.
- Temporary helper venv `/tmp/pocketpad-device-tools` may not survive restart; recreate from PyPI only if new Xcode still cannot install.

## Latest app changes and validation
- Actual controller UIView canvas dimensions replace UIScreen.main telemetry; resize callbacks update Mac preview and existing resize logic releases touches. Signed build passes; fold/native-size testing pending new SDK.
- iPhone settings handle is draggable, position persists in normalized safe-area coordinates, edges clamped; tap opens settings, hold enters layout editor. User confirmed dragging works.
- Red icon corrected toward Apple Games' warm orange-red based on user's photo. White and Graphite alternate icons added through native iOS API. User confirmed Home Screen switching works.
- User reported blank in-app icon previews and stale-looking OS confirmation art. Latest build explicitly loads loose PNG previews via UIImage, forces original rendering, puts App icon LAST in settings, increments development bundle version to 2, uses content-hashed system icon filenames and supplies 20/29/40/60-point images at 2x/3x. Build/sign/install passed; previews/system prompt appearance still need on-device recheck. Do not claim this visual recheck passed.
- Source artwork and exact prompts preserved in Assets/PocketPad-icon-{red,white,graphite}.png and Assets/ICON-{RED,WHITE,GRAPHITE}-PROMPT.txt. Prior artwork retained. Generated via built-in image_gen.
- Latest Duo installed build: `/var/folders/jh/nbqdbll1053f81wr4kv67c0w0000gn/T/PocketPad-device-1a8gs5c5/PhoneGamepad.app` (temporary; rebuild after restart).
- Latest Mac installed at `/Users/williamwu/Applications/Pocket Pad.app`; warmer default red icon. Mac build passed. Air has NOT received these latest icon/settings changes.
- Broader core test suite last passed 122 tests before these UI/resource changes. Recent UI changes verified by signed builds and bundle resource checks; no full suite rerun needed unless new logic changes.

## Build commands
Phone SDK-only fallback (after upgrade prefer normal Xcode where possible):
`python3 Scripts/install_iphone.py --profile '/Users/williamwu/Downloads/PocketPad_iPhone_Development_2026-11 (1).mobileprovision' --device 7805C1DC-3B59-59A2-8DA8-CFDE2B900EFC --build-only`
Then install with devicectl. If needed fallback:
`/tmp/pocketpad-device-tools/bin/pymobiledevice3 apps install --udid 00008160-000A64E13E70000A --developer <built.app>`
Mac:
`xcodebuild -project iPhoneGamepad.xcodeproj -scheme MacGamepad-HID -configuration Gamepad -derivedDataPath /tmp/PocketPadControllerPrototype -allowProvisioningUpdates build`
Copy resulting MacGamepad.app to existing installed Pocket Pad.app, verify signing and open that installed path (HID permission depends on it). Do not delete/reset app data or phone layouts.

## Next checks
1. Verify OS upgrade; install/select Xcode 27.1+, handle any new license explicitly with user.
2. Rebuild with new SDK and verify Duo fills native display, handles fold/unfold, keeps controls/settings handle reachable, and Mac mirrors actual canvas.
3. Recheck in-app previews and iOS icon confirmation on latest Duo build. Home Screen icon switching already confirmed.
4. Keep existing custom layouts, mappings, and pairing intact. No remote push/publish requested.
