#!/usr/bin/env python3
"""Exercise version precedence and real git-history planning without dependencies."""
import importlib.util
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_plan', Path(__file__).with_name('release-plan.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleasePlanTests(unittest.TestCase):
    def test_bumps(self):
        cases = [
            (['fix: repair', 'feat!: replace'], '2.0.0'),
            (['fix(api)!: replace'], '2.0.0'),
            (['fix: repair\n\nBREAKING CHANGE: new format'], '2.0.0'),
            (['fix: repair', 'feat(ui): add control'], '1.24.0'),
            (['ci: automate', 'docs: explain'], '1.23.4'),
        ]
        for messages, expected in cases:
            with self.subTest(messages=messages):
                self.assertEqual(release.next_version('1.23.3', messages), expected)

    def test_history_and_first_release(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                def git(*args):
                    return subprocess.check_output(['git', *args], stderr=subprocess.STDOUT, text=True)
                git('init')
                git('config', 'user.name', 'Release test')
                git('config', 'user.email', 'release@example.invalid')
                Path('Resources').mkdir()
                Path('Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.23.3'}))
                git('add', '.')
                git('commit', '-m', 'chore: initial')
                self.assertEqual(release.plan(), ('1.23.4', '- chore: initial\n'))
                git('tag', 'v1.23.3')
                git('commit', '--allow-empty', '-m', 'feat: new feature (#42)', '-m', 'Details stay out of notes.')
                resolved = release.plan(lambda commit: ['Actual PR title'])
                self.assertEqual(resolved, ('1.24.0', '- Actual PR title\n'))
                self.assertEqual(release.plan(lambda commit: ['feat!: new API'])[0], '2.0.0')
                git('checkout', '--detach')
                self.assertEqual(release.plan(), ('1.24.0', '- feat: new feature (#42)\n'))
                git('tag', 'v1.24.0')
                with self.assertRaisesRegex(ValueError, 'No commits'):
                    release.plan()
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
