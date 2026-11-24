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

## Follow-up after initial checkpoint
Phone build 3 now installed on Duo: disconnected wording, Settings title, no mode subtitle, right-aligned Edit layout, hold-to-edit firing on recognizer began. Mac assistant prototype added with real local sample edits through existing layout command/ack transport and preview-only free-form requests. Mac UI inspected; signed builds pass. Await user reopening phone to verify physical hold timing and assistant sync. Latest source checkpoint supersedes the original icon-only checkpoint.

## Practice screen follow-up
Removed redundant connected/success lines in Mac onboarding practice; retained disconnected feedback. Corrected practice stick Y display to negate wire Y (phone sends positive-up). Signed Mac build passed and was installed/relaunched; physical practice test pending. Initial Xcode invocation stalled in NSFileCoordinator reading project; building a temporary project copy in /tmp with source symlinks succeeded.
User proposed final onboarding choices: AI assist, Marketplace game search, Build manually. Recommended placing that choice after practice, with manual leading to Choose controls and preview features clearly labeled. This navigation change is not implemented yet.

## Onboarding choices implemented before restart
Removed the remaining practice-only sentence. After practice, three full-row buttons now offer AI assist (Preview), Marketplace (Preview), and Build manually. Previews reuse the existing assistant/marketplace UI in sheets, with Back and Continue setup; manual opens input selection. Input selection Back returns to the choices; choices Back returns to practice and syncs the phone. Existing permissions and final Start playing remain required. Signed Mac build passed and installed; device/UI walkthrough still pending. No new AI service or marketplace backend enabled.

## Upgrade completed and native Duo build installed — 2026-11-23
- Verified macOS 26.7.3 (25G342), updated Xcode through App Store to 27.2 (27B52), iOS SDK 27.2. User explicitly approved Icon Composer and Xcode/SDK licenses, then completed administrator authentication. `xcodebuild -checkFirstLaunchStatus` passes.
- Built PhoneGamepad with normal Xcode target (Debug, generic iOS destination), signed successfully, build number 4. `vtool -show-build` confirms SDK 27.2, minimum iOS 17.0.
- Installed and launched on Duo UDID 00008160-000A64E13E70000A using current devicectl. Current devicectl identifies the device by UDID; old CoreDevice UUID may not work. Installed app info confirms version 1.0/build 4. No app deletion or layout reset.
- User additionally reported icons were wrong in dark/tinted/clear appearances. With explicit user approval, recreated the same controller silhouette as SVG after image generation produced unusable alpha cutouts. Native Icon Composer documents are in Assets/LayeredIcons: PocketPad.icon, AppIconWhite.icon, AppIconGraphite.icon. Dark primary uses red glyph on system dark background; mono provides native clear/tinted material. Icon Composer dark and mono previews inspected. Matching default previews exported through Icon Composer and copied into existing IconPreview image sets.
- Xcode project compiles all three .icon documents with actool. Primary iOS icon name PocketPad; alternate names AppIconWhite/AppIconGraphite unchanged. Mac keeps existing catalog icon. Legacy alternate bitmap sets moved to Assets/LegacyAppIcons; SDK-only install script remains explicitly marked as legacy flattened-icon fallback, not the preferred installer.
- Await physical-device confirmation: Duo fills display without zoom button; fold/unfold resizes and Mac canvas follows; check Home Screen dark/clear/tinted modes and all icon choices. Original Air has not received build 4.
- Build product: /tmp/PocketPadNativeDuo/Build/Products/Debug-iphoneos/PhoneGamepad.app. Build log: /tmp/pocketpad-native-duo-build.log.

## Red icon and final onboarding destinations — 2026-11-23
- User confirmed native icon appearances and Duo phone mode work correctly. Shifted primary icon default and dark glyph toward a cooler red; refreshed Icon Composer export and in-app preview. White/Graphite unchanged.
- AI assist and Marketplace now finish setup and open their existing full-window workspace pages. Removed setup preview sheets and Continue setup return path. Manual setup retains controls/permissions flow. Existing phone layout determines input type; Active app remains default.
- Paused sessions can initialize with monitor output so entering editing pages does not fail before keyboard/mouse permission is available.
- Signed Mac and iPhone builds passed; 14 CableTests passed; git diff --check passed. Installed Mac app at existing path and phone build 5 on Duo, preserving data. Physical color comparison and full onboarding walkthrough remain to be confirmed.

## Layout deletion/reset and AWS design — November 23, 2026
- Added single personal-layout deletion on phone and Mac, with confirmation and preset protection. Mac deletion uses a base-layout conflict check; a snapshot capability flag prevents sending new commands to older phone apps.
- Added red Clear saved layouts (restores built-in presets, removes personal layouts/recovery history) and Erase local data controls. Phone erase resets its defaults/catalog/pairing and reopens onboarding. Mac erase stops input, removes defaults and diagnostic history, then quits. Device scope and exclusions (exports, system permissions, Home Screen icon) are explained in confirmations. No actual user layouts/data were erased during validation.
- Custom action style now respects destructive roles. Mac General reset UI and confirmation/cancel were inspected. Both signed app builds succeeded and were installed (Duo phone build 7). 125 Swift tests passed including deletion selection fallback and wire command round trip.
- docs/layout-format contains a draft readable JSON Schema, validated example, semantic validation requirements and migration plan. It is deliberately not a runtime format change; multi-mode/advanced preferences still need a complete lossless adapter before adoption.
- docs/AWS_LAYOUT_SERVICE.md proposes S3/CloudFront + HTTP API/Lambda + DynamoDB, Cognito/Apple for publishers, async generation with server-side Anthropic credentials. Includes endpoint/data design, moderation, quotas, and setup decisions. No AWS resources provisioned.
