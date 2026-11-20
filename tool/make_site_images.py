#!/usr/bin/env python3
"""把模拟器截图打包成 GitHub Pages 用的 WebP，并生成站点图标。

手机上直接看 1440×2560 的 PNG 太大（一张近 2 MB），站点上按 720px 宽输出就够了：
页面上按 480 显示、2x 屏也有富余，单张掉到 40–80 KB。

用法::

    python tool/make_site_images.py
    python tool/make_site_images.py --src docs/screenshots --out docs/assets

名字按 NEWS_SHOTS 的表映射：`feed.png` → `shot-feed.webp`。
源图缺哪个就跳过哪个，不会中断 —— 截图是分几次抓的，缺一张不算错。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - 只在没装 Pillow 的机器上跑到
    sys.exit("需要 Pillow：python -m pip install Pillow")

# 源文件名 → 输出文件名。顺序即站点上的展示顺序。
SHOTS = {
    "feed.png": "shot-feed.webp",
    "detail.png": "shot-detail.webp",
    "comments.png": "shot-comments.webp",
    "discover.png": "shot-discover.webp",
    "settings.png": "shot-settings.webp",
    "profile.png": "shot-profile.webp",
}

ICON_SRC = Path("assets/icon/hobo_icon_512.png")
ICON_OUT = "icon-192.png"

TARGET_WIDTH = 720
WEBP_QUALITY = 82


def convert(source: Path, target: Path, width: int) -> tuple[int, int, int]:
    """等比缩到 width 宽，写成 WebP。返回 (宽, 高, 字节数)。"""
    with Image.open(source) as image:
        image = image.convert("RGB")
        height = round(image.height * width / image.width)
        resized = image.resize((width, height), Image.LANCZOS)
    target.parent.mkdir(parents=True, exist_ok=True)
    resized.save(target, "WEBP", quality=WEBP_QUALITY, method=6)
    return width, height, target.stat().st_size


def make_icon(target: Path) -> tuple[int, int, int]:
    with Image.open(ICON_SRC) as image:
        resized = image.convert("RGBA").resize((192, 192), Image.LANCZOS)
    target.parent.mkdir(parents=True, exist_ok=True)
    resized.save(target, "PNG", optimize=True)
    return 192, 192, target.stat().st_size


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", default="docs/screenshots", help="原始 PNG 目录")
    parser.add_argument("--out", default="docs/assets", help="输出目录")
    parser.add_argument("--width", type=int, default=TARGET_WIDTH, help="输出宽度")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    source_dir = (root / args.src).resolve()
    out_dir = (root / args.out).resolve()

    if not source_dir.is_dir():
        print(f"找不到截图目录：{source_dir}", file=sys.stderr)
        return 1

    made = 0
    for name, output in SHOTS.items():
        source = source_dir / name
        if not source.is_file():
            print(f"跳过（没有源图） {name}")
            continue
        width, height, size = convert(source, out_dir / output, args.width)
        print(f"{output:<22} {width}×{height}  {size / 1024:5.1f} KB")
        made += 1

    icon_source = root / ICON_SRC
    if icon_source.is_file():
        width, height, size = make_icon(out_dir / ICON_OUT)
        print(f"{ICON_OUT:<22} {width}×{height}  {size / 1024:5.1f} KB")
        made += 1
    else:
        print(f"跳过（没有图标） {ICON_SRC}", file=sys.stderr)

    if made == 0:
        print("一个文件都没生成。", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
