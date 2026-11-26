#!/bin/bash
# Generate a signed Sparkle feed from one already-notarized Mac release DMG.
# Does not publish: upload the DMG first, then commit the generated feed.
set -euo pipefail
if [[ $# != 3 ]]; then
  echo 'Usage: prepare_mac_update.sh SPARKLE_BIN_DIR RELEASE_DMG OUTPUT_XML' >&2
  exit 2
fi
sparkle_bin="$1"
dmg="$2"
output="$3"
[[ ! -e "$output" ]] || { echo 'Output already exists; refusing to replace it.' >&2; exit 1; }
name=$(basename "$dmg")
[[ "$name" =~ ^GamepadAir-1\.0-build([0-9]+)\.dmg$ ]] || { echo 'Unexpected DMG name.' >&2; exit 1; }
build="${BASH_REMATCH[1]}"
[[ "$build" -ge 14 ]] || { echo 'Builds before 14 do not have the updater.' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
expected=$(plutil -extract SUPublicEDKey raw "$root/Config/MacInfo.plist")
actual=$("$sparkle_bin/generate_keys" --account gamepadair -p)
[[ "$actual" = "$expected" ]] || { echo 'Signing key does not match the app.' >&2; exit 1; }
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp "$dmg" "$staging/$name"
"$sparkle_bin/generate_appcast" --account gamepadair --maximum-deltas 0 \
  --download-url-prefix "https://github.com/WilliamW9758/GamepadAir/releases/download/v1.0-beta.$build/" \
  -o "$staging/macos.xml" "$staging"
python3 - "$staging/macos.xml" "$build" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = root.findall('./channel/item')
assert len(items) == 1
item = items[0]
assert item.findtext('s:version', namespaces=ns) == sys.argv[2], 'DMG build differs from filename'
enclosure = item.find('enclosure')
assert enclosure.get('{'+ns['s']+'}edSignature'), 'Missing update signature'
assert int(enclosure.get('length')) > 0
PY
cp "$staging/macos.xml" "$output"
echo "Prepared $output. Upload and verify the GitHub asset before replacing updates/macos.xml."
