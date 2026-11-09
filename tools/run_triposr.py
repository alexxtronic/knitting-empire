"""Make a character mesh from one cut-out picture with TripoSR (github.com/VAST-AI-Research/TripoSR).

    python -I tools/run_triposr.py TRIPOSR_SRC WEIGHTS_DIR OUT_DIR [--res 448] [--ratio 0.85] image.png ...

TRIPOSR_SRC is a clone of the TripoSR repo; WEIGHTS_DIR holds config.yaml and model.ckpt from
huggingface.co/stabilityai/TripoSR. Needs torch, transformers<4.50, omegaconf, einops, trimesh,
huggingface_hub, scikit-image and pillow (not rembg or torchmcubes: the pictures already have alpha,
and scikit-image does the marching cubes). Runs on the Mac GPU (MPS) in about a minute per picture.

For each image it writes OUT_DIR/<name>/input.png, nerf_XX.png previews, mesh.ply (TripoSR's frame)
and rig_ready.ply: the largest piece only, normals facing out, turned to face -Y with +Z up, which is
what tools/rig_sculpt.py takes. TripoSR sees one picture, so use the front view of a turnaround.
"""
import os
import sys
import time
import types

import numpy as np
import torch
from PIL import Image

src, weights, out = sys.argv[1], sys.argv[2], sys.argv[3]
args = sys.argv[4:]
res, ratio = 448, 0.85
imgs = []
i = 0
while i < len(args):
    if args[i] == "--res":
        res = int(args[i + 1]); i += 2
    elif args[i] == "--ratio":
        ratio = float(args[i + 1]); i += 2
    else:
        imgs.append(args[i]); i += 1

# tsr.utils imports rembg at the top; our images already have alpha, so it is never called.
sys.modules["rembg"] = types.ModuleType("rembg")
# torchmcubes needs a C++ build; scikit-image's marching cubes does the same job on the CPU.
from skimage.measure import marching_cubes as _sk_mc  # noqa: E402

def _mc(vol, level):
    v, f, _, _ = _sk_mc(vol.cpu().numpy(), level=float(level))
    # torchmcubes returns coordinates last-axis first; TripoSR swaps them back
    return torch.from_numpy(np.ascontiguousarray(v[:, ::-1])).float(), torch.from_numpy(f.astype(np.int64))

tm = types.ModuleType("torchmcubes")
tm.marching_cubes = _mc
sys.modules["torchmcubes"] = tm

sys.path.insert(0, src)
from tsr.system import TSR  # noqa: E402
from tsr.utils import resize_foreground  # noqa: E402

device = "mps" if torch.backends.mps.is_available() else "cpu"
t0 = time.time()
model = TSR.from_pretrained(weights, config_name="config.yaml", weight_name="model.ckpt")
model.renderer.set_chunk_size(8192)
model.to(device)
print(f"model on {device} in {time.time() - t0:.1f}s", flush=True)

for p in imgs:
    name = os.path.splitext(os.path.basename(p))[0]
    od = os.path.join(out, name)
    os.makedirs(od, exist_ok=True)
    im = resize_foreground(Image.open(p).convert("RGBA"), ratio)
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb = a[:, :, :3] * a[:, :, 3:4] + (1 - a[:, :, 3:4]) * 0.5
    image = Image.fromarray((rgb * 255).astype(np.uint8))
    image.save(os.path.join(od, "input.png"))
    t0 = time.time()
    with torch.no_grad():
        codes = model([image], device=device)
    t1 = time.time()
    meshes = model.extract_mesh(codes, True, resolution=res)
    m = meshes[0]
    m.export(os.path.join(od, "mesh.ply"))
    # for tools/rig_sculpt.py: drop floaters, fix the winding (scikit-image's faces point inward),
    # and turn her from facing +X (TripoSR's camera) to facing -Y
    import trimesh
    part = max(m.split(only_watertight=False), key=lambda p: len(p.faces))
    if part.volume < 0:
        part.invert()
    part.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [0, 0, 1]))
    part.export(os.path.join(od, "rig_ready.ply"))
    t2 = time.time()
    with torch.no_grad():
        renders = model.render(codes, n_views=4, return_type="pil")
    for k, r in enumerate(renders[0]):
        r.save(os.path.join(od, f"nerf_{k:02d}.png"))
    print(f"{name}: model {t1 - t0:.1f}s, mesh {t2 - t1:.1f}s ({len(m.vertices)} verts, {len(m.faces)} faces), "
          f"bounds {np.round(m.bounds, 3).tolist()}", flush=True)
