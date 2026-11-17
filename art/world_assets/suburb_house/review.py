"""Review renders of the Bretton Oaks house, compared with Alex's reference photo.

    Blender -b art/world_assets/suburb_house/out/building_suburb_house.blend --python art/world_assets/suburb_house/review.py -- <round>

Writes review/<round>_*.png: the reference camera (street level, a little right of centre, a long
lens), a three-quarter from the left, the back, the game's overhead three-quarter, the reference
view in clay, and <round>_compare.png with the reference above the render. The brick and the
shingles are drawn with the game's own maps (assets/textures/house, as scripts/building_skin.gd
puts them on), the arborvitae and the shrub stand where the photo has them, small renders.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
rnd = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(HERE, "review")
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = int(os.environ.get("SAMPLES", 24))
sc.cycles.use_denoising = True
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.85, 0.88, 0.92, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 2.6
sun.data.angle = math.radians(25)
sun.rotation_euler = (math.radians(55), 0, math.radians(-30))
sc.collection.objects.link(sun)
ground = bpy.data.meshes.new("ground")
ground.from_pydata([(-40, -40, 0), (40, -40, 0), (40, 40, 0), (-40, 40, 0)], [], [(0, 1, 2, 3)])
g = bpy.data.objects.new("ground", ground)
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.36, 0.08, 1)
ground.materials.append(gm)
sc.collection.objects.link(g)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
parts = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "ground"]
for o in parts:
    o.hide_render = o.name.endswith("_low")


def skin(mat_name, tex, tint, scale):
    """Like BuildingSkin: the house's map, box-projected in world space, tinted to the surface's colour."""
    m = bpy.data.materials.get(mat_name)
    if m is None:
        return
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(PROJECT, "assets", "textures", "house", tex + ".png"))
    t.projection = "BOX"
    t.projection_blend = 0.2
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / scale, 1 / scale, 1 / scale)
    nt.links.new(co.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], t.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(t.outputs["Color"], mix.inputs["A"])
    if len(tint) == 3:  # a target colour: tint the map so it averages to it, as BuildingSkin does
        import numpy as np
        px = np.array(t.image.pixels[:]).reshape(-1, 4)[:, :3].mean(0)
        lin = [c ** 2.2 for c in tint]
        tint = tuple(min(1.7, max(0.15, lin[i] / max(px[i], 0.02))) for i in range(3)) + (1.0,)
    mix.inputs["B"].default_value = tint
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])


skin("suburb_brick", "brick", (0.54, 0.29, 0.21), 2.0)
skin("suburb_roof_shake", "shingles", (0.37, 0.365, 0.353), 1.0)


def plant(path, loc, s=1.0):
    if not os.path.exists(path):
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    for o in set(bpy.data.objects) - before:
        if o.parent is None:
            o.location = loc
            o.scale = (s, s, s)


props = os.path.join(PROJECT, "assets", "props")
for x in (0.3, 2.45, 4.6):  # the three arborvitae before the right wing (the photo's)
    plant(os.path.join(props, "arborvitae.glb"), (x, -5.3, 0), 1.0)
plant(os.path.join(props, "red_shrub.glb"), (7.6, -4.6, 0), 1.0)


def shot(name, az, el, dist, look=(0, -1, 2.0), lens=50, res=(741, 370), shift=0.0):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam.data.shift_y = shift
    a, e = math.radians(az), math.radians(el)
    loc = Vector(look) + dist * Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(look) - loc).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (rnd, name))
    bpy.ops.render.render(write_still=True)


# the reference (741 x 370): eave to eave (13.9 m here) is 67 % of the width, seen from the street a
# little right of centre at about eye height; the frame is centred a little right of the door.
REF = dict(az=8, el=0.5, dist=31.0, look=(0.6, -3.0, 2.2), lens=50, shift=-0.015)  # a street-view camera at about 2.5 m
shot("ref_cam", **REF)
shot("q_left", -40, 18, 34, look=(0, 0, 2.0), res=(640, 400))
shot("back", 160, 15, 34, look=(0, 0, 2.0), res=(640, 400))
shot("game", 20, 48, 40, look=(0, 0, 1.5), res=(640, 400))
clay = bpy.data.materials.new("clay")
clay.use_nodes = True
clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.75, 0.75, 1)
for o in bpy.data.objects:
    if o.type == "MESH" and o.name != "ground":
        for i in range(len(o.data.materials)):
            o.data.materials[i] = clay
shot("clay_ref_cam", **REF)

try:
    import numpy as np
    ref = bpy.data.images.load(os.path.join(HERE, "ref", "bretton_oaks_house.png"))
    ren = bpy.data.images.load(os.path.join(OUT, "%s_ref_cam.png" % rnd))
    a = np.array(ref.pixels[:]).reshape(ref.size[1], ref.size[0], 4)
    b = np.array(ren.pixels[:]).reshape(ren.size[1], ren.size[0], 4)
    both = np.concatenate([b, a], 0)  # Blender's rows run bottom up: the reference ends up on top
    img = bpy.data.images.new("compare", both.shape[1], both.shape[0], alpha=True)
    img.pixels[:] = both.ravel()
    img.filepath_raw = os.path.join(OUT, "%s_compare.png" % rnd)
    img.file_format = "PNG"
    img.save()
except Exception as e:
    print("compare failed:", e)
print("REVIEW", OUT)
