# Settings audit — November 25, 2026

Reviewed iPhone Settings and editor options; Mac General/About, layout editor, advanced/motion sheets, legacy settings sheet, setup and menu commands; shared labels and privacy copy.

## Changes

- iPhone main Settings now separates saved layouts, current-layout options, connection, device appearance, Help, backups and local data.
- Controller emulation, layout haptics, cursor modes and motion live under Layout options. They still edit the canonical layout and synchronize normally.
- Radial assignment belongs to the selected radial; removed the separate global Show radial button switch. Add control in the editor creates or reveals controls; Remove control handles removal. Existing visible singleton controls and exhausted custom slots cannot be added again.
- Stick centering and tap action belong to the selected stick. They are hidden for a right stick acting as a trackpad. D-pad style already belonged to its selected control.
- Two-finger scrolling/right-click timing belong to the selected trackpad. The right-stick trackpad also exposes its hold timing.
- RT hold-to-aim is a real, distinct hold-and-drag touch gesture, not a gyro activation option. Moved it to the right trigger, renamed it, and expose timing only when enabled. Explain its unavailability while motion is enabled; preserve saved values.
- Removed duplicate shape/position reset in phone control options; kept one reset command. Mode arrangement reset remains in Layout options with confirmation.
- Hide motion activation/tuning when motion is Off on both platforms; fixed wording for keyboard/mouse aiming.
- Removed game-specific Sneak/Attack/Block tap labels. Inputs work with arbitrary mappings and Xbox/PlayStation layouts.
- Show setup again is visible in Help on iPhone and General → Help on Mac, rather than hidden under About.
- Removed unreachable legacy Mac Settings sheet and unused standalone Diagnostics destination, including stale import-to-sync/disconnect-to-edit instructions. Diagnostics remain in General. Kept Mac file-menu backup commands and collapsed phone Layout backups; marketplace is not a replacement for private/offline backups.
- Corrected in-app privacy text that still claimed there were no accounts or cloud layouts; described the current optional marketplace sign-in/submissions and GitHub update requests.

## Deliberately retained

- Matching layout options on Mac and iPhone are access from two devices to the same document, not independent duplicate preferences.
- Touch haptics and game rumble are distinct; haptics remain per layout, not per button.
- Connection transport/pairing controls remain available without resetting layouts.
- Clear layouts and erase local data have different scopes and retain destructive confirmations.
- Automatic updates, permissions and logs are Mac app settings; settings-button appearance and app icons are iPhone device settings.

## Follow-up observations

- Mac still lacks direct editors for several phone gesture options (stick centering/taps and trigger drag timing). These are preserved in downloaded/synchronized layouts; this is a parity gap, not a duplicate setting.
- Account deletion and backend retention need a coordinated server/privacy review before the public App Store release; signing out must not be described as deleting server data.
- This pass does not change the layout schema or gesture runtime and does not reset existing settings. Device usability verification is separate from successful builds.
