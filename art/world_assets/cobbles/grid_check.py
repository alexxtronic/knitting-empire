"""Lays the built tiles out as a grid, mixing the variants the way the game does (3 x 3 plaza
tiles, or a lane 1 m wide and 5 tiles long), and saves <kind>/grid.blend to render with the
harness and look for seams.

    Blender -b --factory-startup --python grid_check.py -- <kind> <variants>
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
kind, nvar = sys.argv[sys.argv.index("--") + 1], int(sys.argv[sys.argv.index("--") + 2])
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob)
coll = bpy.data.collections.new("KE_grid")
bpy.context.scene.collection.children.link(coll)
meshes = []
for v in range(nvar):
    path = os.path.join(HERE, kind, "out_%d" % v, "cobble_%s_%d.blend" % (kind, v))
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = ["model"]
    meshes.append(dst.objects[0].data)
W, H = (4.0, 2.0) if kind == "plaza" else (1.0, 0.8)
cells = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1)] if kind == "plaza" else [(0, j) for j in range(-2, 3)]
for n, (i, j) in enumerate(cells):
    ob = bpy.data.objects.new("tile", meshes[(n * 7 + 3) % nvar])
    ob.location = (i * W, j * H, 0)
    coll.objects.link(ob)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, kind, "grid.blend"))
