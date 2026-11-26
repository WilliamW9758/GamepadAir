# Mac automatic updates

The standalone Mac app uses Sparkle 2.10.1. Builds 13 and earlier have no updater and need one manual installation of an updater-enabled build. iPhone updates remain managed by TestFlight.

The app checks automatically and defaults to downloading/installing updates automatically. Users can change both preferences in General → Updates, or choose Gamepad Air → Check for Updates. Sparkle manages scheduling, relaunch UI, and installation; the app's normal termination handler stops controller output before quitting. Installing an update preserves Application Support and Keychain data.

## Trust and hosting

- Feed: `https://raw.githubusercontent.com/WilliamW9758/GamepadAir/main/updates/macos.xml`.
- Archives: the existing GitHub Release DMGs, signed with Developer ID, notarized and stapled.
- Sparkle Ed25519 signature is checked before extracting the archive.
- Public key is in `Config/MacInfo.plist`. Private key is in this Mac's login Keychain under Sparkle's signing-key service, account `gamepadair`. It is never committed or embedded in either app.
- Securely back up the signing key before changing development Macs (Sparkle's `generate_keys --account gamepadair -x` exports it; protect that file as a credential).
- Both beta and eventual stable updates use this feed. Only publish tested, compatible builds to it. Do not publish a beta here after switching the audience to stable releases without introducing explicit channels.

## Each Mac release

1. Increment `CURRENT_PROJECT_VERSION`; archive, Developer ID export/notarize, staple, and run the usual release checks.
2. Create the DMG with `Scripts/package_mac_release.sh`.
3. Run `Scripts/prepare_mac_update.sh /path/to/Sparkle/bin /path/to/GamepadAir-1.0-buildN.dmg /tmp/macos-N.xml`. Use the pinned Sparkle tools from the package artifact or official 2.10.1 distribution. This checks the Keychain public key, infers the actual bundle version and minimum macOS version, and signs the DMG.
4. Upload the unchanged DMG to `v1.0-beta.N` on GitHub. Verify the public download and checksum. Never replace an asset after signing it.
5. Copy the prepared XML to `updates/macos.xml`, review the version/URL/signature, and push it to `main` **only after the download is live**. Publishing this feed offers the update to installed clients.
6. Check for Updates from the previous updater-enabled release and verify install/relaunch, version, layouts, pairing, permissions and controller output. An initial empty feed means no update is offered; it is not an install test.

`Scripts/sync_project_sources.py` preserves and registers the Mac-only Swift package dependency. Do not regenerate the signing-configured Xcode project with the old bootstrap generator. `Package.resolved` pins the framework version; no dependency is added to the iPhone or shared-core package.
