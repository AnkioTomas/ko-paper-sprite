#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""生成占位图（纯标准库，几何图形，4 级灰：0x00/0x55/0xAA/0xFF）。不使用任何外部图片。"""
import os, struct, zlib
G = [0x00, 0x55, 0xAA, 0xFF]
ROOT = os.path.join(os.path.dirname(__file__), "..", "paper-sprite.koplugin", "assets")

class Canvas:
    def __init__(s, w, h, bg=3, alpha=False):
        s.w, s.h, s.alpha = w, h, alpha
        s.px = [[(G[bg], 0 if alpha else 255)] * w for _ in range(h)]
    def put(s, x, y, g):
        if 0 <= x < s.w and 0 <= y < s.h: s.px[y][x] = (G[g], 255)
    def rect(s, x0, y0, x1, y1, g, fill=False):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if fill or y in (y0, y1) or x in (x0, x1): s.put(x, y, g)
    def circle(s, cx, cy, r, g, fill=False):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if d <= r * r and (fill or d >= (r - 2) ** 2): s.put(x, y, g)
    def tri(s, a, b, c, g):
        xs, ys = [p[0] for p in (a, b, c)], [p[1] for p in (a, b, c)]
        def sgn(p, q, r): return (p[0]-r[0])*(q[1]-r[1])-(q[0]-r[0])*(p[1]-r[1])
        for y in range(min(ys), max(ys) + 1):
            for x in range(min(xs), max(xs) + 1):
                d1, d2, d3 = sgn((x,y),a,b), sgn((x,y),b,c), sgn((x,y),c,a)
                if not ((d1<0 or d2<0 or d3<0) and (d1>0 or d2>0 or d3>0)): s.put(x, y, g)
    def dots(s, step, g):
        for y in range(0, s.h, step):
            for x in range((y // step) % 2 * step // 2, s.w, step): s.put(x, y, g)
    def save(s, rel):
        path = os.path.join(ROOT, rel); os.makedirs(os.path.dirname(path), exist_ok=True)
        raw = b"".join(b"\0" + b"".join(bytes([v, a]) for v, a in row) for row in s.px)
        def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", s.w, s.h, 8, 4, 0, 0, 0)) \
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
        open(path, "wb").write(png)

W, H = 600, 300
# 阁楼：斜屋顶、书桌、油灯、藤筐、明信片墙、阿页
c = Canvas(W, H); c.tri((0, 0), (W - 1, 0), (0, 90), 2); c.rect(0, 0, W - 1, H - 1, 0)
c.rect(60, 190, 300, 205, 0, True); c.rect(70, 205, 80, 280, 0, True); c.rect(280, 205, 290, 280, 0, True)
c.rect(240, 160, 252, 190, 1, True); c.circle(246, 150, 12, 2, True)
c.rect(380, 230, 470, 280, 1)
for i in range(4): c.rect(380 + i * 45, 60, 415 + i * 45, 110, 1)
c.rect(150, 150, 180, 190, 0); c.tri((170, 150), (180, 150), (180, 160), 0)  # 阿页：纸身 + 折角
c.save("attic/attic.png")
# 地点背景
c = Canvas(W, H); c.rect(0, 0, W-1, H-1, 0); c.rect(1, 170, W-2, H-2, 1, True); c.dots(14, 2); c.save("places/ink_lake.png")
c = Canvas(W, H); c.rect(0, 0, W-1, H-1, 0)
for i in range(5): c.rect(40 + i * 110, 120, 120 + i * 110, 260, 1)
c.dots(9, 2); c.save("places/fog_market.png")
c = Canvas(W, H); c.rect(0, 0, W-1, H-1, 0); c.tri((50, 280), (260, 40), (470, 280), 2); c.tri((300, 280), (430, 110), (560, 280), 1)
c.save("places/fold_peak.png")
# 姿势 / 道具 / 天气（透明图层）
for name, dx in (("sit", 0), ("wave", 10), ("peek", -10)):
    c = Canvas(120, 160, alpha=True); c.rect(30, 40, 90, 150, 0); c.tri((70, 40), (90, 40), (90, 60), 0)
    c.circle(50 + dx, 80, 3, 0, True); c.circle(70 + dx, 80, 3, 0, True); c.save(f"sprite/{name}.png")
c = Canvas(60, 90, alpha=True); c.rect(20, 30, 40, 80, 0); c.circle(30, 20, 10, 2, True); c.save("props/lantern.png")
c = Canvas(60, 60, alpha=True); c.rect(10, 25, 45, 50, 0); c.circle(50, 37, 6, 0); c.save("props/teacup.png")
for name, step in (("clear", 0), ("drizzle", 23), ("mist", 7)):
    c = Canvas(W, H, alpha=True)
    if step: c.dots(step, 2 if name == "mist" else 1)
    c.save(f"weather/{name}.png")
print("ok")
