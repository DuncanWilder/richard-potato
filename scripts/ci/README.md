# Dev-flow checks

Run `python3 scripts/ci/test-checks.py` locally. The standard-library-only scripts
also run on Ubuntu in `.github/workflows/dev-flow.yml`. PR metadata is read from
an event JSON file, never interpolated into shell commands.

- `check-title.py EVENT`: requires type(scope)!: description; scope and ! are
  optional. Allowed types are feat, fix, perf, chore, docs, refactor, test, ci,
  build. A BREAKING CHANGE footer can also document a breaking change.
- `check-verification.py EVENT`: requires a filled `## Verification` section.
- `check-images.py EVENT`: rejects PR-body Markdown and HTML images unless their
  URLs use `https://github.com/user-attachments/`, including reference images
  and HTML srcset sources. Upload screenshots with
  `gh pr create/edit --body-file ... --attach <file>` (gh 2.99.0+). Never commit
  or push evidence images to branches or link them through raw.githubusercontent.com.
- `check-perf.py EVENT`: perf titles require a Markdown table with Before and
  After columns and numeric measurements. Describe units and methodology too.
- `check-guardrails.py DIFF`: rejects added test skips, suppression comments and
  common bypass settings. Rejects removal/replacement of check configuration or
  CI scripts conservatively, including deletion. This includes this repository’s
  `scripts/check.sh`, `scripts/test.sh`, `scripts/format.sh`, and `scripts/toolchain.sh`. Allows action pin replacements.
  This is a textual tripwire, not a proof that arbitrary code preserves checks;
  review additions carefully. Legitimate config replacements require a deliberate
  policy change, not a bypass flag. Fixtures and Markdown are exempt from added
  code scanning so examples can be tested and documented.
- `check-pins.py ROOT`: requires tracked Package.resolved, full resolved revisions,
  exact Swift package requirements and exact semver tags (`@vMAJOR.MINOR.PATCH`)
  for workflow actions. Floating refs (`@v2`, `@main`, `@master`, `@latest`),
  commit SHAs, partial versions, and prerelease/build suffixes are rejected.
- `test-checks.py`: executes each script against committed good/bad fixtures;
  pin fixtures are materialized in temporary git repositories.

When copying: copy the template, workflow and this directory. Replace the Swift
manifest/lockfile portion of check-pins.py for your stack, update protected config
filenames and skip/suppression syntax in check-guardrails.py, and add fixtures for
those conventions. Keep action exact-version enforcement. Update the
build/test/format jobs for the new stack. Remote reusable workflows also require
exact semver tags; local actions and Docker tags are intentionally rejected by this policy. Configure squash-only
merges and PR_TITLE/PR_BODY in repository settings separately. Branch protection
should require the checks; workflow files alone do not configure that setting.

Keep copied scripts, comments, docs, templates, and fixtures neutral: use
“locally” or “the developer’s Mac” instead of naming a person or machine. Use
example paths and identities in fixtures. Preserve functional app identifiers
and service URLs when they are required for the repository to work.
