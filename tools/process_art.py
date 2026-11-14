#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""把 art-samples/v3、v4、v5 下的原图处理成插件素材：裁切 / 缩放 / 量化压缩。

默认输出彩色 PNG（透明层 alpha 仅 0/255）。v5 是用 tools/colorize_art.py
（Teamo image edit）上过鲜明颜色的版本，同名文件覆盖 v3/v4 的淡彩稿。
传入 --gray 则改为 4 级灰 Bayer 4×4 有序抖动（旧版观感，供对照）。
可同时预生成灰度到 --gray-dir。

多个源目录按顺序处理，后面的同名文件覆盖前面的。天气 / 时刻层由本脚本
程序生成（鲜明彩色网点，二元 alpha），不需要原图。

成就原图额外读取 skills-workspace/achievements/raw（不在 v3/v4 分类目录里）。
伴读椅子姿势额外读取 skills-workspace/companion 与 skills-workspace/aye-turn。

需要 Pillow；若本机有 pngquant，会再压一档。用法：
  python3 tools/colorize_art.py          # 先把 v3/v4 上成鲜明彩色，写入 v5
  python3 tools/process_art.py [源目录...，默认 art-samples/v3 v4 v5]
  python3 tools/process_art.py --gray
  python3 tools/process_art.py --gray-dir paper-sprite.koplugin/assets-gray
"""
import argparse
import math
import os
import random
import shutil
import subprocess
import sys
from PIL import Image, ImageOps, ImageEnhance, ImageDraw, ImageChops

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
DST_DEFAULT = os.path.join(ROOT, "paper-sprite.koplugin/assets")
LV = [0x00, 0x55, 0xAA, 0xFF]
B4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
PNGQUANT = shutil.which("pngquant") or shutil.which("/opt/homebrew/bin/pngquant")

# 成就原图不在 art-samples 分类目录里；椅子姿势在伴读工作目录。
EXTRA_ACHIEVEMENTS = os.path.join(ROOT, "skills-workspace/achievements/raw")
CHAIR_SOURCES = [
    (os.path.join(ROOT, "skills-workspace/companion/chair_empty.png"), "chair_empty.png"),
    (os.path.join(ROOT, "skills-workspace/companion/chair_read.png"), "chair_read.png"),
    # 翻页：右页抬起 → 页落到左边（与现用动画帧一致）
    (os.path.join(ROOT, "skills-workspace/aye-turn/turn-a.png"), "chair_turn.png"),
    (os.path.join(ROOT, "skills-workspace/aye-turn/turn-b.png"), "chair_turn_left.png"),
]


def dither(gray):
    """L 图 → 4 级灰有序抖动"""
    w, h = gray.size
    src = gray.load()
    out = Image.new("L", (w, h))
    dst = out.load()
    for y in range(h):
        row = B4[y & 3]
        for x in range(w):
            v = src[x, y] / 255 * 3
            base = int(v)
            if base >= 3:
                dst[x, y] = 255
                continue
            dst[x, y] = LV[base + (1 if (v - base) * 16 > row[x & 3] + 0.5 else 0)]
    return out


def prep(img):
    g = ImageOps.grayscale(img)
    g = ImageEnhance.Contrast(g).enhance(1.15)
    return g


def _ensure_dir(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)


def crush(path, colors=128):
    """有 pngquant 时再压一档；失败则保留 Pillow 结果。"""
    if not PNGQUANT or not os.path.isfile(path):
        return
    tmp = path + ".pq"
    cmd = [
        PNGQUANT, str(colors), "--force", "--quality=65-95", "--speed=1",
        "--output", tmp, path,
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=60)
        if r.returncode == 0 and os.path.isfile(tmp):
            if os.path.getsize(tmp) < os.path.getsize(path):
                os.replace(tmp, path)
            else:
                os.remove(tmp)
        elif os.path.isfile(tmp):
            os.remove(tmp)
    except (OSError, subprocess.SubprocessError):
        if os.path.isfile(tmp):
            os.remove(tmp)


def save_scene_color(im, dst, colors=128):
    """RGB 场景：自适应调色板，尽量小于无压缩 RGB。"""
    _ensure_dir(dst)
    q = im.quantize(colors=colors, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE)
    q.save(dst, optimize=True, compress_level=9)
    crush(dst, colors)


def save_cutout_color(im, dst, colors=96):
    """RGBA 抠图：二元 alpha，量化后交给 pngquant 收成带 tRNS 的调色板。"""
    _ensure_dir(dst)
    alpha = im.getchannel("A")
    rgb = im.convert("RGB")
    q = rgb.quantize(colors=colors, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE)
    out = q.convert("RGBA")
    out.putalpha(alpha)
    out.save(dst, optimize=True, compress_level=9)
    crush(dst, colors)


def scene(src, dst, size=(1200, 600), gray=False):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    th = int(w * size[1] / size[0])
    top = max(0, (h - th) // 2)
    im = im.crop((0, top, w, top + th)).resize(size, Image.LANCZOS)
    _ensure_dir(dst)
    if gray:
        dither(prep(im)).save(dst, optimize=True)
    else:
        save_scene_color(im, dst, 128)


def cutout(src, dst, size, white_bg=False, gray=False):
    im = Image.open(src).convert("RGBA")
    if white_bg:
        rgb = im.convert("RGB")
        corner = rgb.getpixel((0, 0))
        if min(corner) >= 240:
            ImageDraw.floodfill(rgb, (0, 0), (255, 0, 255), thresh=24)
            marker = Image.new("RGB", rgb.size, (255, 0, 255))
            alpha = ImageChops.difference(rgb, marker).convert("L").point(lambda v: 0 if v == 0 else 255)
            im = rgb.convert("RGBA")
            im.putalpha(alpha)
    a = im.getchannel("A")
    bbox = a.point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0, *im.size)
    im = im.crop(bbox)
    side = max(im.size)
    sq = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    sq.paste(im, ((side - im.width) // 2, side - im.height))  # 贴底对齐，方便站在地面
    sq = sq.resize((size, size), Image.LANCZOS)
    alpha = sq.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    if gray:
        flat = Image.new("RGB", sq.size, (255, 255, 255))
        flat.paste(sq, mask=alpha)
        g = dither(prep(flat))
        out = Image.merge("LA", (g, alpha))
        _ensure_dir(dst)
        out.save(dst, optimize=True)
    else:
        sq.putalpha(alpha)
        save_cutout_color(sq, dst, 96)


def weather(dst_dir, W=1200, H=600, gray=False):
    """纸面层：彩色（或灰度）网点 / 短线，alpha 只有 0 或 255，不要半透明脏边。"""
    os.makedirs(dst_dir, exist_ok=True)
    rnd = random.Random(7)

    def blank():
        if gray:
            return Image.new("LA", (W, H), (255, 0))
        return Image.new("RGBA", (W, H), (255, 255, 255, 0))

    def ink(rgb, level=None):
        if gray:
            return (level if level is not None else 0x55, 255)
        return (rgb[0], rgb[1], rgb[2], 255)

    # 小雨：斜短线，青灰
    im = blank(); p = im.load()
    drop = ink((70, 130, 200), 0x55)
    for _ in range(900):
        x, y = rnd.randrange(W), rnd.randrange(H)
        for i in range(10):
            if 0 <= x + i // 3 < W and 0 <= y + i < H:
                p[x + i // 3, y + i] = drop
    im.save(f"{dst_dir}/drizzle.png", optimize=True); crush(f"{dst_dir}/drizzle.png", 16)

    # 落纸屑：带深边的小白方块，偶发浅色碎片
    im = blank(); p = im.load()
    whites = [ink((255, 255, 255), 0xFF), ink((235, 242, 250), 0xFF), ink((255, 246, 230), 0xFF)]
    edge_c = ink((40, 36, 32), 0x00)
    for _ in range(260):
        x, y = rnd.randrange(2, W - 6), rnd.randrange(2, H - 6)
        fill = whites[rnd.randrange(len(whites))]
        for dx in range(-1, 5):
            for dy in range(-1, 5):
                edge = dx in (-1, 4) or dy in (-1, 4)
                p[x + dx, y + dy] = edge_c if edge else fill
    im.save(f"{dst_dir}/snow.png", optimize=True); crush(f"{dst_dir}/snow.png", 16)

    # 起雾：下浓上淡的冷白网点
    im = blank(); p = im.load()
    mist_c = ink((220, 235, 250), 0xFF)
    for y in range(H):
        d = 0.15 + 0.55 * (y / H)
        for x in range(W):
            if B4[y & 3][x & 3] < d * 16:
                p[x, y] = mist_c
    im.save(f"{dst_dir}/mist.png", optimize=True); crush(f"{dst_dir}/mist.png", 8)

    # 黄昏：上半部稀疏暖褐网点
    im = blank(); p = im.load()
    dusk_c = ink((220, 96, 36), 0x55)
    for y in range(H):
        d = max(0.0, 0.35 * (1 - y / (H * 0.7)))
        for x in range(W):
            if B4[y & 3][x & 3] < d * 16:
                p[x, y] = dusk_c
    im.save(f"{dst_dir}/dusk.png", optimize=True); crush(f"{dst_dir}/dusk.png", 8)

    # 夜里：靛蓝网点 + 星星
    im = blank(); p = im.load()
    night_c = ink((16, 20, 80), 0x00)
    star_c = ink((255, 252, 240), 0xFF)
    for y in range(H):
        for x in range(W):
            if B4[y & 3][x & 3] < 6:
                p[x, y] = night_c
    for _ in range(70):
        x, y = rnd.randrange(3, W - 3), rnd.randrange(3, H // 2)
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            p[x + dx, y + dy] = star_c
    im.save(f"{dst_dir}/night.png", optimize=True); crush(f"{dst_dir}/night.png", 8)

    # 起风：墨褐弧线 + 翻飞的小纸片
    im = blank(); p = im.load()
    wind_c = ink((42, 32, 28), 0x00)
    scrap = ink((250, 244, 230), 0xFF)
    for _ in range(26):
        x0, y0, L = rnd.randrange(-100, W), rnd.randrange(20, H - 20), rnd.randrange(120, 320)
        amp, ph = rnd.uniform(6, 16), rnd.uniform(0, 6.28)
        for i in range(L):
            if (i // 18) % 3 == 2:
                continue
            x, y = x0 + i, int(y0 + amp * math.sin(ph + i / 40))
            if 0 <= x < W and 0 <= y < H:
                p[x, y] = wind_c
    for _ in range(14):
        x, y = rnd.randrange(4, W - 10), rnd.randrange(4, H - 8)
        for dx in range(-1, 7):
            for dy in range(-1, 4):
                if 0 <= x + dx + dy < W:
                    p[x + dx + dy, y + dy] = wind_c if dx in (-1, 6) or dy in (-1, 3) else scrap
    im.save(f"{dst_dir}/wind.png", optimize=True); crush(f"{dst_dir}/wind.png", 16)

    # 星夜：上深下浅的蓝黑网点 + 十字星
    im = blank(); p = im.load()
    sky = ink((12, 18, 72), 0x00)
    star_c = ink((255, 250, 230), 0xFF)
    for y in range(H):
        d = 9 - 6 * y / H
        for x in range(W):
            if B4[y & 3][x & 3] < d:
                p[x, y] = sky
    for _ in range(160):
        x, y = rnd.randrange(6, W - 6), rnd.randrange(6, int(H * 0.7))
        r = 1 if rnd.random() < 0.8 else 3
        for k in range(-r, r + 1):
            p[x + k, y] = star_c
            p[x, y + k] = star_c
    im.save(f"{dst_dir}/starry.png", optimize=True); crush(f"{dst_dir}/starry.png", 8)

    # 日出：金太阳 + 浅橙光线，天空上部淡暖压暗
    im = blank(); p = im.load()
    sun = ink((255, 200, 64), 0xFF)
    rim = ink((255, 130, 40), 0x55)
    ray = ink((255, 200, 110), 0xFF)
    wash = ink((255, 120, 60), 0x55)
    cx, cy, R0 = int(W * 0.84), int(H * 0.42), 54
    for y in range(H):
        for x in range(W):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if r < R0:
                p[x, y] = sun
                continue
            if r < R0 + 4:
                p[x, y] = rim
                continue
            ang = math.atan2(dy, dx)
            if int((ang + math.pi) / math.pi * 36) % 2 == 0 and r < 260 and B4[y & 3][x & 3] < 3:
                p[x, y] = ray
            elif y < H * 0.3 and B4[y & 3][x & 3] < 2:
                p[x, y] = wash
    im.save(f"{dst_dir}/sunrise.png", optimize=True); crush(f"{dst_dir}/sunrise.png", 16)

    # 飘花瓣：浅粉椭圆，深边，斜着落
    im = blank(); p = im.load()
    petal = ink((255, 90, 140), 0xAA)
    petal_edge = ink((180, 20, 70), 0x00)
    for _ in range(90):
        x, y = rnd.randrange(10, W - 10), rnd.randrange(10, H - 10)
        a, b, t = rnd.uniform(6, 9), rnd.uniform(3, 4.5), rnd.uniform(0, 3.14)
        ct, st = math.cos(t), math.sin(t)
        for dx in range(-9, 10):
            for dy in range(-9, 10):
                u, v = (dx * ct + dy * st) / a, (-dx * st + dy * ct) / b
                q = u * u + v * v
                if q <= 1:
                    p[x + dx, y + dy] = petal if q < 0.6 else petal_edge
    im.save(f"{dst_dir}/petals.png", optimize=True); crush(f"{dst_dir}/petals.png", 16)


SPEC = {"places": ("scene", None), "attic": ("scene", None), "sprite": ("cut", 320),
        "visitors": ("cut", 200), "items": ("cut", 128), "achievements": ("cut_white", 128),
        "props": ("cut", 200), "souvenirs": ("cut", 128)}


def process_one(src, dst, kind, size, gray):
    if kind == "scene":
        scene(src, dst, gray=gray)
    else:
        cutout(src, dst, size, white_bg=kind == "cut_white", gray=gray)


def iter_pngs(d):
    if not os.path.isdir(d):
        return
    for f in sorted(os.listdir(d)):
        if f.endswith(".png") and "retry" not in f:
            yield f, os.path.join(d, f)


def main(argv=None):
    parser = argparse.ArgumentParser(description="处理阿页阁楼插件素材")
    parser.add_argument("sources", nargs="*", help="源目录，默认 art-samples/v3、v4 与 v5")
    parser.add_argument("--gray", action="store_true", help="输出 4 级灰有序抖动（覆盖默认彩色）")
    parser.add_argument("--gray-dir", help="另外把 4 级灰版本写到这个目录（默认目录仍是彩色）")
    parser.add_argument("--dst", default=DST_DEFAULT, help="彩色（或 --gray）输出目录")
    args = parser.parse_args(argv)

    srcs = args.sources or [
        os.path.join(ROOT, "art-samples/v3"),
        os.path.join(ROOT, "art-samples/v4"),
        os.path.join(ROOT, "art-samples/v5"),
    ]
    gray_only = bool(args.gray)
    n = 0

    def run_tree(dst, gray):
        nonlocal n
        count = 0
        for SRC in srcs:
            for sub, (kind, size) in SPEC.items():
                for f, path in iter_pngs(os.path.join(SRC, sub)) or []:
                    process_one(path, os.path.join(dst, sub, f), kind, size, gray)
                    count += 1
                    n += 1
        # 成就 / 椅子：仅当 v3/v4/v5 都没有同名文件时，从工作区原图补。
        # 不能放在源目录循环之后无条件处理，否则会覆盖已经成功的 v5 鲜艳稿。
        def missing_in_srcs(sub, filename):
            return not any(os.path.isfile(os.path.join(SRC, sub, filename)) for SRC in srcs)

        for f, path in iter_pngs(EXTRA_ACHIEVEMENTS) or []:
            if not missing_in_srcs("achievements", f):
                continue
            process_one(path, os.path.join(dst, "achievements", f), "cut_white", 128, gray)
            count += 1
            n += 1
        for path, name in CHAIR_SOURCES:
            if os.path.isfile(path) and missing_in_srcs("sprite", name):
                process_one(path, os.path.join(dst, "sprite", name), "cut", 320, gray)
                count += 1
                n += 1
        weather(os.path.join(dst, "weather"), gray=gray)
        return count

    # iter_pngs 在目录不存在时返回 None，上面 `or []` 已兜住
    c = run_tree(args.dst, gray_only)
    extra = 0
    if args.gray_dir and not gray_only:
        # 同时预生成灰度，不占用默认插件目录
        n = 0
        extra = run_tree(args.gray_dir, True)
    print("processed", c, "color" if not gray_only else "gray",
          ("+ %d gray copies" % extra) if extra else "")
    if PNGQUANT:
        print("pngquant", PNGQUANT)
    else:
        print("pngquant not found; palette PNG only")


if __name__ == "__main__":
    main()
