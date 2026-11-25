#!/bin/bash
# Local distribution rehearsal. No upload, notarization submission, or publication.
set -euo pipefail
if [[ $# != 2 || ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  echo 'Usage: Scripts/prepare_release.sh BUILD_NUMBER NEW_OUTPUT_DIRECTORY' >&2
  exit 2
fi
build_number="$1"
release_dir="$2"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$release_dir"
release_dir="$(cd "$release_dir" && pwd)"
if [[ -n "$(ls -A "$release_dir")" ]]; then
  echo 'Choose an empty output directory to preserve previous artifacts.' >&2
  exit 2
fi
cd "$repo_dir"
for platform in iphone mac; do
  if [[ "$platform" == iphone ]]; then
    scheme=PhoneGamepad; configuration=Release; destination=generic/platform=iOS
    product="Gamepad Air"; export_options=Config/ExportOptions-AppStore.plist
  else
    scheme=MacGamepad-HID; configuration=Gamepad; destination=generic/platform=macOS
    product="Gamepad Air"; export_options=Config/ExportOptions-DeveloperID.plist
  fi
  archive="$release_dir/$platform.xcarchive"
  xcodebuild -project iPhoneGamepad.xcodeproj -scheme "$scheme" \
    -configuration "$configuration" -destination "$destination" \
    -derivedDataPath "$release_dir/DerivedData-$platform" -archivePath "$archive" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build_number" archive \
    > "$release_dir/$platform-archive.log" 2>&1
  python3 Scripts/check_release_bundle.py "$archive/Products/Applications/$product.app"
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$release_dir/$platform" \
    -exportOptionsPlist "$export_options" -allowProvisioningUpdates \
    > "$release_dir/$platform-export.log" 2>&1
  echo "Exported $platform locally to $release_dir/$platform"
done
