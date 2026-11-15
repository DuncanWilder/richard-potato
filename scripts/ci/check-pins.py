#!/usr/bin/env python3
"""Check Swift dependency and GitHub Actions pins in a repository root."""
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
def fail(message):
    sys.exit(message)
resolved = root / 'Package.resolved'
if not resolved.is_file():
    fail('Commit Package.resolved (an empty pins array is valid without dependencies).')
if subprocess.run(['git', '-C', str(root), 'ls-files', '--error-unmatch', 'Package.resolved'], capture_output=True).returncode:
    fail('Package.resolved must be tracked.')
for pin in json.loads(resolved.read_text())['pins']:
    if not re.fullmatch(r'[0-9a-fA-F]{40}', pin.get('state', {}).get('revision', '')):
        fail('Every resolved dependency needs a full revision.')
manifest = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', lambda m: m[0] if m[0].startswith('"') else '', (root / 'Package.swift').read_text(), flags=re.S)
for dependency in re.findall(r'\.package\s*\((.*?)\)', manifest, re.S):
    if not (re.search(r'(?:\bexact\s*:|\.exact\s*\()\s*"\d+\.\d+\.\d+(?:[-+][\w.-]+)?"', dependency) or re.search(r'(?:\brevision\s*:|\.revision\s*\()\s*"[0-9a-fA-F]{40}"', dependency)):
        fail('Package.swift dependencies must use exact: versions or full revision: hashes.')
for path in (root / '.github/workflows').glob('*'):
    if path.suffix not in ('.yml', '.yaml'):
        continue
    for value in re.findall(r'(?:^\s*(?:-\s*)?|[,{]\s*)[\'\"]?uses[\'\"]?:\s*[\'\"]?([^\s\'\"#,}]+)', path.read_text(), re.M):
        if not re.fullmatch(r'[^@]+@v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', value):
            fail(f'{path}: action uses must have an exact semver tag (@vMAJOR.MINOR.PATCH): {value}')
