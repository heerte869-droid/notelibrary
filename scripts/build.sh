#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${NOTELIBRARY_BUILD_DIR:-$ROOT/.build/release}"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Building NoteLibrary requires macOS and Xcode." >&2
  exit 1
fi
xcodebuild -project "$ROOT/macOS/NoteLibrary.xcodeproj" \
  -scheme NoteLibrary -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

APP="$DERIVED/Build/Products/Release/NoteLibrary.app"
# Ad-hoc signing is for a local build; it is not Developer ID signing or notarization.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '\nLocal app: %s\n' "$APP"
