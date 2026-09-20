#!/usr/bin/env bash
# Pack release ZIP with entries: addons/gdframe/...
# Usage: ./tools/pack_release.sh
# Output: dist/gdframe.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/gdframe"
DIST="$ROOT/dist"
STAGING="$DIST/_staging_gdframe"
ZIP_PATH="$DIST/gdframe.zip"

if [[ ! -d "$SRC" ]]; then
	echo "Missing plugin dir: $SRC" >&2
	exit 1
fi

mkdir -p "$DIST"
rm -rf "$STAGING"
mkdir -p "$STAGING/addons"
cp -R "$SRC" "$STAGING/addons/gdframe"
rm -f "$ZIP_PATH"

(
	cd "$STAGING"
	zip -r -q "$ZIP_PATH" addons
)

rm -rf "$STAGING"
echo "Created: $ZIP_PATH"
