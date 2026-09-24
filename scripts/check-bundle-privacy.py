#!/usr/bin/env python3
"""Fail closed on local home paths or private operational files in a release bundle."""
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
needle = str(Path.home()).encode()
failures = []
for p in bundle.rglob('*'):
    if not p.is_file() or p.is_symlink():
        continue
    if needle in p.read_bytes() or p.suffix in {'.sqlite', '.db', '.log'} or p.name.startswith('.env'):
        failures.append(str(p.relative_to(bundle)))
if failures:
    print('Release privacy check failed (paths only):\n' + '\n'.join(failures), file=sys.stderr)
    sys.exit(1)
print('Release bundle privacy check passed.')
