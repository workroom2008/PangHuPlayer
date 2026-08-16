#!/bin/bash
# ============================================================
# APK 版本管理：只保留「最新」和「上一个」两个调试包
#
# 用法（每次构建前运行）：
#   bash scripts/save_apk.sh && flutter build apk --debug
#
# 构建前执行：把当前 app-debug.apk 保留为 lanplayer-debug-prev.apk，
# 然后清理所有历史自定义命名 apk 与 tv-* 副本。
#
# 最终目录（build/app/outputs/flutter-apk/）：
#   app-debug.apk              ← 最新调试版（构建产物）
#   lanplayer-debug-prev.apk   ← 上一个调试版（回滚用）
#   app-release.apk            ← 正式版（构建产物，需要时构建）
# ============================================================
set -e
cd "$(dirname "$0")/.."

DIR=build/app/outputs/flutter-apk

if [ ! -d "$DIR" ]; then
  echo "未找到 $DIR，请先在项目根目录运行。"
  exit 1
fi

# 1) 把当前最新调试包保留为「上一个」（内容相同则跳过，避免重复）
if [ -f "$DIR/app-debug.apk" ]; then
  if [ -f "$DIR/lanplayer-debug-prev.apk" ] && cmp -s "$DIR/app-debug.apk" "$DIR/lanplayer-debug-prev.apk"; then
    echo "上一个版本与当前相同，跳过（确认在每次构建前运行本脚本）"
  else
    cp -f "$DIR/app-debug.apk" "$DIR/lanplayer-debug-prev.apk"
    echo "已保留上一个版本: $DIR/lanplayer-debug-prev.apk"
  fi
fi

# 2) 清理所有历史 apk（只保留 app-debug / app-release / lanplayer-debug-prev）
find build -name "*.apk" \
  ! -name "app-debug.apk" \
  ! -name "app-release.apk" \
  ! -name "lanplayer-debug-prev.apk" \
  -delete

echo "清理完成，当前保留："
ls -lh "$DIR"/*.apk 2>/dev/null | awk '{print "  " $9 "  (" $5 ")"}'
