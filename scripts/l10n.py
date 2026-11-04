#!/usr/bin/env python3
"""Translations for Ondi. Spanish is the source language: the keys are the Spanish strings in the code.

  scripts/l10n.py extract          lists every translatable string (with the Swift compiler) into Localization/keys.json
  scripts/l10n.py build            writes Resources/<lang>.lproj/Localizable.strings from Localization/<lang>.json
  scripts/l10n.py check            reports keys without translation and format specifiers that do not match

To add a language: copy Localization/en.json to Localization/<lang>.json, translate the values, run build.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.join(ROOT, 'Localization')
SPEC = re.compile(r'%(?:\d+\$)?(?:lld|ld|lu|llu|lf|@|d|u|f|%)')


def extract():
    out = tempfile.mkdtemp()
    subprocess.run(['swift', 'build', '--build-path', os.path.join(out, 'build'), '-Xswiftc', '-emit-localized-strings',
                    '-Xswiftc', '-emit-localized-strings-path', '-Xswiftc', out], cwd=ROOT, check=True)
    keys = set()
    for f in glob.glob(os.path.join(out, '*.stringsdata')):
        for entries in json.load(open(f)).get('tables', {}).values():
            keys.update(e['key'] for e in entries if e['key'].strip())
    os.makedirs(LOC, exist_ok=True)
    json.dump(sorted(keys), open(os.path.join(LOC, 'keys.json'), 'w'), ensure_ascii=False, indent=1)
    print(f'{len(keys)} strings → Localization/keys.json')


def languages():
    return [os.path.basename(p)[:-5] for p in glob.glob(os.path.join(LOC, '*.json')) if not p.endswith('keys.json')]


def check():
    keys = set(json.load(open(os.path.join(LOC, 'keys.json'))))
    ok = True
    for lang in languages():
        table = json.load(open(os.path.join(LOC, f'{lang}.json')))
        missing = sorted(keys - table.keys())
        bad = [k for k, v in table.items() if SPEC.findall(k) != SPEC.findall(v)]
        print(f'{lang}: {len(table)} strings, {len(missing)} missing, {len(bad)} with mismatched format specifiers')
        for k in missing[:20]: print('  missing:', k)
        for k in bad[:20]: print('  specifiers:', k)
        ok = ok and not missing and not bad
    return ok


def build():
    def esc(s):
        return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    for lang in languages():
        table = json.load(open(os.path.join(LOC, f'{lang}.json')))
        d = os.path.join(ROOT, 'Resources', f'{lang}.lproj')
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'Localizable.strings'), 'w') as f:
            for k in sorted(table):
                f.write(f'"{esc(k)}" = "{esc(table[k])}";\n')
        print(f'{lang}: {len(table)} strings → Resources/{lang}.lproj/Localizable.strings')


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'check'
    if cmd == 'extract': extract()
    elif cmd == 'build': build()
    else: sys.exit(0 if check() else 1)
