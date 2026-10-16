#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""把 art-samples/v3、v4 下的原图处理成插件素材：裁切 / 缩放 / 4 级灰有序抖动（Bayer 4×4）。
多个源目录按顺序处理，后面的同名文件覆盖前面的。
天气 / 时刻层由本脚本程序生成（不需要原图）。需要 Pillow。
用法：python3 tools/process_art.py [源目录...，默认 art-samples/v3 art-samples/v4]"""
import math
import os, sys, random
from PIL import Image, ImageOps, ImageEnhance

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
SRCS = sys.argv[1:] or [os.path.join(ROOT, "art-samples/v3"), os.path.join(ROOT, "art-samples/v4")]
DST = os.path.join(ROOT, "paper-sprite.koplugin/assets")
LV = [0x00, 0x55, 0xAA, 0xFF]
B4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

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
            if base >= 3: dst[x, y] = 255; continue
            dst[x, y] = LV[base + (1 if (v - base) * 16 > row[x & 3] + 0.5 else 0)]
    return out

def prep(img):
    g = ImageOps.grayscale(img)
    g = ImageEnhance.Contrast(g).enhance(1.15)
    return g

def scene(src, dst, size=(1200, 600)):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    th = int(w * size[1] / size[0])
    top = max(0, (h - th) // 2)
    im = im.crop((0, top, w, top + th)).resize(size, Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    dither(prep(im)).save(dst, optimize=True)

def cutout(src, dst, size):
    im = Image.open(src).convert("RGBA")
    a = im.getchannel("A")
    bbox = a.point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0, *im.size)
    im = im.crop(bbox)
    side = max(im.size)
    sq = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    sq.paste(im, ((side - im.width) // 2, side - im.height))  # 贴底对齐，方便站在地面
    sq = sq.resize((size, size), Image.LANCZOS)
    flat = Image.new("RGB", sq.size, (255, 255, 255)); flat.paste(sq, mask=sq.getchannel("A"))
    g = dither(prep(flat))
    alpha = sq.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    out = Image.merge("LA", (g, alpha))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst, optimize=True)

def weather(dst_dir, W=1200, H=600):
    os.makedirs(dst_dir, exist_ok=True)
    rnd = random.Random(7)
    def blank(): return Image.new("LA", (W, H), (255, 0))
    # 小雨：斜短线
    im = blank(); p = im.load()
    for _ in range(900):
        x, y = rnd.randrange(W), rnd.randrange(H)
        for i in range(10):
            if 0 <= x + i // 3 < W and 0 <= y + i < H: p[x + i // 3, y + i] = (0x55, 255)
    im.save(f"{dst_dir}/drizzle.png", optimize=True)
    # 落纸屑：带黑边的小白方块
    im = blank(); p = im.load()
    for _ in range(260):
        x, y = rnd.randrange(2, W - 6), rnd.randrange(2, H - 6)
        for dx in range(-1, 5):
            for dy in range(-1, 5):
                edge = dx in (-1, 4) or dy in (-1, 4)
                p[x + dx, y + dy] = (0x00 if edge else 0xFF, 255)
    im.save(f"{dst_dir}/snow.png", optimize=True)
    # 起雾：下浓上淡的白色网点
    im = blank(); p = im.load()
    for y in range(H):
        d = 0.15 + 0.55 * (y / H)
        for x in range(W):
            if B4[y & 3][x & 3] < d * 16: p[x, y] = (0xFF, 255)
    im.save(f"{dst_dir}/mist.png", optimize=True)
    # 黄昏：上半部稀疏深灰网点
    im = blank(); p = im.load()
    for y in range(H):
        d = max(0.0, 0.35 * (1 - y / (H * 0.7)))
        for x in range(W):
            if B4[y & 3][x & 3] < d * 16: p[x, y] = (0x55, 255)
    im.save(f"{dst_dir}/dusk.png", optimize=True)
    # 夜里：均匀黑网点 + 星星
    im = blank(); p = im.load()
    for y in range(H):
        for x in range(W):
            if B4[y & 3][x & 3] < 6: p[x, y] = (0x00, 255)
    for _ in range(70):
        x, y = rnd.randrange(3, W - 3), rnd.randrange(3, H // 2)
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)): p[x + dx, y + dy] = (0xFF, 255)
    im.save(f"{dst_dir}/night.png", optimize=True)
    # 起风：长长的弧形风线 + 几片翻飞的小纸片
    im = blank(); p = im.load()
    for _ in range(26):
        x0, y0, L = rnd.randrange(-100, W), rnd.randrange(20, H - 20), rnd.randrange(120, 320)
        amp, ph = rnd.uniform(6, 16), rnd.uniform(0, 6.28)
        for i in range(L):
            if (i // 18) % 3 == 2: continue  # 断续
            x, y = x0 + i, int(y0 + amp * math.sin(ph + i / 40))
            if 0 <= x < W and 0 <= y < H: p[x, y] = (0x00, 255)
    for _ in range(14):
        x, y = rnd.randrange(4, W - 10), rnd.randrange(4, H - 8)
        for dx in range(-1, 7):
            for dy in range(-1, 4):
                if 0 <= x + dx + dy < W: p[x + dx + dy, y + dy] = (0x00 if dx in (-1, 6) or dy in (-1, 3) else 0xFF, 255)
    im.save(f"{dst_dir}/wind.png", optimize=True)
    # 星夜：上深下浅的黑网点 + 大小星星（十字星）
    im = blank(); p = im.load()
    for y in range(H):
        d = 9 - 6 * y / H
        for x in range(W):
            if B4[y & 3][x & 3] < d: p[x, y] = (0x00, 255)
    for _ in range(160):
        x, y = rnd.randrange(6, W - 6), rnd.randrange(6, int(H * 0.7))
        r = 1 if rnd.random() < 0.8 else 3
        for k in range(-r, r + 1): p[x + k, y] = (0xFF, 255); p[x, y + k] = (0xFF, 255)
    im.save(f"{dst_dir}/starry.png", optimize=True)
    # 日出：右侧远处升起的太阳 + 放射光线，天空上部淡淡压暗
    im = blank(); p = im.load()
    cx, cy, R0 = int(W * 0.84), int(H * 0.42), 54
    for y in range(H):
        for x in range(W):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if r < R0: p[x, y] = (0xFF, 255); continue
            if r < R0 + 4: p[x, y] = (0x55, 255); continue
            ang = math.atan2(dy, dx)
            if int((ang + math.pi) / math.pi * 36) % 2 == 0 and r < 260 and B4[y & 3][x & 3] < 3:
                p[x, y] = (0xFF, 255)
            elif y < H * 0.3 and B4[y & 3][x & 3] < 2: p[x, y] = (0x55, 255)
    im.save(f"{dst_dir}/sunrise.png", optimize=True)
    # 飘花瓣：带黑边的小椭圆花瓣，斜着落
    im = blank(); p = im.load()
    for _ in range(90):
        x, y = rnd.randrange(10, W - 10), rnd.randrange(10, H - 10)
        a, b, t = rnd.uniform(6, 9), rnd.uniform(3, 4.5), rnd.uniform(0, 3.14)
        ct, st = math.cos(t), math.sin(t)
        for dx in range(-9, 10):
            for dy in range(-9, 10):
                u, v = (dx * ct + dy * st) / a, (-dx * st + dy * ct) / b
                q = u * u + v * v
                if q <= 1: p[x + dx, y + dy] = (0xAA if q < 0.6 else 0x00, 255)
    im.save(f"{dst_dir}/petals.png", optimize=True)

SPEC = {"places": ("scene", None), "attic": ("scene", None), "sprite": ("cut", 320),
        "visitors": ("cut", 200), "items": ("cut", 128), "props": ("cut", 200), "souvenirs": ("cut", 128)}

if __name__ == "__main__":
    n = 0
    for SRC in SRCS:
      for sub, (kind, size) in SPEC.items():
        d = os.path.join(SRC, sub)
        if not os.path.isdir(d): continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".png"): continue
            out = os.path.join(DST, sub, f)
            (scene(os.path.join(d, f), out) if kind == "scene" else cutout(os.path.join(d, f), out, size)); n += 1
    weather(os.path.join(DST, "weather"))
    print("processed", n)
