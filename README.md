# Nova

A focus and task app for Android with a dark glass interface: frosted
glassmorphism, soft neumorphic controls and a Dynamic Island style floating
panel. Built with Flutter. Accounts and data are stored locally on the device.

The full plan and the progress checklist are in [`docs/PLAN.md`](docs/PLAN.md).

## Get the APK

Every run of the **Build Android APK** workflow publishes `nova.apk` in the
repository's **Releases** page. Open the release on your phone and install the
APK (Android will ask you to allow installs from your browser).

The APK is signed with the debug key, which is fine for installing directly.
Publishing to Google Play needs your own keystore.

## Build it yourself

You need the Flutter SDK (stable) and the Android SDK.

```bash
# 1. Download the Inter font (assets/fonts/)
bash tool/get_fonts.sh

# 2. Generate the Android project once (it is not committed)
flutter create --platforms=android --org com.codesoli --project-name nova .
git checkout -- lib pubspec.yaml analysis_options.yaml test README.md
bash tool/patch_android.sh

# 3. Run or build
flutter pub get
flutter run
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
