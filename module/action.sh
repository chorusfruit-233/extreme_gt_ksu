#!/system/bin/sh
MODDIR=${0%/*}
printf '%s\n' 'Extreme GT: 覆盖文件比对（只读，不执行挂载）'
[ -f "$MODDIR/overlay-files.txt" ] || exit 1
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
case "$(cat "$MODDIR/variant")" in
  susfs)
    printf '%s\n' '文件一致不等于 SUSFS 协同已确认；最近挂载日志：'
    tail -n 60 /data/adb/extreme_gt_susfs/mount.log 2>/dev/null
    ;;
  *) printf '%s\n' '文件一致不等于挂载来源已确认；来源请在 Hybrid Mount 中查看。' ;;
esac
