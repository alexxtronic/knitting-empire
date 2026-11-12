"""Flatten the board's face out of Alex's reference into a front-on texture (tex/board_face.png).

Alex, 2026-11-12: the words needn't be 3D; get them exactly like the reference. The board in
ref/welcome_sign_ref.png is close to front-on with a little perspective, so a four-point
(homography) warp straightens it. The four points are the ends of the cream border band where
it meets the posts: top edge of the top band and bottom edge of the bottom band, on each side.
They land at x = +-POST_IN, z = BAND_TOP / BAND_LOW in the model (metres, front view, x right, z up).

Run: uv run --no-project --with numpy --with pillow python make_face.py
"""
import os
import json
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
POST_IN = 0.88            # the posts' inner edges
BAND_LOW, BAND_TOP = 1.0, 1.76
XR = 1.0                  # the texture covers x -XR..XR
Z0, Z1 = 0.70, 2.38       # and z Z0..Z1
PPM = 800                 # texture pixels per metre
RIM = 0.03                # the wood showing outside the cream band
REF = {(-POST_IN, BAND_TOP): (334, 511), (POST_IN, BAND_TOP): (972, 487),
       (POST_IN, BAND_LOW): (972, 758), (-POST_IN, BAND_LOW): (324, 800)}
UP = 2                    # upscale the reference first so the warp resamples smoothly


def tex_px(x, z):
    return ((x + XR) * PPM, (Z1 - z) * PPM)


def homography(src, dst):
    """3x3 H with dst ~ H @ src (src, dst: four (x, y) pairs)."""
    A, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    h = np.linalg.solve(np.array(A, float), np.array(b, float))
    return np.append(h, 1).reshape(3, 3)


def main():
    ref = Image.open(os.path.join(HERE, "ref", "welcome_sign_ref.png")).convert("RGB")
    ref = ref.resize((ref.width * UP, ref.height * UP), Image.LANCZOS)
    src = [tex_px(*k) for k in REF]
    dst = [(u * UP, v * UP) for u, v in REF.values()]
    H = homography(src, dst)  # texture pixel -> reference pixel, what PIL's PERSPECTIVE wants
    w, h = round(2 * XR * PPM), round((Z1 - Z0) * PPM)
    face = ref.transform((w, h), Image.PERSPECTIVE, tuple(H.flatten()[:8]), Image.BICUBIC)
    os.makedirs(os.path.join(HERE, "tex"), exist_ok=True)
    face.save(os.path.join(HERE, "tex", "board_face_raw.png"))
    a = np.asarray(face).astype(float)

    # the posts cover the board's ends: carry the last clear column outwards so the bands run on
    # behind them, not into a picture of post and bolt
    edge = round((XR - 0.86) * PPM)
    a[:, :edge] = a[:, edge:edge + 1]
    a[:, w - edge:] = a[:, w - edge - 1:w - edge]

    # the board's outline: trace the cream border band's outer edge from outside the board (from
    # above, under the rafter scrolls; from below), then grow it outwards by the wood rim the
    # reference shows round the band. (Tracing the background picked up the board's back edge
    # and the far posts behind its shoulders.)
    rgb = np.asarray(face).astype(float)
    cream = (rgb[..., 1] > 200) & (rgb[..., 2] > 140) & (rgb[..., 0] - rgb[..., 2] > 25)  # the light wood has far less blue
    # and solid for 6 px down: the soft edge where the wood meets the white background passes the
    # colour test for a pixel or two
    solid = cream.copy()
    for k in range(1, 6):
        solid[:-k] &= cream[k:]
    cream = solid
    xs = np.linspace(-0.86, 0.86, 87)
    band_top, band_low = [], []
    for x in xs:
        i = int(round((x + XR) * PPM))
        col = cream[:, i - 1:i + 2].any(axis=1)
        j0 = int((Z1 - 2.26) * PPM)
        j1 = int((Z1 - 0.72) * PPM)
        hit = np.nonzero(col[j0:])[0]
        band_top.append(Z1 - (j0 + hit[0]) / PPM)
        hit = np.nonzero(col[:j1][::-1])[0]
        band_low.append(Z1 - (j1 - hit[0] + 5) / PPM)

    def smooth(v):
        v = np.asarray(v)
        return np.convolve(np.pad(v, 2, mode="edge"), np.ones(5) / 5, mode="valid")

    def grow(zs, sign):  # offset the polyline outwards (sign +1 up, -1 down) by RIM along its normal
        pts = np.column_stack((xs, smooth(zs)))
        t = np.gradient(pts, axis=0)
        t /= np.linalg.norm(t, axis=1, keepdims=True)
        n = np.column_stack((-t[:, 1], t[:, 0])) * sign
        q = pts + n * RIM
        return np.interp(xs, q[:, 0], q[:, 1])
    top = grow(band_top, 1)
    low = grow(band_low, -1)
    prof = {"x": [round(float(x), 4) for x in xs], "top": [round(float(z), 4) for z in top],
            "low": [round(float(z), 4) for z in low], "xr": XR, "z0": Z0, "z1": Z1}
    with open(os.path.join(HERE, "tex", "board_profile.json"), "w") as f:
        json.dump(prof, f, indent=1)

    Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(os.path.join(HERE, "tex", "board_face.png"))

    # a gentle relief so the cream work catches the game's light: the cream (warm, bright) raised
    cream = ((rgb[..., 0] > 200) & (rgb[..., 0] - rgb[..., 2] > 30)).astype(np.uint8) * 255
    hgt = np.asarray(Image.fromarray(cream).filter(ImageFilter.GaussianBlur(3))).astype(float) / 255
    gy, gx = np.gradient(hgt)
    k = 6.0
    n = np.dstack((-gx * k, gy * k, np.ones_like(hgt)))
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(HERE, "tex", "board_face_normal.png"))
    print("face", w, h, "top crown %.3f shoulder %.3f, bottom swag %.3f shoulder %.3f" % (top.max(), top[3], low.min(), low[3]))


if __name__ == "__main__":
    main()
