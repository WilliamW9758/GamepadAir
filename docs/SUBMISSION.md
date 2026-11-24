# Existing-feature submission packet

Prepared November 6, 2026. App Store Connect record created: 6831873832 (PocketPad Remote Controller), iOS 1.0, Prepare for Submission. No Community Layouts, account system, or AI features are included. This document does not assert approval or successful upload.

## Distribution and identity

- iPhone: App Store, free, iOS 17+, iPhone only, landscape.
- Mac companion: separate Developer ID signed/notarized download, macOS 15+; not a Mac App Store build.
- Keep the existing bundle identifiers to preserve installed data: `dev.pocketpad.prototype.iphone` and `dev.pocketpad.prototype.mac` for this project's owner. Contributors use their own prefix.
- Current version/build: 1.0 (1). Do not increment or reuse build numbers blindly after an upload; check App Store Connect first.
- First release claims keyboard/mouse output. Do not claim authorized virtual gamepad distribution or verified game compatibility until independently validated.
- Release remains blocked until there is a downloadable, notarized Mac companion and a working iPhone archive. Source-only setup is not an adequate consumer/reviewer installation flow.

## Store copy (draft, ready for entry after name availability check)

Name: PocketPad Remote Controller

Subtitle: Your iPhone controls your Mac

Promotional text: Create a touch controller for your Mac with movable buttons, sticks, saved layouts, and keyboard and mouse mappings. Requires the free PocketPad Mac companion.

Keywords: controller,remote,keyboard,mouse,layout,custom,buttons,trackpad,mac

Suggested primary category: Utilities. Price: Free. No in-app purchases.

Description:

Turn your iPhone into a customizable touch controller for your Mac.

PocketPad works with its free Mac companion to send the keyboard and mouse controls you configure. Connect by USB cable, local Wi-Fi, or Bluetooth, then build a controller that fits the way you play.

- Arrange, resize, rename, and color your buttons.
- Save separate layouts for your games.
- Use analog-style touch sticks, optional D-pad controls, and a trackpad for menus.
- Map buttons to keys, mouse buttons, scrolling, or combinations.
- Add custom buttons and an eight-direction radial quick bar.
- Adjust stick sensitivity, hold gestures, and optional haptic feedback.
- Export profiles and backups as files you control.

Requires an iPhone running iOS 17 or later and a Mac running macOS 15 or later with the PocketPad companion installed. Keyboard and mouse output requires Accessibility permission on the Mac. Keep the iPhone app open while playing. Wireless connections require Bluetooth permission or a network that allows devices to communicate; hotel and guest networks may block Wi-Fi connections.

PocketPad does not stream games. Your game runs on your Mac, and compatibility depends on its keyboard and mouse controls and your mappings. Touch-layout presets do not emulate branded controller hardware.

No account or subscription is required. PocketPad is free and open source.

## URLs and contact

- Support: https://github.com/WilliamW9758/PocketPad/issues
- Project: https://github.com/WilliamW9758/PocketPad
- Intended privacy URL after publishing: https://github.com/WilliamW9758/PocketPad/blob/main/docs/PRIVACY.md
- Mac download URL: must point to the actual signed/notarized release before submission; do not substitute an unbuilt source archive.
- Reviewer contact: account owner must confirm current name, email, and phone before entry. Do not publish private contact details in this repository.

## Reviewer notes

PocketPad is an iPhone input controller for a Mac companion. It does not download or stream games. No account/login is required.

Prerequisites: iPhone and Mac, Mac companion installed from the release URL, and a USB data cable. The companion requires macOS 15 or later. Grant Accessibility permission to the Mac companion to test keyboard/mouse output.

1. Open PocketPad on the iPhone. Open the Mac companion.
2. Select USB cable on both devices. Unlock the iPhone and trust the Mac if prompted.
3. On the Mac, choose an app to receive keyboard/mouse input, such as TextEdit for keyboard mapping verification. Connect and focus that app.
4. Move the left stick to generate mapped movement keys. Switch the iPhone to Cursor mode to test pointer movement and tap clicks.
5. On the iPhone, open Settings, save a layout copy, and choose Move and resize controls. Move a button, finish editing, and verify the saved layout.
6. Disconnect. Held outputs must release. Reconnect to resume.

The development-only virtual gamepad backend is not a claimed feature of this release. Test keyboard/mouse output. Provide an actual companion release URL with the submission, not this draft instruction alone.

## Privacy and encryption

- Privacy policy is available offline inside both apps. Publish docs/PRIVACY.md before entering its URL in App Store Connect.
- No developer backend, advertising SDK, analytics SDK, accounts, or automatic diagnostic uploads were found in the current source audit. The manifest declares no tracking or developer collection. Review the final App Store privacy answers against Apple's definitions and actual release behavior.
- Required-reason API declarations: UserDefaults CA92.1 for app settings; system boot time 35F9.1 for elapsed input/timer calculations. Mac logs record session elapsed time rather than raw system uptime.
- Wi-Fi uses TLS through Apple's Network/Security frameworks; Bluetooth uses platform transport/security. Complete Apple's export-compliance questionnaire accurately for the final binary and distribution territories. No exemption flag has been guessed or hardcoded.
- There is no public user-generated content service in this version. Local editable labels and file import/export are not a community marketplace.

## Release commands

Run from the repository root with the appropriate Xcode platform components installed. Set your team in ignored Config/Local.xcconfig. Do not commit certificates, provisioning profiles, or signing credentials.

```sh
swift test
xcodebuild -project iPhoneGamepad.xcodeproj -scheme PhoneGamepad -configuration Release -destination 'generic/platform=iOS' -archivePath build/submission/PhoneGamepad.xcarchive archive
xcodebuild -exportArchive -archivePath build/submission/PhoneGamepad.xcarchive -exportPath build/submission/iphone -exportOptionsPlist Config/ExportOptions-AppStore.plist
xcodebuild -project iPhoneGamepad.xcodeproj -scheme MacGamepad -configuration Release -destination 'generic/platform=macOS' -archivePath build/submission/MacGamepad.xcarchive CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY='Developer ID Application' archive
xcodebuild -exportArchive -archivePath build/submission/MacGamepad.xcarchive -exportPath build/submission/mac -exportOptionsPlist Config/ExportOptions-DeveloperID.plist
python3 Scripts/check_release_bundle.py build/submission/mac/MacGamepad.app
```

Export is local, not an upload. Use Xcode Organizer to validate the iPhone archive before uploading. Notarize the exported Mac package, staple the result, and test Gatekeeper on a clean Mac before publishing it. The SDK-only development installer is not an App Store archive workflow.

## Final manual gates

- Accept App Store Connect's terms and create/check the app record.
- Obtain appropriate distribution certificates and profiles; validate signed archives.
- Complete export compliance, age rating, content rights, availability, and privacy questionnaires from actual facts; confirm reviewer contact details.
- Capture real screenshots of the final iPhone build at Apple's accepted device sizes. Do not use Mac mockups as iPhone screenshots or advertise unbuilt features.
- Verify first install, permission denial/recovery, all three transports, sleep/lock/reconnect, held-input release, profile import/export, and upgrading the tuned existing layout.
- Publish a signed/notarized companion and live support/privacy URLs.
- Run archive validation, upload, inspect processing warnings, select the build, and only then send for review.

Apple references: [required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [privacy disclosures](https://developer.apple.com/app-store/app-privacy-details/), [distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).
