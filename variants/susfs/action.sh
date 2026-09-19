#!/system/bin/sh
MODDIR=${0%/*}
printf '%s\n' 'Extreme GT · susfs' '挂载方式：SUSFS 协同自行挂载。' '执行按钮：查看启动挂载结果，不在启动后补挂载。'
if [ -f "$MODDIR/skip_mount" ]; then
  printf '%s\n' '元模块挂载：已跳过。'
else
  printf '%s\n' '异常：缺少 skip_mount，请重新安装 SUSFS 版。'
fi
if [ -f /dev/extreme_gt_susfs.lock/complete ]; then
  printf '%s\n' '本次启动：自行挂载流程已完成。'
else
  printf '%s\n' '本次启动：未发现完成标记；可能未执行或已失败回滚。'
fi
[ -s "$MODDIR/overlay-files.txt" ] || { printf '%s\n' '未找到覆盖清单，请检查安装是否完成。'; exit 1; }
ok=0
failed=0
tab=$(printf '\t')
while IFS="$tab" read -r relative target; do
  if cmp -s "$MODDIR/$relative" "$target"; then
    printf '一致 %s\n' "$target"
    ok=$((ok + 1))
  else
    printf '不一致/不可读 %s\n' "$target"
    failed=$((failed + 1))
  fi
done < "$MODDIR/overlay-files.txt"
printf '一致：%s，不一致：%s\n' "$ok" "$failed"
printf '%s\n' '内容比对不能独立证明 SUSFS 隐藏效果。' '最近一次启动挂载日志：'
if [ -r /data/adb/extreme_gt_susfs/mount.log ]; then
  tail -n 60 /data/adb/extreme_gt_susfs/mount.log
else
  printf '%s\n' '暂无日志。安装或启用后请重启。'
fi
