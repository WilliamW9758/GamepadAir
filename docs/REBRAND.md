# Gamepad Air branding

Public name: **Gamepad Air**. GitHub: https://github.com/WilliamW9758/GamepadAir.

The November 25, 2026 rebrand preserves bundle IDs, OAuth callbacks and scopes, Keychain services, Bonjour/Bluetooth identifiers, local Application Support paths, layout format identifiers, and icon asset names. These are compatibility identifiers, not product copy. Do not bulk-replace `pocketpad` across the codebase.

Both Xcode products are now `Gamepad Air.app`; schemes and executable names remain PhoneGamepad and MacGamepad. Packaging scripts and CI use the new product paths.

Historical beta 11 downloads, signed archives, provisioning profile names, validation records and screenshots may retain Pocket Pad. Do not rewrite signed historical binaries. New release archives are needed to deliver the new branding to TestFlight testers.

The separately managed AWS service and Apple Sign in with Apple service display names should be updated by their deployment owner without changing auth identifiers or callback URLs. Domain/DNS configuration awaits domain registration.
