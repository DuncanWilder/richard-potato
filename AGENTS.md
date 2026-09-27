# Project guide

Use ASD-STE100 Simplified Technical English when you communicate with the user.

## Project

Richard Potato is a SwiftUI macOS menu bar app. It uses Apple's Speech framework for dictation. The Xcode project has one app target and no test target. The minimum macOS version is 26.0.

- `RichardPotato/RichardPotatoApp.swift` defines the menu bar UI.
- `RichardPotato/AppController.swift` controls the shortcut, capture, and text output.
- `RichardPotato/Services/DictationEngine.swift` prepares the speech model, opens the microphone during capture, and finishes the transcript.
- `RichardPotato/Services/HotkeyMonitor.swift` uses an event tap for the global shortcut.
- `RichardPotato/Services/TextInserter.swift` types text or pastes it into the active app.
- `RichardPotato/Services/PreferencesStore.swift` saves user settings. `AnalyticsStore.swift` saves session counts and duration in Application Support. It does not save audio or transcript text.
- `RichardPotato/Views/ListeningIndicator.swift` draws the fixed, click-through dictation bar. `AppController` controls its state and visibility.

## Build and check

Use Xcode 27 or later. To check compilation without opening the app, run:

```bash
xcodebuild -scheme RichardPotato -configuration Debug -derivedDataPath /tmp/richard-potato-build -quiet build
```

The shared Xcode scheme runs `scripts/stabilize-signature.sh` after Debug and Release builds. It signs both with the `Richard Potato Dev` certificate and removes quarantine from the local app bundle. `./scripts/release.sh` signs its copy in `dist/` with the same certificate. Do not remove these signing steps. The certificate must exist before a build. `./scripts/dev.sh` builds, stops a running copy, and opens the app. `./scripts/release.sh` builds and replaces `dist/`. Use these scripts only when those effects are wanted. `./scripts/setup-signing.sh` changes the login keychain; do not run it as part of a normal build check.

For a manual check, open the built app, grant Microphone and Accessibility access, and check the shortcut, both activation modes, both text output modes, Settings, and Analytics. A build alone does not verify these actions. The app can install an Apple on-device speech model during setup.

## Source and workspace

Edit source in `RichardPotato/` and project settings in `RichardPotato.xcodeproj/`. Do not edit generated files in `build/` or `dist/`. Preserve unrelated work in the checkout.
