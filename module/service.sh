#!/system/bin/sh
MODDIR=${0%/*}
[ "$KSU" = true ] || exit 0
if [ "$(cat "$MODDIR/variant")" = susfs ]; then
  [ -f /dev/extreme_gt_susfs.lock/complete ] || exit 0
fi
# Each write is optional: kernel interfaces differ between devices.
write_node() {
  [ -f "$2" ] || return 0
  printf '%s\n' "$1" > "$2" 2>/dev/null || return 0
}
lock_value() {
  [ -f "$2" ] || return 0
  chmod 0644 "$2" 2>/dev/null || return 0
  write_node "$1" "$2"
  chmod 0444 "$2" 2>/dev/null || :
}
soc=$(getprop ro.board.platform)
case "$soc" in
  mt6891|mt6893|mt6889)
    . "$MODDIR/assets/d1x00/service.sh"
    ;;
  *)
    for tz in /sys/class/thermal/thermal_zone*; do
      [ -f "$tz/type" ] && [ -f "$tz/emul_temp" ] || continue
      value=29500
      case "$(cat "$tz/type")" in
        pm8550_gpio03_usr|pm8550vs_g_tz|pm8550b_tz|pm8550vs_c_tz|pa-therm2-sys3|rear-tof-therm|cam-flash-therm|batt-therm|usb-therm|wlan-therm|xo-therm|oplus_thermal_ipa|board_temp|ap_ntc|ltepa_ntc|nrpa_ntc|wcn_temp) ;;
        shell*) value=33000 ;;
        *) continue ;;
      esac
      write_node "$value" "$tz/emul_temp"
    done
    for i in 0 1 2 3 4 5 6 7 8 9; do
      write_node "$i 29500" /proc/shell-temp
    done
    gu=/proc/oplus-votable/GAUGE_UPDATE
    for node in force_val force_active; do
      [ -f "$gu/$node" ] && chmod 0666 "$gu/$node" 2>/dev/null
    done
    write_node 1000 "$gu/force_val"
    write_node 1 "$gu/force_active"
    ;;
esac
exit 0
