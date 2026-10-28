#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""修复 21 张「假空图」：attic_*_empty.png 里还画着阿页（AI 生图时只把阿页画小了，没删掉）。

修法：阿页固定坐在画面中心，同季节、同时段已确认真空的那张图，房间构图一致。
把真空图的中心区域（椅子+墙面）带羽化贴回坏图，再按 process_art 的 4 级灰抖动重新量化。
原图已按 tools/process_art.py 入库过，这里只动中心贴片区，窗外天气/光线不换。

用法：python3 tools/fix_empty_attic.py [--check]
  --check 只打印每张坏图将用的 donor，不写文件。
"""
import os, sys
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
ATTIC = os.path.join(ROOT, "paper-sprite.koplugin/assets/attic")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from process_art import dither  # noqa: E402

# 坏图 -> donor（同季节同时段、已逐张看图确认真空）
FIX = {
    "attic_autumn_day_mist_empty.png": "attic_autumn_day_clear_empty.png",
    "attic_autumn_dusk_clear_empty.png": "attic_autumn_dusk_drizzle_empty.png",
    "attic_autumn_dusk_mist_empty.png": "attic_autumn_dusk_drizzle_empty.png",
    "attic_autumn_dusk_snow_empty.png": "attic_autumn_dusk_drizzle_empty.png",
    "attic_autumn_night_clear_empty.png": "attic_autumn_night_mist_empty.png",
    "attic_spring_night_clear_empty.png": "attic_spring_night_mist_empty.png",
    "attic_spring_night_drizzle_empty.png": "attic_spring_night_mist_empty.png",
    "attic_spring_night_snow_empty.png": "attic_spring_night_mist_empty.png",
    "attic_summer_day_drizzle_empty.png": "attic_summer_day_clear_empty.png",
    "attic_summer_day_mist_empty.png": "attic_summer_day_clear_empty.png",
    "attic_summer_dusk_clear_empty.png": "attic_summer_dusk_snow_empty.png",
    "attic_summer_dusk_drizzle_empty.png": "attic_summer_dusk_snow_empty.png",
    "attic_summer_dusk_mist_empty.png": "attic_summer_dusk_snow_empty.png",
    "attic_summer_night_clear_empty.png": "attic_summer_night_snow_empty.png",
    "attic_summer_night_drizzle_empty.png": "attic_summer_night_snow_empty.png",
    "attic_summer_night_mist_empty.png": "attic_summer_night_snow_empty.png",
    "attic_winter_day_snow_empty.png": "attic_winter_day_clear_empty.png",
    "attic_winter_dusk_clear_empty.png": "attic_winter_dusk_drizzle_empty.png",
    "attic_winter_dusk_mist_empty.png": "attic_winter_dusk_drizzle_empty.png",
    "attic_winter_dusk_snow_empty.png": "attic_winter_dusk_drizzle_empty.png",
    "attic_winter_night_snow_empty.png": "attic_winter_night_mist_empty.png",
}

# 阿页（纸人+书+腿）所在的中心区域，相对坐标；贴到画面底边（椅子腿完整），其余三边羽化融入原图
BOX = (0.325, 0.13, 0.635, 1.0)


def fix(name, donor_name):
    target = Image.open(os.path.join(ATTIC, name)).convert("L")
    donor = Image.open(os.path.join(ATTIC, donor_name)).convert("L")
    assert target.size == donor.size, (name, target.size, donor.size)
    w, h = target.size
    x0, y0, x1, y1 = (int(BOX[0] * w), int(BOX[1] * h), int(BOX[2] * w), int(BOX[3] * h))
    patch_t = target.crop((x0, y0, x1, y1))
    patch_d = donor.crop((x0, y0, x1, y1))
    # 亮度对齐：只比贴片上方的墙面条（阿页够不到那里），避免被白纸人拉偏
    strip = 18
    tt = patch_t.crop((0, 0, patch_t.width, strip))
    dd = patch_d.crop((0, 0, patch_d.width, strip))
    mean = lambda im: sum(im.getdata()) / (im.width * im.height)  # noqa: E731
    off = round(mean(tt) - mean(dd))
    if off:
        patch_d = patch_d.point(lambda v: max(0, min(255, v + off)))
    # 羽化只在贴片边缘：先把掩膜边缘收一圈再模糊（中心全实）；底边贴到画面边，不羽化
    inner = Image.new("L", patch_d.size, 0)
    inner.paste(255, (24, 24, patch_d.width - 24, patch_d.height))
    mask = inner.filter(ImageFilter.GaussianBlur(16))
    out = target.copy()
    out.paste(patch_d, (x0, y0), mask)
    dither(out).save(os.path.join(ATTIC, name), optimize=True)
    return off


if __name__ == "__main__":
    check = "--check" in sys.argv
    for name, donor in sorted(FIX.items()):
        if check:
            print(f"{name}  <- {donor}")
        else:
            print(f"{name}  <- {donor}  (亮度偏移 {fix(name, donor)})")
    print(len(FIX), "files", "checked" if check else "fixed")
