# Project guide

Use ASD-STE100 Simplified Technical English when you communicate with the user.

## Project

Richard Potato is a SwiftUI macOS menu bar app. It uses Apple's Speech framework for dictation. The Swift package has one executable target and a Swift Testing target. The minimum macOS version is 26.0.

- `RichardPotato/RichardPotatoApp.swift` defines the menu bar UI.
- `RichardPotato/AppController.swift` controls the shortcut, capture, and text output.
- `RichardPotato/Services/DictationEngine.swift` prepares the speech model, opens the microphone during capture, and finishes the transcript.
- `RichardPotato/Services/HotkeyMonitor.swift` uses an event tap for the global shortcut.
- `RichardPotato/Services/TextInserter.swift` types text or pastes it into the active app.
- `RichardPotato/Services/PreferencesStore.swift` saves user settings. `AnalyticsStore.swift` saves session counts and duration in Application Support. It does not save audio or transcript text.
- `RichardPotato/Views/ListeningIndicator.swift` draws the fixed, click-through dictation bar. `AppController` controls its state and visibility.

## Build and check

Use the scripts in `./scripts/` for local app checks and release builds:

- `./scripts/dev.sh` stops the running app, builds and signs Debug, and opens the new build. Use it when a fix needs a check in the running app, such as an idle CPU measurement.
- `./scripts/release.sh` builds Release, replaces `dist/`, signs the app, creates a versioned ZIP, and opens `dist/`. Use it to prepare a release.

Read these scripts before a build or a runtime check. Use the Swift command-line tools and the macOS SDK. A full Xcode installation is not required.

CI runs on macOS 26 and checks Debug and Release compilation, Swift Testing, formatting, shell syntax, and app metadata. It does not package or sign an app.

- `./scripts/check.sh` runs all CI checks locally without opening or signing the app.
- `./scripts/test.sh` runs Swift Testing without the XCTest runner. Add `--filter` to select tests.
- `./scripts/format.sh` checks Swift formatting. Use `./scripts/format.sh fix` to apply it.
- `.swift-format` sets four-space indentation, as in BlueSquare.
- `scripts/toolchain.sh` selects an installed macOS 26 SDK when available. Set `SDKROOT` to select another SDK.
- Add tests for deterministic logic in `RichardPotatoTests/`. Automated tests do not check microphone access, Accessibility access, or speech model installation.

To check compilation without opening the app or signing a bundle, run:

```bash
swift build
```

The views use `ViewState`, an alias for the SwiftUI `State` property wrapper, because the macOS 27 command-line tools do not include the new `State` macro plugin. `scripts/build.sh [debug|release]` compiles the executable, creates the app bundle and icon, and runs `scripts/stabilize-signature.sh`. The app version and privacy descriptions are in `Resources/Info.plist`. Both dev and release builds use the `Richard Potato Dev` certificate and remove quarantine. Do not remove these signing steps. The certificate must exist before app packaging can finish. `./scripts/setup-signing.sh` changes the login keychain; do not run it as part of a normal build check.

For a manual check, open the built app, grant Microphone and Accessibility access, and check the shortcut, both activation modes, both text output modes, Settings, and Analytics. A build alone does not verify these actions. The app can install an Apple on-device speech model during setup.

## Source and workspace

Edit source in `RichardPotato/` and package settings in `Package.swift`. Edit app metadata in `Resources/Info.plist`. Do not edit generated files in `build/` or `dist/`. Preserve unrelated work in the checkout.
