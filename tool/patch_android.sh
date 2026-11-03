#!/usr/bin/env bash
# Runs after flutter create. Installs the native Android layer:
# system island, device readers, voice assistant, accessibility service.
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
for file in "$ROOT"/tool/android-src/*.kt; do
  cp "$file" "$PACKAGE_DIR/$(basename "$file")"
done

RES_DIR="$ROOT/android/app/src/main/res"
mkdir -p "$RES_DIR/xml" "$RES_DIR/values"
cat > "$RES_DIR/xml/nova_accessibility.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagIncludeNotImportantViews|flagReportViewIds"
    android:canRetrieveWindowContent="true"
    android:notificationTimeout="200"
    android:description="@string/nova_accessibility_description" />
XML
cat > "$RES_DIR/values/nova_strings.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="nova_accessibility_description">Lets the Soli assistant read the text on screen, type what you dictate and press buttons when you ask it to.</string>
</resources>
XML

python3 - "$MANIFEST" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text()

if 'xmlns:tools=' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

permissions = [
    ("android.permission.INTERNET", ""),
    ("android.permission.SYSTEM_ALERT_WINDOW", ""),
    ("android.permission.FOREGROUND_SERVICE", ""),
    ("android.permission.FOREGROUND_SERVICE_SPECIAL_USE", ""),
    ("android.permission.FOREGROUND_SERVICE_MICROPHONE", ""),
    ("android.permission.POST_NOTIFICATIONS", ""),
    ("android.permission.ACCESS_NETWORK_STATE", ""),
    ("android.permission.BLUETOOTH", ' android:maxSdkVersion="30"'),
    ("android.permission.BLUETOOTH_CONNECT", ""),
    ("android.permission.READ_PHONE_STATE", ""),
    ("android.permission.RECORD_AUDIO", ""),
    ("android.permission.READ_CONTACTS", ""),
    ("android.permission.READ_CALENDAR", ""),
    ("android.permission.CALL_PHONE", ""),
    ("android.permission.RECEIVE_BOOT_COMPLETED", ""),
    ("android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", ""),
    ("android.permission.SCHEDULE_EXACT_ALARM", ""),
    ("android.permission.PACKAGE_USAGE_STATS", ' tools:ignore="ProtectedPermissions"'),
]
lines = ""
for name, extra in permissions:
    if f'android:name="{name}"' not in s:
        lines += f'    <uses-permission android:name="{name}"{extra} />\n'

query_intents = """        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.HOME" />
        </intent>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
"""
if '</queries>' in s:
    # Flutter's template already has a <queries> block: extend it.
    s = s.replace('</queries>', query_intents + '    </queries>', 1)
else:
    lines += "    <queries>\n" + query_intents + "    </queries>\n"

s = s.replace('<application', lines + '    <application', 1)

components = """
        <service
            android:name=".NovaIslandService"
            android:exported="false"
            android:foregroundServiceType="specialUse|microphone">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="User-enabled floating island, device status and voice assistant" />
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
        <service
            android:name=".NovaAccessibilityService"
            android:label="Soli assistant"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/nova_accessibility" />
        </service>
        <receiver
            android:name=".NovaBootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
"""
if 'NovaIslandService' not in s:
    s = s.replace("</application>", components + "    </application>")

p.write_text(s)
PY
grep -nE 'android:label|Nova[A-Za-z]+|uses-permission|queries' "$MANIFEST"

# Offline wake-word engine (Vosk) for the voice assistant.
GRADLE_KTS="$ROOT/android/app/build.gradle.kts"
GRADLE_GROOVY="$ROOT/android/app/build.gradle"
if [ -f "$GRADLE_KTS" ]; then
  if ! grep -q 'vosk-android' "$GRADLE_KTS"; then
    cat >> "$GRADLE_KTS" <<'KTS'

dependencies {
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    implementation("com.alphacephei:vosk-android:0.3.47")
}
KTS
  fi
elif [ -f "$GRADLE_GROOVY" ]; then
  if ! grep -q 'vosk-android' "$GRADLE_GROOVY"; then
    cat >> "$GRADLE_GROOVY" <<'GRV'

dependencies {
    implementation 'net.java.dev.jna:jna:5.13.0@aar'
    implementation 'com.alphacephei:vosk-android:0.3.47'
}
GRV
  fi
else
  echo "app build.gradle(.kts) not found" >&2
  exit 1
fi
echo "--- gradle dependencies"
grep -n 'vosk\|jna' "$GRADLE_KTS" "$GRADLE_GROOVY" 2>/dev/null || true
