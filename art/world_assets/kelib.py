"""Shared helpers for the world-asset build scripts in this folder (bed, fountain, bus ...).

Each asset has its own build.py that imports this file and regenerates its .blend and .glb from
scratch, headless:

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/<id>/build.py

Game conventions (docs/STYLE_GUIDE.md): metres, Z up here, the model's front faces -Y here (+Z in
Godot), centred on its footprint with its base on the floor. A surface whose material is named
wool_<palette id> gets the game's felt shader (Catalog.model); any other material name keeps its
own colour or texture, which is how the generated textures here survive.
"""
import json
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(HERE))
_PALETTE = {}
_MATS = {}
COLL = None


# --- scene -----------------------------------------------------------------------------------

def reset(name):
    """Empty scene with one collection, KE_<name>, that everything is built into."""
    global COLL
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    COLL = bpy.data.collections.new("KE_" + name)
    bpy.context.scene.collection.children.link(COLL)
    return COLL


def _link(ob):
    COLL.objects.link(ob)
    return ob


# --- colour and materials ----------------------------------------------------------------------

def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def pal_srgb(pid):
    if not _PALETTE:
        with open(os.path.join(PROJECT, "data", "palette.json"), encoding="utf-8") as f:
            for e in json.load(f)["colors"]:
                _PALETTE[e["id"]] = hex_rgb(e["hex"])
    return _PALETTE[pid]


def _principled(name, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    return m, b


def wool(pid):
    """A palette colour; the game swaps this for its felt material by name."""
    key = "wool_" + pid
    if key not in _MATS:
        m, b = _principled(key, 0.9)
        b.inputs["Base Color"].default_value = (*[srgb_to_lin(c) for c in pal_srgb(pid)], 1.0)
        _MATS[key] = m
    return _MATS[key]


def plain(name, hexcol, rough=0.85, emit=0.0, alpha=1.0):
    """A flat colour outside the palette (glass, water, lamps). Keeps its look in the game."""
    if name not in _MATS:
        m, b = _principled(name, rough)
        col = (*[srgb_to_lin(c) for c in hex_rgb(hexcol)], 1.0)
        b.inputs["Base Color"].default_value = col
        if emit > 0.0:
            b.inputs["Emission Color"].default_value = col
            b.inputs["Emission Strength"].default_value = emit
        if alpha < 1.0:
            b.inputs["Alpha"].default_value = alpha
            m.surface_render_method = "BLENDED"
        _MATS[name] = m
    return _MATS[name]


def textured(name, image, rough=0.9, emit=0.0, normal=None, normal_strength=1.0):
    """A material with a colour texture (uses the mesh's UVs). emit > 0 makes it glow; normal is
    an optional tangent-space normal map image for surface relief."""
    if name not in _MATS:
        m, b = _principled(name, rough)
        nt = m.node_tree
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = image
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
        if emit > 0.0:
            nt.links.new(t.outputs["Color"], b.inputs["Emission Color"])
            b.inputs["Emission Strength"].default_value = emit
        if normal is not None:
            normal.colorspace_settings.name = "Non-Color"
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = normal
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = normal_strength
            nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        _MATS[name] = m
    return _MATS[name]


# --- generated textures --------------------------------------------------------------------------

def tile_noise(n, beta=1.6, seed=0, m=None):
    """Tileable fractal noise, 0..1, shape (m or n, n). Higher beta = smoother."""
    m = m or n
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((m, n)))
    fy = np.fft.fftfreq(m)[:, None]
    fx = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    a = np.real(np.fft.ifft2(f / k ** beta))
    a -= a.min()
    return a / a.max()


def grain_noise(n, stretch=24.0, beta=1.3, seed=0):
    """Tileable noise drawn out into streaks that run down the image (wood grain, brushed paint)."""
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n)[:, None] * stretch
    fx = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    a = np.real(np.fft.ifft2(f / k ** beta))
    a -= a.min()
    return a / a.max()


def wood_image(name, folder, seed=1, planks=4, n=512):
    """Warm plank wood in the palette's wood colours; grain and plank seams run up the image."""
    g = grain_noise(n, 30.0, 1.25, seed)
    fine = grain_noise(n, 80.0, 0.7, seed + 7)
    base = np.array(pal_srgb("wood"))
    light = np.array(pal_srgb("wood_light"))
    dark = np.array(pal_srgb("wood_dark"))
    t = np.clip((g - 0.5) * 1.6 + 0.5, 0, 1)[..., None]
    rgb = base * (1 - t) + (base * 0.55 + light * 0.45) * t
    rgb = rgb * (0.9 + 0.2 * fine[..., None])
    x = np.arange(n)
    w = n // planks
    seam = np.minimum(x % w, w - x % w)
    line = np.clip(1.0 - seam / 2.5, 0, 1)[None, :, None]
    tint = (0.94 + 0.12 * np.random.default_rng(seed).random(planks))[(x // w) % planks][None, :, None]
    rgb = rgb * tint
    rgb = rgb * (1 - 0.55 * line) + dark * 0.55 * line
    return save_image(name, rgb, folder)


def normal_from_height(hgt, strength=2.0):
    """A tangent-space normal map (OpenGL, +Y up) from a tileable height image (row 0 at the top)."""
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * strength
    dy = (np.roll(hgt, 1, axis=0) - np.roll(hgt, -1, axis=0)) * strength  # up the image is +v
    n = np.dstack([-dx, -dy, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save_image(name, rgb, folder):
    """rgb: float array (H, W, 3), sRGB 0..1, row 0 at the top. Saved as a PNG and packed."""
    os.makedirs(folder, exist_ok=True)
    h, w, _ = rgb.shape
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb[::-1], 0.0, 1.0)  # Blender's rows start at the bottom
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(folder, name + ".png")
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


# --- meshes --------------------------------------------------------------------------------------

def _obj(name, mesh, mat=None):
    ob = bpy.data.objects.new(name, mesh)
    _link(ob)
    if mat is not None:
        mesh.materials.append(mat)
    return ob


def smooth(ob, keep_sharp=True):
    ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
    if keep_sharp:
        wn = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
    return ob


def apply_mods(ob):
    """Bakes the object's modifiers into its mesh."""
    if not ob.modifiers:
        return ob
    dg = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = new
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def box(name, size, loc, mat, bevel=0.03, seg=2, rot=(0, 0, 0)):
    """A rounded box: size and centre in metres."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = _obj(name, me, mat)
    ob.location = loc
    ob.rotation_euler = [math.radians(a) for a in rot]
    if bevel > 0.0:
        b = ob.modifiers.new("bevel", "BEVEL")
        b.width = min(bevel, min(size) * 0.49)
        b.segments = seg
        b.limit_method = "ANGLE"
    smooth(ob)
    bpy.context.view_layer.update()
    return apply_mods(ob)


def cyl(name, r1, r2, depth, loc, mat, verts=20, rot=(0, 0, 0), bevel=0.0, seg=2):
    """A cylinder or cone along its local Z, centred on loc. r1 is the bottom radius."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=r1, radius2=r2, depth=depth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = _obj(name, me, mat)
    ob.location = loc
    ob.rotation_euler = [math.radians(a) for a in rot]
    if bevel > 0.0:
        b = ob.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = seg
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(50)
    smooth(ob)
    bpy.context.view_layer.update()
    return apply_mods(ob)


def ball(name, r, loc, mat, scale=(1, 1, 1), u=16, v=10, boxy=1.0):
    """A sphere. boxy < 1 squares it off into a cushion shape before scaling."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    for vert in bm.verts:
        c = vert.co
        if boxy != 1.0:
            c = Vector([math.copysign(abs(a) ** boxy, a) for a in c])
        vert.co = Vector((c.x * r * scale[0], c.y * r * scale[1], c.z * r * scale[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = _obj(name, me, mat)
    ob.location = loc
    return smooth(ob, keep_sharp=False)


def torus(name, R, r, loc, mat, rot=(0, 0, 0), major=20, minor=6):
    verts, faces = [], []
    for i in range(major):
        a = 2 * math.pi * i / major
        for j in range(minor):
            b = 2 * math.pi * j / minor
            verts.append(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
    for i in range(major):
        for j in range(minor):
            a, b = i * minor + j, i * minor + (j + 1) % minor
            c, d = ((i + 1) % major) * minor + (j + 1) % minor, ((i + 1) % major) * minor + j
            faces.append((a, d, c, b))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = _obj(name, me, mat)
    ob.location = loc
    ob.rotation_euler = [math.radians(x) for x in rot]
    return smooth(ob, keep_sharp=False)


def lathe(name, profile, mat, steps=28, loc=(0, 0, 0), u_rep=1.0, v_rep=1.0, sharp=40):
    """Spins a profile [(radius, z), ...] round Z, listed from the outside-bottom upwards so the
    faces point outwards. UVs: u runs round (u_rep tiles), v runs along the profile (0..v_rep)."""
    lens = [0.0]
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        lens.append(lens[-1] + math.hypot(r1 - r0, z1 - z0))
    total = lens[-1] or 1.0
    verts, faces, uvs = [], [], []
    n = len(profile)
    for i in range(steps + 1):
        a = 2 * math.pi * i / steps
        for r, z in profile:
            verts.append((r * math.cos(a), r * math.sin(a), z))
    for i in range(steps):
        for j in range(n - 1):
            a, b = i * n + j, (i + 1) * n + j
            faces.append((a, b, b + 1, a + 1))
            u0, u1 = i / steps * u_rep, (i + 1) / steps * u_rep
            v0, v1 = lens[j] / total * v_rep, lens[j + 1] / total * v_rep
            uvs += [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    layer = me.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", [c for uv in uvs for c in uv])
    ob = _obj(name, me, mat)
    ob.location = loc
    # weld the seam and the pole so shading is continuous (UVs live on face corners, so they stay)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    es = ob.modifiers.new("edges", "EDGE_SPLIT")
    es.split_angle = math.radians(sharp)
    bpy.context.view_layer.update()
    return apply_mods(ob)


def disc(name, r, z, mat, steps=28, turn=0.0):
    """A flat round (or, with few steps, many-sided) surface, with the texture laid across it once."""
    ang = [turn + 2 * math.pi * i / steps for i in range(steps)]
    verts = [(0, 0, z)] + [(r * math.cos(a), r * math.sin(a), z) for a in ang]
    faces = [(0, 1 + i, 1 + (i + 1) % steps) for i in range(steps)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    uv = me.uv_layers.new(name="UVMap")
    for li, loop in enumerate(me.loops):
        x, y, _ = verts[loop.vertex_index]
        uv.data[li].uv = (0.5 + x / (2 * r), 0.5 + y / (2 * r))
    return _obj(name, me, mat)


def star(name, r, loc, mat, points=5, turn=0.0, inner=0.45):
    """A small flat star: a fallen maple leaf."""
    verts = [(0, 0, 0)]
    for i in range(points * 2):
        a = turn + math.pi * i / points
        rr = r if i % 2 == 0 else r * inner
        verts.append((rr * math.cos(a), rr * math.sin(a), 0))
    faces = [(0, 1 + i, 1 + (i + 1) % (points * 2)) for i in range(points * 2)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = _obj(name, me, mat)
    ob.location = loc
    return ob


def extrude_xz(name, pts, y0, y1, mat, bevel=0.015):
    """A flat shape drawn in XZ (counter-clockwise seen from -Y), given thickness from y0 to y1."""
    n = len(pts)
    verts = [(x, y0, z) for x, z in pts] + [(x, y1, z) for x, z in pts]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, i + n, j + n, j))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = _obj(name, me, mat)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    if bevel > 0.0:
        b = ob.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(60)
    smooth(ob)
    bpy.context.view_layer.update()
    return apply_mods(ob)


def pane(name, a, b, mat, out):
    """A flat upright panel from corner a (bottom-left) to b (top-right), facing `out` (a unit
    vector), with the whole texture mapped across it once. For windows, doors and signs."""
    a, b, out = Vector(a), Vector(b), Vector(out)
    up = Vector((0, 0, b.z - a.z))
    along = Vector((b.x - a.x, b.y - a.y, 0))
    verts = [a, a + along, a + along + up, a + up]
    order = (0, 1, 2, 3) if along.cross(up).dot(out) > 0 else (3, 2, 1, 0)
    uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [order])
    me.uv_layers.new(name="UVMap").data.foreach_set("uv", [c for i in order for c in uv[i]])
    return _obj(name, me, mat)


def text(name, body, size, loc, rot, mat, depth=0.008):
    """Raised lettering (the built-in font), centred on loc. rot in degrees."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = depth
    ob = bpy.data.objects.new(name, cu)
    _link(ob)
    ob.location = loc
    ob.rotation_euler = [math.radians(x) for x in rot]
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    mob = _obj(name, me, mat)
    mob.matrix_world = ob.matrix_world.copy()
    bpy.data.objects.remove(ob)
    return mob


# --- UVs -----------------------------------------------------------------------------------------

def uv_box(ob, scale=1.0, v_from_z=None, grain="z"):
    """Projects UVs from the side each face points to, in world metres times scale.
    v_from_z=(z0, z1): on upright faces v runs 0..1 from z0 to z1 instead (for height gradients).
    grain: the world axis the texture's v runs along where it can ("z" upright, "x" or "y" lengthwise)."""
    me = ob.data
    layer = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    mw = ob.matrix_world
    rot = mw.to_3x3()
    for poly in me.polygons:
        n = (rot @ poly.normal).normalized()
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            p = mw @ me.vertices[me.loops[li].vertex_index].co
            if ax == 2:
                u, v = (p.y, p.x) if grain == "x" else (p.x, p.y)
            elif ax == 1:
                u, v = (p.z, p.x) if grain == "x" else (p.x, p.z)
            else:
                u, v = (p.z, p.y) if grain == "y" else (p.y, p.z)
            u, v = u * scale, v * scale
            if v_from_z is not None and ax != 2:
                v = min(0.999, max(0.001, (p.z - v_from_z[0]) / (v_from_z[1] - v_from_z[0])))
            layer.data[li].uv = (u, v)
    return ob


# --- finishing -----------------------------------------------------------------------------------

def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def finish(name, out_dir, max_tris=None):
    """Joins everything into one mesh called 'model', saves <name>.blend and exports <name>.glb."""
    bpy.context.view_layer.update()
    obs = [o for o in COLL.objects if o.type == "MESH"]
    for o in obs:
        apply_mods(o)
        # Join keeps only the active object's UV layers, so every part needs one called UVMap or
        # textured parts lose their UVs when the first part happens to be untextured.
        if "UVMap" not in o.data.uv_layers:
            for extra in list(o.data.uv_layers):
                extra.name = "UVMap"
                break
            else:
                o.data.uv_layers.new(name="UVMap")
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "model"
    ob.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    os.makedirs(out_dir, exist_ok=True)
    co = [v.co for v in ob.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    tris = tri_count(ob)
    stats = {
        "name": name, "triangles": tris, "materials": [m.name for m in ob.data.materials],
        "size_m": [round(hi.x - lo.x, 3), round(hi.y - lo.y, 3), round(hi.z - lo.z, 3)],
        "min_m": [round(a, 3) for a in lo], "max_m": [round(a, 3) for a in hi],
        "images": [i.name for i in bpy.data.images if i.users and i.type == "IMAGE"],
    }
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, name + ".glb"), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)
    stats["glb_bytes"] = os.path.getsize(os.path.join(out_dir, name + ".glb"))
    with open(os.path.join(out_dir, "stats.json"), "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)
    print("[ke] " + json.dumps(stats))
    if max_tris and tris > max_tris:
        raise SystemExit("%s has %d triangles, over the %d budget" % (name, tris, max_tris))
    return ob
