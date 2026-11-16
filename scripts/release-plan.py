#!/usr/bin/env python3
"""Calculate a release from reachable version tags and squash commit titles."""
import argparse
from pathlib import Path
import re
import plistlib
import subprocess


def next_version(base, messages):
    parts = [int(value) for value in base.removeprefix('v').split('.')]
    if len(parts) == 2:
        parts.append(0)
    major, minor, patch = parts
    breaking = any(re.match(r'^[a-z]+(?:\([^\n]+\))?!:', message) or
                   re.search(r'^BREAKING CHANGE:\s*\S', message, re.M) for message in messages)
    feature = any(re.match(r'^feat(?:\([^\n]+\))?:', message) for message in messages)
    if breaking:
        return f'{major + 1}.0.0'
    if feature:
        return f'{major}.{minor + 1}.0'
    return f'{major}.{minor}.{patch + 1}'


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def plan(resolve_title=None):
    tags = git('tag', '--merged', 'HEAD').splitlines()
    tags = [tag for tag in tags if re.fullmatch(r'v\d+\.\d+(?:\.\d+)?', tag)]
    if tags:
        base_tag = max(tags, key=lambda tag: tuple(int(x) for x in tag[1:].split('.')))
        base = base_tag[1:]
        revision = f'{base_tag}..HEAD'
    else:
        with Path('Resources/Info.plist').open('rb') as source:
            base = plistlib.load(source)['CFBundleShortVersionString']
        revision = 'HEAD'
    messages = git('log', '--first-parent', '--reverse', '--format=%B%x00', revision).split('\0')
    messages = [message.strip() for message in messages if message.strip()]
    if not messages:
        raise ValueError('No commits to release')
    titles = [message.splitlines()[0] for message in messages]
    if resolve_title:
        commits = git('rev-list', '--first-parent', '--reverse', revision).splitlines()
        titles = []
        for commit, message in zip(commits, messages):
            for title in resolve_title(commit) or [message.splitlines()[0]]:
                if title not in titles:
                    titles.append(title)
    return next_version(base, messages + titles), '\n'.join('- ' + title for title in titles) + '\n'


def pr_titles(commit):
    # Resolve legacy merge commits too: their subjects are not PR titles.
    return subprocess.check_output([
        'gh', 'api', f'repos/{{owner}}/{{repo}}/commits/{commit}/pulls',
        '--jq', '.[].title',
    ], text=True).splitlines()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notes-file', required=True)
    parser.add_argument('--commit-titles', action='store_true',
                        help='Use local subjects for an offline dry run')
    args = parser.parse_args()
    version, notes = plan(None if args.commit_titles else pr_titles)
    Path(args.notes_file).write_text(notes)
    print(version)
