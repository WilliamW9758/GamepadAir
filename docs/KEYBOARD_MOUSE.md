# Keyboard and mouse mode

This mode translates the iPhone controls into macOS keyboard and mouse events over the existing USB connection. It requires Accessibility permission for the Mac companion, but does not require Apple's restricted virtual HID entitlement or a paid developer account.

## Playing

1. Open Pocket Pad on the connected iPhone and the updated Mac companion.
2. Start your game on the Mac. Select **Keyboard / mouse**, then choose the game in **Target app**. Use **Refresh** if it was launched after the companion.
3. Use **Enable Accessibility** and enable the companion under System Settings → Privacy & Security → Accessibility. Return to the companion afterward. Relaunch it if macOS requests that.
4. Select **Mappings…** to customize controls. Changes save automatically on this Mac. Close the editor and select **Connect USB**.
5. Bring the selected game to the foreground and release all iPhone controls once to arm input.

Output pauses when another app takes focus, input becomes stale, or the phone enters its layout editor. Controls held through an interruption must be released individually before they resume. Other controls remain usable; a held movement stick no longer blocks a new attack press. Disconnecting releases generated keys and mouse buttons. Opening the Mac mapping editor disconnects the session; reconnect after editing.

## Starter mapping

| iPhone control | Output |
| --- | --- |
| Left stick | W / A / S / D, including diagonals |
| Right stick | Mouse movement |
| A / × | Space, held while pressed |
| B / ○ | RMB + Space, one tap per press |
| X / □ | E |
| Y / △ | R |
| LT / L2 | Right mouse button |
| RT / R2 | Left mouse button |
| LB / L1 | Shift |
| RB / R1 | Middle mouse button |
| Back / Share | Tab tap |
| Start / Options | Escape tap |
| Left stick click | Control |
| Right stick click | Q tap |
| D-pad up / right / down / left | 1 / 2 / 3 / 4 tap |

This is an editable starting point; match it to your game's bindings. Key labels refer to physical US keyboard positions. The game receives keyboard/mouse input and will generally show keyboard prompts; movement through WASD is digital.

## Custom controls and combos

Each virtual control can map to zero to four keyboard keys or mouse buttons. Empty mappings do nothing. The first selected input is pressed first, followed by the others with a configurable short delay. All inputs overlap, then release in reverse order.

**Hold** keeps the combination down while the virtual control is held. **Tap** completes one short combination per press, including when you quickly lift your finger. Tap does not repeatedly fire while held. Very rapid presses that overlap an already-running tap on the same control are ignored rather than queued.

For dodge, select **B / ○**, choose **Right mouse** followed by **Space**, and select **Tap** (or use the dodge preset). The default interval is 30 ms between inputs and 120 ms holding the completed combination. Adjust these if a game needs more time to recognize block before jump. If another control already holds RMB, dodge keeps that shared RMB held afterward.

Mouse speed, aim smoothing, vertical inversion, stick activation threshold, combo spacing, and tap duration are configurable. Aim smoothing defaults to 25 ms; increase it for gentler changes or lower it for faster response (0 disables smoothing). Mouse output defaults to a 1 ms timer target (1000 Hz), independently of USB frames; **Mouse updates** also offers 500 and 250 Hz. Actual event delivery depends on scheduling and movement speed; this does not raise the iPhone touch sampling rate. Releasing the stick stops movement immediately, without a smoothing tail. Turn off right-stick mouse movement to map its four directions to keys instead. Button positions and sizes remain editable on the iPhone with **Edit layout**; input is paused while arranging them.

## Compatibility

Use the updated phone and Mac builds together: the phone now sends an explicit pause flag during layout editing. Older Mac builds may disconnect when receiving that flag.

Game compatibility must be checked in the actual game after Accessibility is granted. Games differ in how they handle synthetic mouse movement and key events, particularly when capturing the cursor. This mode does not create a system gamepad.

## Auto-run

In **Mappings**, enable **Auto-run beyond left-stick threshold**. Adjust **Run radius** from 20–95% of the stick travel; the default is 80%. The boundary is circular, so diagonal and straight movement use the same radial distance. Auto-run holds Shift outside this boundary and releases five percentage points inside it, avoiding rapid toggling near the threshold. Returning to center, pausing, or disconnecting releases it.

Use **Run mapping…** to choose a different key or combination; auto-run always holds its mapping. Shift stays down if another virtual control still holds it. The toggle is off by default and settings are saved on the Mac. Reconnect after editing. Only the Mac app needs updating for this feature.

## Named buttons and quick bar

On the phone, enter **Edit layout → Buttons → Add quick bar 1–8**. This adds eight movable, resizable buttons whose default Mac mappings tap number keys 1–8. Existing slot mappings on the Mac remain unchanged if you customized them previously.

Use **Add custom button** for individual controls, up to 16 per Xbox/PlayStation layout. Tap a control in edit mode, then choose **Buttons → Rename selected control** to rename either an existing or custom button (up to 20 characters). Blank names restore the default label. Names and positions save separately for each layout.

Custom controls have stable slots: the rename dialog identifies the corresponding **Custom 1** through **Custom 16** in the Mac mapping editor. Phone labels do not synchronize to the Mac. Changing a label does not change a binding. Slots 9–16 are initially unmapped; assign a key, mouse button, or combo on the Mac. Renaming standard controls preserves their original A/B/X/Y/etc. identity in the Mac editor.

**Remove selected button** removes a custom control from the current phone layout. Its Mac mapping is retained if you reuse that slot later. **Reset layout** removes custom controls and names for that layout as well as resetting positions. Custom controls currently produce keyboard/mouse mappings; they do not extend the experimental HID gamepad descriptor.

Update both apps together: custom button states use previously reserved frame bytes, so older Mac builds reject them. The updated phone is installed; quit and reopen the updated Mac companion before trying the new controls.

Triggers now stay held when their captured finger drifts outside the circle; lift the finger to release. This avoids accidental attack/block releases during multi-touch aiming. Face/custom buttons retain their slide-out release behavior.

## Hold attack to aim

RT/R2 now has **hold-to-aim**, enabled by default. It presses its usual attack binding immediately. After 0.3 seconds it becomes a floating aiming stick: keep the same finger down and drag to steer the camera while holding the bow. The aiming center is the finger position when the delay expires, so activation itself does not move the camera. Farther displacement means faster turning; returning to that center stops turning. Lifting releases attack and restores the normal button.

On iPhone, **Edit layout → Buttons → RT hold-to-aim** toggles the feature; **Aim hold delay** offers 0.2, 0.3, 0.5, and 0.8 seconds. These settings save on the phone. Short taps remain ordinary attack presses. The floating stick takes priority over the normal right stick while active; after release the normal stick resumes if another finger still holds it. Cancellation, backgrounding, layout editing, and resizing clear the gesture.

This gesture sends RT plus right-stick axes over the existing connection. Keep the Mac's **RT → LMB / Hold** mapping and **Right stick moves the mouse** enabled for bow aiming. No Mac update is needed. Other remapped attack controls do not gain this gesture automatically.

## Input diagnostics

The Mac **Input log** button opens a bounded local trace at `~/Library/Application Support/PocketPad/input-trace.log`. It records Pocket Pad trigger edges, generated key/button transitions, and focus/permission/USB freshness decisions. It does not monitor physical keyboard input or other apps. One previous log is retained, approximately 512 KB per file. If attack fails, note the approximate time and preserve this log to distinguish missing RT input, output recovery, and game-side behavior.

The delivery diagnostic build also logs `POST_CLICK` and `OS_CLICK` for Pocket Pad-tagged mouse events. Matching numbers indicate the event reached the annotated macOS session stream, not that the game acted on it. `OBSERVER unavailable` means macOS did not permit that observation; absence of observed events in that case is not proof of dropped clicks. Physical mouse clicks and keyboard events are excluded from observation logs.

## Relative game aiming and cursor drift

**Relative game aiming (prevent cursor drift)** in Mac Mappings is enabled by default. Camera movement sends relative deltas while retaining a valid absolute cursor position. This prevents prolonged aiming from pushing subsequent attack clicks outside the display. An already off-display position is recovered to the nearest display's center. Mouse-down/up and drag positions use the same valid coordinate policy.

Turn this option off if you want the stick to move a visible desktop/menu pointer; desktop movement remains constrained to active displays. You can also use the physical trackpad for menus while relative game aiming stays enabled. Reconnect after changing the option. Reconnect after changing display arrangements so the session picks up the new bounds.

## Switching between gameplay and menus

Use the **Aim · tap for Cursor** / **Cursor · tap for Aim** button on the iPhone status bar during play. No disconnection is needed.

- **Aim:** the right stick and held RT aiming gesture turn the camera without moving the absolute cursor off-screen.
- **Cursor:** the right-stick area becomes a trackpad. Swipe to move the visible pointer; lifting or stopping your finger stops movement. Tap for a left click; hold still for a right click (0.5 seconds by default). Swiping cancels the tap/hold click gesture. RT still clicks and holds for dragging; its hold-to-aim transformation is disabled in this mode.

Switching releases all held controls. Switch back to Aim when closing the game menu. The phone's explicit mode overrides the Mac relative-aim setting; the Mac setting remains the fallback for older phone clients. The app starts in Aim mode. Update both apps together because the mode uses a formerly reserved protocol byte.


### Trackpad and scroll mappings

Change the right-click threshold under iPhone **Edit layout → Buttons → Trackpad right-click hold** (0.3, 0.5, or 0.7 seconds). A stationary hold clicks once when the threshold passes; lifting afterward does not left-click. Trackpad motion uses two screen pixels per finger point and bypasses the analog stick's velocity smoothing. The area retains the right stick's saved position and size.

Mac **Mappings → Input** now includes **Scroll up** and **Scroll down**, including in custom-button mappings and combos. **Tap** sends one wheel step; **Hold** sends one step immediately, then repeats at 10 steps/second after 0.35 seconds. Release, disconnect, or loss of game focus stops repetition. Both apps must be updated for trackpad commands. Quit and reopen the Mac companion, then reconnect USB.


### Mouse timing diagnostics

The Mac output timer targets 1000 Hz by default (Mappings → Mouse updates). This synthesizes continuous analog-stick motion; it is not a claim of 1000 Hz iPhone touch sampling or guaranteed game event delivery. Phone state heartbeats are 60 Hz, with touch changes sent immediately. Cursor trackpad displacement remains event-driven.

The timing update moves diagnostic disk writes to a utility queue. Focus is checked at most every 8 ms and Accessibility permission every 250 ms; pause and USB freshness are still evaluated each output tick. This bounds extra focus-change detection latency to roughly 8 ms under normal scheduling. Every five seconds, Input log reports timer tick count, maximum tick gap, ticks delayed over 8 ms, input frame count, and maximum state-frame arrival gap. These measure app scheduling and arrival timing, not game-rendering FPS or physical USB latency. They help distinguish transport stalls from Mac timer delays; actual smoothness must be verified in Valheim.


## Named layouts, two modes, and full-screen controls

The phone now opens directly to controls. Tap the gear for settings; Done closes the menu. Input is paused while settings or layout editing is open.

**Settings → Saved layouts** selects a named layout, **Save a copy** duplicates it, and **New layout** starts a fresh Xbox or PlayStation arrangement. User layouts save edits automatically. Factory Xbox/PlayStation presets are read-only; copy them before editing. Mac key bindings remain shared across layouts/modes and are not replaced by these phone settings.

The old tuned layout is imported as **Valheim Controls**. Its source `control-layouts-v1` is never overwritten. A byte-for-byte `control-layouts-v1-backup` is also retained on the phone; an external preferences backup was taken before installing the migration. The new catalog uses `named-control-layouts-v2`. Invalid new-catalog data blocks saving instead of silently overwriting it with defaults. Any independently tuned alternate controller style is also imported. Legacy controls are converted from the old safe-area canvas and 78-point header into full-screen coordinates, retaining scale values with a stored base-size conversion factor. Modes copy the old arrangement initially, then save independently.

Every layout has exactly two modes, initially **Aim** and **Cursor**. Select the mode to edit in settings; rename it and choose whether it uses game aiming or a cursor trackpad. Each mode stores its own positions, sizes, labels, custom buttons, D-pad visibility, and gesture options. Tap the circular on-screen mode button to switch. Move/resize it like any other control; renaming it changes that mode's name. Switching releases held inputs.

**Settings → Sticks in this mode** includes independent left/right **center on touch** toggles. The initial touch anywhere inside the stick's hit area becomes its temporary neutral center; the ring follows that center and resets on lift. Optional tap actions select existing semantic mappings (e.g. left stick → L3 for Control/sneak; right stick → RT for attack). Taps require a release within 0.25 seconds with no movement beyond 8 points; dragging out and back is not a tap. Pulses last 0.12 seconds and retain other held inputs. Defaults are off. Right-stick taps in Cursor mode retain trackpad left/right click behavior.

**Settings → Controls in this mode → Move and resize controls** opens editing. Select/drag a control; resize using the bottom slider; the ellipsis menu renames, resets, or removes it. Done returns to play. The controller surface extends into the former top/left/right reserved areas, with only the gear button overlaid during play. Physical screen cutouts and system gestures remain iOS constraints.


## Wireless, live input, and radial controls — 2026-10-05

**Move and resize controls** is now first in phone Settings. Holding the gear for 0.5 seconds enters editing directly; doing this on a factory preset makes an editable copy. Double-tap a control in editing to rename it. **Right control behavior** replaces the old cursor toggle label, with **Camera aim · analog stick** and **Menu pointer · trackpad** choices.

The Mac shows **Interpreted input** from the active output mapper (keys, modifiers, mouse buttons, and wheel tokens), including shared/combo ownership. Movement is identified separately. This is the app's interpreted output, not an acknowledgment that the game consumed it. The phone footer points to this display because Mac mappings are not synchronized back to the phone.

### Wi-Fi

1. Put the phone and Mac on the same local network. On iPhone choose **Settings → Connection → Wi-Fi**.
2. On Mac select **Wi-Fi**, click **Find phones**, select the phone name displayed on the iPhone, and enter its six-digit code. A manual IP address remains available. Choose your output and either a target app or Global input, then Connect.
3. Allow Local Network access if prompted. Close phone Settings to resume controls.

The pairing code is six random decimal digits, including possible leading zeros. Old 16-character codes are replaced automatically. Wi-Fi uses TLS 1.2 with ECDHE-PSK/ChaCha20-Poly1305; no unencrypted fallback or accept-all certificate callback is used. Ephemeral key exchange protects against passive offline PIN guessing from captured TLS traffic. The phone limits unsuccessful connection attempts to five per minute. The Mac validates the code through the TLS handshake. There is no cloud service. Bonjour advertises the phone under an independent device name, and the phone listens on its Wi-Fi interface at port 27184. Discovery names do not derive from the pairing code. Networks with client isolation can prevent a connection. **New pairing code** disconnects the active link and invalidates the old code.

### Bluetooth (experimental)

Choose **Bluetooth** on both apps. On the Mac click **Find phones**, select the phone name shown on the iPhone, then enter its six-digit code. Bluetooth Low Energy discovery uses a service UUID and independent phone name; the connection targets the selected peripheral UUID. Allow Bluetooth access and accept system pairing prompts; no paid developer account is required for this app-to-app Core Bluetooth transport. Keep the phone app open. This connects to the companion app, not to the Mac as a system HID gamepad.

Notifications and the control characteristic require Bluetooth encryption. The Mac subscribes, sends the protocol hello and matching code, and receives the same state/pointer stream as USB. Notification payloads are split at the negotiated maximum update size and reassembled with bounded buffering, ordered sequence validation and a 250 ms active-input watchdog. A 3-second first-frame allowance accommodates initial authentication, after a separately bounded connection setup. Bluetooth latency and throughput depend on negotiated radio timing; a 1000 Hz Mac mouse timer does not imply 1000 Hz Bluetooth sampling. Real-device radio behavior still requires hands-on testing.

Only one transport is active at a time. USB remains the launch default and loopback-only. Backgrounding/locking the phone stops all transports; stale, disconnected or malformed streams release held inputs. macOS Accessibility, pause and freshness gates apply to all three transports. The target-focus gate applies unless Global input is enabled.

### Radial quick bar

Enable **Settings → Radial quick bar → Show radial button** for the current mode. Hold it to reveal eight directions, swipe, and release to select; releasing in the 24-point center zone cancels. Up starts at slot 1 and directions proceed clockwise. Each direction can be **None** or **Custom 1–16**; Custom 1–8 default to number keys 1–8 but retain your existing Mac remappings.

The selector pulses one selected slot for 0.12 seconds and preserves other held controls. Resize, move, or double-tap to rename the radial button like other controls. The optional **Hide separate buttons used by the radial** removes only their visibility from the current mode; it preserves their labels, positions and Mac bindings. Add quick bar restores slots 1–8. All radial settings save per mode and default to disabled, so current layouts do not change automatically.


## Global input and Wi-Fi reachability

In Mac **Keyboard / mouse**, enable **Global input · control whichever app is active** to use all applications without selecting a target. This is opt-in and is not enabled merely because a selected app closes. Accessibility permission, disconnect/stale-input release, and phone menu/edit pauses still apply. Use **Menu pointer · trackpad** on the phone for desktop pointer testing; game-aim mode intentionally keeps the absolute cursor anchored.

Errors 64 (host down) and 50 (network down) are reachability errors, not evidence of an incorrect code. The app now distinguishes these from TLS pairing failures and known Local Network permission denial. **Local Network settings** opens the relevant Mac privacy page. Allow Pocket Pad there and on the phone. Find phones to avoid an outdated address. Guest/shared networks may isolate clients, and VPNs can interfere; this requires a network change rather than a different code.
