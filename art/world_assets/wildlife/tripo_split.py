"""Split a Tripo lineup (several animals in one export) into one source model per animal.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/wildlife/tripo_split.py -- <lineup.glb> <id> [<id> ...] [--rows N]

To save Tripo credits (Alex, 2026-11-14) each Tripo run makes five animals standing in a row, all
facing the picture's left (tripo/ref/lineup_N.png). The export is one mesh. This script:
  1. imports it and welds it (Tripo splits it along its UV seams);
  2. cuts it into animals (its largest connected pieces), left to right, named by the ids given in
     that order; with --rows N the picture was N rows of animals (the shorn sheet, Alex 2026-11-16:
     all nine in one picture, 3 x 3) and the ids go row by row from the top, each row left to right;
  3. turns each to face -Y (+Z in Godot), stands it on the ground with its origin under the middle of
     its body, and scales it to its height in the game (HEIGHTS, metres to the top of the ears);
  4. saves out_tripo/<id>/<id>_src.blend: the full-detail mesh with Tripo's own 4K textures, which
     tripo_build.py bakes from;
  5. renders a side, front, top and three-quarter view of each on a 5 cm grid (out_tripo/<id>/views/),
     to measure the joints from.
The source exports stay in Alex's Downloads, not the repo (each is about 18 MB).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:]
SRC = os.path.abspath(argv[0])
ROWS = int(argv[argv.index("--rows") + 1]) if "--rows" in argv else 1
IDS = [a for i, a in enumerate(argv[1:], 1) if not a.startswith("--") and argv[i - 1] != "--rows"]
OUT = os.path.join(HERE, "out_tripo")

# metres to the top of the ears (the old species.py units; the birds as birds.py made them)
HEIGHTS = {"rabbit": 0.42, "fox": 0.68, "raccoon": 0.42, "beaver": 0.38, "coyote": 0.76, "mink": 0.30,
           "sable": 0.34, "lynx": 0.90, "chinchilla": 0.32, "sparrow": 0.20, "robin": 0.20, "gull": 0.42,
           # the birds in flight, for their wings: tripo_birds.py scales each to its standing bird
           "sparrow_fly": 0.26, "gull_fly": 0.52}
# a shorn animal (<id>_shorn, the naked form shown after a comb) stands as tall as its furry self to
# the top of its ears, so its head and legs match at the swap; a factor here where they don't
SHORN_HEIGHT = {}


def height(sid):
    if sid in HEIGHTS:
        return HEIGHTS[sid]
    base = sid[:-len("_shorn")] if sid.endswith("_shorn") else sid
    return HEIGHTS[base] * SHORN_HEIGHT.get(base, 1.0)
BIRDS = ("sparrow", "robin", "gull")
YAW = {"raccoon": 15.0, "chinchilla": 90.0}  # degrees added to the measured turn, where the feet don't line up with the body
FLYING = ("sparrow_fly", "gull_fly")  # no feet to line up: only the quarter turn to face -Y


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_lineup():
    bpy.ops.import_scene.gltf(filepath=SRC)
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    assert len(obs) == 1, "expected one mesh in the export, found %d" % len(obs)
    ob = obs[0]
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix()
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(ob.data)
    print("IMPORTED %s: %d faces, %d -> %d vertices after welding" % (os.path.basename(SRC), len(bm.faces), before, len(bm.verts)))
    bm.free()
    return ob


def cut_points(ob, n):
    """The n-1 x positions to cut at: the middles of the widest empty runs along the row."""
    xs = [v.co.x for v in ob.data.vertices]
    lo, hi = min(xs), max(xs)
    bins = 4000
    occ = [False] * bins
    for x in xs:
        occ[min(bins - 1, int((x - lo) / (hi - lo) * bins))] = True
    runs, start = [], None
    for i, o in enumerate(occ + [True]):
        if not o and start is None:
            start = i
        elif o and start is not None:
            runs.append((i - start, start, i))
            start = None
    runs.sort(reverse=True)
    assert len(runs) >= n - 1, "only %d gaps along the row for %d animals" % (len(runs), n)
    cuts = sorted(lo + (a + b) / 2.0 / bins * (hi - lo) for _w, a, b in runs[:n - 1])
    widths = sorted(((b - a) / bins * (hi - lo) for _w, a, b in runs[:n - 1]))
    print("CUTS at x = %s (gaps %s wide; the next widest %.4f)" % (
        ", ".join("%.3f" % c for c in cuts), ", ".join("%.3f" % w for w in widths),
        (runs[n - 1][0] / bins * (hi - lo)) if len(runs) >= n else 0.0))
    return cuts


def pieces(ob, n):
    """Which animal each face belongs to: the n largest connected pieces are the animals (left to
    right); every smaller piece joins the animal it comes nearest to."""
    me = ob.data
    parent = list(range(len(me.vertices)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    comp_faces = {}
    for p in me.polygons:
        comp_faces.setdefault(find(p.vertices[0]), []).append(p.index)
    comps = sorted(comp_faces.items(), key=lambda kv: -len(kv[1]))
    big = comps[:n]
    sizes = [len(f) for _r, f in comps]
    print("PIECES %d connected pieces; the largest %s faces; the next %s" % (len(comps), sizes[:n], sizes[n:n + 5]))
    assert len(big) == n and len(big[-1][1]) > 2000, "fewer than %d animal-sized pieces" % n

    def centre(faces):
        c = Vector()
        for i in faces:
            c += me.polygons[i].center
        return c / len(faces)
    big.sort(key=lambda kv: centre(kv[1]).x)
    if ROWS > 1:  # rows of animals: Tripo puts the picture's rows one above another (z) or one behind another (y)
        cs = [centre(f) for _r, f in big]
        per = n // ROWS

        def rows_by(axis, top_first):
            order = sorted(range(n), key=lambda i: cs[i][axis], reverse=top_first)
            groups = [order[r * per:(r + 1) * per] for r in range(ROWS)]
            spread = max(max(cs[i][axis] for i in g) - min(cs[i][axis] for i in g) for g in groups)
            gap = min(abs(min(cs[i][axis] for i in groups[r]) - max(cs[i][axis] for i in groups[r + 1])) if top_first else
                      abs(min(cs[i][axis] for i in groups[r + 1]) - max(cs[i][axis] for i in groups[r])) for r in range(ROWS - 1))
            return gap / max(spread, 1e-6), groups
        qz, gz = rows_by(2, True)  # the top row highest
        qy, gy = rows_by(1, True)  # the top row furthest back
        groups = gz if qz >= qy else gy
        print("ROWS along %s (gap/spread: z %.2f, y %.2f)" % ("z" if qz >= qy else "y", qz, qy))
        big = [big[i] for g in groups for i in sorted(g, key=lambda i: cs[i].x)]
        for k, (_r, f) in enumerate(big):
            c = centre(f)
            print("  piece %d: %d faces at (%.3f, %.3f, %.3f)" % (k, len(f), c.x, c.y, c.z))
    from mathutils.kdtree import KDTree
    owner = {}
    trees = []
    for k, (_r, faces) in enumerate(big):
        for i in faces:
            owner[i] = k
        vs = {v for i in faces for v in me.polygons[i].vertices}
        t = KDTree(len(vs))
        for v in vs:
            t.insert(me.vertices[v].co, v)
        t.balance()
        trees.append(t)
    stray = 0
    for _r, faces in comps[n:]:
        c = centre(faces)
        k = min(range(n), key=lambda j: trees[j].find(c)[2])
        for i in faces:
            owner[i] = k
        stray += len(faces)
    print("PIECES %d faces in small pieces given to the nearest animal" % stray)
    return owner


def split(ob, n):
    """One object per animal."""
    owner = pieces(ob, n)
    parts = []
    for k in range(n):
        dup = ob.copy()
        dup.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(dup)
        bm = bmesh.new()
        bm.from_mesh(dup.data)
        bm.faces.ensure_lookup_table()
        gone = [f for f in bm.faces if owner[f.index] != k]
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bm.to_mesh(dup.data)
        bm.free()
        parts.append(dup)
    bpy.data.objects.remove(ob)
    return parts


def level(me, sid):
    """Tripo builds a three-quarter picture a little tilted (the shorn sheet's hind paws stood 1 to 2.5
    cm off the ground): turn it so the lowest points of its four paws lie level."""
    co = [v.co for v in me.vertices]
    z0, z1 = min(c.z for c in co), max(c.z for c in co)
    h = z1 - z0
    band = [c for c in co if c.z < z0 + 0.05 * h]
    mid = (min(c.y for c in band) + max(c.y for c in band)) / 2.0
    cx = (min(c.x for c in band) + max(c.x for c in band)) / 2.0  # it still stands where it was in the lineup
    pts = []
    for fx in (1, -1):
        for fy in (1, -1):
            q = [c for c in co if (c.x - cx) * fx > 0 and (c.y - mid) * fy > 0 and c.z < z0 + 0.12 * h]
            if q:
                pts.append(min(q, key=lambda c: c.z))
    if len(pts) < 4:
        return
    # the plane z = a x + b y + c through them, by least squares
    import numpy as np
    A = np.array([[c.x, c.y, 1.0] for c in pts])
    a, b, _c = np.linalg.lstsq(A, np.array([c.z for c in pts]), rcond=None)[0]
    n = Vector((-a, -b, 1.0)).normalized()
    tilt = math.degrees(n.angle(Vector((0, 0, 1))))
    print("LEVEL %s: its paws lay %.1f deg off level (%s)" % (sid, tilt, ", ".join("%.3f" % (c.z - z0) for c in pts)))
    if tilt > 0.3:
        me.transform(n.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4())


def stand(ob, sid):
    """Face -Y, feet on z=0, origin under the middle of the body, scaled to its height."""
    me = ob.data
    me.transform(Matrix.Rotation(math.radians(90), 4, "Z"))  # it faced -X (the picture's left)
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    # Drawn in three-quarter view, Tripo builds it turned that way: line its body up with Y. The body
    # runs along the long axis of where its feet stand (of the whole body for a bird, whose two feet
    # stand side by side); the head is the end nearer -Y.
    low = [v.co for v in me.vertices if v.co.z < z0 + (0.6 if sid in BIRDS else 0.05) * (z1 - z0)]
    mx = sum(c.x for c in low) / len(low)
    my = sum(c.y for c in low) / len(low)
    sxx = sum((c.x - mx) ** 2 for c in low)
    syy = sum((c.y - my) ** 2 for c in low)
    sxy = sum((c.x - mx) * (c.y - my) for c in low)
    ang = 0.5 * math.atan2(2 * sxy, sxx - syy)  # the long axis, from +X
    ax = Vector((math.cos(ang), math.sin(ang), 0))
    if ax.y > 0:
        ax = -ax  # pointing at the head (toward -Y)
    yaw = math.atan2(ax.x, -ax.y) + math.radians(YAW.get(sid, 0.0))  # how far it is turned from -Y
    if sid in FLYING:
        yaw = 0.0
    me.transform(Matrix.Rotation(-yaw, 4, "Z"))
    print("TURN %s: its body ran %.0f deg off the Y axis" % (sid, math.degrees(yaw)))
    if sid not in BIRDS and sid not in FLYING:
        level(me, sid)
        zs = [v.co.z for v in me.vertices]
        z0, z1 = min(zs), max(zs)
    s = height(sid) / (z1 - z0)
    ground = [v.co for v in me.vertices if v.co.z < z0 + 0.04 * (z1 - z0)]
    cx = (min(c.x for c in ground) + max(c.x for c in ground)) / 2.0
    cy = (min(c.y for c in ground) + max(c.y for c in ground)) / 2.0
    me.transform(Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-cx, -cy, -z0))))
    me.update()
    co = [v.co for v in me.vertices]
    size = Vector((max(c.x for c in co) - min(c.x for c in co), max(c.y for c in co) - min(c.y for c in co), max(c.z for c in co)))
    print("ANIMAL %s: %d faces, %.3f x %.3f x %.3f m (scaled x%.3f)" % (sid, len(me.polygons), size.x, size.y, size.z, s))
    return size


def views(ob, sid, size):
    """Orthographic views on a 5 cm grid, coloured by Tripo's texture."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 1200
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.color = (1, 1, 1)
    # grid: thin bars every 5 cm on the far side of each view
    grid = bpy.data.materials.new("grid")
    grid.diffuse_color = (0.55, 0.65, 0.85, 1)
    ext = max(size) * 0.75 + 0.1
    bars = []

    def bar(a, b, w):
        d = b - a
        cyl = bpy.data.meshes.new("bar")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bm.to_mesh(cyl)
        bm.free()
        o = bpy.data.objects.new("bar", cyl)
        o.data.materials.append(grid)
        o.location = (a + b) / 2
        o.scale = (max(abs(d.x), w), max(abs(d.y), w), max(abs(d.z), w))
        sc.collection.objects.link(o)
        bars.append(o)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2 * ext
    out = os.path.join(OUT, sid, "views")
    os.makedirs(out, exist_ok=True)
    zc = size.z / 2
    for name, loc, rot, plane in (
        ("side", (3, 0, zc), (90, 0, 90), "x"),        # from the animal's left (+X), head to the left
        ("front", (0, -3, zc), (90, 0, 0), "y"),
        ("top", (0, 0, 3), (0, 0, 0), "z"),
        ("threequarter", (2.1, -2.1, 1.2 + zc), (68, 0, 45), None),
    ):
        for o in bars:
            bpy.data.objects.remove(o)
        bars.clear()
        if plane:
            w = 0.0015
            n = int(ext / 0.05) + 1
            for i in range(-n, n + 1):
                t = i * 0.05
                if plane == "x":
                    bar(Vector((-1, t, zc - ext)), Vector((-1, t, zc + ext)), w)
                    bar(Vector((-1, -ext, zc + t)), Vector((-1, ext, zc + t)), w)
                elif plane == "y":
                    bar(Vector((t, 1, zc - ext)), Vector((t, 1, zc + ext)), w)
                    bar(Vector((-ext, 1, zc + t)), Vector((ext, 1, zc + t)), w)
                else:
                    bar(Vector((t, -ext, -0.5)), Vector((t, ext, -0.5)), w)
                    bar(Vector((-ext, t, -0.5)), Vector((ext, t, -0.5)), w)
            bar(Vector((-ext, 0, 0)) if plane != "x" else Vector((-1, -ext, 0)),
                Vector((ext, 0, 0)) if plane != "x" else Vector((-1, ext, 0)), 0.004)
        cam.location = loc
        cam.rotation_euler = [math.radians(a) for a in rot]
        sc.render.filepath = os.path.join(out, name + ".png")
        bpy.ops.render.render(write_still=True)
    for o in bars:
        bpy.data.objects.remove(o)
    bpy.data.objects.remove(cam)
    print("VIEWS %s -> %s (grid 5 cm, ortho %.2f m across)" % (sid, os.path.relpath(out, HERE), 2 * ext))


reset()
ob = import_lineup()
parts = split(ob, len(IDS))
for sid, part in zip(IDS, parts):
    reset_others = [o for o in bpy.context.scene.objects if o is not part]
    for o in reset_others:
        o.hide_render = True
    part.hide_render = False
    part.name = part.data.name = sid + "_src"
    size = stand(part, sid)
    os.makedirs(os.path.join(OUT, sid), exist_ok=True)
    views(part, sid, size)
    for o in reset_others:
        o.hide_render = False
# one file per animal
for sid in IDS:
    keep = bpy.data.objects[sid + "_src"]
    for o in list(bpy.context.scene.objects):
        if o is not keep:
            o.hide_viewport = False
    path = os.path.join(OUT, sid, sid + "_src.blend")
    others = [o for o in bpy.context.scene.objects if o is not keep]
    bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
    # strip the others from the saved copy
    import subprocess  # noqa: F401  (kept simple: reopen and delete below)
for sid in IDS:
    path = os.path.join(OUT, sid, sid + "_src.blend")
    bpy.ops.wm.open_mainfile(filepath=path)
    for o in list(bpy.data.objects):
        if o.name != sid + "_src":
            bpy.data.objects.remove(o)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("SAVED", os.path.relpath(path, HERE))
