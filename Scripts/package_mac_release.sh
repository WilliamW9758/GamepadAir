#!/bin/bash
# Package a previously Developer ID signed, notarized, stapled companion.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo 'Usage: Scripts/package_mac_release.sh EXPORTED_APP NEW_DMG_PATH' >&2
  exit 2
fi
app="$1"
dmg="$2"
[[ -d "$app/Contents" ]] || { echo 'Missing Mac .app bundle' >&2; exit 2; }
[[ ! -e "$dmg" ]] || { echo 'Refusing to overwrite an existing package' >&2; exit 2; }
codesign --verify --strict "$app"
signature="$(codesign -dvv "$app" 2>&1)"
[[ "$signature" == *'Authority=Developer ID Application:'* ]] || { echo 'Requires Developer ID signing' >&2; exit 1; }
[[ "$signature" == *runtime* ]] || { echo 'Requires hardened runtime' >&2; exit 1; }
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
staging="$(mktemp -d "${TMPDIR:-/tmp}/pocketpad-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Pocket Pad.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname 'Pocket Pad' -srcfolder "$staging" -format UDZO "$dmg"
hdiutil verify "$dmg"
shasum -a 256 "$dmg"
echo 'Test this DMG on a clean Mac before publishing.'
