#!/usr/bin/env python3
"""Require GitHub user attachments for every PR-body evidence image."""
from html import unescape
from html.parser import HTMLParser
import json
import re
import sys
from urllib.parse import urlsplit

body = json.load(open(sys.argv[1]))['pull_request'].get('body') or ''
errors = []

def check(url):
    url = unescape(url)
    parsed = urlsplit(url)
    if (not url.startswith('https://github.com/user-attachments/') or
            parsed.scheme != 'https' or parsed.netloc != 'github.com' or
            not parsed.path.startswith('/user-attachments/') or
            not parsed.path.removeprefix('/user-attachments/') or
            re.search(r'[\s\\]', url)):
        errors.append(url or '(missing image URL)')

class Images(HTMLParser):
    def handle_starttag(self, tag, attrs):
        if tag.lower() != 'img':
            return
        sources = [value or '' for key, value in attrs if key.lower() == 'src']
        if not sources:
            check('')
        for source in sources:
            check(source)
        for key, value in attrs:
            if key.lower() == 'srcset':
                for candidate in (value or '').split(','):
                    check(candidate.strip().split()[0] if candidate.strip() else '')

Images().feed(body)
# Definitions and reference images are supported as well as inline images.
def label(value):
    return ' '.join(value.split()).casefold()

definitions = {}
for match in re.finditer(r'^ {0,3}\[([^\]\n]+)\]:\s*(?:<([^>\n]*)>|(\S+))', body, re.M):
    definitions.setdefault(label(match[1]), match[2] if match[2] is not None else match[3])
for match in re.finditer(r'!\[((?:\\.|[^\]\\])*)\]', body):
    rest = body[match.end():]
    inline = re.match(r'\s*\(\s*(?:<([^>\n]*)>|((?:\\.|[^\s)])*))', rest)
    if inline:
        destination = inline[1] if inline[1] is not None else inline[2]
        check(re.sub(r'\\([!"#$%&\'()*+,\-./:;<=>?@\[\]\\^_`{|}~])', r'\1', destination))
    else:
        reference = re.match(r'\s*\[([^\]]*)\]', rest)
        key = reference[1] if reference and reference[1] else match[1]
        check(definitions.get(label(key), ''))
if errors:
    sys.exit('PR images must use https://github.com/user-attachments/ URLs. '
             'Upload with gh pr create/edit --body-file ... --attach <file> (gh 2.99.0+).\n'
             + '\n'.join(errors))
