"""Her hands: shape keys that close a character's fingers round what she holds, and the knitting
pose that goes with them. The rig has no finger bones, so the game turns the keys on and off.

- 'grip_R': the right hand's fist round a tool handle that runs front to back across the palm, the
  thumb lying on the handle. The game turns it on while she holds a tool.
- 'knit_R' and 'knit_L': each hand round a knitting needle: three fingers curled round it, the index
  finger left almost straight (on the right hand it carries the yarn, on the left it steadies the
  tip), the thumb on top. The game turns them on while she knits (scripts/body.gd).
- The knitting loop (SitKnit) turned palms down, the upper arms out a little, so the index side of
  each fist faces the middle, and the needles (the KnitProps mesh) laid through the fists with the
  tips crossing, the work hanging from the left needle.

Run it on the eyes model's blend (after tools/add_eyes.py, which starts that blend afresh), then
import. It saves the blend and exports assets/<id>_eyes.glb with add_eyes.py's export settings.

    Blender -b tools/character_build/<id>_eyes/<id>_eyes.blend -P tools/add_grip.py -- "$PWD" <id> [--review]

The hand's measurements (rest pose, Blender metres) are per character: GRIPS below, given for the
right hand; the left hand uses them mirrored. The game's FIST_C in scripts/main.gd must match the
grip_R handle's centre and axis here.
"""
import math
import os
import struct
import json
import sys
import tempfile

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, CID = argv[0], argv[1]
REVIEW = "--review" in argv

# Nora's right hand hangs at her side, palm in (+x), fingers down, knuckles at z 0.725; the
# fingers fan front (index, y -0.105) to back (little finger, y -0.02). Each grip's handle is a
# cylinder along y through (hx, hz), radius r, against the palm just below the finger roots.
# theta: how far each finger curls at most, little, ring, middle, index (radians). thumb: the box
# that is the thumb (x above, y below, z between zmin and z), its root, how far it swings onto the
# handle and how far from the handle's middle it stays.
_THUMB = dict(x=-0.212, y=-0.088, z=0.80, zmin=0.0, root=(-0.196, 0.80))
GRIPS = {
    "nora_tripo": {
        "grip_R": dict(side="Right", zk=0.725, hx=-0.194, hz=0.716, r=0.021, theta=(3.25,) * 4,
                       bands=(-0.034, -0.061, -0.09), thumb=dict(_THUMB, turn=24.0, clear=0.011)),
        # a needle is thin: the fingers close round it nearer the palm, and not all the way
        "knit_R": dict(side="Right", zk=0.725, hx=-0.209, hz=0.716, r=0.0045, theta=(2.75, 2.7, 2.5, 0.55),
                       bands=(-0.034, -0.061, -0.09), thumb=dict(_THUMB, turn=14.0, clear=0.011)),
        "knit_L": dict(side="Left", zk=0.725, hx=-0.206, hz=0.716, r=0.0045, theta=(2.75, 2.7, 2.5, 0.4),
                       bands=(-0.034, -0.061, -0.09), thumb=dict(_THUMB, zmin=0.705, turn=14.0, clear=0.011)),
    },
}
# The knitting loop: extra twist (radians) about each bone's own length, right side; the left is
# mirrored. The upper arm turns out (spreads the hands), the forearm and wrist turn palm down.
KNIT_TWIST = {"nora_tripo": dict(UpperArm=0.3, LowerArm=-0.5, Hand=-0.5)}
# How much of the loop's stroke to keep: the forearms rock in turn, one up while the other comes
# down, and at full swing the needle tips part by several centimetres. Each arm key is scaled
# about its mean, so the tips stay together and the hands still work.
KNIT_SWING = {"nora_tripo": 0.2}
# How far (degrees) the upper arms swing out from the shoulder, so her elbows clear her sides and
# sit out over the chair's arms; each forearm then turns back in so the hand (and its needle) stays
# where it was.
KNIT_SPREAD = {"nora_tripo": 20.0}
# The working yarn: its radius and colour (the swatch's sage green, linear), and the ball it
# comes from, on her right thigh at (x, y) in the SitKnit pose.
YARN = dict(r=0.0018, color=(0.48, 0.58, 0.40, 1.0), ball_r=0.032, ball_at=(-0.1, -0.34))
# The needles: length past the index side and past the little-finger side, radius.
NEEDLE = dict(tip=0.15, butt=0.075, r=0.0042)


def body_mesh():
    return max([o for o in bpy.data.objects if o.type == "MESH" and o.name != "KnitProps"], key=lambda o: len(o.data.vertices))


def rig_obj():
    return next(o for o in bpy.data.objects if o.type == "ARMATURE")


def smooth01(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def add_key(body, name, G):
    """One hand closed round a handle along y through (hx, hz). Worked in right-hand terms: the left
    hand's points are mirrored in x on the way in and out."""
    me = body.data
    sx = 1.0 if G["side"] == "Right" else -1.0
    gi = body.vertex_groups[G["side"] + "Hand"].index
    mw = body.matrix_world
    inv = mw.inverted()
    if not me.shape_keys:
        body.shape_key_add(name="Basis", from_mix=False)
    if name in me.shape_keys.key_blocks:
        body.shape_key_remove(me.shape_keys.key_blocks[name])
    key = body.shape_key_add(name=name, from_mix=False)

    def w_hand(v):
        return sum(g.weight for g in v.groups if g.group == gi)

    def mirror(p):
        return Vector((sx * p.x, p.y, p.z))

    P = {v.index: mirror(mw @ v.co) for v in me.vertices if w_hand(v) > 0.3}
    hx, hz, R, zk = G["hx"], G["hz"], G["r"], G["zk"]
    th = G["thumb"]

    def band(p):
        return sum(1 for b in G["bands"] if p.y < b)

    def is_thumb(p):
        return p.x > th["x"] and p.y < th["y"] and th["zmin"] < p.z < th["z"]

    fingers = {i: p for i, p in P.items() if p.z < zk and not is_thumb(p) and w_hand(me.vertices[i]) > 0.5}
    # each finger's palm side at its root: the innermost of its vertices just below the knuckle
    xs = {}
    for i, p in fingers.items():
        if p.z > zk - 0.03:
            b = band(p)
            xs[b] = max(xs.get(b, -9.0), p.x)
    print("[grip] %s: fingers %d, palm side per finger %s" % (name, len(fingers), {b: round(x, 4) for b, x in sorted(xs.items())}))
    moved = {}
    for i, p in fingers.items():
        b = band(p)
        x0 = xs.get(b, hx - R)
        rf = max(R, hx - x0)              # this finger wraps the handle at its own distance from it
        n = x0 - p.x                       # depth from the finger's palm side toward its back
        s = zk - p.z                       # how far down the finger
        # bend about the finger's middle, so its back stretches a little and its pad tucks in
        tmax = G["theta"][b]
        theta = s / (rf + 0.009)
        theta = tmax * math.tanh(theta / tmax)
        rad = rf + n
        # the bend only starts at the knuckle: a vertex level with it stays where it is
        c = Vector((hx, p.y, zk))
        moved[i] = c + Vector((-rad * math.cos(theta), 0.0, -rad * math.sin(theta)))
    # the thumb comes down the other side of the handle, as in a real fist: it swings out from its
    # root over the handle's inner side and lies on it. Its turn grows over its first 2.5 cm, so it
    # stays joined to the palm.
    rx, rz = th["root"]
    turn = math.radians(th["turn"])
    for i, p in P.items():
        if not is_thumb(p) or i in moved:
            continue
        a = turn * smooth01((rz - p.z) / 0.025)
        dx, dz = p.x - rx, p.z - rz
        q = Vector((rx + dx * math.cos(a) - dz * math.sin(a), p.y, rz + dx * math.sin(a) + dz * math.cos(a)))
        d = Vector((q.x - hx, 0.0, q.z - hz))
        if d.length < R + th["clear"]:
            q = Vector((hx, q.y, hz)) + d.normalized() * (R + th["clear"])
        moved[i] = q
    # nothing passes through the handle: the palm and any finger pushed out to its skin
    clear = R + 0.003
    for i, p in P.items():
        q = moved.get(i, p.copy())
        d = Vector((q.x - hx, 0.0, q.z - hz))
        if d.length < clear:
            if d.length < 1e-6:
                d = Vector((1, 0, 0))
            q = Vector((hx, q.y, hz)) + d.normalized() * clear
        moved[i] = q
    for i, q in moved.items():
        key.data[i].co = inv @ mirror(q)
    key.value = 0.0
    print("[grip] %s: moved %d vertices; handle at x %.3f z %.3f r %.3f" % (name, len(moved), sx * hx, hz, R))


def action_fcurves(act):
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out += list(cb.fcurves)
    return out


def twist_knit_loop(rig):
    """Turns SitKnit's arms by KNIT_TWIST, about each bone's own length, on every key. It records
    what it applied on the action, so a second run only adds the difference."""
    act = bpy.data.actions["SitKnit"]
    want = KNIT_TWIST[CID]
    done = dict(act.get("knit_twist", {}))
    fcs = action_fcurves(act)
    for side, sx in (("Right", 1.0), ("Left", -1.0)):
        for bone, ang in want.items():
            delta = sx * (ang - float(done.get(bone, 0.0)))
            if abs(delta) < 1e-9:
                continue
            path = 'pose.bones["%s%s"].rotation_euler' % (side, bone)
            comp = {f.array_index: f for f in fcs if f.data_path == path}
            assert len(comp) == 3, "SitKnit has no full rotation keys on " + side + bone
            for k in range(len(comp[0].keyframe_points)):
                pts = [comp[j].keyframe_points[k] for j in range(3)]
                e = rig.pose.bones[side + bone].rotation_euler.copy()
                for j in range(3):
                    e[j] = pts[j].co[1]
                ne = (e.to_quaternion() @ Quaternion((0, 1, 0), delta)).to_euler(e.order, e)
                for j in range(3):
                    pts[j].co[1] = ne[j]
                    pts[j].handle_left_type = pts[j].handle_right_type = "AUTO_CLAMPED"
            for f in comp.values():
                f.update()
    act["knit_twist"] = dict(want)
    # the stroke: every arm curve scaled about its mean (by the ratio to what a past run left)
    swing = KNIT_SWING[CID]
    k = swing / float(act.get("knit_swing", 1.0))
    if abs(k - 1.0) > 1e-9:
        for f in fcs:
            if any(('"%s%s"' % (side, b)) in f.data_path for side in ("Left", "Right") for b in ("UpperArm", "LowerArm", "Hand")):
                vals = [p.co[1] for p in f.keyframe_points]
                mean = sum(vals) / len(vals)
                for p, v in zip(f.keyframe_points, vals):
                    p.co[1] = mean + (v - mean) * k
                    p.handle_left_type = p.handle_right_type = "AUTO_CLAMPED"
                f.update()
    act["knit_swing"] = swing
    print("[grip] SitKnit arms turned", want, "stroke kept", swing)


def spread_knit_arms(rig):
    """Swings SitKnit's upper arms out by KNIT_SPREAD about the shoulder (a turn about the body's
    front axis), then turns each forearm so the wrist goes back where it was, the hand keeping its
    own orientation. Done key by key in armature space; records the spread on the action, so a
    second run only adds the difference."""
    act = bpy.data.actions["SitKnit"]
    want = KNIT_SPREAD[CID]
    delta = math.radians(want - float(act.get("knit_spread", 0.0)))
    if abs(delta) < 1e-9:
        return
    ad = rig.animation_data
    keep = [t.mute for t in ad.nla_tracks]
    for t in ad.nla_tracks:
        t.mute = True
    ad.action = act
    if act.slots:
        ad.action_slot = act.slots[0]
    fcs = action_fcurves(act)
    names = [s + b for s in ("Right", "Left") for b in ("UpperArm", "LowerArm", "Hand")]
    curves = {n: {f.array_index: f for f in fcs if f.data_path == 'pose.bones["%s"].rotation_euler' % n} for n in names}
    frames = [int(round(k.co[0])) for k in curves["RightUpperArm"][0].keyframe_points]
    new = {n: [] for n in names}
    sc = bpy.context.scene
    for fr in frames:
        sc.frame_set(fr)
        bpy.context.view_layer.update()
        for side, sx in (("Right", 1.0), ("Left", -1.0)):
            U, L, H = (rig.pose.bones[side + b] for b in ("UpperArm", "LowerArm", "Hand"))
            Um, Lm, Hm = U.matrix.copy(), L.matrix.copy(), H.matrix.copy()
            wrist = Hm.translation.copy()
            # the swing: about the body's front-back axis through the shoulder
            R = Matrix.Translation(Um.translation) @ Matrix.Rotation(sx * delta, 4, "Y") @ Matrix.Translation(-Um.translation)
            U2 = R @ Um
            elbow = U2 @ Vector((0, U.bone.length, 0))
            L1 = R @ Lm
            L1.translation = elbow
            q = (L1.to_3x3() @ Vector((0, 1, 0))).rotation_difference(wrist - elbow)
            L2 = (q.to_matrix().to_4x4() @ L1.to_3x3().to_4x4())
            L2.translation = elbow
            H2 = Hm.copy()
            H2.translation = L2 @ Vector((0, L.bone.length, 0))
            for pb, m in ((U, U2), (L, L2), (H, H2)):
                pb.matrix = m
                bpy.context.view_layer.update()
            for pb in (U, L, H):
                e = pb.rotation_euler.copy()
                if new[pb.name]:
                    e.make_compatible(new[pb.name][-1])
                new[pb.name].append(e)
    for n in names:
        for i in range(3):
            f = curves[n][i]
            for k, e in zip(f.keyframe_points, new[n]):
                k.co[1] = e[i]
                k.handle_left_type = k.handle_right_type = "AUTO_CLAMPED"
            f.update()
    for t, m in zip(ad.nla_tracks, keep):
        t.mute = m
    act["knit_spread"] = want
    print("[grip] SitKnit elbows out by %.0f degrees" % want)


def hand_deform(rig, side):
    """Rest -> SitKnit pose (frame 0), world space, for points riding on that hand alone."""
    return bone_deform(rig, side + "Hand")


def at_knit_frame(rig, fn):
    """Calls fn() with the rig in SitKnit's first frame, then puts the rig back as it was."""
    ad = rig.animation_data
    keep = (ad.action, [t.mute for t in ad.nla_tracks])
    for t in ad.nla_tracks:
        t.mute = True
    act = bpy.data.actions["SitKnit"]
    ad.action = act
    if act.slots:
        ad.action_slot = act.slots[0]
    bpy.context.scene.frame_set(1)
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    out = fn()
    ad.action = keep[0]
    for t, m in zip(ad.nla_tracks, keep[1]):
        t.mute = m
    return out


def bone_deform(rig, bone):
    """Rest -> SitKnit pose (frame 0), world space, for points riding on that bone alone."""
    def get():
        pb = rig.pose.bones[bone]
        return rig.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted() @ rig.matrix_world.inverted()
    return at_knit_frame(rig, get)


def swatch_image():
    """The Fair Isle swatch's texture: the procedural Nora (assets/nora.glb) still carries it; the
    sculpted model's blend lost the file. Packed into the blend so the export keeps it."""
    img = bpy.data.images.get("swatch")
    if img is not None and img.has_data and img.size[0] > 0:
        if img.packed_file is None:
            img.pack()
        return img
    path = os.path.join(PROJECT, "assets", "nora.glb")
    if not os.path.exists(path):
        return None
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    binoff = 20 + n + 8
    for im in j.get("images", []):
        if im.get("name") == "swatch":
            bv = j["bufferViews"][im["bufferView"]]
            data = b[binoff + bv.get("byteOffset", 0): binoff + bv.get("byteOffset", 0) + bv["byteLength"]]
            tmp = os.path.join(tempfile.mkdtemp(), "swatch.png")
            open(tmp, "wb").write(data)
            if img is not None:
                bpy.data.images.remove(img)
            img = bpy.data.images.load(tmp)
            img.name = "swatch"
            img.pack()
            return img
    return None


def lathe(bm, a, b, r, segs=10):
    """A needle from butt a to tip b: a round stick tapering to a point, a bead cap on the butt."""
    axis = (b - a).normalized()
    q = Vector((0, 0, 1)).rotation_difference(axis)
    L = (b - a).length
    prof = [(-0.009, 0.0), (-0.0085, 0.0045), (-0.006, 0.0078), (-0.002, 0.0085), (0.0, r), (L - 0.035, r), (L - 0.012, r * 0.55), (L, 0.0)]
    rings = []
    for z, rr in prof:
        if rr == 0.0:
            rings.append([bm.verts.new(a + q @ Vector((0, 0, z)))])
            continue
        rings.append([bm.verts.new(a + q @ Vector((rr * math.cos(2 * math.pi * k / segs), rr * math.sin(2 * math.pi * k / segs), z))) for k in range(segs)])
    faces = []
    for i in range(len(rings) - 1):
        A, B = rings[i], rings[i + 1]
        cap = i < 4  # the bead
        for k in range(segs):
            if len(A) == 1:
                f = bm.faces.new((A[0], B[(k + 1) % segs], B[k]))
            elif len(B) == 1:
                f = bm.faces.new((A[k], A[(k + 1) % segs], B[0]))
            else:
                f = bm.faces.new((A[k], A[(k + 1) % segs], B[(k + 1) % segs], B[k]))
            f.material_index = 1 if cap else 0
            f.smooth = True
            faces.append(f)
    return faces


def yarn_material():
    """The working yarn and its ball: the swatch's sage green, soft and matte."""
    m = bpy.data.materials.get("Yarn") or bpy.data.materials.new("Yarn")
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = YARN["color"]
    bsdf.inputs["Roughness"].default_value = 0.95
    return m


def index_top(rig):
    """The top of her right index finger in the knitting fist (the knit_R key), SitKnit pose:
    where the working yarn runs over it."""
    body = body_mesh()
    G = GRIPS[CID]["knit_R"]
    th = G["thumb"]
    gi = body.vertex_groups["RightHand"].index
    key = body.data.shape_keys.key_blocks["knit_R"]
    mw = body.matrix_world
    D = hand_deform(rig, "Right")
    best = None
    for v in body.data.vertices:
        if sum(g.weight for g in v.groups if g.group == gi) < 0.5:
            continue
        p = mw @ v.co
        thumb = p.x > th["x"] and p.y < th["y"] and th["zmin"] < p.z < th["z"]
        if p.y < G["bands"][2] and not thumb and G["zk"] - 0.045 < p.z < G["zk"] - 0.02:
            q = D @ (mw @ key.data[v.index].co)
            if best is None or q.z > best.z:
                best = q
    return best


def lap_top(rig, x, y):
    """The top of her right thigh near (x, y) in the SitKnit pose."""
    body = body_mesh()
    gi = body.vertex_groups["RightUpperLeg"].index
    def get():
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        m = ev.to_mesh()
        zs = [(body.matrix_world @ mv.co).z for v, mv in zip(body.data.vertices, m.vertices)
              if sum(g.weight for g in v.groups if g.group == gi) > 0.6
              and abs((body.matrix_world @ mv.co).x - x) < 0.025 and abs((body.matrix_world @ mv.co).y - y) < 0.025]
        ev.to_mesh_clear()
        return max(zs)
    return at_knit_frame(rig, get)


def add_yarn(rig, bm, groups, stitch):
    """The working yarn: from the last stitch on the left needle, over her right index finger, down
    to a ball of the same yarn in her lap. Laid out in the SitKnit pose; each point rides on the
    bones it lies between (left hand to right hand, right hand to thigh), so the strand follows her
    hands as they work, and the ball sits on her right thigh."""
    bones = ("LeftHand", "RightHand", "RightUpperLeg")
    D = {b: bone_deform(rig, b) for b in bones}
    a = stitch + Vector((0, 0, -0.004))
    b = index_top(rig) + Vector((0, 0, YARN["r"] + 0.001))
    lx, ly = YARN["ball_at"]
    ball = Vector((lx, ly, lap_top(rig, lx, ly) + YARN["ball_r"] * 0.85))
    e = ball + Vector((0, 0, YARN["ball_r"] * 0.9))

    def bez(p0, p1, p2, t):
        return p0 * (1 - t) ** 2 + p1 * 2 * t * (1 - t) + p2 * t * t

    # a little slack between the needle and the finger; from the finger it falls to the ball
    pts, wts = [], []
    m1 = (a + b) / 2 + Vector((0, -0.004, -0.012))
    for i in range(14):
        t = i / 13
        pts.append(bez(a, m1, b, t))
        u = smooth01(t)
        wts.append({"LeftHand": 1 - u, "RightHand": u})
    m2 = Vector((b.x - 0.02, b.y - 0.01, b.z + 0.01))
    for i in range(1, 19):
        t = i / 18
        pts.append(bez(b, m2 + (e - b) * 0.15, e, t))
        u = smooth01(t)
        wts.append({"RightHand": 1 - u, "RightUpperLeg": u})

    def to_rest(p, w):
        M = Matrix(((0, 0, 0, 0),) * 4)
        for name, x in w.items():
            M += D[name] * x
        return M.inverted() @ p

    segs, r = 6, YARN["r"]
    prev_n = None
    rings = []
    for i, p in enumerate(pts):
        tang = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = prev_n if prev_n is not None else tang.orthogonal().normalized()
        n = (n - tang * n.dot(tang)).normalized()  # carried along the strand, so it doesn't twist
        prev_n = n
        bnorm = tang.cross(n)
        ring = []
        for k in range(segs):
            ang = 2 * math.pi * k / segs
            q = p + (n * math.cos(ang) + bnorm * math.sin(ang)) * r
            v = bm.verts.new(to_rest(q, wts[i]))
            groups[v] = wts[i]
            ring.append(v)
        rings.append(ring)
    for A, B in zip(rings, rings[1:]):
        for k in range(segs):
            f = bm.faces.new((A[k], A[(k + 1) % segs], B[(k + 1) % segs], B[k]))
            f.material_index = 3
            f.smooth = True
    # the ball: a sphere wound with a few raised strands round it
    R = YARN["ball_r"]
    nu, nv = 24, 14
    verts = []
    for j in range(nv + 1):
        th_ = math.pi * j / nv
        row = []
        for i in range(nu):
            ph = 2 * math.pi * i / nu
            d = Vector((math.sin(th_) * math.cos(ph), math.sin(th_) * math.sin(ph), math.cos(th_)))
            wound = 1.0 + 0.04 * math.sin(5 * th_ + 3 * ph) + 0.03 * math.sin(7 * ph - 2 * th_)
            p = ball + d * R * wound
            v = bm.verts.new(D["RightUpperLeg"].inverted() @ p)
            groups[v] = {"RightUpperLeg": 1.0}
            row.append(v)
        verts.append(row)
    for j in range(nv):
        for i in range(nu):
            q = [verts[j][i], verts[j][(i + 1) % nu], verts[j + 1][(i + 1) % nu], verts[j + 1][i]]
            if j == 0 or j == nv - 1:
                q = list(dict.fromkeys(q)) if len(set(q)) < 4 else q
            try:
                f = bm.faces.new(q)
            except ValueError:
                continue
            f.material_index = 3
            f.smooth = True
    print("[grip] yarn from the work over her index finger to a ball in her lap at (%.2f, %.2f, %.2f)" % tuple(ball))


def build_needles(rig):
    """Replaces the KnitProps mesh: a needle through each knitting fist (along the grip's handle,
    rest pose, bound to that hand), the tips toward the middle, and the work hanging from the left
    needle, laid out in the SitKnit pose and moved back to rest on the left hand."""
    old = bpy.data.objects["KnitProps"]
    mats = {m.name: m for m in old.data.materials}
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    groups = {}
    posed = {}
    for side, sx in (("Right", 1.0), ("Left", -1.0)):
        G = GRIPS[CID]["knit_" + side[0]]
        c = Vector((sx * G["hx"], 0.0, G["hz"]))
        butt = Vector((c.x, 0.02 + NEEDLE["butt"], c.z))   # past the little finger
        tip = Vector((c.x, -0.105 - NEEDLE["tip"], c.z))    # past the index finger
        # the two tips pass a finger's width apart: the right needle a little in front
        D = hand_deform(rig, side)
        Dinv = D.inverted()
        off = D.to_3x3().inverted() @ Vector((0, -0.006 * sx, 0))
        tip += off
        fs = lathe(bm, butt, tip, NEEDLE["r"])
        for f in fs:
            for v in f.verts:
                groups[v] = {side + "Hand": 1.0}
        posed[side] = (D, D @ butt, D @ tip)
    # the work: a small knitted piece hanging off the left needle's front half, toward her lap
    D, pb, pt = posed["Left"]
    Dinv = D.inverted()
    across = pt - pb
    top_a, top_b = pb + across * 0.42, pb + across * 0.86
    down = Vector((0, 0, -1))
    toward = Vector((0, 1, 0))
    nu, nv, depth = 8, 6, 0.085
    grid = []
    for j in range(nv + 1):
        v = j / nv
        row = []
        for i in range(nu + 1):
            u = i / nu
            p = top_a + (top_b - top_a) * u + down * depth * v + toward * (0.02 * math.sin(math.pi * v) + 0.025 * v)
            p += toward * 0.006 * math.sin(math.pi * u) + down * 0.004 * math.sin(math.pi * u) * v
            vert = bm.verts.new(Dinv @ p)
            groups[vert] = {"LeftHand": 1.0}
            row.append(vert)
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            for flip in (False, True):  # both faces, a little apart: a knitted piece has two sides
                vs = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
                if flip:
                    vs = tuple(reversed(vs))
                try:
                    f = bm.faces.new(vs)
                except ValueError:
                    continue
                f.material_index = 2
                f.smooth = True
                uvs = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                if flip:
                    uvs = list(reversed(uvs))
                for loop, (uu, vv) in zip(f.loops, uvs):
                    loop[uv].uv = (uu / nu, 1.0 - vv / nv)
    add_yarn(rig, bm, groups, top_b)
    me = bpy.data.meshes.new("KnitProps")
    bm.verts.index_update()
    order = list(bm.verts)
    bm.to_mesh(me)
    bm.free()
    for name in ("Needle", "NeedleCap", "Swatch"):
        me.materials.append(mats.get(name))
    me.materials.append(yarn_material())
    img = swatch_image()
    sw = mats.get("Swatch")
    if img is not None and sw is not None:
        for n in sw.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                n.image = img
    old_me = old.data
    old.data = me
    bpy.data.meshes.remove(old_me)
    for vg in list(old.vertex_groups):
        old.vertex_groups.remove(vg)
    for k, v in enumerate(order):
        for name, w in groups.get(v, {}).items():
            if w <= 1e-4:
                continue
            vg = old.vertex_groups.get(name) or old.vertex_groups.new(name=name)
            vg.add([k], w, "REPLACE")
    # the mesh is in rest-pose world space: undo the object's own transform
    me.transform(old.matrix_world.inverted())
    print("[grip] needles laid through the fists; swatch texture", img.name if img else None)


def main():
    body = body_mesh()
    for name, G in GRIPS[CID].items():
        add_key(body, name, G)
    rig = rig_obj()
    twist_knit_loop(rig)
    spread_knit_arms(rig)
    build_needles(rig)


main()
OUT = os.path.join(PROJECT, "tools", "character_build", CID + "_eyes")
if REVIEW:
    body_mesh().data.shape_keys.key_blocks["grip_R"].value = 1.0
else:
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, CID + "_eyes.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(PROJECT, "assets", CID + "_eyes.glb"), export_format="GLB", export_apply=False,
                              export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
                              export_morph=True, export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True)
    print("[grip] exported", os.path.join("assets", CID + "_eyes.glb"))
