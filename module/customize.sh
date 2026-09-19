#!/system/bin/sh
# Sourced by KernelSU's installer (BusyBox ash).
[ "$KSU" = true ] || abort '! 请使用 KernelSU 管理器安装。'
[ "$BOOTMODE" = true ] || abort '! 不支持 Recovery 安装。'
case "${KSU_METAMODULE:-}" in
  hybrid_mount|meta-hybrid_mount) ;;
  *)
    [ "${HYBRID_MOUNT:-}" = true ] ||
      abort '! 请先启用 meta-hybrid_mount 并重启，再安装本模块。'
    ;;
esac

SRC=$MODPATH
module="$TMPDIR/extreme-gt-staging"
mkdir -p "$module" || abort '! 无法创建临时目录。'
ui_print '- Extreme GT 4.2.1 · KernelSU / Hybrid Mount'
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

# Label directories using the actual device hierarchy, including dedicated OEM partitions.
find "$MODPATH/system" -type d 2>/dev/null | while IFS= read -r directory; do
  target=/${directory#"$MODPATH/"}
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
ui_print '- 配置已生成；重启后由 Hybrid Mount 挂载。'
ui_print '- 上游温控与充电阈值规则保留；请先阅读项目说明。'
