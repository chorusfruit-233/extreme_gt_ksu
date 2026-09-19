#!/system/bin/sh
# Do not change SUSFS global configuration or download a replacement helper.
susfs_check() {
  SUSFS_BIN=/data/adb/ksu/bin/ksu_susfs
  KSUD=/data/adb/ksud
  [ -x "$SUSFS_BIN" ] || { echo '! 缺少 /data/adb/ksu/bin/ksu_susfs'; return 1; }
  susfs_features=$("$SUSFS_BIN" show enabled_features) || return 1
  printf '%s\n' "$susfs_features" | grep -qx 'CONFIG_KSU_SUSFS_SUS_MOUNT' || {
    echo '! 内核未提供 CONFIG_KSU_SUSFS_SUS_MOUNT'; return 1;
  }
  if printf '%s\n' "$susfs_features" | grep -qx 'CONFIG_KSU_SUSFS_TRY_UMOUNT'; then
    SUSFS_UMOUNT=susfs
  elif [ -x "$KSUD" ] && "$KSUD" kernel umount add --help >/dev/null 2>&1; then
    SUSFS_UMOUNT=ksud
  else
    echo '! 需要 SUSFS TRY_UMOUNT 或支持 kernel umount add 的 ksud'; return 1
  fi
}
susfs_register() {
  "$SUSFS_BIN" add_sus_mount "$1" || return 1
  if [ "$SUSFS_UMOUNT" = susfs ]; then
    "$SUSFS_BIN" add_try_umount "$1" 1
  else
    "$KSUD" kernel umount add "$1" --flags 2
  fi
}
