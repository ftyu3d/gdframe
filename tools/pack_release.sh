#!/usr/bin/env bash
# Pack dist/gdframe.zip. Zip root is addons/.
# Usage: ./tools/pack_release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP_PATH="$ROOT/dist/gdframe.zip"

if [[ ! -f "$ROOT/addons/gdframe/plugin.cfg" ]]; then
	echo "Missing plugin: $ROOT/addons/gdframe" >&2
	exit 1
fi

mkdir -p "$ROOT/dist"
rm -f "$ZIP_PATH"
(
	cd "$ROOT"
	zip -r -q "$ZIP_PATH" addons
)
echo "Created: $ZIP_PATH"
