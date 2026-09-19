"""Actual bind mounts in a disposable user/mount namespace; SUSFS API is mocked."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build import module_files
BUSYBOX = os.environ.get('BUSYBOX')


@unittest.skipUnless(shutil.which('bwrap') and BUSYBOX, 'requires bwrap and BUSYBOX')
class SusfsMountTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for part in ('work', 'data', 'system'):
            (self.root / part).mkdir()
        for name, content in module_files('susfs').items():
            p = self.root / 'work/module' / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(content)
        self.write('work/module/payload/etc/a.conf', 'patched a\n')
        self.write('work/module/payload/etc/b space.conf', 'patched b\n')
        self.write('system/etc/a.conf', 'original a\n')
        self.write('system/etc/b space.conf', 'original b\n')
        self.write('work/module/overlay-files.txt', 'payload/etc/a.conf\t/system/etc/a.conf\npayload/etc/b space.conf\t/system/etc/b space.conf\n')
        self.write('data/adb/ksu/bin/ksu_susfs', '''#!/busybox ash
if [ "$*" = 'show version' ]; then
  if [ -f /work/v2 ]; then echo v2.3.0; else echo v1.5.9; fi
  exit 0
fi
if [ "$1" = --help ]; then
  [ -f /work/v2 ] || echo 'add_sus_mount add_try_umount'
  exit 0
fi
if [ "$1" = show ]; then
  [ ! -f /work/no_features ] || exit 1
  echo CONFIG_KSU_SUSFS_SUS_MOUNT
  [ -f /work/modern ] || echo CONFIG_KSU_SUSFS_TRY_UMOUNT
  exit 0
fi
printf '%s\n' "$*" >> /work/calls
if [ -f /work/fail ] && [ "$1" = add_sus_mount ] && [ "$2" = '/system/etc/b space.conf' ]; then
  exit 1
fi
exit 0
''', executable=True)
        self.write('data/adb/ksud', '''#!/busybox ash
[ "$*" != 'kernel umount add --help' ] || exit 0
printf '%s\n' "$*" >> /work/calls
''', executable=True)

    def write(self, path, data, executable=False):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(data)
        if executable:
            p.chmod(0o755)

    def run_mount(self, repeat=False):
        self.write('work/getprop', '#!/busybox ash\necho 0\n', executable=True)
        self.write('work/runner.sh', '''export KSU=true
export PATH=/work:$PATH
[ ! -f /work/late ] || export KSU_LATE_LOAD=1
/busybox ash /work/module/post-mount.sh
code=$?
cat /system/etc/a.conf > /work/after_a
cat '/system/etc/b space.conf' > /work/after_b
[ ! -f /dev/extreme_gt_susfs.lock/complete ] || touch /work/complete
''' + ('''/busybox ash /work/module/post-mount.sh
''' if repeat else '') + '''exit "$code"
''')
        args = ['bwrap', '--unshare-user', '--uid', '0', '--gid', '0', '--unshare-pid', '--die-with-parent', '--cap-add', 'CAP_SYS_ADMIN', '--tmpfs', '/', '--dev', '/dev', '--proc', '/proc', '--ro-bind', BUSYBOX, '/busybox']
        for part in ('work', 'data', 'system'):
            args += ['--bind', str(self.root / part), '/' + part]
        args += ['--setenv', 'ASH_STANDALONE', '1', '/busybox', 'ash', '/work/runner.sh']
        result = subprocess.run(args, capture_output=True, text=True)
        log = self.root / 'data/adb/extreme_gt_susfs/mount.log'
        return result, log.read_text() if log.exists() else ''

    def test_mount_register_and_no_duplicate_mounts(self):
        result, log = self.run_mount(repeat=True)
        self.assertEqual(result.returncode, 0, result.stderr + log)
        self.assertEqual((self.root / 'work/after_a').read_text(), 'patched a\n')
        self.assertEqual((self.root / 'work/after_b').read_text(), 'patched b\n')
        calls = (self.root / 'work/calls').read_text().splitlines()
        self.assertEqual(calls, ['add_sus_mount /system/etc/a.conf', 'add_try_umount /system/etc/a.conf 1', 'add_sus_mount /system/etc/b space.conf', 'add_try_umount /system/etc/b space.conf 1'])
        self.assertTrue((self.root / 'work/complete').exists())
        self.assertEqual((self.root / 'system/etc/a.conf').read_text(), 'original a\n')

    def test_susfs_registration_failure_rolls_back_all(self):
        self.write('work/fail', '')
        result, log = self.run_mount()
        self.assertNotEqual(result.returncode, 0, log)
        self.assertIn('SUSFS 注册失败', log)
        self.assertEqual((self.root / 'work/after_a').read_text(), 'original a\n')
        self.assertEqual((self.root / 'work/after_b').read_text(), 'original b\n')
        self.assertFalse((self.root / 'work/complete').exists())

    def test_missing_features_prevent_any_mount(self):
        self.write('work/no_features', '')
        result, log = self.run_mount()
        self.assertNotEqual(result.returncode, 0, log)
        self.assertEqual((self.root / 'work/after_a').read_text(), 'original a\n')
        self.assertFalse((self.root / 'work/calls').exists())

    def test_ksud_unmount_registration(self):
        self.write('work/modern', '')
        result, log = self.run_mount()
        self.assertEqual(result.returncode, 0, result.stderr + log)
        self.assertIn('kernel umount add /system/etc/b space.conf --flags 2', (self.root / 'work/calls').read_text())

    def test_missing_target_rejected_before_first_mount(self):
        with (self.root / 'work/module/overlay-files.txt').open('a') as f:
            f.write('payload/etc/a.conf\t/system/etc/missing.conf\n')
        result, log = self.run_mount()
        self.assertNotEqual(result.returncode, 0, log)
        self.assertEqual((self.root / 'work/after_a').read_text(), 'original a\n')
        self.assertFalse((self.root / 'work/calls').exists())

    def test_v2_without_removed_commands_uses_kernel_auto_and_ksud(self):
        self.write('work/v2', '')
        self.write('work/modern', '')
        result, log = self.run_mount()
        self.assertEqual(result.returncode, 0, result.stderr + log)
        calls = (self.root / 'work/calls').read_text()
        self.assertNotIn('add_sus_mount', calls)
        self.assertNotIn('add_try_umount', calls)
        self.assertIn('kernel umount add /system/etc/a.conf --flags 2', calls)
        self.assertIn('mount=auto', log)
        self.assertEqual((self.root / 'work/after_a').read_text(), 'patched a\n')

    def test_old_helper_missing_manual_command_fails_before_mount(self):
        helper = self.root / 'data/adb/ksu/bin/ksu_susfs'
        helper.write_text(helper.read_text().replace("echo 'add_sus_mount add_try_umount'", "echo 'add_sus_path'"))
        result, log = self.run_mount()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('无 add_sus_mount', log)
        self.assertFalse((self.root / 'work/calls').exists())

    def test_v2_late_load_rejected_before_mount(self):
        self.write('work/v2', '')
        self.write('work/modern', '')
        self.write('work/late', '')
        result, log = self.run_mount()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('需要正常启动阶段', log)
        self.assertFalse((self.root / 'work/calls').exists())

    def test_v2_universal_helper_does_not_force_removed_command(self):
        self.write('work/v2', '')
        self.write('work/modern', '')
        helper = self.root / 'data/adb/ksu/bin/ksu_susfs'
        helper.write_text(helper.read_text().replace("[ -f /work/v2 ] || echo", "echo"))
        result, log = self.run_mount()
        self.assertEqual(result.returncode, 0, result.stderr + log)
        self.assertNotIn('add_sus_mount', (self.root / 'work/calls').read_text())
