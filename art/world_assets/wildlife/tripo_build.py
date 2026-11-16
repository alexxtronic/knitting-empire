"""The wild animals from Tripo: each split model re-textured, rigged and given its loops for the game.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/wildlife/tripo_build.py -- <id> [...] [--render] [--bones] [--no-export]

Alex (2026-11-14) found the script-built animals (build.py) "terrible, low poly" and asked for the
sheep's quality, made in Tripo, five animals to an image. tripo_split.py cuts each Tripo lineup into
out_tripo/<id>/<id>_src.blend (the full-detail mesh, standing on the ground facing -Y, at its height in
the game, with Tripo's 4K textures). For each animal this script:
  1. thins a copy to FACES triangles, unwraps it and bakes Tripo's colour and its normal detail (the
     full mesh's shape and its normal map) onto it at TEX px: the sheep's resolution;
  2. finds the joints (measure()): the paws where it touches the ground and the nose on the mesh; the
     spine, neck, head pivot and tail from HAND, read off each animal's side view on its 5 cm grid
     (out_tripo/<id>/views/side.png); the legs from the paws up to the shoulders and hips;
  3. builds the skeleton on blender-kiln's bone names (the same bones and loops as before, so the game
     doesn't change), skins it with bone-heat weights, and makes the head rigid (everything from the
     neck up follows the Head bone alone, so the face never shears);
  4. keys Idle, Walk and Run with gait.py (the dog's method: every paw solved to its spot on the
     ground, checked frame by frame);
  5. exports assets/wildlife/<id>.glb (never Draco: Godot can't read it) and prints each loop's
     STRIDE for data/wildlife.json.
--bones renders the measured skeleton over the model (out_tripo/<id>/bones.png) to check the joints;
--render renders the loops (review/<id>/tripo_*.png).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gait as G  # noqa: E402

PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
IDS = [a for a in argv if not a.startswith("--")]
RENDER = "--render" in argv
BONES = "--bones" in argv
EXPORT = "--no-export" not in argv
OUT = os.path.join(HERE, "out_tripo")
TEX = 2048
FACES = 30000

# gait: dog (walk, gallop), bound (mink, sable), waddle (beaver), hop (rabbit, chinchilla)
# tail: how many bones down the tail; ground_y: paws are only looked for in front of this (a beaver's
# paddle lies on the ground behind it)
SPECIES = {
    "coyote": {"gait": "dog", "tail": 3},
    "lynx": {"gait": "dog", "tail": 2},
    "fox": {"gait": "dog", "tail": 3},
    "raccoon": {"gait": "dog", "tail": 3},
    "beaver": {"gait": "waddle", "tail": 3},
    "rabbit": {"gait": "hop", "tail": 1},
    "chinchilla": {"gait": "hop", "tail": 3},
    "mink": {"gait": "bound", "tail": 3},
    "sable": {"gait": "bound", "tail": 3},
    "wolf_small": {"gait": "dog", "tail": 3},
    "wolf_medium": {"gait": "dog", "tail": 3},
    "wolf_large": {"gait": "dog", "tail": 3},
}
# The spine, neck, head pivot and tail, (y, z) in metres at x = 0, read off each animal's side view on
# its 5 cm grid (out_tripo/<id>/views/side.png). The paws (and so the legs' x and y) and the nose are
# found on the mesh. elbow, knee: the joint's height as a share of the shoulder's or hip's. ground_y:
# paws are only looked for in front of this (where a tail lies on the ground behind them). bend: how far
# the elbows and knees stand off the line to the paw (1 = the usual); short straight legs that have to
# crouch to walk at all (the rabbit's) need more.
HAND = {
    "fox": {"chest": (-0.13, 0.25), "hips": (0.12, 0.24), "neck": (-0.13, 0.32), "head": (-0.12, 0.37),
            "tail": [(0.18, 0.24), (0.33, 0.31), (0.40, 0.47), (0.53, 0.56)]},
    "coyote": {"chest": (-0.25, 0.42), "hips": (0.08, 0.42), "neck": (-0.31, 0.49), "head": (-0.36, 0.53),
               "tail": [(0.14, 0.50), (0.25, 0.32), (0.32, 0.17), (0.36, 0.05)], "elbow": 0.64, "ground_y": 0.2},
    "raccoon": {"chest": (-0.19, 0.18), "hips": (0.02, 0.18), "neck": (-0.21, 0.23), "head": (-0.23, 0.26),
                "tail": [(0.11, 0.20), (0.17, 0.15), (0.22, 0.09), (0.25, 0.04)], "ground_y": 0.08},
    "beaver": {"chest": (-0.17, 0.17), "hips": (0.0, 0.16), "neck": (-0.22, 0.22), "head": (-0.26, 0.26),
               "tail": [(0.10, 0.10), (0.17, 0.08), (0.23, 0.065), (0.30, 0.05)], "ground_y": 0.02},
    "rabbit": {"chest": (-0.06, 0.10), "hips": (0.08, 0.09), "neck": (-0.05, 0.15), "head": (-0.05, 0.18),
               "tail": [(0.12, 0.14), (0.18, 0.13)], "ear_reach": 2.8, "bend": 2.2},
    "sable": {"chest": (-0.17, 0.16), "hips": (0.02, 0.155), "neck": (-0.19, 0.20), "head": (-0.21, 0.235),
              "tail": [(0.06, 0.17), (0.12, 0.13), (0.17, 0.08), (0.20, 0.035)], "ground_y": 0.06},
    "lynx": {"chest": (-0.25, 0.47), "hips": (0.28, 0.46), "neck": (-0.32, 0.55), "head": (-0.36, 0.63),
             "tail": [(0.40, 0.55), (0.48, 0.58), (0.55, 0.62)], "elbow": 0.62},
    "chinchilla": {"chest": (-0.08, 0.08), "hips": (0.04, 0.07), "neck": (-0.08, 0.13), "head": (-0.08, 0.17),
                   "tail": [(0.10, 0.05), (0.18, 0.08), (0.20, 0.18), (0.25, 0.26)], "ground_y": 0.08,
                   "ear_reach": 2.4, "bend": 2.2},
    # the wolves (2026-11-16): the large one stands with its head lowered, the nose below the neck
    "wolf_small": {"chest": (-0.10, 0.27), "hips": (0.10, 0.25), "neck": (-0.13, 0.36), "head": (-0.18, 0.46),
                   "tail": [(0.165, 0.31), (0.23, 0.235), (0.28, 0.14), (0.30, 0.05)], "elbow": 0.6, "ground_y": 0.2},
    "wolf_medium": {"chest": (-0.32, 0.53), "hips": (0.09, 0.51), "neck": (-0.39, 0.66), "head": (-0.50, 0.77),
                    "tail": [(0.16, 0.62), (0.28, 0.50), (0.39, 0.30), (0.45, 0.06)], "elbow": 0.64, "ground_y": 0.25},
    "wolf_large": {"chest": (-0.50, 0.66), "hips": (0.25, 0.62), "neck": (-0.72, 0.78), "head": (-0.95, 0.86),
                   "tail": [(0.40, 0.86), (0.59, 0.625), (0.74, 0.36), (0.83, 0.09)], "elbow": 0.64, "ground_y": 0.42},
    "mink": {"chest": (-0.18, 0.135), "hips": (0.03, 0.135), "neck": (-0.20, 0.18), "head": (-0.24, 0.215),
             "tail": [(0.08, 0.15), (0.14, 0.11), (0.19, 0.065), (0.22, 0.02)], "ground_y": 0.06},
    # the shorn ones (Alex, 2026-11-16: every shearable animal has a naked form, shown from a comb until
    # its coat is back), from tripo/ref/shorn_1.png: slimmer, so read off their own side views
    "fox_shorn": {"chest": (-0.12, 0.23), "hips": (0.15, 0.22), "neck": (-0.12, 0.30), "head": (-0.13, 0.38),
                  "tail": [(0.22, 0.26), (0.31, 0.28), (0.39, 0.32), (0.45, 0.40)]},
    "coyote_shorn": {"chest": (-0.13, 0.40), "hips": (0.15, 0.40), "neck": (-0.17, 0.46), "head": (-0.21, 0.54),
                     "tail": [(0.22, 0.44), (0.30, 0.34), (0.37, 0.22), (0.41, 0.10)], "elbow": 0.64, "ground_y": 0.3},
    "lynx_shorn": {"chest": (-0.22, 0.44), "hips": (0.24, 0.44), "neck": (-0.25, 0.53), "head": (-0.29, 0.62),
                   "tail": [(0.33, 0.52), (0.41, 0.53), (0.48, 0.55)], "elbow": 0.62},
    "raccoon_shorn": {"chest": (-0.10, 0.18), "hips": (0.10, 0.17), "neck": (-0.12, 0.21), "head": (-0.12, 0.27),
                      "tail": [(0.17, 0.21), (0.22, 0.16), (0.27, 0.09), (0.30, 0.03)], "ground_y": 0.2},
    "beaver_shorn": {"chest": (-0.13, 0.18), "hips": (0.06, 0.16), "neck": (-0.15, 0.22), "head": (-0.16, 0.27),
                     "tail": [(0.15, 0.14), (0.22, 0.11), (0.30, 0.08), (0.38, 0.06)], "ground_y": 0.17},
    "rabbit_shorn": {"chest": (-0.06, 0.10), "hips": (0.07, 0.09), "neck": (-0.05, 0.15), "head": (-0.06, 0.19),
                     "tail": [(0.12, 0.13), (0.17, 0.15)], "ear_reach": 2.8, "bend": 2.2},
    "sable_shorn": {"chest": (-0.08, 0.15), "hips": (0.08, 0.14), "neck": (-0.10, 0.18), "head": (-0.11, 0.23),
                    "tail": [(0.13, 0.15), (0.18, 0.11), (0.23, 0.07), (0.27, 0.04)], "ground_y": 0.15},
    "mink_shorn": {"chest": (-0.09, 0.13), "hips": (0.09, 0.12), "neck": (-0.10, 0.17), "head": (-0.13, 0.22),
                   "tail": [(0.15, 0.14), (0.20, 0.10), (0.26, 0.06), (0.31, 0.03)], "ground_y": 0.18},
    "chinchilla_shorn": {"chest": (-0.06, 0.09), "hips": (0.06, 0.08), "neck": (-0.06, 0.13), "head": (-0.07, 0.17),
                         "tail": [(0.12, 0.08), (0.17, 0.07), (0.21, 0.09), (0.24, 0.13)], "ground_y": 0.12,
                         "ear_reach": 2.4, "bend": 2.2},
}
# joint -> (dx, dy, dz) metres added to what measure() found, for both sides of a leg pair when the
# name has no side ("Arm" moves LeftArm and RightArm, mirrored)
FIX = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def activate(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


class Build:
    def __init__(self, sid):
        self.sid = sid
        self.sp = SPECIES[sid[:-len("_shorn")] if sid.endswith("_shorn") else sid]  # a shorn one moves like its furry self
        self.log = []

    def say(self, *a):
        line = " ".join(str(x) for x in a)
        print(line)
        self.log.append(line)

    # --- 1. thin, unwrap, bake ----------------------------------------------------------------------
    def low(self, src):
        low = src.copy()
        low.data = src.data.copy()
        bpy.context.scene.collection.objects.link(low)
        low.name = low.data.name = "model"
        mod = low.modifiers.new("decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = min(1.0, FACES / max(1, len(src.data.polygons)))
        activate(low)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bm = bmesh.new()
        bm.from_mesh(low.data)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.to_mesh(low.data)
        bm.free()
        for p in low.data.polygons:
            p.use_smooth = True
        self.say("THINNED %s: %d -> %d triangles" % (self.sid, len(src.data.polygons), len(low.data.polygons)))
        return low

    def bake(self, src, low):
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 1
        H = self.H
        # the source's metal off, so the colour bake is its plain colour
        for m in src.data.materials:
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf:
                for l in list(bsdf.inputs["Metallic"].links):
                    m.node_tree.links.remove(l)
                bsdf.inputs["Metallic"].default_value = 0.0
        activate(low)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        col = bpy.data.images.new(self.sid + "_color", TEX, TEX, alpha=False)
        nor = bpy.data.images.new(self.sid + "_normal", TEX, TEX, alpha=False)
        nor.colorspace_settings.name = "Non-Color"
        m = bpy.data.materials.new(self.sid)
        m.use_nodes = True
        low.data.materials.clear()
        low.data.materials.append(m)
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tex = nt.nodes.new("ShaderNodeTexImage")
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = nor
        for img, kind, extra in ((col, "DIFFUSE", {"pass_filter": {"COLOR"}}), (nor, "NORMAL", {"normal_space": "TANGENT"})):
            tex.image = img
            nt.nodes.active = tex
            activate(low, src)
            bpy.context.view_layer.objects.active = low
            src.select_set(True)
            bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=0.012 * H,
                                max_ray_distance=0.04 * H, margin=12, **extra)
        # the game's material: the baked colour and normal, matte like fur
        tex.image = col
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ntex.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Roughness"].default_value = 0.88
        bsdf.inputs["Metallic"].default_value = 0.0
        out = os.path.join(OUT, self.sid)
        for img in (col, nor):
            img.filepath_raw = os.path.join(out, img.name + ".png")
            img.file_format = "PNG"
            img.save()
        self.say("BAKED %s colour and normal at %d px" % (self.sid, TEX))

    # --- 2. joints ------------------------------------------------------------------------------------
    def measure(self, ob):
        me = ob.data
        co = [v.co.copy() for v in me.vertices]
        H = self.H
        sp = self.sp
        say = self.say
        ground = [c for c in co if c.z < 0.035 * H and c.y < HAND[self.sid].get("ground_y", 9.0)]
        # fore and hind: two groups along the body
        a, b = min(c.y for c in ground), max(c.y for c in ground)
        for _ in range(30):
            cut = (a + b) / 2.0
            fore = [c for c in ground if c.y < cut]
            hind = [c for c in ground if c.y >= cut]
            a2, b2 = sum(c.y for c in fore) / len(fore), sum(c.y for c in hind) / len(hind)
            if abs(a2 - a) + abs(b2 - b) < 1e-6:
                break
            a, b = a2, b2
        paws = {}
        for key, grp in (("F", fore), ("H", hind)):
            for side, sgn in (("L", 1), ("R", -1)):
                pts = [c for c in grp if c.x * sgn > 0] or grp
                paws[side + key] = {"x": sum(c.x for c in pts) / len(pts), "y": sum(c.y for c in pts) / len(pts),
                                    "front": min(c.y for c in pts), "back": max(c.y for c in pts)}
        yf = (paws["LF"]["y"] + paws["RF"]["y"]) / 2
        yh = (paws["LH"]["y"] + paws["RH"]["y"]) / 2
        xf = (abs(paws["LF"]["x"]) + abs(paws["RF"]["x"])) / 2
        xh = (abs(paws["LH"]["x"]) + abs(paws["RH"]["x"])) / 2

        say("MEASURE %s: height %.3f, paws fore y %.3f x +-%.3f, hind y %.3f x +-%.3f" % (self.sid, H, yf, xf, yh, xh))
        hand = HAND[self.sid]

        def P(yz, x=0.0):
            return Vector((x, yz[0], yz[1]))
        J = {"Chest": P(hand["chest"]), "Hips": P(hand["hips"]), "Neck": P(hand["neck"]), "Head": P(hand["head"])}
        J["Spine1"] = J["Chest"].lerp(J["Hips"], 0.5)
        sh, hp = J["Chest"].z, J["Hips"].z
        ef, kf, bend = hand.get("elbow", 0.5), hand.get("knee", 0.55), hand.get("bend", 1.0)
        for side, sgn in (("Left", 1), ("Right", -1)):
            pf, ph = paws[("L" if sgn > 0 else "R") + "F"], paws[("L" if sgn > 0 else "R") + "H"]
            J[side + "Arm"] = Vector((pf["x"] * 0.85, pf["y"], sh))
            J[side + "ForeArm"] = Vector((pf["x"], pf["y"] + 0.12 * bend * sh, ef * sh))
            J[side + "Hand"] = Vector((pf["x"], pf["y"], max(0.03 * H, 0.2 * sh)))
            J[side + "HandEnd"] = Vector((pf["x"], pf["front"], 0.01 * H))
            J[side + "UpLeg"] = Vector((ph["x"] * 0.85, ph["y"] - 0.02, hp))
            J[side + "Leg"] = Vector((ph["x"], ph["y"] - 0.15 * bend * hp, kf * hp))
            J[side + "Foot"] = Vector((ph["x"], ph["y"] + 0.12 * hp, max(0.035 * H, 0.25 * hp)))
            J[side + "FootEnd"] = Vector((ph["x"], ph["front"], 0.01 * H))
        # the nose: the most forward point at the head's height
        up = [c for c in co if c.z > J["Neck"].z - 0.1 * H]
        tip = min(up, key=lambda c: c.y)
        J["HeadEnd"] = Vector((0, tip.y, tip.z))
        J["tail"] = [P(t) for t in hand.get("tail", [])]
        say("HEAD nose at y %.3f z %.3f; head %.3f m long; tail %d points" % (tip.y, tip.z, (J["HeadEnd"] - J["Head"]).length, len(J["tail"])))
        for name, d in FIX.get(self.sid, {}).items():
            d = Vector(d)
            if name in J:
                J[name] += d
            else:
                for side, sgn in (("Left", 1), ("Right", -1)):
                    if side + name in J:
                        J[side + name] += Vector((d.x * sgn, d.y, d.z))
        self.J = J
        self.stance = {"F": xf, "H": xh}
        return J

    # --- 3. rig ---------------------------------------------------------------------------------------
    def rig(self):
        J = self.J
        bones = [("Hips", J["Hips"], J["Spine1"], None), ("Spine1", J["Spine1"], J["Chest"], "Hips"),
                 ("Neck", J["Neck"], J["Head"], "Spine1"), ("Head", J["Head"], J["HeadEnd"], "Neck")]
        tpts = J.get("tail", [])
        self.n_tail = max(0, len(tpts) - 1)
        for i in range(self.n_tail):
            bones.append(("Tail%d" % (i + 1), tpts[i], tpts[i + 1], "Hips" if i == 0 else "Tail%d" % i))
        for side in ("Left", "Right"):
            bones += [(side + "Arm", J[side + "Arm"], J[side + "ForeArm"], "Spine1"),
                      (side + "ForeArm", J[side + "ForeArm"], J[side + "Hand"], side + "Arm"),
                      (side + "Hand", J[side + "Hand"], J[side + "HandEnd"], side + "ForeArm"),
                      (side + "UpLeg", J[side + "UpLeg"], J[side + "Leg"], "Hips"),
                      (side + "Leg", J[side + "Leg"], J[side + "Foot"], side + "UpLeg"),
                      (side + "Foot", J[side + "Foot"], J[side + "FootEnd"], side + "Leg")]
        ad = bpy.data.armatures.new(self.sid + "_rig")
        rig = bpy.data.objects.new("rig", ad)
        bpy.context.scene.collection.objects.link(rig)
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
        return rig

    def skin(self, rig, body):
        activate(rig, body)
        bpy.context.view_layer.objects.active = rig
        body.select_set(True)
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        me = body.data
        loose = [v.index for v in me.vertices if not v.groups or sum(g.weight for g in v.groups) < 1e-4]
        if loose:
            self.say("WARN bone heat left %d of %d vertices without weights: given to the nearest bone" % (len(loose), len(me.vertices)))
            self._nearest_bone(body, rig, loose)
        J = self.J
        head_len = (J["HeadEnd"] - J["Head"]).length
        neck_dir = (J["Head"] - J["Neck"]).normalized()
        head_dir = (J["HeadEnd"] - J["Head"]).normalized()
        n = (neck_dir + head_dir).normalized()
        fade = 0.06 * head_len + 0.01 * self.H
        groups = {g.name: g for g in body.vertex_groups}
        hg = groups.get("Head") or body.vertex_groups.new(name="Head")
        legs = {groups[k].index for k in groups if any(k.endswith(s) for s in ("Arm", "ForeArm", "Hand"))}
        rigid = 0
        for v in me.vertices:
            c = v.co
            # near the head: within its length of the skull's middle, or above it (the ears)
            mid = (J["Head"] + J["HeadEnd"]) / 2
            reach = HAND[self.sid].get("ear_reach", 1.9)
            near = (c - mid).length < 0.85 * head_len or (c.z > J["Head"].z and abs(c.y - J["Head"].y) < 0.9 * head_len
                                                          and (c - mid).length < reach * head_len)
            if not near:
                continue
            if any(g.group in legs and g.weight > 0.3 for g in v.groups):
                continue
            d = (c - J["Head"]).dot(n)
            t = G.ease((d + fade) / fade)
            if t <= 0.0:
                continue
            for g in v.groups:
                if g.group != hg.index:
                    g.weight *= (1.0 - t)
            cur = sum(g.weight for g in v.groups if g.group != hg.index)
            hg.add([v.index], max(0.0, 1.0 - cur) if t < 1.0 else 1.0, "REPLACE")
            rigid += t >= 1.0
        for v in me.vertices:
            tot = sum(g.weight for g in v.groups)
            if tot > 0:
                for g in v.groups:
                    g.weight /= tot
        self.say("SKIN %d vertices on %d bones, %d rigid on the head" % (len(me.vertices), len(rig.data.bones), rigid))

    def _nearest_bone(self, ob, rig, verts):
        segs = [(b.name, b.head_local, b.tail_local) for b in rig.data.bones]
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

    # --- 4. loops (as build.py's) ----------------------------------------------------------------------
    def loops(self, rig, body):
        J = self.J
        L = J["LeftUpLeg"].z  # hip height
        # The body's scale for bobs, breaths and the crouch search: its height, but no more than its
        # hips allow, so long ears (the rabbit's, the chinchilla's) don't make a small body bounce
        # like a big one.
        U = min(self.H, L / 0.35)
        stand_y = {"LF": J["LeftHand"].y, "RF": J["RightHand"].y, "LH": J["LeftFoot"].y, "RH": J["RightFoot"].y}
        g = G.Gaits(rig, body, U, self.stance, stand_y, tails=self.n_tail)
        tempo = math.sqrt(max(L, 0.05) / 0.37)
        kind = self.sp.get("gait", "dog")
        still = {"phase": {"LH": 0, "LF": 0, "RH": 0, "RF": 0}, "duty": 1.0, "step": 0.0, "lift_fore": 0, "lift_hind": 0,
                 "fold_fore": 0, "fold_hind": 0, "crouch": 0.0, "cap": 0.92}
        nt = self.n_tail

        def tail_wave(t, amp, freq=1.0, lift=0.0):
            return [(lift, amp * math.sin(G.TAU * (t * freq - 0.18 * i))) for i in range(nt)]

        def idle(t):
            p = g.pose()
            br = math.sin(G.TAU * t * 3)
            shift = G.ease(0.5 + 0.5 * math.sin(G.TAU * (t - 0.1))) - 0.5
            look = G.bump(t, 0.1, 0.07, 0.18, 0.08) - 0.8 * G.bump(t, 0.55, 0.05, 0.12, 0.07)
            sniff = G.bump(t, 0.36, 0.06, 0.1, 0.07)
            twitch = math.sin(G.TAU * t * 14) * G.bump(t, 0.8, 0.02, 0.06, 0.03)
            g.body(p, dz=-still["crouch"] + 0.004 * U * br, dx=0.01 * U * shift, roll=1.5 * shift,
                   chest=(-0.8 * br, 0, -1.0 * shift), neck=(12.0 * sniff + 1.0 * br, 18.0 * look, 0),
                   head=(10.0 * sniff + 4 * twitch, 14.0 * look, 6.0 * G.bump(t, 0.2, 0.03, 0.08, 0.05)),
                   tail=tail_wave(t, 7.0 + 6.0 * G.bump(t, 0.7, 0.03, 0.15, 0.05), 3.0))
            g.paws(p, still, 0.0)
            return p

        S = L / 0.37
        if kind == "hop":
            walk_g = {"T": 0.5 * tempo, "duty": 0.42, "step": 0.15 * S, "phase": {"LF": 0.0, "RF": 0.05, "LH": 0.42, "RH": 0.42},
                      "lift_fore": 0.07 * S, "lift_hind": 0.09 * S, "fold_fore": 30, "fold_hind": 10, "crouch": 0.02 * S, "carry": 0.2}
            run_g = {"T": 0.34 * tempo, "duty": 0.34, "step": 0.24 * S, "phase": {"LF": 0.0, "RF": 0.06, "LH": 0.45, "RH": 0.45},
                     "lift_fore": 0.09 * S, "lift_hind": 0.09 * S, "fold_fore": 40, "fold_hind": 15, "crouch": 0.03 * S, "carry": 0.15}

            def hop(gg, amp):
                def f(t):
                    p = g.pose()
                    up = max(0.0, math.sin(G.TAU * (t - gg["duty"] * 0.6)))
                    g.body(p, dz=-gg["crouch"] + amp * 0.1 * U * up, pitch=-6.0 * amp * math.sin(G.TAU * (t - 0.3)),
                           arch=10.0 * amp * math.cos(G.TAU * (t - 0.9)), neck=(-4.0 * amp * up, 0, 0), head=(3.0 * amp * up, 0, 0),
                           tail=[(-10 * amp * up, 0)] * nt)
                    g.paws(p, gg, t)
                    return p
                return f
            walk_f, run_f = hop(walk_g, 0.6), hop(run_g, 1.0)
        else:
            walk_g = {"T": 0.6 * tempo, "duty": 0.64, "step": 0.25 * S, "phase": {"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75},
                      "lift_fore": 0.07 * S, "lift_hind": 0.055 * S, "fold_fore": 45, "fold_hind": 14, "crouch": 0.022 * S}
            if kind == "waddle":
                walk_g.update({"T": 0.75 * tempo, "step": 0.2 * S, "lift_fore": 0.05 * S, "lift_hind": 0.04 * S})
            if kind == "bound":
                run_g = {"T": 0.34 * tempo, "duty": 0.3, "step": 0.36 * S, "phase": {"LF": 0.0, "RF": 0.08, "LH": 0.5, "RH": 0.56},
                         "lift_fore": 0.1 * S, "lift_hind": 0.1 * S, "fold_fore": 50, "fold_hind": 20, "crouch": 0.03 * S, "carry": 0.18}
            elif kind == "waddle":
                run_g = {"T": 0.46 * tempo, "duty": 0.44, "step": 0.24 * S, "phase": {"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5},
                         "lift_fore": 0.06 * S, "lift_hind": 0.05 * S, "fold_fore": 40, "fold_hind": 14, "crouch": 0.03 * S, "carry": 0.25}
            else:
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
                           tail=[(-18 + 10 * math.cos(G.TAU * (t - 0.05 - 0.15 * i)), 0) for i in range(nt)])
                g.paws(p, gg, t)
                return p

        def keyed(name, f, gg):
            """Keys a loop; if a short-legged animal can't fold a paw that close to its shoulder (the
            crouch its long stride needs leaves the lifted paw out of reach), shortens the stride and
            the lift a little at a time until every paw lands on its spot."""
            for tries in range(10):
                try:
                    g.make_action(name, gg["T"], f, gg)
                    return
                except AssertionError as e:
                    if "misses its spot" not in str(e) or tries == 9:
                        raise
                    for k in ("step", "lift_fore", "lift_hind"):
                        gg[k] *= 0.88
                    self.say("RETRY %s (%s): step now %.3f m" % (name, e, gg["step"]))

        g.make_action("Idle", 6.0, idle, still)
        keyed("Walk", walk_f, walk_g)
        keyed("Run", run_f, run_g)
        bpy.context.scene.render.fps = g.fps
        self.strides = g.strides
        self.say("STRIDE %s" % self.strides)

    # --- review -------------------------------------------------------------------------------------
    def render_bones(self, ob, path):
        sc = bpy.context.scene
        sc.render.engine = "BLENDER_WORKBENCH"
        sc.display.shading.light = "FLAT"
        sc.display.shading.color_type = "TEXTURE"
        sc.display.shading.show_xray = True
        sc.display.shading.xray_alpha = 0.5
        sc.render.resolution_x, sc.render.resolution_y = 1000, 1000
        sc.world = sc.world or bpy.data.worlds.new("w")
        sc.world.color = (1, 1, 1)
        red = bpy.data.materials.new("stick")
        red.diffuse_color = (1, 0, 0, 1)
        J = self.J
        pairs = [("Hips", "Spine1"), ("Spine1", "Chest"), ("Chest", "Neck"), ("Neck", "Head"), ("Head", "HeadEnd")]
        for side in ("Left", "Right"):
            pairs += [(side + "Arm", side + "ForeArm"), (side + "ForeArm", side + "Hand"), (side + "Hand", side + "HandEnd"),
                      (side + "UpLeg", side + "Leg"), (side + "Leg", side + "Foot"), (side + "Foot", side + "FootEnd")]
        segs = [(J[a], J[b]) for a, b in pairs]
        tp = J.get("tail", [])
        segs += list(zip(tp, tp[1:]))
        sticks = []
        for a, b in segs:
            d = b - a
            if d.length < 1e-5:
                continue
            bpy.ops.mesh.primitive_cylinder_add(radius=0.005 * self.H + 0.0015, depth=d.length, location=(a + b) / 2)
            s = bpy.context.object
            s.rotation_mode = "QUATERNION"
            s.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
            s.data.materials.append(red)
            sticks.append(s)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam.data.type = "ORTHO"
        size = max(ob.dimensions) * 1.1
        cam.data.ortho_scale = size
        zc = ob.dimensions.z / 2
        for name, loc, rot in (("side", (3, 0, zc), (90, 0, 90)), ("front", (0, -3, zc), (90, 0, 0)), ("top", (0, 0, 3), (0, 0, 0))):
            cam.location = loc
            cam.rotation_euler = [math.radians(a) for a in rot]
            sc.render.filepath = path + "_" + name + ".png"
            bpy.ops.render.render(write_still=True)
        for s in sticks:
            bpy.data.objects.remove(s)
        bpy.data.objects.remove(cam)
        sc.display.shading.show_xray = False

    def render_loops(self, body, rig, outdir):
        os.makedirs(outdir, exist_ok=True)
        sc = bpy.context.scene
        sc.render.engine = "BLENDER_WORKBENCH"
        sc.display.shading.light = "STUDIO"
        sc.display.shading.color_type = "TEXTURE"
        sc.display.shading.show_xray = False
        sc.render.resolution_x, sc.render.resolution_y = 700, 700
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = max(body.dimensions) * 1.35
        zc = body.dimensions.z / 2
        tracks = {t.name: t for t in rig.animation_data.nla_tracks}
        for t in tracks.values():
            t.mute = True
        for name in ("Idle", "Walk", "Run"):
            tr = tracks[name]
            tr.mute = False
            strip = tr.strips[0]
            n = int(strip.frame_end - strip.frame_start)
            for k, fr in enumerate((0.0, 0.25, 0.5, 0.75)):
                sc.frame_set(int(strip.frame_start + fr * n))
                for view, loc, rot in (("side", (3, 0, zc), (90, 0, 90)), ("q", (2.2, -2.2, 1.3 + zc), (66, 0, 45))):
                    cam.location = loc
                    cam.rotation_euler = [math.radians(a) for a in rot]
                    sc.render.filepath = os.path.join(outdir, "tripo_%s_%s_%d.png" % (name.lower(), view, k))
                    bpy.ops.render.render(write_still=True)
            tr.mute = True
        bpy.data.objects.remove(cam)

    # --- 5. export ------------------------------------------------------------------------------------
    def export(self, body, rig):
        out = os.path.join(PROJECT, "assets", "wildlife", self.sid + ".glb")
        activate(body, rig)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                                  export_image_format="JPEG", export_jpeg_quality=90, export_animations=True,
                                  export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                                  export_draco_mesh_compression_enable=False)
        tris = len(body.data.polygons)
        self.say("EXPORTED %s: %d triangles, %d bones -> %s" % (self.sid, tris, len(rig.data.bones), os.path.relpath(out, PROJECT)))

    def run(self):
        src_path = os.path.join(OUT, self.sid, self.sid + "_src.blend")
        bpy.ops.wm.open_mainfile(filepath=src_path)
        src = bpy.data.objects[self.sid + "_src"]
        self.H = max(v.co.z for v in src.data.vertices)
        low = self.low(src)
        self.measure(low)
        if BONES:
            self.render_bones(low, os.path.join(OUT, self.sid, "bones"))
        if not EXPORT and not RENDER:
            return
        self.bake(src, low)
        src.hide_render = True
        src.hide_set(True)
        rig = self.rig()
        self.skin(rig, low)
        self.loops(rig, low)
        bpy.data.objects.remove(src)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, self.sid, self.sid + ".blend"))
        if EXPORT:
            self.export(low, rig)
        if RENDER:
            self.render_loops(low, rig, os.path.join(HERE, "review", self.sid))
        with open(os.path.join(OUT, self.sid, "build_log.txt"), "w") as f:
            f.write("\n".join(self.log) + "\n")


if __name__ == "__main__":
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
