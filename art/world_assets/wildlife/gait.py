"""Loops for a four-legged animal on kiln's bone names, every paw solved to its spot on the ground.

The method is tools/rig_dog.py's (the dog the game already plays with), taken out of that script so
every wild animal can use it: each paw follows a path over the ground and its leg is solved to reach
it from wherever the body is that frame, so a planted paw stays exactly where it was put. Every frame
of every loop is checked: no leg straighter than its cap, no planted paw more than a millimetre off.

    g = Gaits(rig, mesh, S, stance_x, stand_y)
    g.make_action("Walk", WALK_T, g.walk_fn(WALK), WALK)

Bones (built by build.py): Hips, Spine1, Neck, Head, Tail1..TailN, {Left,Right}{Arm,ForeArm,Hand}
and {Left,Right}{UpLeg,Leg,Foot}. Blender front is -Y, up +Z, the animal's left +X.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

X, Yax, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
TAU = math.tau
MAX_EXTENSION = 0.95
LEGS = {  # key: upper, lower, paw bones; which way the middle joint points (+1 elbow back, -1 knee forward)
    "LF": ("LeftArm", "LeftForeArm", "LeftHand", 1.0), "RF": ("RightArm", "RightForeArm", "RightHand", 1.0),
    "LH": ("LeftUpLeg", "LeftLeg", "LeftFoot", -1.0), "RH": ("RightUpLeg", "RightLeg", "RightFoot", -1.0),
}


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ease(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def bump(t, at, rise, hold, fall):
    """0 -> 1 -> 0: eases up from `at` over `rise`, holds, eases back (loop time 0..1)."""
    x = (t - at) % 1.0
    if x < rise:
        return ease(x / rise)
    if x < rise + hold:
        return 1.0
    return 1.0 - ease(min(1.0, (x - rise - hold) / fall))


def path(u, duty, step, lift, carry=0.3):
    """Where a paw is at stride phase u, as (metres back of its standing spot, height, how far through
    the swing: -1 on the ground). On the ground it travels back at a steady pace; in the air it swings
    forward past its landing spot and is already moving back when it lands."""
    if u < duty:
        return step * (u / duty - 0.5), 0.0, -1.0
    w = (u - duty) / (1.0 - duty)
    m = carry * step * (1.0 - duty) / duty
    h00, h10, h01, h11 = 2 * w ** 3 - 3 * w ** 2 + 1, w ** 3 - 2 * w ** 2 + w, -2 * w ** 3 + 3 * w ** 2, w ** 3 - w ** 2
    y = h00 * step * 0.5 + h10 * m + h01 * -step * 0.5 + h11 * m
    z = lift * math.sin(math.pi * w) ** 1.2 * (1.0 - 0.3 * w)
    return y, z, w


class Gaits:
    def __init__(self, rig, ob, S, stance_x, stand_y, fps=60, tails=0):
        self.rig, self.ob, self.S, self.fps = rig, ob, S, fps
        self.me = ob.data
        ad = rig.data
        self.REST = {b.name: b.matrix_local.copy() for b in ad.bones}
        self.PARENT = {b.name: (b.parent.name if b.parent else None) for b in ad.bones}
        self.tails = tails
        self.stance_x = stance_x
        self.stand_y = stand_y
        self.groups = {g.name: g for g in ob.vertex_groups}
        self.PAW = self._paw_setup()
        self.LEN = {k: ((self.REST[lo].translation - self.REST[up].translation).length,
                        (self.REST[paw].translation - self.REST[lo].translation).length)
                    for k, (up, lo, paw, _s) in LEGS.items()}
        self.strides = {}
        for b in rig.pose.bones:
            b.rotation_mode = "QUATERNION"

    # --- setup -------------------------------------------------------------------------------------
    def _paw_setup(self):
        """Each paw's sole: turned level about the wrist or hock, and how high that joint then sits."""
        out = {}
        me = self.me
        for key, (up, lo, paw, _s) in LEGS.items():
            gi = self.groups[paw].index
            mine = [v.index for v in me.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
            pivot = self.REST[paw].translation
            n = Vector()
            for i in mine:
                if me.vertices[i].normal.z < -0.6:
                    n += me.vertices[i].normal
            level = 0.0
            if n.length > 0:
                n.normalize()
                level = -math.degrees(math.atan2(n.y, -n.z))
            r = rot_x(level)
            low = min((r @ (me.vertices[i].co - pivot)).z for i in mine) if mine else -pivot.z
            out[key] = {"level": level, "height": -low, "verts": len(mine)}
            print("PAW %s: %d vertices, sole %.0f deg off level, joint %.3f m above the ground" % (key, len(mine), level, -low))
        return out

    def basis_rot(self, name, axis, deg):
        """A rotation about an axis of the model (not the bone), as the bone's own rotation."""
        r = Matrix.Rotation(math.radians(deg), 3, axis)
        R = self.REST[name].to_3x3()
        return (R.inverted() @ r @ R).to_quaternion()

    # --- a pose ------------------------------------------------------------------------------------
    def pose(self):
        return _Pose(self)

    def paws(self, p, gait, t, shift=None):
        """Sets every paw on its path for this moment of a gait."""
        for key, phase in gait["phase"].items():
            fore = key[1] == "F"
            y, z, w = path((t - phase) % 1.0, gait["duty"], gait["step"], gait["lift_fore" if fore else "lift_hind"], gait.get("carry", 0.3))
            sx = self.stance_x[key[1]] * (1 if key[0] == "L" else -1) * gait.get("narrow", 1.0)
            off = gait.get("fore_y" if fore else "hind_y", 0.0)
            joint = Vector((sx, self.stand_y[key] + off + y, self.PAW[key]["height"] + z))
            if shift:
                joint += shift.get(key, Vector())
            pitch = 0.0 if w < 0 else (gait["fold_fore"] if fore else gait["fold_hind"]) * math.sin(math.pi * min(1.0, w * 1.25))
            p.leg(key, joint, pitch)

    def body(self, p, dz=0.0, dx=0.0, dy=0.0, pitch=0.0, roll=0.0, yaw=0.0, arch=0.0, chest=(0, 0, 0), neck=(0, 0, 0),
             head=(0, 0, 0), tail=None):
        """The trunk. pitch: nose down. arch: the back rounds. chest, neck, head: (nod down, turn to
        the animal's left, tilt) in degrees. tail: per bone (lift, swing)."""
        br = self.basis_rot
        p.loc["Hips"] = self.REST["Hips"].to_3x3().inverted() @ Vector((dx, dy, dz))
        p.rot["Hips"] = _compose(br("Hips", X, pitch - 0.45 * arch), br("Hips", Yax, roll), br("Hips", Z, yaw))
        p.rot["Spine1"] = _compose(br("Spine1", X, arch + chest[0]), br("Spine1", Z, chest[1]), br("Spine1", Yax, chest[2]))
        p.rot["Neck"] = _compose(br("Neck", X, neck[0]), br("Neck", Z, neck[1]), br("Neck", Yax, neck[2]))
        p.rot["Head"] = _compose(br("Head", X, head[0]), br("Head", Z, head[1]), br("Head", Yax, head[2]))
        for i, (lift, swing) in enumerate((tail or [])[:self.tails]):
            n = "Tail%d" % (i + 1)
            p.rot[n] = _compose(br(n, X, lift), br(n, Z, swing))

    # --- keying ------------------------------------------------------------------------------------
    def make_action(self, name, seconds, pose_at, gait=None):
        """Keys the loop. With a gait, finds the body height first: it starts high and comes down a
        little at a time until no leg is stretched past the gait's cap, so the animal stands as tall
        as its legs allow."""
        S = self.S
        frames = max(2, int(round(seconds * self.fps)))
        cap = gait.get("cap", MAX_EXTENSION) if gait else MAX_EXTENSION
        if gait is not None:
            gait["crouch"] = -0.08 * S
        while True:
            poses = [pose_at(f / frames) for f in range(frames + 1)]
            ext = max(s[0] for p in poses for s in p.stats.values())
            if ext <= cap or gait is None or gait["crouch"] > 0.3 * S:
                break
            gait["crouch"] += 0.002 * S
        slip = max(s[1] for p in poses for s in p.stats.values())
        worst = max(((k, f, s) for f, p in enumerate(poses) for k, s in p.stats.items()), key=lambda x: x[2][1])
        longest = max(((k, f, s[0]) for f, p in enumerate(poses) for k, s in p.stats.items()), key=lambda x: x[2])
        assert ext <= MAX_EXTENSION + 1e-3, "%s: a leg reaches %.0f%% of its length (%s at frame %d; crouch %.3f m)" % (
            name, ext * 100, longest[0], longest[1], gait["crouch"] if gait else 0.0)
        assert slip < 0.001, "%s: a paw misses its spot by %.4f m (%s at frame %d, reach %.0f%%; crouch %.3f m)" % (
            name, slip, worst[0], worst[1], worst[2][0] * 100, gait["crouch"] if gait else 0.0)
        rig = self.rig
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = act
        pb = rig.pose.bones
        for f, p in enumerate(poses):
            for b in pb:
                p.matrix(b.name)
                b.rotation_quaternion = p.rot.get(b.name, Quaternion())
                b.location = p.loc.get(b.name, Vector())
                b.keyframe_insert("rotation_quaternion", frame=f + 1)
                if b.name == "Hips":
                    b.keyframe_insert("location", frame=f + 1)
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, act)
        rig.animation_data.action = None
        for b in pb:
            b.rotation_quaternion = Quaternion()
            b.location = Vector()
        line = "LOOP %s: %d frames, %.2f s, legs at most %.0f%% straight, paws within %.2f mm" % (name, frames, seconds, ext * 100, slip * 1000)
        if gait and gait["step"] > 0:
            speed = gait["step"] / (gait["duty"] * seconds)
            line += "; crouch %.3f m; STRIDE %.3f m/s" % (gait["crouch"], speed)
            self.strides[name] = round(speed, 3)
        print(line)
        return act


def _compose(*qs):
    out = Quaternion()
    for q in qs:
        out = out @ q
    return out


class _Pose:
    """One frame: body bones set by rotation, legs solved to their paws."""

    def __init__(self, g):
        self.g = g
        self.rot, self.loc, self.mat, self.stats = {}, {}, {}, {}

    def zero(self, name):
        g = self.g
        par = g.PARENT[name]
        if par is None:
            return g.REST[name].copy()
        return self.matrix(par) @ g.REST[par].inverted() @ g.REST[name]

    def matrix(self, name):
        if name not in self.mat:
            basis = Matrix.Translation(self.loc.get(name, Vector())) @ self.rot.get(name, Quaternion()).to_matrix().to_4x4()
            self.mat[name] = self.zero(name) @ basis
        return self.mat[name]

    def aim(self, name, direction=None, world_rot=None):
        m0 = self.zero(name)
        if world_rot is None:
            y0 = (m0.to_3x3() @ Yax).normalized()
            world_rot = y0.rotation_difference(direction.normalized()).to_matrix() @ m0.to_3x3()
        m = Matrix.Translation(m0.translation) @ world_rot.to_4x4()
        self.rot[name] = (m0.inverted() @ m).to_quaternion()
        self.mat[name] = m

    def leg(self, key, joint, pitch=0.0):
        """Solves a leg so its wrist or hock is at `joint`; the paw level, tipped by `pitch` degrees."""
        g = self.g
        up, lo, paw, s = LEGS[key]
        l1, l2 = g.LEN[key]
        h = self.zero(up).translation
        to = joint - h
        reach = to.length
        d = min(reach, (l1 + l2) * 0.999)
        u = to.normalized()
        pole = Yax * s
        w = (pole - u * pole.dot(u)).normalized()
        a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
        k = h + u * a + w * math.sqrt(max(0.0, l1 * l1 - a * a))
        self.aim(up, k - h)
        self.aim(lo, (h + u * d) - k)
        self.aim(paw, world_rot=rot_x(g.PAW[key]["level"] + pitch) @ g.REST[paw].to_3x3())
        self.stats[key] = (reach / (l1 + l2), (self.matrix(paw).translation - joint).length)
