#!/usr/bin/env python3
"""Check release privacy/version resources in an .app (not signing or store approval)."""
import argparse
from pathlib import Path
import plistlib


def check(app):
    mac = (app / "Contents").is_dir()
    info_path = app / "Contents/Info.plist" if mac else app / "Info.plist"
    resources = app / "Contents/Resources" if mac else app
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    with (resources / "PrivacyInfo.xcprivacy").open("rb") as stream:
        privacy = plistlib.load(stream)
    if mac:
        assert (app / "Contents/Frameworks/Sparkle.framework").exists(), "Missing updater framework"
        assert info.get("SUFeedURL", "").startswith("https://"), "Missing HTTPS update feed"
        import base64
        assert len(base64.b64decode(info["SUPublicEDKey"], validate=True)) == 32, "Invalid updater public key"
        assert info.get("SUVerifyUpdateBeforeExtraction") is True
    assert info.get("CFBundleIdentifier"), "Missing bundle identifier"
    assert info.get("CFBundleShortVersionString"), "Missing version"
    assert info.get("CFBundleVersion"), "Missing build number"
    assert "_pocketpad._tcp" in info.get("NSBonjourServices", []), "Missing Bonjour service"
    for key in ("NSLocalNetworkUsageDescription", "NSBluetoothAlwaysUsageDescription"):
        assert info.get(key), f"Missing {key}"
    assert privacy.get("NSPrivacyTracking") is False, "Unexpected tracking declaration"
    assert privacy.get("NSPrivacyCollectedDataTypes") == [], "Review changed collection practices"
    reasons = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
               for entry in privacy["NSPrivacyAccessedAPITypes"]}
    assert "CA92.1" in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", [])
    assert "35F9.1" in reasons.get("NSPrivacyAccessedAPICategorySystemBootTime", [])
    print(f"Resource checks passed: {info['CFBundleIdentifier']} "
          f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
    print("Signing, notarization, archive validation, and device testing are separate gates.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    check(args.app)
