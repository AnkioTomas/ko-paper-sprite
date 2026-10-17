#!/bin/bash
# 本地发版：tools/release.sh 1.2.3
#   改 _meta.lua 版本号 → CHANGELOG 的「未发布」改成该版本 → 跑测试 → 打包 dist/ → 提交并打 tag（不推送）
set -euo pipefail
V="${1:?用法: tools/release.sh VERSION（如 1.0.0）}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "版本号格式应为 X.Y.Z"; exit 1; }
cd "$(dirname "$0")/.."
[ -z "$(git status --porcelain)" ] || { echo "工作区不干净，先提交"; exit 1; }
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && { echo "tag v$V 已存在"; exit 1; }

LUAC=$(command -v luac5.1 || command -v luac); LUA=$(command -v lua5.1 || command -v lua)
find paper-sprite.koplugin spec -name '*.lua' -print0 | xargs -0 "$LUAC" -p
"$LUA" spec/headless.lua

sed -i.bak -E "s/version = \"[^\"]*\"/version = \"$V\"/" paper-sprite.koplugin/_meta.lua && rm paper-sprite.koplugin/_meta.lua.bak
TODAY=$(date +%Y-%m-%d)
if grep -q "^## 未发布" CHANGELOG.md; then
    sed -i.bak "s/^## 未发布.*/## $V - $TODAY/" CHANGELOG.md && rm CHANGELOG.md.bak
elif ! grep -q "^## $V" CHANGELOG.md; then
    echo "CHANGELOG.md 里没有「## 未发布」或「## $V」段落"; exit 1
fi

mkdir -p dist && rm -f "dist/paper-sprite.koplugin-v${V}.zip"
zip -qr "dist/paper-sprite.koplugin-v${V}.zip" paper-sprite.koplugin -x '*.DS_Store'
git add paper-sprite.koplugin/_meta.lua CHANGELOG.md
git commit -qm "Release v$V"
git tag -a "v$V" -m "v$V"
echo "已打 tag v${V}，包在 dist/paper-sprite.koplugin-v${V}.zip。推送：git push origin main --tags"
