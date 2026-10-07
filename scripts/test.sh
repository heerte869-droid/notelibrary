#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${NOTELIBRARY_TEST_BUILD_DIR:-$ROOT/.build/tests}"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Testing NoteLibrary requires macOS and Xcode." >&2
  exit 1
fi
# The shared test scheme isolates storage inside DerivedData and disables
# automatic Codex connection. No provider account is needed by this suite.
xcodebuild -project "$ROOT/macOS/NoteLibrary.xcodeproj" \
  -scheme NoteLibrary -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
