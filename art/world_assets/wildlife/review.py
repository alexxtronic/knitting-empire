"""Review pictures for a built animal (called by build.py --render, inside Blender).

Writes to review/<id>/:
  side.png         the reference's side view: orthographic, nose to the left, transparent ground
  side_clay.png    the same in grey clay (the shape alone)
  threeq.png       the reference's front three-quarter view (we see its left side)
  loop_<name>.png  six moments of each loop from the side, on one strip
sheet.py lays them beside the reference; the blender-image-to-3d skill's compose_review.py measures
the side view's silhouette against the reference's.
"""
import math
import os

import bpy
from mathutils import Vector


def _engine(sc):
    for e in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = e
            return
        except TypeError:
            pass


def _bounds(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [ev.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def _look(cam, target):
    d = target - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def _setup(sc):
    _engine(sc)
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    w = sc.world or bpy.data.worlds.new("review")
    sc.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.62, 0.66, 0.72, 1)
    bg.inputs[1].default_value = 0.9
    for name, rot, power in (("key", (math.radians(50), math.radians(10), math.radians(-35)), 3.2),
                             ("rim", (math.radians(60), 0, math.radians(150)), 1.2)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = power
        ld.angle = math.radians(8)
        lo = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo)
        lo.rotation_euler = rot
    cd = bpy.data.cameras.new("review")
    cam = bpy.data.objects.new("review", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def _side(sc, cam, lo, hi, px):
    c = (lo + hi) / 2
    size = max(hi.y - lo.y, hi.z - lo.z) * 1.08
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size
    cam.location = Vector((hi.x + 5.0, c.y, c.z))
    cam.data.clip_end = 20
    _look(cam, Vector((c.x, c.y, c.z)))
    sc.render.resolution_x = sc.render.resolution_y = px


def ref_box(path):
    """The side view's figure in the reference sheet, as grid.py measured it: (width / height, px w, px h)."""
    import numpy as np
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
    ink = a.min(axis=2) < 225 / 255.0
    cols = ink.sum(axis=0) > 2
    best, run = (0, 0), 0
    for x in range(w // 4, 3 * w // 4):
        if not cols[x]:
            run += 1
            if run > best[0]:
                best = (run, x - run + 1)
        else:
            run = 0
    split = best[1] + best[0] // 2 if best[0] > 5 else w // 2
    ys, xs = np.where(ink[:, :split])
    fw, fh = int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)
    return fw / fh, fw, fh


def _world_side(sc, cam, b, path):
    """The side view framed on the reference's own grid: u from the nose (0) to the figure's far end,
    v from the ground (0) to its top (1), so the render lies on the reference pixel for pixel."""
    aspect, fw, fh = ref_box(path)
    k = 1024.0 / max(fw, fh)
    sc.render.resolution_x, sc.render.resolution_y = int(round(fw * k)), int(round(fh * k))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(aspect, 1.0) * b.U
    a, z = b.P(0, 0), b.P(aspect, 1)
    cam.location = Vector((5.0, (a.y + z.y) / 2, b.U / 2))
    cam.data.clip_end = 20
    _look(cam, Vector((0, cam.location.y, cam.location.z)))


def render(b, body, rig, out):
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    cam = _setup(sc)
    sc.frame_set(1)
    if rig.animation_data:
        for t in rig.animation_data.nla_tracks:
            t.mute = True
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    lo, hi = _bounds(body)
    _world_side(sc, cam, b, os.path.join(os.path.dirname(out), "..", "ref", b.sid + ".png"))
    sc.render.filepath = os.path.join(out, "side_world.png")
    bpy.ops.render.render(write_still=True)
    _side(sc, cam, lo, hi, 1024)
    sc.render.filepath = os.path.join(out, "side.png")
    bpy.ops.render.render(write_still=True)
    clay = bpy.data.materials.new("clay")
    clay.use_nodes = True
    bs = next(n for n in clay.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bs.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    bs.inputs["Roughness"].default_value = 0.7
    vl = bpy.context.view_layer
    vl.material_override = clay
    sc.render.filepath = os.path.join(out, "side_clay.png")
    bpy.ops.render.render(write_still=True)
    vl.material_override = None
    # front three-quarter, perspective, seeing its left side
    c = (lo + hi) / 2
    cam.data.type = "PERSP"
    cam.data.lens = 50
    d = Vector((0.62, -0.78, 0.12)).normalized()
    span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    cam.location = c + d * span * 2.6
    _look(cam, c)
    sc.render.resolution_x, sc.render.resolution_y = 1024, 1024
    sc.render.filepath = os.path.join(out, "threeq.png")
    bpy.ops.render.render(write_still=True)
    # the loops, six moments each, from the side
    if rig.animation_data:
        for t in rig.animation_data.nla_tracks:
            act = t.strips[0].action
            rig.animation_data.action = act
            if hasattr(rig.animation_data, "action_slot") and rig.animation_data.action_slot is None and len(act.slots):
                rig.animation_data.action_slot = act.slots[0]
            f0, f1 = act.frame_range
            for i in range(6):
                f = int(round(f0 + (f1 - f0) * i / 6))
                sc.frame_set(f)
                _side(sc, cam, lo - Vector((0, 0.1 * b.U, 0.05 * b.U)), hi + Vector((0, 0.1 * b.U, 0.05 * b.U)), 384)
                sc.render.filepath = os.path.join(out, "loop_%s_%d.png" % (t.name, i))
                bpy.ops.render.render(write_still=True)
            rig.animation_data.action = None
    print("REVIEW pictures in", out)
