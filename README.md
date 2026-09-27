# Richard Potato

Menu-bar dictation for macOS. Press (or press and hold) a shortcut and it transcribes
what you say into whatever app you're typing in. No Dock icon, no API calls, no network
calls — transcription runs on Apple's on-device speech model.

## Signing

Debug and Release builds use the same `Richard Potato Dev` code-signing certificate. The shared
Xcode scheme applies it after each build. `./scripts/release.sh` also applies it to the copy in
`dist/`. This keeps the app's permission identity the same when its code changes. The build
step also removes quarantine inherited from a downloaded source checkout, so macOS does not
run a local build from a new temporary path on each launch.

Run `./scripts/setup-signing.sh` once if the certificate is missing from your login keychain.
The build stops with an error if it cannot find the certificate.

## Open and run

For dev builds (you'll need Xcode installed)

```bash
./scripts/dev.sh
```

Or to generate a release build

```bash
./scripts/release.sh
```

Because the app isn't signed/verified by Apple, it will be blocked when you try running it.

To run it

- Open System Settings
- Privacy & Security
- Scroll all the way down to the bottom
- Find the app, and select open
- And you're done

## Permissions

On first run, grant both:

- **Microphone** — captures audio for transcription.
- **Accessibility** — lets the app see your shortcut globally and paste the result into
  the frontmost app. Privacy & Security → Accessibility.

The menu bar icon shows `mic.slash` whenever the shortcut is inactive, and Settings shows
the live state of both permissions.

### Why permission grants can be lost after a rebuild

The default ad-hoc requirement contains the app's code hash. The hash changes on a rebuild.
The shared scheme now signs both build types with the same certificate. Their requirement is
the bundle ID plus that certificate. You may need to grant access once after this change
because the app's identity has changed. The app no longer opens the Accessibility prompt at
every launch; use the menu bar action if access is missing.

## Why it starts instantly

macOS keyboard dictation is slow to start because it cold-starts the speech stack on every
activation. Instead, this app warms everything up at launch and keeps it warm:

- The microphone tap and `AVAudioEngine` stay running.
- A `SpeechAnalyzer` session is pre-created with `prepareToAnalyze(in:)` and
  `modelRetention: .lingering`, so the on-device model stays resident.
- Audio streams continuously into the analyzer with a small 512-frame tap buffer.

Pressing the shortcut only flips a flag that starts collecting transcript text, so there
is no start-up cost at press time. Releasing the key inserts the final text.

## Settings

Open Settings from the menu-bar icon to configure:

- **Shortcut** — click Change and press any key combination, or a single modifier such as
  Right Option (the default).
- **Activation** — press and hold, or press to start / stop.
- **Microphone** — system default or any specific input device. Changing it re-warms the
  pipeline so the next press is still instant.
- **Text insertion** — how the transcript reaches the focused app:
  - *Paste (⌘V)* (default) — puts the text on the clipboard, sends ⌘V, then restores your
    previous clipboard contents. Instant regardless of transcript length.
  - *Simulated typing* — synthesises keystrokes instead. Leaves the clipboard untouched,
    but is slower and some apps drop characters.
- **On-screen indicator** — Show dictation bar displays a small bar at the bottom of the screen
  only during dictation. Moving bars show recording; a spinner shows that the app is finishing.
  The bar fades in and out and passes clicks through to the app below it.
