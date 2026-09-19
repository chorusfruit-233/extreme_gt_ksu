#!/system/bin/sh
# After any metamodule's mounts, before zygote; skip_mount does not skip scripts.
MODDIR=${0%/*}
[ "$KSU" = true ] || exit 1
[ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] || exit 0
[ -f "$MODDIR/skip_mount" ] || exit 1
STATE=/data/adb/extreme_gt_susfs
mkdir -p "$STATE" || exit 1
chmod 0700 "$STATE"
. "$MODDIR/susfs-common.sh"
# A boot-scoped lock prevents a second post-mount event from stacking mounts.
LOCK=/dev/extreme_gt_susfs.lock
mkdir "$LOCK" 2>/dev/null || exit 0
chmod 0700 "$LOCK"
# Replace the previous boot log only after acquiring the boot-scoped lock.
exec > "$STATE/mount.log" 2>&1
ledger="$LOCK/mounted"
: > "$ledger"
complete=false
rollback() {
  if [ "$complete" != true ]; then
    # Reverse order, using only mounts created by this invocation.
    sed '1!G;h;$!d' "$ledger" | while IFS= read -r target; do
      umount "$target" || echo "! 回滚失败：$target"
    done
    rm "$ledger"
    rmdir "$LOCK"
    echo '! 自挂载未完成，已尝试回滚；请查看日志并重启。'
  fi
}
trap rollback EXIT
trap 'exit 1' HUP INT TERM
susfs_check || exit 1
if [ "$SUSFS_MOUNT" = auto ]; then
  if [ "${KSU_LATE_LOAD:-0}" = 1 ] || [ "$(getprop sys.boot_completed)" = 1 ]; then
    echo '! SUSFS 自动标记需要正常启动阶段，请重启；不支持启动完成后补挂载。'
    exit 1
  fi
fi
[ -s "$MODDIR/overlay-files.txt" ] || { echo '! 缺少覆盖清单'; exit 1; }
# Validate the whole manifest before making the first mount.
tab=$(printf '\t')
while IFS="$tab" read -r relative target; do
  case "$relative" in payload/*) ;; *) exit 1 ;; esac
  case "$relative/$target" in *../*) exit 1 ;; esac
  case "$target" in
    /system/*|/vendor/*|/product/*|/system_ext/*|/odm/*|/oem/*|/my_product/*|/my_stock/*|/my_heytap/*) ;;
    *) exit 1 ;;
  esac
  [ -f "$MODDIR/$relative" ] && [ -f "$target" ] || {
    echo "! 覆盖文件或目标缺失：$target"; exit 1;
  }
done < "$MODDIR/overlay-files.txt"
while IFS="$tab" read -r relative target; do
  mount --bind "$MODDIR/$relative" "$target" || exit 1
  printf '%s\n' "$target" >> "$ledger"
  mount -o remount,bind,ro,nosuid,nodev,noexec "$MODDIR/$relative" "$target" || exit 1
  susfs_register "$target" || { echo "! SUSFS 注册失败：$target"; exit 1; }
  echo "OK $target"
done < "$MODDIR/overlay-files.txt"
touch "$LOCK/complete" || exit 1
complete=true
echo 'SUSFS 自挂载完成；元模块已跳过本模块。'
