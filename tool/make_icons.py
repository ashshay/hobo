"""从 IconKitchen 导出的图稿生成 Hobo 的启动图标（圆角矩形 / 圆形两套）。

母版是 `assets/icon/hobo_icon.png`：512×512、铺满整张画布的方图（深绿底 + 白色回环箭头 +
底部青色条带 + HOBO 字样）。两种形状都在同一张母版上套遮罩得到，所以切换形状时画面内容
完全一致，只差边界：圆角矩形是 n=4 的超椭圆（和 Material 的 squircle 同一套路），圆形是正圆。

输出的两份都是**位图**（不带 `mipmap-anydpi-v26/*.xml` 自适应图标），因为 Android 的自适应
图标由启动器决定遮罩形状，应用管不了；要"由应用决定圆角矩形还是圆形"就只能自己把形状画进图里，
再用 `AndroidManifest.xml` 里的 `activity-alias` 切换（见 `MainActivity.kt` 的 `hobo/icon` 通道）。

用法：

    python tool/make_icons.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "assets" / "icon"
MASTER = ICON_DIR / "hobo_icon.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# Android 各密度下启动图标的边长。
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# 先按 4 倍画再缩小，边缘不会出现锯齿。
SUPERSAMPLE = 4

# 圆角矩形的超椭圆指数：4 接近 Material 的 squircle，再大就趋近方角。
SQUIRCLE_N = 4.0


def shape_mask(size: int, *, circle: bool) -> Image.Image:
    """硬边遮罩（0 / 255）。圆是正圆，圆角矩形是 |x|^n + |y|^n <= 1 的超椭圆。"""
    y, x = np.mgrid[0:size, 0:size]
    center = (size - 1) / 2
    radius = size / 2
    dx = (x - center) / radius
    dy = (y - center) / radius
    power = 2.0 if circle else SQUIRCLE_N
    inside = np.abs(dx) ** power + np.abs(dy) ** power <= 1.0
    return Image.fromarray((inside * 255).astype(np.uint8))


def masked_icon(master: Image.Image, size: int, *, circle: bool) -> Image.Image:
    """把母版缩到目标尺寸并套上形状遮罩。

    缩小前先预乘 alpha、缩小后再除回去，否则遮罩外的透明黑会顺着 LANCZOS 的负旁瓣
    渗进边缘，青色条带那侧能看到一圈发暗的毛边。
    """
    big = size * SUPERSAMPLE
    art = master.resize((big, big), Image.LANCZOS).convert("RGBA")
    alpha = np.asarray(shape_mask(big, circle=circle)).astype(np.float32) / 255.0

    pixels = np.asarray(art).astype(np.float32)
    pixels[..., 3] *= alpha
    pixels[..., :3] *= alpha[..., None]
    premultiplied = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))

    small = np.asarray(premultiplied.resize((size, size), Image.LANCZOS))
    out = small.astype(np.float32)
    ratio = out[..., 3] / 255.0
    out[..., :3] = np.divide(
        out[..., :3],
        ratio[..., None],
        out=np.zeros_like(out[..., :3]),
        where=ratio[..., None] > 0,
    )
    out[..., 3] = small[..., 3]
    return Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8))


def main() -> None:
    master = Image.open(MASTER).convert("RGBA")
    for folder, size in SIZES.items():
        target_dir = RES / folder
        target_dir.mkdir(parents=True, exist_ok=True)
        rounded = masked_icon(master, size, circle=False)
        circle = masked_icon(master, size, circle=True)
        rounded.save(target_dir / "ic_launcher.png")
        circle.save(target_dir / "ic_launcher_round.png")
        print(f"wrote {folder}/ic_launcher.png + ic_launcher_round.png ({size}px)")

    # 应用内（关于页、设置页）直接读这张 512 的方图，按设置的形状在运行时裁切。
    store = master.resize((512, 512), Image.LANCZOS)
    store.save(ICON_DIR / "hobo_icon_512.png")
    print(f"wrote assets/icon/hobo_icon_512.png ({store.width}px)")


if __name__ == "__main__":
    main()
