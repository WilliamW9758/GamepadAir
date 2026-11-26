# Mac updater verification — 2026-11-26

## End-to-end result

Passed a real Sparkle download/install/relaunch against the public build 14 feed and DMG, without changing either public artifact. Because public build 13 predates Sparkle, the starting app was a private test build numbered 13, compiled from the current updater code and signed with the team's Developer ID. It ran from `~/Applications/Updater Test/Gamepad Air.app` with the normal app bundle identifier and actual local application data.

- Launch found version 1.0 (14) and displayed the in-app update notice without taking focus.
- Opening the notice showed Sparkle's downloaded-and-ready state.
- Clicking **Install and Relaunch** replaced the test app and launched build 14 from the same path.
- Strict deep signature verification passed; Gatekeeper accepted the installed app as **Notarized Developer ID**.
- The canonical layout file was byte-identical before and after installation (SHA-256 `0dcbce9eeaa6e39c710f5879521bd942f7fa6a1f45a0f6e1e2596d4bd3f8eac1`). The layout library opened with its existing entries and selection.
- Stored wireless code, host, phone endpoint and transport preferences compared equal. No secret values were printed.
- Backups of the original app, preferences and layout file are in `~/PocketPad Backups/Updater-e2e-20261126`.

No phone was connected during this test. Live wireless reconnection and Keychain-backed marketplace login were not exercised. The six-hour timer was configured, not observed for six wall-clock hours. A future release should also be tested from the unmodified public build 14 to its successor.

## Update notice behavior

The updater checks immediately after startup if the user has enabled automatic checks. Sparkle owns subsequent scheduled checks, every six hours by default. A discovered update appears in a nonmodal banner; **View update…** brings Sparkle's update UI forward. Scheduled checks do not steal focus during a game. Sparkle remains responsible for download verification, installation, relaunch and persisted user preferences. Automatic checks/downloads can still be disabled in General settings.

The downloaded-update reminder interval is twelve hours. The banner is set on discovery, so users need not wait for that interval to see that a new version exists. Attention to the update or finishing the update session clears the banner. No custom timer competes with Sparkle's scheduler.

The new notice code is a development change for the next release; the immutable public build 14 remains unchanged.
