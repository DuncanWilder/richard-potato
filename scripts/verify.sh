#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ $# != 0 && $# != 3 ]]; then
  echo "Usage: $0 [audio-file expected-text locale]" >&2
  exit 1
fi
mkdir -p .verify
EVIDENCE_DIR="$(mktemp -d "$ROOT/.verify/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
exec > >(tee "$EVIDENCE_DIR/verify.log") 2>&1
echo "Evidence: $EVIDENCE_DIR"
echo "Permission prompts need a human click. Do not reset permissions or delete settings."
SETTINGS="$HOME/Library/Application Support/Richard Potato/settings.json"
settings_hash() {
  if [[ -f "$SETTINGS" ]]; then
    shasum -a 256 "$SETTINGS" | awk '{print $1}'
  else
    echo absent
  fi
}
BEFORE="$(settings_hash)"
printf '%s\n' "$BEFORE" > "$EVIDENCE_DIR/settings-before.sha256"
# Use the normal Debug build, stable signing identity, and relaunch path.
./scripts/dev.sh
APP="$ROOT/build/debug/RichardPotato.app"
for _ in {1..50}; do
  if pgrep -x RichardPotato >/dev/null; then break; fi
  sleep 0.1
done
sleep 2
PID="$(pgrep -x RichardPotato)"
if [[ "$PID" == *$'\n'* ]]; then
  echo "Multiple app processes found; cannot confirm the build." >&2
  exit 1
fi
RUNNING_PATH="$(ps -p "$PID" -o comm=)"
if [[ "$RUNNING_PATH" != "$APP/Contents/MacOS/RichardPotato" ]]; then
  echo "Unexpected executable: $RUNNING_PATH" >&2
  exit 1
fi
printf 'PID: %s\nExecutable: %s\n' "$PID" "$RUNNING_PATH" > "$EVIDENCE_DIR/process.txt"
AFTER="$(settings_hash)"
printf '%s\n' "$AFTER" > "$EVIDENCE_DIR/settings-after.sha256"
if [[ "$BEFORE" != absent && "$BEFORE" != "$AFTER" ]]; then
  echo "Settings changed during startup. Inspect migration or concurrent edits before proceeding." >&2
  exit 1
fi
codesign -d -r- "$APP" > "$EVIDENCE_DIR/signature.txt" 2>&1
if ! /usr/sbin/screencapture -x "$EVIDENCE_DIR/launch.png"; then
  echo "Screen capture failed. A human must grant Screen Recording access to the agent host." >&2
  exit 1
fi
[[ -s "$EVIDENCE_DIR/launch.png" ]]
if [[ $# == 3 ]]; then
  source "$ROOT/scripts/toolchain.sh"
  xcrun swiftc -sdk "$SDKROOT" -parse-as-library scripts/verify-audio.swift -o "$EVIDENCE_DIR/verify-audio"
  "$EVIDENCE_DIR/verify-audio" "$1" "$2" "$3" > "$EVIDENCE_DIR/audio.txt" 2>&1 &
  AUDIO_PID=$!
  # Bound model/service failures without leaving an analyzer running.
  for _ in {1..120}; do
    if ! kill -0 "$AUDIO_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if kill -0 "$AUDIO_PID" 2>/dev/null; then
    kill "$AUDIO_PID"
    wait "$AUDIO_PID" || true
    echo "Silent recognition timed out; see audio.txt." >&2
    exit 1
  fi
  if ! wait "$AUDIO_PID"; then
    cat "$EVIDENCE_DIR/audio.txt"
    echo "Silent recognition failed; see audio.txt." >&2
    exit 1
  fi
  cat "$EVIDENCE_DIR/audio.txt"
fi
echo "Launch and settings check passed. No audio was played."
echo "Follow VERIFY.md for UI, permission, and interactive microphone checks."
echo "Save further screenshots in $EVIDENCE_DIR and upload with gh --attach."
