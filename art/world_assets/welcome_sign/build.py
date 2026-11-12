"""The 'Welcome to Maple Grove' sign at the edge of town, built from Alex's reference
(ref/welcome_sign_ref.png, 2026-11-12): two square timber posts on mossy stone feet, iron bands with
bolts, a gable of thick wooden shingles on two rafters with a ridge cap, a king post with a leaf
sprig, and a carved board hanging between the posts: scalloped top and bottom, a raised cream
border, a maple leaf, 'Welcome to' between two sprigs, 'Maple Grove' in big soft serif letters,
three pines and two flourishes.

Front faces -Y (+Z in Godot), the origin is on the ground under the middle. Measured off the
reference at 2.9 mm a pixel (posts 1.98 m apart, 3.0 m to the ridge).

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/welcome_sign/build.py

The lettering is Superclarendon Bold (macOS), cut out of the system font collection into the temp
folder at build time; the font itself is never stored in the repo, only the geometry.
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

NAME = "welcome_sign"
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")
PROPS = os.path.join(K.PROJECT, "assets", "props")
FONT_TTC = "/System/Library/Fonts/Supplemental/SuperClarendon.ttc"
FONT_FACE = 7  # Superclarendon Black (round 1: Bold read thin)

PX = 0.0029  # metres per reference pixel
POST_X = 1.03  # post centres: their inner edges at 0.88, where make_face.py puts the board's ends
POST_W = 0.34
POST_D = 0.32
STONE_H = 0.32
POST_TOP = 2.02  # the rafters sit on the post tops (round 2)
RAFTER_END = 1.3  # x of the rafters' lower ends (round 4: the eaves overhung twice the reference's)
RAFTER_LOW = 2.04  # their top edge there
APEX = 2.82  # their top edge at the ridge
BOARD_FRONT = -0.07  # the board's front face: tucked behind the posts (their front is at -0.16)
BOARD_T = 0.07
CREAM = "#f3e3b8"


def font_path():
    """Superclarendon Bold as a single .ttf in the temp folder (Blender can't pick a face from a .ttc)."""
    out = os.path.join(tempfile.gettempdir(), "ke_superclarendon_%d.ttf" % FONT_FACE)
    if not os.path.exists(out):
        code = ("from fontTools.ttLib import TTCollection;"
                "c=TTCollection(%r);c.fonts[%d].save(%r)" % (FONT_TTC, FONT_FACE, out))
        subprocess.run(["uv", "run", "--no-project", "--with", "fonttools", "python", "-c", code], check=True)
    return out


# --- textures ------------------------------------------------------------------------------------

def stone_maps(n=256, seed=7):
    """Pale pinkish stone, mottled and chipped, with olive moss creeping up from the bottom (v = 0
    at the ground, 1 at the top: the stones are UV'd with v_from_z)."""
    mott = K.tile_noise(n, 1.5, seed)
    fine = K.tile_noise(n, 0.9, seed + 3)
    yy, xx = np.mgrid[0:n, 0:n]
    v = 1 - yy / n
    rgb = CL.mix(CL.C("#988c88"), CL.C("#cfc4bc"), np.clip(mott * 1.3 - 0.15, 0, 1)[..., None])
    rgb = rgb * (0.9 + 0.18 * fine[..., None])
    blot = K.tile_noise(n, 1.2, seed + 11)
    moss = np.clip((0.5 - v) * 3.0 + (blot - 0.6) * 4.0, 0, 1)
    moss = np.where(v < 0.6, moss, 0.0)
    rgb = CL.mix(rgb, CL.mix(CL.C("#6f7d34"), CL.C("#9aa84a"), fine[..., None]), moss[..., None])
    hgt = 0.6 * mott + 0.3 * fine + 0.2 * moss
    return K.save_image("sign_stone", rgb, TEX), K.save_image("sign_stone_n", K.normal_from_height(hgt, 2.2), TEX)


def materials():
    M = {}
    i, n = CL.plank_maps("sign_post", TEX, base="#b9703f", light="#d39461", dark="#8d5230", knots=0, seed=31)
    M["post"] = K.textured("sign_post", i, rough=0.72, normal=n, normal_strength=0.7)
    i, n = CL.plank_maps("sign_rafter", TEX, base="#c27c48", light="#dca06c", dark="#985d33", knots=0, seed=37)
    M["rafter"] = K.textured("sign_rafter", i, rough=0.72, normal=n, normal_strength=0.7)
    i, n = CL.plank_maps("sign_board", TEX, base="#99492a", light="#b8653a", dark="#6a301a", knots=2, seams=3, seed=43)
    M["board"] = K.textured("sign_board", i, rough=0.75, normal=n, normal_strength=0.8)
    i, n = CL.plank_maps("sign_shingle", TEX, base="#bf6a45", light="#d68a62", dark="#94503a", knots=0, seed=53)
    M["shingle"] = K.textured("sign_shingle", i, rough=0.88, normal=n, normal_strength=0.2)
    i, n = stone_maps()
    M["stone"] = K.textured("sign_stone", i, rough=0.92, normal=n, normal_strength=1.0)
    M["cream"] = K.plain("sign_cream", CREAM, rough=0.55)
    M["leaf"] = K.plain("sign_leaf", "#e8642f", rough=0.6)
    M["leaf_vein"] = K.plain("sign_leaf_vein", "#b8441e", rough=0.6)
    # the board's face, flattened out of Alex's reference by make_face.py (lettering, leaf, sprigs,
    # pines, flourishes and the cream border, exactly as drawn)
    face = bpy.data.images.load(os.path.join(TEX, "board_face.png"))
    face_n = bpy.data.images.load(os.path.join(TEX, "board_face_normal.png"))
    M["face"] = K.textured("sign_face", face, rough=0.7, normal=face_n, normal_strength=1.0)
    M["iron"] = K.plain("sign_iron", "#7d7570", rough=0.55)
    bolt = K.plain("sign_bolt", "#c9c5c2", rough=0.28)
    bolt.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.85
    M["bolt"] = bolt
    return M


# --- shapes --------------------------------------------------------------------------------------

def piped(name, pts, width, height, normal, mat, round_ends=True):
    """A raised cream trim line along pts (Vectors on a surface whose outward normal is `normal`):
    a half-oval section like piped icing, the way the reference's border and scrolls stand off the
    wood."""
    normal = Vector(normal).normalized()
    pts = [Vector(p) for p in pts]
    sides = 8
    verts, faces, uvs = [], [], []
    n = len(pts)
    ring = sides + 1
    run = [0.0]
    for a, b in zip(pts, pts[1:]):
        run.append(run[-1] + (b - a).length)
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        side = t.cross(normal).normalized()
        w = width / 2
        if round_ends:
            end = min(run[i], run[-1] - run[i])
            w *= min(1.0, 0.45 + end / (width * 1.2))
        for j in range(ring):
            a = math.pi * j / sides  # 0..pi over the top
            verts.append(p + side * (math.cos(a) * w) + normal * (math.sin(a) * height - 0.002))
    for i in range(n - 1):
        for j in range(sides):
            a0, a1 = i * ring + j, i * ring + j + 1
            b0, b1 = (i + 1) * ring + j, (i + 1) * ring + j + 1
            faces.append((a0, b0, b1, a1))  # wound to face away from the surface
            uvs += [(j / sides, run[i] * 4), (j / sides, run[i + 1] * 4), ((j + 1) / sides, run[i + 1] * 4), ((j + 1) / sides, run[i] * 4)]
    return CL._finish_mesh(name, verts, faces, uvs, mat, recalc=False)


def flat_shape(name, outline, y_front, depth, mat, bevel=0.004):
    """A flat cut-out (leaf, tree, maple leaf) standing `depth` proud of a board whose front face
    is at y = y_front. outline: (x, z) points, counter-clockwise seen from the front."""
    return K.uv_box(K.extrude_xz(name, outline, y_front - depth, y_front + 0.004, mat, bevel=bevel), 6.0)


def ellipse_leaf(cx, cz, length, width, angle, steps=14):
    """An almond leaf outline pointing along `angle` (degrees, 0 = +x), base at (cx, cz)."""
    a = math.radians(angle)
    d, s = Vector((math.cos(a), math.sin(a))), Vector((-math.sin(a), math.cos(a)))
    pts = []
    for i in range(steps):
        t = math.pi * 2 * i / steps
        u = (1 - math.cos(t)) / 2  # 0 base .. 1 tip
        w = math.copysign(width / 2 * math.sin(math.pi * u) ** 1.2, math.sin(t))
        p = Vector((cx, cz)) + d * (u * length) + s * w
        pts.append((p.x, p.y))
    return pts


def sprig(prefix, base, up_angle, size, y_front, mat, mirror=1, leaves=5):
    """Three almond leaves on a short curved stem (the reference's sprigs beside 'Welcome to' and on
    the king post)."""
    bx, bz = base
    a = math.radians(up_angle)
    tip = Vector((bx + math.cos(a) * size, bz + math.sin(a) * size))
    stem = [Vector((bx, y_front, bz)).lerp(Vector((tip.x, y_front, tip.y)), t) + Vector((0.012 * size * math.sin(math.pi * t) * mirror, 0, 0)) for t in np.linspace(0, 1, 7)]
    piped(prefix + "_stem", stem, 0.022 * size / 0.2, 0.009, (0, -1, 0), mat)
    # five full leaves up a curved stem (round 2: three thin ones read as a dragonfly)
    for k, (t, off, ln) in enumerate(((1.0, 0, 0.42), (0.7, 50, 0.38), (0.7, -50, 0.38), (0.35, 55, 0.34), (0.35, -55, 0.34))[:leaves]):
        p = Vector((bx, bz)).lerp(tip, t)
        flat_shape("%s_leaf%d" % (prefix, k), ellipse_leaf(p.x, p.y, ln * size, 0.55 * ln * size, up_angle + off * mirror), y_front, 0.012, mat)


def maple_leaf_outline(cx, cz, r, n=120):
    """A stylised maple leaf: five pointed lobes (the top one tallest), toothed edges."""
    pts = []
    for i in range(n):
        th = math.pi / 2 + 2 * math.pi * i / n
        lobe = abs(math.cos(2.5 * (th - math.pi / 2))) ** 3.5
        teeth = 0.2 * abs(math.cos(12.5 * (th - math.pi / 2))) ** 10
        rr = r * (0.45 + 0.55 * lobe + teeth * (1 - lobe))
        if math.sin(th) < -0.55:  # the notch either side of the stem is deeper
            rr *= 0.8
        pts.append((cx + rr * math.cos(th), cz + rr * math.sin(th) * 0.95))
    return pts


def pine_outline(cx, base_z, h, w):
    """A three-tier pine with a stub trunk, flat (counter-clockwise from the bottom left)."""
    trunk = h * 0.14
    tw = w * 0.14
    pts = [(cx - tw / 2, base_z), (cx + tw / 2, base_z), (cx + tw / 2, base_z + trunk)]
    tiers = [(0.0, 1.0), (0.32, 0.78), (0.6, 0.55)]
    right = []
    for k, (z0, ww) in enumerate(tiers):
        zb = base_z + trunk + (h - trunk) * z0
        zt = base_z + trunk + (h - trunk) * (z0 + 0.5)
        right += [(cx + w / 2 * ww, zb), (cx + w * 0.16 * ww, zb + (zt - zb) * 0.55)]
    top = (cx, base_z + h)
    left = [(2 * cx - x, z) for x, z in reversed(right)]
    pts += right + [top] + left + [(cx - tw / 2, base_z + trunk)]
    return pts


def scroll(name, start, length, height, rise, curl_dir, y, mat, normal=(0, -1, 0), width=0.03, flip=1, slope=0.0):
    """An S-shaped flourish with a curled end (the cream scrolls on the rafters and under the board).
    Drawn in the board's plane, along +x (or -x with flip=-1), turned up by `slope` degrees."""
    pts = []
    sx, sz = start
    ca, sa = math.cos(math.radians(slope)), math.sin(math.radians(slope))
    for t in np.linspace(0, 1, 26):
        x = t * length
        z = rise * math.sin(math.pi * 2 * t) * 0.5 * height
        pts.append((x, z))
    # the curl at the far end
    # (a spiral turning on from the S's last direction, tightening as it goes; round 4: a curl that
    # turned back on itself made a blob like a head)
    cx, cz = pts[-1]
    rr = height * 0.55
    turn = 1.55 * math.pi
    for k in range(1, 30):
        s_ = turn * k / 29
        a = -math.pi / 2 + s_
        rk = rr * (1 - 0.6 * s_ / turn)
        pts.append((cx + math.cos(a) * rk, cz + rr + math.sin(a) * rk))
    out = []
    for x, z in pts:
        x *= flip
        out.append(Vector((sx + x * ca - z * sa * flip, y, sz + x * sa * flip + z * ca)))
    return piped(name, out, width, width * 0.3, normal, mat, round_ends=False)  # a flat, even ribbon


def lettering(name, text, size, centre_x, centre_z, y_front, mat, fit_width=None):
    """Raised letters in Superclarendon Bold, centred, standing proud of the board."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = text
    cu.font = bpy.data.fonts.load(font_path())
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = 0.024
    cu.bevel_depth = 0.009
    cu.bevel_resolution = 1
    cu.resolution_u = 4
    ob = bpy.data.objects.new(name, cu)
    K._link(ob)
    ob.rotation_euler = (math.radians(90), 0, 0)  # the text faces -Y
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    mob = K._obj(name, me, mat)
    mob.matrix_world = ob.matrix_world.copy()
    bpy.data.objects.remove(ob)
    bpy.context.view_layer.update()
    xs = [(mob.matrix_world @ v.co).x for v in mob.data.vertices]
    w = max(xs) - min(xs)
    if fit_width and w > fit_width:
        s = fit_width / w
        mob.scale = (s, s, s)
    bpy.context.view_layer.update()
    co = [mob.matrix_world @ v.co for v in mob.data.vertices]
    cx = (min(c.x for c in co) + max(c.x for c in co)) / 2
    cz = (min(c.z for c in co) + max(c.z for c in co)) / 2
    back = max(c.y for c in co)
    # centred where asked, the letters' backs sunk 3 mm into the board's face
    mob.location += Vector((centre_x - cx, (y_front + 0.003) - back, centre_z - cz))
    bpy.context.view_layer.update()
    K.apply_mods(mob)
    bpy.ops.object.select_all(action="DESELECT")
    mob.select_set(True)
    bpy.context.view_layer.objects.active = mob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    K.uv_box(mob, 8.0)
    return mob


# --- the board outline -----------------------------------------------------------------------------

BW = 1.0  # half the board's width (its ends are behind the posts)
B_LOW, B_HIGH = 1.02, 2.18  # its straight top and bottom edges
ARCH_TOP, ARCH_W = 2.56, 0.56  # the bump in the middle of the top edge
DIP_LOW, DIP_W = 0.8, 0.66  # and of the bottom edge


def board_outline(inset=0.0, steps=28):
    """Counter-clockwise from the bottom left: the reference's cartouche, a board with rounded
    corners, a soft S-curved bump up the middle of the top edge and a shallower one down the middle
    of the bottom (round 1: stepped notches read as a saloon sign)."""
    w = BW - inset
    lo, hi = B_LOW + inset, B_HIGH - inset
    rc = 0.1  # corner radius
    pts = []

    def bump(x0, x1, z0, z1, n):
        # smooth S-shoulders (a raised cosine) up to the bump's crown and back down
        # a bell: concave shoulders rising into a round crown (round 2)
        return [(x0 + (x1 - x0) * i / n, z0 + (z1 - z0) * (0.5 - 0.5 * math.cos(2 * math.pi * i / n)) ** 1.15) for i in range(n + 1)]

    def corner(cx, cz, a0, a1, n=6):
        return [(cx + rc * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cz + rc * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
    pts += corner(-w + rc, lo + rc, 180, 270)
    pts += bump(-(DIP_W - inset), DIP_W - inset, lo, DIP_LOW + inset, steps)
    pts += corner(w - rc, lo + rc, 270, 360)
    pts += corner(w - rc, hi - rc, 0, 90)
    pts += bump(ARCH_W - inset, -(ARCH_W - inset), hi, ARCH_TOP - inset, steps)
    pts += corner(-w + rc, hi - rc, 90, 180)
    clean = []
    for p in pts:
        if not clean or math.dist(p, clean[-1]) > 1e-4:
            clean.append(p)
    if math.dist(clean[0], clean[-1]) < 1e-4:
        clean.pop()
    return clean


def build():
    K.reset(NAME)
    M = materials()
    rng = np.random.default_rng(5)

    # stone feet: chunky, a little lopsided, moss at the foot
    for sx in (-1, 1):
        # a chunky, soft-edged block (round 2: per-vertex jitter on the bevel crumpled it like paper)
        st = K.box("stone_%d" % sx, (0.74, 0.62, STONE_H), (sx * POST_X, 0.0, STONE_H / 2), M["stone"], bevel=0.045, seg=3)
        ph = rng.uniform(0, 6.28, 3)
        for v in st.data.vertices:
            c = v.co
            bulge = 1.0 + 0.035 * math.sin(c.x * 9 + ph[0]) * math.sin(c.y * 8 + ph[1]) + 0.02 * math.sin(c.z * 11 + ph[2])
            c.x *= bulge
            c.y *= bulge
            if c.z > 0:
                c.z *= 1.0 + 0.04 * math.sin(c.x * 6 + c.y * 5 + ph[0])
        K.uv_box(st, 1.6, v_from_z=(0.0, STONE_H))
        uvl = st.data.uv_layers.active.data
        for poly in st.data.polygons:  # the top stays clean stone: moss only creeps up the sides
            if poly.normal.z > 0.5:
                for li in poly.loop_indices:
                    uvl[li].uv = (uvl[li].uv[0], 0.7 + 0.25 * (uvl[li].uv[1] % 1.0))
        # post: a square timber, slightly hand-hewn
        # the post runs up into the rafter's underside (round 4: its top showed as a cut stub)
        post_top = RAFTER_LOW - 0.3 + (APEX - RAFTER_LOW) * (1 - POST_X / RAFTER_END) + 0.1
        CL.beam("post_%d" % sx, [(sx * POST_X, 0, STONE_H - 0.04), (sx * POST_X, 0, post_top)],
                POST_W, POST_D, M["post"], sides=16, v_scale=0.9, wave=0.012, seed=3 + sx, square=0.3)
        # iron band and its two bolts
        K.box("band_%d" % sx, (POST_W + 0.05, POST_D + 0.05, 0.27), (sx * POST_X, 0, 0.83), M["iron"], bevel=0.016, seg=2)
        K.ball("band_bolt", 0.06, (sx * POST_X, -(POST_D + 0.05) / 2 - 0.008, 0.83), M["bolt"], scale=(1, 0.55, 1))
        # two bolts up the post, where the board and the rafter are fixed
        K.ball("post_bolt", 0.055, (sx * POST_X, -POST_D / 2 - 0.01, 1.62), M["bolt"], scale=(1, 0.55, 1))

    # rafters: thick beams from past the posts up to the ridge, a cream scroll on each
    slope = math.atan2(APEX - RAFTER_LOW, RAFTER_END)
    rh = 0.3  # rafter depth (up/down): fat, like the reference
    for sx in (-1, 1):
        a = Vector((sx * RAFTER_END, 0, RAFTER_LOW - rh / 2))
        b = Vector((0, 0, APEX - rh / 2))
        b = b + (b - a).normalized() * 0.12  # on past the ridge, into the king post head: no notch
        r = CL.beam("rafter_%d" % sx, [a.lerp(b, t) for t in np.linspace(0, 1, 6)], 0.3, rh, M["rafter"], sides=16, v_scale=0.9, square=0.3)
        # a bolt near the lower end
        e = a.lerp(b, 0.16)
        K.ball("rafter_bolt", 0.042, (e.x, -0.155, e.z), M["bolt"], scale=(1, 0.55, 1))
        # the scroll along the middle of the rafter's face
        s0 = a.lerp(b, 0.36)
        scroll("rafter_scroll_%d" % sx, (s0.x, s0.z - 0.04), 0.46, 0.13, 1.0, 1, -0.152, M["cream"],
               width=0.038, flip=-sx, slope=math.degrees(slope))

    # roof: four thick shingle slabs a side, overhanging the rafters, each higher one standing a
    # step proud of the one below it; a ridge cap over the top
    n_sh = 4
    over = 0.2  # past the rafter's end
    for sx in (-1, 1):
        e = Vector((sx * (RAFTER_END + over * math.cos(slope)), RAFTER_LOW - over * math.sin(slope)))
        r_ = Vector((0.0, APEX))
        length = (r_ - e).length
        d = (r_ - e) / length
        nrm = Vector((sx * math.sin(slope), math.cos(slope)))
        sh_len = length / n_sh + 0.2  # each course laps well over the one below: no gaps
        for k in range(n_sh):
            # thick, chunky slabs (the reference's are about half as thick as the rafter is deep)
            # thick flat planks resting on the rafter (round 1: thin strips with gaps read as loose slats)
            c = e + d * ((k + 0.5) * length / n_sh - 0.1) + nrm * (0.105 + 0.05 * k)  # the top course stops at the ridge
            slab = K.box("shingle", (sh_len, 0.8 + rng.uniform(-0.01, 0.01), 0.24), (c.x, rng.uniform(-0.01, 0.01), c.y),
                         M["shingle"], bevel=0.035, seg=2, rot=(0, sx * math.degrees(slope), 0))
            K.uv_box(slab, 1.2, grain="x")  # grain down the slope, layers across the sawn ends
    # a tent-shaped ridge cap astride both slopes, swallowing the king post's top (round 4: a flat
    # oval floated over the apex)
    cap = K.box("ridge", (0.44, 0.92, 0.44), (0, 0, APEX + 0.25), M["shingle"], bevel=0.06, seg=3, rot=(0, 45, 0))
    K.uv_box(cap, 1.2, grain="x")
    # king post under the ridge, with a sprig, and the hanger down to the board's arch
    # it comes down to meet the board's crown, as in the reference
    # it stands in front of the rafters from the board's crown up into the ridge cap (round 4)
    kp_low, kp_high = 2.17, APEX + 0.05
    K.uv_box(K.box("king_post", (0.32, 0.36, kp_high - kp_low), (0, -0.06, (kp_low + kp_high) / 2), M["post"], bevel=0.035, seg=2), 1.0)
    sprig("king_sprig", (0.0, 2.27), 90, 0.42, -0.241, M["cream"], leaves=3)

    # the board: its outline traced from the reference (tex/board_profile.json), its face the
    # reference's own picture. Alex, 2026-11-12: the words needn't be modelled, get them exactly
    # like the reference. The ends run on flat behind the posts.
    with open(os.path.join(TEX, "board_profile.json")) as f:
        prof = json.load(f)
    xs, top, low = prof["x"], prof["top"], prof["low"]
    inset = 0.004  # keep the soft edge of the picture (a hint of white background) off the face
    end = POST_X  # to the posts' centres
    outline = [(-end, low[0] + inset)] + [(x, z + inset) for x, z in zip(xs, low)] + [(end, low[-1] + inset)]
    outline += [(end, top[-1] - inset)] + [(x, z - inset) for x, z in zip(reversed(xs), reversed(top))] + [(-end, top[0] - inset)]
    board = K.extrude_xz("board", outline, BOARD_FRONT, BOARD_FRONT + BOARD_T, M["board"], bevel=0.012)
    K.uv_box(board, 1.2, grain="x")  # the back and edges: plain planks
    # the front: planar UVs onto the face texture, and its material
    me = board.data
    if "sign_face" not in [m.name for m in me.materials]:
        me.materials.append(M["face"])
    fi = list(me.materials).index(M["face"])
    uvl = me.uv_layers.active.data
    xr, z0, z1 = prof["xr"], prof["z0"], prof["z1"]
    for poly in me.polygons:
        if poly.normal.y < -0.95:
            poly.material_index = fi
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                uvl[li].uv = ((co.x + xr) / (2 * xr), (co.z - z0) / (z1 - z0))

    # finish: join, export, copy into the game
    K.finish(NAME, OUT, max_tris=60000)
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(OUT, NAME + ".glb"), os.path.join(PROPS, NAME + ".glb"))
    print("COPIED", os.path.join(PROPS, NAME + ".glb"))


build()
