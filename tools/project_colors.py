"""Paint an image-to-sculpt mesh with the colours of its reference views.

    python -I project_colors.py I2S_SCRIPTS_DIR CASE_DIR OUT.ply [smooth_iters]

Takes the newest mesh in CASE/build/steps, lightly Taubin-smooths it (silhouette-only fits are rippled),
then colours every vertex from the view that sees it most squarely (z-buffer visibility, weight =
facing^12, the front photo counted double). Vertices no view sees take their neighbours' colour.
Writes a binary PLY with per-vertex colour, in the case's world frame (+Z up, subject faces -Y).
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, sys.argv[1])
from i2s import geom  # noqa: E402

case = sys.argv[2]
out = sys.argv[3]
iters = int(sys.argv[4]) if len(sys.argv) > 4 else 12

steps = sorted(glob.glob(os.path.join(case, "build", "steps", "*.npz")))
d = np.load(steps[-1])
V, F = d["verts"].astype(np.float64), d["faces"].astype(np.int64)
print("mesh", os.path.basename(steps[-1]), len(V), "verts", len(F), "faces")

E = geom.edges_of(F)
A, deg = geom.adjacency(E, len(V))
if iters:
    V = geom.taubin(V, A, deg, it=iters)
VN = geom.vertex_normals(V, F)

cfg = json.load(open(os.path.join(case, "case.json")))
W, H = cfg["work"]["size"]
center = np.array(cfg["front"]["center"])
K = tuple(cfg["front"]["K"])

views = [("front", {}, os.path.join(case, "ref", "front.png"), os.path.join(case, "ref", "front_mask.png"), 2.0)]
for name, v in cfg["views"].items():
    # a view that registered close to the front would paint a second, offset face over the photo's
    if v.get("role") == "rejected" or abs(((v["params"].get("az", 0) + 180) % 360) - 180) < 30:
        print(f"  {name:8s} skipped (az {v['params'].get('az', 0):.0f})")
        continue
    views.append((name, v["params"], os.path.join(case, "views", name + ".png"),
                  os.path.join(case, "views", name + "_mask.png"), 1.0))

acc = np.zeros((len(V), 3))
wsum = np.zeros(len(V))
best = np.zeros(len(V))
for name, params, img_p, mask_p, boost in views:
    cam = geom.make_cam(params, center, K)
    img = np.asarray(Image.open(img_p).convert("RGB").resize((W, H), Image.LANCZOS), np.float64) / 255.0
    mask = np.asarray(Image.open(mask_p).convert("L").resize((W, H)), np.float64) / 255.0
    r = geom.raster(V, F, cam, W, H)
    u, v, z = geom.project(V, cam)
    ui = np.clip(np.floor(u).astype(int), 0, W - 1)
    vi = np.clip(np.floor(v).astype(int), 0, H - 1)
    inside = (u >= 0) & (u < W) & (v >= 0) & (v < H)
    zbuf = r["depth"][vi, ui]
    vis = inside & (z <= zbuf + 0.004)
    to_cam = geom.unit(cam["p"] - V)
    facing = np.clip((VN * to_cam).sum(1), 0, 1)
    m = geom.sample(mask, u, v)
    w = boost * facing ** 12 * vis * np.clip((m - 0.5) * 4, 0, 1)
    col = geom.sample(img, u, v)
    acc += col * w[:, None]
    wsum += w
    best = np.maximum(best, w)
    print(f"  {name:8s} sees {int((w > 1e-3).sum())} verts")

C = np.where(wsum[:, None] > 1e-6, acc / np.maximum(wsum, 1e-9)[:, None], 0.0)
# The side views are all on one side: where a vertex is seen poorly but its mirror image across the
# subject's centre plane is seen well, take the mirror's colour (the outfit is near-symmetric).
from scipy.spatial import cKDTree  # noqa: E402
Vm = V.copy()
Vm[:, 0] = 2 * center[0] - Vm[:, 0]
dist, j = cKDTree(V).query(Vm)
take = (best < 0.25) & (best[j] > 2 * best + 0.1) & (dist < 0.02)
C[take] = C[j[take]]
wsum[take] = np.maximum(wsum[take], wsum[j[take]])
print("mirrored", int(take.sum()), "verts")
known = wsum > 1e-4
print("unseen verts", int((~known).sum()))
# fill unseen vertices by diffusing from their neighbours
for _ in range(200):
    if known.all():
        break
    s = A @ (C * known[:, None])
    n = A @ known.astype(np.float64)
    fill = (~known) & (n > 0)
    C[fill] = s[fill] / n[fill][:, None]
    known = known | fill

rgb = np.clip(np.round(C * 255), 0, 255).astype(np.uint8)
with open(out, "wb") as f:
    f.write(("ply\nformat binary_little_endian 1.0\n"
             f"element vertex {len(V)}\nproperty float x\nproperty float y\nproperty float z\n"
             "property uchar red\nproperty uchar green\nproperty uchar blue\n"
             f"element face {len(F)}\nproperty list uchar int vertex_indices\nend_header\n").encode())
    vt = np.zeros(len(V), dtype=[("p", "<f4", 3), ("c", "u1", 3)])
    vt["p"] = V
    vt["c"] = rgb
    f.write(vt.tobytes())
    ft = np.zeros(len(F), dtype=[("n", "u1"), ("i", "<i4", 3)])
    ft["n"] = 3
    ft["i"] = F
    f.write(ft.tobytes())
print("wrote", out, "height", round(float(V[:, 2].max() - V[:, 2].min()), 3))
