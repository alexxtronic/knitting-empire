"""The birds from Tripo: a standing bird and a bird in flight in one rig, with Idle and Fly loops.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/wildlife/tripo_birds.py -- <sparrow|robin|gull ...> [--render]

tripo_split.py cut the birds out of the Tripo lineups (tripo/ref/lineup_2.png and lineup_3.png): each
standing bird, and a sparrow and a gull in flight with their wings raised. For each bird this script:
  1. thins both models and bakes Tripo's colour and normal detail onto each (tripo_build.py's way);
     the robin flies on the sparrow's wings, its pale feathers recoloured robin orange;
  2. scales the flying bird to the standing one's body and sets it where the standing body is;
  3. rigs them on one skeleton: Body and Head carry the standing bird, FlyBody and WingL / WingR the
     flying one, so bird.gd can swap them: in Idle the flying bird is scaled to nothing, in Fly the
     standing one;
  4. keys Idle (pecks and looks about) and Fly (one wingbeat) and exports assets/wildlife/<id>.glb.
--render writes review/<id>/tripo_{idle,fly}_{side,q}_N.png.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tripo_build as TB  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
IDS = [a for a in argv if not a.startswith("--")]
RENDER = "--render" in argv
OUT = TB.OUT
FPS = 60

# wings: which flying model; tex: map size; faces: per model; head: head radius as a share of the
# height; beat: seconds per wingbeat; idle: seconds of the Idle loop
BIRDS = {
    "sparrow": {"wings": "sparrow_fly", "tex": 1024, "faces": 16000, "head": 0.19, "beat": 0.2, "idle": 2.4},
    "robin": {"wings": "sparrow_fly", "tex": 1024, "faces": 16000, "head": 0.2, "beat": 0.2, "idle": 2.8, "recolour": True},
    "gull": {"wings": "gull_fly", "tex": 2048, "faces": 20000, "head": 0.13, "beat": 0.5, "idle": 3.2},
}
TINY = 1e-4  # "nothing": the hidden body's scale


def smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def bump(t, at, rise, hold, fall):
    t = t % 1.0
    if t < at:
        return 0.0
    x = t - at
    if x < rise:
        return smooth(0, 1, x / rise)
    if x < rise + hold:
        return 1.0
    return 1.0 - smooth(0, 1, min(1.0, (x - rise - hold) / fall))


def append_object(blend, name):
    with bpy.data.libraries.load(blend, link=False) as (src, dst):
        dst.objects = [name]
    ob = dst.objects[0]
    bpy.context.scene.collection.objects.link(ob)
    return ob


def baker(sid, H, tex, faces):
    b = TB.Build.__new__(TB.Build)
    b.sid, b.sp, b.log, b.H = sid, {}, [], H
    TB.TEX, TB.FACES = tex, faces
    os.makedirs(os.path.join(OUT, sid), exist_ok=True)
    return b


class Bird:
    def __init__(self, sid):
        self.sid = sid
        self.cfg = BIRDS[sid]
        self.log = []

    def say(self, *a):
        line = " ".join(str(x) for x in a)
        print(line)
        self.log.append(line)

    # --- 1. both models, thinned and baked --------------------------------------------------------
    def models(self):
        cfg = self.cfg
        bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, self.sid, self.sid + "_src.blend"))
        src = bpy.data.objects[self.sid + "_src"]
        wid = cfg["wings"]
        fsrc = append_object(os.path.join(OUT, wid, wid + "_src.blend"), wid + "_src")
        self.H = max(v.co.z for v in src.data.vertices)
        self.fit(src, fsrc)
        b = baker(self.sid, self.H, cfg["tex"], cfg["faces"])
        stand = b.low(src)
        stand.name = stand.data.name = "bird"
        b.bake(src, stand)
        fid = self.sid + "_fly"
        fb = baker(fid, self.H, cfg["tex"], cfg["faces"])
        fly = fb.low(fsrc)
        fly.name = fly.data.name = "bird_fly"
        fb.bake(fsrc, fly)
        if cfg.get("recolour"):
            self.recolour(bpy.data.images[fid + "_color"])
        self.log += b.log + fb.log
        for o in (src, fsrc):
            bpy.data.objects.remove(o)
        return stand, fly

    def fit(self, src, fsrc):
        """Scales the flying bird to the standing one: the same length from beak to tail along the
        body, its wings left out; and puts its body where the standing body is."""
        sc = np.array([v.co[:] for v in src.data.vertices])
        fc = np.array([v.co[:] for v in fsrc.data.vertices])
        self.half_w = 0.5 * (sc[:, 0].max() - sc[:, 0].min())
        core = fc[np.abs(fc[:, 0]) < 0.12 * np.ptp(fc[:, 0])]  # the body between the spread wings

        def length(p):
            q = p[:, 1:] - p[:, 1:].mean(0)
            w, v = np.linalg.eigh(q.T @ q)
            ax = v[:, -1]
            s = q @ ax
            return s.max() - s.min()

        k = length(sc) / length(core)
        me = fsrc.data
        me.transform(Matrix.Scale(k, 4))
        fc = fc * k
        core = core * k
        to = sc.mean(0) - core.mean(0)
        me.transform(Matrix.Translation(Vector(to)))
        me.update()
        self.say("FIT %s wings: scaled x%.3f, moved %.3f %.3f %.3f m" % (self.sid, k, *to))

    def recolour(self, img):
        """The robin flies on the sparrow's wings: its pale feathers (cheeks, breast, belly) turn robin
        orange and the browns go a little olive."""
        px = np.array(img.pixels[:]).reshape(-1, 4)
        rgb = px[:, :3]
        mx, mn = rgb.max(1), rgb.min(1)
        sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
        pale = np.clip((mx - 0.33) / 0.2, 0, 1) * np.clip((0.48 - sat) / 0.2, 0, 1)
        orange = np.array([0.80, 0.33, 0.09]) * (0.55 + 0.6 * mx[:, None])
        olive = rgb @ np.array([[0.85, 0.05, 0.0], [0.1, 0.9, 0.05], [0.05, 0.05, 0.95]])
        rgb[:] = olive * (1 - pale[:, None]) + orange * pale[:, None]
        px[:, :3] = np.clip(rgb, 0, 1)
        img.pixels[:] = px.ravel()
        img.save()
        self.say("RECOLOURED %s: %.0f%% of the map turned robin orange" % (img.name, 100 * (pale > 0.5).mean()))

    # --- 2. the skeleton ---------------------------------------------------------------------------
    def joints(self, stand, fly):
        H = self.H
        co = [v.co for v in stand.data.vertices]
        top = max(co, key=lambda c: c.z)
        r = self.cfg["head"] * H
        self.head_c = Vector((0, top.y, top.z - r))
        self.neck = self.head_c + Vector((0, 0.55 * r, -1.1 * r))
        self.head_r = r
        tip = min((c for c in co if c.z > 0.5 * H), key=lambda c: c.y)
        self.head_reach = max(2.8 * r, 1.15 * (tip - self.head_c).length)  # the whole beak goes with the head
        self.say("HEAD %s: crown at y %.3f z %.3f, beak tip y %.3f; neck at y %.3f z %.3f" % (
            self.sid, top.y, top.z, tip.y, self.neck.y, self.neck.z))
        # the wings' roots: where the flying bird's body ends at its sides
        fco = np.array([v.co[:] for v in fly.data.vertices])
        hw = self.fly_half_w = 0.75 * self.half_w
        root = fco[(np.abs(fco[:, 0]) > hw) & (np.abs(fco[:, 0]) < 1.4 * hw)]
        self.shoulder = Vector((hw, root[:, 1].mean(), root[:, 2].mean()))
        self.fly_c = Vector(fco[np.abs(fco[:, 0]) < hw].mean(0))
        self.say("WINGS %s: span %.3f m, roots at x %.3f y %.3f z %.3f" % (
            self.sid, np.ptp(fco[:, 0]), hw, self.shoulder.y, self.shoulder.z))

    def rig(self):
        H = self.H
        arm = bpy.data.armatures.new("rig")
        rig = bpy.data.objects.new("rig", arm)
        bpy.context.scene.collection.objects.link(rig)
        TB.activate(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        eb = arm.edit_bones

        def bone(name, head, tail, parent=None):
            b = eb.new(name)
            b.head, b.tail = head, tail
            if parent:
                b.parent = eb[parent]
            return b

        up = Vector((0, 0, 0.25 * H))
        bone("Root", Vector(), up)
        bone("Body", Vector(), up, "Root")
        bone("Head", self.neck, self.neck + (self.head_c - self.neck).normalized() * 0.6 * self.head_r * 2, "Body")
        bone("FlyBody", self.fly_c, self.fly_c + Vector((0, -0.2 * H, 0)), "Root")
        s = self.shoulder
        bone("WingL", Vector((s.x, s.y, s.z)), Vector((s.x + 0.3 * H, s.y, s.z + 0.1 * H)), "FlyBody")
        bone("WingR", Vector((-s.x, s.y, s.z)), Vector((-s.x - 0.3 * H, s.y, s.z + 0.1 * H)), "FlyBody")
        bpy.ops.object.mode_set(mode="OBJECT")
        return rig

    def skin(self, rig, stand, fly):
        r = self.head_r
        n = (self.head_c - self.neck).normalized()
        sg = {k: stand.vertex_groups.new(name=k) for k in ("Body", "Head")}
        heads = 0
        for v in stand.data.vertices:
            d = v.co - self.neck
            near = 1.0 - smooth(self.head_reach - 0.6 * r, self.head_reach, (v.co - self.head_c).length)
            w = smooth(-0.2 * r, 0.25 * r, d.dot(n)) * near
            if w > 0.001:
                sg["Head"].add([v.index], w, "REPLACE")
            if w < 0.999:
                sg["Body"].add([v.index], 1.0 - w, "REPLACE")
            heads += w > 0.5
        fg = {k: fly.vertex_groups.new(name=k) for k in ("FlyBody", "WingL", "WingR")}
        hw = self.fly_half_w
        wings = 0
        for v in fly.data.vertices:
            w = smooth(0.8 * hw, 1.25 * hw, abs(v.co.x))
            side = "WingL" if v.co.x > 0 else "WingR"
            if w > 0.001:
                fg[side].add([v.index], w, "REPLACE")
            if w < 0.999:
                fg["FlyBody"].add([v.index], 1.0 - w, "REPLACE")
            wings += w > 0.5
        for ob in (stand, fly):
            ob.parent = rig
            mod = ob.modifiers.new("rig", "ARMATURE")
            mod.object = rig
        self.say("SKIN %s: %d of %d standing vertices on the head, %d of %d flying vertices on the wings" % (
            self.sid, heads, len(stand.data.vertices), wings, len(fly.data.vertices)))

    # --- 3. loops ----------------------------------------------------------------------------------
    def loops(self, rig):
        REST = {b.name: b.matrix_local.copy() for b in rig.data.bones}

        def rot(name, axis, deg):
            R = REST[name].to_3x3()
            return (R.inverted() @ Matrix.Rotation(math.radians(deg), 3, axis) @ R).to_quaternion()

        def shift(name, v):
            return REST[name].to_3x3().inverted() @ v

        X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
        H = self.H

        def idle(t):
            peck = max(bump(t, 0.12, 0.06, 0.05, 0.08), bump(t, 0.30, 0.06, 0.04, 0.08), 0.8 * bump(t, 0.66, 0.07, 0.05, 0.09))
            look = bump(t, 0.47, 0.05, 0.1, 0.06) - bump(t, 0.83, 0.05, 0.08, 0.06)
            breathe = math.sin(2 * math.pi * t * 4)
            return {
                "Body": (rot("Body", X, 24 * peck) @ rot("Body", Z, 6 * look), shift("Body", Vector((0, 0, 0.004 * H * breathe))), 1.0),
                "Head": (rot("Head", X, 38 * peck - 6 * look * look) @ rot("Head", Z, 34 * look), None, 1.0),
                "FlyBody": (Quaternion(), None, TINY),
            }

        def fly(t):
            down = 35 - 45 * math.cos(2 * math.pi * t)  # 0: wings up as modelled; up to 80 degrees down
            bob = math.sin(2 * math.pi * (t - 0.25))
            return {
                "Body": (Quaternion(), None, TINY),
                "FlyBody": (rot("FlyBody", X, -3 * bob), shift("FlyBody", Vector((0, 0, 0.03 * H * bob))), 1.0),
                "WingL": (rot("WingL", Y, down), None, 1.0),
                "WingR": (rot("WingR", Y, -down), None, 1.0),
            }

        rig.animation_data_create()
        pb = rig.pose.bones
        for b in pb:
            b.rotation_mode = "QUATERNION"
        for name, secs, f in (("Idle", self.cfg["idle"], idle), ("Fly", self.cfg["beat"], fly)):
            act = bpy.data.actions.new(name)
            act.use_fake_user = True
            rig.animation_data.action = act
            frames = max(2, int(round(secs * FPS)))
            for fr in range(frames + 1):
                pose = f(fr / frames)
                for b in pb:
                    q, loc, s = pose.get(b.name, (Quaternion(), None, 1.0))
                    b.rotation_quaternion = q
                    b.location = loc if loc is not None else Vector()
                    b.scale = (s, s, s)
                    b.keyframe_insert("rotation_quaternion", frame=fr + 1)
                    b.keyframe_insert("location", frame=fr + 1)
                    b.keyframe_insert("scale", frame=fr + 1)
            track = rig.animation_data.nla_tracks.new()
            track.name = name
            track.strips.new(name, 1, act)
            rig.animation_data.action = None
            self.say("LOOP %s: %d frames, %.2f s" % (name, frames, secs))
        for b in pb:
            b.rotation_quaternion = Quaternion()
            b.location = Vector()
            b.scale = (1, 1, 1)

    # --- 4. out ------------------------------------------------------------------------------------
    def export(self, rig, stand, fly):
        out = os.path.join(TB.PROJECT, "assets", "wildlife", self.sid + ".glb")
        TB.activate(stand, fly, rig)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                                  export_image_format="JPEG", export_jpeg_quality=90, export_animations=True,
                                  export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                                  export_draco_mesh_compression_enable=False)
        self.say("EXPORTED %s: %d + %d triangles, %d bones -> %s" % (
            self.sid, len(stand.data.polygons), len(fly.data.polygons), len(rig.data.bones), os.path.relpath(out, TB.PROJECT)))

    def render(self, rig, outdir):
        os.makedirs(outdir, exist_ok=True)
        sc = bpy.context.scene
        sc.render.engine = "BLENDER_WORKBENCH"
        sc.display.shading.light = "STUDIO"
        sc.display.shading.color_type = "TEXTURE"
        sc.render.resolution_x = sc.render.resolution_y = 600
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam.data.type = "ORTHO"
        H = self.H
        tracks = {t.name: t for t in rig.animation_data.nla_tracks}
        for t in tracks.values():
            t.mute = True
        for name in ("Idle", "Fly"):
            tr = tracks[name]
            tr.mute = False
            strip = tr.strips[0]
            n = int(strip.frame_end - strip.frame_start)
            cam.data.ortho_scale = (2.6 if name == "Fly" else 1.6) * H
            zc = (0.7 if name == "Fly" else 0.5) * H
            for k, fr in enumerate((0.0, 0.17, 0.33, 0.5, 0.67, 0.83) if name == "Idle" else (0.0, 0.25, 0.5, 0.75)):
                sc.frame_set(int(strip.frame_start + fr * n))
                for view, loc, rt in (("side", (3, 0, zc), (90, 0, 90)), ("q", (2.0, -2.0, 1.6 + zc), (60, 0, 45))):
                    cam.location = loc
                    cam.rotation_euler = [math.radians(a) for a in rt]
                    sc.render.filepath = os.path.join(outdir, "tripo_%s_%s_%d.png" % (name.lower(), view, k))
                    bpy.ops.render.render(write_still=True)
            tr.mute = True
        bpy.data.objects.remove(cam)

    def run(self):
        stand, fly = self.models()
        self.joints(stand, fly)
        rig = self.rig()
        self.skin(rig, stand, fly)
        self.loops(rig)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, self.sid, self.sid + ".blend"))
        self.export(rig, stand, fly)
        if RENDER:
            self.render(rig, os.path.join(HERE, "review", self.sid))
        with open(os.path.join(OUT, self.sid, "build_log.txt"), "w") as f:
            f.write("\n".join(self.log) + "\n")


if __name__ == "__main__":
    failed = []
    for sid in IDS:
        try:
            Bird(sid).run()
        except Exception as e:
            import traceback
            traceback.print_exc()
            failed.append("%s: %s" % (sid, e))
    if failed:
        raise SystemExit("FAILED " + "; ".join(failed))
