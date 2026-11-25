# Validation status

PocketPad is a working prototype, not a finished consumer release.

- 78 Swift package tests passed on November 6, 2026 after the Intel TLS build fix: wire framing, mappings, focus/freshness gates, pointer gestures, layout compatibility, linked placements, undo/redo, and profile transfer.
- Mac and physical-iPhone builds have succeeded. USB keyboard/mouse play has been exercised during development.
- Wi-Fi encryption is covered by loopback tests. Real-network Wi-Fi and Bluetooth reliability still need broader testing. Guest networks may isolate devices.
- The virtual HID development capability is assigned, but a signed gamepad build has not been validated in games; distribution approval remains pending. Its presence does not establish Xbox/PlayStation identity or game compatibility.
- Native Mac setup screens were rendered and visually checked. See `docs/design/` for UI previews; connected-state previews use fixtures.
- Physical haptics, profile sharing, and behavior across different devices need further hands-on testing.

Run `swift test` to validate the current checkout. Report your OS versions, transport, and reproduction steps when filing an issue; remove pairing codes, device identifiers, and unrelated personal data from logs.

## Release audit — November 6, 2026

- Unsigned universal Mac Release build succeeded (arm64 and x86_64). Fixed an architecture-dependent TLS cipher constant conversion discovered by this build.
- iPhone Xcode Release build could not run because this Xcode installation lacks the required iOS 26.5 platform component. No platform download was started.
- Plist/project syntax and `git diff --check` passed.
- CI workflow added; hosted execution and signed archives remain unverified.
- No app was installed, no user layouts were modified, and no release was uploaded.

## Submission preparation — November 6, 2026

- Added required-reason privacy manifests to both app resource phases and the SDK-only installer.
- Added offline privacy/support screens without changing saved layout storage.
- iPhone source type-check succeeded using the installed iPhoneOS SDK. This is not an archive or App Store validation.
- Unsigned universal Mac archive succeeded; packaged privacy, Bonjour, permission strings, and version resources passed Scripts/check_release_bundle.py.
- 78 Swift tests passed after the privacy/logging changes.
- App Store Connect record created as PocketPad Remote Controller, ID 6831873832. No binary uploaded and no review requested.
- Distribution identities, iOS platform component, final screenshots, real-device release regression, and notarized companion remain outstanding.

## Core experience polish — November 23, 2026

- 100 Swift package tests pass, including five-minute log expiry, byte limits and cursor-switching persistence.
- Mac build/signature verification pass. Merged settings navigation and local marketplace category/search/detail flows were checked in the running app.
- Input trace records Pocket Pad output decisions and its tagged mouse delivery, not system keyboard activity. It retains up to five minutes / 512 KB and prunes while idle. The old rotated history is removed.
- New layouts start without a mode switch. Right-stick cursor switching is optional; legacy layouts retain their existing modes. Keyboard/controller mappings remain shared between modes.
- Marketplace listings are local examples only; there is no upload, download or AI service yet.
- iPhone source build/signing succeeded, but device installation timed out twice. A subsequent launch was denied by iOS with “outstanding termination assertions”; physical-device verification awaits a device restart. Existing layouts were not deleted or reset.
- After restarting the iPhone, installation and launch succeeded. USB connected successfully, the Mac received the saved Minecraft layout and phone dimensions, and all four left-stick direction mappings appeared together with the new combo controls. Returning from the editor preserved the connection. No saved layout was changed during this check.
- November 23 controller investigation: Steam detected/configured PocketPad and the user confirmed its input test works, but Valheim did not respond. macOS HID monitoring received stick events; GCController enumeration returned zero devices. Valheim compatibility remains unresolved pending its per-game Steam Input override/configuration check.
- Fixed a startup input-gating bottleneck: USB/Wi-Fi now carry up to 16 layout chunks per heartbeat instead of one. BLE pacing and the safety gate remain unchanged. All 100 tests pass; signed iPhone build installed and launched successfully. Responsiveness during Steam setup still needs a hands-on retest.

### Valheim generic-controller compatibility diagnosis (2026-11-23)
- User verified Steam's input test works but Valheim still does not respond after explicit per-game Enable Steam Input and restart. Steam log confirms activation for app 892970 at 16:59:16.
- Read-only inspection of installed Valheim `globalgamemanagers.assets` found `InputSystem.inputsettings`, followed by the four serialized supported-device names: Gamepad, Mouse, Keyboard, Touchscreen (Gamepad string at offset 341124). Joystick is absent from this list.
- PocketPad currently publishes generic HID VID FFFF / PID 0001. Unity Input System 1.19 documentation states auto-generated HID layouts are Joystick devices even for GenericDesktop/Gamepad usage: https://docs.unity.cn/Packages/com.unity.inputsystem@1.19/manual/HID.html . This explains why Steam can read the device while Valheim's supported-device filter excludes the generic layout. No runtime inspection of Valheim's unsupported-device list was performed.
- No game binaries, Steam mappings, or user layouts were modified. Native controller compatibility remains unresolved; it requires a recognized Gamepad output path, not merely a successful IOHID report or Steam input test. Keyboard/mouse is an alternative output path, not a fix for controller mode.

### Opt-in controller compatibility prototype (2026-11-23)
- Added `CompatibilityHIDReport` with a 64-byte report-ID-1 DS4 USB input layout, correct face/menu/shoulder/stick-click mapping, unsigned stick axes, analog and digital triggers, inactive touch contacts, and sequence field. Output report 5 is accepted but haptics are not implemented.
- `POCKETPAD_EXPERIMENTAL_DS4=1` selects this format and VID 054C/PID 09CC only for that process. The default remains the original generic controller. Product name explicitly identifies PocketPad Compatibility Prototype. This borrowed hardware identity is a local compatibility experiment, not a release-ready device identity or a claim of Sony hardware.
- Decoder/matcher reference: Unity Input System Runtime/Plugins/DualShock/{DualShockSupport,DualShockGamepadHID}.cs on the Unity-Technologies/InputSystem repository. No standalone Unity runtime test has been performed.
- All 104 Swift tests pass, including neutral/extreme axes, each button independently, hat/trigger/counter encoding, and descriptor report lengths. Signed MacGamepad-HID build and codesign verification pass.
- Prototype launched from `/tmp/PocketPadControllerPrototype/Build/Products/Gamepad/MacGamepad.app` with the environment flag. Installed app was not replaced; saved layouts are untouched. Quit the prototype and open the installed Pocket Pad normally to revert.
- Awaiting phone reconnect and Valheim hands-on test. CUA capture timed out. Build success is not evidence of game compatibility.
- Follow-up: launching from the temporary path produced a kernel MACF denial opening IOHIDResourceDeviceUserClient (IOServiceOpen 0xe00002e2). The UI also restored keyboard/mouse mode and disabled Connect based on Accessibility. Prototype launch now explicitly selects gamepad mode without persisting that override.
- Backed up installed app to `/tmp/PocketPad-before-controller-prototype.app`, installed the signed prototype at the usual `/Users/williamwu/Applications/Pocket Pad.app`, and launched via LaunchServices with the experimental flag. USB then connected successfully; UI shows Test1 Aim and Connected. macOS registry confirms VID 054C/PID 09CC, 64-byte input and 32-byte output reports. macOS reports Transport Virtual despite the requested USB property. Apple GCController probe still returns zero. Steam detected the new controller at 17:11:52.
- Asked user to disable Steam Input for Valheim for the direct Unity HID test. Native Apple Game Controller compatibility is not established.

### Layout-selected Xbox / PlayStation output (2026-11-23)
- User reports the PS prototype appears to work in Valheim, with testing still incomplete.
- Controller output now uses SavedLayout.style: Xbox wireless HID report for Xbox, DS4 report for PlayStation. Xbox encodes 16-bit unsigned axes, 10-bit analog triggers, 1-based hat, and the button bits consumed by Unity's XboxGamepadMacOSWireless decoder. This remains experimental and uses compatible hardware IDs for recognition; no universal compatibility claim.
- Session waits for the initial layout before creating gamepad output. A style change releases and closes the old controller before creating the new one. Phone transport stays connected. Games may require restarting after changing controller identity.
- Removed the process-only DS4 override. The current layout's input mode is remembered for reconnects. No phone schema or stored-layout migration needed.
- 108 tests pass, including Xbox report length, axes, triggers, hats, and independent button bit checks. Signed build succeeds. Installed at the normal Pocket Pad app path. Previous working PS-only build preserved at `/tmp/PocketPad-working-PS-prototype.app`.
- Xbox live validation pending: phone listener returned USB error 3 after restart; asked user to reopen PocketPad on unlocked phone. No Xbox device has been verified in-game yet. Keep Valheim Steam Input disabled for direct HID testing.
- 17:37 follow-up: user reconnected. Registry confirms Xbox PocketPad Wireless Controller, VID 045E/PID 0B13, 18-byte input report. Steam selects its Xbox One controller configuration and HIDAPI driver. Valheim was not running at this check; Xbox prompts and gameplay response remain pending hands-on verification.

### View, stick-click hold, and rumble return path (2026-11-23)
- User reports Xbox gameplay generally works but View does not. Corrected View from bit 16 to bit 10 to match Unity XboxGamepadMacOSWireless's V2 state for Series identity 045E:0B13. Regression test checks exact bit.
- Added 0.45-second center dwell (20% normalized stick radius) for L3/R3. Moving before activation cancels that touch's hold; moving afterward preserves the click until touch release/cancellation. Cursor-mode right stick retains trackpad gestures. Dedicated L3/R3 remain available. Gesture resets on view/edit cancellation.
- Added HID motor report decoding (DS4 output 5, Xbox wireless output 3), a bounded latest-value return channel over the existing USB/Wi-Fi/Bluetooth command stream, and Core Haptics continuous playback. Nonzero motor state refreshes every 200ms; phone stops after a 700ms lease, disconnect, editing, or engine stop/reset. Maps two motor strengths to one actuator's intensity/sharpness; not identical physical rumble.
- 113 Swift tests pass; signed Mac and iPhone builds succeed. Installed and launched both; CUA confirms Test1 Aim connected after update.
- A synthetic Xbox HID output pulse (low=45/high=20 for 300ms, then zero) returned success for both SetReport writes. User confirmation of tactile playback, View/map, and radial-menu center hold is pending. Actual Valheim-generated rumble has not yet been verified; unsupported game output formats are not claimed to work.

### Default touch feedback and stick positioning (2026-11-23)
- User confirms previous View/center-hold/test-vibration check works; actual game-generated rumble remains separately unverified.
- Added phone-wide persisted button-haptics switch (default on) and strength (default 50%, light impact), available for presets as well as custom layouts. Existing explicit per-control haptic overrides remain respected; the master switch disables all press feedback. Game rumble is separate.
- Normal stick touch/movement produces no pulse. Center-hold emits one pulse on the L3/R3 activation transition; moving while held does not repeat it.
- Phone-wide left/right stick positioning defaults to center on first contact, with fixed-position choices in Settings. These preferences supersede legacy per-mode floating flags without rewriting stored layouts.
- All 113 Swift tests pass. Signed iPhone build succeeded and installed without deleting app data. Physical feel and settings interaction require hands-on verification on the phone.

### Layout-wide haptics revision (2026-11-23)
- Replaced phone-wide touch haptics and per-button haptic UI with a SavedLayout touchHaptic preference: Off, Light, Medium, Strong. Missing values default to Medium; legacy per-button haptic values are retained in serialized data for compatibility but ignored during playback.
- The one layout choice covers buttons and L3/R3 activation in both modes. Selecting a value for a preset makes a custom copy. Stick positioning remains phone-wide as before.
- Added layout serialization/default regression coverage; all 114 tests pass. Signed Mac and iPhone builds succeeded, installed both, and relaunched. Mac understands the new field so layout edits/transfers preserve it.

### Non-scrolling live controller preview (2026-11-23)
- Live layout no longer uses the editor ScrollView. It fits both available width and height while keeping the phone aspect ratio and fixed on-screen label sizing. Editing retains its scroll container.
- Signed Mac build succeeded and installed. Reconnected USB; UI inspection shows no live scroll area/bar, all three settings entrances visible, and scrolling over the preview leaves UI state unchanged.

### Layout editor control management (2026-11-23)
- Combo rows now expose Remove, including pending empty rows. Canvas background clicks clear selection.
- Add control menu supports custom buttons (16 slots), left/right joystick slots, D-pad, and radial. Existing joystick/D-pad/radial slots cannot be duplicated; removed ones can be restored. Selected controls can be removed. Built-in removal is stored per mode in optional hiddenControls and respected by both Mac and phone; custom removal reclaims its slot. Draft edits support undo/redo and existing Save flow.
- Advanced settings excludes regular mappings and controls already in the inspector; retains timing/mouse tuning/auto-run or controller swap/inversion.
- 115 tests pass including removed-control persistence/validation. Signed Mac/iPhone builds installed. UI checks verified Add button, Remove button, pending-combo Remove, empty-canvas deselection, and advanced-only content. Test draft was discarded without saving changes to the user's layout.

### Combo list, drag scaling, and sparse radial (2026-11-23)
- Combo rows now have aligned number/label/picker/remove columns and separators.
- Editor drag uses a named unscaled canvas coordinate space, avoiding a second scale division. Installed UI verification: a radial dragged from (1427,918) to (1307,798) followed that 120px diagonal movement exactly; undo restored it, no layout saved.
- Sparse radial chooses nearest mapped angular direction; unmapped slots (-1) disappear from phone selector. Tests cover upper/lower and left/right halves, wraparound, zero/one mapped slot, and center cancellation.
- Added preview-only state byte 15 (0 idle, 1 center, 2–9 direction). Mac highlights radial touch/selection and pulses from its custom slots. It never emits game button presses from preview state. Protocol roundtrip and invalid-value tests pass; manual phone-to-Mac radial visual verification remains pending.
- All 117 tests pass. Signed Mac/iPhone builds installed and USB reconnected. Existing malformed-frame test updated for the now-defined byte 15 range.

### Explicit controller identity selector (2026-11-23)
- Added optional SavedLayout.emulatedController; default remains the template style. Mac layout editor and iPhone settings expose Xbox/PlayStation for controller-input layouts. Overrides preserve arrangements, names, and mappings.
- Session rebuilds virtual HID output when effective identity changes. Mac Save applies the draft; phone setting publishes immediately. Games may require a restart to detect replacement hardware.
- All 118 tests pass, including identity override serialization/default behavior. Signed Mac/iPhone builds installed and launched; Mac UI confirms Test1 connected. In-game identity switching remains a manual check.

### D-pad clarity and Stardew navigation investigation (2026-11-23)
- D-pad default radius increased 43→50 on phone and Mac (about 16%). Eight outlined directional sectors match the angular input regions; only the active sector highlights. Center neutral radius is 18% and now matches the drawing. Mac connected screenshot verified.
- Signed Mac and iPhone builds succeeded, installed, launched, and USB reconnected.
- Stardew top-entry navigation remains unresolved. Xbox hat encoder distinguishes Up=1 and released=0, with all hats already covered by tests; no speculative encoding change made. Read-only game preferences show snappyMenus=true and gamepadMode=Auto. Awaiting whether issue affects stick, D-pad, or both and whether discrete release/repress helps.

### D-pad visual refinement (2026-11-23)
- Matched the existing circular controls with low-contrast inset direction boundaries, small chevrons, and a translucent blue active sector. The whole pad no longer highlights when one direction is pressed.
- Preserved the larger default size and existing eight-way hit testing/neutral zone; no controller output changes.
- Mac HID and iPhone signed builds passed; installed both updates without resetting layouts. Reconnected over USB and visually checked the Mac live preview beside the other controls.
- Stardew's top-entry navigation issue remains unverified; this is a visual change only.

### Stardew SDL input capture (2026-11-23)
- Read the controller using the SDL2 dylib bundled with the installed Stardew Valley macOS build (x86_64 diagnostic). It recognizes the virtual device as Xbox Series X Controller.
- User reported completing three D-pad Up taps and left-stick Up/release. Capture contains six Up-on/off pairs, one preceding Right-on/off pair, and two left-stick excursions with negative Y (peak -32365), each returning to idle (-1 on the four signed axes). No Down event or sustained directional state was recorded.
- Probe timestamps are iteration counts, NOT measured elapsed times; do not infer input latency or pulse duration from them. Polling snapshots are not an exhaustive event trace. Extra transitions remain unexplained.
- This confirms the direction sign and observed releases at SDL, but does not establish the cause of the in-game top-row issue. No output change made based on this capture.

### Guide input and Stardew recording review (2026-11-23)
- Added a center Guide control to controller layouts on phone and Mac; retained existing positions/IDs and separate Menu/Options. The control follows emulated Xbox/PS identity and can be moved, removed, or remapped.
- 121 Swift tests passed, including Guide wire round-trip, reserved-bit rejection, mapping/release, both trigger presence, Xbox button bit, and DS4 Guide/sequence separation.
- Inspected frames from the supplied 56-second recording. Visible clipped top game icons and offset system/game cursor positions support a display-coordinate hypothesis, not a proven Pocket Pad defect or a confirmed game fix. Requested a normal-window comparison from the user.
- Found a more specific firsthand report connecting notch/fullscreen clipping and misplaced controller cursor: https://forums.stardewvalley.net/threads/full-screen-on-macbook-m1-camera-notch-cuts-off-part-of-game-content.11144/ (Aug 28, 2025 post). No changes to the game's preferences, display settings, or saves.
- Installed signed Mac/iPhone Guide builds and reconnected USB. Mac live preview shows the new PS center button for the user's current PlayStation emulation, retaining their Xbox-template labels and custom positions.
- User confirmed that leaving fullscreen fixes Stardew's top-entry/selection alignment problem. Same controller configuration working windowed strongly isolates this symptom to the game's fullscreen/display coordinate handling. No Pocket Pad directional compensation was added. Guide's in-game/overlay response still needs a physical press check; packet/mapping tests and connected preview passed.

### Single-mode presentation cleanup (2026-11-23)
- Gate the Mac live mode subtitle and phone settings mode subtitle/name field on `hasCursorSwitching`.
- Disable phone reference placement lookup and ghost rendering when switching is off; hide cross-mode copy/link/outline options on phone and the position-link toggle on Mac. Stored second-mode data remains intact for re-enabling switching.
- Signed Mac and iPhone builds passed and were installed. Reconnected USB; Mac AX verified heading `Test1` without the previous `Aim` suffix. Phone drag appearance is code-checked but has not been visually exercised on-device.

### Emulation-aware default labels (2026-11-23)
- Added shared label resolution: controller defaults follow emulated Xbox/PlayStation identity; saved explicit names override defaults using the original layout-template namespace. Geometry and stored names are not rewritten.
- Phone canvas, Mac canvas/editor, and controller mapping labels use the resolved captions. Explicit names equal to an old default remain custom.
- 122 tests passed, including identity changes, custom face/trigger labels, round-trip persistence, reverse switching, and unchanged placements. Both signed builds passed and were installed. USB reconnect verified Test1 displays Share, Options, L1/L2/R1/R2, and PlayStation face symbols on the Mac preview.

### Duo native-display preparation (2026-11-23)
- Registered the second device and refreshed the existing development profile with both phones. Standard installation-proxy install succeeded; user confirmed the app opens/connects, but reports boxed compatibility presentation with a zoom control.
- Current toolchain is Xcode 26.5 / iOS 26.5 SDK on macOS 26.5.2. Apple documents iOS 27.1+ SDK for full Duo display support; Xcode 27.1 requires macOS 26.6+. Native-display verification is blocked on that toolchain update.
- Replaced UIScreen.main telemetry with actual controller UIView canvas dimensions. Resize callbacks republish dimensions to the Mac; existing resize handling releases touches. Signed iPhone compilation passed with the available SDK. This preparation alone does not remove compatibility mode; not yet installed or fold-tested.
- References: https://developer.apple.com/iphone-duo/prepare/ and https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes

### Movable settings handle and coral icon (2026-11-23)
- Added a draggable phone settings handle with persisted normalized safe-area position, edge clamping, gesture-state cancellation, tap to open, hold to edit, and an accessibility reset action. Connect remains a separate control.
- Generated an Apple Games-inspired coral/red revision of the existing minimal controller mark with built-in image_gen; source and prompt saved in Assets/PocketPad-icon-coral.png and Assets/ICON-CORAL-PROMPT.txt. Regenerated all icon catalog sizes; original artwork retained.
- Signed iPhone and Mac builds passed. Installed on Duo through installation proxy and updated the local Mac app; Mac launch verified. Requested physical drag/tap/persistence check on Duo; not yet confirmed. Original Air has not received this update.
- macOS Tahoe 26.7.3 full installer download is in progress for the subsequent native Duo toolchain update; macOS has not been upgraded or restarted.

### Icon choices and warmer red (2026-11-23)
- User confirmed dragging the settings handle works. Their photo showed the coral icon was pinker than Apple Games; regenerated warmer orange-red primary artwork plus White and Graphite variants using built-in image_gen. Exact generation prompts are in Assets/ICON-{RED,WHITE,GRAPHITE}-PROMPT.txt; source PNGs and catalog exports are in Assets.
- Added native iPhone App icon settings with preview tiles, actual system selection, in-flight disabling, error handling, and foreground refresh. Xcode alternate-icon build settings and the manual installer both bundle White/Graphite icons.
- Signed Mac/iPhone builds passed; checked every alternate icon declaration resolves to bundled 2x/3x PNGs and all previews exist. Installed picker build on Duo and warmer default icon on Mac. Requested on-device system icon-switch verification; pending.

### Icon preview follow-up (2026-11-23)
- User confirmed all Home Screen icon choices work; reported blank in-app previews and a stale-looking system confirmation icon.
- Load SDK-only bundled previews explicitly through UIImage(contentsOfFile:) and force original rendering; retain asset-catalog lookup for Xcode builds. Moved App icon to the final settings section.
- Manual installer now uses build version 2 (overridable), content-specific icon filenames, and 20/29/40/60-point resources at 2x and 3x for each icon. This addresses stale-resource reuse; the OS-owned confirmation appearance still requires device verification.
- Signed device build passed; all previews and 24 system icon PNGs verified present. Installed on Duo without removing its data.

### macOS update handoff (2026-11-23)
- Downloaded Apple's full macOS Tahoe 26.7.3 installer successfully to /Applications/Install macOS Tahoe.app. Installer opened; currently at Apple license agreement, awaiting explicit user acceptance authorization. No macOS installation or restart has begun; Xcode remains 26.5. About 25 GiB free after download.
- Next: accept license only after confirmation, inspect disk/preflight, stop before restart so work can be saved. After macOS update, install Xcode 27.1+ and rebuild to enable native Duo sizing.

### Phone settings polish and Mac assistant prototype (2026-11-23)
- Renamed Use offline to Use disconnected and status Offline to Disconnected. Phone sheet title is Settings, removed mode subtitle from its header, right-aligned Edit layout.
- Replaced settings-handle gesture arbitration with UIKit pan/tap/long-press recognizers. Long press acts at began (0.5 seconds), tap waits for pan/hold failure, dragging uses window coordinates and cancellation resets translation. Signed device build 3 passed and installed on Duo; physical hold timing check requested.
- Added Mac AI helper entry in sidebar, dashboard header and layout toolbar. Native split view shows phone canvas/proposed draft beside a clearly labeled local assistant preview. Two sample edits (size +15%, light haptics) preview before applying; presets create copies; custom edits use guarded base revision. Existing sendLayout transport and acknowledgement update the preview; free-form requests explicitly remain unavailable and marketplace opens the existing placeholder. No external AI calls or credentials.
- Mac build passed, installed and UI inspected. Device disconnected after update, so end-to-end assistant edit acknowledgement is pending reconnect.

### Extended controls and editing (2026-11-25)
- Added Mac physical-key shortcut recording with a review step, Escape/Cancel, four-key bound, local event consumption, and cancellation when the app loses focus. Existing editor output pause remains active. Verified Control+Shift+K capture, Cancel retaining Space, Control+K apply with caption retained, and Undo in the disconnected editor.
- Added shared rectangular geometry for custom buttons and a dedicated keyboard/mouse trackpad; independent normalized dimensions, fitting, optional snapping/alignment guides, conservative overlap outlines, compact/wide/connected-phone previews, and marketplace preview support. Verified adding Trackpad and changing the preview to 932×430; overlap counts changed appropriately. Undid UI test drafts without saving user layout changes.
- Trackpad reuses tap/hold pointer gestures, with optional two-finger scroll and click suppression until both fingers lift. Motion is off by default, calibrated on each RT/R2 hold, with sensitivity/dead zone and aim/steering modes; release, settings, layout changes and backgrounding stop input. Added settings-handle size/fade/opacity preferences. No independent runtime persistence.
- Canonical schema v2, shared fixtures, Swift semantics/compiler and sync protocol 4 updated. AWS chat updated the matching Python validator/tests in its own untracked server work; no deployment.
- `swift test`: 114 tests passed. `server/.venv/bin/python -m pytest tests/test_layout_format.py -q` from server: 45 passed.
- Signed builds passed: MacGamepad-HID / Gamepad at `/tmp/PocketPadControls`, PhoneGamepad / Debug generic iOS at `/tmp/PocketPadControlsPhone`. UI inspected using `/tmp/PocketPadControls/Build/Products/Gamepad/MacGamepad.app`, after stopping the old PocketPadCreationFlow process. Narrow-window toolbar wrapping corrected and rechecked.
- Pending physical-device acceptance: two-finger scrolling and tap/hold arbitration, motion axis direction/feel and recalibration in both landscape orientations, settings-handle fading/touch reachability, and live phone/Mac sync of extended documents. No phone installation, release, or TestFlight upload in this change.
