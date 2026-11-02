#!/usr/bin/env bash
# Runs after flutter create. Installs the native Android system-island layer.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  echo "AndroidManifest.xml not found. Run flutter create first." >&2
  exit 1
fi
sed -i 's/android:label="[^"]*"/android:label="Nova"/' "$MANIFEST"

PACKAGE_DIR="$ROOT/android/app/src/main/kotlin/com/codesoli/nova"
mkdir -p "$PACKAGE_DIR"
cp "$ROOT/tool/android-src/MainActivity.kt" "$PACKAGE_DIR/MainActivity.kt"
cp "$ROOT/tool/android-src/NovaIslandService.kt" "$PACKAGE_DIR/NovaIslandService.kt"
cp "$ROOT/tool/android-src/NovaNotificationListener.kt" "$PACKAGE_DIR/NovaNotificationListener.kt"

for permission in \
  android.permission.SYSTEM_ALERT_WINDOW \
  android.permission.FOREGROUND_SERVICE \
  android.permission.FOREGROUND_SERVICE_SPECIAL_USE \
  android.permission.POST_NOTIFICATIONS \
  android.permission.ACCESS_NETWORK_STATE \
  android.permission.BLUETOOTH \
  android.permission.BLUETOOTH_CONNECT \
  android.permission.READ_PHONE_STATE; do
  if ! grep -q "android:name=\"$permission\"" "$MANIFEST"; then
    sed -i "/<application/i\\    <uses-permission android:name=\"$permission\" />" "$MANIFEST"
  fi
done

if ! grep -q 'NovaIslandService' "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
services = """
        <service
            android:name=".NovaIslandService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="User-enabled floating activity and notification display" />
        </service>
        <service
            android:name=".NovaNotificationListener"
            android:label="Nova notification access"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>
"""
s = s.replace("</application>", services + "\n    </application>")
p.write_text(s)
PY
fi
grep -nE 'android:label|NovaIslandService|NovaNotificationListener|uses-permission' "$MANIFEST"
