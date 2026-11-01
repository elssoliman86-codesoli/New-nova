#!/usr/bin/env bash
# Runs after `flutter create --platforms=android` to adjust the generated
# Android project (app label, etc.). Safe to run more than once.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"

if [ ! -f "$MANIFEST" ]; then
  echo "AndroidManifest.xml not found. Run 'flutter create --platforms=android .' first." >&2
  exit 1
fi

# Launcher label shown under the icon.
sed -i 's/android:label="[^"]*"/android:label="Nova"/' "$MANIFEST"

grep -n 'android:label' "$MANIFEST"
