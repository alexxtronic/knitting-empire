"""Split a Tripo lineup of people (several characters standing in a row, one export) into one GLB per person.

    Blender --background --factory-startup --python-exit-code 1 --python tools/split_people.py -- \
        <lineup.glb> <out_dir> <id> [<id> ...]

The townsfolk (2026-11-17) came as two exports of four people each, standing side by side in an A-pose,
facing the picture. The export is one mesh, and where two people's hands touch it is one piece. This script:
  1. imports it and welds it (Tripo splits it along its UV seams);
  2. finds the people: the feet seen from above (the lowest tenth of the lineup) fall into as many groups
     as ids were given, left to right as Blender's front view shows them (-X to +X);
  3. gives each connected piece to the person it stands over; a piece that stands over two people (hands
     touching) is cut where it is thinnest between them, which is where the fingertips meet;
  4. writes <out_dir>/<id>.glb for each, with Tripo's own UVs and textures (the atlas is shared: each
     person uses about a quarter of it), centred over its feet, feet on the ground, facing -Y as tripo.ai
     exports always face, at the lineup's own scale (tools/rig_sculpt.py scales it to the rig);
  5. renders a front view of each to <out_dir>/<id>_front.png.
The source exports stay in Alex's Downloads (and Desktop/Knitting Game/townsfolk), not the repo.
"""
import heapq
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector, kdtree

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, IDS = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2:]
os.makedirs(OUT, exist_ok=True)


def log(*a):
    print("[split_people]", *a, flush=True)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
src = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
for o in bpy.data.objects:
    o.select_set(o == src)
bpy.context.view_layer.objects.active = src
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

bm = bmesh.new()
bm.from_mesh(src.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
co = np.array([v.co[:] for v in bm.verts])
z0, z1 = co[:, 2].min(), co[:, 2].max()
NEAR = 0.025 * (z1 - z0)  # 'near where the hands touch', about 4 cm on a grown-up

# each point's colour, from the base-colour texture at its UVs (to tell two people's hands apart)
img = next(i for i in bpy.data.images if "basecolor" in i.name.lower() or "base" in i.name.lower())
iw, ih = img.size
tex = np.empty(iw * ih * 4, dtype=np.float32)
img.pixels.foreach_get(tex)
tex = tex.reshape(ih, iw, 4)[..., :3]
uvl = bm.loops.layers.uv.active
uvsum = np.zeros((len(bm.verts), 2))
uvn = np.zeros(len(bm.verts))
for f in bm.faces:
    for lp in f.loops:
        uvsum[lp.vert.index] += lp[uvl].uv[:]
        uvn[lp.vert.index] += 1
uv = uvsum / np.maximum(uvn, 1)[:, None]
rgb = tex[np.clip((uv[:, 1] % 1.0 * ih).astype(int), 0, ih - 1), np.clip((uv[:, 0] % 1.0 * iw).astype(int), 0, iw - 1)]

# --- the people: k-means on the feet's x, started at even quantiles
feet = co[co[:, 2] < z0 + 0.1 * (z1 - z0), 0]
centres = np.quantile(feet, (np.arange(len(IDS)) + 0.5) / len(IDS))
for _ in range(50):
    lab = np.argmin(np.abs(feet[:, None] - centres[None, :]), axis=1)
    centres = np.array([feet[lab == k].mean() if (lab == k).any() else centres[k] for k in range(len(IDS))])
centres.sort()
log("people at x", np.round(centres, 3))

# --- connected pieces
comp = np.full(len(bm.verts), -1)
n = 0
for v in bm.verts:
    if comp[v.index] >= 0:
        continue
    st = [v]
    comp[v.index] = n
    while st:
        x = st.pop()
        for e in x.link_edges:
            y = e.other_vert(x)
            if comp[y.index] < 0:
                comp[y.index] = n
                st.append(y)
    n += 1
log("pieces", n)

owner = np.zeros(len(bm.verts), dtype=int)
for c in range(n):
    idx = np.where(comp == c)[0]
    p = co[idx]
    low = p[p[:, 2] < z0 + 0.1 * (z1 - z0), 0]
    if len(low) == 0:  # a piece off the ground (an earring, a hat brim): whoever's feet are nearest
        owner[idx] = int(np.argmin(np.abs(centres - p[:, 0].mean())))
        continue
    stands = sorted(set(np.argmin(np.abs(low[:, None] - centres[None, :]), axis=1).tolist()))
    if len(stands) == 1:
        owner[idx] = stands[0]
        continue
    # hands touching: each point goes to whoever's chest it is nearer along the surface (Dijkstra from
    # both people's breastbones at once, each in units of their own height, so a short child's arm and a
    # tall man's arm meet at the fingertips), so the line falls where the two hands meet, not at a wrist
    dist = {}
    heap = []
    tall = {}
    for k in stands:
        mine = idx[np.abs(co[idx, 0] - centres[k]) < 0.04]
        tall[k] = co[mine, 2].max() - z0
        chest = mine[(co[mine, 2] - z0 > 0.6 * tall[k]) & (co[mine, 2] - z0 < 0.7 * tall[k]) & (np.abs(co[mine, 0] - centres[k]) < 0.015)]
        for i in chest:
            dist[int(i)] = 0.0
            owner[i] = k
            heap.append((0.0, int(i), k))
    heapq.heapify(heap)
    while heap:
        d, i, k = heapq.heappop(heap)
        if d > dist.get(i, 1e9):
            continue
        for e in bm.verts[i].link_edges:
            j = e.other_vert(bm.verts[i]).index
            nd = d + e.calc_length() / tall[k]
            if nd < dist.get(j, 1e9):
                dist[j] = nd
                owner[j] = k
                heapq.heappush(heap, (nd, j, k))
    # one hand lies over the other's fingers, so near where they meet the surface can't tell them apart: there
    # each point goes to the one whose skin it is (the colour of their free hand, the one touching nobody)
    for a, b in zip(stands[:-1], stands[1:]):
        pa, pb = idx[owner[idx] == a], idx[owner[idx] == b]
        a_reach = centres[a] - co[pa, 0].min()  # a's free hand is on a's far side from b
        b_reach = co[pb, 0].max() - centres[b]
        ref_a = rgb[pa[co[pa, 0] < centres[a] - 0.85 * a_reach]].mean(0)
        ref_b = rgb[pb[co[pb, 0] > centres[b] + 0.85 * b_reach]].mean(0)
        # the hands' zone: from the inside of a's reach to the inside of b's; skin-coloured points there go by colour
        lo_x, hi_x = centres[a] + 0.55 * a_reach, centres[b] - 0.55 * b_reach
        pab = idx[(co[idx, 0] > lo_x) & (co[idx, 0] < hi_x)]
        da = np.sum((rgb[pab] - ref_a) ** 2, axis=1)
        db = np.sum((rgb[pab] - ref_b) ** 2, axis=1)
        skin = np.minimum(da, db) < 0.1  # skin, lit or in shade; a sleeve is much further from both
        want = np.where(da < db, a, b)
        near = pab[skin]
        moved = int((owner[near] != want[skin]).sum())
        owner[near] = want[skin]
        # then the odd speck: a small island of one person inside the other's hand goes to the other
        for k, other in ((a, b), (b, a)):
            mine = set(idx[owner[idx] == k].tolist())
            seen_ = set()
            for i0 in mine:
                if i0 in seen_:
                    continue
                isl = [i0]
                seen_.add(i0)
                q = [i0]
                while q:
                    x_ = q.pop()
                    for e in bm.verts[x_].link_edges:
                        y_ = e.other_vert(bm.verts[x_]).index
                        if y_ in mine and y_ not in seen_:
                            seen_.add(y_)
                            isl.append(y_)
                            q.append(y_)
                if len(isl) < 0.05 * len(mine):
                    owner[isl] = other
                    moved += len(isl)
        log("  hands meet: skin", np.round(ref_a, 2), "and", np.round(ref_b, 2), "-", len(near), "points near the touch,", moved, "moved by colour")
    log("piece", c, "stands over", stands, "split along the surface:", [int((owner[idx] == k).sum()) for k in stands])

# --- one object per person
fo = np.array([owner[f.verts[0].index] for f in bm.faces])
src.data.clear_geometry()
bm.to_mesh(src.data)
bm.free()
for k, pid in enumerate(IDS):
    ob = src.copy()
    ob.data = src.data.copy()
    ob.name = ob.data.name = pid
    bpy.context.scene.collection.objects.link(ob)
    b2 = bmesh.new()
    b2.from_mesh(ob.data)
    b2.faces.ensure_lookup_table()
    bmesh.ops.delete(b2, geom=[f for f in b2.faces if fo[f.index] != k], context="FACES")
    bmesh.ops.delete(b2, geom=[v for v in b2.verts if not v.link_faces], context="VERTS")
    # crumbs of the neighbour's fingers that came away on their own: under 1% of the person, gone
    b2.verts.ensure_lookup_table()
    left = set(range(len(b2.verts)))
    crumbs = []
    while left:
        st = [left.pop()]
        isl = list(st)
        while st:
            x = b2.verts[st.pop()]
            for e in x.link_edges:
                y = e.other_vert(x).index
                if y in left:
                    left.discard(y)
                    st.append(y)
                    isl.append(y)
        if len(isl) < 0.01 * len(b2.verts):
            crumbs += isl
    bmesh.ops.delete(b2, geom=[b2.verts[i] for i in crumbs], context="VERTS")
    P = np.array([v.co[:] for v in b2.verts])
    pz0 = P[:, 2].min()
    base = P[P[:, 2] < pz0 + 0.1 * (P[:, 2].max() - pz0)]
    shift = Vector((-base[:, 0].mean(), -base[:, 1].mean(), -pz0))
    for v in b2.verts:
        v.co += shift
    b2.to_mesh(ob.data)
    b2.free()
    log(pid, "points", len(ob.data.vertices), "height", round(P[:, 2].max() - pz0, 4))
bpy.data.objects.remove(src)

scene = bpy.context.scene
for o in list(scene.collection.objects):
    if o.type != "MESH":
        continue
    for x in scene.collection.objects:
        x.select_set(x == o)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, o.name + ".glb"), use_selection=True, export_format="GLB")
    # a front view to look at
    hide = [x for x in scene.collection.objects if x.type == "MESH" and x != o]
    for x in hide:
        x.hide_render = True
    h = max((o.matrix_world @ Vector(c)).z for c in o.bound_box)
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = h * 1.15
    co_ = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(co_)
    co_.location = (0, -3, h / 2)
    co_.rotation_euler = (1.5708, 0, 0)
    scene.camera = co_
    scene.render.resolution_x = scene.render.resolution_y = 800
    if scene.world is None:
        scene.world = bpy.data.worlds.new("w")
        scene.world.use_nodes = True
        scene.world.node_tree.nodes["Background"].inputs[1].default_value = 3.0
    scene.render.filepath = os.path.join(OUT, o.name + "_front.png")
    bpy.ops.render.render(write_still=True)
    for x in hide:
        x.hide_render = False
    bpy.data.objects.remove(co_)
log("done")
