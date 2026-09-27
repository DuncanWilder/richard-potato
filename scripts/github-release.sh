#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v gh >/dev/null || { echo "Install GitHub CLI (gh) first." >&2; exit 1; }

versions="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' RichardPotato.xcodeproj/project.pbxproj | sort -u)"
if [[ ! "$versions" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Expected one numeric MARKETING_VERSION in the Xcode project." >&2
  exit 1
fi
tag="v$versions"

gh auth status >/dev/null
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

github_status() {
  local response status
  response="$(gh api -i "repos/$repo/$1" 2>&1)" || true
  status="$(printf '%s\n' "$response" | sed -nE 's/^HTTP\/[0-9.]+ ([0-9]{3}).*/\1/p' | tail -n 1)"
  if [[ -z "$status" ]]; then
    echo "Could not check $1 on GitHub: $response" >&2
    exit 1
  fi
  printf '%s' "$status"
}

for resource in "git/ref/tags/$tag" "releases/tags/$tag"; do
  status="$(github_status "$resource")"
  case "$status" in
    200) echo "Tag or release $tag already exists on GitHub." >&2; exit 1 ;;
    404) ;;
    *) echo "GitHub version check failed (HTTP $status)." >&2; exit 1 ;;
  esac
done

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit your changes before making a release." >&2
  exit 1
fi

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "Check out a branch before making a release." >&2
  exit 1
fi

commit="$(git rev-parse HEAD)"
remote_commit="$(git ls-remote origin "refs/heads/$branch" | cut -f1)"
if [[ "$remote_commit" != "$commit" ]]; then
  echo "Push the current commit to origin/$branch before making a release." >&2
  exit 1
fi

notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
echo "Write the changelog for $tag in your editor, then save and close it."
"${EDITOR:-vi}" "$notes"
if [[ -z "$(tr -d '[:space:]' < "$notes")" ]]; then
  echo "The changelog is empty. No release was made." >&2
  exit 1
fi

echo "Building $tag..."
./scripts/release.sh
archive="$ROOT/dist/Richard-Potato-$versions.zip"
if [[ ! -s "$archive" ]]; then
  echo "Release archive is missing: $archive" >&2
  exit 1
fi

echo "Creating GitHub release $tag..."
gh release create "$tag" "$archive" \
  --target "$commit" \
  --title "Richard Potato $tag" \
  --notes-file "$notes"
