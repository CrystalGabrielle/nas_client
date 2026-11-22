"""Copy golden screenshots into docs/screenshots at README-friendly sizes.

Prerequisites:
    flutter test --update-goldens test/docs_screenshots_test.dart

The golden images are rendered entirely from synthetic data (no real accounts,
no real IPs, no real files), so the resulting screenshots are safe to publish.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tool" / "goldens"
DST = ROOT / "docs" / "screenshots"

SHOTS = [
    ("screenshot_home.png", "01-home.png"),
    ("screenshot_browser.png", "02-browser.png"),
]


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for src_name, dst_name in SHOTS:
        src = SRC / src_name
        if not src.exists():
            raise SystemExit(f"missing golden: {src}")
        img = Image.open(src).convert("RGB")
        # Golden renders at 3x device pixel ratio; scale down for docs.
        out = img.resize((img.width // 3, img.height // 3), Image.LANCZOS)
        path = DST / dst_name
        out.save(path, "PNG", optimize=True)
        print(f"{dst_name}: {out.size[0]}x{out.size[1]} {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
