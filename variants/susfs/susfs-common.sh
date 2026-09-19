#!/system/bin/sh
# Do not change SUSFS global configuration or download a replacement helper.
susfs_has_command() {
  printf '%s\n' "$susfs_help" | grep -Eq "(^|[[:space:]])$1([[:space:]]|$)"
}
susfs_check() {
  SUSFS_BIN=/data/adb/ksu/bin/ksu_susfs
  KSUD=/data/adb/ksud
  [ -x "$SUSFS_BIN" ] || { echo '! 缺少 /data/adb/ksu/bin/ksu_susfs'; return 1; }
  susfs_features=$("$SUSFS_BIN" show enabled_features) || return 1
  printf '%s\n' "$susfs_features" | grep -qx 'CONFIG_KSU_SUSFS_SUS_MOUNT' || {
    echo '! 内核未提供 CONFIG_KSU_SUSFS_SUS_MOUNT'; return 1;
  }
  susfs_version=$("$SUSFS_BIN" show version) || return 1
  susfs_help=$("$SUSFS_BIN" --help 2>&1) || :
  case "$susfs_version" in
    v2.*|2.*)
      # GKI SUSFS 2.x assigns SUS mount IDs in the KSU-domain mount/clone hooks.
      # Some universal helpers still advertise the removed manual command.
      SUSFS_MOUNT=auto
      ;;
    *)
      susfs_has_command add_sus_mount || {
        echo "! SUSFS $susfs_version 无可验证的挂载协同接口（无 add_sus_mount）"; return 1;
      }
      SUSFS_MOUNT=manual
      ;;
  esac
  if susfs_has_command add_try_umount && printf '%s\n' "$susfs_features" | grep -qx 'CONFIG_KSU_SUSFS_TRY_UMOUNT'; then
    SUSFS_UMOUNT=susfs
  elif [ -x "$KSUD" ] && "$KSUD" kernel umount add --help >/dev/null 2>&1; then
    SUSFS_UMOUNT=ksud
  else
    echo '! 需要 SUSFS TRY_UMOUNT 或支持 kernel umount add 的 ksud'; return 1
  fi
  echo "SUSFS $susfs_version: mount=$SUSFS_MOUNT, umount=$SUSFS_UMOUNT"
}
susfs_register() {
  if [ "$SUSFS_MOUNT" = manual ]; then
    "$SUSFS_BIN" add_sus_mount "$1" || return 1
  fi
  if [ "$SUSFS_UMOUNT" = susfs ]; then
    "$SUSFS_BIN" add_try_umount "$1" 1
  else
    "$KSUD" kernel umount add "$1" --flags 2
  fi
}
