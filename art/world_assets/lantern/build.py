"""Storm lantern, copied from Alex's reference render (ref/lantern.png): a chunky, toy-like oil lantern for
Nora's hand. Dark purplish cast iron worn to warm orange on its edges, a round stepped base, a fat amber
glass globe over a brass burner with a flame on its wick tube, two thin wires crossing in an X in front
of (and behind) the globe, two thick side arms riveted in brass at both ends, a vent collar with glowing
slots under a low domed cap, a block on the cap holding a big ring handle, and a knurled brass wick knob.
The lantern only, no ground.

Painted the way the park bench and the mailbox are (art/world_assets/bench_park/build.py): procedural
Cycles shaders, baked onto the model's own UVs. One mesh, `lantern`, one 0-1 atlas, four 1024 px maps:
colour (its alpha is how see-through the glass is), normal, emission, and occlusion/roughness/metallic
(glTF's ORM: G roughness, B metallic). Two materials read them:
- `lantern_mat`, opaque: the iron, the brass, the flame, the slots' light, and the glass's far wall (a
  copy of the globe facing inward, so through the glass you always end on glowing amber);
- `lantern_glass`, alpha-blended: the globe's near wall, so the flame, wick and burner show through it.
Both are single-sided. The globe (both walls), the flame, the slots and, faintly, the burner under the
glass are emissive through the emission map (factor 1, strength 1, no glTF extension): raise the
materials' emission energy in the game for more glow. What gives light is painted nearly black and
carried by the emission, so it looks the same by day and by night.
out/lantern_shaders.blend keeps the shaders for editing.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/lantern/build.py

It writes out/lantern.glb and copies it to assets/props/lantern.glb; then import (see AGENTS.md).
LANTERN_TEX (default 1024) sets the texture size, LANTERN_SAMPLES (default 36) the bake samples. A draft
(LANTERN_TEX below 1024) overwrites out/ and tex/ but is not copied to assets/props: finish with a full
build. LANTERN_DEBUG=1 or 2 bakes the wear's ingredients as colours instead, to look at them on the model.

0.30 m tall, 0.163 m across the arms, 0.131 m across the base. Front -Y here (+Z in Godot): the arms stand
to the left and right and the ring handle stands in their plane; the wick knob is at the front right.
The ORIGIN IS THE INSIDE TOP OF THE RING HANDLE, where her fingers hook through, so the lantern hangs
straight down below it: the base is at z = -0.285, the top of the ring at z = +0.015.
The wire cage is turned 18 degrees on the axis (WIRE_TURN) so that its X faces the camera of the
reference, which looks at the lantern from 18 degrees to the left of its front; set it to 0 for an X
square on the front.
Review renders: review.py beside this file. Export audit: audit.py. Phase log: lantern_log.md.
"""
import importlib.util
import json
import math
import os
import shutil
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import tessellate_polygon

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

_spec = importlib.util.spec_from_file_location("bench_build", os.path.join(os.path.dirname(HERE), "bench_park", "build.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)

NAME = "lantern"
RES = int(os.environ.get("LANTERN_TEX", 1024))
SAMPLES = int(os.environ.get("LANTERN_SAMPLES", 36))
MM = 0.001

# --- measures (millimetres; base at z = 0 while building), read off the reference -------------------
# One pixel is 0.424 mm across and 0.4455 mm of height up the axis (camera 18 deg above); lantern_log.md
# has the readings.
RING_Z, RING_R, RING_TUBE = 258.0, 34.5, 7.5      # ring handle: centre height, centre-line radius, tube radius
ORIGIN_Z = RING_Z + RING_R - RING_TUBE            # 285: the inside top of the ring
GLOBE = [(35.0, 69.0), (38.6, 70.8), (43.2, 75.5), (48.0, 83.5), (51.3, 92.5), (52.3, 101.0), (51.4, 111.0),
         (48.6, 123.0), (44.6, 135.0), (41.0, 145.0), (39.4, 151.0), (39.0, 156.0)]
VENT_R, VENT_Z0, VENT_Z1 = 33.0, 167.6, 190.2     # the vent collar's drum
SLOTS, SLOT_W, SLOT_H, SLOT_Z, SLOT_DEPTH = 10, 6.0, 12.5, 179.2, 3.0
ARM_DEPTH, ARM_BEVEL = 22.0, 6.5                  # the side arms: front to back, and how round their edges are
WIRE_R, WIRE_TILT, WIRE_Z = 2.5, 40.0, 105.0      # the wires: radius, how far each loop leans, its centre height
WIRE_TURN = -18.0                                 # the wire cage is turned on the axis so its X faces the reference's camera
WIRE_CLEAR = (0.3, 4.8)                           # off the glass where they cross: the second passes over the first
KNOB_AZ = 36.0                                    # the wick knob: degrees from the right (+X) toward the front
KNOB_Z = 55.5
RIVET_R, RIVET_H = 6.0, 3.6

IRON = {"dark": "#3a2826", "mid": "#503a3a", "light": "#6e585c", "shade": "#231716"}
WORN = {"dark": "#8c4e2a", "mid": "#b06a3c", "light": "#cf8a56"}
BRASS = {"shade": "#7a4514", "dark": "#b06c1e", "mid": "#d28f33", "light": "#f8c964"}
GLASS = {"dark": "#c05c18", "mid": "#e58424", "light": "#ffb03a", "glow": "#ffbe46", "shine": "#ffe9d2"}
FLAME = {"foot": "#ffa81e", "body": "#ffd83a", "core": "#fff4b0", "tip": "#fc9412"}
SLOT = {"low": "#ffe14a", "high": "#f07f0e"}

ATTRS = ("m_brass", "m_glass", "m_flame", "m_glow", "m_liner", "grain", "gain")
PARTS = []


# --- small geometry helpers (millimetres in, metres out) --------------------------------------------

def tag(ob, brass=0.0, glass=0.0, flame=0.0, glow=0.0, liner=0.0, grain=0.0, gain=1.0):
    """Marks a part for the painter: which material it is, which way its brush strokes run (grain 0:
    round the lantern's axis, 1: up and down, 2: round the ring handle), and how strongly its edges wear.
    Every part also carries `wearv`, 1 on the vertices where the paint is rubbed through (see worn())."""
    K.apply_mods(ob)
    for name, v in zip(ATTRS, (brass, glass, flame, glow, liner, grain, gain)):
        at = ob.data.attributes.new(name, "FLOAT", "POINT")
        at.data.foreach_set("value", [v] * len(ob.data.vertices))
    if "wearv" not in ob.data.attributes:
        ob.data.attributes.new("wearv", "FLOAT", "POINT")
    PARTS.append(ob)
    return ob


def rounded(poly, per=30.0):
    """A polyline [(x, y, corner radius)] with each corner rounded off by its radius. CORNERS collects the
    points of the outward corners (a turned profile runs anticlockwise, so those are its left turns):
    where a casting's paint rubs through first."""
    out = []
    n = len(poly)
    for i, (x, y, rad) in enumerate(poly):
        if rad <= 0 or i in (0, n - 1):
            out.append((x, y))
            continue
        p, a, b = np.array((x, y), float), np.array(poly[i - 1][:2], float), np.array(poly[i + 1][:2], float)
        d0, d1 = p - a, b - p
        l0, l1 = np.linalg.norm(d0), np.linalg.norm(d1)
        d0, d1 = d0 / l0, d1 / l1
        turn = math.acos(float(np.clip(d0 @ d1, -1.0, 1.0)))
        if turn < 1e-3:
            out.append((x, y))
            continue
        t = min(rad * math.tan(turn / 2), 0.48 * l0, 0.48 * l1)
        r = t / math.tan(turn / 2)
        side = 1.0 if d0[0] * d1[1] - d0[1] * d1[0] > 0 else -1.0
        p0 = p - d0 * t
        c = p0 + np.array((-d0[1], d0[0])) * side * r
        a0 = math.atan2(p0[1] - c[1], p0[0] - c[0])
        k = max(2, int(math.ceil(math.degrees(turn) / per)))
        for j in range(k + 1):
            ang = a0 + side * turn * j / k
            q = (c[0] + r * math.cos(ang), c[1] + r * math.sin(ang))
            out.append(q)
            if side > 0:
                CORNERS.add((round(q[0], 4), round(q[1], 4)))
    return out


CORNERS = set()


def worn(ob, prof, more=()):
    """Sets `wearv` on a turned part: 1 on the rings spun from its profile's outward corners, and what
    `more` ((radius, z, weight), ...) gives other profile points, to carry the scuffing further."""
    extra = {(round(r, 4), round(z, 4)): wt for r, z, wt in more}
    flag = [1.0 if (round(r, 4), round(z, 4)) in CORNERS else extra.get((round(r, 4), round(z, 4)), 0.0) for r, z in prof]
    pr = np.array(prof, float) * MM
    at = ob.data.attributes.new("wearv", "FLOAT", "POINT")
    vals = []
    for v in ob.data.vertices:
        d = (pr[:, 0] - math.hypot(v.co.x, v.co.y)) ** 2 + (pr[:, 1] - v.co.z) ** 2
        vals.append(flag[int(np.argmin(d))])
    at.data.foreach_set("value", vals)
    return ob


def arc(cx, cz, r, a0, a1, n):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cz + r * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
            for i in range(n + 1)]


def lathe(name, prof, mat, steps=32, sharp=50):
    """Spins a profile [(radius, z)] (mm) round the axis; listed from the bottom centre outward and up."""
    return K.lathe(name, [(r * MM, z * MM) for r, z in prof], mat, steps=steps, sharp=sharp)


def slab_xz(name, pts, y0, y1, mat, bevel, seg=3):
    """A flat casting: an outline drawn in XZ (mm), given its depth from y0 to y1, its rim rounded over."""
    n = len(pts)
    verts = [(x * MM, y0 * MM, z * MM) for x, z in pts] + [(x * MM, y1 * MM, z * MM) for x, z in pts]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
    ob = B._finish_mesh(name, verts, faces, mat)
    b = ob.modifiers.new("bevel", "BEVEL")
    b.width = bevel * MM
    b.segments = seg
    b.limit_method = "ANGLE"
    b.angle_limit = math.radians(40)
    K.smooth(ob)
    bpy.context.view_layer.update()
    return K.apply_mods(ob)


def tube(name, pts, normal, radius, mat, sides=6):
    """A round wire along a closed flat loop of points (mm) lying in the plane with this normal."""
    n = len(pts)
    nrm = Vector(normal).normalized()
    verts, faces = [], []
    for i in range(n):
        t = (Vector(pts[(i + 1) % n]) - Vector(pts[i - 1])).normalized()
        b = nrm.cross(t).normalized()
        for j in range(sides):
            a = 2 * math.pi * j / sides
            verts.append(tuple((Vector(pts[i]) + (nrm * math.cos(a) + b * math.sin(a)) * radius) * MM))
    for i in range(n):
        for j in range(sides):
            a, b_ = i * sides + j, i * sides + (j + 1) % sides
            c, d = ((i + 1) % n) * sides + (j + 1) % sides, ((i + 1) % n) * sides + j
            faces.append((a, b_, c, d))
    ob = B._finish_mesh(name, verts, faces, mat)
    return K.smooth(ob, keep_sharp=False)


def crisp(ob, angle=40.0):
    """Smooth shading with a hard line wherever two faces meet at more than `angle` degrees."""
    me = ob.data
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.set_sharp_from_angle(angle=math.radians(angle))
    return ob


def rivet(name, loc, mat, front, r=RIVET_R, h=RIVET_H):
    """A dome-headed brass rivet on a front (-Y, front=1) or back (front=-1) face, its foot sunk in."""
    prof = [(r, -3.0), (r, h * 0.34), (r * 0.88, h * 0.80), (r * 0.52, h), (0.0, h)]
    ob = lathe(name, prof, mat, steps=10, sharp=70)
    ob.location = [v * MM for v in loc]
    ob.rotation_euler = (math.radians(90 * front), 0, 0)
    return ob


# --- the parts ---------------------------------------------------------------------------------------

def vent_strip(mat):
    """The vent collar's drum, with a stadium-shaped pocket cut for each slot. Each slot's sector is three
    flat panels side by side: a plain one, one with the slot as a hole in it, a plain one. (Extra points
    along a panel's top and bottom edges don't work: the triangulator joins them into slivers and leaves
    the edge a straight chord across the whole sector, which stood 1.6 mm inside the drum.)"""
    r, z0, z1 = VENT_R, VENT_Z0, VENT_Z1
    step = 2 * math.pi / SLOTS
    half = r * step / 2
    m = 4
    panel = [(-half / 2, z0), (half / 2, z0), (half / 2, z1), (-half / 2, z1)]
    hw = SLOT_W / 2
    hs = SLOT_H / 2 - hw
    hole = [(hw * math.cos(math.pi + math.pi * i / m), SLOT_Z - hs + hw * math.sin(math.pi + math.pi * i / m)) for i in range(m + 1)]
    hole += [(hw * math.cos(math.pi * i / m), SLOT_Z + hs + hw * math.sin(math.pi * i / m)) for i in range(m + 1)]
    sides = [(-half, z0), (-half, z1), (half, z0), (half, z1)]
    flat = panel + hole + sides
    tris = [tuple(t) for t in tessellate_polygon([[Vector((u, v, 0.0)) for u, v in panel], [Vector((u, v, 0.0)) for u, v in hole]])]
    no, nh = len(panel), len(hole)
    tris += [(no + nh, 0, 3), (no + nh, 3, no + nh + 1), (1, no + nh + 2, no + nh + 3), (1, no + nh + 3, 2)]
    nf = len(flat)

    def on_drum(u, v, rad, s):
        a = s * step + u / r
        return Vector((rad * math.sin(a), -rad * math.cos(a), v)) * MM

    verts, faces = [], []
    for s in range(SLOTS):
        base = len(verts)
        verts += [on_drum(u, v, r, s) for u, v in flat]
        verts += [on_drum(u, v, r - SLOT_DEPTH, s) for u, v in hole]
        mid = on_drum(0.0, SLOT_Z, r - SLOT_DEPTH / 2, s)
        for t in tris:
            a, b, c = (verts[base + i] for i in t)
            out = (b - a).cross(c - a).dot(Vector((a.x, a.y, 0.0)))
            faces.append(tuple(base + i for i in (t if out > 0 else t[::-1])))
        for i in range(nh):
            q = [base + no + i, base + no + (i + 1) % nh, base + nf + (i + 1) % nh, base + nf + i]
            a, b, c = verts[q[0]], verts[q[1]], verts[q[2]]
            inward = (b - a).cross(c - a).dot(mid - a)
            faces.append(tuple(q if inward > 0 else q[::-1]))
    me = bpy.data.meshes.new("vent")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(me)
    bm.free()
    return crisp(K._obj("vent", me, mat), 40)


def vent_glow(mat):
    """The light behind the slots: a plain drum the pockets open onto."""
    r, n = VENT_R - SLOT_DEPTH + 0.4, 40       # just behind the pockets' inner rims
    verts, faces = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        verts += [(r * math.cos(a) * MM, r * math.sin(a) * MM, (VENT_Z0 + 0.5) * MM),
                  (r * math.cos(a) * MM, r * math.sin(a) * MM, (VENT_Z1 - 0.5) * MM)]
    for i in range(n):
        a, b = 2 * i, 2 * ((i + 1) % n)
        faces.append((a, b, b + 1, a + 1))
    me = bpy.data.meshes.new("vent_glow")
    me.from_pydata(verts, [], faces)
    ob = K._obj("vent_glow", me, mat)
    return K.smooth(ob, keep_sharp=False)


def arm_outline():
    """The right arm seen from the front: a shoulder leaving the vent collar, a soft corner, a run that
    bows out beside the globe, and a big curve in to the foot on the base collar."""
    cz = 73.0                                   # centre of the lower curve
    pts = [(31.0, 187.5)]
    pts += arc(54.5, 173.5, 14.0, 90, 0, 6)                                     # outer top corner
    outer = B.catmull([(68.5, 173.5), (68.6, 166.0), (69.5, 156.0), (72.5, 140.0), (77.0, 120.0),
                       (80.5, 100.0), (81.5, 86.0), (81.0, cz)], 2)
    pts += outer[1:-1]
    pts += arc(50.5, cz, 30.5, 0, -90, 9)                                       # the big lower curve, outside
    pts += [(30.0, cz - 30.5), (30.0, cz - 9.5)]
    pts += arc(48.5, cz, 9.5, -90, 0, 5)                                        # and inside
    inner = B.catmull([(58.0, cz), (57.6, 86.0), (56.0, 100.0), (52.5, 120.0), (48.2, 140.0),
                       (45.8, 156.0), (45.5, 162.5)], 2)
    pts += inner[1:-1]
    pts += arc(41.5, 162.5, 4.0, 0, 90, 3)                                      # inner top corner
    pts += [(31.0, 166.5)]
    return pts


def globe_r(z):
    """The glass's radius at a height; below it the burner's lip, above it the flange."""
    return float(np.interp(z, [p[1] for p in GLOBE], [p[0] for p in GLOBE]))


def wire_loop(tilt_sign, clear):
    """A wire's centre line: a loop round the glass through the lantern's axis, leaning from high on one
    side to the globe's foot on the other. It lies on the glass all the way round (`clear` off it where
    the two wires cross, at the front and the back), as a real lantern's globe guard does."""
    tl = math.radians(WIRE_TILT) * tilt_sign
    turn = Matrix.Rotation(math.radians(WIRE_TURN), 3, "Z")
    u = turn @ Vector((math.cos(tl), 0.0, math.sin(tl)))
    v = turn @ Vector((0.0, -1.0, 0.0))
    n = 40
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        flat = math.sqrt((math.cos(t) * math.cos(tl)) ** 2 + math.sin(t) ** 2)     # horizontal reach per unit
        off = WIRE_R + WIRE_CLEAR[0] + (clear - WIRE_CLEAR[0]) * math.sin(t) ** 4
        lo, hi = 20.0, 90.0
        for _ in range(40):                                                        # where the loop meets the glass
            rho = (lo + hi) / 2
            if rho * flat > globe_r(WIRE_Z + rho * math.cos(t) * math.sin(tl)) + off:
                hi = rho
            else:
                lo = rho
        pts.append(Vector((0, 0, WIRE_Z)) + (u * math.cos(t) + v * math.sin(t)) * rho)
    return pts, u.cross(v)


def knob_wheel(mat, r=12.5, thick=9.5, teeth=20):
    """The wick knob's knurled wheel, its axis along local Z from 0 to `thick`."""
    n = teeth * 2
    def ring(rad, d):
        return [(rad(i) * math.cos(2 * math.pi * i / n) * MM, rad(i) * math.sin(2 * math.pi * i / n) * MM, d * MM) for i in range(n)]
    knurl = lambda i: r if i % 2 == 0 else r - 1.3  # noqa: E731
    face = lambda i: r - 2.4                        # noqa: E731
    rings = [ring(face, 0.0), ring(knurl, 1.3), ring(knurl, thick - 1.3), ring(face, thick)]
    verts = [v for rg in rings for v in rg]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(3 * n, 4 * n))]
    for k in range(3):
        for i in range(n):
            a, b = k * n + i, k * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    ob = B._finish_mesh("knob_wheel", verts, faces, mat)
    return crisp(ob, 28)


def build(mat):
    """Every part, at its place, tagged for the painter. Millimetres, base on z = 0."""
    iron = dict()
    brass = dict(brass=1.0)

    # --- the base: a fat foot, a second step, a shallow cone, the collar with a bead round its foot
    base = rounded([(0, 0, 0), (65.5, 0, 7.0), (65.5, 10.2, 0), (65.5, 19.5, 6.0), (58.4, 24.6, 0), (58.2, 31.0, 0), (58.2, 37.6, 3.2),
                    (36.6, 46.6, 0), (36.4, 48.4, 0), (36.8, 50.4, 1.2), (35.6, 52.8, 0), (32.8, 53.6, 0),
                    (32.8, 64.4, 1.6), (29.0, 64.6, 0)], per=36.0)
    tag(worn(lathe("base", base, mat, 32), base), **iron)

    # --- the burner: a brass lip the globe stands in, two stepped discs, the wick tube
    burner = rounded([(31.5, 62.6, 0), (35.9, 63.2, 1.4), (35.9, 70.6, 2.4), (30.2, 70.6, 0), (29.6, 68.4, 0),
                      (26.6, 68.4, 0), (26.0, 73.6, 1.6), (19.4, 73.8, 0), (18.6, 77.0, 1.4), (0, 77.2, 0)], per=46.0)
    tag(lathe("burner", burner, mat, 24), **brass)
    tag(K.cyl("wick_tube", 3.7 * MM, 3.5 * MM, 24.0 * MM, (0, 0, 88.0 * MM), mat, verts=12, bevel=0.6 * MM), **brass)

    # --- the flame and the glass round it
    flame = [(0.0, 95.5), (5.2, 96.4), (9.6, 99.2), (12.6, 103.6), (13.6, 108.6), (12.9, 113.6), (11.0, 118.6),
             (8.2, 123.4), (5.4, 127.6), (2.8, 131.2), (0.9, 133.8), (0.0, 135.0)]
    tag(lathe("flame", flame, mat, 16, sharp=80), flame=1.0)
    tag(lathe("globe", GLOBE, mat, 32, sharp=80), glass=1.0)
    # the glass's far wall, seen through the near one: the same shape a hair smaller, facing inward
    liner = lathe("liner", [(r - 0.6, z) for r, z in GLOBE], mat, 32, sharp=80)
    bm = bmesh.new()
    bm.from_mesh(liner.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(liner.data)
    bm.free()
    tag(liner, liner=1.0)

    # --- flange, vent collar, cap
    flange = rounded([(0, 152.6, 0), (44.0, 152.6, 5.5), (44.0, 160.1, 0), (44.0, 167.6, 5.5), (32.6, 167.9, 0)])
    tag(worn(lathe("flange", flange, mat, 32), flange), **iron)
    tag(vent_strip(mat), **iron)
    tag(vent_glow(mat), glow=1.0)
    cap = rounded([(31.5, 189.9, 0), (47.0, 190.5, 4.0), (47.0, 195.0, 0), (47.0, 199.4, 4.6), (40.5, 202.2, 0), (33.0, 207.2, 0),
                   (24.5, 212.0, 0), (15.5, 216.0, 0), (7.5, 218.9, 0), (0.0, 220.0, 0)], per=30.0)
    tag(worn(lathe("cap", cap, mat, 32), cap, more=[(40.5, 202.2, 1.0), (33.0, 207.2, 0.55)]), **iron)

    # --- the block on the crown and the ring through it
    block = [(-13.0, 211.5), (13.0, 211.5)] + arc(6.0, 236.0, 7.0, 0, 90, 4) + arc(-6.0, 236.0, 7.0, 90, 180, 4)
    tag(K.extrude_xz("block", [(x * MM, z * MM) for x, z in block], -12.0 * MM, 12.0 * MM, mat, bevel=3.0 * MM), grain=1.0)
    ring = K.torus("ring", RING_R * MM, RING_TUBE * MM, (0, 0, RING_Z * MM), mat, rot=(90, 0, 0), major=36, minor=10)
    at = ring.data.attributes.new("wearv", "FLOAT", "POINT")      # a long rubbed streak round its outer front
    at.data.foreach_set("value", [1.0 if i % 10 == 1 else 0.0 for i in range(len(ring.data.vertices))])
    tag(ring, grain=2.0, gain=0.3)
    for front in (1, -1):
        tag(rivet("rivet_block", (0.0, -12.0 * front, 225.0), mat, front, r=5.2), **brass)

    # --- the side arms and their rivets
    right = arm_outline()
    for side in (1, -1):
        pts = [(x * side, z) for x, z in right]
        tag(slab_xz("arm", pts, -ARM_DEPTH / 2, ARM_DEPTH / 2, mat, ARM_BEVEL), grain=1.0)
        for front in (1, -1):
            y = -ARM_DEPTH / 2 * front
            tag(rivet("rivet_top", (56.5 * side, y, 174.5), mat, front), **brass)
            tag(rivet("rivet_foot", (47.0 * side, y, 53.0), mat, front), **brass)

    # --- the wires: two tilted loops, the second passing over the first where they cross
    for sign, clear in zip((1, -1), WIRE_CLEAR):
        pts, nrm = wire_loop(sign, clear)
        tag(tube("wire", pts, nrm, WIRE_R, mat, sides=5), grain=1.0, gain=0.12)

    # --- the wick knob, low on the right and turned toward the front
    az = math.radians(KNOB_AZ)
    d = Vector((math.cos(az), -math.sin(az), 0.0))
    rot = (0, 90, -KNOB_AZ)
    def at(rho):
        return tuple(d * rho * MM + Vector((0, 0, KNOB_Z * MM)))
    tag(K.cyl("knob_boss", 6.8 * MM, 6.2 * MM, 6.5 * MM, at(34.0), mat, verts=16, rot=rot, bevel=1.2 * MM), **brass)
    tag(K.cyl("knob_stem", 3.2 * MM, 3.2 * MM, 13.0 * MM, at(43.0), mat, verts=10, rot=rot), **brass)
    wheel = knob_wheel(mat)
    wheel.matrix_world = Matrix.Translation(Vector(at(48.0))) @ Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
    tag(wheel, **brass)
    return PARTS


def floating(parts, tol=0.0005):
    """kiln's attachment check: parts that neither cut into another part nor come within `tol` of one."""
    bpy.context.view_layer.update()
    data = []
    for o in parts:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.transform(o.matrix_world)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        data.append((o.name, BVHTree.FromBMesh(bm), [v.co.copy() for v in bm.verts]))
        bm.free()
    out = []
    for i, (name, tree, pts) in enumerate(data):
        others = [t for j, (_, t, _) in enumerate(data) if j != i]
        if any(tree.overlap(t) for t in others):
            continue
        best = min(min(t.find_nearest(p)[3] for p in pts) for t in others)
        if best > tol:
            out.append((name, round(best * 1000, 2)))
    return out


# --- shaders ----------------------------------------------------------------------------------------

def fmix(g, fac, a, b, kind="FLOAT"):
    n = g.new("ShaderNodeMix", data_type=kind)
    ins = {s.identifier: s for s in n.inputs}
    key = {"FLOAT": "Float", "VECTOR": "Vector"}[kind]
    g.put(ins["Factor_Float"], fac)
    g.put(ins["A_" + key], a)
    g.put(ins["B_" + key], b)
    return [s for s in n.outputs if s.identifier == "Result_" + key][0]


def noise4(g, vec, w, scale, detail=3.0, rough=0.6):
    n = g.new("ShaderNodeTexNoise", noise_dimensions="4D")
    g.put(n.inputs["Vector"], vec)
    g.put(n.inputs["W"], w)
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    return n.outputs[0]


def paint(mat):
    """The whole lantern's paint in one node tree: cast iron, brass, amber glass, the flame and the slots'
    light, each where its parts are tagged. Returns the colour, the bump height, the emission colour and
    the occlusion/roughness/metallic triple."""
    g = B.Nodes(mat)
    lin = B.lin
    pos = g.sep(g.new("ShaderNodeTexCoord").outputs["Object"])
    px, py, pz = pos[0], pos[1], pos[2]
    p = g.xyz(px, py, pz)
    geo = g.new("ShaderNodeNewGeometry")
    true_n = geo.outputs["True Normal"]

    def bevel(radius, lo, hi):
        b = g.new("ShaderNodeBevel", samples=16)
        b.inputs["Radius"].default_value = radius
        return b, g.step(g.math("SUBTRACT", 1.0, g.dot(b.outputs["Normal"], true_n)), lo, hi)

    attr = {n: g.new("ShaderNodeAttribute", attribute_name=n).outputs["Fac"] for n in ATTRS}
    bev, edge = bevel(0.0032, 0.001, 0.05)
    soft = g.step(g.math("SUBTRACT", 1.0, g.dot(geo.outputs["Normal"], true_n)), 0.002, 0.10)
    edge = g.math("MULTIPLY", g.math("MAXIMUM", edge, soft), attr["gain"])
    _, wide = bevel(0.007, 0.002, 0.08)
    wide = g.math("MULTIPLY", wide, attr["gain"])
    up = g.sep(bev.outputs["Normal"])[2]
    face_up = g.sep(true_n)[2]
    ao_n = g.new("ShaderNodeAmbientOcclusion", samples=12, inside=False, only_local=False)
    ao_n.inputs["Distance"].default_value = 0.014
    ao = ao_n.outputs["AO"]

    # brush strokes: round the axis on the turned parts, up and down the arms, round the ring handle
    S, K_ = 230.0, 1.3
    rad = g.math("ADD", g.math("SQRT", g.math("ADD", g.math("MULTIPLY", px, px), g.math("MULTIPLY", py, py))), 1e-5)
    v0 = g.xyz(g.math("MULTIPLY", g.math("DIVIDE", px, rad), K_), g.math("MULTIPLY", g.math("DIVIDE", py, rad), K_),
               g.math("MULTIPLY", pz, S))
    w0 = g.math("MULTIPLY", rad, S)
    v1 = g.xyz(g.math("MULTIPLY", px, S), g.math("MULTIPLY", py, S), g.math("MULTIPLY", pz, S / 7.0))
    rz = g.math("SUBTRACT", pz, RING_Z * MM)
    rad2 = g.math("ADD", g.math("SQRT", g.math("ADD", g.math("MULTIPLY", px, px), g.math("MULTIPLY", rz, rz))), 1e-5)
    v2 = g.xyz(g.math("MULTIPLY", g.math("DIVIDE", px, rad2), K_), g.math("MULTIPLY", g.math("DIVIDE", rz, rad2), K_),
               g.math("MULTIPLY", py, S))
    w2 = g.math("MULTIPLY", rad2, S)
    is1 = g.step(attr["grain"], 0.4, 0.6)
    is2 = g.step(attr["grain"], 1.4, 1.6)
    vec = fmix(g, is2, fmix(g, is1, v0, v1, "VECTOR"), v2, "VECTOR")
    w = fmix(g, is2, fmix(g, is1, w0, 0.0), w2)
    streak = noise4(g, vec, w, 1.0, 3.0, 0.6)
    rag = noise4(g, vec, g.math("ADD", w, 7.3), 2.6, 3.0, 0.65)

    # --- cast iron, worn to orange
    blotch = g.noise(p, 26.0, 3.0, 0.6, 0.4)
    mottle = g.noise(p, 110.0, 3.0, 0.65)
    pit = g.noise(p, 650.0, 2.0, 0.6)
    col = g.mix(g.step(blotch, 0.30, 0.72), lin(IRON["dark"]), lin(IRON["mid"]))
    col = g.mix(g.step(mottle, 0.52, 0.85, 0.0, 0.12), col, lin(IRON["light"]))
    col = g.mix(g.step(streak, 0.56, 0.80, 0.0, 0.14), col, lin(IRON["light"]))
    col = g.mix(g.step(pit, 0.64, 0.85, 0.0, 0.05), col, lin(IRON["shade"]))
    col = g.mix(g.step(face_up, -1.0, 0.1, 0.40, 0.0), col, lin(IRON["shade"]))
    col = g.mix(g.step(face_up, 0.2, 1.0, 0.0, 0.45), col, lin(IRON["light"]))
    col = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.1, -0.8, 0.0, 0.45)), col, lin(IRON["shade"]))
    # wear: a line along every edge, broken into long dashes that run with the brush strokes
    patch = g.step(g.noise(p, 20.0, 2.0, 0.5, 0.6), 0.36, 0.58, 0.15, 1.0)
    # (the bevel node answers at inside corners too: only what stands open to the air wears)
    rim = g.math("MULTIPLY", g.math("MAXIMUM", edge, g.math("MULTIPLY", wide, 0.8)), g.step(ao, 0.55, 0.85))
    line = g.step(rim, 0.12, 0.50)
    dash = g.step(streak, 0.44, 0.60, 0.0, 1.0)
    w1 = g.step(g.math("MULTIPLY", g.math("MULTIPLY", line, patch), dash), 0.25, 0.45)
    # the turned parts' outward corners and the ring's streak: a band whose border the brush strokes fray
    wearv = g.new("ShaderNodeAttribute", attribute_name="wearv").outputs["Fac"]
    band = g.step(g.math("MULTIPLY", wearv, g.math("ADD", g.math("MULTIPLY", rag, 0.9), 0.45)), 0.64, 0.76)
    w1 = g.math("MAXIMUM", w1, g.math("MULTIPLY", band, g.math("MULTIPLY", patch, dash)))
    # and a few long scuffs along the brush strokes, out on the faces
    scuff = g.math("MULTIPLY", g.step(streak, 0.69, 0.77), g.step(g.noise(p, 14.0, 2.0, 0.5, 0.5), 0.48, 0.62))
    scuff = g.math("MULTIPLY", g.math("MULTIPLY", scuff, g.step(ao, 0.55, 0.85)), g.math("MULTIPLY", attr["gain"], 0.7))
    wear = g.math("MAXIMUM", w1, scuff)
    orange = g.mix(g.step(blotch, 0.3, 0.7), lin(WORN["dark"]), lin(WORN["mid"]))
    orange = g.mix(g.step(up, 0.0, 0.8, 0.0, 0.55), orange, lin(WORN["light"]))
    col = g.mix(g.math("MULTIPLY", wear, 0.92), col, orange)
    col = g.mix(g.step(ao, 0.30, 0.92, 0.62, 0.0), col, lin(IRON["shade"]))
    h_iron = g.math("SUBTRACT", g.math("ADD", g.math("MULTIPLY", mottle, 0.5), g.math("MULTIPLY", pit, 0.35)),
                    g.math("MULTIPLY", wear, 0.5))
    rough = g.math("SUBTRACT", 0.56, g.math("MULTIPLY", wear, 0.16))
    metal = g.math("MULTIPLY", wear, 0.25)

    # --- brass: polished, bright where it faces the light
    bl = g.noise(p, 190.0, 3.0, 0.6)
    br = g.mix(g.step(bl, 0.35, 0.75, 0.0, 0.40), lin(BRASS["mid"]), lin(BRASS["dark"]))
    br = g.mix(g.step(up, 0.1, 0.9, 0.0, 0.70), br, lin(BRASS["light"]))
    br = g.mix(g.math("MULTIPLY", edge, 0.55), br, lin(BRASS["light"]))
    br = g.mix(g.step(up, -0.1, -0.9, 0.0, 0.55), br, lin(BRASS["shade"]))
    br = g.mix(g.step(ao, 0.30, 0.90, 0.50, 0.0), br, lin(BRASS["shade"]))

    # --- amber glass: brightest at the flame's height, with a soft window's reflection front and back
    hot = g.math("MULTIPLY", g.step(pz, 0.072, 0.104), g.step(pz, 0.152, 0.116))
    gl = g.mix(hot, lin(GLASS["dark"]), lin(GLASS["mid"]))
    gl = g.mix(g.math("MULTIPLY", g.math("MULTIPLY", hot, hot), 0.6), gl, lin(GLASS["light"]))
    shine = None
    for sx, sy in ((1.0, 1.0), (-1.0, -1.0)):
        ang = g.math("ARCTAN2", g.math("MULTIPLY", px, sx), g.math("MULTIPLY", py, -sy))   # 0 at the front, + to the right
        ang = g.math("ADD", ang, g.math("MULTIPLY", g.math("SUBTRACT", pz, 0.13), 6.0))    # a leaning parallelogram
        big = g.math("MULTIPLY", g.math("MULTIPLY", g.step(ang, -1.02, -0.94), g.step(ang, -0.50, -0.58)),
                     g.math("MULTIPLY", g.step(pz, 0.1165, 0.1205), g.step(pz, 0.1445, 0.1395)))
        small = g.math("MULTIPLY", g.math("MULTIPLY", g.step(ang, 0.62, 0.70), g.step(ang, 0.98, 0.90)),
                       g.math("MULTIPLY", g.step(pz, 0.080, 0.084), g.step(pz, 0.097, 0.092)))
        s = g.math("ADD", g.math("MULTIPLY", big, 0.60), g.math("MULTIPLY", small, 0.30))
        shine = s if shine is None else g.math("MAXIMUM", shine, s)
    amber = gl
    gl = g.mix(g.math("MULTIPLY", shine, 1.4, clamp=True), gl, lin(GLASS["shine"]))
    # see-through at the flame's height, thicker amber above and below it and where the window shines
    gl_alpha = g.math("ADD", g.math("SUBTRACT", 0.64, g.math("MULTIPLY", hot, 0.30)), g.math("MULTIPLY", shine, 0.5), clamp=True)
    # its far wall, lit by the flame
    ln = g.mix(hot, lin(GLASS["dark"]), lin(GLASS["mid"]))
    ln = g.mix(g.math("MULTIPLY", g.math("MULTIPLY", hot, hot), 0.75), ln, lin(GLASS["glow"]))
    ln_emit = g.mix(g.math("ADD", g.math("MULTIPLY", hot, 0.45), 0.55), (0, 0, 0, 1), ln)
    # the glass is lit from inside: most of its colour is emission, so it reads the same by day and by night.
    # Where the window shines the wall is thicker, so there it gives the far wall's light and the shine is
    # paint only: in the dark it doesn't show.
    gl_emit = g.mix(g.math("ADD", g.math("MULTIPLY", hot, 0.20), 0.25), (0, 0, 0, 1), amber)
    gl_emit = g.mix(g.math("MULTIPLY", shine, 1.4, clamp=True), gl_emit, ln_emit)
    gl = g.mix(g.math("SUBTRACT", 0.55, g.math("MULTIPLY", shine, 0.55), clamp=True), gl, (0, 0, 0, 1))

    # --- the flame and the slots' light
    t = g.math("DIVIDE", g.math("SUBTRACT", pz, 0.0955), 0.0395)
    fl = g.mix(g.step(t, 0.02, 0.20), lin(FLAME["foot"]), lin(FLAME["body"]))
    fl = g.mix(g.math("MULTIPLY", g.step(t, 0.10, 0.26), g.step(t, 0.52, 0.34)), fl, lin(FLAME["core"]))
    fl = g.mix(g.step(t, 0.50, 0.95), fl, lin(FLAME["tip"]))
    sl = g.mix(g.step(pz, (SLOT_Z - SLOT_H / 2) * MM, (SLOT_Z + SLOT_H / 2) * MM), lin(SLOT["low"]), lin(SLOT["high"]))

    black = (0.0, 0.0, 0.0, 1.0)
    colour, emit = col, black
    dim = lambda c, k=0.9: g.mix(k, c, black)    # noqa: E731  what gives light is nearly all emission, little paint
    # the burner and the wick tube under the glass catch the flame's light
    lit = g.math("MULTIPLY", g.math("MULTIPLY", g.step(pz, 0.0690, 0.0700), g.step(pz, 0.1010, 0.1000)), g.step(rad, 0.0356, 0.0350))
    br_emit = g.mix(g.math("MULTIPLY", lit, 0.40), black, br)
    for mask, c, e in ((attr["m_brass"], br, br_emit), (attr["m_glass"], gl, gl_emit), (attr["m_flame"], dim(fl), fl),
                       (attr["m_glow"], dim(sl), sl), (attr["m_liner"], dim(ln, 0.8), ln_emit)):
        m = g.step(mask, 0.4, 0.6)
        colour = g.mix(m, colour, c)
        emit = g.mix(m, emit, e)
    is_brass = g.step(attr["m_brass"], 0.4, 0.6)
    is_glass = g.step(attr["m_glass"], 0.4, 0.6)
    is_light = g.math("MAXIMUM", g.math("MAXIMUM", g.step(attr["m_flame"], 0.4, 0.6), g.step(attr["m_glow"], 0.4, 0.6)),
                      g.step(attr["m_liner"], 0.4, 0.6))
    rough = fmix(g, is_light, fmix(g, is_glass, fmix(g, is_brass, rough, 0.27), 0.10), 1.0)
    metal = fmix(g, is_light, fmix(g, is_glass, fmix(g, is_brass, metal, 0.85), 0.0), 0.0)
    height = fmix(g, g.math("MAXIMUM", is_light, is_glass), fmix(g, is_brass, h_iron, g.math("MULTIPLY", bl, 0.12)), 0.0)
    alpha = fmix(g, is_glass, 1.0, gl_alpha)
    if os.environ.get("LANTERN_DEBUG"):            # the wear's ingredients as colours, to look at them on the model
        colour = g.xyz(edge, wide, dash) if os.environ["LANTERN_DEBUG"] == "1" else g.xyz(line, w1, scuff)
    return g, colour, height, emit, g.xyz(1.0, rough, metal), g.xyz(alpha, alpha, alpha)


def save_rgba(name, rgb, alpha, folder):
    """K.save_image with an alpha channel: the colour map, with how see-through the glass is."""
    os.makedirs(folder, exist_ok=True)
    h, w, _ = rgb.shape
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.alpha_mode = "STRAIGHT"
    px = np.ones((h, w, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb[::-1], 0.0, 1.0)
    px[..., 3] = alpha[::-1]
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(folder, name + ".png")
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def final_materials(colour, normal, orm, emit):
    """The two materials the GLB carries. Both read the same four maps."""
    orm.colorspace_settings.name = "Non-Color"
    normal.colorspace_settings.name = "Non-Color"
    mats = []
    for name, glass in (("lantern_mat", False), ("lantern_glass", True)):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        m.use_backface_culling = True
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]

        def tex(img):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = img
            return t

        tc = tex(colour)
        nt.links.new(tc.outputs["Color"], b.inputs["Base Color"])
        nt.links.new(tex(emit).outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.0
        if glass:
            b.inputs["Roughness"].default_value = 0.10
            b.inputs["Metallic"].default_value = 0.0
            nt.links.new(tc.outputs["Alpha"], b.inputs["Alpha"])
            m.surface_render_method = "BLENDED"
        else:
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(tex(orm).outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tex(normal).outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        mats.append(m)
    return mats


def main():
    K.reset(NAME)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.device = "CPU"
    bake_mat = bpy.data.materials.new("lantern_shader")
    bake_mat.use_nodes = True
    parts = build(bake_mat)
    names = sorted({o.name.split(".")[0] for o in parts})
    print("[ke] scene: %d parts: %s" % (len(parts), ", ".join(names)))
    count = {}
    for o in parts:
        count[o.name.split(".")[0]] = count.get(o.name.split(".")[0], 0) + K.tri_count(o)
    print("[ke] triangles: %s" % ", ".join("%s %d" % kv for kv in sorted(count.items(), key=lambda kv: -kv[1])))
    loose = floating(parts)
    print("[ke] attachment: %s" % ("every part touches another" if not loose else "FLOATING (mm): %s" % loose))

    ob = B.join(parts, NAME)
    B.unwrap(ob)
    g, colour, height, emit, orm, alpha = paint(bake_mat)
    ic = bpy.data.images.new("lantern_bake", RES, RES, alpha=False, float_buffer=True)
    inn = bpy.data.images.new("lantern_bake_n", RES, RES, alpha=False, float_buffer=True)
    inn.colorspace_settings.name = "Non-Color"
    w = B.wire_for_bake(g, colour, height, 0.22, ic, inn)
    for n in g.nt.nodes:
        if n.bl_idname == "ShaderNodeBump":
            n.inputs["Distance"].default_value = 0.0012

    def bake_emit(sock):
        for l in list(w["emit"].inputs["Color"].links):
            g.nt.links.remove(l)
        g.put(w["emit"].inputs["Color"], sock)
        return B.bake(ob, g, w, "EMIT", RES)

    maps = {"colour": B.to_srgb(bake_emit(colour))}
    print("[ke] baked colour")
    maps["emit"] = B.to_srgb(bake_emit(emit))
    print("[ke] baked emission")
    maps["orm"] = np.clip(bake_emit(orm), 0.0, 1.0)
    glass_alpha = np.clip(bake_emit(alpha)[..., 0], 0.0, 1.0)
    print("[ke] baked roughness, metallic and the glass's alpha")
    maps["n"] = B.bake(ob, g, w, "NORMAL", RES)
    print("[ke] baked normal")
    for l in list(w["emit"].inputs["Color"].links):       # leave the shaders' file showing the colour
        g.nt.links.remove(l)
    g.nt.links.new(colour, w["emit"].inputs["Color"])
    g.nt.links.new(w["emit"].outputs[0], w["out"].inputs["Surface"])

    out = os.path.join(HERE, "out")
    tex = os.path.join(HERE, "tex")
    os.makedirs(out, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, NAME + "_shaders.blend"), copy=True)

    images = {k: K.save_image("lantern_" + k, v, tex) for k, v in maps.items() if k != "colour"}
    images["colour"] = save_rgba("lantern_colour", maps["colour"], glass_alpha, tex)
    m_main, m_glass = final_materials(images["colour"], images["n"], images["orm"], images["emit"])
    me = ob.data
    glass = np.empty(len(me.vertices), dtype=np.float32)
    me.attributes["m_glass"].data.foreach_get("value", glass)
    me.materials.clear()
    me.materials.append(m_main)
    me.materials.append(m_glass)
    for poly in me.polygons:
        poly.material_index = 1 if glass[poly.vertices[0]] > 0.5 else 0
    for n in ATTRS + ("wearv",):
        me.attributes.remove(me.attributes[n])
    bpy.data.materials.remove(bake_mat)
    for img in list(bpy.data.images):
        if img.name.startswith("lantern_bake"):
            bpy.data.images.remove(img)

    # hang it from the inside top of the ring
    ob.location.z = -ORIGIN_Z * MM
    for o in bpy.context.view_layer.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = NAME
    me.name = NAME

    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    tris = K.tri_count(ob)
    stats = {
        "name": NAME, "triangles": tris, "materials": [m.name for m in me.materials],
        "size_m": [round(float(v), 4) for v in co.max(0) - co.min(0)],
        "min_m": [round(float(v), 4) for v in co.min(0)], "max_m": [round(float(v), 4) for v in co.max(0)],
        "origin": "inside top of the ring handle (0, 0, 0); base at z = %.3f" % (-ORIGIN_Z * MM),
        "texture_px": RES, "images": sorted(i.name for i in bpy.data.images if i.users and i.type == "IMAGE"),
    }
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, NAME + ".blend"))
    glb = os.path.join(out, NAME + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_draco_mesh_compression_enable=False)
    stats["glb_bytes"] = os.path.getsize(glb)
    with open(os.path.join(out, "stats.json"), "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)
    print("[ke] " + json.dumps(stats))
    if RES >= 1024:
        dest = os.path.join(K.PROJECT, "assets", "props", NAME + ".glb")
        shutil.copyfile(glb, dest)
        print("[ke] copied to", dest)
    else:
        print("[ke] draft textures (%d px): not copied to assets/props" % RES)


if __name__ == "__main__":
    main()
