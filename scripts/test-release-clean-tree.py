#!/usr/bin/env python3
"""Check release fixtures and the real shell preflight in an isolated checkout."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class ReleaseCleanTreeTests(unittest.TestCase):
    def test_fixture_cache_and_dirty_checkout(self):
        source = Path(__file__).resolve().parent.parent
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            fixed_ignore = (source / '.gitignore').read_text()
            (root / '.gitignore').write_text(fixed_ignore.replace('__pycache__/\n', ''))
            for name in ('github-release.sh', 'release-plan.py', 'test-release-plan.py'):
                shutil.copy(source / 'scripts' / name, root / 'scripts')

            def run(*args):
                return subprocess.run(args, cwd=root, text=True, capture_output=True, check=True)

            run('git', 'init', '-q')
            run('git', 'add', '.')
            run('git', '-c', 'user.name=Release test', '-c',
                'user.email=release@example.invalid', 'commit', '-qm', 'chore: fixture')
            # Use the runner's in-tree cache location even with Apple Python.
            run(sys.executable, '-c',
                'import runpy, sys; sys.pycache_prefix = None; '
                'sys.dont_write_bytecode = False; '
                'sys.argv = ["scripts/test-release-plan.py"]; '
                'runpy.run_path(sys.argv[0], run_name="__main__")')
            self.assertTrue(list((root / 'scripts' / '__pycache__').glob('*.pyc')))
            self.assertEqual(run('git', 'status', '--porcelain').stdout,
                             '?? scripts/__pycache__/\n')
            print('Dirty files with the original ignore rules:', flush=True)
            print(run('git', 'ls-files', '--others', '--exclude-standard').stdout, flush=True)
            (root / '.gitignore').write_text(fixed_ignore)
            run('git', 'add', '.gitignore')
            run('git', '-c', 'user.name=Release test', '-c',
                'user.email=release@example.invalid', 'commit', '-qm', 'fix: ignore bytecode')
            self.assertEqual(run('git', 'status', '--porcelain').stdout, '')
            notes = root / 'scripts' / '__pycache__' / 'notes.txt'
            notes.write_text('- fix: fixture\n')
            command = ['/bin/bash', 'scripts/github-release.sh', '--version', '1.3.2',
                       '--notes-file', str(notes), '--plan-only']
            self.assertIn('Planned release: v1.3.2', run(*command).stdout)

            # Both tracked changes and untracked source files must still fail.
            (root / '.gitignore').write_text((root / '.gitignore').read_text() + '\n')
            (root / 'untracked.txt').write_text('source change\n')
            result = subprocess.run(command, cwd=root, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('Commit changes before publishing', result.stderr)
            self.assertIn(' M .gitignore', result.stderr)
            self.assertIn('?? untracked.txt', result.stderr)


if __name__ == '__main__':
    unittest.main()
