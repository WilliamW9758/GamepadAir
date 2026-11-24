# Pocket Pad release preparation

Updated November 23, 2026. This is a preparation packet, not an approval or public release. AI and Marketplace remain local previews; the combined launch is intended after their services are complete.

## Current evidence

- App Store Connect record 6831873832, PocketPad Remote Controller: iOS 1.0, Prepare for Submission; manual release selected, no build selected. Rechecked November 23.
- iPhone Release archive 1.0 (6) and App Store Connect export succeeded using Xcode 27.2 / iOS SDK 27.2. Exported IPA has Apple Distribution signing, beta-reports-active enabled, get-task-allow disabled, and no registered-device restriction. This is a rehearsal build; it has not been uploaded or reviewed.
- Mac Gamepad archive 1.0 (6) succeeded with hardened runtime. Portal inspection confirms HID Virtual Device is enabled and its development-only variant is unchecked. No Developer ID certificates are available for a manual profile. Automatic Developer ID export failed: “The HID Virtual Device (development) capability is not available for Developer ID provisioning profiles.” Do not remove HID just to get an apparently successful controller release.
- All 122 Swift package tests passed. Both archives pass Scripts/check_release_bundle.py resource checks. Those checks do not validate distribution signing or App Review acceptance.
- User confirmed native Duo display mode and layered icon appearances; broader clean-install and distribution-build testing remains outstanding.

## Distribution and identity

- iPhone: App Store / TestFlight, free, iOS 17+, landscape. Preserve dev.pocketpad.prototype.iphone.
- Mac: Developer ID signed, notarized standalone download, macOS 15+. Preserve dev.pocketpad.prototype.mac. Use MacGamepad-HID, not the keyboard-only MacGamepad release configuration.
- Explicit Developer ID certificate/profile are now created; downloaded profile includes HID. Finish export after keychain authentication, then notarize, staple, and test on another Mac before publishing a companion download.
- Build 6 is reserved for this local rehearsal, not confirmed on App Store Connect. Check uploaded build numbers before the next upload. Never reuse an already-uploaded build number.
- Keep manual release. Production submission must include working AI/Marketplace or remove their preview entry points. TestFlight previews must be clearly described in beta notes.

## Store copy draft

Name: PocketPad Remote Controller
Subtitle: Your iPhone controls your Mac
Keywords: controller,gamepad,remote,keyboard,mouse,layout,custom,buttons,trackpad,mac
Promotional text: Turn your iPhone into a customizable controller for your Mac. Arrange your controls, save layouts, and connect with the free Pocket Pad Mac companion.
Suggested category: Utilities. Price: Free. No in-app purchases currently implemented.

Description:

Turn your iPhone into a touch controller built around the way you play.

Connect to the free Pocket Pad Mac companion using a USB cable, local Wi-Fi, or Bluetooth. Create layouts with buttons, joysticks, a D-pad, and radial controls, then arrange them on your phone or Mac.

• Move, resize, and rename controls.
• Save separate layouts for your games and switch between them from either device.
• Map keyboard and mouse actions, including combinations and hold or tap behavior.
• Use controller layouts with Xbox or PlayStation button styles and emulation.
• See your phone layout and live input on your Mac.
• Adjust stick behavior and per-layout haptic feedback.
• Export layouts and backups as files you control.

Requires an iPhone running iOS 17 or later and a Mac running macOS 15 or later with the free Pocket Pad companion installed. Keep the phone app open during play. Keyboard and mouse output requires Accessibility permission on the Mac. Wireless connections require the relevant system permissions; some guest networks prevent devices from communicating.

Your games run on your Mac. Pocket Pad does not stream games. Controller support and button prompts depend on the game and its input settings. Pocket Pad is not affiliated with Apple, Microsoft, Sony, or individual game publishers.

Editorial gate: the controller sentence above is conditional on successful Developer ID HID distribution validation. Add AI/Marketplace copy only when those services are implemented and tested; do not describe preview examples as a live catalog.

## URLs and contact

- Support: https://github.com/WilliamW9758/PocketPad/issues
- Project: https://github.com/WilliamW9758/PocketPad
- Privacy policy intended URL: https://github.com/WilliamW9758/PocketPad/blob/main/docs/PRIVACY.md
- Public checks on November 23: project and Issues URLs load without sign-in; the intended privacy URL returns 404. Publish the updated policy before using that URL for submission.
- Mac download: pending a signed, notarized release; a source archive is not an installer.
- Review contact and copyright holder need account-owner confirmation. Do not copy private contact details into this repository.

## Reviewer instructions draft

Pocket Pad turns iPhone touch controls into input on a separate Mac companion. No app account is required for the current core features. It does not stream or download games.

Prerequisites: an iPhone, a Mac running macOS 15 or later, and a USB data cable. Install the Mac companion from the final download URL supplied here before submission. No Xcode, Developer Mode, or development provisioning should be required for the distributed apps.

1. Open Pocket Pad on both devices. Select USB cable, unlock the iPhone, and trust the Mac if prompted. Complete pairing.
2. In the Mac practice step, move a phone stick and press the indicated button. The Mac visualization should respond in the same direction.
3. Select Build manually, choose keyboard and mouse input, and grant Mac Accessibility permission. Keep Active app selected and start playing.
4. Open a blank TextEdit document on the Mac and focus it. Check the layout mappings in Pocket Pad; press a control mapped to a printable key and confirm the corresponding text appears in TextEdit.
5. Return to Pocket Pad. Open Layout & mappings, duplicate the layout, move/rename a control, and save. Verify the connected phone updates. Editing pauses game output while keeping the connection alive.
6. Return to the main screen and check live input. Disconnect while holding a control; held output should release. Reconnect and verify the saved layout remains.
7. Controller test, after distribution authorization: select a controller layout and use a compatible Mac game. Valheim was exercised with Steam Input disabled. Recognition and prompts vary by game. Do not require the reviewer to purchase a game to verify the basic connection and editing features.

Before submission, append exact AI and Marketplace review steps and service availability details if those features ship. Supply a review account only if the finished experience requires one.

## Privacy and compliance

See PRIVACY.md for current local-only behavior. The offline policy is also embedded in AppInformation.swift. The Mac input log is a rolling five-minute window capped at 512,000 bytes; the last saved file can remain after quit. No automatic upload is implemented.

Current source audit found no advertising, analytics SDK, account service, AI API calls, or marketplace backend. Proposed current privacy-label answer: no data collected by the developer, subject to final review under Apple's definitions. This answer MUST be reassessed when AI/server features are added, including prompts, layouts, identifiers, server request logs, third-party processing, and retention. TestFlight feedback/crash information is a separate beta-testing channel managed by Apple.

Required-reason APIs: UserDefaults CA92.1; system boot time 35F9.1. Wi-Fi uses Apple's Network/Security TLS APIs. Export-compliance answers remain pending; no exemption flag has been guessed. Finish age rating, content rights, availability, accessibility declarations, and contact information using the final app's behavior. The current Connect page displays China mainland compliance notices; check applicability and intended territories before selecting availability.

## Screenshots and beta plan

Capture the final iPhone UI, not the Mac window, in landscape at sizes currently accepted by App Store Connect. Keep original PNGs. The store now offers a Duo screenshot group; include actual native Duo captures. Do not scale a normal phone capture and present it as Duo UI.

Suggested screenshots: controller layout; layout editing with a selected control; saved layout choices; connection screen; AI/Marketplace only after working implementation. Exclude personal names, pairing codes, private game data, and unfinished preview states from production marketing.

Internal beta first: install through TestFlight and install the notarized Mac companion on a clean Mac; verify no developer setup is needed. External testers require the first external build's Beta App Review. Test USB/Wi-Fi/Bluetooth, denied-permission recovery, sleep/lock/reconnect, input release, edit sync, both controller identities, and layout preservation during updates. Exercise both phones and Duo resizing. Record failures as release blockers, not assumptions of support.

## Repeatable build commands

Use Scripts/prepare_release.sh with a new build number and destination. It archives and exports locally, never uploads or submits. The initial automatic Mac export failed; the explicit profile now includes HID, and signing authentication is being completed. iPhone output is still useful for validation. Do not treat archive success as successful distribution.

After signing is resolved: notarize the Developer ID app, staple it, create the drag-to-Applications DMG with Scripts/package_mac_release.sh, then verify Gatekeeper on a clean Mac. The packaging script deliberately refuses an unstapled or incorrectly signed app.

## Apple references

- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- https://developer.apple.com/testflight/
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/help/account/capabilities/capability-requests/
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Local rehearsal artifacts

Saved outside Git at `~/PocketPad Backups/Release Prep 2026-11-23/`: iPhone and Mac archives, App Store IPA, export summary, and build/export/test logs. Build 6 was archived from commit 718b83e before this preparation pass updated the embedded privacy text. Rebuild the final version after the planned services and disclosure changes. No binary has been uploaded to TestFlight, notarization, or production.

## Notarization handoff after signed export

Use an authorized Apple notarytool keychain credential profile (or Xcode Organizer's Developer ID distribution flow). Keep passwords and API private keys out of this repository and chat. Example commands below assume a credential profile named PocketPad-Notary has already been configured by the account owner:

```sh
ditto -c -k --keepParent '/path/to/export/MacGamepad.app' '/path/to/PocketPad-notarization.zip'
xcrun notarytool submit '/path/to/PocketPad-notarization.zip' --keychain-profile PocketPad-Notary --wait
# Continue only after status Accepted. Fetch the submission log if rejected.
xcrun stapler staple '/path/to/export/MacGamepad.app'
xcrun stapler validate '/path/to/export/MacGamepad.app'
Scripts/package_mac_release.sh '/path/to/export/MacGamepad.app' '/path/to/PocketPad-1.0.dmg'
```

These are future steps, not a record of completed notarization. An App Store Connect upload and a notarization submission are different operations; neither publishes the app on its own.
