# SecureChat — iOS Setup & Run Guide (Mac)

Status as of 2026-09-30: the iOS target is fully pre-configured from the Windows side. On a Mac you only need the standard Flutter toolchain — no flutterfire configure, no plist editing.

## What's already configured

- **Firebase** — `ios/Runner/GoogleService-Info.plist` (Firebase project `chat-e2e86`) is present and committed. `Firebase.initializeApp()` is called with no options, so iOS reads this plist automatically.
- **Bundle ID** — `com.trisentricai.securechat`, matching the Firebase registration exactly. (It was `com.example.secureChat`, which made `Firebase.initializeApp()` fail at startup with a bundle-ID mismatch.)
- **Deployment target** — iOS 15.0 everywhere (Podfile `platform` + `post_install`, Xcode project). Required by Firebase Apple SDK 12 (pulled in by `firebase_core: ^4.x`); the previous 12.0/13.0 mix would have broken `pod install`.
- **Info.plist permissions** — camera, microphone, photo library (read + add), contacts. Without these, `image_picker`, `flutter_sound` (voice messages), `flutter_webrtc` (calls), and the `contacts_service` fork crash on first use.
- **Google Sign-In** — the reversed-client-ID URL scheme is registered in `Info.plist` (`CFBundleURLTypes`), as required by `google_sign_in ^7.x` on iOS.
- **Local pods** — `plugins/contacts_service` ships its own iOS pod; nothing to do.

## Mac prerequisites

1. macOS with **Xcode 16+** from the App Store, then:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```
   Open Xcode once → Settings → Platforms, and install an iOS simulator runtime if none is listed.
2. CocoaPods: `brew install cocoapods` (or `sudo gem install cocoapods`).
3. Flutter SDK (stable): https://docs.flutter.dev/get-started/install/macos — `flutter doctor` should show no issues for the iOS toolchain.

## Run on the iOS Simulator

```bash
cd mobile
flutter pub get
open -a Simulator
flutter devices        # confirm an iOS simulator is listed
flutter run            # first build runs `pod install` — allow several minutes
```

No signing is needed for the simulator. On startup, Firebase should initialize without errors.

- **Google Sign-In** works on the simulator as long as the Google provider is enabled in Firebase Console → Authentication → Sign-in method for the iOS app.
- **Push notifications:** FCM token registration works in the simulator on an iOS 16+ simulator runtime. Actual remote pushes additionally require an APNs Auth Key (`.p8`) uploaded in Firebase Console → Project settings → Cloud Messaging → iOS; the key comes from a paid Apple Developer account.

## Run on a real iPhone

1. Connect the phone, tap *Trust*, and enable Developer Mode (iOS 16+).
2. `open ios/Runner.xcworkspace` — use the **workspace**, not the `.xcodeproj`.
3. Select the Runner target → *Signing & Capabilities* → choose your Apple ID team.
4. `flutter run -d <device-id>` (id from `flutter devices`).

## Troubleshooting

- **`pod install` version conflicts** — `pod repo update`, then retry; ensure CocoaPods ≥ 1.15.
- **Firebase "bundle ID mismatch" / `FIRApp` crash at launch** — stale build: `flutter clean && flutter pub get && flutter run`.
- **Google Sign-In fails with "no valid URL scheme"** — verify `CFBundleURLSchemes` in `Info.plist` still contains `com.googleusercontent.apps.913365185172-…`.
- **Plain-HTTP dev backend** — the ATS exception list in `Info.plist` only covers `10.0.2.2` (the Android emulator loopback). The iOS simulator reaches your Mac at `127.0.0.1`/`localhost`, which ATS blocks for cleartext HTTP. The default path (Supabase/Cloudinary) is HTTPS and needs nothing; only add a temporary local-networking ATS exception if you must hit an insecure dev server from iOS.
- **Changing the bundle ID** — never change `PRODUCT_BUNDLE_IDENTIFIER` without re-registering the app in the Firebase console; `GoogleService-Info.plist` embeds the bundle ID and it is verified at startup.

## CI (Codemagic)

`codemagic.yaml` at the **repo root** defines the `ios-simulator` workflow: pub get → `flutter test` → `flutter build ios --debug --no-codesign`, with `Runner.app` uploaded as an artifact.

1. The repo is not under git yet — `git init`, commit, and push to GitHub/GitLab/Bitbucket first.
2. Sign up at codemagic.io, add the app, connect the repo, and select the `ios-simulator` workflow.
3. Edit the `publishing.email.recipients` address in `codemagic.yaml` before the first build.
4. For signed builds (TestFlight / App Store), add code signing credentials in Codemagic (App Store Connect API key) and extend the workflow — see https://docs.codemagic.io/yaml-publishing/distribution/.
