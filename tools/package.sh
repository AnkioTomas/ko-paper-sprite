#!/bin/bash
# 打包 paper-sprite.koplugin：tools/package.sh [版本] [完整包 zip]
# 同时在同目录写出代码包：*-code.zip（不含 assets/）
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
VERSION="${VERSION#v}"
OUT="${2:-dist/paper-sprite.koplugin-$VERSION.zip}"
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
CODE_OUT="${OUT%.zip}-code.zip"
rm -f "$OUT" "$CODE_OUT"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R paper-sprite.koplugin "$STAGE/paper-sprite.koplugin"
sed -i.bak "s/@VERSION@/${VERSION}/g" "$STAGE/paper-sprite.koplugin/papersprite/version.lua"
rm -f "$STAGE/paper-sprite.koplugin/papersprite/version.lua.bak"

(cd "$STAGE" && zip -qrX "$OUT" paper-sprite.koplugin -x '*.DS_Store')

# 代码包：同一份树去掉 assets，首装仍用完整包
rm -rf "$STAGE/paper-sprite.koplugin/assets"
(cd "$STAGE" && zip -qrX "$CODE_OUT" paper-sprite.koplugin -x '*.DS_Store')

echo "$OUT"
echo "$CODE_OUT"
