# Local verification

Run `./scripts/verify.sh` on the developer's Mac before a PR is ready. This
follows the local verification approach from blue-square #15 / PR #16.
Read `scripts/dev.sh` and `scripts/build.sh` first. The script uses the normal
SwiftPM Debug build and stable local signature, stops the old app, opens the new
app, and checks its exact executable path after a startup delay. It does not use
Xcode. It does not change preferences or reset permission grants.

Logs, settings hashes, signature details, process details, and `launch.png` go
into the printed `.verify/<timestamp>-<suffix>/` folder. This folder is ignored
by Git. Existing settings must have the same file hash after startup. A missing
settings file can be created by normal first-run setup. A migration or a
concurrent settings edit causes the hash check to fail; inspect the cause before
you run the script again. Hashes do not prove that every control works.

Run `./scripts/check.sh` too. Fix each failed check. Do not weaken, skip, or delete
a check, test, or lint rule. This workflow is local. It does not change CI,
release packaging, or signing.

## Drive the menu bar UI

Use the available computer-use tools, or macOS System Events through `osascript`,
to make real mouse, keyboard, and Accessibility actions. The app has no Dock
icon. Inspect a screenshot, find the potato icon in the menu bar, and click it.
Use current screen coordinates or Accessibility elements; do not assume fixed
coordinates. Open **Settings…**, inspect the configured shortcut, activation
mode, microphone, and text output method. Open **Analytics…** and check that the
window displays. Save screenshots after each important action:

```sh
/usr/sbin/screencapture -x .verify/<run>/settings.png
/usr/sbin/screencapture -x .verify/<run>/analytics.png
```

Replace `<run>` with the folder printed by the script. The `-x` option disables
the screenshot sound. Inspect each image before upload. Exclude private windows,
transcripts, and other personal information. The launch image proves startup
only. Record the controls used and the results seen in the PR.

Microphone access belongs to the app. Accessibility access is needed for its
global shortcut and text output. The agent host can also need Accessibility and
Screen Recording access. If macOS needs a human click, stop the affected check
and ask the user to grant access in the prompt or System Settings. Report the
blocked check. Do not bypass the prompt, run `tccutil reset`, delete preferences,
or claim that a blocked check passed. Model installation can also need an
interactive setup step and network access.

## Real microphone check (manual and interactive)

Arrange this step with a person who can speak into the selected microphone.
Never use speech playback, tones, or speaker output to supply test speech.

1. Record the current settings so you can restore them. Open a new, unsaved text
   document and put the cursor in it. Wait for the app to be ready.
2. In hold mode, hold the configured shortcut while the person says a known
   phrase. Release it. Check the listening bar, the end of capture, and the
   inserted text. Allow for the one-second capture tail.
3. In toggle mode, press the shortcut to start, speak a different phrase, then
   press it to stop. Check that the second result has no words from the first.
4. Check both text output methods in the test document. Check Analytics for the
   new sessions. Save relevant screenshots, then restore the original settings.

If no person is available, mark this step **not run**. Do not open the microphone
as a substitute for a completed speech check.

## Silent recognizer check

Supply a local speech recording with a known transcript and a supported locale.
Use a non-private fixture that you are permitted to process. No file is played:

```sh
./scripts/verify.sh /absolute/path/fixture.wav 'The expected words' en_US
```

The optional arguments compile `scripts/verify-audio.swift` with the selected
macOS SDK. It reads the file directly into `SpeechAnalyzer`, uses the app's
`SpeechTranscriber` preset, waits for final results, and compares the complete
transcript with the expected words. Case, punctuation, and whitespace do not
affect the comparison. Empty expectations fail. The helper uses the app's model setup API. Model installation can need network access. The check fails
if model setup fails, the file is unreadable, the transcript differs, or
recognition exceeds 120 seconds. Complete setup in the app if required. `audio.txt` contains the
result. No microphone or audio output is opened by this helper.

This checks the on-device recognizer with real audio. It does not check the
microphone, global shortcut, capture timing, listening bar, or insertion into
another app. Use the interactive check for those paths. Keep audio fixtures out
of Git and review transcripts before you upload logs.

## Attach evidence to the PR

Use GitHub CLI 2.99.0 or later (`gh --version`). Keep images in `.verify/`; do not
commit them or push an evidence branch. Use all PR template headings: **What and
why**, **Root cause**, **Verification**, and **Screenshots**. In Verification,
list the actual commands and results, including checks that were blocked or not
run. Put matching local image references in the body file, for example:

```markdown
## Screenshots
![Launch](./.verify/<run>/launch.png)
![Settings](./.verify/<run>/settings.png)
```

From the repository root, create a ready PR after local checks:

```sh
gh pr create --title 'chore: add local app verification' \
  --body-file .verify/pr-body.md \
  --attach ./.verify/<run>/launch.png \
  --attach ./.verify/<run>/settings.png
```

For an existing PR, use `gh pr edit NUMBER --body-file .verify/pr-body.md` with
the same `--attach` flags. Replace `<run>` first. Each image reference must match
an attachment. Check `gh pr view NUMBER --json body --jq .body`: all image links
must use `https://github.com/user-attachments/`. Do not leave local paths or raw
repository image URLs in the PR. Check CI and merge status before handback.
