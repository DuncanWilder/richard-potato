#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
version="${RELEASE_VERSION:-}"
notes=""
dry_run=false
plan_only=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --notes-file) notes="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --plan-only) plan_only=true; shift ;;
    *) echo "Usage: $0 [--version X.Y.Z --notes-file FILE] [--dry-run | --plan-only]" >&2; exit 1 ;;
  esac
done

# Without explicit inputs, local releases use the same deterministic plan as CI.
temporary="$(mktemp)"
trap 'rm -f "$temporary"' EXIT
# Bash 3.2 with nounset needs the guarded expansion even for a declared array.
plan_options=()
if [[ "$dry_run" == true ]]; then
  plan_options+=(--commit-titles)
fi
if [[ -z "$version" ]]; then
  version="$(python3 scripts/release-plan.py --notes-file "$temporary" ${plan_options[@]+"${plan_options[@]}"})"
fi
if [[ -z "$notes" ]]; then
  python3 scripts/release-plan.py --notes-file "$temporary" ${plan_options[@]+"${plan_options[@]}"} >/dev/null
  notes="$temporary"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid release version" >&2; exit 1; }
[[ -s "$notes" ]] || { echo "Release notes are empty" >&2; exit 1; }
if [[ "$plan_only" == true ]]; then
  printf 'Planned release: v%s\n' "$version"
  cat "$notes"
  exit 0
fi
tag="v$version"
commit="$(git rev-parse HEAD)"
if [[ "$dry_run" == false ]]; then
  command -v gh >/dev/null
  [[ -z "$(git status --porcelain)" ]] || { echo "Commit changes before publishing" >&2; exit 1; }
  # A queued merge can already be behind the remote tip. Verify reachability,
  # rather than requiring a remote branch to point at this exact commit.
  git fetch origin
  remote_refs="$(git ls-remote origin)"
  if [[ -z "$(git branch -r --contains "$commit")" ]]; then
    echo "Push the current commit before publishing" >&2; exit 1
  fi
  if printf '%s\n' "$remote_refs" | awk '{print $2}' | grep -qx "refs/tags/$tag"; then
    echo "Tag $tag already exists" >&2; exit 1
  fi
fi

RELEASE_VERSION="$version" RELEASE_NO_OPEN=true ./scripts/release.sh
archive="$ROOT/dist/Richard-Potato-$version.zip"
[[ -s "$archive" ]] || { echo "Release archive is missing: $archive" >&2; exit 1; }
if [[ "$dry_run" == true ]]; then
  echo "Dry run complete: $tag at $commit (no tag or release published)"
  exit 0
fi
# gh creates the tag at the exact built commit, without a version commit on main.
gh release create "$tag" "$archive" --target "$commit" \
  --title "Richard Potato $tag" --notes-file "$notes"
