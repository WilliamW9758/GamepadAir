#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Keep build bundles outside iCloud Documents to avoid FinderInfo signing errors.
derived="${TMPDIR:-/tmp}/PocketPadDerived"
xcodebuild -project iPhoneGamepad.xcodeproj -scheme MacGamepad \
    -configuration Debug -derivedDataPath "$derived" build
open "$derived/Build/Products/Debug/MacGamepad.app"
