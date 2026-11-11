"""
Quick look renders of the master (Workbench, material colours, white background).

  Blender --background --python review/look.py -- --blend CH_Rowan_master.blend --out review/x \
      --name head --z 1.46 1.82 --views 0,45,90,180 [--hide CH_Rowan_Sweater,...] [--only ...] [--res 700]
      [--el 0] [--clay] [--wire] [--pose jaw=18,eyes=20:0]

Azimuth 0 looks at his front, 90 at his left side. Orthographic, so sizes compare with the reference.
"""
import bpy, sys, os, math, argparse
from mathutils import Vector, Matrix, Euler


def args():
    a = sys.argv
    a = a[a.index("--") + 1:] if "--" in a else []
    p = argparse.ArgumentParser()
    p.add_argument("--blend", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--name", default="look")
    p.add_argument("--z", type=float, nargs=2, default=[-0.02, 1.84])
    p.add_argument("--cx", type=float, default=0.0)
    p.add_argument("--cy", type=float, default=0.0)
    p.add_argument("--views", default="0,45,90,135,180")
    p.add_argument("--el", type=float, default=0.0)
    p.add_argument("--res", type=int, default=700)
    p.add_argument("--aspect", type=float, default=0.5)
    p.add_argument("--hide", default="")
    p.add_argument("--only", default="")
    p.add_argument("--clay", action="store_true")
    p.add_argument("--wire", action="store_true")
    p.add_argument("--pose", default="")
    p.add_argument("--lit", action="store_true", help="lit render with the real materials")
    p.add_argument("--samples", type=int, default=48)
    return p.parse_args(a)


def main():
    a = args()
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(a.blend))
    sc = bpy.context.scene
    hide = set(n for n in a.hide.split(",") if n)
    only = set(n for n in a.only.split(",") if n)
    low = bpy.data.collections.get("LOW")
    keep = set(o.name for o in low.all_objects)
    for o in bpy.data.objects:
        show = o.name in keep and o.name not in hide and (not only or o.name in only)
        if o.type == "ARMATURE":
            show = False
        o.hide_render = not show
        o.hide_viewport = not show
    for c in bpy.data.collections:
        c.hide_render = False
    # optional face pose, straight on the objects (no rig needed): jaw angle, eye yaw:pitch
    for item in [s for s in a.pose.split(",") if s]:
        k, v = item.split("=")
        if k == "jaw":
            pose_jaw(float(v))
        if k == "eyes":
            yaw, pitch = [float(t) for t in v.split(":")]
            for n in ("CH_Rowan_Eye_L", "CH_Rowan_Eye_R"):
                o = bpy.data.objects.get(n)
                if o:
                    o.rotation_euler = Euler((math.radians(pitch), 0, math.radians(yaw)))
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "SINGLE" if a.clay else "MATERIAL"
    sh.single_color = (0.72, 0.70, 0.68)
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_shadows = False
    sh.show_backface_culling = True
    sh.show_object_outline = False
    sc.display.render_aa = "8"
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("W")
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    if a.wire:
        for o in bpy.data.objects:
            if o.type == "MESH" and not o.hide_render:
                m = o.modifiers.new("W", "WIREFRAME")
                m.thickness = 0.0006
                m.use_replace = False
    h = a.z[1] - a.z[0]
    sc.render.resolution_y = a.res
    sc.render.resolution_x = int(a.res * a.aspect)
    cam_d = bpy.data.cameras.new("LookCam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = h
    cam_d.sensor_fit = "VERTICAL"
    cam_d.clip_end = 50
    cam = bpy.data.objects.new("LookCam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sh.background_type = "VIEWPORT"
    sh.background_color = (1, 1, 1)
    tgt = Vector((a.cx, a.cy, (a.z[0] + a.z[1]) / 2))
    os.makedirs(a.out, exist_ok=True)
    lights = None
    if a.lit:
        lights = studio(sc, a.samples)
    for v in [float(t) for t in a.views.split(",")]:
        az, el = math.radians(v), math.radians(a.el)
        d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
        cam.location = tgt + d * 5.0
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        if lights is not None:                       # the lights turn with the camera, like a turntable
            lights.rotation_euler = (0, 0, az)
        sc.render.filepath = os.path.join(a.out, "%s_%03d.png" % (a.name, int(v)))
        bpy.ops.render.render(write_still=True)
        print("LOOK", sc.render.filepath)


def studio(sc, samples):
    """Cycles, a white world and a soft key, fill and rim, all parented to one empty."""
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.device = "CPU"
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("LookWorld")
    if bpy.app.version < (5, 0, 0):
        w.use_nodes = True
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    out = next(n for n in nt.nodes if n.type == "OUTPUT_WORLD")
    bg.inputs[0].default_value = (1, 1, 1, 1)
    bg.inputs[1].default_value = 0.30                    # soft ambient light
    white = nt.nodes.new("ShaderNodeBackground")         # what the camera sees: plain white, like the reference
    white.inputs[0].default_value = (1, 1, 1, 1)
    white.inputs[1].default_value = 1.0
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(bg.outputs[0], mix.inputs[1])
    nt.links.new(white.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    sc.world = w
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    root = bpy.data.objects.new("LookLights", None)
    sc.collection.objects.link(root)
    for name, loc, energy, size, col in (("Key", (-2.2, -3.2, 3.4), 210, 2.5, (1.0, 0.96, 0.90)),
                                         ("Fill", (3.0, -2.4, 1.6), 55, 4.0, (0.92, 0.95, 1.0)),
                                         ("Rim", (1.2, 3.4, 3.0), 150, 2.0, (1.0, 0.97, 0.94))):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy, ld.size, ld.color = energy, size, col
        lo = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo)
        lo.parent = root
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 1.1)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return root


def pose_jaw(deg):
    """Rotate everything weighted to the Jaw group about the hinge, like the jaw bone will."""
    import numpy as np
    piv = Vector((0.0, 0.012, 1.628))
    for o in bpy.data.objects:
        if o.type != "MESH" or "Jaw" not in o.vertex_groups:
            continue
        gi = o.vertex_groups["Jaw"].index
        Rm = Matrix.Rotation(math.radians(deg), 4, "X")
        mw, mwi = o.matrix_world, o.matrix_world.inverted()
        for v in o.data.vertices:
            w = 0.0
            for g in v.groups:
                if g.group == gi:
                    w = g.weight
            if w <= 0:
                continue
            p = mw @ v.co
            q = piv + (Rm @ (p - piv))
            v.co = mwi @ (p.lerp(q, w))


main()
