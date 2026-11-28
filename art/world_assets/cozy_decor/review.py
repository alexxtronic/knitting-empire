"""Cycles renders of the built pieces against light grey, from the front right like the ChatGPT
references in ref/.

    Blender -b --factory-startup --python art/world_assets/cozy_decor/review.py -- <kind> [...]
    Blender -b --factory-startup --python art/world_assets/cozy_decor/review.py -- lineup [kind ...]

The first writes review/<kind>.png; `lineup` loads every built piece (or those named) into one
scene on a grid, each at its real size, and writes review/lineup.png.
Env: REVIEW_AZ (degrees, default 30), REVIEW_EL (default 20), REVIEW_SAMPLES (24), REVIEW_PX (420).
"""
import math
import os
import sys

import bpy

BIG = ("chaise_longue", "papasan_chair", "wingback_chair", "egg_chair", "scallop_chair", "floor_lounger", "arc_lamp", "tripod_lamp",
       "paper_lantern_lamp", "pleated_lamp", "tulip_lamp", "arch_mirror", "fiddle_fig", "floor_vase", "candle_stand", "plant_stand",
       "rug_checker", "rug_scallop", "rug_arch")
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
REVIEW = os.path.join(HERE, "review")
os.makedirs(REVIEW, exist_ok=True)
AZ = math.radians(float(os.environ.get("REVIEW_AZ", 30)))
EL = math.radians(float(os.environ.get("REVIEW_EL", 20)))


def stage():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("REVIEW_SAMPLES", 24))
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.82, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.6
    sun.data.angle = math.radians(18)
    sun.rotation_euler = (math.radians(42), 0, math.radians(-35))
    sc.collection.objects.link(sun)
    gm = bpy.data.materials.new("floor")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.62, 0.64, 1)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.001))
    bpy.context.object.data.materials.append(gm)
    return sc


def bounds(obs):
    co = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    return lo, hi


def shoot(sc, obs, path, px_w, px_h, dist=3.0):
    lo, hi = bounds(obs)
    ctr = (lo + hi) / 2
    size = max((hi - lo).x, (hi - lo).z, (hi - lo).y)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 55
    cam.data.clip_start = 0.01
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = ctr + Vector((math.sin(AZ) * math.cos(EL), -math.cos(AZ) * math.cos(EL), math.sin(EL))) * size * dist
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = px_w, px_h
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def append_model(kind):
    path = os.path.join(OUT, kind, kind + ".blend")
    with bpy.data.libraries.load(path) as (src, dst):
        dst.objects = [n for n in src.objects]
    obs = []
    for o in dst.objects:
        if o is not None and o.type == "MESH":
            bpy.context.scene.collection.objects.link(o)
            obs.append(o)
    return obs


args = sys.argv[sys.argv.index("--") + 1:]
px = int(os.environ.get("REVIEW_PX", 420))
if args and args[0] == "lineup":
    kinds = args[1:] or sorted(d for d in os.listdir(OUT) if os.path.isfile(os.path.join(OUT, d, d + ".blend")))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = stage()
    # big pieces in a back row, the toys in front, each spaced by its own width
    big = [k for k in kinds if k in BIG]
    small = [k for k in kinds if k not in big]
    allobs = []
    half = (len(big) + 1) // 2
    for row, ks, y, gap in ((0, big[:half], 2.2, 0.3), (1, big[half:], 0.0, 0.3), (2, small, -1.4, 0.15)):
        groups = [(k, append_model(k)) for k in ks]
        widths = [bounds(g)[1].x - bounds(g)[0].x for _, g in groups]
        x = -(sum(widths) + gap * (len(widths) - 1)) / 2
        for (k, g), w in zip(groups, widths):
            lo, hi = bounds(g)
            for o in g:
                o.location.x += x - lo.x
                o.location.y += y
            bpy.context.view_layer.update()
            x += w + gap
            allobs += g
    shoot(sc, allobs, os.path.join(REVIEW, "lineup.png"), 1600, 900, dist=1.7)
else:
    for kind in args:
        bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, kind, kind + ".blend"))
        sc = stage()
        obs = [o for o in bpy.data.objects if o.type == "MESH" and o.name not in ("Plane",)]
        obs = [o for o in obs if o.data.materials and o.data.materials[0] and o.data.materials[0].name != "floor"]
        shoot(sc, obs, os.path.join(REVIEW, kind + ".png"), px, px)
