"""Park bench, copied from Alex's reference render (ref/reference.png): two cast-iron ends with scroll
armrests and curled tops, a centre leg frame, three leaning back slats, four seat planks (the front one
bull-nosed) and dome bolts. The bench only, no ground.

The wood and iron are procedural Cycles shaders (painted grain, light upper edges, soft cavity shadow,
cast-iron mottling) baked onto the model's own UVs as a colour and a normal map per material, because
glTF carries textures, not node trees. out/bench_park_shaders.blend keeps the shaders for editing.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/bench_park/build.py

BENCH_TEX (default 1024) sets the texture size, BENCH_SAMPLES (default 48) the bake samples.
Front faces -Y here (+Z in Godot); about 2.0 m long, 0.78 m deep, 1.0 m tall, seat at 0.44 m.
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

NAME = "bench_park"
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")
RES = int(os.environ.get("BENCH_TEX", 1024))
SAMPLES = int(os.environ.get("BENCH_SAMPLES", 48))

# --- measures (metres) ------------------------------------------------------------------------
END_X = 0.90            # centre plane of each end casting
FRAME_T = 0.10          # casting thickness: the reference is chunky, legs about as thick as they are wide
SEAT_TOP = 0.44
SEAT_T = 0.09           # rear seat boards; the front plank is deeper (0.12) and hangs like an apron
RAIL_TOP = SEAT_TOP - SEAT_T + 0.002
LEAN = math.radians(10.8)   # the back leans this far from upright
BACK_W, BACK_T, BACK_GAP, BACK_Z0 = 0.15, 0.07, 0.016, 0.487

# colours sampled from the reference (sRGB hex)
WOOD = {"dark": "#b4531b", "mid": "#de6f25", "light": "#f18a3a", "edge": "#ffab58", "shade": "#8c3c18"}
IRON = {"dark": "#473735", "mid": "#614e4d", "light": "#7f6a69", "edge": "#aa9596", "shade": "#2e2221"}
STEEL = {"dark": "#6f5d63", "mid": "#917f86", "edge": "#c8b8bd"}


# --- curves ------------------------------------------------------------------------------------

def catmull(ctrl, per=4):
    """Smooth samples through control tuples (any length), `per` samples per span."""
    p = [np.array(c, float) for c in ctrl]
    p = [p[0] * 2 - p[1]] + p + [p[-1] * 2 - p[-2]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for j in range(per):
            t = j / per
            out.append(0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3))
    out.append(p[-2])
    return [tuple(v) for v in out]


def spiral(start, tangent, turn, rc, th, w, turns, per_turn=14):
    """A scroll: from `start` (y, z) heading along `tangent`, curling to the left (turn=+1) or right
    (-1), the centre-line radius, band thickness and band width each running from [0] to [1]."""
    ty, tz = tangent
    n = math.hypot(ty, tz)
    ty, tz = ty / n, tz / n
    ny, nz = (-tz * turn, ty * turn)
    cy, cz = start[0] + ny * rc[0], start[1] + nz * rc[0]
    a0 = math.atan2(start[1] - cz, start[0] - cy)
    steps = max(4, int(round(turns * per_turn)))
    out = []
    for i in range(1, steps + 1):
        s = i / steps
        a = a0 + turn * s * turns * 2 * math.pi
        r = rc[0] + (rc[1] - rc[0]) * s
        out.append((cy + r * math.cos(a), cz + r * math.sin(a), th[0] + (th[1] - th[0]) * s,
                    w[0] + (w[1] - w[0]) * s))
    return out, (cy, cz)


# --- meshes ------------------------------------------------------------------------------------

def _finish_mesh(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return K._obj(name, me, mat)


def sweep(name, samples, x, mat, seg=2, corner=0.6):
    """A bar swept along a path in the YZ plane at `x`. samples: (y, z, thickness in the plane, width
    along X). The section is a rounded rectangle, so the casting reads soft and chunky."""
    verts, faces = [], []
    n = len(samples)
    ring = 4 * (seg + 1)
    for i, (y, z, th, w) in enumerate(samples):
        a, b = samples[max(0, i - 1)], samples[min(n - 1, i + 1)]
        ty, tz = b[0] - a[0], b[1] - a[1]
        d = math.hypot(ty, tz) or 1.0
        ny, nz = -tz / d, ty / d
        hx, hn = w / 2, th / 2
        r = min(hx, hn) * corner
        for k, (sx, sn) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
            for j in range(seg + 1):
                ang = math.pi / 2 * (k + j / seg)
                lx = sx * (hx - r) + r * math.cos(ang)
                ln = sn * (hn - r) + r * math.sin(ang)
                verts.append((x + lx, y + ln * ny, z + ln * nz))
    for i in range(n - 1):
        for j in range(ring):
            a, b = i * ring + j, i * ring + (j + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    faces.append(tuple(range(ring)))
    faces.append(tuple(range((n - 1) * ring, n * ring)))
    ob = _finish_mesh(name, verts, faces, mat)
    return K.smooth(ob, keep_sharp=False)  # plain smooth shading: soft and pillowy, like modelled clay


def extrude_yz(name, pts, x0, x1, mat, bevel=0.014, seg=3):
    """A flat casting: an outline drawn in YZ, given thickness from x0 to x1, its rim rounded over."""
    n = len(pts)
    verts = [(x0, y, z) for y, z in pts] + [(x1, y, z) for y, z in pts]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, i + n, j + n, j))
    ob = _finish_mesh(name, verts, faces, mat)
    b = ob.modifiers.new("bevel", "BEVEL")
    b.width = bevel
    b.segments = seg
    b.limit_method = "ANGLE"
    b.angle_limit = math.radians(38)
    K.smooth(ob)
    bpy.context.view_layer.update()
    return K.apply_mods(ob)


def foot(x, y, mat, hx=0.088, hy=0.118):
    """A plinth foot: a block whose top edge is chamfered up to where the leg leaves it."""
    lv = [(hx, hy, 0.0), (hx, hy, 0.08), (hx - 0.028, hy - 0.034, 0.126)]
    verts = []
    for sx_, sy_, z in lv:
        verts += [(x - sx_, y - sy_, z), (x + sx_, y - sy_, z), (x + sx_, y + sy_, z), (x - sx_, y + sy_, z)]
    faces = [(3, 2, 1, 0), (8, 9, 10, 11)]
    for lvl in range(2):
        for j in range(4):
            a, b = lvl * 4 + j, lvl * 4 + (j + 1) % 4
            faces.append((a, b, b + 4, a + 4))
    ob = _finish_mesh("foot", verts, faces, mat)
    b = ob.modifiers.new("bevel", "BEVEL")
    b.width = 0.009
    b.segments = 2
    b.limit_method = "ANGLE"
    b.angle_limit = math.radians(25)
    K.smooth(ob)
    bpy.context.view_layer.update()
    return K.apply_mods(ob)


def plank(name, length, width, thick, mat, rng, radii=(0.012, 0.012, 0.012, 0.012), seg=2, stations=6):
    """A hand-cut board along X, `width` along local Y (front is -Y), `thick` along local Z. radii are
    the corner radii: front-top, front-bottom, back-bottom, back-top. The section wanders by a
    millimetre or two along its length and the ends are cut a touch off square."""
    hw, ht = width / 2, thick / 2
    corners = ((-1, 1, radii[0], 90), (-1, -1, radii[1], 180), (1, -1, radii[2], 270), (1, 1, radii[3], 0))
    prof = []
    for sy, sz, r, a0 in corners:
        for j in range(seg + 1):
            ang = math.radians(a0 + 90 * j / seg)
            prof.append((sy * (hw - r) + r * math.cos(ang), sz * (ht - r) + r * math.sin(ang)))
    ring = len(prof)
    cr = 0.011
    xs = [-length / 2, -length / 2 + cr] + [(-length / 2 + cr) + (length - 2 * cr) * i / (stations - 1)
                                             for i in range(1, stations - 1)] + [length / 2 - cr, length / 2]
    skew = (rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02))  # the two end cuts
    verts, faces = [], []
    for i, x in enumerate(xs):
        end = i in (0, len(xs) - 1)
        s = (1 - 2 * cr / width, 1 - 2 * cr / thick) if end else (1.0, 1.0)
        dy, dz = rng.uniform(-0.0018, 0.0018), rng.uniform(-0.0012, 0.0012)
        sc = 1.0 + rng.uniform(-0.012, 0.012)
        t = (x + length / 2) / length
        k = skew[0] * (1 - t) ** 6 + skew[1] * t ** 6
        for py, pz in prof:
            verts.append((x + py * k, py * s[0] * sc + dy, pz * s[1] + dz))
    for i in range(len(xs) - 1):
        for j in range(ring):
            a, b = i * ring + j, i * ring + (j + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    faces.append(tuple(range(ring)))
    faces.append(tuple(range((len(xs) - 1) * ring, len(xs) * ring)))
    ob = _finish_mesh(name, verts, faces, mat)
    # the two sawn ends stay flat: a sharp line round each, so the smoothing does not dish them
    last = (len(xs) - 1) * ring
    for e in ob.data.edges:
        a, b = e.vertices
        if (a < ring and b < ring) or (a >= last and b >= last):
            e.use_edge_sharp = True
    K.smooth(ob)
    bpy.context.view_layer.update()
    return K.apply_mods(ob)


def bolt(name, r, h, loc, mat, rot=(0, 0, 0), steps=10):
    """A dome-headed bolt, its axis along local Z."""
    prof = [(r, -0.004), (r * 0.98, h * 0.3), (r * 0.72, h * 0.8), (0.0, h)]
    ob = K.lathe(name, prof, mat, steps=steps, loc=loc, sharp=80)
    ob.rotation_euler = [math.radians(a) for a in rot]
    return ob


def xdisc(name, r, depth, x, y, z, mat, verts=16, bevel=0.006):
    """A short cylinder lying along X: the web behind a scroll, and the eye at its centre."""
    return K.cyl(name, r, r, depth, (x, y, z), mat, verts=verts, rot=(0, 90, 0), bevel=bevel, seg=2)


# --- the bench ---------------------------------------------------------------------------------

def frame_outline(riser):
    """The lower casting seen from the side: two splayed legs, the arch between them, the seat rail,
    and (on the ends) the lobe that rises in front of the seat to carry the arm scroll."""
    pts = [(-0.302, 0.09), (-0.300, 0.20), (-0.298, 0.30)]
    if riser:
        lobe = [(-0.298, 0.36), (-0.300, 0.44), (-0.280, 0.488), (-0.225, 0.502), (-0.172, 0.488),
                (-0.152, 0.44), (-0.150, 0.385)]
        pts += [(y, z) for y, z in catmull(lobe, 3)] + [(-0.148, RAIL_TOP)]
    else:
        pts += [(-0.297, RAIL_TOP)]
    pts += [(0.300, RAIL_TOP), (0.304, 0.30), (0.316, 0.20), (0.330, 0.09), (0.198, 0.09)]
    yc, a, b, z0 = 0.011, 0.187, 0.178, 0.112
    for k in range(0, 11):
        t = math.pi * k / 10
        pts.append((yc + a * math.cos(t), z0 + b * math.sin(t)))
    pts.append((-0.176, 0.09))
    return pts


def back_axis(z):
    """Centre line of the back upright where the slats sit: (y, z)."""
    return 0.280 + (z - 0.60) * math.tan(LEAN), z


def build_geometry(wood, metal):
    rng = random.Random(11)
    parts_wood, parts_metal, steel = [], [], []

    # --- castings: both ends, and a leg frame in the middle
    for x, end in ((-END_X, True), (0.0, False), (END_X, True)):
        t = FRAME_T if end else 0.085
        side = 1 if x >= 0 else -1
        parts_metal.append(extrude_yz("frame", frame_outline(end), x - t / 2, x + t / 2, metal, seg=2))
        for fy in (-0.243, 0.268):
            parts_metal.append(foot(x, fy, metal, hx=0.088 if end else 0.076))
        if not end:
            continue
        # rivets where the rail meets each leg, on the outer face
        for ry in (-0.236, 0.250):
            parts_metal.append(bolt("rivet", 0.021, 0.011, (x + side * (t / 2 - 0.001), ry, RAIL_TOP - 0.038),
                                    metal, rot=(0, 90 * side, 0), steps=8))
        # back upright: out of the rear leg, leaning with the slats, curling backwards at the top
        up = [(0.252, 0.30, 0.10, FRAME_T), (0.251, 0.40, 0.088, FRAME_T)]
        for z, th in ((0.50, 0.080), (0.62, 0.075), (0.76, 0.072), (0.87, 0.070), (0.945, 0.070)):
            y, _ = back_axis(z)
            up.append((y, z, th, FRAME_T))
        path = catmull(up, 3)
        curl, c = spiral(path[-1][:2], (math.sin(LEAN), math.cos(LEAN)), -1, (0.056, 0.018), (0.070, 0.032),
                         (FRAME_T, FRAME_T), 1.1, per_turn=16)
        parts_metal.append(sweep("upright", path + curl, x, metal))
        parts_metal.append(xdisc("curl_web", 0.045, FRAME_T * 0.62, x, c[0], c[1], metal, verts=12))
        parts_metal.append(xdisc("curl_eye", 0.021, FRAME_T + 0.008, x, c[0], c[1], metal, verts=10, bevel=0.005))
        # a rivet through the upright behind each back slat, so the back is not left plain
        for k in range(3):
            zc = BACK_Z0 + (BACK_W / 2 + k * (BACK_W + BACK_GAP)) * math.cos(LEAN)
            ay, _ = back_axis(zc)
            parts_metal.append(bolt("rivet", 0.019, 0.010, (x, ay + 0.035 * math.cos(LEAN), zc - 0.035 * math.sin(LEAN)),
                                    metal, rot=(-90 - math.degrees(LEAN), 0, 0), steps=8))
        # armrest: forward from the upright, a slight rise, then the big scroll down onto the lobe
        ax = x + side * 0.005
        arm = catmull([(0.31, 0.615, 0.046, 0.100), (0.20, 0.636, 0.050, 0.104), (0.08, 0.655, 0.056, 0.112),
                       (-0.05, 0.663, 0.060, 0.120), (-0.15, 0.656, 0.062, 0.126), (-0.23, 0.641, 0.062, 0.128)], 3)
        scroll, c = spiral(arm[-1][:2], (-1.0, 0.0), 1, (0.100, 0.014), (0.062, 0.020), (0.128, 0.118), 1.78,
                           per_turn=16)
        parts_metal.append(sweep("arm", arm + scroll, ax, metal))
        parts_metal.append(xdisc("scroll_web", 0.070, 0.076, ax, c[0], c[1], metal, verts=16))
        parts_metal.append(xdisc("scroll_eye", 0.022, 0.130, ax, c[0], c[1], metal, verts=12))
        # a raised bead following the arch, as on the reference casting
        yc, a, b, z0 = 0.011, 0.187 + 0.032, 0.178 + 0.032, 0.112
        bead = [(yc + a * math.cos(math.pi * k / 10), z0 + b * math.sin(math.pi * k / 10), 0.020, t + 0.016)
                for k in range(1, 10)]
        parts_metal.append(sweep("bead", bead, x, metal, seg=1, corner=0.9))

    # --- seat: a deep bull-nosed front plank that stops inside the end castings, three boards behind it
    p = plank("seat_front", 2 * END_X + 0.01, 0.16, 0.12, wood, rng, radii=(0.046, 0.032, 0.012, 0.012), seg=3)
    p.location = (0, -0.245, SEAT_TOP - 0.06)
    p.rotation_euler = (rng.uniform(-0.006, 0.006), 0, rng.uniform(-0.0015, 0.0015))
    parts_wood.append(p)
    seat_y = [-0.245]
    z = SEAT_TOP - SEAT_T / 2
    for i, y in enumerate((-0.1005, 0.0165, 0.1335)):
        p = plank("seat", 2 * END_X + FRAME_T + 0.05 + rng.uniform(-0.012, 0.012), 0.105, SEAT_T, wood, rng,
                  radii=(0.016, 0.014, 0.014, 0.016))
        p.location = (rng.uniform(-0.006, 0.006), y, z - 0.003 + rng.uniform(-0.002, 0.002))
        p.rotation_euler = (rng.uniform(-0.008, 0.008), 0, rng.uniform(-0.0015, 0.0015))
        parts_wood.append(p)
        seat_y.append(y)
    for y in seat_y:
        for s in (-1, 1):
            b = bolt("bolt", 0.027, 0.008, (s * (END_X - 0.115), y, SEAT_TOP - 0.004), metal, steps=9)
            parts_metal.append(b)
            steel.append(b)

    # --- back: three wide slats leaning on the uprights, a dome bolt at each end
    ny, nz = -math.cos(LEAN), math.sin(LEAN)
    for k in range(3):
        zc = BACK_Z0 + (BACK_W / 2 + k * (BACK_W + BACK_GAP)) * math.cos(LEAN)
        ay, _ = back_axis(zc)
        off = 0.036 + BACK_T / 2 - 0.006
        p = plank("back", 2 * END_X + FRAME_T + 0.10 + rng.uniform(-0.015, 0.015), BACK_W, BACK_T, wood, rng,
                  radii=(0.017, 0.017, 0.015, 0.015))
        tilt = math.pi / 2 - LEAN + rng.uniform(-0.006, 0.006)
        p.location = (rng.uniform(-0.008, 0.008), ay + ny * off, zc + nz * off)
        p.rotation_euler = (tilt, 0, rng.uniform(-0.0012, 0.0012))
        parts_wood.append(p)
        for s in (-1, 1):
            d = off + BACK_T / 2 - 0.004
            b = bolt("bolt", 0.030, 0.014, (s * (END_X - 0.10), ay + ny * d, zc + nz * d), metal,
                     rot=(math.degrees(math.pi / 2 - LEAN), 0, 0), steps=9)
            parts_metal.append(b)
            steel.append(b)
    return parts_wood, parts_metal, steel


def join(obs, name):
    for o in obs:
        K.apply_mods(o)
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def unwrap(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    # the packed islands leave a third of the square empty; stretching them to fill it costs nothing on a
    # baked texture and gives the boards half as many texels again along their length
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, area_weight=0.0,
                             scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    ob.data.uv_layers[0].name = "UVMap"
    # every face must own some texture: a collapsed UV face bakes as a smear
    uv = ob.data.uv_layers[0].data
    bad = 0
    for poly in ob.data.polygons:
        pts = [uv[i].uv for i in poly.loop_indices]
        area = 0.0
        for i in range(1, len(pts) - 1):
            area += abs((pts[i] - pts[0]).cross(pts[i + 1] - pts[0])) / 2
        bad += area < 1e-9
    print("[ke] uv %s: %d faces, %d collapsed" % (ob.name, len(ob.data.polygons), bad))


# --- shaders -----------------------------------------------------------------------------------

def lin(hexcol):
    return (*[K.srgb_to_lin(c) for c in K.hex_rgb(hexcol)], 1.0)


class Nodes:
    """Small helpers to wire a node tree in code."""

    def __init__(self, mat):
        self.nt = mat.node_tree
        for n in list(self.nt.nodes):
            self.nt.nodes.remove(n)

    def new(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def put(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.nt.links.new(v, sock)
        else:
            sock.default_value = v

    def math(self, op, a, b=None, clamp=False):
        n = self.new("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        return n.outputs[0]

    def step(self, v, lo, hi, out0=0.0, out1=1.0):
        n = self.new("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        self.put(n.inputs["Value"], v)
        n.inputs["From Min"].default_value = lo
        n.inputs["From Max"].default_value = hi
        n.inputs["To Min"].default_value = out0
        n.inputs["To Max"].default_value = out1
        return n.outputs["Result"]

    def mix(self, fac, a, b, blend="MIX"):
        n = self.new("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        ins = {s.identifier: s for s in n.inputs}
        self.put(ins["Factor_Float"], fac)
        self.put(ins["A_Color"], a)
        self.put(ins["B_Color"], b)
        return [s for s in n.outputs if s.identifier == "Result_Color"][0]

    def xyz(self, x, y, z):
        n = self.new("ShaderNodeCombineXYZ")
        for s, v in zip(n.inputs, (x, y, z)):
            self.put(s, v)
        return n.outputs[0]

    def sep(self, v):
        n = self.new("ShaderNodeSeparateXYZ")
        self.put(n.inputs[0], v)
        return n.outputs

    def noise(self, vec, scale, detail=2.0, rough=0.5, distortion=0.0):
        n = self.new("ShaderNodeTexNoise", noise_dimensions="3D")
        self.put(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = distortion
        return n.outputs[0]

    def dot(self, a, b):
        n = self.new("ShaderNodeVectorMath", operation="DOT_PRODUCT")
        self.put(n.inputs[0], a)
        self.put(n.inputs[1], b)
        return n.outputs["Value"]


def shared_fields(g, edge_radius):
    """What both shaders paint with: the position, how much a point sits on a rounded edge, how far
    that edge faces the sky, how far the face itself does, and how open the spot is (cavity)."""
    pos = g.sep(g.new("ShaderNodeTexCoord").outputs["Object"])
    geo = g.new("ShaderNodeNewGeometry")
    bev = g.new("ShaderNodeBevel", samples=6)
    bev.inputs["Radius"].default_value = edge_radius
    edge = g.step(g.math("SUBTRACT", 1.0, g.dot(bev.outputs["Normal"], geo.outputs["True Normal"])), 0.004, 0.16)
    soft = g.step(g.math("SUBTRACT", 1.0, g.dot(geo.outputs["Normal"], geo.outputs["True Normal"])), 0.002, 0.10)
    edge = g.math("MAXIMUM", edge, soft)
    up = g.sep(bev.outputs["Normal"])[2]
    face_up = g.sep(geo.outputs["True Normal"])[2]
    ao = g.new("ShaderNodeAmbientOcclusion", samples=12, inside=False, only_local=False)
    ao.inputs["Distance"].default_value = 0.09
    return pos, edge, up, face_up, ao.outputs["AO"]


def wood_shader(mat):
    """Painted orange wood: long flowing grain lines, broad lighter streaks, a pale upper edge and a
    darker lower edge on every board, soft shadow where boards meet iron. Returns (colour, height)."""
    g = Nodes(mat)
    (px, py, pz), edge, up, face_up, ao = shared_fields(g, 0.012)
    across = g.math("ADD", g.math("MULTIPLY", py, 0.92), g.math("MULTIPLY", pz, 1.0))
    other = g.math("SUBTRACT", g.math("MULTIPLY", py, 0.4), g.math("MULTIPLY", pz, 0.4))
    # grain lines: bands across the board, drawn out along it and bent by a slow noise
    wave = g.new("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X", wave_profile="SIN")
    g.put(wave.inputs["Vector"], g.xyz(across, g.math("MULTIPLY", px, 0.085), other))
    wave.inputs["Scale"].default_value = 4.2
    wave.inputs["Distortion"].default_value = 9.0
    wave.inputs["Detail"].default_value = 2.0
    wave.inputs["Detail Scale"].default_value = 1.1
    wave.inputs["Detail Roughness"].default_value = 0.55
    wfac = wave.outputs[1]
    lines = g.step(wfac, 0.83, 0.99)
    pale = g.step(wfac, 0.30, 0.02)
    # broad tone streaks, and fine fibres, both running along the board
    streak = g.noise(g.xyz(g.math("MULTIPLY", across, 7.0), g.math("MULTIPLY", px, 0.55), g.math("MULTIPLY", other, 7.0)),
                     1.0, 3.0, 0.55)
    fibre = g.noise(g.xyz(g.math("MULTIPLY", across, 55.0), g.math("MULTIPLY", px, 1.6), g.math("MULTIPLY", other, 55.0)),
                    1.0, 2.0, 0.6)
    col = g.mix(g.step(streak, 0.22, 0.62), lin(WOOD["dark"]), lin(WOOD["mid"]))
    col = g.mix(g.step(streak, 0.56, 0.86, 0.0, 0.55), col, lin(WOOD["light"]))
    col = g.mix(g.math("MULTIPLY", pale, 0.16), col, lin(WOOD["light"]))
    col = g.mix(g.math("MULTIPLY", lines, 0.55), col, lin(WOOD["dark"]))
    col = g.mix(g.step(fibre, 0.62, 0.88, 0.0, 0.07), col, lin(WOOD["shade"]))
    # the painter's light: tops a little lighter, undersides darker
    col = g.mix(g.step(face_up, -1.0, 0.2, 0.42, 0.0), col, lin(WOOD["shade"]))
    col = g.mix(g.step(face_up, 0.3, 1.0, 0.0, 0.16), col, lin(WOOD["light"]))
    # edges: pale where they face up, dark where they face down
    col = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.15, 0.75, 0.0, 0.85)), col, lin(WOOD["edge"]))
    col = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.1, -0.8, 0.0, 0.55)), col, lin(WOOD["shade"]))
    # cavities
    col = g.mix(g.step(ao, 0.30, 0.92, 0.62, 0.0), col, lin(WOOD["shade"]))
    height = g.math("SUBTRACT", g.math("MULTIPLY", fibre, 0.35), g.math("MULTIPLY", lines, 1.0))
    return g, col, height


def iron_shader(mat):
    """Painted cast iron: warm dark grey, mottled, a soft pale rim wherever a rounded edge faces the
    light, darker in the hollows. Vertices marked `steel` (the bolt heads in the wood) are pale steel."""
    g = Nodes(mat)
    (px, py, pz), edge, up, face_up, ao = shared_fields(g, 0.02)
    p = g.xyz(px, py, pz)
    blotch = g.noise(p, 5.0, 3.0, 0.6, 0.4)
    mottle = g.noise(p, 22.0, 3.0, 0.65)
    pit = g.noise(p, 130.0, 2.0, 0.6)
    col = g.mix(g.step(blotch, 0.30, 0.72), lin(IRON["dark"]), lin(IRON["mid"]))
    col = g.mix(g.step(mottle, 0.52, 0.85, 0.0, 0.22), col, lin(IRON["light"]))
    col = g.mix(g.step(pit, 0.64, 0.85, 0.0, 0.10), col, lin(IRON["shade"]))
    col = g.mix(g.step(face_up, -1.0, 0.1, 0.38, 0.0), col, lin(IRON["shade"]))
    col = g.mix(g.step(face_up, 0.2, 1.0, 0.0, 0.30), col, lin(IRON["light"]))
    col = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.2, 0.7, 0.0, 0.80)), col, lin(IRON["edge"]))
    col = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.1, -0.8, 0.0, 0.45)), col, lin(IRON["shade"]))
    # steel bolt heads
    attr = g.new("ShaderNodeAttribute", attribute_name="steel")
    st = g.mix(g.step(face_up, -0.6, 0.5), lin(STEEL["dark"]), lin(STEEL["mid"]))
    st = g.mix(g.step(face_up, 0.55, 1.0, 0.0, 0.5), st, lin(STEEL["edge"]))
    st = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.2, 0.6, 0.0, 0.7)), st, lin(STEEL["edge"]))
    col = g.mix(g.step(attr.outputs["Fac"], 0.4, 0.6), col, st)
    col = g.mix(g.step(ao, 0.30, 0.92, 0.60, 0.0), col, lin(IRON["shade"]))
    height = g.math("ADD", g.math("MULTIPLY", mottle, 0.5), g.math("MULTIPLY", pit, 0.35))
    return g, col, height


def wire_for_bake(g, col, height, bump_strength, image_colour, image_normal):
    """Emission carries the colour to the bake; a diffuse surface carries the bumped normal."""
    out = g.new("ShaderNodeOutputMaterial")
    emit = g.new("ShaderNodeEmission")
    g.put(emit.inputs["Color"], col)
    bump = g.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.004
    g.put(bump.inputs["Height"], height)
    diff = g.new("ShaderNodeBsdfDiffuse")
    g.put(diff.inputs["Normal"], bump.outputs["Normal"])
    tc = g.new("ShaderNodeTexImage", image=image_colour)
    tn = g.new("ShaderNodeTexImage", image=image_normal)
    return {"out": out, "emit": emit, "diff": diff, "colour": tc, "normal": tn}


def bake(ob, g, w, kind):
    nt = g.nt
    for l in list(w["out"].inputs["Surface"].links):
        nt.links.remove(l)
    node = w["colour"] if kind == "EMIT" else w["normal"]
    nt.links.new((w["emit"] if kind == "EMIT" else w["diff"]).outputs[0], w["out"].inputs["Surface"])
    for n in nt.nodes:
        n.select = False
    node.select = True
    nt.nodes.active = node
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type=kind, margin=max(4, RES // 128), use_clear=True, normal_space="TANGENT")
    img = node.image
    px = np.empty(RES * RES * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    return px.reshape(RES, RES, 4)[::-1, :, :3]


def to_srgb(a):
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055)


def main():
    K.reset(NAME)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.device = "CPU"
    wood_bake = bpy.data.materials.new("bench_wood_shader")
    iron_bake = bpy.data.materials.new("bench_iron_shader")
    for m in (wood_bake, iron_bake):
        m.use_nodes = True
    pw, pm, steel = build_geometry(wood_bake, iron_bake)
    for o in pm:
        K.apply_mods(o)
        at = o.data.attributes.new("steel", "FLOAT", "POINT")
        at.data.foreach_set("value", [1.0 if o in steel else 0.0] * len(o.data.vertices))
    wood = join(pw, "wood")
    metal = join(pm, "metal")
    unwrap(wood)
    unwrap(metal)

    done = {}
    for ob, mat, make, label, bump in ((wood, wood_bake, wood_shader, "bench_wood", 0.35),
                                       (metal, iron_bake, iron_shader, "bench_iron", 0.22)):
        g, col, height = make(mat)
        ic = bpy.data.images.new(label + "_bake", RES, RES, alpha=False, float_buffer=True)
        inn = bpy.data.images.new(label + "_bake_n", RES, RES, alpha=False, float_buffer=True)
        inn.colorspace_settings.name = "Non-Color"
        w = wire_for_bake(g, col, height, bump, ic, inn)
        colour = to_srgb(bake(ob, g, w, "EMIT"))
        normal = bake(ob, g, w, "NORMAL")
        g.nt.links.new(w["emit"].outputs[0], w["out"].inputs["Surface"])
        done[label] = (ob, colour, normal)
        print("[ke] baked", label)

    # the shaders, kept for editing
    os.makedirs(OUT, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, NAME + "_shaders.blend"), copy=True)

    for label, rough, spec in (("bench_wood", 0.62, 0.35), ("bench_iron", 0.52, 0.45)):
        ob, colour, normal = done[label]
        alb = K.save_image(label, colour, TEX)
        nrm = K.save_image(label + "_n", normal, TEX)
        m = K.textured(label + "_mat", alb, rough=rough, normal=nrm, normal_strength=1.0)
        m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = spec
        ob.data.materials[0] = m
    for m in (wood_bake, iron_bake):
        bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.name.endswith("_bake") or img.name.endswith("_bake_n"):
            bpy.data.images.remove(img)
    K.finish(NAME, OUT)


main()
