#!/system/bin/sh
MODDIR=${0%/*}
printf '%s\n' 'Extreme GT · hybrid_mount' '挂载方式：由 Hybrid Mount 元模块接管。' '执行按钮：检查当前可见文件，不触发挂载。'
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
printf '%s\n' '内容一致仅说明当前可见文件相同，实际挂载来源请在 Hybrid Mount 中查看。'
