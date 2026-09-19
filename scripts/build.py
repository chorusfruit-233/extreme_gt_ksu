#!/usr/bin/env python3
"""Build a deterministic KernelSU module and auditable upstream diff."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', help='download the pinned upstream ZIP and verify its SHA256')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'upstream/lock.json').read_text())
    archive = ROOT / 'upstream' / ('extreme_gt_' + lock['version'] + '.zip')
    if args.fetch:
        data = urllib.request.urlopen(lock['zip_url'], timeout=60).read()
        if hashlib.sha256(data).hexdigest() != lock['sha256']:
            raise SystemExit('Upstream SHA256 changed; refusing unreviewed input')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != lock['sha256']:
        raise SystemExit('Upstream SHA256 mismatch')
    with zipfile.ZipFile(archive) as z:
        old = {p: z.read(p) for p in z.namelist() if not p.endswith('/')}
    new = {p.relative_to(ROOT / 'module').as_posix(): p.read_bytes()
           for p in sorted((ROOT / 'module').rglob('*')) if p.is_file()}
    for name, data in new.items():
        if name.endswith('.sh'):
            import re
            if re.search(rb'(?m)^\s*(?:busybox\s+)?(?:mount|umount|nsenter)\b', data):
                raise SystemExit('Manual mounting is forbidden: ' + name)
    forbidden = {'skip_mount', 'post-fs-data.sh', 'metamount.sh'}
    if forbidden.intersection(new) or any(p.startswith('META-INF/') for p in new):
        raise SystemExit('Unexpected legacy installer/mount hooks')
    diff = []
    for name in sorted(old.keys() | new.keys()):
        if old.get(name) == new.get(name):
            continue
        lines = difflib.unified_diff(
            old.get(name, b'').decode().splitlines(True),
            new.get(name, b'').decode().splitlines(True),
            fromfile='a/' + name if name in old else '/dev/null',
            tofile='b/' + name if name in new else '/dev/null')
        for line in lines:
            diff.append(line if line.endswith('\n') else line + '\n\\ No newline at end of file\n')
    (ROOT / 'patches').mkdir(exist_ok=True)
    (ROOT / 'patches/0001-kernelsu-hybrid-mount.patch').write_text(''.join(diff))
    props = dict(line.split('=', 1) for line in new['module.prop'].decode().splitlines() if '=' in line)
    output = ROOT / 'dist' / ('extreme_gt-' + props['version'] + '.zip')
    output.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(new.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (0o100755 if name.endswith('.sh') else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data, compresslevel=9)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.zip.sha256').write_text(f'{checksum}  {output.name}\n')
    print(output)
    print('SHA256:', checksum)

if __name__ == '__main__':
    main()
