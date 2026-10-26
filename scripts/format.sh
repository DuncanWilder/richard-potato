#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
case "${1:-check}" in
  check) xcrun swift-format lint --strict --recursive Package.swift RichardPotato RichardPotatoTests ;;
  fix) xcrun swift-format format --in-place --recursive Package.swift RichardPotato RichardPotatoTests ;;
  *) echo "Usage: $0 [check|fix]" >&2; exit 1 ;;
esac
