#!/usr/bin/env python3
"""CI entry point: require real tests, verify patch replay and reproducibility."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    subprocess.run(args, check=True, cwd=kwargs.pop('cwd', ROOT), **kwargs)


def files(directory):
    return {p.relative_to(directory).as_posix(): p.read_bytes()
            for p in directory.rglob('*') if p.is_file()}


def main():
    busybox = os.environ.get('BUSYBOX', '')
    if not busybox or not Path(busybox).is_file():
        raise SystemExit('BUSYBOX must point to KernelSU x86_64 BusyBox')
    for command in ('bwrap', 'patch'):
        if not shutil.which(command):
            raise SystemExit(f'Missing required test dependency: {command}')
    for script in sorted((ROOT / 'module').rglob('*.sh')):
        run(busybox, 'ash', '-n', str(script))
    suite = unittest.defaultTestLoader.discover(str(ROOT / 'tests'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful() or result.skipped or not result.testsRun:
        raise SystemExit('Tests failed, skipped, or no tests were discovered')

    run(sys.executable, 'scripts/build.py')
    expected = files(ROOT / 'module')
    # The patch preserves upstream CRLF and missing final newlines.
    with tempfile.TemporaryDirectory() as directory:
        destination = Path(directory)
        import json
        lock = json.loads((ROOT / 'upstream/lock.json').read_text())
        archive = ROOT / 'upstream' / f"extreme_gt_{lock['version']}.zip"
        with zipfile.ZipFile(archive) as z:
            z.extractall(destination)
        with (ROOT / 'patches/0001-kernelsu-hybrid-mount.patch').open('rb') as patch:
            run('patch', '--binary', '--batch', '-p1', cwd=destination, stdin=patch)
        if files(destination) != expected:
            raise SystemExit('Replayed patch differs from module source')

    before = files(ROOT / 'dist')
    run(sys.executable, 'scripts/build.py')
    if files(ROOT / 'dist') != before:
        raise SystemExit('Build is not reproducible')
    for archive in (ROOT / 'dist').glob('*.zip'):
        with zipfile.ZipFile(archive) as z:
            if z.testzip() or {name: z.read(name) for name in z.namelist()} != expected:
                raise SystemExit('ZIP integrity or source manifest mismatch')
        checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
        if archive.with_suffix('.zip.sha256').read_text() != f'{checksum}  {archive.name}\n':
            raise SystemExit('ZIP checksum mismatch')
    print('All checks passed: tests, ash syntax, patch replay, reproducibility, ZIP integrity')


if __name__ == '__main__':
    main()
