#!/usr/bin/env python3
"""Writes docs/COMPATIBILIDAD.md from the engine's game profiles (dm/games/<title ID>/game.tsv).

  scripts/make_compat.py [engine folder]     default: ~/Library/Application Support/Ondi/engine/nxnative, then ~/nxnative
"""
import os
import re
import subprocess
import sys
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
candidates = sys.argv[1:] or [os.path.expanduser('~/Library/Application Support/Ondi/engine/nxnative'), os.path.expanduser('~/nxnative')]
engine = next((c for c in candidates if os.path.isdir(os.path.join(c, 'dm/games'))), None)
if not engine:
    sys.exit('No encuentro el motor: pasa su carpeta como argumento.')

rows = []
games = os.path.join(engine, 'dm/games')
for tid in sorted(os.listdir(games)):
    tsv = os.path.join(games, tid, 'game.tsv')
    if not re.fullmatch(r'[0-9A-Fa-f]{16}', tid) or not os.path.isfile(tsv):
        continue
    lines = open(tsv, encoding='utf-8').read().splitlines()
    name = next((l.split('\t', 1)[1].strip() for l in lines if l.startswith('name\t')), tid)
    package = next((l.split('\t', 1)[1].strip() for l in lines if l.startswith('package\t')), '')
    header = lines[0] if lines else ''
    label = re.search(r'update ([0-9][0-9.]*[0-9])', header)
    if package in ('', 'v0'):
        version = 'Juego base'
    else:
        version = f'Actualización {label.group(1)} ({package})' if label else f'Actualización {package}'
    console = 'Switch 2 · solo Mac' if 'Switch 2' in header else 'Switch'
    rows.append((name, tid.upper(), version, console))

rows.sort(key=lambda r: r[0].casefold())
commit = subprocess.run(['git', '-C', engine, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
out = [
    '# Juegos compatibles',
    '',
    f'**{len(rows)} juegos** tienen un perfil probado en el motor que usa Ondi (versión `{commit or "?"}`, lista generada el {date.today():%d-%m-%Y}).',
    'Dentro de la app está la misma lista, con buscador, en el botón **Compatibilidad** del inicio.',
    '',
    '- **Versión probada:** la que hay que agregar junto al juego. Con otra versión el juego puede no arrancar, verse mal o ir a menos FPS.',
    '- Un juego sin perfil puede funcionar, pero no está probado.',
    '- *English:* games with a tested profile, the update each one needs, and the console it comes from.',
    '',
    '| Juego | ID | Versión probada | Consola |',
    '|---|---|---|---|',
]
out += [f'| {n} | `{t}` | {v} | {c} |' for n, t, v, c in rows]
out += ['', 'Para regenerar esta lista: `scripts/make_compat.py`.', '']
path = os.path.join(ROOT, 'docs', 'COMPATIBILIDAD.md')
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, 'w', encoding='utf-8').write('\n'.join(out))
print(f'{len(rows)} juegos → docs/COMPATIBILIDAD.md')
