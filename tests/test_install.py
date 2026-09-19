"""Run the real installer in an isolated fake Android filesystem (bwrap).
Set BUSYBOX to KernelSU's x86_64 BusyBox to test ash standalone mode.
No host /sys, /proc, /data or Android partitions are writable by the module.
"""
import sys
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUSYBOX = os.environ.get('BUSYBOX')
sys.path.insert(0, str(ROOT / 'scripts'))
from build import module_files

@unittest.skipUnless(shutil.which('bwrap') and BUSYBOX, 'requires bwrap and BUSYBOX')
class InstallFixture(unittest.TestCase):
    variant = "hybrid_mount"
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for part in ['system', 'vendor', 'odm', 'product', 'my_product', 'my_stock', 'my_heytap', 'data', 'work', 'proc', 'sys']:
            (self.root / part).mkdir()
        for name, content in module_files(self.variant).items():
            output = self.root / 'work/module' / name
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(content)
        (self.root / 'work/tmp').mkdir()
        for part in ['vendor', 'odm', 'product', 'my_product', 'my_stock', 'my_heytap']:
            (self.root / 'system' / part).symlink_to('/' + part)
        self.write('vendor/etc/sys_thermal_config.xml', '<config><isOpen>1</isOpen></config>\n')
        self.write('my_product/etc/with space/sys_thermal_config.xml', '<config><isOpen>1</isOpen></config>\n')
        self.write('my_stock/etc/thermallevel_to_fps.xml', '<item fps="30"/>\n')
        self.write('my_heytap/etc/QEGA_Config.txt', 'original\n')
        self.write('product/etc/refresh_rate_config.xml', '<config>\n<value>2-2-2-2</value>\n</config>\n')
        self.write('data/system/refresh_rate_config.xml', 'must remain untouched\n')
        self.write('vendor/etc/devices_config.json', json.dumps({'high.capacity.threshold': 90, 'battery.temperate.range': '[10,20]'}, indent=2))
        self.write('vendor/etc/charging_default.txt', 'header,a,b\n400,1000,2\n')
        self.write('vendor/etc/thermal/fix_ttj_95.conf', '95\n')
        self.write('vendor/etc/thermal/fix_ttj_85.conf', '85\n')
        (self.root / 'odm/etc/powerhal').mkdir(parents=True)

    def write(self, path, data):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(data)

    def run_install(self, soc='sm8650', ksu='true', meta='hybrid_mount'):
        self.write('work/runner.sh', f'''
export KSU={ksu} BOOTMODE=true KSU_METAMODULE={meta}
export MODPATH=/work/module TMPDIR=/work/tmp
ui_print() {{ printf '%s\\n' "$*"; }}
abort() {{ ui_print "$*"; exit 1; }}
set_perm() {{ chmod "$4" "$1"; }}
chcon() {{ :; }}
getprop() {{ printf '%s\\n' {soc}; }}
. /work/module/customize.sh
''')
        cmd = ['bwrap', '--unshare-user', '--unshare-pid', '--die-with-parent', '--tmpfs', '/', '--bind', str(self.root / 'work'), '/work', '--ro-bind', BUSYBOX, '/busybox', '--dev', '/dev', '--proc', '/proc']
        for part in ['system', 'vendor', 'odm', 'product', 'my_product', 'my_stock', 'my_heytap', 'data', 'sys']:
            if (self.root / part).is_symlink():
                cmd += ['--symlink', os.readlink(self.root / part), '/' + part]
            else:
                cmd += ['--ro-bind', str(self.root / part), '/' + part]
        cmd += ['--setenv', 'ASH_STANDALONE', '1', '/busybox', 'ash', '/work/runner.sh']
        return subprocess.run(cmd, capture_output=True, text=True)

class InstallTest(InstallFixture):
    def test_generic_install(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        m = self.root / 'work/module'
        for file in ['system/vendor/etc/sys_thermal_config.xml', 'system/my_product/etc/with space/sys_thermal_config.xml']:
            self.assertIn('<isOpen>0</isOpen>', (m / file).read_text())
        self.assertIn('fps="144"', (m / 'system/my_stock/etc/thermallevel_to_fps.xml').read_text())
        self.assertTrue((m / 'system/my_heytap/etc/QEGA_Config.txt').is_file())
        self.assertIn('0-0-0-0', (m / 'system/product/etc/refresh_rate_config.xml').read_text())
        self.assertEqual((self.root / 'data/system/refresh_rate_config.xml').read_text(), 'must remain untouched\n')
        self.assertEqual(json.loads((m / 'system/vendor/etc/devices_config.json').read_text())['high.capacity.threshold'], 85)
        self.assertEqual((m / 'system/vendor/etc/charging_default.txt').read_text(), 'header,a,b\n450,1000,2\n')
        self.assertEqual((m / 'system/vendor/etc/thermal/fix_ttj_85.conf').read_text(), '95\n')
        self.assertFalse((m / 'post-fs-data.sh').exists())
        self.assertFalse((m / 'vendor').exists())

    def test_mediatek_payload(self):
        result = self.run_install(soc='mt6893')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        m = self.root / 'work/module'
        self.assertTrue((m / 'system/vendor/etc/.tp/.ht120.mtc').is_file())
        self.assertTrue((m / 'system/odm/etc/powerhal/powerscntbl.xml').is_file())

    def test_threshold_100_preserved(self):
        self.write('vendor/etc/devices_config.json', '{"high.capacity.threshold": 100, "other": 2}\n')
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = self.root / 'work/module/system/vendor/etc/devices_config.json'
        self.assertEqual(json.loads(output.read_text())['high.capacity.threshold'], 100)

    def test_vendor_inside_system(self):
        (self.root / 'system/vendor').unlink()
        shutil.move(str(self.root / 'vendor'), str(self.root / 'system/vendor'))
        (self.root / 'vendor').symlink_to('/system/vendor')
        # bwrap cannot bind a symlink directory as a mountpoint; use its symlink option.
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('<isOpen>0</isOpen>', (self.root / 'work/module/system/vendor/etc/sys_thermal_config.xml').read_text())

    def test_wrong_root_rejected(self):
        result = self.run_install(ksu='false')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('KernelSU 管理器', result.stdout)

    def test_wrong_metamodule_rejected(self):
        result = self.run_install(meta='meta-overlayfs')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('meta-hybrid_mount', result.stdout)

class SusfsInstallTest(InstallFixture):
    variant = 'susfs'

    def setUp(self):
        super().setUp()
        self.helper('CONFIG_KSU_SUSFS_SUS_MOUNT\nCONFIG_KSU_SUSFS_TRY_UMOUNT')

    def helper(self, features):
        self.write('data/adb/ksu/bin/ksu_susfs', '#!/busybox ash\nprintf "%s\\n" "' + features + '"\n')
        (self.root / 'data/adb/ksu/bin/ksu_susfs').chmod(0o755)

    def test_install_without_metamodule(self):
        result = self.run_install(meta='')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        m = self.root / 'work/module'
        self.assertTrue((m / 'skip_mount').is_file())
        self.assertFalse((m / 'system').exists())
        self.assertFalse((m / 'vendor').exists())
        self.assertIn('<isOpen>0</isOpen>', (m / 'payload/vendor/etc/sys_thermal_config.xml').read_text())
        self.assertTrue((m / 'payload/my_product/etc/with space/sys_thermal_config.xml').is_file())
        lines = (m / 'overlay-files.txt').read_text().splitlines()
        self.assertEqual(len(lines), len(set(lines)))
        self.assertTrue(all(line.startswith('payload/') for line in lines))

    def test_install_with_metamodule_still_skips(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'work/module/system').exists())
        self.assertTrue((self.root / 'work/module/skip_mount').is_file())

    def test_missing_helper_rejected(self):
        (self.root / 'data/adb/ksu/bin/ksu_susfs').unlink()
        result = self.run_install(meta='')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('缺少 /data/adb/ksu/bin/ksu_susfs', result.stdout)

    def test_missing_feature_rejected(self):
        self.helper('CONFIG_KSU_SUSFS_SUS_PATH')
        result = self.run_install(meta='')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CONFIG_KSU_SUSFS_SUS_MOUNT', result.stdout)

    def test_missing_destination_rejected(self):
        result = self.run_install(soc='mt6893', meta='')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('目标存在', result.stdout)

    def test_conflicting_variant_rejected(self):
        self.write('data/adb/modules/extreme_gt_hybrid_mount/module.prop', 'id=extreme_gt_hybrid_mount\n')
        result = self.run_install(meta='')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('不能同时启用', result.stdout)

    def test_modern_ksud_fallback(self):
        self.helper('CONFIG_KSU_SUSFS_SUS_MOUNT')
        self.write('data/adb/ksud', '#!/busybox ash\n[ "$*" = "kernel umount add --help" ]\n')
        (self.root / 'data/adb/ksud').chmod(0o755)
        result = self.run_install(meta='')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
