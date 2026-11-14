"""The garden birds: a house sparrow, a robin and a herring gull, from ref/birds.png.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/wildlife/birds.py -- <id ...|all> [--render]

Each bird is one soft body (metaballs: the body tilted up to the head) with a beak, glossy eyes, a
tail fan and thin legs. Its folded wings are painted on its sides, as a small bird's are mostly hidden
in its feathers anyway; the open wings are their own meshes on wing bones, tucked away (scaled to
nothing inside the shoulder) while it stands, and spread in flight. Paint is per point, by part
and by where it sits on the bird (u from the beak tip back, v up from the ground, both in units of
the standing bird's height, as measured on the reference's grid), baked to one texture.

Two loops, in place (scripts/bird.gd moves the bird):
  Idle  pecking about: looks left, pecks, looks right, flicks its tail
  Fly   wings spread and flapping, legs tucked back

Writes assets/wildlife/<id>.glb (not Draco-compressed), out/<id>/ and, with --render, review/<id>/.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TEX = 512
THRESH = 0.6
FPS = 30


def srgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def K(stiff):
    return math.sqrt(1.0 - (THRESH / stiff) ** (1.0 / 3.0))


def soft(x, a, b):
    """0 at a, 1 at b, smooth between (a > b runs the other way)."""
    if a == b:
        return 1.0 if x >= a else 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def mix(c1, c2, t):
    a, b = srgb(c1) if isinstance(c1, str) else c1, srgb(c2) if isinstance(c2, str) else c2
    t = max(0.0, min(1.0, t))
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def activate(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


# --- the three birds: shapes measured on ref/birds.png's grid, paints from its colours ----------------

def _sparrow(p):
    c = mix("#d8cdbd", "#e2d8c9", p.n)  # pale buff-grey underneath
    back = soft(p.v, 0.5, 0.62) * soft(p.u, 0.42, 0.55)
    streak = soft(abs(math.sin(p.u * 46.0 + p.n * 3.0)), 0.55, 0.85)
    c = mix(c, mix("#8f5e36", "#3b2a20", streak * 0.8), back)  # the streaky brown back
    side_wing = p.side * soft(p.v, 0.25, 0.4) * soft(p.u, 0.4, 0.52) * soft(p.u, 1.05, 0.95)
    feathers = soft(abs(math.sin(p.u * 30.0 - p.v * 14.0)), 0.75, 0.95)
    c = mix(c, mix("#a8622e", "#4a3022", feathers * 0.7), side_wing)  # the folded wing on the side
    bar = soft(abs(p.u - 0.6 - (p.v - 0.45) * 0.6), 0.025, 0.01) * soft(p.v, 0.36, 0.42) * soft(p.v, 0.56, 0.5)
    c = mix(c, "#efe6d8", side_wing * bar)  # its white wing bar
    head = p.head
    c = mix(c, "#9a5428", head * soft(p.v, 0.74, 0.8) * soft(p.u, 0.18, 0.3))  # chestnut from the eye back
    c = mix(c, "#8e8a88", head * soft(p.v, 0.9, 0.96) * soft(p.u, 0.12, 0.2))  # the grey crown
    c = mix(c, "#ece4d6", head * p.side * soft(p.v, 0.83, 0.77) * soft(p.u, 0.12, 0.2) * soft(p.u, 0.42, 0.34))  # pale cheek
    c = mix(c, "#2c2522", (head + p.breast) * soft(p.v, 0.8, 0.72) * soft(abs(p.x), 0.6, 0.3) * soft(p.u, 0.4, 0.3) * soft(p.v, 0.52, 0.6))  # the black bib
    c = mix(c, "#3a302c", head * soft(abs(p.v - 0.86), 0.03, 0.012) * soft(p.u, 0.12, 0.17) * soft(p.u, 0.3, 0.26))  # eye stripe
    c = mix(c, "#6e4a30", p.tail)
    return c


def _robin(p):
    c = mix("#ece0cc", "#f2e8d8", p.n)  # cream belly
    back = soft(p.v, 0.55, 0.68) * soft(p.u, 0.3, 0.42)  # the brown back, behind the face
    crown = p.head * soft(p.v, 0.9, 0.96)
    c = mix(c, mix("#8a6a46", "#7a5c3c", p.n), max(back, crown))
    side_wing = p.side * soft(p.v, 0.28, 0.42) * soft(p.u, 0.42, 0.55) * soft(p.u, 1.05, 0.95)
    feathers = soft(abs(math.sin(p.u * 28.0 - p.v * 12.0)), 0.75, 0.95)
    c = mix(c, mix("#86643f", "#5a4028", feathers * 0.6), side_wing)
    front = soft(p.u, 0.46, 0.36) * soft(p.v, 0.34, 0.44) * soft(p.v, 0.92, 0.86)
    c = mix(c, "#a9abb2", soft(p.u, 0.52, 0.44) * soft(p.v, 0.3, 0.4) * soft(p.v, 0.96, 0.9) * (1 - crown))  # the grey edge round the red
    c = mix(c, mix("#e66e24", "#f08a3a", p.n), front * (1 - crown))  # the orange face and breast
    c = mix(c, "#6a4a30", p.tail)
    return c


def _gull(p):
    c = mix("#f1efea", "#f8f6f2", p.n)  # white
    mantle = soft(p.v, 0.55, 0.62) * soft(p.u, 0.5, 0.62) * (1.0 - p.head)
    c = mix(c, "#9da3b4", mantle)
    side_wing = p.side * soft(p.v, 0.3, 0.42) * soft(p.u, 0.48, 0.6)
    c = mix(c, mix("#9da3b4", "#8a90a2", p.n), side_wing)
    tips = soft(p.u, 1.0, 1.12) * side_wing
    c = mix(c, "#1f1f24", tips)  # black wing tips
    c = mix(c, "#f4f2ee", tips * soft(abs(math.sin(p.u * 40.0)), 0.92, 0.99))  # with white spots
    c = mix(c, "#f1efea", p.tail * soft(p.v, 0.3, 0.22))
    return c


BIRDS = {
    "sparrow": dict(
        unit=0.2, paint=_sparrow,
        body=(0.58, 0.44, 0.23, 0.44, 0.25, 22), head=(0.31, 0.8, 0.19), neck=(0.42, 0.64, 0.2),
        beak=(0.0, 0.79, 0.14, 0.068, "#46464c", None), eye=(0.25, 0.86, 0.1, 0.042),
        tail=((0.84, 0.34), (1.23, 0.13), 0.1, 0.14, "#6e4a30"), legs=(0.5, 0.18, 0.05, "#a0704a"),
        wing=(0.62, 0.3, "#9a6436", "#d8c8b2", "#4a3022"), flap=0.36, fly_speed=6.0,
    ),
    "robin": dict(
        unit=0.2, paint=_robin,
        body=(0.54, 0.45, 0.26, 0.43, 0.29, 18), head=(0.27, 0.8, 0.19), neck=(0.38, 0.64, 0.22),
        beak=(0.0, 0.82, 0.12, 0.055, "#3e3632", None), eye=(0.23, 0.85, 0.1, 0.045),
        tail=((0.88, 0.31), (1.17, 0.12), 0.09, 0.13, "#6a4a30"), legs=(0.46, 0.17, 0.05, "#8a5a3a"),
        wing=(0.6, 0.3, "#86643f", "#e0d0bc", "#5a4028"), flap=0.34, fly_speed=5.5,
    ),
    "gull": dict(
        unit=0.42, paint=_gull,
        body=(0.68, 0.5, 0.2, 0.5, 0.23, 10), head=(0.33, 0.83, 0.15), neck=(0.46, 0.68, 0.16),
        beak=(0.0, 0.82, 0.22, 0.055, "#f2b630", "#d8402a"), eye=(0.31, 0.88, 0.085, 0.032),
        tail=((0.92, 0.42), (1.33, 0.32), 0.09, 0.12, "#f1efea"), legs=(0.56, 0.28, 0.035, "#e8a594"),
        wing=(1.0, 0.27, "#9da3b4", "#eceae6", "#1f1f24"), flap=0.7, fly_speed=7.0,
    ),
}


class P:
    """What a paint function knows about a point."""
    u = v = x = n = 0.0
    head = breast = tail = side = 0.0


class Bird:
    def __init__(self, sid):
        self.sid = sid
        self.sp = BIRDS[sid]
        self.U = self.sp["unit"]
        self.log = []

    def say(self, s):
        print(s)
        self.log.append(s)

    def Pt(self, u, v, x=0.0):
        """A point of the bird: u back from the beak tip, v up from the ground, x to its left side."""
        return Vector((x * self.U, (u - 0.6) * self.U, v * self.U))

    # --- the body -------------------------------------------------------------------------------------
    def body(self):
        sp, U = self.sp, self.U
        mb = bpy.data.metaballs.new("body")
        mb.resolution = 0.008 * U
        mb.render_resolution = mb.resolution
        mb.threshold = THRESH
        ob = link(bpy.data.objects.new("body", mb))

        def ellip(c, rx, ry, rz, rot=None, stiff=2.0):
            e = mb.elements.new(type="ELLIPSOID")
            e.co = c
            e.radius = 1.0 / K(stiff)
            e.size_x, e.size_y, e.size_z = rx * U, ry * U, rz * U
            e.stiffness = stiff
            if rot is not None:
                e.rotation = rot

        u, v, rx, ry, rz, pitch = sp["body"]
        self.body_c = self.Pt(u, v)
        ellip(self.body_c, rx, ry, rz, Quaternion((1, 0, 0), math.radians(pitch)))
        hu, hv, hr = sp["head"]
        self.head_c = self.Pt(hu, hv)
        ellip(self.head_c, hr * 0.95, hr, hr * 0.97, stiff=2.0)
        nu, nv, nr = sp["neck"]
        ellip(self.Pt(nu, nv), nr * 0.9, nr, nr, stiff=2.0)
        activate(ob)
        bpy.ops.object.convert(target="MESH")
        ob = bpy.context.view_layer.objects.active
        ob.name = "body"
        me = ob.data
        if len(me.polygons) > 3000:
            mod = ob.modifiers.new("dec", "DECIMATE")
            mod.ratio = 3000 / len(me.polygons)
            bpy.ops.object.modifier_apply(modifier=mod.name)
        # soft feather clumps on the outline
        f = 1.0 / (0.06 * U)
        for vx in me.vertices:
            vx.co += vx.normal * 0.008 * U * noise.noise(vx.co * f)
        bpy.ops.object.shade_smooth()
        self.say("BODY %d faces" % len(me.polygons))
        return ob

    def beak(self):
        u, v, length, r, col, spot = self.sp["beak"]
        tip = self.Pt(u, v)
        base = self.Pt(u + length, v + 0.01)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=r * self.U, radius2=0.004 * self.U, depth=(base - tip).length)
        me = bpy.data.meshes.new("beak")
        bm.to_mesh(me)
        bm.free()
        ob = link(bpy.data.objects.new("beak", me))
        d = (tip - base).normalized()
        ob.matrix_world = Matrix.Translation((tip + base) / 2) @ Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4() \
            @ Matrix.Diagonal((1.0, 0.82, 1.0, 1.0))
        activate(ob)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.shade_smooth()
        ob["solid"] = col
        if spot:
            ob["spot"] = spot
            ob["spot_at"] = tuple(tip.lerp(base, 0.3))
        return ob

    def eyes(self):
        u, v, x, r = self.sp["eye"]
        out = []
        for side in (1, -1):
            c = self.Pt(u, v, side * x)
            out_dir = (c - self.head_c).normalized()
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=r * self.U)
            me = bpy.data.meshes.new("eye")
            bm.to_mesh(me)
            bm.free()
            ob = link(bpy.data.objects.new("eye", me))
            hr = self.sp["head"][2] * self.U
            pos = self.head_c + out_dir * (hr * 0.93)
            ob.matrix_world = Matrix.Translation(pos) @ Vector((0, 0, 1)).rotation_difference(out_dir).to_matrix().to_4x4() \
                @ Matrix.Diagonal((1.0, 1.0, 0.6, 1.0))
            activate(ob)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            bpy.ops.object.shade_smooth()
            ob["solid"] = "#141012"
            ob["eye"] = True
            out.append(ob)
        return out

    def tail(self):
        (u0, v0), (u1, v1), w0, w1, col = self.sp["tail"]
        a, b = self.Pt(u0, v0), self.Pt(u1, v1)
        d = (b - a)
        L = d.length
        bm = bmesh.new()
        rows = []
        for i in range(9):
            s = i / 8
            w = (w0 + (w1 - w0) * s) * self.U
            row = []
            for j in range(7):
                t = j / 6 * 2 - 1
                tip_notch = 0.06 * L * (1 - abs(math.cos(t * math.pi * 1.5))) * (s ** 3)  # feather ends
                row.append(bm.verts.new((t * w, s * L - tip_notch, 0.0)))
            rows.append(row)
        for i in range(8):
            for j in range(6):
                bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
        me = bpy.data.meshes.new("tail")
        bm.to_mesh(me)
        bm.free()
        ob = link(bpy.data.objects.new("tail", me))
        sol = ob.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = 0.055 * self.U  # the layered feathers have some depth
        sol.offset = 0.0
        activate(ob)
        bpy.ops.object.modifier_apply(modifier=sol.name)
        for vx in ob.data.vertices:  # deep at the rump (the coverts over and under it), thin at the tip
            s = max(0.0, min(1.0, vx.co.y / L))
            vx.co.z = (1.0 if vx.co.z > 0 else -1.0) * self.U * (0.06 - 0.045 * s)
        ob.matrix_world = Matrix.Translation(a) @ Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.shade_smooth()
        ob["part"] = "tail"
        ob["col"] = col
        self.tail_a, self.tail_b = a, b
        return ob

    def legs(self):
        u, v, r, col = self.sp["legs"]
        out = []
        self.hips = []
        for side in (1, -1):
            hip = self.Pt(u, v, side * 0.1)
            foot = self.Pt(u - 0.02, 0.012, side * 0.12)
            self.hips.append((hip, foot))
            bm = bmesh.new()
            parts = [(hip, foot, r)]
            for ang in (-25, 0, 25):  # three toes forward
                a = math.radians(ang)
                toe = foot + Vector((side * math.sin(a) * 0.12 * self.U, -math.cos(a) * 0.13 * self.U, -0.008 * self.U))
                parts.append((foot, toe, r * 0.6))
            parts.append((foot, foot + Vector((0, 0.09 * self.U, -0.008 * self.U)), r * 0.55))
            for (a, b, rr) in parts:
                d = b - a
                tmp = bmesh.new()
                bmesh.ops.create_cone(tmp, cap_ends=True, segments=8, radius1=rr * self.U, radius2=rr * self.U * 0.8, depth=d.length)
                mat = Matrix.Translation((a + b) / 2) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
                bmesh.ops.transform(tmp, matrix=mat, verts=tmp.verts)
                me_t = bpy.data.meshes.new("t")
                tmp.to_mesh(me_t)
                tmp.free()
                bm.from_mesh(me_t)
                bpy.data.meshes.remove(me_t)
            me = bpy.data.meshes.new("leg")
            bm.to_mesh(me)
            bm.free()
            ob = link(bpy.data.objects.new("leg", me))
            ob["solid"] = col
            ob["side"] = side
            out.append(ob)
        return out

    def wings(self):
        """The open wings, spread out sideways: a broad rounded hand, the trailing edge scalloped by
        the flight feathers. Left wing first (+x)."""
        span, chord, top, under, tips = self.sp["wing"]
        L, C = span * self.U, chord * self.U
        out = []
        self.shoulders = []
        for side in (1, -1):
            sh = self.Pt(self.sp["body"][0] - 0.06, self.sp["body"][1] + 0.12, side * 0.1)
            self.shoulders.append(sh)
            bm = bmesh.new()
            rows, cols = 16, 10
            grid = []
            for i in range(rows + 1):
                s = i / rows
                width = C * (0.55 + 0.45 * math.sin(math.pi * min(1.0, 0.25 + s * 0.85))) * (1.0 - 0.75 * s ** 3)
                lead = -0.3 * width
                scallop = 0.08 * C * abs(math.sin(s * math.pi * 9)) if s > 0.2 else 0.0
                row = []
                for j in range(cols + 1):
                    t = j / cols
                    y = lead + t * (width - scallop * t)
                    z = 0.06 * C * math.sin(math.pi * t) * (1 - s)  # a little arched
                    row.append(bm.verts.new((side * s * L, y, z)))
                grid.append(row)
            for i in range(rows):
                for j in range(cols):
                    f = (grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j])
                    bm.faces.new(f if side > 0 else f[::-1])
            me = bpy.data.meshes.new("wing")
            bm.to_mesh(me)
            bm.free()
            ob = link(bpy.data.objects.new("wing", me))
            sol = ob.modifiers.new("sol", "SOLIDIFY")
            sol.thickness = 0.02 * self.U
            sol.offset = 0.0
            activate(ob)
            bpy.ops.object.modifier_apply(modifier=sol.name)
            ob.matrix_world = Matrix.Translation(sh)
            bpy.ops.object.transform_apply(location=True)
            bpy.ops.object.shade_smooth()
            ob["wing"] = side
            ob["span"] = L
            ob["chord"] = C
            out.append(ob)
        return out

    # --- paint and bake --------------------------------------------------------------------------------
    def paint_body(self, ob):
        me = ob.data
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        hu, hv, hr = self.sp["head"]
        for i, vx in enumerate(me.vertices):
            co = vx.co
            p = P()
            p.u = co.y / self.U + 0.6
            p.v = co.z / self.U
            p.x = co.x / max(1e-6, (self.sp["body"][2] * self.U))
            p.n = 0.5 + 0.5 * noise.noise(co * (1.0 / (0.05 * self.U)))
            dh = (co - self.head_c).length / (hr * self.U)
            p.head = soft(dh, 1.25, 1.0)
            p.breast = soft(p.u, 0.55, 0.4) * soft(p.v, 0.75, 0.62)
            p.side = soft(abs(vx.normal.x), 0.3, 0.6) * (1.0 - p.head)
            p.tail = soft(p.u, 0.95, 1.05)
            c = self.sp["paint"](p)
            # soft feather texture: lighter tips over darker bases
            k = 0.9 + 0.1 * soft(abs(math.sin(p.u * 60 + p.v * 20 + p.n * 4)), 0.3, 0.9)
            attr.data[i].color = (*lin(tuple(x * k for x in c)), 1.0)

    def paint_wing(self, ob):
        me = ob.data
        span, chord, top, under, tips = self.sp["wing"]
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        sh = self.shoulders[0 if ob["wing"] > 0 else 1]
        for i, vx in enumerate(me.vertices):
            co = vx.co - sh
            s = abs(co.x) / ob["span"]
            t = (co.y + 0.3 * ob["chord"]) / ob["chord"]
            dorsal = vx.normal.z > 0
            if dorsal:
                c = mix(top, "#ffffff", 0.0)
                # rows of feathers: coverts near the leading edge, flight feathers behind
                c = mix(c, mix(top, "#2a2020", 0.25), soft(t, 0.35, 0.5))
                edge = soft(abs(math.sin(s * math.pi * 9)), 0.8, 0.97) * soft(t, 0.45, 0.6)
                c = mix(c, under, edge * 0.5)
                c = mix(c, tips, soft(s, 0.7, 0.85) * soft(t, 0.3, 0.5))
            else:
                c = mix(under, top, 0.15 * soft(t, 0.6, 0.9))
                c = mix(c, tips, soft(s, 0.75, 0.9) * soft(t, 0.4, 0.6) * 0.6)
            attr.data[i].color = (*lin(c), 1.0)

    def paint_solid(self, ob, col, spot=None):
        me = ob.data
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        for i, vx in enumerate(me.vertices):
            c = srgb(col)
            if spot and (vx.co - Vector(ob["spot_at"])).length < 0.025 * self.U * 2.2 and vx.co.z < Vector(ob["spot_at"]).z:
                c = srgb(spot)
            attr.data[i].color = (*lin(c), 1.0)

    def paint_tail(self, ob):
        me = ob.data
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        a, b = self.tail_a, self.tail_b
        L = (b - a).length
        for i, vx in enumerate(me.vertices):
            s = (vx.co - a).dot((b - a).normalized()) / L
            c = mix(ob["col"], "#1a1416", 0.25 * soft(s, 0.6, 1.0))
            stripes = soft(abs(math.sin((vx.co - a).cross((b - a).normalized()).length / (0.03 * self.U))), 0.85, 0.98)
            c = mix(c, "#f4ece0", stripes * 0.15)
            attr.data[i].color = (*lin(c), 1.0)

    def bake(self, objs):
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 1
        img = bpy.data.images.new(self.sid + "_color", TEX, TEX, alpha=False)
        aimg = bpy.data.images.new(self.sid + "_ao", TEX, TEX, alpha=False)
        activate(*objs)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        mats = {}
        for ob in objs:
            m = bpy.data.materials.new("bake_" + ob.name)
            m.use_nodes = True
            ob.data.materials.clear()
            ob.data.materials.append(m)
            mats[ob.name] = m

        def setup(target, mode):
            for ob in objs:
                nt = mats[ob.name].node_tree
                nt.nodes.clear()
                out = nt.nodes.new("ShaderNodeOutputMaterial")
                tex = nt.nodes.new("ShaderNodeTexImage")
                tex.image = target
                nt.nodes.active = tex
                if mode == "color":
                    em = nt.nodes.new("ShaderNodeEmission")
                    at = nt.nodes.new("ShaderNodeAttribute")
                    at.attribute_name = "Col"
                    nt.links.new(at.outputs["Color"], em.inputs[0])
                    nt.links.new(em.outputs[0], out.inputs[0])
                else:
                    bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
                    nt.links.new(bs.outputs[0], out.inputs[0])

        setup(img, "color")
        bpy.ops.object.bake(type="EMIT", margin=6, use_clear=True)
        sc.cycles.samples = 32
        sc.world = sc.world or bpy.data.worlds.new("w")
        setup(aimg, "ao")
        wings = [ob for ob in objs if "wing" in ob]
        for ob in wings:  # the open wings cut through the body: out of the way, or they shade a line on it
            ob.location.z += 10.0
        bpy.ops.object.bake(type="AO", margin=6, use_clear=True)
        for ob in wings:
            ob.location.z -= 10.0
        n = TEX * TEX * 4
        c = np.empty(n, np.float32)
        a = np.empty(n, np.float32)
        img.pixels.foreach_get(c)
        aimg.pixels.foreach_get(a)
        c = c.reshape(-1, 4)
        c[:, :3] *= 0.6 + 0.4 * a.reshape(-1, 4)[:, :1]
        img.pixels.foreach_set(c.ravel())
        img.update()
        out = os.path.join(HERE, "out", self.sid)
        os.makedirs(out, exist_ok=True)
        img.filepath_raw = os.path.join(out, self.sid + "_color.png")
        img.file_format = "PNG"
        img.save()
        self.img = img

    def materials(self, objs):
        def mat(name, rough):
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            nt = m.node_tree
            bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = self.img
            nt.links.new(tex.outputs[0], bs.inputs["Base Color"])
            bs.inputs["Roughness"].default_value = rough
            return m
        feathers = mat(self.sid + "_feathers", 0.85)
        gloss = mat(self.sid + "_gloss", 0.2)
        for ob in objs:
            ob.data.materials.clear()
            ob.data.materials.append(gloss if ("eye" in ob or ob.name.startswith("beak")) else feathers)

    # --- rig, skin and loops ---------------------------------------------------------------------------
    def rig(self):
        ad = bpy.data.armatures.new(self.sid + "_rig")
        rig = link(bpy.data.objects.new("rig", ad))
        activate(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        eb = ad.edit_bones
        U = self.U

        def bone(name, a, b, parent=None, roll=0.0):
            e = eb.new(name)
            e.head, e.tail = a, b
            e.roll = roll
            if parent:
                e.parent = eb[parent]
            return e
        root = bone("Root", Vector((0, 0, 0)), Vector((0, 0, 0.1 * U)))
        chest = self.body_c.lerp(self.head_c, 0.35)
        bone("Body", self.body_c, chest, "Root")
        bone("Head", self.head_c.lerp(self.body_c, 0.3), self.head_c + Vector((0, -0.2 * U, 0)), "Body")
        bone("Tail", self.tail_a, self.tail_b, "Body")
        for side, nm in ((1, "Left"), (-1, "Right")):
            sh = self.shoulders[0 if side > 0 else 1]
            bone(nm + "Wing", sh, sh + Vector((side * 0.3 * U, 0, 0)), "Body")
            hip, foot = self.hips[0 if side > 0 else 1]
            bone(nm + "Leg", hip, foot, "Root")
        root.select = True
        bpy.ops.object.mode_set(mode="OBJECT")
        return rig

    def skin(self, rig, body, beak, eyes, tail, legs, wings):
        groups = {}
        objs = [body, beak, tail] + eyes + legs + wings
        for ob in objs:
            for nm in ("Body", "Head", "Tail", "LeftWing", "RightWing", "LeftLeg", "RightLeg"):
                groups[(ob.name, nm)] = ob.vertex_groups.new(name=nm)
        # body: head and tail fade in along the lines out to them
        hd = self.head_c - self.body_c
        td = self.tail_a - self.body_c
        for vx in body.data.vertices:
            t = (vx.co - self.body_c).dot(hd) / hd.length_squared
            wh = soft(t, 0.45, 0.8)
            tt = (vx.co - self.body_c).dot(td) / td.length_squared
            wt = soft(tt, 0.85, 1.15) * (1 - wh)
            wb = 1.0 - wh - wt
            for nm, w in (("Head", wh), ("Tail", wt), ("Body", wb)):
                if w > 0.001:
                    groups[(body.name, nm)].add([vx.index], w, "REPLACE")
        for ob, nm in [(beak, "Head")] + [(e, "Head") for e in eyes] + [(tail, "Tail")] + \
                [(legs[0], "LeftLeg"), (legs[1], "RightLeg"), (wings[0], "LeftWing"), (wings[1], "RightWing")]:
            groups[(ob.name, nm)].add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        activate(*objs)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        ob.name = self.sid
        ob.parent = rig
        mod = ob.modifiers.new("rig", "ARMATURE")
        mod.object = rig
        return ob

    def loops(self, rig):
        pb = rig.pose.bones
        rest = {b.name: b.matrix_local.to_quaternion() for b in rig.data.bones}

        def rot(bone, axis, deg):
            R = rest[bone]
            return R.inverted() @ Quaternion(axis, math.radians(deg)) @ R

        def key(f, pose):
            for b in pb:
                q, s, loc = pose.get(b.name, (Quaternion(), 1.0, Vector()))
                b.rotation_mode = "QUATERNION"
                b.rotation_quaternion = q
                b.scale = (s, s, s)
                b.location = loc
                b.keyframe_insert("rotation_quaternion", frame=f)
                b.keyframe_insert("scale", frame=f)
                b.keyframe_insert("location", frame=f)

        def action(name, frames, pose_at):
            act = bpy.data.actions.new(name)
            act.use_fake_user = True
            rig.animation_data_create()
            rig.animation_data.action = act
            for f in range(frames + 1):
                key(f + 1, pose_at(f / frames))
            tr = rig.animation_data.nla_tracks.new()
            tr.name = name
            tr.strips.new(name, 1, act)
            rig.animation_data.action = None
            self.say("LOOP %s: %d frames, %.2f s" % (name, frames, frames / FPS))

        tucked = 0.001
        X, Z, Y = Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0))

        def bump(t, a, b):  # 0 outside a..b, rising and falling smoothly inside
            if t <= a or t >= b:
                return 0.0
            return math.sin(math.pi * (t - a) / (b - a)) ** 2

        def idle(t):
            look = 28 * bump(t, 0.06, 0.3) - 24 * bump(t, 0.62, 0.84)
            peck = bump(t, 0.36, 0.56)
            flick = bump(t, 0.86, 0.96)
            breathe = 1.0 + 0.015 * math.sin(2 * math.pi * t * 3)
            return {
                "Body": (rot("Body", X, 30 * peck), breathe, Vector()),
                "Head": (rot("Head", Z, look) @ rot("Head", X, 22 * peck), 1.0, Vector()),
                "Tail": (rot("Tail", X, -18 * flick + 8 * peck), 1.0, Vector()),
                "LeftWing": (Quaternion(), tucked, Vector()),
                "RightWing": (Quaternion(), tucked, Vector()),
            }

        def fly(t):
            a = math.sin(2 * math.pi * t)  # 1 up, -1 down
            up = 15 + 45 * a
            return {
                "Body": (rot("Body", X, -8), 1.0, Vector((0, 0, -0.02 * self.U * a))),
                "Head": (rot("Head", X, 10), 1.0, Vector()),
                "Tail": (rot("Tail", X, -10 + 4 * a), 1.0, Vector()),
                "LeftWing": (rot("LeftWing", Y, -up), 1.0, Vector()),
                "RightWing": (rot("RightWing", Y, up), 1.0, Vector()),
                "LeftLeg": (rot("LeftLeg", X, 65), 1.0, Vector()),
                "RightLeg": (rot("RightLeg", X, 65), 1.0, Vector()),
            }

        action("Idle", int(round(2.4 * FPS)), idle)
        action("Fly", max(8, int(round(self.sp["flap"] * FPS))), fly)
        bpy.context.scene.render.fps = FPS

    def export(self, ob, rig):
        out = os.path.join(PROJECT, "assets", "wildlife", self.sid + ".glb")
        activate(ob, rig)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                                  export_image_format="JPEG", export_jpeg_quality=90, export_animations=True,
                                  export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                                  export_draco_mesh_compression_enable=False)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        self.say("EXPORTED %s: %d triangles, %d bones -> %s" % (self.sid, tris, len(rig.data.bones), os.path.relpath(out, PROJECT)))

    def render(self, ob, rig):
        out = os.path.join(HERE, "review", self.sid)
        os.makedirs(out, exist_ok=True)
        sc = bpy.context.scene
        sc.render.engine = "BLENDER_EEVEE"
        sc.render.film_transparent = True
        sc.view_settings.view_transform = "Standard"
        sc.render.resolution_x = sc.render.resolution_y = 768
        w = sc.world or bpy.data.worlds.new("review")
        sc.world = w
        w.use_nodes = True
        bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
        bg.inputs[0].default_value = (0.62, 0.66, 0.72, 1)
        bg.inputs[1].default_value = 0.9
        for nm, r, e in (("key", (math.radians(50), 0, math.radians(-35)), 3.0), ("rim", (math.radians(60), 0, math.radians(150)), 1.2)):
            ld = bpy.data.lights.new(nm, "SUN")
            ld.energy = e
            lo = link(bpy.data.objects.new(nm, ld))
            lo.rotation_euler = r
        cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
        sc.camera = cam
        c = Vector((0, 0, 0.55 * self.U))

        def shoot(name, d, ortho, track, frame):
            ad = rig.animation_data
            for t in ad.nla_tracks:
                t.mute = t.name != track
            sc.frame_set(frame)
            cam.data.type = "ORTHO" if ortho else "PERSP"
            cam.data.ortho_scale = 2.4 * self.U if track == "Fly" else 1.7 * self.U
            cam.data.lens = 50
            cam.location = c + d.normalized() * (6 * self.U if not ortho else 4 * self.U)
            cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(out, name + ".png")
            bpy.ops.render.render(write_still=True)
        shoot("side", Vector((1, 0, 0)), True, "Idle", 1)
        shoot("threeq", Vector((0.62, -0.78, 0.2)), False, "Idle", 1)
        shoot("peck", Vector((1, 0, 0)), True, "Idle", int(0.46 * 2.4 * FPS) + 1)
        shoot("fly_up", Vector((0.5, -0.6, 0.45)), False, "Fly", 1 + int(0.25 * self.sp["flap"] * FPS))
        shoot("fly_down", Vector((0.5, -0.6, 0.45)), False, "Fly", 1 + int(0.75 * self.sp["flap"] * FPS))
        print("REVIEW", out)

    def run(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        body = self.body()
        beak = self.beak()
        eyes = self.eyes()
        tail = self.tail()
        legs = self.legs()
        wings = self.wings()
        self.paint_body(body)
        self.paint_solid(beak, beak["solid"], beak.get("spot"))
        for o in eyes + legs:
            self.paint_solid(o, o["solid"])
        self.paint_tail(tail)
        for w in wings:
            self.paint_wing(w)
        objs = [body, beak, tail] + eyes + legs + wings
        self.bake(objs)
        self.materials(objs)
        rig = self.rig()
        ob = self.skin(rig, body, beak, eyes, tail, legs, wings)
        self.loops(rig)
        out = os.path.join(HERE, "out", self.sid)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, self.sid + ".blend"))
        self.export(ob, rig)
        if "--render" in argv:
            self.render(ob, rig)
        with open(os.path.join(out, "build_log.txt"), "w") as f:
            f.write("\n".join(self.log) + "\n")


ids = [a for a in argv if not a.startswith("--")]
if ids == ["all"] or not ids:
    ids = list(BIRDS)
failed = []
for sid in ids:
    try:
        Bird(sid).run()
    except Exception as e:
        import traceback
        traceback.print_exc()
        failed.append("%s: %s" % (sid, e))
if failed:
    raise SystemExit("FAILED " + "; ".join(failed))
