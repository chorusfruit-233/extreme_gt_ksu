#!/system/bin/sh
# Sourced only after service.sh has read ro.board.platform.
for pair in '0 4' '4 3' '7 1'; do
  cpu=${pair% *}
  count=${pair#* }
  base=/sys/devices/system/cpu/cpu${cpu}/core_ctl
  lock_value "$count" "$base/max_cpus"
  lock_value "$count" "$base/min_cpus"
  lock_value 0 "$base/enable"
done
for i in 3 4 5 6; do
  write_node "$i 0 0" /proc/gpufreq/gpufreq_limit_table
done
for policy in hard_userlimit_cpu_freq hard_userlimit_freq_limit_by_others; do
  node=/proc/ppm/policy/$policy
  write_node '0 -1' "$node"
  write_node '1 -1' "$node"
  [ ! -f "$node" ] || chmod 0444 "$node" 2>/dev/null
done
write_node 1 /proc/ppm/enabled
if [ -f /proc/ppm/policy_status ]; then
  # Parse the complete policy index; upstream truncated multi-digit indices.
  while IFS= read -r row; do
    index=$(printf '%s\n' "$row" | sed -n 's/^[[:space:]]*\[\([0-9][0-9]*\)\].*/\1/p')
    [ -n "$index" ] || continue
    value=0
    case "$row" in *PPM_POLICY_HARD_USER_LIMIT*) value=1 ;; esac
    write_node "$index $value" /proc/ppm/policy_status
  done < /proc/ppm/policy_status
fi
lock_value 100 /sys/kernel/fpsgo/fbt/thrm_temp_th
lock_value -1 /sys/kernel/fpsgo/fbt/thrm_limit_cpu
lock_value -1 /sys/kernel/fpsgo/fbt/thrm_sub_cpu
for i in 0 1 2 3 4 5 6 7; do
  write_node "$i" /sys/devices/system/cpu/sched/set_sched_deisolation
done
node=/sys/devices/system/cpu/sched/set_sched_isolation
[ ! -f "$node" ] || chmod 000 "$node" 2>/dev/null
