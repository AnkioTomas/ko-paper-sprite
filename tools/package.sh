#!/bin/bash
# 打包 paper-sprite.koplugin：tools/package.sh [版本] [输出 zip]
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
OUT="${2:-dist/paper-sprite.koplugin-$VERSION.zip}"
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT"
# 在临时副本里把版本号写进 papersprite/version.lua，源码保持占位符
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R paper-sprite.koplugin "$STAGE/paper-sprite.koplugin"
sed -i.bak "s/@VERSION@/${VERSION}/g" "$STAGE/paper-sprite.koplugin/papersprite/version.lua"
rm -f "$STAGE/paper-sprite.koplugin/papersprite/version.lua.bak"
(cd "$STAGE" && zip -rq "$OUT" paper-sprite.koplugin -x '*.DS_Store')
echo "$OUT"
