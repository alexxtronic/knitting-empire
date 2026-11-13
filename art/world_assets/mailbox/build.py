"""Mailbox, copied from Alex's reference render (ref/reference.png): a blue street post box with a roof
arched front to back, a mail-slot hood, two arched ribs that run down into four flared legs on plinth
feet, two riveted straps, a door with brass hinges and lock, and a cream flying-envelope decal. The paint
is chipped through to bronze along its edges. The box only, no ground.

Painted the way the park bench is (art/world_assets/bench_park/build.py): procedural Cycles shaders,
baked to a colour and a normal map per material on the model's own UVs. out/mailbox_shaders.blend keeps
the shaders for editing.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/mailbox/build.py

MAILBOX_TEX (default 1024) sets the paint's texture size. 0.46 m wide (0.66 m over the feet), 0.44 m
deep, 1.15 m tall; front -Y here (+Z in Godot), origin at the centre of the base. Then copy
out/mailbox.glb to assets/props/ and import (see AGENTS.md).
"""
import importlib.util
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

_spec = importlib.util.spec_from_file_location("bench_build", os.path.join(os.path.dirname(HERE), "bench_park", "build.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)

NAME = "mailbox"
RES = int(os.environ.get("MAILBOX_TEX", 1024))
BRASS_RES = 256

# --- measures (metres), read off the reference at 0.865 mm a pixel --------------------------------
W2, D2 = 0.23, 0.22           # half the body's width and depth
Z0 = 0.248                    # the body's underside
ZS, RISE = 0.975, 0.175       # where the arched roof springs, and how high it rises
RIB_X = W2 + 0.012            # each rib's centre plane
RIB_TH, RIB_W = 0.044, 0.072  # rib: a flat band, thickness across its path, width along X
RIB_CORNER = 0.42
BANDS = ((0.806, 0.043), (0.279, 0.050))   # straps: centre height, height
FLARE = 0.05                 # how far each foot stands out past its rib
DOOR = (0.39, 0.415, 0.5335)  # width, height, centre height
DOOR_FRONT = -D2 - 0.014      # the door's face
LOCK = (-0.156, 0.562)
HINGES = (0.664, 0.413)

PAINT = {"dark": "#2d4a7e", "mid": "#3a5d98", "light": "#5279bd", "edge": "#7397d2", "shade": "#203660"}
BRONZE = {"dark": "#8a5c32", "mid": "#c08a52", "light": "#e2b37c"}
BRASS = {"dark": "#7a4f28", "mid": "#b37e4b", "light": "#e9b47f", "shade": "#4a2f17"}
CREAM = "#ecd8c6"

# the decal's square on the door (x from, x to, z from, z to) and its image size
DECAL = (-0.16, 0.16, 0.515, 0.67)
DECAL_PX = (640, 310)
S = 0.000865                  # metres per pixel of the reference


# --- the decal: four cream pieces of an envelope and three speed lines ------------------------------

def _ref(vx, vy):
    """A point picked on the 2x crop of the door (ref px 280.., 560..) to reference pixels."""
    return 280 + vx / 2, 560 + vy / 2


ENVELOPE = [  # convex pieces, in crop coordinates
    [(335, 78), (712, 84), (490, 238)],                       # the flap, pointing down
    [(315, 112), (420, 228), (262, 340)],                     # left
    [(722, 118), (668, 348), (565, 232)],                     # right
    [(275, 376), (438, 249), (485, 272), (485, 378)],         # bottom, left of the notch
    [(485, 272), (532, 249), (645, 378), (485, 378)],         # bottom, right of the notch
]
SPEED = [((145, 140), (268, 140)), ((72, 210), (250, 210)), ((148, 280), (235, 280))]
SPEED_R = 15


def decal_image():
    w, h = DECAL_PX
    xs = DECAL[0] + (np.arange(w) + 0.5) / w * (DECAL[1] - DECAL[0])
    zs = DECAL[2] + (np.arange(h) + 0.5) / h * (DECAL[3] - DECAL[2])   # bottom row first, as Blender stores it
    X, Z = np.meshgrid(xs, zs)
    # reference pixels -> crop coordinates (2x)
    vx = ((X / S + 470) - 280) * 2
    vy = ((1357 - Z / S) - 560) * 2
    feather = 1.6
    alpha = np.zeros_like(X)
    for poly in ENVELOPE:
        p = np.array(poly, float)
        # signed distance for a convex polygon: the largest signed distance to its edges' lines
        cx, cy = p.mean(0)
        sd = np.full_like(X, -1e9)
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]
            nx, ny = b[1] - a[1], -(b[0] - a[0])
            n = math.hypot(nx, ny)
            nx, ny = nx / n, ny / n
            if (cx - a[0]) * nx + (cy - a[1]) * ny > 0:   # point the normal outward
                nx, ny = -nx, -ny
            sd = np.maximum(sd, (vx - a[0]) * nx + (vy - a[1]) * ny)
        sd = sd + 3.0                                   # rounded off a little: grow by 3, ease the corners
        alpha = np.maximum(alpha, np.clip(0.5 - sd / feather, 0, 1))
    for (ax, ay), (bx, by) in SPEED:
        t = np.clip(((vx - ax) * (bx - ax) + (vy - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2), 0, 1)
        d = np.hypot(vx - (ax + t * (bx - ax)), vy - (ay + t * (by - ay))) - SPEED_R
        alpha = np.maximum(alpha, np.clip(0.5 - d / feather, 0, 1))
    img = bpy.data.images.new("mailbox_decal", w, h, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    px = np.zeros((h, w, 4), np.float32)
    px[..., 3] = alpha
    img.pixels.foreach_set(px.ravel())
    return img


# --- geometry -----------------------------------------------------------------------------------

def arch(n=14):
    """The roof's outline seen from the side, from the back (y = +D2) over to the front."""
    return [(D2 * math.cos(math.pi * i / n), ZS + RISE * math.sin(math.pi * i / n)) for i in range(n + 1)]


def dense(pts, step=0.03, end=0.004):
    """Samples along a polyline no more than `step` apart, with a ring `end` from each end, so smooth
    shading doesn't bend the long straight runs toward their end caps."""
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.ceil(math.dist(a, b) / step)))
        out += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(1, n + 1)]
    def near(p, q):
        d = math.dist(p, q)
        return (p[0] + (q[0] - p[0]) * end / d, p[1] + (q[1] - p[1]) * end / d)
    return [out[0], near(out[0], out[1])] + out[1:-1] + [near(out[-1], out[-2]), out[-1]]


def rib_path(z_from):
    """A rib's centre line: up the front edge, over the roof, down the back edge."""
    pts = [(-D2, z_from)]
    pts += [(y, z) for y, z in reversed(arch(24))]
    pts += [(D2, z_from)]
    return [(y, z, RIB_TH, RIB_W) for y, z in dense(pts)]


def leg(side, front):
    """A leg below a rib's end: straight down, then out to the side onto its foot."""
    path = B.catmull([(0.0, Z0 + 0.03, 0.068, 0.07), (0.0, 0.20, 0.066, 0.068), (0.008, 0.15, 0.066, 0.068),
                      (0.03, 0.10, 0.07, 0.07), (FLARE, 0.06, 0.078, 0.076)], 5)
    path = [path[0], tuple(a + (b - a) * 0.15 for a, b in zip(path[0], path[1]))] + path[1:]
    ob = B.sweep("leg", path, 0.0, None, corner=0.5)
    ob.rotation_euler = (0, 0, -math.pi / 2 * side)
    ob.location = (side * RIB_X, front * D2, 0)
    return ob


def build(paint, brass, dark):
    pa, br, dk = [], [], []
    # the body: its side outline (with the arched roof) drawn in YZ and given its width
    outline = [(-D2, Z0), (D2, Z0)] + arch(18)
    pa.append(B.extrude_yz("body", outline, -W2, W2, paint, bevel=0.016, seg=3))
    # the ribs and legs, a plinth foot under each leg with a rivet on its face
    for side in (-1, 1):
        rib = B.sweep("rib", rib_path(Z0 - 0.01), side * RIB_X, paint, corner=RIB_CORNER)
        pa.append(rib)
        for front in (-1, 1):
            pa.append(leg(side, front))
            fx = side * (RIB_X + FLARE)
            pa.append(B.foot(fx, front * D2, paint, hx=0.066, hy=0.06, h=0.04, top=0.066, inset=(0.014, 0.014)))
            br.append(B.bolt("rivet", 0.010, 0.007, (fx, front * (D2 + 0.06), 0.021), brass,
                             rot=(-90 * front, 0, 0), steps=10))
    # the two straps round the body, rivets near each end of the front and along each side, and one on
    # each rib's outer face where the strap passes under it
    for zc, h in BANDS:
        pa.append(K.box("band", (2 * W2 + 0.016, 2 * D2 + 0.016, h), (0, 0, zc), paint, bevel=0.006))
        for x in (-0.19, 0.19):
            br.append(B.bolt("rivet", 0.012, 0.008, (x, -D2 - 0.007, zc), brass, rot=(90, 0, 0), steps=10))
        for side in (-1, 1):
            for y in (-0.15, 0.15):
                br.append(B.bolt("rivet", 0.011, 0.007, (side * (W2 + 0.007), y, zc), brass, rot=(0, 90 * side, 0), steps=10))
            for front in (-1, 1):
                br.append(B.bolt("rivet", 0.011, 0.007, (side * (RIB_X + RIB_W / 2 - 0.001), front * D2, zc), brass,
                                 rot=(0, 90 * side, 0), steps=10))
    # the door, standing proud of the front
    dw, dh, dz = DOOR
    pa.append(K.box("door", (dw, 0.03, dh), (0, DOOR_FRONT + 0.015, dz), paint, bevel=0.011, seg=3))
    # the slot hood: a C seen from the side, with cheeks closing its ends
    hood = [(-0.212, 0.978), (-0.276, 0.966), (-0.290, 0.952), (-0.288, 0.934), (-0.272, 0.928), (-0.240, 0.928),
            (-0.240, 0.890), (-0.268, 0.890), (-0.280, 0.881), (-0.277, 0.866), (-0.212, 0.866)]
    cheek = [hood[0], hood[1], hood[2], hood[3], (-0.284, 0.9), hood[8], hood[9], hood[10]]
    pa.append(B.extrude_yz("hood", hood, -0.158, 0.158, paint, bevel=0.007, seg=2))
    for x0, x1 in ((-0.178, -0.156), (0.156, 0.178)):
        pa.append(B.extrude_yz("cheek", cheek, x0, x1, paint, bevel=0.007, seg=2))
    dk.append(K.box("slot", (0.314, 0.004, 0.036), (0, -0.2385, 0.909), dark, bevel=0.0))
    # hinges on the right of the door: a barrel and a leaf each
    for z in HINGES:
        br.append(K.cyl("hinge", 0.011, 0.011, 0.088, (0.199, DOOR_FRONT - 0.006, z), brass, verts=14, bevel=0.003))
        for zz in (z - 0.046, z + 0.046):
            br.append(K.cyl("hinge_cap", 0.0115, 0.006, 0.006, (0.199, DOOR_FRONT - 0.006, zz + (0.003 if zz > z else -0.003)),
                            brass, verts=14, rot=(0, 0, 0) if zz > z else (180, 0, 0)))
        br.append(K.box("hinge_leaf", (0.034, 0.004, 0.072), (0.178, DOOR_FRONT - 0.002, z), brass, bevel=0.0015))
    # the lock: a round brass boss with a keyhole
    lx, lz = LOCK
    br.append(K.cyl("lock", 0.031, 0.027, 0.013, (lx, DOOR_FRONT - 0.006, lz), brass, verts=24, rot=(90, 0, 0),
                    bevel=0.004, seg=3))
    dk.append(K.cyl("keyhole", 0.0068, 0.0068, 0.003, (lx, DOOR_FRONT - 0.0135, lz + 0.003), dark, verts=12, rot=(90, 0, 0)))
    dk.append(K.box("keyhole_slot", (0.005, 0.003, 0.014), (lx, DOOR_FRONT - 0.0135, lz - 0.004), dark, bevel=0.0))
    for o in pa:
        if not o.data.materials:
            o.data.materials.append(paint)
    return pa, br, dk


# --- shaders ------------------------------------------------------------------------------------

def paint_shader(mat, decal):
    """Blue paint: blotchy and mottled, lighter on the roof and up-facing edges, darker underneath and in
    the hollows, chipped through to bronze along the edges, the cream envelope decal on the door."""
    g = B.Nodes(mat)
    (px, py, pz), edge, up, face_up, ao = B.shared_fields(g, 0.012)
    p = g.xyz(px, py, pz)
    lin = B.lin
    blotch = g.noise(p, 6.0, 3.0, 0.6, 0.3)
    mottle = g.noise(p, 26.0, 3.0, 0.65)
    scuff = g.noise(g.xyz(g.math("MULTIPLY", px, 60.0), g.math("MULTIPLY", py, 60.0), g.math("MULTIPLY", pz, 6.0)), 1.0, 2.0, 0.5)
    col = g.mix(g.step(blotch, 0.30, 0.72), lin(PAINT["dark"]), lin(PAINT["mid"]))
    col = g.mix(g.step(mottle, 0.55, 0.85, 0.0, 0.25), col, lin(PAINT["light"]))
    col = g.mix(g.step(scuff, 0.70, 0.86, 0.0, 0.10), col, lin(PAINT["edge"]))
    # the painter's light
    col = g.mix(g.step(face_up, -1.0, 0.1, 0.45, 0.0), col, lin(PAINT["shade"]))
    col = g.mix(g.step(face_up, 0.25, 1.0, 0.0, 0.42), col, lin(PAINT["light"]))
    col = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.2, 0.7, 0.0, 0.75)), col, lin(PAINT["edge"]))
    col = g.mix(g.math("MULTIPLY", edge, g.step(up, -0.1, -0.8, 0.0, 0.45)), col, lin(PAINT["shade"]))
    # the decal, on the door's face only
    u = g.math("DIVIDE", g.math("SUBTRACT", px, DECAL[0]), DECAL[1] - DECAL[0])
    v = g.math("DIVIDE", g.math("SUBTRACT", pz, DECAL[2]), DECAL[3] - DECAL[2])
    tex = g.new("ShaderNodeTexImage", image=decal, extension="CLIP", interpolation="Cubic")
    g.put(tex.inputs["Vector"], g.xyz(u, v, 0.0))
    front = g.step(py, DOOR_FRONT + 0.0035, DOOR_FRONT + 0.0015)
    speck = g.noise(p, 160.0, 2.0, 0.6)
    worn = g.step(g.noise(p, 34.0, 3.0, 0.6), 0.70, 0.76, 1.0, 0.0)
    dfac = g.math("MULTIPLY", g.math("MULTIPLY", tex.outputs["Alpha"], front), worn)
    cream = g.mix(g.step(speck, 0.55, 0.80, 0.0, 0.18), lin(CREAM), lin("#cdb7a3"))
    col = g.mix(dfac, col, cream)
    # chips through to bronze: thick along the edges, now and then on a flat face
    # broken, not a line: an edge chips only where a patchy noise says so, in flecks of all sizes
    chipn = g.noise(p, 30.0, 4.0, 0.7, 0.5)
    patch = g.step(g.noise(p, 9.0, 2.0, 0.5, 0.6), 0.36, 0.50)
    chip = g.step(g.math("MULTIPLY", g.math("MULTIPLY", edge, patch), g.math("ADD", chipn, 0.40)), 0.42, 0.46)
    spot = g.step(g.noise(p, 48.0, 2.0, 0.5), 0.79, 0.81, 0.0, 0.85)
    chip = g.math("MAXIMUM", chip, g.math("MULTIPLY", spot, g.step(chipn, 0.48, 0.62)))
    bronze = g.mix(g.step(mottle, 0.3, 0.7), lin(BRONZE["dark"]), lin(BRONZE["mid"]))
    bronze = g.mix(g.step(up, 0.0, 0.8, 0.0, 0.6), bronze, lin(BRONZE["light"]))
    col = g.mix(chip, col, bronze)
    col = g.mix(g.step(ao, 0.30, 0.92, 0.62, 0.0), col, lin(PAINT["shade"]))
    height = g.math("SUBTRACT", g.math("MULTIPLY", mottle, 0.25), g.math("MULTIPLY", chip, 0.6))
    return g, col, height


def brass_shader(mat):
    """Worn brass: warm, mottled, bright on the domes and edges that face the light, dark underneath."""
    g = B.Nodes(mat)
    (px, py, pz), edge, up, face_up, ao = B.shared_fields(g, 0.004)
    p = g.xyz(px, py, pz)
    lin = B.lin
    blotch = g.noise(p, 40.0, 3.0, 0.6)
    col = g.mix(g.step(blotch, 0.3, 0.7), lin(BRASS["dark"]), lin(BRASS["mid"]))
    # domes and bosses: lit where the surface turns up and toward the viewer's side
    col = g.mix(g.step(up, 0.1, 0.9, 0.0, 0.75), col, lin(BRASS["light"]))
    col = g.mix(g.math("MULTIPLY", edge, 0.5), col, lin(BRASS["light"]))
    col = g.mix(g.step(up, -0.1, -0.9, 0.0, 0.6), col, lin(BRASS["shade"]))
    col = g.mix(g.step(ao, 0.3, 0.9, 0.55, 0.0), col, lin(BRASS["shade"]))
    return g, col, g.math("MULTIPLY", blotch, 0.3)


def main():
    K.reset(NAME)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = B.SAMPLES
    sc.cycles.device = "CPU"
    paint_bake = bpy.data.materials.new("mailbox_paint_shader")
    brass_bake = bpy.data.materials.new("mailbox_brass_shader")
    for m in (paint_bake, brass_bake):
        m.use_nodes = True
    dark = K.plain("mailbox_dark", "#10192a", rough=0.9)
    pa, br, dk = build(paint_bake, brass_bake, dark)
    print("[ke] scene:", len(pa), "paint parts,", len(br), "brass parts,", len(dk), "dark parts")
    paint = B.join(pa, "paint")
    brass = B.join(br, "brass")
    B.unwrap(paint)
    B.unwrap(brass)
    decal = decal_image()
    tex = os.path.join(HERE, "tex")
    out = os.path.join(HERE, "out")
    done = {}
    for ob, mat, label, bump, res in ((paint, paint_bake, "mailbox_paint", 0.25, RES),
                                      (brass, brass_bake, "mailbox_brass", 0.15, BRASS_RES)):
        g, col, height = paint_shader(mat, decal) if ob is paint else brass_shader(mat)
        ic = bpy.data.images.new(label + "_bake", res, res, alpha=False, float_buffer=True)
        inn = bpy.data.images.new(label + "_bake_n", res, res, alpha=False, float_buffer=True)
        inn.colorspace_settings.name = "Non-Color"
        w = B.wire_for_bake(g, col, height, bump, ic, inn)
        done[label] = (ob, B.to_srgb(B.bake(ob, g, w, "EMIT", res)), B.bake(ob, g, w, "NORMAL", res))
        g.nt.links.new(w["emit"].outputs[0], w["out"].inputs["Surface"])
        print("[ke] baked", label)
    os.makedirs(out, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, NAME + "_shaders.blend"), copy=True)
    for label, rough, metal in (("mailbox_paint", 0.55, 0.0), ("mailbox_brass", 0.35, 0.65)):
        ob, colour, normal = done[label]
        m = K.textured(label + "_mat", K.save_image(label, colour, tex), rough=rough,
                       normal=K.save_image(label + "_n", normal, tex), normal_strength=1.0)
        m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = metal
        ob.data.materials[0] = m
    for m in (paint_bake, brass_bake):
        bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.name.endswith("_bake") or img.name.endswith("_bake_n") or img.name == "mailbox_decal":
            bpy.data.images.remove(img)
    K.finish(NAME, out)


if __name__ == "__main__":
    main()
