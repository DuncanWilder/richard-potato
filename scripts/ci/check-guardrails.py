#!/usr/bin/env python3
"""Inspect a zero-context git diff; reject bypasses and config removals."""
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
path = ''
removed = []
added = []
errors = []
def protected(name):
    return (name in ('scripts/check.sh', 'scripts/test.sh', 'scripts/format.sh', 'scripts/toolchain.sh') or
            name.startswith('.github/workflows/') or
            bool(re.search(r'(swift-format|swiftlint|eslint|prettier|pytest|jest|vitest|test.*config|lint.*config|format.*config)', name, re.I)) or
            name.startswith('scripts/ci/') and not name.startswith('scripts/ci/fixtures/'))
def normalized(line):
    return re.sub(r'(uses:\s*[^@\s]+)@[^\s]+(?:\s+#.*)?', r'\1@PIN', line)
def finish():
    # Deleting enforcement is ambiguous: fail closed, including deleted CI scripts.
    available = [normalized(x) for x in added]
    if protected(path):
        for line in removed:
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            value = normalized(line)
            if value in available:
                available.remove(value)
            else:
                errors.append(f'{path}: removed/replaced check configuration: {line}')
for line in text.splitlines():
    if line.startswith('diff --git '):
        finish()
        path = line.split(' b/', 1)[-1]
        removed, added = [], []
    elif line.startswith('--- ') or line.startswith('+++ '):
        continue
    elif line.startswith('-'):
        removed.append(line[1:])
    elif line.startswith('+'):
        value = line[1:]
        added.append(value)
        # Fixtures/docs contain examples, not executable bypasses.
        if path.endswith(('.md', '.json', '.diff')) or path.startswith('scripts/ci/fixtures/'):
            continue
        patterns = [
            r'\b(?:skip|x?disabled)\s*[:=(]', r'\.(?:skip|todo)\s*\(',
            r'\b(?:xit|xdescribe|xtest)\s*\(', r'@(?:pytest\.mark\.skip\w*|unittest\.skip\w*)',
            r'\.enabled\s*\(\s*if:\s*false', r'\.disabled\s*\(',
            r'(?:^|\s)(?://|#|/\*|<!--).*?(?:noqa|nosonar|swiftlint:|swift-format-ignore|eslint-disable|prettier-ignore|type:\s*ignore|fmt:\s*(?:off|skip)|istanbul ignore|c8 ignore)',
            r'\bcontinue-on-error\s*:\s*true', r'\|\|\s*(?:true|:)',
            r'\bif\s*:\s*(?:false|\$\{\{\s*false\s*\}\})',
            r'(?:disabled_rules|excluded|ignorePatterns)\s*:',
            r'[\"\']?(?:enabled|strict|failOn\w*|enforce\w*)[\"\']?\s*[:=]\s*(?:false|off|0)',
            r'--(?:no-verify|passWithNoTests)|\b(?:failOn|enforce|strict)\w*\s*[:=]\s*false',
        ]
        if any(re.search(p, value, re.I) for p in patterns):
            errors.append(f'{path}: potential check bypass: {value}')
finish()
if errors:
    sys.exit('\n'.join(errors))
