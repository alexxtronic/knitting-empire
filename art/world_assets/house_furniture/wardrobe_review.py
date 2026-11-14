"""Review renders of the wardrobe from the reference's camera (ref/wardrobe.png: front left, a level
camera 5.9 m off, eye 1.07 m, 59 mm, 1024 x 1536), in colour or clay, with the doors shut or open.

    Blender -b --factory-startup --python art/world_assets/house_furniture/wardrobe_review.py -- <out_dir> [ref|front|open|inside] [clay]

Then compare with the skill's compose_review.py (see wardrobe/wardrobe_log.md).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
view = argv[1] if len(argv) > 1 else "ref"
clay = "clay" in argv[2:]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "wardrobe", "out", "wardrobe.blend"))
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = int(os.environ.get("REVIEW_SAMPLES", 48))
sc.cycles.use_denoising = True
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.use_nodes = True
# the camera sees plain white, as the reference's background; the model gets a dimmer sky
nt = w.node_tree
bg = nt.nodes["Background"]
bg.inputs["Color"].default_value = (1, 1, 1, 1)
bg.inputs["Strength"].default_value = 0.4
white = nt.nodes.new("ShaderNodeBackground")
white.inputs["Color"].default_value = (1, 1, 1, 1)
lp = nt.nodes.new("ShaderNodeLightPath")
mix = nt.nodes.new("ShaderNodeMixShader")
nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
nt.links.new(bg.outputs[0], mix.inputs[1])
nt.links.new(white.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], nt.nodes["World Output"].inputs["Surface"])
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.6
sun.data.angle = math.radians(18)
sun.rotation_euler = (math.radians(55), 0, math.radians(30))   # the reference is lit from the front right: its left side is in shade
sc.collection.objects.link(sun)
if clay:
    cm = bpy.data.materials.new("clay")
    cm.use_nodes = True
    cm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.75, 0.75, 1)
    for ob in sc.objects:
        if ob.type == "MESH":
            ob.data.materials.clear()
            ob.data.materials.append(cm)
if view in ("open", "inside"):
    for name, sgn in (("door_l", 1), ("door_r", -1)):
        if name in bpy.data.objects:
            bpy.data.objects[name].rotation_euler.z = math.radians(sgn * -105)
obs = [o for o in sc.objects if o.type == "MESH"]
co = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
body = bpy.data.objects["model"]
cb = [body.matrix_world @ v.co for v in body.data.vertices if 0.6 < (body.matrix_world @ v.co).z < 1.6]
lo_body = Vector((min(c.x for c in cb), min(c.y for c in cb), 0))   # the carcass's front left corner
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.resolution_x, sc.render.resolution_y = 1024, 1536
cam.data.sensor_fit = "VERTICAL"
if view == "inside":   # roughly where her eyes are when she stands at it, looking in
    cam.data.lens = 22
    cam.location = Vector((0.0, -0.95, 1.55))
    cam.rotation_euler = (math.radians(84), 0, 0)
    sc.render.resolution_x, sc.render.resolution_y = 1280, 800
    cam.data.sensor_fit = "AUTO"
else:
    # the reference's camera, solved from its converging lines (wardrobe/wardrobe_log.md): level, eye
    # 1.07 m up, 24 degrees round to the left, 3760 px focal length, the front left corner 5.89 m deep
    # and 0.42 m left of the middle of the frame; the horizon 54 px under the middle
    a = math.radians(-24.0 if view != "front" else 0.0)
    cam.data.lens = 24.0 * 3760 / 1536
    fwd = Vector((-math.sin(a), math.cos(a), 0))
    right = Vector((math.cos(a), math.sin(a), 0))
    corner = Vector((lo_body.x, lo_body.y, 0)) if view != "front" else Vector((0, lo_body.y, 0))
    p = corner - fwd * 5.89 + (right * 0.4215 if view != "front" else Vector())
    cam.location = Vector((p.x, p.y, 1.07))
    cam.rotation_euler = (math.radians(90), 0, a)
    cam.data.shift_y = 54 / 1536
    cam.data.shift_x = 15 / 1536 if view != "front" else 0.0   # round 3: the carcass came out 15 px right
sc.render.filepath = os.path.join(out, "%s%s.png" % (view, "_clay" if clay else ""))
bpy.ops.render.render(write_still=True)
