"""Bring a generated model (Tripo, image-to-sculpt, a store asset) into the game in the Woolcore style.

Run headless:
  Blender -b --factory-startup -P tools/import_asset.py -- <project_dir> <model.glb|.gltf|.obj|.fbx> <id>
          [--height 1.0 | --fit W,D] [--yaw 0] [--faces 4000] [--colors 5] [--keep-colors]
          [--render out.png]

What it does, in order:
  1. imports the file, keeps only meshes, joins them and applies their transforms;
  2. turns it --yaw degrees, then scales it to --height metres (or to fit a W x D footprint), centres it
     on its footprint and puts its base on the floor (it faces +Z in Godot, -Y here, like every model);
  3. reads each face's colour (texture under its UVs, else the material colour), groups the colours into
     --colors clusters and snaps every cluster to the nearest colour in data/palette.json, so the model
     uses the same colours as everything else (--keep-colors keeps the cluster colours instead), then
     decimates it to a --faces budget;
  4. gives each cluster a flat material named wool_<palette id> (Godot swaps in the Woolcore felt/knit
     shader by that name: Catalog.model in scripts/catalog.gd), drops the textures and exports
     assets/props/<id>.glb. Prints a report; --render writes a preview.
"""
import bpy, bmesh, json, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, SRC, ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


HEIGHT = float(opt("--height")) if opt("--height") else None
FIT = [float(x) for x in opt("--fit").split(",")] if opt("--fit") else None
YAW = float(opt("--yaw", 0))
FACES = int(opt("--faces", 4000))
NCOL = int(opt("--colors", 5))
KEEP = "--keep-colors" in argv
RENDER = opt("--render")

# ----------------------------------------------------------------------------- 1. import
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
ext = os.path.splitext(SRC)[1].lower()
if ext in (".glb", ".gltf"):
    bpy.ops.import_scene.gltf(filepath=SRC)
elif ext == ".obj":
    bpy.ops.wm.obj_import(filepath=SRC)
elif ext == ".fbx":
    bpy.ops.import_scene.fbx(filepath=SRC)
else:
    raise SystemExit(f"can't import {ext} files")
scene = bpy.context.scene
for o in list(scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)
meshes = [o for o in scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("no meshes in " + SRC)
for o in meshes:
    o.data = o.data.copy()  # instanced data would be transformed twice
    o.data.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
obj.name = obj.data.name = ID
src_faces = len(obj.data.polygons)
# glTF and most generators split vertices along texture seams; weld them, or decimation tears holes
bm = bmesh.new()
bm.from_mesh(obj.data)
diag = (Vector(max(v.co[i] for v in bm.verts) for i in range(3)) - Vector(min(v.co[i] for v in bm.verts) for i in range(3))).length
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=diag * 1e-5)
bm.to_mesh(obj.data)
bm.free()

# ----------------------------------------------------------------------------- 2. orient and size
obj.data.transform(Matrix.Rotation(math.radians(YAW), 4, "Z"))
V = np.array([v.co[:] for v in obj.data.vertices])
lo, hi = V.min(0), V.max(0)
size = hi - lo
if HEIGHT:
    s = HEIGHT / max(size[2], 1e-6)
elif FIT:
    s = min(FIT[0] / max(size[0], 1e-6), FIT[1] / max(size[1], 1e-6))
else:
    s = 1.0
c = (lo + hi) / 2
obj.data.transform(Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation((-c[0], -c[1], -lo[2])))
obj.data.update()

# ----------------------------------------------------------------------------- 3. colours
def srgb_to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, float), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def to_lab(srgb):
    """sRGB (0..1) -> CIELAB, for colour distances that match what eyes see"""
    lin = srgb_to_lin(srgb)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = lin @ M.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def material_source(mat):
    """-> (pixels HxWx4 sRGB or None, base colour sRGB)"""
    base = np.array([0.8, 0.8, 0.8])
    if mat is None or not mat.use_nodes:
        return None, base if mat is None else lin_to_srgb(mat.diffuse_color[:3])
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return None, base
    inp = bsdf.inputs["Base Color"]
    base = lin_to_srgb(inp.default_value[:3])
    stack = [l.from_node for l in inp.links]
    while stack:
        n = stack.pop()
        if n.type == "TEX_IMAGE" and n.image is not None and n.image.size[0] > 0:
            w, h = n.image.size
            px = np.array(n.image.pixels[:], np.float32).reshape(h, w, 4)
            if n.image.colorspace_settings.name != "sRGB" or n.image.is_float:
                px[..., :3] = lin_to_srgb(px[..., :3])
            return px, base
        stack += [l.from_node for i in n.inputs for l in i.links]
    return None, base


me = obj.data
sources = [material_source(m) for m in me.materials] or [(None, np.array([0.8, 0.8, 0.8]))]
uv = me.uv_layers.active
nf = len(me.polygons)
cols = np.zeros((nf, 3))
area = np.array([p.area for p in me.polygons])
for p in me.polygons:
    px, base = sources[min(p.material_index, len(sources) - 1)]
    if px is None or uv is None:
        cols[p.index] = base
        continue
    h, w = px.shape[:2]
    pts = [uv.data[li].uv for li in p.loop_indices]
    cen = sum(pts, Vector((0, 0))) / len(pts)
    acc = np.zeros(3)
    for q in pts + [cen, cen]:  # corners and (twice) the centre
        x = int((q.x % 1.0) * (w - 1))
        y = int((q.y % 1.0) * (h - 1))
        acc += px[y, x, :3]
    cols[p.index] = acc / (len(pts) + 2)

lab = to_lab(cols)
# k-means (k-means++ seeding) on face colours, weighted by face area
rng = np.random.default_rng(1)
k = max(1, min(NCOL, nf))
cent = [lab[rng.choice(nf, p=area / area.sum())]]
for _ in range(k - 1):
    d = np.min([((lab - c) ** 2).sum(1) for c in cent], 0) * area
    cent.append(lab[rng.choice(nf, p=d / d.sum())] if d.sum() > 0 else lab[rng.integers(nf)])
cent = np.array(cent)
for _ in range(25):
    lbl = np.argmin(((lab[:, None] - cent[None]) ** 2).sum(-1), 1)
    for j in range(k):
        m = lbl == j
        if m.any():
            cent[j] = (lab[m] * area[m, None]).sum(0) / area[m].sum()
# clean up speckle (texture noise, stray faces): each face takes the area-weighted majority label of
# itself and its edge neighbours, twice
bm = bmesh.new()
bm.from_mesh(me)
nbrs = [[f.index] + [g.index for e in f.edges for g in e.link_faces if g is not f] for f in bm.faces]
bm.free()
for _ in range(2):
    new = lbl.copy()
    for i, nb in enumerate(nbrs):
        votes = np.bincount(lbl[nb], weights=area[nb], minlength=k)
        new[i] = int(np.argmax(votes))
    lbl = new
srgb_cent = np.array([(cols[lbl == j] * area[lbl == j, None]).sum(0) / max(area[lbl == j].sum(), 1e-9) for j in range(k)])

pal = json.load(open(os.path.join(PROJECT, "data", "palette.json")))["colors"]
pal_srgb = np.array([[int(e["hex"][i:i + 2], 16) / 255 for i in (1, 3, 5)] for e in pal])
pal_lab = to_lab(pal_srgb)

# ----------------------------------------------------------------------------- 4. flat materials, export
me.materials.clear()
names = {}
report = []
for j in range(k):
    share = area[lbl == j].sum() / area.sum()
    if share == 0:
        continue
    d = np.sqrt(((pal_lab - cent[j]) ** 2).sum(1))
    pi = int(np.argmin(d))
    if KEEP:
        name, rgb = f"wool_custom_{j}", srgb_cent[j]
    else:
        name, rgb = "wool_" + pal[pi]["id"], pal_srgb[pi]
    if name not in names:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*srgb_to_lin(rgb), 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
        me.materials.append(m)
        names[name] = len(me.materials) - 1
    for p in me.polygons:
        if lbl[p.index] == j:
            p.material_index = names[name]
    report.append((share, "#%02x%02x%02x" % tuple(int(round(x * 255)) for x in srgb_cent[j]), name, d[pi]))

for o in scene.objects:
    o.select_set(o == obj)
bpy.context.view_layer.objects.active = obj
# ----------------------------------------------------------------------------- polygon budget (after the
# colours are chosen on the full-detail mesh; decimation keeps each face's material)
if len(obj.data.polygons) > FACES:
    dec = obj.modifiers.new("dec", "DECIMATE")
    dec.ratio = FACES / len(obj.data.polygons)
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
try:
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
except Exception:
    bpy.ops.object.shade_flat()
for img in list(bpy.data.images):
    bpy.data.images.remove(img)

out_dir = os.path.join(PROJECT, "assets", "props")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, ID + ".glb")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                          export_yup=True, export_cameras=False, export_lights=False, export_animations=False)
V = np.array([v.co[:] for v in obj.data.vertices])
dims = V.max(0) - V.min(0)
print(f"IMPORTED {ID}: {src_faces} -> {len(obj.data.polygons)} faces, "
      f"{dims[0]:.2f} wide x {dims[1]:.2f} deep x {dims[2]:.2f} tall (m) -> {out}")
for share, src_hex, name, dist in sorted(report, reverse=True):
    print(f"  {share * 100:5.1f}%  {src_hex} -> {name}  (colour distance {dist:.0f})")

if RENDER:
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 512
    w = bpy.data.worlds.new("w")
    scene.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.62, 0.58, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(45), 0, math.radians(35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    r = max(dims) * 1.9
    cam.location = (r * 0.7, -r * 0.7, dims[2] * 0.5 + r * 0.45)
    look = Vector((0, 0, dims[2] * 0.45)) - cam.location
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.abspath(RENDER)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", RENDER)
