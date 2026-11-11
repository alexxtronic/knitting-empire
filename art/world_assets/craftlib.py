"""Organic shapes for the crop and yarn builds (art/world_assets/crops, art/world_assets/yarn), on top
of kelib: swept tubes (stems, vines, tendrils, yarn strands), strap leaves (turnip greens), palmate
leaves (pumpkin), a ribbed lathe (pumpkins) and painterly textures in the style of Alex's
reference art: soft, saturated, brushy colour with gentle relief.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import kelib as K


# --- meshes ----------------------------------------------------------------------------------------

def _finish_mesh(name, verts, faces, uvs, mat, recalc=True, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    layer = me.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", [c for uv in uvs for c in uv])
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = K._obj(name, me, mat)
    if smooth:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return ob


def frames(pts):
    """Tangents and rotation-minimising normals along a polyline."""
    n = len(pts)
    T = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    a = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    N = [T[0].cross(a).normalized()]
    for i in range(1, n):
        nv = N[-1].copy()
        ax = T[i - 1].cross(T[i])
        if ax.length > 1e-9:
            nv = Matrix.Rotation(T[i - 1].angle(T[i]), 3, ax.normalized()) @ nv
        nv = (nv - T[i] * nv.dot(T[i])).normalized()
        N.append(nv)
    B = [T[i].cross(N[i]) for i in range(n)]
    return T, N, B


def tube(name, pts, radii, mat, sides=8, v_scale=1.0, u_rep=1.0, caps=True, flat=1.0):
    """A tube swept along pts (Vectors) with a radius per point. UVs: u round, v along (metres x
    v_scale). Capped ends are closed with a fan so the normals can be fixed up automatically.
    flat < 1 squashes the cross-section along the binormal (a strap or a flattened yarn)."""
    pts = [Vector(p) for p in pts]
    T, N, B = frames(pts)
    verts, faces, uvs = [], [], []
    lens = [0.0]
    for a, b in zip(pts, pts[1:]):
        lens.append(lens[-1] + (b - a).length)
    ring = sides + 1
    for i, p in enumerate(pts):
        for j in range(ring):
            ang = 2 * math.pi * j / sides
            verts.append(p + radii[i] * (math.cos(ang) * N[i] + flat * math.sin(ang) * B[i]))
    for i in range(len(pts) - 1):
        for j in range(sides):
            a0, a1 = i * ring + j, i * ring + j + 1
            b0, b1 = (i + 1) * ring + j, (i + 1) * ring + j + 1
            faces.append((a0, a1, b1, b0))
            uvs += [(j / sides * u_rep, lens[i] * v_scale), ((j + 1) / sides * u_rep, lens[i] * v_scale),
                    ((j + 1) / sides * u_rep, lens[i + 1] * v_scale), (j / sides * u_rep, lens[i + 1] * v_scale)]
    if caps:
        # wound so both caps face outward (the side quads above already do), no guessing needed
        for end, i in ((0, 0), (1, len(pts) - 1)):
            c = len(verts)
            verts.append(pts[i])
            for j in range(sides):
                if end == 0:
                    faces.append((c, i * ring + j + 1, i * ring + j))
                    uvs += [(0.5, lens[i] * v_scale), ((j + 1) / sides * u_rep, lens[i] * v_scale), (j / sides * u_rep, lens[i] * v_scale)]
                else:
                    faces.append((c, i * ring + j, i * ring + j + 1))
                    uvs += [(0.5, lens[i] * v_scale), (j / sides * u_rep, lens[i] * v_scale), ((j + 1) / sides * u_rep, lens[i] * v_scale)]
    return _finish_mesh(name, verts, faces, uvs, mat, recalc=False)


def bezier(p0, p1, p2, p3, n=12):
    p0, p1, p2, p3 = (Vector(p) for p in (p0, p1, p2, p3))
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(p0 * (1 - t) ** 3 + p1 * 3 * (1 - t) ** 2 * t + p2 * 3 * (1 - t) * t * t + p3 * t ** 3)
    return out


def tendril(name, start, direction, mat, length=0.12, coils=2.2, r=0.0055, rise=0.02, seed=0):
    """A pumpkin tendril: a short reach that winds into a tightening curl, like the reference art."""
    rng = np.random.default_rng(seed)
    d = Vector(direction).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d).normalized()
    pts = []
    reach = length * 0.45
    n_reach = 6
    for i in range(n_reach):
        t = i / n_reach
        pts.append(Vector(start) + d * reach * t + up * rise * math.sin(t * math.pi * 0.5))
    centre_base = pts[-1] + d * 0.0
    n_coil = int(14 * coils)
    rad0 = length * 0.16
    for i in range(1, n_coil + 1):
        t = i / n_coil
        ang = t * coils * 2 * math.pi
        rad = rad0 * (1 - 0.85 * t)
        # the curl sits in the plane of d and up, winding toward its centre
        c = centre_base + up * rad0 + up * rise * t * 0.3
        pts.append(c + (-up * math.cos(ang) + d * math.sin(ang)) * rad + side * 0.002 * rng.standard_normal())
    radii = [r * (1 - 0.5 * i / len(pts)) for i in range(len(pts))]
    return tube(name, pts, radii, mat, sides=5, v_scale=4.0)


def strap_leaf(name, base, yaw, length, width, mat, petiole=0.35, lift=55.0, droop=35.0, fold=0.35,
               wave=0.0, lobes=0.0, ns=9, petiole_mat=None, petiole_r=None, twist=0.0):
    """A turnip-style leaf: a pale stalk rising from base, then a rounded blade with wavy lobes that
    arches out and droops at the tip. yaw/lift/droop in degrees. UVs: u across (0..1), v along (0..1)."""
    yaw_r = math.radians(yaw)
    fwd = Vector((math.cos(yaw_r), math.sin(yaw_r), 0))
    side = Vector((-math.sin(yaw_r), math.cos(yaw_r), 0))
    up = Vector((0, 0, 1))
    # the spine: the elevation eases from `lift` at the base to `-droop` at the tip
    steps = 24
    spine = [Vector(base)]
    for i in range(steps):
        t = (i + 0.5) / steps
        el = math.radians(lift + (-droop - lift) * t ** 1.4)
        spine.append(spine[-1] + (fwd * math.cos(el) + up * math.sin(el)) * length / steps)

    def at(t):
        f = t * steps
        i = min(int(f), steps - 1)
        return spine[i].lerp(spine[i + 1], f - i)

    pr = petiole_r or width * 0.12
    stalk = [at(t) for t in np.linspace(0, petiole, 5)]
    tube(name + "_stalk", stalk, [pr * 1.15, pr, pr * 0.95, pr * 0.9, pr * 0.85], petiole_mat or mat, sides=5, v_scale=6.0)
    # the blade
    nx = 4
    verts, faces, uvs = [], [], []
    for i in range(ns + 1):
        s = i / ns
        t = petiole * 0.92 + (1 - petiole * 0.92) * s
        c = at(t)
        tan = (at(min(1, t + 0.01)) - at(max(0, t - 0.01))).normalized()
        nrm = tan.cross(side).normalized()
        shape = math.sin(math.pi * min(1.0, 0.04 + s * 0.98)) ** 0.55 * (0.5 + 0.5 * s ** 0.6)
        shape *= 1 + lobes * math.sin(s * math.pi * 5.0 + 0.4) * (1 - s * 0.6)
        w = width * shape
        rot = Matrix.Rotation(math.radians(twist) * s, 3, tan)
        for j in range(nx + 1):
            x = -1 + 2 * j / nx
            off = rot @ (side * x * w + nrm * (fold * abs(x) * w + wave * w * math.sin(s * 9 + x * 2) * abs(x)))
            verts.append(c + off)
    for i in range(ns):
        for j in range(nx):
            a = i * (nx + 1) + j
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
            uvs += [(j / nx, i / ns), ((j + 1) / nx, i / ns), ((j + 1) / nx, (i + 1) / ns), (j / nx, (i + 1) / ns)]
    return _finish_mesh(name, verts, faces, uvs, mat, recalc=False)


PALM_LOBES = ((0.0, 1.0), (0.95, 0.86), (-0.95, 0.86), (1.95, 0.62), (-1.95, 0.62))


def palm_outline(theta):
    """Radius (0..1) of a five-lobed, pointed, heart-based pumpkin leaf at angle theta (0 = tip)."""
    best = 0.0
    for c, amp in PALM_LOBES:
        d = abs((theta - c + math.pi) % (2 * math.pi) - math.pi)
        best = max(best, amp * max(0.0, 1 - d / 0.95) ** 1.35)
    base = 0.48 + 0.1 * math.cos(theta)
    notch = 1 - 0.75 * math.exp(-((abs(theta) - math.pi) / 0.35) ** 2)
    return max(base, best) * notch


def palm_leaf(name, centre, R, mat, yaw=0.0, pitch=10.0, roll=0.0, cup=0.18, droop=0.28, ruffle=0.05, seg=34):
    """A pumpkin leaf lying roughly flat: attached at `centre`, pointing along yaw. UVs are planar in
    the leaf's own frame (centre of the image = the attachment point, tip toward +u)."""
    rings = (0.0, 0.35, 0.7, 1.0)
    verts, faces, uvs = [], [], []
    rot = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Matrix.Rotation(math.radians(-pitch), 3, "Y") @ Matrix.Rotation(math.radians(roll), 3, "X")
    local = []
    for k in rings[1:]:
        for i in range(seg):
            th = -math.pi + 2 * math.pi * i / seg
            r = palm_outline(th) * k * R
            z = R * (cup * k - droop * k * k) + R * ruffle * math.sin(th * 7) * k ** 2
            local.append((r * math.cos(th), r * math.sin(th), z))
    verts = [Vector(centre)] + [Vector(centre) + rot @ Vector(p) for p in local]
    lv = [(0.0, 0.0, 0.0)] + local
    for i in range(seg):
        faces.append((0, 1 + i, 1 + (i + 1) % seg))
    for ri in range(len(rings) - 2):
        a0, b0 = 1 + ri * seg, 1 + (ri + 1) * seg
        for i in range(seg):
            j = (i + 1) % seg
            faces.append((a0 + i, b0 + i, b0 + j, a0 + j))
    for f in faces:
        for vi in f:
            x, y, _ = lv[vi]
            uvs.append((0.5 + x / (2.2 * R), 0.5 + y / (2.2 * R)))
    return _finish_mesh(name, verts, faces, uvs, mat, recalc=False)


def ribbed(name, R, H, mat, ribs=10, depth=0.12, steps=None, dimple=0.16, loc=(0, 0, 0), sharp=179, squash_top=0.0):
    """A pumpkin: a squat lathe with deep rounded lobes. u runs round the body (one unit per turn),
    so a texture can shade the grooves where cos(ribs * pi * u) is near zero."""
    steps = steps or ribs * 4
    prof = []
    n = 14
    for i in range(n + 1):
        ph = -math.pi / 2 + math.pi * i / n
        r = R * max(0.0, math.cos(ph)) ** 0.72
        z = H / 2 * (1 + math.sin(ph))
        rr = r / R
        if ph > 0:
            z -= H * dimple * (1 - rr) ** 3 + H * squash_top * (1 - rr) * rr
        else:
            z += H * dimple * 0.45 * (1 - rr) ** 3
        prof.append((r, z))
    prof[0] = (0.0, prof[0][1])
    prof[-1] = (0.0, prof[-1][1])
    ob = K.lathe(name, prof, mat, steps=steps, sharp=sharp)
    for v in ob.data.vertices:
        c = v.co
        phi = math.atan2(c.y, c.x)
        f = 1 - depth * (1 - abs(math.cos(ribs * phi / 2))) ** 2.2
        v.co = Vector((c.x * f, c.y * f, c.z))
    ob.location = loc
    return ob


# --- painterly textures ---------------------------------------------------------------------------

def mix(a, b, t):
    return a * (1 - t) + b * t


def C(h):
    return np.array(K.hex_rgb(h))


def brush(n, seed, stretch=10.0, beta=1.0):
    """Soft brush strokes: streaky noise, 0..1."""
    return K.grain_noise(n, stretch, beta, seed)


def pumpkin_maps(name, folder, ribs, base="#f07a1c", light="#ffa646", dark="#b9470c", top="#c75a14", green=False, n=512):
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    lobe = np.abs(np.cos(ribs * np.pi * u))  # 1 on a lobe's crown, 0 in a groove
    s1 = brush(n, 11, 18, 1.1)
    s2 = brush(n, 13, 40, 0.8)
    crown = np.clip(lobe ** 0.6, 0, 1)[..., None]
    rgb = mix(C(dark), C(base), np.clip(lobe ** 0.35 * 1.15, 0, 1)[..., None])
    rgb = mix(rgb, C(light), (crown * np.clip((s1 - 0.35) * 1.6, 0, 1)[..., None]) * 0.75)
    rgb *= (0.9 + 0.18 * s2[..., None])
    pole = np.clip(np.abs(v - 0.5) * 2 - 0.55, 0, 1)[..., None] / 0.45
    rgb = mix(rgb, C(top), pole * 0.55)
    if green:  # an unripe pumpkin: green with pale stripes down the lobes
        g = mix(C("#4f7a2a"), C("#8fb24a"), np.clip(lobe ** 3 * (0.6 + 0.6 * s1), 0, 1)[..., None])
        rgb = g * (0.9 + 0.15 * s2[..., None])
    hgt = 0.5 * lobe + 0.15 * s1 + 0.1 * s2
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(hgt, 2.0), folder)


def stem_maps(name, folder, base="#8b5a2b", light="#c08850", dark="#5e3a1c", n=256):
    yy, xx = np.mgrid[0:n, 0:n]
    v = 1 - yy / n
    g = brush(n, 21, 30, 1.0)
    f = brush(n, 23, 60, 0.7)
    rgb = mix(C(dark), C(base), np.clip(g * 1.4, 0, 1)[..., None])
    rgb = mix(rgb, C(light), np.clip((g - 0.6) * 2.5, 0, 1)[..., None] * 0.7)
    rgb *= (0.9 + 0.15 * f[..., None])
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(0.6 * g + 0.3 * f, 3.0), folder)


def strap_leaf_maps(name, folder, base="#5ea832", light="#9fd14e", dark="#3d7a24", rib="#c9e48a", n=256):
    """u across the blade, v base to tip: a pale midrib, side veins sweeping toward the tip, a
    brighter centre and brushy light patches."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    x = np.abs(u - 0.5) * 2
    s = brush(n, 31, 6, 1.2)
    rgb = mix(C(base), C(light), np.clip((1 - x) * 0.6 + (s - 0.5) * 0.8, 0, 1)[..., None])
    rgb = mix(rgb, C(dark), np.clip(x - 0.75, 0, 1)[..., None] * 1.6)
    midrib = np.exp(-((u - 0.5) / 0.035) ** 2)[..., None]
    vein_phase = (v * 7 - x * 1.4) % 1.0
    vein = (np.exp(-((vein_phase - 0.5) / 0.05) ** 2) * np.clip(1 - x, 0, 1) * 0.5)[..., None]
    rgb = mix(rgb, C(rib), np.clip(midrib + vein, 0, 1) * 0.8)
    hgt = -midrib[..., 0] * 0.6 - vein[..., 0] * 0.5 + 0.2 * s
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(hgt, 2.5), folder)


def palm_leaf_maps(name, folder, base="#6fa82c", light="#a8d24c", dark="#4a7d22", vein="#d0e88e", n=512):
    """Planar: the attachment point in the middle, veins radiating to each lobe, finer side veins."""
    yy, xx = np.mgrid[0:n, 0:n]
    x = (xx / n - 0.5) * 2.2
    y = ((1 - yy / n) - 0.5) * 2.2
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    s = brush(n, 41, 3, 1.3)
    rgb = mix(C(base), C(light), np.clip(0.55 - r * 0.5 + (s - 0.5) * 0.9, 0, 1)[..., None])
    rgb = mix(rgb, C(dark), np.clip(r - 0.75, 0, 1)[..., None] * 1.5)
    v = np.zeros_like(r)
    for c, _ in [(0.0, 1), (0.95, 1), (-0.95, 1), (1.95, 1), (-1.95, 1)]:
        d = np.abs((th - c + np.pi) % (2 * np.pi) - np.pi)
        v = np.maximum(v, np.exp(-(d * r / 0.025) ** 2) * (r < 0.98))
        for side in (-1, 1):  # side veins leaving each main vein toward the edge
            for k in (0.25, 0.45, 0.65):
                ang = c + side * 0.45
                px, py = k * np.cos(c), k * np.sin(c)
                dx, dy = x - px, y - py
                along = dx * np.cos(ang) + dy * np.sin(ang)
                perp = np.abs(-dx * np.sin(ang) + dy * np.cos(ang))
                v = np.maximum(v, np.exp(-(perp / 0.012) ** 2) * (along > 0) * (along < 0.28) * 0.6)
    rgb = mix(rgb, C(vein), np.clip(v, 0, 1)[..., None] * 0.75)
    hgt = -v * 0.7 + 0.25 * s
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(hgt, 2.5), folder)


def turnip_maps(name, folder, n=512, band=0.58):
    """u round, v from the root tip up to the crown: cream below, a brushy magenta-purple shoulder
    above, a few little root wrinkles on the cream."""
    rng = np.random.default_rng(51)
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    edge = band + 0.07 * (K.tile_noise(n, 1.2, 53)[0][None, :] - 0.5) * 2 + 0.05 * (brush(n, 55, 4, 1.0) - 0.5)
    s = brush(n, 57, 10, 1.0)
    cream = mix(C("#e9d7b3"), C("#f6ead0"), np.clip(s * 1.2 - 0.1, 0, 1)[..., None])
    cream = mix(cream, C("#d8c29a"), np.clip(0.25 - v, 0, 1)[..., None] * 2.5)
    purple = mix(C("#a63f9a"), C("#cf6cc2"), np.clip((s - 0.3) * 1.5, 0, 1)[..., None])
    purple = mix(purple, C("#8c3486"), np.clip(v - 0.9, 0, 1)[..., None] * 6)
    t = np.clip((v - edge) / 0.09 + (s - 0.5) * 0.9, 0, 1)[..., None]
    rgb = mix(cream, purple, t)
    hgt = 0.2 * s
    for _ in range(14):  # little wrinkle arcs on the cream
        cu, cv = rng.uniform(0, 1), rng.uniform(0.18, band - 0.08)
        w = rng.uniform(0.025, 0.045)
        du = (u - cu + 0.5) % 1.0 - 0.5
        arc = np.exp(-((v - cv - 3.0 * du ** 2) / 0.004) ** 2) * (np.abs(du) < w)
        rgb = mix(rgb, C("#bfa57a"), arc[..., None] * 0.8)
        hgt -= arc * 0.8
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(hgt, 2.0), folder)


def yarn_maps(name, folder, hexcol, n=128, plies=3, twists=2):
    """A chunky plied strand: u round the strand, v along it. Helical ply grooves and soft fuzz."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    ply = 0.5 + 0.5 * np.cos(2 * np.pi * (plies * u + twists * v))
    fuzz = K.tile_noise(n, 0.6, 61)
    base = C(hexcol)
    rgb = base * (0.86 + 0.22 * ply[..., None] ** 0.7) * (0.95 + 0.1 * fuzz[..., None])
    hgt = ply ** 0.7 + 0.15 * fuzz
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(hgt, 3.0), folder)


def wood_maps(name, folder, base="#cf7630", light="#eda055", dark="#a5561f", n=256):
    """Glossy turned wood like the reference needles: smooth orange-tan with long, soft grain lines
    and a few gentle cathedral loops; nothing speckled."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    g = K.grain_noise(n, 12.0, 2.2, 71)  # broad, smooth drift
    phase = 3 * u + 1.6 * g + 0.25 * np.sin(2 * np.pi * v)
    line = 0.5 + 0.5 * np.cos(2 * np.pi * phase)
    rgb = mix(C(base), C(light), np.clip(line ** 3, 0, 1)[..., None])
    rgb = mix(rgb, C(dark), np.clip(0.22 - line, 0, 1)[..., None] * 3.5)
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(0.15 * line, 1.0), folder)


def wicker_maps(name, folder, n=256):
    """A basket weave: two rows of horizontal reed per tile passing over and under upright stakes."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    row = (v * 4) % 1.0
    which = np.floor(v * 4).astype(int) % 2
    col = (u * 4 + which * 0.5) % 1.0
    # each reed swells where it passes over a stake and dips where it goes under
    over = np.sin(np.pi * col)
    reed = np.sin(np.pi * row) ** 0.5 * (0.45 + 0.55 * over)
    gap = np.clip(1 - np.sin(np.pi * row) * 2.5, 0, 1)
    under = np.clip(0.25 - over, 0, 1) * 2.5
    s = K.tile_noise(n, 0.8, 81)
    rgb = mix(C("#a86c34"), C("#e7b878"), reed[..., None] * (0.75 + 0.35 * s[..., None]))
    rgb = mix(rgb, C("#6a4220"), np.clip(gap + under * 0.6, 0, 1)[..., None] * 0.85)
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(reed, 3.0), folder)


# --- more shapes (fence, hay, scarecrow, stall) -----------------------------------------------------

def beam(name, pts, w, h, mat, sides=12, v_scale=1.0, wave=0.0, seed=0, square=0.35):
    """A rounded-square beam along pts (a fence rail, a post, a plank): w across, h up. The
    cross-section is a superellipse (square=1 is an ellipse, smaller is boxier with soft edges).
    wave > 0 lets it meander a little, like hand-cut wood in the reference."""
    pts = [Vector(p) for p in pts]
    if wave > 0:
        rng = np.random.default_rng(seed)
        ph = rng.uniform(0, 6.28, 2)
        n = len(pts)
        pts = [p + Vector((0, wave * math.sin(3.1 * i / n + ph[0]) * 0.5, wave * math.sin(4.3 * i / n + ph[1]))) for i, p in enumerate(pts)]
    T, N, B = frames(pts)
    verts, faces, uvs = [], [], []
    lens = [0.0]
    for a, b in zip(pts, pts[1:]):
        lens.append(lens[-1] + (b - a).length)
    ring = sides + 1
    for i, p in enumerate(pts):
        up = Vector((0, 0, 1))
        n_ = (up - T[i] * up.dot(T[i]))
        if n_.length < 1e-4:
            n_ = N[i]
        n_.normalize()
        b_ = T[i].cross(n_)
        for j in range(ring):
            a = 2 * math.pi * j / sides + math.pi / sides
            c, s = math.cos(a), math.sin(a)
            x = math.copysign(abs(c) ** square, c) * w / 2
            y = math.copysign(abs(s) ** square, s) * h / 2
            verts.append(p + b_ * x + n_ * y)
    for i in range(len(pts) - 1):
        for j in range(sides):
            a0, a1 = i * ring + j, i * ring + j + 1
            b0, b1 = (i + 1) * ring + j, (i + 1) * ring + j + 1
            faces.append((a0, b0, b1, a1))
            uvs += [(j / sides, lens[i] * v_scale), (j / sides, lens[i + 1] * v_scale),
                    ((j + 1) / sides, lens[i + 1] * v_scale), ((j + 1) / sides, lens[i] * v_scale)]
    for end, i in ((0, 0), (1, len(pts) - 1)):
        c = len(verts)
        verts.append(pts[i])
        for j in range(sides):
            if end == 0:
                faces.append((c, i * ring + j, i * ring + j + 1))
            else:
                faces.append((c, i * ring + j + 1, i * ring + j))
            uvs += [(0.5, 0.5), (0.5, 0.5), (0.5, 0.5)]
    ob = _finish_mesh(name, verts, faces, uvs, mat, recalc=True)
    es = ob.modifiers.new("edges", "EDGE_SPLIT")
    es.split_angle = math.radians(60)
    return K.apply_mods(ob)


def quad_cap(name, centre, size, mat, normal=(0, 0, 1), turn=0.0):
    """A flat square (or rectangle) with the whole texture across it once: end grain on a post top."""
    c = Vector(centre)
    nz = Vector(normal).normalized()
    ax = Vector((1, 0, 0)) if abs(nz.x) < 0.9 else Vector((0, 1, 0))
    u = (ax - nz * ax.dot(nz)).normalized()
    u = Matrix.Rotation(turn, 3, nz) @ u
    v = nz.cross(u)
    sx, sy = size if isinstance(size, (tuple, list)) else (size, size)
    vs = [c + (-u * sx - v * sy) / 2, c + (u * sx - v * sy) / 2, c + (u * sx + v * sy) / 2, c + (-u * sx + v * sy) / 2]
    return _finish_mesh(name, vs, [(0, 1, 2, 3)], [(0, 0), (1, 0), (1, 1), (0, 1)], mat, recalc=False, smooth=False)


def tuft(name, root, direction, out, length, width, mat, curl=0.35, segs=3, feather=False):
    """One painterly straw tuft: a tapered blade from root along direction, lifting away from the
    surface (out) toward its tip. UVs: u across, v root to tip."""
    root, d, o = Vector(root), Vector(direction).normalized(), Vector(out).normalized()
    side = d.cross(o).normalized()
    verts, faces, uvs = [], [], []
    for i in range(segs + 1):
        t = i / segs
        p = root + d * length * t + o * length * curl * t * t
        if feather:  # a broad, soft, pointed lock like the reference bale
            w = width * math.sin(math.pi * (0.35 + 0.65 * t)) ** 0.7 if t < 1 else 0.0
        else:
            w = width * (1 - t) ** 0.8 * (0.6 + 0.4 * math.sin(math.pi * min(1, t + 0.3)))
        verts += [p - side * w / 2, p + side * w / 2]
    for i in range(segs):
        a = 2 * i
        faces.append((a, a + 1, a + 3, a + 2))
        uvs += [(0, i / segs), (1, i / segs), (1, (i + 1) / segs), (0, (i + 1) / segs)]
    return verts, faces, uvs


def tufts_mesh(name, blades, mat):
    """Joins many tuft() results into one mesh (much faster than one object each)."""
    V, F, U = [], [], []
    for v, f, u in blades:
        off = len(V)
        V += v
        F += [tuple(i + off for i in face) for face in f]
        U += u
    return _finish_mesh(name, V, F, U, mat, recalc=False)


def plank_maps(name, folder, base="#c56f2c", light="#e08f45", dark="#93501f", knots=1, seams=0, n=256, seed=91):
    """Stylised hand-painted wood: long flowing grain lines in warm orange-brown, a couple of swirl
    knots, optional plank seams across u. v runs along the grain."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    g = K.grain_noise(n, 14.0, 2.0, seed)
    phase = 3 * u + 1.2 * g
    for _ in range(knots):
        ku, kv = rng.uniform(0.2, 0.8), rng.uniform(0.15, 0.85)
        du, dv = (u - ku), (v - kv) * 0.35
        r = np.hypot(du, dv)
        phase += 0.5 * np.exp(-(r / 0.06) ** 2) * np.sin(r * 70)
    line = 0.5 + 0.5 * np.cos(2 * np.pi * phase)
    s = brush(n, seed + 1, 8, 1.2)
    rgb = mix(C(base), C(light), np.clip(line ** 3 * 0.8 + (s - 0.5) * 0.5, 0, 1)[..., None])
    rgb = mix(rgb, C(dark), np.clip(0.18 - line, 0, 1)[..., None] * 4)
    hgt = 0.25 * line
    if seams:
        su = (u * seams) % 1.0
        seam = np.clip(1 - np.minimum(su, 1 - su) * n / seams / 2.0, 0, 1)
        rgb = mix(rgb, C(dark) * 0.7, seam[..., None])
        hgt -= seam
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(hgt, 1.5), folder)


def endgrain_maps(name, folder, base="#d38a48", light="#eaa766", dark="#9c5a2a", n=256):
    """The sawn top of a post: a soft spiral of growth rings, like the reference fence."""
    yy, xx = np.mgrid[0:n, 0:n]
    x = (xx / n - 0.5) * 2
    y = ((1 - yy / n) - 0.5) * 2
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    ring = 0.5 + 0.5 * np.cos(2 * np.pi * (r * 4.2 + th / (2 * np.pi)))
    rgb = mix(C(base), C(light), np.clip(ring ** 2, 0, 1)[..., None] * 0.7)
    rgb = mix(rgb, C(dark), np.clip(0.15 - ring, 0, 1)[..., None] * 4)
    edge = np.clip((np.maximum(np.abs(x), np.abs(y)) - 0.85) * 6, 0, 1)[..., None]
    rgb = mix(rgb, C(dark), edge * 0.6)
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(0.2 * ring, 1.5), folder)


def straw_maps(name, folder, base="#f0b22a", light="#ffd968", dark="#b8780c", n=256, strands=40, seed=101):
    """Straw: many fine strands running along v, each its own shade of gold, with dark gaps between
    them, darker at the root (v = 0) and sunlit toward the tip."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    wob = K.tile_noise(n, 2.2, seed)
    x = (u * strands + 0.7 * (wob - 0.5)) % strands
    idx = np.floor(x).astype(int) % strands
    f = x - np.floor(x)
    tone = rng.uniform(0, 1, strands)[idx]
    rgb = mix(C(base), C(light), np.clip(tone * 1.6 - 0.6, 0, 1)[..., None])
    rgb = mix(rgb, C(dark), np.clip(0.6 - tone * 1.6, 0, 1)[..., None])
    ridge = np.sin(np.pi * f) ** 0.5
    rgb = rgb * (0.62 + 0.42 * ridge[..., None])
    rgb = mix(C(dark) * 0.8, rgb, np.clip(0.45 + v * 1.4, 0, 1)[..., None])
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(ridge * 0.5, 2.5), folder)


def plaid_maps(name, folder, a="#cf4a2c", b="#ef8a33", c="#9e2a1c", n=256, checks=6):
    """Buffalo-check flannel in red and orange, soft and slightly woven."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    bu = (np.floor(u * checks) % 2)
    bv = (np.floor(v * checks) % 2)
    rgb = np.where((bu + bv)[..., None] == 0, C(b), np.where((bu * bv)[..., None] == 1, C(c), C(a)))
    weave = 0.5 + 0.5 * np.sin(2 * np.pi * (u + v) * n / 4)
    rgb = rgb * (0.9 + 0.12 * weave[..., None])
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(0.1 * weave, 1.0), folder)


def cloth_maps(name, folder, hexcol, n=256, seed=111, weave_px=3, rough=0.12):
    """A plain woven cloth (denim, burlap, canvas): base colour with a fine weave and soft mottling."""
    yy, xx = np.mgrid[0:n, 0:n]
    wx = np.sin(2 * np.pi * xx / (weave_px * 2))
    wy = np.sin(2 * np.pi * yy / (weave_px * 2))
    weave = 0.5 + 0.25 * wx + 0.25 * wy
    mott = K.tile_noise(n, 1.4, seed)
    rgb = C(hexcol) * (0.86 + rough * 2 * weave[..., None]) * (0.92 + 0.14 * mott[..., None])
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(weave * 0.6, 2.0), folder)


def stripes_maps(name, folder, a="#d65a52", b="#f4e3c3", stripes=8, n=256, seed=121):
    """Awning canvas: equal stripes across u, with a soft fabric texture."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    band = (np.floor(u * stripes) % 2)[..., None]
    rgb = np.where(band == 0, C(a), C(b))
    mott = K.tile_noise(n, 1.2, seed)
    weave = 0.5 + 0.25 * np.sin(2 * np.pi * xx / 6) + 0.25 * np.sin(2 * np.pi * yy / 6)
    rgb = rgb * (0.9 + 0.1 * mott[..., None]) * (0.95 + 0.08 * weave[..., None])
    return K.save_image(name, rgb, folder), K.save_image(name + "_n", K.normal_from_height(weave * 0.3, 1.5), folder)
