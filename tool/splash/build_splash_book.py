"""Builds the frame strips of the native splash (native/splash/splash_book_*.png), shared by the
Windows and Linux runners.

Source: the 24 book-opening frames of the download assistant art (`book_00_250.png`..`book_23_250.png`),
the release pinned in installer/assistant_art.pin.json, or `download-assistant/out` of otzaria-design.

Each strip stacks the frames vertically, one per DPI bucket, so the native splash decodes only the size
it shows and can decode frame by frame from the top (PNG rows are sequential).

    python tool/splash/build_splash_book.py <dir with book_NN_250.png>
"""

import sys
from pathlib import Path

from PIL import Image

FRAMES = 24
# Logical frame size that keeps the open book at the size of the old static icon (160px for the
# whole 1024px iconnew.png): the logo is 176 of the frame's 220 units.
LOGICAL = 177
SCALES = {100: 1.0, 150: 1.5, 200: 2.0}
OUT = Path(__file__).resolve().parents[2] / "native" / "splash"


def main() -> None:
    src = Path(sys.argv[1])
    frames = [Image.open(src / f"book_{i:02d}_250.png").convert("RGBA") for i in range(FRAMES)]
    for name, scale in SCALES.items():
        side = round(LOGICAL * scale)
        strip = Image.new("RGBA", (side, side * FRAMES))
        for i, frame in enumerate(frames):
            strip.paste(frame.resize((side, side), Image.LANCZOS), (0, i * side))
        # Fully transparent pixels carry no colour; zeroing them only helps compression.
        alpha = strip.getchannel("A")
        clear = Image.new("RGBA", strip.size)
        strip = Image.composite(strip, clear, alpha.point(lambda a: 255 if a else 0))
        path = OUT / f"splash_book_{name}.png"
        strip.save(path, optimize=True)
        print(f"{path.name}: {side}px x {FRAMES}, {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
