#!/usr/bin/env python3
"""Cut character turnaround views out of a plain white background, for image-to-sculpt.

    python3 tools/cutout_views.py OUT_DIR NAME front.png:000_front side.png:090_side ...

Each INPUT:LABEL pair becomes OUT_DIR/NAME_LABEL.png: a transparent PNG, the figure centred on a
square canvas. Put the approximate yaw first in the label (000 front, 090 side, 180 back);
image-to-sculpt finds the exact cameras itself. Needs Pillow only.

The background is everything near-white that touches the image border, plus any enclosed
near-pure-white patch of 25+ pixels (gaps between legs, between strands of hair). Cream or pale
clothing survives because it's either not connected to the border or not pure white.
"""
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


def _flood(px, w, h, seeds, test):
    """Pixels reachable from seeds through pixels where test(p) holds."""
    hit = bytearray(w * h)
    q = deque(seeds)
    while q:
        x, y = q.popleft()
        i = y * w + x
        if hit[i] or not test(px[x, y]):
            continue
        hit[i] = 1
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not hit[ny * w + nx]:
                q.append((nx, ny))
    return hit


def cut_out(src: Path) -> Image.Image:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()

    def near_white(p):
        return min(p) >= 226 and max(p) - min(p) < 22

    def pure_white(p):
        return min(p) >= 238 and max(p) - min(p) < 12

    border = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
    border += [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    bg = _flood(px, w, h, border, near_white)

    # enclosed pure-white patches
    seen = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if bg[i] or seen[i] or not pure_white(px[x, y]):
                continue
            comp = []
            q = deque([(x, y)])
            seen[i] = 1
            while q:
                cx, cy = q.popleft()
                comp.append(cy * w + cx)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    j = ny * w + nx
                    if 0 <= nx < w and 0 <= ny < h and not seen[j] and not bg[j] and pure_white(px[nx, ny]):
                        seen[j] = 1
                        q.append((nx, ny))
            if len(comp) >= 25:
                for j in comp:
                    bg[j] = 1

    alpha = Image.frombytes("L", (w, h), bytes(0 if b else 255 for b in bg))
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    rgba = im.convert("RGBA")
    rgba.putalpha(alpha)
    l, t, r, b = alpha.getbbox()
    pad = 16
    rgba = rgba.crop((max(0, l - pad), max(0, t - pad), min(w, r + pad), min(h, b + pad)))
    side = max(rgba.size) + 40
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(rgba, ((side - rgba.width) // 2, (side - rgba.height) // 2), rgba)
    return sq


def main() -> None:
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    name = sys.argv[2]
    out.mkdir(parents=True, exist_ok=True)
    tiles = []
    for pair in sys.argv[3:]:
        src, label = pair.rsplit(":", 1)
        img = cut_out(Path(src))
        dest = out / f"{name}_{label}.png"
        img.save(dest)
        tiles.append(img)
        print(f"{dest}  {img.width}x{img.height}")
    # a contact sheet on green, to check the edges
    th = 600
    tiles = [t.resize((round(t.width * th / t.height), th)) for t in tiles]
    sheet = Image.new("RGB", (sum(t.width for t in tiles), th), (60, 140, 90))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0), t)
        x += t.width
    sheet.save(out / f"{name}_check.png")


if __name__ == "__main__":
    main()
