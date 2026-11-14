#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""用 Teamo imagegen 把 v3/v4（及椅子、成就原图）批量上成鲜明彩色，写入 art-samples/v5。

现有 v3/v4 原图是淡彩 / 近乎灰度的线稿，只加饱和度不够。本脚本对每张做
image edit（默认 gpt-image-2.5-flare），保持构图与线稿，再请模型填上明确色相。

用法：
  python3 tools/colorize_art.py --dry-run
  python3 tools/colorize_art.py --only attic/attic_spring_night_clear.png
  python3 tools/colorize_art.py --workers 2
  python3 tools/colorize_art.py          # 可随时再跑，已成功的会跳过
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
V3 = ROOT / "art-samples/v3"
V4 = ROOT / "art-samples/v4"
V5 = ROOT / "art-samples/v5"
ACHIEVEMENTS = ROOT / "skills-workspace/achievements/raw"
CHAIR_SOURCES = [
    (ROOT / "skills-workspace/companion/chair_empty.png", "sprite/chair_empty.png"),
    (ROOT / "skills-workspace/companion/chair_read.png", "sprite/chair_read.png"),
    (ROOT / "skills-workspace/aye-turn/turn-a.png", "sprite/chair_turn.png"),
    (ROOT / "skills-workspace/aye-turn/turn-b.png", "sprite/chair_turn_left.png"),
]
TEAMO_CANDIDATES = [
    Path("/Applications/Teamo.app/Contents/MacOS/teamo-imagegen"),
    Path.home() / "Library/Application Support/com.teamolab.teamorouter/bin/teamo-imagegen",
]

# 分类尺寸与是否透明底：与当初生成原图时一致。
SPEC = {
    "places":        {"size": "1536x1024", "transparent": False},
    "attic":         {"size": "1536x1024", "transparent": False},
    "sprite":        {"size": "1024x1024", "transparent": True},
    "visitors":      {"size": "1024x1024", "transparent": True},
    "items":         {"size": "1024x1024", "transparent": True},
    "achievements":  {"size": "1024x1024", "transparent": True},
    "souvenirs":     {"size": "1024x1024", "transparent": True},
    "props":         {"size": "1024x1024", "transparent": True},
}

SCENE_PROMPT = """\
Recolor this exact illustration with vivid, saturated storybook colors. Recolor only: keep composition, camera, poses, outlines, and every object's shape and placement. Do not add, remove, or move objects. Empty shelves stay empty. Blank papers stay blank. Do not add rugs, extra books, new flowers, or new props. No text or letters.

Every region gets a clear hue so the picture is obviously in color: blue skies by day, green foliage, warm honey-brown wood, colorful existing fabrics and book covers, rich water, cream paper walls. Clean ink line art with cel-shaded fills and light halftone, children's picture book style. Not photorealistic, not monochrome, not a faint beige tint on gray ink.
"""

# 仅在原图本来就有阿页、且该资产语义需要阿页时附加。切勿写进通用底稿，以免污染 empty 或地点图。
AYE_LOOK = (
    "If and only if the source illustration already shows Aye the folded-paper spirit, "
    "keep Aye exactly as drawn: off-white cream paper body, center crease, top-right dog-eared corner, "
    "two black dot eyes, NO mouth, thin black stick arms and legs. Body stays paper-colored. "
    "Do not add Aye, a person, or any substitute character if the source has no such figure."
)

# empty 阁楼：出门无人。即使原图误画了纸人，也必须去掉。
EMPTY_ATTIC_RULE = (
    "This attic is EMPTY because the occupant is away. There must be NO character anywhere: "
    "no Aye, no folded-paper spirit, no person, no creature, and no substitute figure. "
    "The chair is vacant. If the source mistakenly shows a paper character or anyone sitting, "
    "REMOVE that figure completely and leave the chair empty. Keep the vacant chair, desk, lamp, "
    "window, wall papers, hanging cloth or scarf, and other existing props. Empty shelves stay empty. "
    "Do not add books, toys, rugs, or clutter. No text or letters."
)

EMPTY_CHAIR_RULE = (
    "This is an EMPTY chair with nobody sitting on it. Do not add Aye, a person, or any character."
)

CUTOUT_PROMPT = """\
Recolor this exact character or object with vivid, saturated storybook colors, isolated on a fully transparent background, no ground, no shadow box, no backdrop. Recolor only: keep the pose, outlines, linework, and silhouette. Do not add, remove, or move anything. No text or letters.

Give the figure clear, distinct hues so it is obviously in color: warm browns, golds, greens, blues, or other fitting local colors, plus light cel shading and halftone. Clean ink line art, not photorealistic, not monochrome, not a faint beige tint on gray ink.
"""


def find_teamo() -> Path:
    for p in TEAMO_CANDIDATES:
        if p.is_file() and os.access(p, os.X_OK):
            return p
    raise SystemExit("未找到 teamo-imagegen，请确认已安装 Teamo.app")


def iter_named(folder: Path):
    if not folder.is_dir():
        return
    for p in sorted(folder.glob("*.png")):
        if "retry" in p.name:
            continue
        yield p.name, p


def collect_jobs() -> list[dict]:
    """v4 覆盖 v3，再补成就原图和椅子姿势。"""
    found: dict[str, Path] = {}
    for src in (V3, V4):
        for cat in SPEC:
            for name, path in iter_named(src / cat) or []:
                found[f"{cat}/{name}"] = path
    for name, path in iter_named(ACHIEVEMENTS) or []:
        found[f"achievements/{name}"] = path
    for path, rel in CHAIR_SOURCES:
        if path.is_file():
            found[rel] = path
    jobs = []
    for rel, src in sorted(found.items()):
        cat, name = rel.split("/", 1)
        spec = SPEC[cat]
        jobs.append({
            "rel": rel,
            "src": src,
            "dst": V5 / rel,
            "cat": cat,
            "name": name,
            "size": spec["size"],
            "transparent": spec["transparent"],
        })
    return jobs


def attic_hints(stem: str) -> list[str]:
    parts = set(stem.split("_"))
    hints = []
    if "spring" in parts:
        hints.append("Season is spring: fresh greens, blossom colors already in the drawing.")
    elif "summer" in parts:
        hints.append("Season is summer: lush greens, warm bright daylight when it is day.")
    elif "autumn" in parts:
        hints.append("Season is autumn: gold, amber, and rust foliage, warm low light.")
    elif "winter" in parts:
        hints.append("Season is winter: cool palette, bare branches or snow if already drawn.")
    if "night" in parts:
        hints.append(
            "It is NIGHT. Window: dark indigo night sky with moonlight or stars, not daylight. "
            "Dim interior, cool shadows, warm gold lamplight as the main illumination. "
            "Do not make it daytime."
        )
    elif "dusk" in parts:
        hints.append(
            "It is DUSK / evening. Sky and window should be warm orange, peach, or violet twilight, "
            "not midday blue. Long warmer shadows."
        )
    elif "day" in parts:
        hints.append("It is daytime.")
    if "drizzle" in parts:
        hints.append("Weather is rain / drizzle: wet cool gray-blue sky, rainy window, damp atmosphere.")
    elif "snow" in parts:
        hints.append("Weather is snow: cool light, visible snow, wintery colors.")
    elif "mist" in parts:
        hints.append("Weather is mist / fog: soft muted distance, pearly cool air, still clearly colored nearby.")
    elif "clear" in parts:
        hints.append("Weather is clear.")
    return hints


def _is_empty_asset(job: dict) -> bool:
    stem = Path(job["name"]).stem.lower()
    if "empty" in stem.split("_") or stem.endswith("_empty") or stem == "empty":
        return True
    if job["rel"] == "sprite/chair_empty.png":
        return True
    return False


def build_prompt(job: dict) -> str:
    if job["transparent"]:
        prompt = CUTOUT_PROMPT.strip()
    else:
        prompt = SCENE_PROMPT.strip()
    if job["cat"] == "attic":
        hints = attic_hints(Path(job["name"]).stem)
        if hints:
            prompt = prompt + "\n\nThis particular image: " + " ".join(hints)
        if _is_empty_asset(job):
            prompt = prompt + "\n\n" + EMPTY_ATTIC_RULE
        else:
            prompt = prompt + "\n\n" + AYE_LOOK
    elif _is_empty_asset(job):
        prompt = prompt + "\n\n" + EMPTY_CHAIR_RULE
    elif job["cat"] in ("sprite", "visitors", "achievements"):
        # 这些分类里常见阿页或角色，仅当原图已有时保持外形；不写进通用底稿。
        prompt = prompt + "\n\n" + AYE_LOOK
    return prompt


def valid_output(path: Path, size: str) -> bool:
    if not path.is_file() or path.stat().st_size < 10_000:
        return False
    try:
        with Image.open(path) as im:
            im.load()
            want = tuple(int(x) for x in size.split("x"))
            if im.size != want:
                return False
            if im.mode not in ("RGB", "RGBA", "P"):
                return False
    except Exception:
        return False
    return True


def run_teamo(teamo: Path, job: dict, prompt: str, quality: str, model: str, timeout: int) -> tuple[int, str]:
    dst: Path = job["dst"]
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_suffix(".part.png")
    if tmp.exists():
        tmp.unlink()
    cmd = [
        str(teamo), "edit",
        "--model", model,
        "--image", str(job["src"]),
        "--prompt", prompt,
        "--size", job["size"],
        "--quality", quality,
        "--output-format", "png",
        "--out", str(tmp),
    ]
    if job["transparent"]:
        cmd.extend(["--background", "transparent"])
    log_path = V5 / "logs" / (job["rel"].replace("/", "__") + ".log")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") + (e.stderr or "")
        log_path.write_text(out + f"\nTIMEOUT after {timeout}s\n")
        if tmp.exists():
            tmp.unlink()
        return 124, "timeout"
    text = (proc.stdout or "") + (proc.stderr or "")
    log_path.write_text(text)
    if proc.returncode == 0 and valid_output(tmp, job["size"]):
        tmp.replace(dst)
        return 0, "ok"
    if tmp.exists():
        tmp.unlink()
    err = text.strip().splitlines()[-1] if text.strip() else f"exit {proc.returncode}"
    return proc.returncode or 1, err[:300]


def process_job(teamo: Path, job: dict, args) -> dict:
    rel = job["rel"]
    if valid_output(job["dst"], job["size"]) and not args.force:
        return {"rel": rel, "status": "skip"}
    prompt = build_prompt(job)
    last_err = ""
    for attempt in range(1, args.retries + 1):
        rc, err = run_teamo(teamo, job, prompt, args.quality, args.model, args.timeout)
        if rc == 0:
            return {"rel": rel, "status": "ok", "attempt": attempt}
        last_err = err
        # 瞬时 API 错误（缺 b64、网络）再试；未知选项之类不必连打。
        transient = any(s in (err or "").lower() for s in (
            "b64_json", "request failed", "timeout", "status 5", "status 429",
            "rate", "temporar", "connection", "empty",
        ))
        if not transient and attempt == 1 and "b64" not in (err or "").lower():
            # 仍再试一次，Teamo 有时会给含糊错误
            pass
        if attempt < args.retries:
            time.sleep(min(8 * attempt, 40))
    return {"rel": rel, "status": "fail", "error": last_err, "attempt": args.retries}


def main(argv=None):
    parser = argparse.ArgumentParser(description="批量把阿页素材上成鲜明彩色（Teamo edit → art-samples/v5）")
    parser.add_argument("--dry-run", action="store_true", help="只列出任务，不调用 API")
    parser.add_argument("--only", action="append", default=[], help="只处理这些相对路径，可重复")
    parser.add_argument("--workers", type=int, default=2, help="并行数，默认 2（更高容易触发 API 空包）")
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--quality", default="high", help="low/medium/high/auto")
    parser.add_argument("--model", default="gpt-image-2.5-flare")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--force", action="store_true", help="已成功的也重跑")
    parser.add_argument("--limit", type=int, default=0, help="最多处理这么多未完成任务（测试用）")
    args = parser.parse_args(argv)

    jobs = collect_jobs()
    if args.only:
        want = set(args.only)
        jobs = [j for j in jobs if j["rel"] in want]
        missing = want - {j["rel"] for j in jobs}
        if missing:
            print("unknown --only:", ", ".join(sorted(missing)), file=sys.stderr)
            return 2

    if args.dry_run:
        for j in jobs:
            print(f"{j['rel']}\t{j['size']}\t{'t' if j['transparent'] else 'o'}\t{j['src']}")
        print(f"total {len(jobs)}", file=sys.stderr)
        return 0

    teamo = find_teamo()
    pending = [j for j in jobs if args.force or not valid_output(j["dst"], j["size"])]
    if args.limit:
        pending = pending[: args.limit]
    skipped = len(jobs) - len(pending)
    print(f"teamo={teamo} model={args.model} quality={args.quality} workers={args.workers}", flush=True)
    print(f"jobs={len(jobs)} pending={len(pending)} already={skipped}", flush=True)

    V5.mkdir(parents=True, exist_ok=True)
    status_path = V5 / "status.jsonl"
    ok = fail = skip = skipped
    started = time.time()
    workers = max(1, args.workers)

    def write_status(row: dict):
        row = dict(row)
        row["t"] = time.strftime("%Y-%m-%d %H:%M:%S")
        with status_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    if workers == 1:
        results = []
        for i, job in enumerate(pending, 1):
            row = process_job(teamo, job, args)
            results.append(row)
            write_status(row)
            print(f"[{i}/{len(pending)}] {row['status']} {row['rel']}"
                  + (f" ({row.get('error','')})" if row["status"] == "fail" else ""),
                  flush=True)
    else:
        results = []
        done = 0
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futs = {pool.submit(process_job, teamo, job, args): job for job in pending}
            for fut in as_completed(futs):
                row = fut.result()
                results.append(row)
                write_status(row)
                done += 1
                print(f"[{done}/{len(pending)}] {row['status']} {row['rel']}"
                      + (f" ({row.get('error','')})" if row["status"] == "fail" else ""),
                      flush=True)

    for row in results:
        if row["status"] == "ok":
            ok += 1
        elif row["status"] == "skip":
            skip += 1
        else:
            fail += 1
    elapsed = time.time() - started
    print(f"done ok={ok} fail={fail} skip={skip} elapsed={elapsed:.0f}s", flush=True)
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
