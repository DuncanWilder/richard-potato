#!/usr/bin/env python3
"""Run the scripts as subprocesses, asserting both acceptance and rejection."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
cases = json.loads((here / 'fixtures/cases.json').read_text())
count = 0
for case in cases:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        script = case['script']
        if script == 'pins':
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / '.github/workflows').mkdir(parents=True)
            (root / 'Package.swift').write_text(case.get('manifest', 'let dependencies = []'))
            if case.get('lock', True):
                (root / 'Package.resolved').write_text(json.dumps({'version': 3, 'pins': []}))
                if case.get('tracked', True):
                    subprocess.run(['git', '-C', str(root), 'add', 'Package.resolved'], check=True)
            (root / '.github/workflows/ci.yml').write_text(case.get('workflow', 'steps:\n  - uses: actions/checkout@v4.4.0'))
            argument = root
        else:
            argument = root / 'input'
            argument.write_text(case['diff'] if script == 'guardrails' else json.dumps({'pull_request': case['pr']}))
        result = subprocess.run([sys.executable, str(here / f'check-{script}.py'), str(argument)], capture_output=True, text=True)
        if (result.returncode == 0) != case['pass']:
            sys.exit(f"FAIL {case['name']}: exit {result.returncode}\n{result.stdout}{result.stderr}")
        count += 1
print(f'{count} fixture cases passed (good inputs accepted, bad inputs rejected).')
