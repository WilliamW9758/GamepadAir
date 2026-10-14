#!/usr/bin/env python3
"""Build/sign/install the simple iPhone app without Xcode destination discovery.

Uses the existing iPhoneOS SDK, signing identity, and provisioning profile.
No downloads or account/provisioning changes. Run with --help for options.
"""
import argparse
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def run(*command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, type=Path, help="Existing .mobileprovision for PhoneGamepad")
    parser.add_argument("--device", required=True, help="Connected device identifier from xcrun devicectl list devices")
    parser.add_argument("--build-only", action="store_true", help="Build and sign without installing")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    decoded = run("security", "cms", "-D", "-i", str(args.profile), capture_output=True).stdout
    profile = plistlib.loads(decoded)
    if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        parser.error("Provisioning profile expired; refresh it in Xcode first.")
    entitlements = dict(profile["Entitlements"])
    identifier = entitlements["application-identifier"]
    _, bundle_id = identifier.split(".", 1)
    if "*" in identifier or not bundle_id.endswith(".iphone"):
        parser.error("Use the explicit provisioning profile for the PhoneGamepad app.")
    entitlements["keychain-access-groups"] = [identifier]
    certificates = profile.get("DeveloperCertificates", [])
    if not certificates:
        parser.error("Profile does not contain a development certificate.")
    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture_output=True, text=True).stdout.upper()
    identity = next((hashlib.sha1(cert).hexdigest().upper() for cert in certificates
                     if hashlib.sha1(cert).hexdigest().upper() in identities), None)
    if identity is None:
        parser.error("No installed signing identity matches this profile. Set up signing in Xcode first.")
    sdk = run("xcrun", "--sdk", "iphoneos", "--show-sdk-path", capture_output=True, text=True).stdout.strip()
    output = Path(tempfile.mkdtemp(prefix="PocketPad-device-"))
    app = output / "PhoneGamepad.app"
    app.mkdir()
    sources = sorted((root / "Sources/GamepadCore").glob("*.swift")) + sorted((root / "Apps/iPhone").glob("*.swift"))
    # File Provider may change source metadata in iCloud Documents during compilation.
    # Compile a stable snapshot outside the synced directory.
    source_dir = output / "Sources"
    source_dir.mkdir()
    snapshot = []
    source_hashes = {}
    for source in sources:
        content = source.read_bytes()
        source_hashes[source] = hashlib.sha256(content).digest()
        staged = source_dir / source.name
        staged.write_bytes(content)
        snapshot.append(staged)
    print("Building with the installed iPhoneOS SDK; no download required…", flush=True)
    run("xcrun", "--sdk", "iphoneos", "swiftc", "-swift-version", "5", "-parse-as-library",
        "-emit-executable", "-target", "arm64-apple-ios17.0", "-sdk", sdk,
        *map(str, snapshot), "-o", str(app / "PhoneGamepad"), env={**os.environ, "SDKROOT": sdk})
    if any(hashlib.sha256(path.read_bytes()).digest() != digest for path, digest in source_hashes.items()):
        parser.error("Source contents changed while building; run again to install the latest version.")
    info = {
        "CFBundleExecutable": "PhoneGamepad", "CFBundleIdentifier": bundle_id,
        "CFBundleName": "Pocket Pad", "CFBundleDisplayName": "Pocket Pad",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"], "MinimumOSVersion": "17.0",
        "NSBonjourServices": ["_pocketpad._tcp"],
        "NSLocalNetworkUsageDescription": "Connect Pocket Pad to your Mac over your local Wi-Fi network.",
        "NSBluetoothAlwaysUsageDescription": "Connect Pocket Pad controls to your Mac using Bluetooth.",
        "LSRequiresIPhoneOS": True, "UIDeviceFamily": [1], "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    }
    # Standalone PNG icons avoid actool's simulator-runtime dependency in this
    # SDK-only installer. Normal Xcode builds use the asset catalog.
    for pixels, scale in [(120, 2), (180, 3)]:
        shutil.copyfile(root / f"Assets/AppIcon.xcassets/AppIcon.appiconset/icon-{pixels}.png",
                        app / f"AppIcon60x60@{scale}x.png")
    info["CFBundleIcons"] = {"CFBundlePrimaryIcon": {
        "CFBundleIconFiles": ["AppIcon60x60"], "UIPrerenderedIcon": True}}
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    (output / "Entitlements.plist").write_bytes(plistlib.dumps(entitlements))
    shutil.copyfile(args.profile, app / "embedded.mobileprovision")
    run("codesign", "--force", "--sign", identity, "--entitlements", str(output / "Entitlements.plist"), str(app))
    run("codesign", "--verify", "--strict", str(app))
    if args.build_only:
        print(f"Built and signed: {app}")
        return
    run("xcrun", "devicectl", "device", "install", "app", "--device", args.device, str(app))
    try:
        run("xcrun", "devicectl", "device", "process", "launch", "--device", args.device, bundle_id)
    except subprocess.CalledProcessError:
        print(f"App installed, but launch failed. Build retained at: {app}")
        print("If the error mentions trust/signing, check iPhone Settings → General → VPN & Device Management → Developer App.")
        print("Trust your own Apple Development profile if prompted, then open Pocket Pad on the phone. See the device error above for other causes.")
        raise SystemExit(2)
    print(f"Installed and launched Pocket Pad. Build: {app}")
    print(f"Profile expires: {profile['ExpirationDate']} UTC. Refresh free signing in Xcode before then.")


if __name__ == "__main__":
    main()
