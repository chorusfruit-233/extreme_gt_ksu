#!/system/bin/sh
# Sourced by KernelSU's installer (BusyBox ash).
[ "$KSU" = true ] || abort '! 请使用 KernelSU 管理器安装。'
[ "$BOOTMODE" = true ] || abort '! 不支持 Recovery 安装。'
variant=$(cat "$MODPATH/variant") || abort '! 缺少版本标记。'
case "$variant" in
  hybrid_mount)
    case "${KSU_METAMODULE:-}" in
      hybrid_mount|meta-hybrid_mount) ;;
      *) [ "${HYBRID_MOUNT:-}" = true ] ||
           abort '! 请先启用 meta-hybrid_mount 并重启，再安装本模块。' ;;
    esac
    ;;
  susfs)
    . "$MODPATH/susfs-common.sh"
    susfs_check || abort '! SUSFS 接口检查失败，请查看上方错误。'
    [ -f "$MODPATH/skip_mount" ] || abort '! SUSFS 包缺少 skip_mount。'
    ;;
  *) abort '! 未知构建版本。' ;;
esac

# IDs are independent, but the variants patch the same device files.
for other in extreme_gt extreme_gt_hybrid_mount extreme_gt_susfs; do
  [ "$other" != "extreme_gt_$variant" ] || continue
  for base in /data/adb/modules /data/adb/modules_update; do
    candidate="$base/$other"
    if [ -f "$candidate/module.prop" ] && [ ! -f "$candidate/disable" ] && [ ! -f "$candidate/remove" ]; then
      abort "! 请先禁用 $other 并重启，两个版本不能同时启用。"
    fi
  done
done

SRC=$MODPATH
module="$TMPDIR/extreme-gt-staging"
mkdir -p "$module" || abort '! 无法创建临时目录。'
ui_print "- Extreme GT 4.2.1 · KernelSU / $variant"
# Run in a subshell so upstream local variables do not leak into the installer.
( set -e; set -o pipefail; . "$SRC/patch-configs.sh" ) || abort '! 生成配置失败。'

# Resolve device aliases before mapping into Hybrid Mount's canonical hierarchy.
# Do not move partitions or create aliases: that is metainstall.sh's responsibility.
: > "$MODPATH/overlay-files.txt"
find "$module" -type f | sort | while IFS= read -r staged; do
  target=${staged#"$module"}
  if [ -e "$target" ]; then
    target=$(readlink -f "$target") || exit 1
  fi
  case "$target" in
    /system/*) relative=${target#/} ;;
    /vendor/*|/product/*|/system_ext/*|/odm/*|/oem/*|/my_product/*|/my_stock/*|/my_heytap/*)
      relative=system${target} ;;
    *) ui_print "! 不支持的配置目标：$target"; exit 1 ;;
  esac
  if [ "$variant" = susfs ]; then
    [ -f "$target" ] || {
      ui_print "! SUSFS 逐文件挂载要求目标存在：$target"
      exit 1
    }
    relative=payload/${relative#system/}
  fi
  destination="$MODPATH/$relative"
  mkdir -p "${destination%/*}" || exit 1
  cp -f "$staged" "$destination" || exit 1
  set_perm "$destination" 0 0 0644
  if [ -f "$target" ]; then
    # Preserve the ROM's vendor/OPlus SELinux label instead of system_file everywhere.
    chcon --reference="$target" "$destination" || exit 1
  fi
  printf '%s\t%s\n' "$relative" "$target" >> "$MODPATH/overlay-files.txt"
done || abort '! 配置映射失败，请检查安装日志。'

sort -u "$MODPATH/overlay-files.txt" -o "$MODPATH/overlay-files.txt" || abort '! 无法整理覆盖清单。'

# Label directories using the actual device hierarchy, including dedicated OEM partitions.
tree=system
[ "$variant" != susfs ] || tree=payload
find "$MODPATH/$tree" -type d 2>/dev/null | while IFS= read -r directory; do
  target=/system${directory#"$MODPATH/$tree"}
  part=${target#/system/}
  part=${part%%/*}
  case "$part" in
    vendor|product|system_ext|odm|oem|my_product|my_stock|my_heytap)
      [ ! -d "/$part" ] || target=${target#/system} ;;
  esac
  chmod 0755 "$directory" || exit 1
  [ ! -d "$target" ] || chcon --reference="$target" "$directory" || exit 1
done || abort '! 无法设置目录权限。'

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
if [ "$variant" = susfs ]; then
  set_perm "$MODPATH/post-mount.sh" 0 0 0755
  ui_print '- skip_mount 已启用；重启后由本模块协同 SUSFS 自行挂载。'
else
  ui_print '- 配置已生成；重启后由 Hybrid Mount 挂载。'
fi
ui_print '- 上游温控与充电阈值规则保留；请先阅读项目说明。'
