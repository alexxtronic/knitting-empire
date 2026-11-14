"""The wild animals: built from their reference sheets, painted, baked, rigged and given their loops.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/wildlife/build.py -- <id> [...] [--render] [--no-export]

<id> is a key of species.SPECIES (or `all`). For each animal:
  1. the body is modelled like clay from blended ellipsoids and capsules (Blender metaballs) at the
     sizes in species.py, read off ref/<id>.png; turned into a mesh, thinned to about 10k triangles
     and roughed up into tufts so the outline reads as fur;
  2. ears (a cupped shell, pointed, long or round), eyes (glossy, iris, pupil and a catch light),
     the nose, a beaver's teeth and paddle tail are separate small meshes;
  3. every point of the fur is painted by the species' paint() (its markings, from the reference),
     and the colour, a fur-clump normal map and the ambient occlusion are baked into one 1024 px atlas;
  4. a skeleton on blender-kiln's bone names, skinned with bone-heat weights, the head rigid
     (everything ahead of the neck follows the Head bone alone);
  5. Idle, Walk and Run loops from gait.py, every paw solved to its spot on the ground (the dog's
     method), checked frame by frame;
  6. exported to assets/wildlife/<id>.glb (never Draco: Godot can't read it). It prints each loop's
     STRIDE: data/wildlife.json takes them, so the paws don't slide.
--render writes review pictures to art/world_assets/wildlife/review/<id>/.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector, noise
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gait as G  # noqa: E402
import species  # noqa: E402

PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
IDS = [a for a in argv if not a.startswith("--")]
if IDS == ["all"]:
    IDS = list(species.SPECIES)
RENDER = "--render" in argv
EXPORT = "--no-export" not in argv
TEX = 1024
FACES = 10000
THRESH = 0.6


def srgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def K(stiff):
    """How far out a metaball element's surface sits, as a share of its radius, at this stiffness."""
    return math.sqrt(1.0 - (THRESH / stiff) ** (1.0 / 3.0))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def activate(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


class Build:
    def __init__(self, sid):
        self.sid = sid
        self.sp = species.SPECIES[sid]
        self.U = self.sp["unit"]
        self.mid = (self.sp["shoulder"][0] + self.sp["hip"][0]) / 2.0
        self.parts = []  # (part, centre, radii (Vector), tail_s or None)
        self.log = []

    def P(self, u, v, x=0.0):
        return Vector((x * self.U, (u - self.mid) * self.U, v * self.U))

    def say(self, *a):
        line = " ".join(str(x) for x in a)
        print(line)
        self.log.append(line)

    # --- 1. the body ---------------------------------------------------------------------------------
    def body(self):
        sp, U = self.sp, self.U
        mb = bpy.data.metaballs.new("body")
        mb.resolution = 0.0075 * U
        mb.render_resolution = mb.resolution
        mb.threshold = THRESH
        ob = link(bpy.data.objects.new("body", mb))

        def ellip(part, c, rx, ry, rz, stiff=2.0, s=None):
            e = mb.elements.new(type="ELLIPSOID")
            k = K(stiff)
            e.co = c
            e.radius = 1.0 / k
            e.size_x, e.size_y, e.size_z = rx * U, ry * U, rz * U
            e.stiffness = stiff
            self.parts.append((part, Vector(c), Vector((rx * U, ry * U, rz * U)), s))

        def capsule(part, a, b, r, stiff=6.0, s=None):
            d = b - a
            if d.length < 1e-5:
                return ellip(part, a, r / U, r / U, r / U, stiff, s)
            e = mb.elements.new(type="CAPSULE")
            e.co = (a + b) / 2
            e.radius = r / K(stiff)
            e.size_x = d.length / 2
            e.rotation = Vector((1, 0, 0)).rotation_difference(d.normalized())
            e.stiffness = stiff
            n = max(2, int(d.length / (r * 0.8)))
            for i in range(n + 1):
                self.parts.append((part, a.lerp(b, i / n), Vector((r, r, r)), s))

        P = self.P
        for (u, v, rx, ry, rz) in sp["torso"]:
            ellip("torso", P(u, v), rx, ry, rz)
        for part, (u, v, rx, ry, rz) in sp.get("extra", []):
            ellip(part, P(u, v), rx, ry, rz)
        u, v, rx, ry, rz = sp["neck"]
        ellip("neck", P(u, v), rx, ry, rz)
        u, v, rx, ry, rz = sp["head"]
        ellip("head", P(u, v), rx, ry, rz)
        u, v, rx, ry, rz = sp["snout"]
        ellip("snout", P(u, v), rx, ry, rz, stiff=3.0)
        for side in (1, -1):
            for key, joints, lx in (("leg_f", sp["fore"], sp["leg_x"][0]), ("leg_h", sp["hind"], sp["leg_x"][1])):
                pts = [(P(u, v, side * lx), r * U) for (u, v, r) in joints]
                for i in range(len(pts) - 2):
                    (a, ra), (b, rb) = pts[i], pts[i + 1]
                    for j in range(3):  # a taper in three steps
                        t0, t1 = j / 3, (j + 1) / 3
                        capsule(key, a.lerp(b, t0), a.lerp(b, t1), ra + (rb - ra) * (t0 + t1) / 2)
                (w, rw), (t, rt) = pts[-2], pts[-1]  # the paw: a soft oval from the wrist (hock) to the toes
                c = (w + t) / 2 + Vector((0, 0, rt * 0.15))
                half = (t - w).length / 2 + rt * 0.9
                e = mb.elements.new(type="ELLIPSOID")
                k = K(4.0)
                e.co = c
                e.radius = 1.0 / k
                e.size_x, e.size_y, e.size_z = rt * 1.15, half, rt * 0.85
                e.rotation = Vector((0, 1, 0)).rotation_difference((t - w).normalized()) if (t - w).length > 1e-4 else Quaternion()
                e.stiffness = 4.0
                self.parts.append(("paw", c, Vector((rt * 1.15, half, rt * 0.85)), None))
                capsule(key, w, c, rw * 0.9)
        tail = sp["tail"]
        if sp.get("tail_ball"):
            u, v, r = tail[0]
            ellip("tail", P(u, v), r, r, r, stiff=3.0, s=0.5)
        elif not sp.get("flat_tail"):
            pts = [(P(u, v), r * U) for (u, v, r) in tail]
            L = sum((pts[i + 1][0] - pts[i][0]).length for i in range(len(pts) - 1))
            acc = 0.0
            for i in range(len(pts) - 1):
                (a, ra), (b, rb) = pts[i], pts[i + 1]
                seg = (b - a).length
                for j in range(4):
                    t0, t1 = j / 4, (j + 1) / 4
                    s = (acc + seg * (t0 + t1) / 2) / L
                    capsule("tail", a.lerp(b, t0), a.lerp(b, t1), ra + (rb - ra) * (t0 + t1) / 2, stiff=3.0, s=s)
                acc += seg
        activate(ob)
        bpy.ops.object.convert(target="MESH")
        ob = bpy.context.view_layer.objects.active
        ob.name = "body"
        me = ob.data
        self.say("BODY from metaballs: %d vertices, %d faces" % (len(me.vertices), len(me.polygons)))
        # thin it to FACES triangles, keeping the outline
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        if len(me.polygons) > FACES:
            mod = ob.modifiers.new("dec", "DECIMATE")
            mod.ratio = FACES / len(me.polygons)
            activate(ob)
            bpy.ops.object.modifier_apply(modifier=mod.name)
        self.body_ob = ob
        self.label()
        self.tufts()
        bpy.ops.object.shade_smooth()
        self.say("BODY thinned: %d faces; %d parts" % (len(me.polygons), len(set(p[0] for p in self.parts))))

    def label(self):
        """Which part of the animal each point belongs to: the element it sits nearest, as a share of
        that element's size (the head, a leg, the tail and how far along it)."""
        me = self.body_ob.data
        C = np.array([p[1] for p in self.parts])
        R = np.array([p[2] for p in self.parts])
        names = [p[0] for p in self.parts]
        tails = [p[3] for p in self.parts]
        V = np.array([v.co[:] for v in me.vertices])
        best = np.full(len(V), 1e9)
        idx = np.zeros(len(V), int)
        for i in range(len(C)):
            d = np.sqrt((((V - C[i]) / R[i]) ** 2).sum(axis=1))
            m = d < best
            best[m] = d[m]
            idx[m] = i
        self.vpart = [names[i] for i in idx]
        self.vtail = [tails[i] if tails[i] is not None else 0.0 for i in idx]

    def tufts(self):
        """Roughs the surface up into soft clumps so the outline reads as fur, not plastic."""
        me = self.body_ob.data
        amp = self.sp.get("fluff", 0.012) * self.U
        f = 1.0 / (0.045 * self.U)
        for i, v in enumerate(me.vertices):
            part = self.vpart[i]
            if part == "paw":
                continue
            q = v.co * f
            # clumps: cell noise for the locks, a little fine noise on top; more on the ruff and tail
            n = noise.noise(q) * 0.6 + noise.noise(q * 2.7) * 0.4
            boost = 1.6 if part in ("chest", "cheek", "tail") else 1.0
            v.co += v.normal * amp * boost * n

    # --- 2. small parts ------------------------------------------------------------------------------
    def ears(self):
        sp = self.sp
        e = sp["ears"]
        out = []
        for side in (1, -1):
            out.append(self._ear(e, side))
        return out

    def _ear(self, e, side):
        U = self.U
        L, W = e["length"] * U, e["width"] * U
        kind = e["kind"]
        rows, cols = 14, 11
        bm = bmesh.new()
        grid = []
        for i in range(rows + 1):
            s = i / rows
            if kind == "pointy":  # a broad, rounded triangle
                prof = (1.0 - s) ** 0.7
            elif kind == "long":
                prof = math.sqrt(max(0.0, 1.0 - ((s - 0.42) / 0.58) ** 2)) * (0.75 + 0.25 * (1 - s))
            else:  # round
                prof = math.sqrt(max(0.0, 1.0 - s ** 2))
            prof = max(prof, 0.02)
            row = []
            for j in range(cols + 1):
                t = j / cols * 2 - 1
                x = t * W / 2 * prof
                cup = 0.28 * W * (1 - t * t) * math.sin(math.pi * min(1.0, s * 1.3)) ** 0.6 * prof
                row.append(bm.verts.new((x, cup, s * L)))
            grid.append(row)
        for i in range(rows):
            for j in range(cols):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
        me = bpy.data.meshes.new("ear")
        bm.to_mesh(me)
        bm.free()
        ob = link(bpy.data.objects.new("ear", me))
        sol = ob.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = 0.022 * U
        sol.offset = 1.0
        activate(ob)
        bpy.ops.object.modifier_apply(modifier=sol.name)
        # masks, in the ear's own frame: front (cupped) side and rim
        me = ob.data
        self._ear_masks = getattr(self, "_ear_masks", {})
        masks = []
        for v in me.vertices:
            s = v.co.z / L
            front = v.normal.y < -0.2
            half = W / 2 * max(0.05, (1 - s) if kind == "pointy" else 1.0)
            t = abs(v.co.x) / max(half, 1e-4)
            masks.append((s, front, t))
        # place it: its opening turned out to its own side, the tip tilted back (+Y) and splayed out,
        # its base sunk a little into the head's surface under the base point
        u, vv, x = e["base"]
        rot = (Matrix.Rotation(math.radians(side * e["splay"]), 4, "Y") @ Matrix.Rotation(math.radians(-e["tilt"]), 4, "X")
               @ Matrix.Rotation(math.radians(side * e.get("turn", 0.0)), 4, "Z"))
        centre = self.P(self.sp["head"][0], self.sp["head"][1])
        want = self.P(u, vv, side * x)
        base = self.surface(centre, want)
        base = base - (base - centre).normalized() * 0.02 * U
        ob.matrix_world = Matrix.Translation(base) @ rot
        activate(ob)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.shade_smooth()
        self._ear_masks[ob.name] = masks
        return ob

    def surface(self, frm, to):
        """Where a ray from `frm` toward `to` leaves the body."""
        bvh = BVHTree.FromObject(self.body_ob, bpy.context.evaluated_depsgraph_get())
        d = (to - frm).normalized()
        hit = bvh.ray_cast(frm, d)
        return hit[0] if hit[0] is not None else to

    def eyes(self):
        sp = self.sp
        u, v, x, r, iris = sp["eye"]
        hu, hv = sp["head"][0], sp["head"][1]
        out = []
        self.eye_pos = []
        for side in (1, -1):
            want = self.P(u, v, side * x)
            centre = self.P(hu, hv, 0)
            surf = self.surface(centre, want)
            outward = (surf - centre).normalized()
            gaze = (outward + Vector((0, -self.sp.get("gaze", 1.6), 0))).normalized()  # forward, a little out
            pos = surf - outward * r * self.U * 0.3
            self.eye_pos.append((pos, r * self.U))
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=r * self.U)
            me = bpy.data.meshes.new("eye")
            bm.to_mesh(me)
            bm.free()
            ob = link(bpy.data.objects.new("eye", me))
            # a little flattened front to back, so it sits in the face like a lens instead of a bead
            ob.matrix_world = (Matrix.Translation(pos) @ Vector((0, -1, 0)).rotation_difference(gaze).to_matrix().to_4x4()
                               @ Matrix.Diagonal((1.0, 0.62, 1.0, 1.0)))
            ob["iris"] = iris
            out.append(ob)
        return out

    def blob(self, name, c, rx, ry, rz, segs=20):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=1.0)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = link(bpy.data.objects.new(name, me))
        ob.matrix_world = Matrix.Translation(c) @ Matrix.Diagonal((rx, ry, rz, 1.0))
        activate(ob)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.shade_smooth()
        return ob

    def nose(self):
        u, v, r, col = self.sp["nose"]
        c = self.surface(self.P(*self.sp["snout"][:2]), self.P(u - 0.2, v))
        ob = self.blob("nose", c + Vector((0, r * self.U * 0.25, 0)), r * self.U * 1.25, r * self.U * 0.85, r * self.U)
        ob["solid"] = col
        return ob

    def teeth(self):
        if "teeth" not in self.sp:
            return []
        u, v, w, h, col = self.sp["teeth"]
        out = []
        for side in (1, -1):
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.18, segments=2, affect="EDGES")
            me = bpy.data.meshes.new("tooth")
            bm.to_mesh(me)
            bm.free()
            ob = link(bpy.data.objects.new("tooth", me))
            ob.matrix_world = Matrix.Translation(self.P(u, v, side * w * 0.55)) @ Matrix.Diagonal((w * self.U, w * 0.5 * self.U, h * self.U, 1))
            activate(ob)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            ob["solid"] = col
            out.append(ob)
        return out

    def paddle(self):
        """The beaver's tail: a flat, rounded paddle along the tail's centre line."""
        if not self.sp.get("flat_tail"):
            return []
        pts = [(self.P(u, v), r * self.U) for (u, v, r) in self.sp["tail"]]
        rows, cols = 18, 10
        bm = bmesh.new()
        grid = []
        total = sum((pts[i + 1][0] - pts[i][0]).length for i in range(len(pts) - 1))
        for i in range(rows + 1):
            s = i / rows
            # along the polyline
            dist, acc = s * total, 0.0
            for k in range(len(pts) - 1):
                seg = (pts[k + 1][0] - pts[k][0]).length
                if acc + seg >= dist - 1e-9 or k == len(pts) - 2:
                    t = 0.0 if seg < 1e-9 else (dist - acc) / seg
                    c = pts[k][0].lerp(pts[k + 1][0], min(1, t))
                    break
                acc += seg
            w = (0.35 + 0.65 * math.sin(math.pi * min(1.0, 0.25 + s * 0.9))) * pts[0][1]
            row = []
            for j in range(cols + 1):
                a = j / cols * 2 - 1
                row.append(bm.verts.new(c + Vector((a * w, 0, 0))))
            grid.append(row)
        for i in range(rows):
            for j in range(cols):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
        me = bpy.data.meshes.new("paddle")
        bm.to_mesh(me)
        bm.free()
        ob = link(bpy.data.objects.new("paddle", me))
        sol = ob.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = 0.035 * self.U
        sol.offset = 0.0
        sub = ob.modifiers.new("sub", "SUBSURF")
        sub.levels = 1
        activate(ob)
        bpy.ops.object.modifier_apply(modifier=sol.name)
        bpy.ops.object.modifier_apply(modifier=sub.name)
        bpy.ops.object.shade_smooth()
        ob["scales"] = self.sp.get("tail_color", "#5e3a2c")
        return [ob]

    # --- 3. paint and bake ---------------------------------------------------------------------------
    def paint(self, ob, kind):
        me = ob.data
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        sp = self.sp
        if kind == "solid":
            c = lin(srgb(ob["solid"]))
            for d in attr.data:
                d.color = (*c, 1.0)
            return
        masks = self._ear_masks.get(ob.name) if kind == "ear" else None
        brow = sp.get("brow")
        eye = sp["eye"]
        for i, v in enumerate(me.vertices):
            co = v.co
            p = Paint()
            p.u = co.y / self.U + self.mid
            p.v = co.z / self.U
            p.x = abs(co.x) / self.U
            p.n = 0.5 + 0.5 * noise.noise(co * (1.0 / (0.03 * self.U)))
            if sp.get("spots"):  # round dark spots (the lynx): near a cell point of a voronoi field
                d = noise.voronoi(co * (1.0 / (sp["spots"] * self.U)))[0][0]
                p.spot = G.ease((0.42 - d) / 0.12)
            if kind == "ear":
                s, front, t = masks[i]
                p.part = "ear"
                p.ear_in = (1.0 if front else 0.0) * G.ease((0.82 - t) / 0.2) * G.ease((0.97 - s) / 0.15)
                p.ear_out = 0.0 if front else 1.0
                p.ear_rim = (1.0 if front else 0.0) * (1.0 - p.ear_in)
                p.ear_tuft = (1.0 if front else 0.0) * G.ease((0.35 - s) / 0.2) * G.ease((0.7 - t) / 0.3)
                p.ear_s = s
            else:
                p.part = self.vpart[i]
                p.tail_s = self.vtail[i]
            p.head_like = 1.0 if p.part in ("head", "cheek", "snout", "neck") else 0.0
            if brow and p.part == "head":
                bu, bv, br = brow
                d = math.sqrt((p.u - bu) ** 2 + (p.v - bv) ** 2 + (p.x - eye[2]) ** 2)
                p.brow = G.ease((br - d) / (br * 0.5)) * 0.8
            c = sp["paint"](p)
            if kind == "body" and p.part in ("head", "cheek", "snout"):
                # a dark liner round each eye, heavier along the top like a lid
                for pos, r in self.eye_pos:
                    d = (co - pos).length / r
                    top = 0.18 if co.z > pos.z else 0.0
                    ring = G.ease((d - 0.92) / 0.08) * G.ease((1.22 + top - d) / 0.1)
                    if ring > 0:
                        c = p.over(c, sp.get("liner", "#2b1a14"), ring)
            attr.data[i].color = (*lin(c), 1.0)

    def bake(self, objs):
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 1
        img = bpy.data.images.new(self.sid + "_color", TEX, TEX, alpha=False)
        nimg = bpy.data.images.new(self.sid + "_normal", TEX, TEX, alpha=False)
        nimg.colorspace_settings.name = "Non-Color"
        aimg = bpy.data.images.new(self.sid + "_ao", TEX, TEX, alpha=False)
        # UVs: all parts packed into one atlas
        activate(*objs)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        mats = {}
        for ob in objs:
            m = bpy.data.materials.new("bake_" + ob.name)
            m.use_nodes = True
            ob.data.materials.clear()
            ob.data.materials.append(m)
            mats[ob.name] = m
        S = 1.0 / self.U

        def setup(target, mode):
            for ob in objs:
                m = mats[ob.name]
                nt = m.node_tree
                nt.nodes.clear()
                out = nt.nodes.new("ShaderNodeOutputMaterial")
                tex = nt.nodes.new("ShaderNodeTexImage")
                tex.image = target
                nt.nodes.active = tex
                if mode == "color":
                    em = nt.nodes.new("ShaderNodeEmission")
                    nt.links.new(em.outputs[0], out.inputs[0])
                    if "iris" in ob:
                        nt.links.new(self._eye_nodes(nt, ob["iris"]), em.inputs[0])
                    elif "scales" in ob:
                        nt.links.new(self._scale_nodes(nt, ob["scales"]), em.inputs[0])
                    else:
                        at = nt.nodes.new("ShaderNodeAttribute")
                        at.attribute_name = "Col"
                        if "solid" in ob:
                            nt.links.new(at.outputs["Color"], em.inputs[0])
                        else:
                            nt.links.new(self._fur_nodes(nt, at.outputs["Color"], S), em.inputs[0])
                elif mode == "normal":
                    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
                    nt.links.new(bs.outputs[0], out.inputs[0])
                    if not ("iris" in ob or "solid" in ob or "scales" in ob):
                        bump = nt.nodes.new("ShaderNodeBump")
                        bump.inputs["Strength"].default_value = 0.55
                        nt.links.new(self._clump_height(nt, S), bump.inputs["Height"])
                        nt.links.new(bump.outputs[0], bs.inputs["Normal"])
                    elif "scales" in ob:
                        bump = nt.nodes.new("ShaderNodeBump")
                        bump.inputs["Strength"].default_value = 0.4
                        nt.links.new(self._scale_height(nt), bump.inputs["Height"])
                        nt.links.new(bump.outputs[0], bs.inputs["Normal"])
                else:
                    bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
                    nt.links.new(bs.outputs[0], out.inputs[0])

        activate(*objs)
        setup(img, "color")
        bpy.ops.object.bake(type="EMIT", margin=6, use_clear=True)
        setup(nimg, "normal")
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=6, use_clear=True)
        sc.cycles.samples = 48
        sc.world = sc.world or bpy.data.worlds.new("w")
        setup(aimg, "ao")
        bpy.context.scene.render.bake.use_clear = True
        bpy.ops.object.bake(type="AO", margin=6, use_clear=True)
        # colour x a soft share of the occlusion
        n = TEX * TEX * 4
        c = np.empty(n, np.float32)
        a = np.empty(n, np.float32)
        img.pixels.foreach_get(c)
        aimg.pixels.foreach_get(a)
        c = c.reshape(-1, 4)
        a = a.reshape(-1, 4)[:, :1]
        c[:, :3] *= 0.55 + 0.45 * a
        img.pixels.foreach_set(c.ravel())
        img.update()
        self.img, self.nimg = img, nimg
        out = os.path.join(HERE, "out", self.sid)
        os.makedirs(out, exist_ok=True)
        for im, name in ((img, "color"), (nimg, "normal")):
            im.filepath_raw = os.path.join(out, "%s_%s.png" % (self.sid, name))
            im.file_format = "PNG"
            im.save()
        self.say("BAKED %d px atlas: colour (with occlusion) and fur normal map" % TEX)

    def _fur_nodes(self, nt, col, S):
        """The painted colour, darker in the gaps between clumps and lighter on their tips."""
        h = self._clump_height(nt, S)
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs[1].default_value, mr.inputs[2].default_value = 0.25, 0.75
        mr.inputs[3].default_value, mr.inputs[4].default_value = 0.78, 1.12
        nt.links.new(h, mr.inputs[0])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(col, mul.inputs[6])
        nt.links.new(mr.outputs[0], mul.inputs[7])
        return mul.outputs[2]

    def _clump_height(self, nt, S):
        """Fur locks: fine streaks running head to tail, gathered into soft clumps."""
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (S, S * 0.28, S)  # streaks run along the body
        nt.links.new(tc.outputs["Object"], mp.inputs[0])
        no = nt.nodes.new("ShaderNodeTexNoise")
        no.inputs["Scale"].default_value = 70.0
        no.inputs["Detail"].default_value = 6.0
        no.inputs["Roughness"].default_value = 0.62
        nt.links.new(mp.outputs[0], no.inputs[0])
        mp2 = nt.nodes.new("ShaderNodeMapping")
        mp2.inputs["Scale"].default_value = (S, S * 0.6, S)
        nt.links.new(tc.outputs["Object"], mp2.inputs[0])
        vo = nt.nodes.new("ShaderNodeTexVoronoi")
        vo.feature = "SMOOTH_F1"
        vo.inputs["Scale"].default_value = 16.0
        nt.links.new(mp2.outputs[0], vo.inputs[0])
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 1.0
        nt.links.new(vo.outputs["Distance"], inv.inputs[1])
        a = nt.nodes.new("ShaderNodeMath")
        a.operation = "MULTIPLY"
        a.inputs[1].default_value = 0.45
        nt.links.new(inv.outputs[0], a.inputs[0])
        mx = nt.nodes.new("ShaderNodeMath")
        mx.operation = "MULTIPLY_ADD"
        nt.links.new(no.outputs["Fac"], mx.inputs[0])
        mx.inputs[1].default_value = 0.6
        nt.links.new(a.outputs[0], mx.inputs[2])
        cl = nt.nodes.new("ShaderNodeMath")
        cl.operation = "MULTIPLY"
        cl.inputs[1].default_value = 1.0
        cl.use_clamp = True
        nt.links.new(mx.outputs[0], cl.inputs[0])
        return cl.outputs[0]

    def _eye_nodes(self, nt, iris_hex):
        """In the eye's own frame (-Y looks out): pupil, iris, a thin white, and a catch light up and
        forward."""
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nrm = nt.nodes.new("ShaderNodeVectorMath")
        nrm.operation = "NORMALIZE"
        nt.links.new(tc.outputs["Object"], nrm.inputs[0])
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        dot.inputs[1].default_value = (0, -1, 0)
        nt.links.new(nrm.outputs[0], dot.inputs[0])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.interpolation = "EASE"
        iris = lin(srgb(iris_hex))
        dark = tuple(x * 0.35 for x in iris)
        light = tuple(min(1.0, x * 1.9 + 0.03) for x in iris)
        cr.elements[0].position, cr.elements[0].color = 0.0, (0.93, 0.9, 0.86, 1)
        cr.elements[1].position, cr.elements[1].color = 0.18, (0.93, 0.9, 0.86, 1)
        for pos, col in ((0.24, (*dark, 1)), (0.55, (*iris, 1)), (0.72, (*light, 1)), (0.8, (0.02, 0.015, 0.012, 1)), (1.0, (0.01, 0.008, 0.006, 1))):
            el = cr.elements.new(pos)
            el.color = col
        nt.links.new(dot.outputs["Value"], ramp.inputs[0])
        g = nt.nodes.new("ShaderNodeVectorMath")
        g.operation = "DOT_PRODUCT"
        gd = Vector((0.3, -0.75, 0.55)).normalized()
        g.inputs[1].default_value = gd
        nt.links.new(nrm.outputs[0], g.inputs[0])
        gr = nt.nodes.new("ShaderNodeMapRange")
        gr.inputs[1].default_value, gr.inputs[2].default_value = 0.955, 0.975
        nt.links.new(g.outputs["Value"], gr.inputs[0])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(gr.outputs[0], mix.inputs["Factor"])
        nt.links.new(ramp.outputs[0], mix.inputs[6])
        mix.inputs[7].default_value = (1, 1, 1, 1)
        return mix.outputs[2]

    def _scale_coords(self, nt):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (0, 0, math.radians(45))
        mp.inputs["Scale"].default_value = (1 / (0.035 * self.U),) * 3
        nt.links.new(tc.outputs["Object"], mp.inputs[0])
        return mp

    def _scale_height(self, nt):
        mp = self._scale_coords(nt)
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(mp.outputs[0], sep.inputs[0])
        out = None
        for axis in ("X", "Y"):
            fr = nt.nodes.new("ShaderNodeMath")
            fr.operation = "PINGPONG"
            fr.inputs[1].default_value = 0.5
            nt.links.new(sep.outputs[axis], fr.inputs[0])
            out = fr if out is None else out
            if axis == "Y":
                mn = nt.nodes.new("ShaderNodeMath")
                mn.operation = "MINIMUM"
                nt.links.new(out.outputs[0], mn.inputs[0])
                nt.links.new(fr.outputs[0], mn.inputs[1])
                out = mn
        return out.outputs[0]

    def _scale_nodes(self, nt, hexcol):
        h = self._scale_height(nt)
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs[1].default_value, mr.inputs[2].default_value = 0.0, 0.12
        mr.inputs[3].default_value, mr.inputs[4].default_value = 0.55, 1.0
        nt.links.new(h, mr.inputs[0])
        rgb = nt.nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*lin(srgb(hexcol)), 1)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(rgb.outputs[0], mul.inputs[6])
        nt.links.new(mr.outputs[0], mul.inputs[7])
        return mul.outputs[2]

    def final_materials(self, objs):
        def mat(name, rough, normal):
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            nt = m.node_tree
            bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = self.img
            nt.links.new(tex.outputs[0], bs.inputs["Base Color"])
            bs.inputs["Roughness"].default_value = rough
            if normal:
                nt2 = nt.nodes.new("ShaderNodeTexImage")
                nt2.image = self.nimg
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(nt2.outputs[0], nm.inputs["Color"])
                nt.links.new(nm.outputs[0], bs.inputs["Normal"])
            return m
        fur = mat(self.sid + "_fur", 0.9, True)
        gloss = mat(self.sid + "_gloss", 0.18, False)
        for ob in objs:
            ob.data.materials.clear()
            ob.data.materials.append(gloss if ("iris" in ob or "solid" in ob) else fur)

    # --- 4. rig --------------------------------------------------------------------------------------
    def rig(self):
        sp, P = self.sp, self.P
        spine_v = sum(t[1] for t in sp["torso"]) / len(sp["torso"])
        hu, hv, hrx, hry, hrz = sp["head"]
        su, sv = sp["snout"][0], sp["snout"][1]
        J = {
            "Hips": P(sp["hip"][0], spine_v), "Spine1": P(self.mid, spine_v), "Chest": P(sp["shoulder"][0], spine_v),
            "Head": P(hu + 0.55 * hry, hv - 0.45 * hrz), "HeadEnd": P(su, sv),
        }
        J["Neck"] = J["Chest"].lerp(J["Head"], 0.25)
        for side, sgn in (("Left", 1), ("Right", -1)):
            lx_f, lx_h = sp["leg_x"]
            f, h = sp["fore"], sp["hind"]
            J[side + "Arm"], J[side + "ForeArm"], J[side + "Hand"], J[side + "HandEnd"] = [P(u, v, sgn * lx_f) for (u, v, r) in f]
            J[side + "UpLeg"], J[side + "Leg"], J[side + "Foot"], J[side + "FootEnd"] = [P(u, v, sgn * lx_h) for (u, v, r) in h]
        tail = sp["tail"]
        tpts = [P(u, v) for (u, v, r) in tail]
        if len(tpts) == 1:  # a ball: one bone from the rump to it
            tpts = [J["Hips"].lerp(tpts[0], 0.6), tpts[0] + (tpts[0] - J["Hips"]).normalized() * tail[0][2] * self.U]
        while len(tpts) < 4 and len(tpts) >= 2 and not sp.get("tail_ball"):
            # split the longest segment so a tail has three bones to wave with
            i = max(range(len(tpts) - 1), key=lambda k: (tpts[k + 1] - tpts[k]).length)
            tpts.insert(i + 1, (tpts[i] + tpts[i + 1]) / 2)
        n_t = min(len(tpts) - 1, 4)
        tpts = tpts[:n_t + 1]
        bones = [("Hips", J["Hips"], J["Spine1"], None), ("Spine1", J["Spine1"], J["Chest"], "Hips"),
                 ("Neck", J["Neck"], J["Head"], "Spine1"), ("Head", J["Head"], J["HeadEnd"], "Neck")]
        for i in range(n_t):
            bones.append(("Tail%d" % (i + 1), tpts[i], tpts[i + 1], "Hips" if i == 0 else "Tail%d" % i))
        for side in ("Left", "Right"):
            bones += [(side + "Arm", J[side + "Arm"], J[side + "ForeArm"], "Spine1"),
                      (side + "ForeArm", J[side + "ForeArm"], J[side + "Hand"], side + "Arm"),
                      (side + "Hand", J[side + "Hand"], J[side + "HandEnd"], side + "ForeArm"),
                      (side + "UpLeg", J[side + "UpLeg"], J[side + "Leg"], "Hips"),
                      (side + "Leg", J[side + "Leg"], J[side + "Foot"], side + "UpLeg"),
                      (side + "Foot", J[side + "Foot"], J[side + "FootEnd"], side + "Leg")]
        ad = bpy.data.armatures.new(self.sid + "_rig")
        rig = link(bpy.data.objects.new("rig", ad))
        activate(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        eb = ad.edit_bones
        for name, h, t, parent in bones:
            b = eb.new(name)
            b.head, b.tail = h, t
            b.align_roll(Vector((0, 0, 1)) if abs(b.vector.normalized().z) < 0.9 else Vector((0, -1, 0)))
            if parent:
                b.parent = eb[parent]
        bpy.ops.object.mode_set(mode="OBJECT")
        self.J, self.rig_ob, self.n_tail = J, rig, n_t
        return rig

    def skin(self, rig, body, rigid_parts, paddle):
        activate(rig, body)
        bpy.context.view_layer.objects.active = rig
        body.select_set(True)
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        me = body.data
        unweighted = sum(1 for v in me.vertices if not v.groups)
        if unweighted:
            self.say("WARN bone heat left %d vertices without weights: given to the nearest bone" % unweighted)
            self._nearest_bone(body, rig, [v.index for v in me.vertices if not v.groups])
        for ob in rigid_parts:
            g = ob.vertex_groups.new(name="Head")
            g.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        for ob in paddle:
            self._nearest_bone(ob, rig, list(range(len(ob.data.vertices))), only=[b.name for b in rig.data.bones if b.name.startswith("Tail")])
        activate(body, *rigid_parts, *paddle)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
        body = bpy.context.view_layer.objects.active
        body.name = body.data.name = "model"
        # the head rigid: ahead of a plane through the top of the neck (facing up and forward)
        J = self.J
        neck_dir = (J["Head"] - J["Neck"]).normalized()
        head_dir = (J["HeadEnd"] - J["Head"]).normalized()
        n = (neck_dir + head_dir).normalized()
        fade = 0.05 * self.U
        groups = {g.name: g for g in body.vertex_groups}
        hg = groups["Head"]
        rigid = 0
        n_body = len(self.vpart)  # the join keeps the body's own points first, in order
        head_parts = ("head", "snout", "cheek", "neck")
        for v in body.data.vertices:
            if v.index < n_body and self.vpart[v.index] not in head_parts:
                continue  # the plane runs on forever: never let it take a raised tail or the back
            d = (v.co - J["Head"]).dot(n)
            t = G.ease((d + fade) / fade)
            if t <= 0.0:
                continue
            for g in v.groups:
                if g.group != hg.index:
                    g.weight *= (1.0 - t)
            cur = sum(g.weight for g in v.groups if g.group != hg.index)
            hg.add([v.index], max(0.0, 1.0 - cur) if t < 1.0 else 1.0, "REPLACE")
            rigid += t >= 1.0
        for v in body.data.vertices:
            tot = sum(g.weight for g in v.groups)
            if tot > 0:
                for g in v.groups:
                    g.weight /= tot
        self.say("SKIN %d vertices on %d bones (%.0f per bone), %d rigid on the head" % (
            len(body.data.vertices), len(rig.data.bones), len(body.data.vertices) / len(rig.data.bones), rigid))
        return body

    def _nearest_bone(self, ob, rig, verts, only=None):
        segs = [(b.name, b.head_local, b.tail_local) for b in rig.data.bones if only is None or b.name in only]
        groups = {g.name: g for g in ob.vertex_groups}
        for vi in verts:
            co = ob.data.vertices[vi].co
            best, bn = 1e9, None
            for name, a, b in segs:
                ab = b - a
                t = max(0.0, min(1.0, (co - a).dot(ab) / max(ab.length_squared, 1e-9)))
                d = (co - (a + ab * t)).length
                if d < best:
                    best, bn = d, name
            g = groups.get(bn) or ob.vertex_groups.new(name=bn)
            groups[bn] = g
            g.add([vi], 1.0, "REPLACE")

    # --- 5. loops ------------------------------------------------------------------------------------
    def loops(self, rig, body):
        sp, J = self.sp, self.J
        stand_y = {"LF": J["LeftHand"].y, "RF": J["RightHand"].y, "LH": J["LeftFoot"].y, "RH": J["RightFoot"].y}
        stance = {"F": sp["leg_x"][0] * self.U, "H": sp["leg_x"][1] * self.U}
        g = G.Gaits(rig, body, self.U, stance, stand_y, tails=self.n_tail)
        L = J["LeftUpLeg"].z  # hip height
        tempo = math.sqrt(max(L, 0.05) / 0.37)  # bigger legs, slower steps (the dog's hip is 0.37 m)
        kind = sp.get("gait", "dog")
        still = {"phase": {"LH": 0, "LF": 0, "RH": 0, "RF": 0}, "duty": 1.0, "step": 0.0, "lift_fore": 0, "lift_hind": 0,
                 "fold_fore": 0, "fold_hind": 0, "crouch": 0.0, "cap": 0.92}
        tw = [0.0] * self.n_tail

        def tail_wave(t, amp, freq=1.0, lift=0.0):
            return [(lift, amp * math.sin(G.TAU * (t * freq - 0.18 * i))) for i in range(self.n_tail)]

        def idle(t):
            p = g.pose()
            br = math.sin(G.TAU * t * 3)
            shift = G.ease(0.5 + 0.5 * math.sin(G.TAU * (t - 0.1))) - 0.5
            look = G.bump(t, 0.1, 0.07, 0.18, 0.08) - 0.8 * G.bump(t, 0.55, 0.05, 0.12, 0.07)
            sniff = G.bump(t, 0.36, 0.06, 0.1, 0.07)
            twitch = math.sin(G.TAU * t * 14) * G.bump(t, 0.8, 0.02, 0.06, 0.03)
            g.body(p, dz=-still["crouch"] + 0.004 * self.U * br, dx=0.01 * self.U * shift, roll=1.5 * shift,
                   chest=(-0.8 * br, 0, -1.0 * shift), neck=(12.0 * sniff + 1.0 * br, 18.0 * look, 0),
                   head=(10.0 * sniff + 4 * twitch, 14.0 * look, 6.0 * G.bump(t, 0.2, 0.03, 0.08, 0.05)),
                   tail=tail_wave(t, 7.0 + 6.0 * G.bump(t, 0.7, 0.03, 0.15, 0.05), 3.0))
            g.paws(p, still, 0.0)
            return p

        S = L / 0.37  # the dog's gaits, scaled to this animal's legs
        if kind == "hop":
            walk_g = {"T": 0.5 * tempo, "duty": 0.42, "step": 0.22 * S, "phase": {"LF": 0.0, "RF": 0.05, "LH": 0.42, "RH": 0.42},
                      "lift_fore": 0.07 * S, "lift_hind": 0.09 * S, "fold_fore": 30, "fold_hind": 10, "crouch": 0.02 * S, "carry": 0.2}
            run_g = {"T": 0.34 * tempo, "duty": 0.34, "step": 0.3 * S, "phase": {"LF": 0.0, "RF": 0.06, "LH": 0.45, "RH": 0.45},
                     "lift_fore": 0.09 * S, "lift_hind": 0.09 * S, "fold_fore": 40, "fold_hind": 15, "crouch": 0.03 * S, "carry": 0.15}

            def hop(gg, amp):
                def f(t):
                    p = g.pose()
                    up = max(0.0, math.sin(G.TAU * (t - gg["duty"] * 0.6)))
                    g.body(p, dz=-gg["crouch"] + amp * 0.06 * self.U * up, pitch=-6.0 * amp * math.sin(G.TAU * (t - 0.3)),
                           arch=10.0 * amp * math.cos(G.TAU * (t - 0.9)), neck=(-4.0 * amp * up, 0, 0), head=(3.0 * amp * up, 0, 0),
                           tail=[(-10 * amp * up, 0)] * self.n_tail)
                    g.paws(p, gg, t)
                    return p
                return f
            walk_f, run_f = hop(walk_g, 0.6), hop(run_g, 1.0)
        else:
            walk_g = {"T": 0.6 * tempo, "duty": 0.64, "step": 0.25 * S, "phase": {"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75},
                      "lift_fore": 0.07 * S, "lift_hind": 0.055 * S, "fold_fore": 45, "fold_hind": 14, "crouch": 0.022 * S}
            if kind == "waddle":
                walk_g.update({"T": 0.75 * tempo, "step": 0.2 * S, "lift_fore": 0.05 * S, "lift_hind": 0.04 * S})
            if kind in ("bound", "hop"):
                run_g = {"T": 0.34 * tempo, "duty": 0.3, "step": 0.36 * S, "phase": {"LF": 0.0, "RF": 0.08, "LH": 0.5, "RH": 0.56},
                         "lift_fore": 0.1 * S, "lift_hind": 0.1 * S, "fold_fore": 50, "fold_hind": 20, "crouch": 0.03 * S, "carry": 0.18}
            elif kind == "waddle":
                run_g = {"T": 0.46 * tempo, "duty": 0.44, "step": 0.24 * S, "phase": {"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5},
                         "lift_fore": 0.06 * S, "lift_hind": 0.05 * S, "fold_fore": 40, "fold_hind": 14, "crouch": 0.03 * S, "carry": 0.25}
            else:  # a gallop, shorter than the dog's: these legs are half as long for the body
                run_g = {"T": 0.34 * tempo, "duty": 0.3, "step": 0.22 * S, "phase": {"LH": 0.0, "RH": 0.14, "RF": 0.50, "LF": 0.64},
                         "lift_fore": 0.08 * S, "lift_hind": 0.07 * S, "fold_fore": 60, "fold_hind": 25, "crouch": 0.035 * S, "carry": 0.16,
                         "narrow": 0.85}

            def walk_f(t):
                gg = walk_g
                p = g.pose()
                dip = math.cos(G.TAU * (t * 2 + 0.06))
                sway = math.sin(G.TAU * (t + 0.08))
                nod = math.sin(G.TAU * (t * 2 - 0.1))
                g.body(p, dz=-gg["crouch"] + 0.004 * S * dip, dx=0.007 * S * sway * (2.0 if kind == "waddle" else 1.0),
                       roll=1.8 * sway * (2.2 if kind == "waddle" else 1.0), yaw=2.2 * math.sin(G.TAU * t),
                       chest=(0.8 * dip, -3.4 * math.sin(G.TAU * t), -2.4 * sway), neck=(3.0 + 5.0 * nod, 1.2 * math.sin(G.TAU * t), 0),
                       head=(-4.0 * nod, 0, 1.4 * sway), tail=tail_wave(t, 9.0, 1.0, 4.0))
                g.paws(p, gg, t)
                return p

            def run_f(t):
                gg = run_g
                p = g.pose()
                if kind == "waddle":
                    bob = -math.cos(2 * G.TAU * (t - gg["duty"] / 2))
                    g.body(p, dz=-gg["crouch"] + 0.012 * S * bob, roll=3.0 * math.sin(G.TAU * t), pitch=0.6 * bob,
                           neck=(-3.0, 0, 0), head=(2.0, 0, 0), tail=tail_wave(t, 6.0, 1.0))
                else:
                    arch = 9.0 * math.cos(G.TAU * (t - 0.93))
                    pitch = 3.0 * math.sin(G.TAU * (t - 0.36))
                    height = 0.02 * S * math.cos(2 * G.TAU * (t - 0.42)) + 0.008 * S * math.cos(G.TAU * (t - 0.42))
                    reach = math.cos(G.TAU * (t - 0.40))
                    g.body(p, dz=-gg["crouch"] + height, pitch=pitch, arch=arch, dy=-0.012 * S * reach,
                           neck=(4.0 - 0.75 * arch - 0.7 * pitch + 5.0 * reach, 0, 0), head=(-2.0 - 0.3 * pitch - 3.0 * reach, 0, 0),
                           tail=[(-18 + 10 * math.cos(G.TAU * (t - 0.05 - 0.15 * i)), 0) for i in range(self.n_tail)])
                g.paws(p, gg, t)
                return p

        g.make_action("Idle", 6.0, idle, still)
        g.make_action("Walk", walk_g["T"], walk_f, walk_g)
        g.make_action("Run", run_g["T"], run_f, run_g)
        bpy.context.scene.render.fps = g.fps
        self.strides = g.strides
        self.say("STRIDE %s" % self.strides)

    # --- 6. export -----------------------------------------------------------------------------------
    def export(self, body, rig):
        out = os.path.join(PROJECT, "assets", "wildlife", self.sid + ".glb")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        activate(body, rig)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                                  export_image_format="JPEG", export_jpeg_quality=90, export_animations=True,
                                  export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                                  export_draco_mesh_compression_enable=False)
        tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
        self.say("EXPORTED %s: %d triangles, %d bones -> %s" % (self.sid, tris, len(rig.data.bones), os.path.relpath(out, PROJECT)))

    def run(self):
        reset()
        self.body()
        ears = self.ears()
        eyes = self.eyes()
        nose = self.nose()
        teeth = self.teeth()
        paddle = self.paddle()
        self.paint(self.body_ob, "body")
        for e in ears:
            self.paint(e, "ear")
        for o in [nose] + teeth:
            self.paint(o, "solid")
        objs = [self.body_ob] + ears + eyes + [nose] + teeth + paddle
        self.bake(objs)
        self.final_materials(objs)
        rig = self.rig()
        body = self.skin(rig, self.body_ob, ears + eyes + [nose] + teeth, paddle)
        self.loops(rig, body)
        out = os.path.join(HERE, "out", self.sid)
        os.makedirs(out, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, self.sid + ".blend"))
        if EXPORT:
            self.export(body, rig)
        if RENDER:
            import review
            review.render(self, body, rig, os.path.join(HERE, "review", self.sid))
        with open(os.path.join(out, "build_log.txt"), "w") as f:
            f.write("\n".join(self.log) + "\n")


class Paint:
    """What paint() knows about a point of the fur."""
    u = v = x = n = 0.0
    part = ""
    tail_s = 0.0
    ear_in = ear_out = ear_rim = ear_tuft = ear_s = 0.0
    spot = 0.0
    brow = 0.0
    head_like = 0.0

    def part_is(self, name):
        return 1.0 if self.part == name else 0.0

    @staticmethod
    def mix(a, b, t):
        a, b = srgb(a) if isinstance(a, str) else a, srgb(b) if isinstance(b, str) else b
        return tuple(x + (y - x) * t for x, y in zip(a, b))

    @staticmethod
    def over(c, col, t):
        col = srgb(col) if isinstance(col, str) else col
        t = max(0.0, min(1.0, t))
        return tuple(x + (y - x) * t for x, y in zip(c, col))


failed = []
for sid in IDS:
    try:
        Build(sid).run()
    except Exception as e:  # build the others, then fail
        import traceback
        traceback.print_exc()
        failed.append("%s: %s" % (sid, e))
if failed:
    raise SystemExit("FAILED " + "; ".join(failed))
