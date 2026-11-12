"""Turn the Tripo golden retriever export into the rigged, animated dog the game plays with.

Run headless (Blender 5):
  Blender -b --factory-startup -P tools/rig_dog.py -- <project_dir> <tripo.glb>
          [--height 0.62] [--faces 60000] [--tex 2048] [--render DIR] [--cache DIR]

The export stands mid-stride with FIVE legs: two right forelegs, one planted under the chest and one
reaching forward beside the scarf's tails. Alex picked the reaching one to go (2026-11-12).

What it does:
  1. imports the export, welds it (it comes split along its UV seams), turns the head to -Y (+Z in
     Godot), decimates it to --faces and scales it to --height metres;
  2. cuts the fifth leg off: everything within CUT_AT metres of its paw, measured along the surface,
     so the cut runs round the leg where it meets the chest; the hole is closed, relaxed flat into
     the chest fur and given the colour of the fur round it (a spare corner of the texture);
  3. builds a quadruped skeleton with blender-kiln's bone names (Hips, Spine1, Neck, Head, Tail1-3,
     {Left,Right}{Arm,ForeArm,Hand} and {Left,Right}{UpLeg,Leg,Foot}) through the joints in JOINTS,
     which were measured on this model, and skins the mesh to it with Blender's bone-heat weights;
     everything from the jaw line up follows the Head bone alone, so the face never shears;
  4. keyframes four loops. Each paw is given a path over the ground and its leg is solved to reach
     it from wherever the body is that frame, so a paw on the ground stays exactly where it was put:
       Idle  standing square, breathing, shifting his weight, looking about, wagging;
       Walk  a four-beat walk (left hind, left fore, right hind, right fore);
       Trot  diagonal pairs with a moment off the ground between them: his everyday pace;
       Run   a rotary gallop: both hind paws, a stretched flight, both forepaws, a gathered flight,
             the back arching and stretching with it;
  5. checks every frame of every loop: no leg straighter than MAX_EXTENSION of its length, and no
     planted paw more than a millimetre from where it was put;
  6. shrinks the textures to --tex and exports assets/props/dog.glb (never Draco: Godot can't read it).

It prints each loop's ground speed (STRIDE); scripts/dog.gd plays the loops at those speeds so the
paws don't slide.
"""
import bpy, bmesh, heapq, json, math, os, sys
from mathutils import Vector, Matrix, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, SRC = os.path.abspath(argv[0]), os.path.abspath(argv[1])
ID = "dog"


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


HEIGHT = float(opt("--height", 0.62))
FACES = int(opt("--faces", 60000))
TEX = int(opt("--tex", 2048))
RENDER = opt("--render")
CACHE = opt("--cache")
FPS = 60
SRC_HEIGHT = 0.6035  # the export's height; JOINTS and the other measurements are in its units
S = HEIGHT / SRC_HEIGHT
Y0 = 0.035  # the point midway between shoulders and hips, which becomes the origin

# --- 1. import, weld, orient, decimate, size ----------------------------------------------------
cache_file = os.path.join(CACHE, "dog_%d.blend" % FACES) if CACHE else None
if cache_file and os.path.exists(cache_file):
    bpy.ops.wm.open_mainfile(filepath=cache_file)
    ob = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    before = ob.get("faces_before", 0)
else:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    ob.parent = None
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    ob.data.transform(Matrix.Rotation(math.radians(-90), 4, "Z"))  # the export's head is at +X
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(ob.data)
    bm.free()
    before = len(ob.data.polygons)
    mod = ob.modifiers.new("decimate", "DECIMATE")
    mod.ratio = FACES / before
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    ob["faces_before"] = before
    if cache_file:
        os.makedirs(CACHE, exist_ok=True)
        bpy.ops.file.pack_all()
        bpy.ops.wm.save_as_mainfile(filepath=cache_file)
bpy.context.view_layer.objects.active = ob
ob.data.transform(Matrix.Translation(Vector((0, -Y0, 0))))
ob.data.transform(Matrix.Scale(S, 4))
ob.data.update()
me = ob.data


def P(x, y, z):
    """A point measured on the export (head at -Y), in the model's final units."""
    return Vector((x, y - Y0, z)) * S


# --- 2. the fifth leg ---------------------------------------------------------------------------
EXTRA_PAW = P(-0.05, -0.41, 0.06)  # the raised right forepaw beside the scarf's tails
CUT_AT = 0.245 * S  # along the surface from that paw's lowest point: where the leg widens into the chest


def geodesic(seed, limit):
    """Distance along the mesh's edges from vertex `seed`, out to `limit`."""
    adj = {}
    for e in me.edges:
        a, b = e.vertices
        l = (me.vertices[a].co - me.vertices[b].co).length
        adj.setdefault(a, []).append((b, l))
        adj.setdefault(b, []).append((a, l))
    dist = {seed: 0.0}
    heap = [(0.0, seed)]
    while heap:
        d, i = heapq.heappop(heap)
        if d > dist.get(i, 1e9) or d > limit:
            continue
        for j, l in adj.get(i, ()):
            nd = d + l
            if nd < dist.get(j, 1e9):
                dist[j] = nd
                heapq.heappush(heap, (nd, j))
    return dist


def lowest_near(p, r):
    near = [v.index for v in me.vertices if (Vector((v.co.x, v.co.y)) - Vector((p.x, p.y))).length < r and v.co.z < p.z + 0.06 * S]
    return min(near, key=lambda i: me.vertices[i].co.z)


dist = geodesic(lowest_near(EXTRA_PAW, 0.05 * S), CUT_AT + 0.05)
doomed = {i for i, d in dist.items() if d < CUT_AT}
bm = bmesh.new()
bm.from_mesh(me)
tag = bm.verts.layers.int.new("patch")  # 1: the rim of the hole, 2: new vertices inside it (made first: a new layer drops old references)
bm.verts.ensure_lookup_table()
uv_layer = bm.loops.layers.uv.active
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in doomed], context="VERTS")
rim = [e for e in bm.edges if e.is_boundary]
rim_verts = list({v for e in rim for v in e.verts})
rim_uv = []
for v in rim_verts:
    for l in v.link_loops:
        rim_uv.append(l[uv_layer].uv.copy())
        break
for v in rim_verts:
    v[tag] = 1
filled = bmesh.ops.holes_fill(bm, edges=rim, sides=0)["faces"]
for v in bmesh.ops.poke(bm, faces=filled)["verts"]:
    v[tag] = 2
# the spokes are cut in three and the patch relaxed, so it settles into the fur rather than sitting as a flat lid
spokes = list({e for v in bm.verts if v[tag] == 2 for e in v.link_edges})
sub = bmesh.ops.subdivide_edges(bm, edges=spokes, cuts=3, use_grid_fill=False)
for g in sub["geom_inner"]:
    if isinstance(g, bmesh.types.BMVert) and g.is_valid and g[tag] == 0:
        g[tag] = 2


def patch_faces():
    return [f for f in bm.faces if all(v[tag] for v in f.verts) and any(v[tag] == 2 for v in f.verts)]


bmesh.ops.triangulate(bm, faces=patch_faces())
ring = {v for v in bm.verts if v[tag]}
for _ in range(3):  # relaxed together with three rings of the fur around it
    ring |= {e.other_vert(v) for v in list(ring) for e in v.link_edges}
for _ in range(40):
    bmesh.ops.smooth_vert(bm, verts=list(ring), factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.faces.index_update()
# The fur next to the hole was painted for the leg that grew there (the scarf's shadow, the leg's
# own shading), so the patch takes in two rings of it; its colour is sampled from the rings beyond.
near = {v for v in bm.verts if v[tag]}
for _ in range(2):
    near |= {e.other_vert(v) for v in list(near) for e in v.link_edges}
PATCH_FACES = [f.index for f in bm.faces if all(v in near for v in f.verts)]
outer = set(near)
for _ in range(4):
    outer |= {e.other_vert(v) for v in list(outer) for e in v.link_edges}
rim_uv = [l[uv_layer].uv.copy() for v in outer - near for l in v.link_loops]
OPEN_EDGES = sum(1 for e in bm.edges if e.is_boundary)
n_rim = len(rim)
bm.verts.layers.int.remove(tag)
bm.to_mesh(me)
bm.free()
me.update()
print("CUT fifth leg: %d vertices removed, hole of %d edges closed with %d faces, %d open edges left" % (len(doomed), n_rim, len(PATCH_FACES), OPEN_EDGES))


# the patch's colour: a spare block of the texture, filled with the fur round the hole
def tex_nodes():
    mat = me.materials[0]
    out = {}
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            links = [l for l in mat.node_tree.links if l.from_node == n]
            if any(l.to_socket.name == "Base Color" for l in links):
                out["color"] = n.image
            elif any(l.to_node.type == "NORMAL_MAP" for l in links):
                out["normal"] = n.image
            else:
                out["rm"] = n.image
    return out


IMAGES = tex_nodes()
uvs = me.uv_layers.active.data
GRID = 64
used = [[False] * GRID for _ in range(GRID)]
patch_set = set(PATCH_FACES)
for poly in me.polygons:
    if poly.index in patch_set:
        continue
    us = [uvs[li].uv for li in poly.loop_indices]
    x0, x1 = min(u.x for u in us), max(u.x for u in us)
    y0, y1 = min(u.y for u in us), max(u.y for u in us)
    for gx in range(max(0, int(x0 * GRID)), min(GRID - 1, int(x1 * GRID)) + 1):
        for gy in range(max(0, int(y0 * GRID)), min(GRID - 1, int(y1 * GRID)) + 1):
            used[gx][gy] = True
free = [(gx, gy) for gx in range(1, GRID - 1) for gy in range(1, GRID - 1)
        if not any(used[gx + dx][gy + dy] for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
if not free:
    free = [(gx, gy) for gx in range(GRID) for gy in range(GRID) if not used[gx][gy]]
assert free, "no spare block in the texture for the patch"
gx, gy = free[len(free) // 2]
spot = Vector(((gx + 0.5) / GRID, (gy + 0.5) / GRID))
for fi in PATCH_FACES:
    for li in me.polygons[fi].loop_indices:
        uvs[li].uv = spot
for kind, img in IMAGES.items():
    w, h = img.size
    px = list(img.pixels)
    if kind == "normal":
        fill = (0.5, 0.5, 1.0, 1.0)
    else:
        samples = []
        for uv in rim_uv:
            i = (min(h - 1, int(uv.y * h)) * w + min(w - 1, int(uv.x * w))) * 4
            c = px[i:i + 3]
            if kind != "color" or (c[0] > 0.3 and 0.4 < c[1] / c[0] < 0.95 and c[2] < c[1]):  # golden fur, not scarf
                samples.append(c)
        samples = samples or [px[0:3]]
        fill = tuple(sorted(c[k] for c in samples)[len(samples) // 2] for k in range(3)) + (1.0,)
        if kind == "color":
            print("PATCH colour from %d of %d samples: %s" % (len(samples), len(rim_uv), tuple(round(c, 2) for c in fill[:3])))
    cell = w // GRID
    for yy in range(gy * cell - cell, gy * cell + 2 * cell):
        for xx in range(gx * cell - cell, gx * cell + 2 * cell):
            i = (yy * w + xx) * 4
            px[i:i + 4] = fill
    img.pixels = px
    img.update()
print("PATCH texture block (%d,%d) of %d" % (gx, gy, GRID))

for p in me.polygons:
    p.use_smooth = True
V = [v.co.copy() for v in me.vertices]

# --- 3. skeleton --------------------------------------------------------------------------------
# Joints measured on the export (see the leg centre lines in art/world_assets/dog/dog_log.md).
# Left is +X. He stands mid-stride, so each leg has its own rest pose; the loops don't care.
JOINTS = {
    "Hips": (0.0, 0.27, 0.37), "Spine1": (0.0, 0.05, 0.38), "Chest": (0.0, -0.17, 0.38),
    "Neck": (0.0, -0.20, 0.40), "Head": (0.0, -0.29, 0.47), "HeadEnd": (0.0, -0.44, 0.50),
    "Tail1": (0.0, 0.345, 0.40), "Tail2": (0.0, 0.43, 0.40), "Tail3": (0.0, 0.465, 0.46), "TailEnd": (0.0, 0.42, 0.55),
    # forelegs: shoulder, elbow, wrist, toes
    "LeftArm": (0.095, -0.20, 0.32), "LeftForeArm": (0.115, -0.225, 0.175), "LeftHand": (0.128, -0.355, 0.095), "LeftHandEnd": (0.133, -0.385, 0.05),
    "RightArm": (-0.095, -0.20, 0.32), "RightForeArm": (-0.072, -0.105, 0.17), "RightHand": (-0.068, -0.135, 0.065), "RightHandEnd": (-0.066, -0.20, 0.02),
    # hind legs: hip, stifle (knee), hock, toes
    "LeftUpLeg": (0.075, 0.27, 0.35), "LeftLeg": (0.08, 0.125, 0.245), "LeftFoot": (0.07, 0.155, 0.09), "LeftFootEnd": (0.095, 0.06, 0.02),
    "RightUpLeg": (-0.075, 0.27, 0.35), "RightLeg": (-0.09, 0.20, 0.235), "RightFoot": (-0.11, 0.345, 0.085), "RightFootEnd": (-0.14, 0.29, 0.02),
}
J = {k: P(*v) for k, v in JOINTS.items()}
BONES = [  # name, head, tail, parent
    ("Hips", "Hips", "Spine1", None), ("Spine1", "Spine1", "Chest", "Hips"), ("Neck", "Neck", "Head", "Spine1"),
    ("Head", "Head", "HeadEnd", "Neck"),
    ("Tail1", "Tail1", "Tail2", "Hips"), ("Tail2", "Tail2", "Tail3", "Tail1"), ("Tail3", "Tail3", "TailEnd", "Tail2"),
]
for side in ("Left", "Right"):
    BONES += [
        (side + "Arm", side + "Arm", side + "ForeArm", "Spine1"), (side + "ForeArm", side + "ForeArm", side + "Hand", side + "Arm"),
        (side + "Hand", side + "Hand", side + "HandEnd", side + "ForeArm"),
        (side + "UpLeg", side + "UpLeg", side + "Leg", "Hips"), (side + "Leg", side + "Leg", side + "Foot", side + "UpLeg"),
        (side + "Foot", side + "Foot", side + "FootEnd", side + "Leg"),
    ]
arm_data = bpy.data.armatures.new("dog_rig")
rig = bpy.data.objects.new("rig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
for name, h, t, parent in BONES:
    b = eb.new(name)
    b.head, b.tail = J[h], J[t]
    b.align_roll(Vector((0, 0, 1)) if abs(b.vector.normalized().z) < 0.9 else Vector((0, -1, 0)))
    if parent:
        b.parent = eb[parent]
bpy.ops.object.mode_set(mode="OBJECT")

# --- 3b. skin: bone heat, then the head made rigid ----------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
groups = {g.name: g for g in ob.vertex_groups}
unweighted = sum(1 for v in me.vertices if not v.groups)
assert unweighted == 0, "bone heat left %d vertices without weights" % unweighted


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# The head: everything ahead of a plane through the top of the neck, tilted the way the neck runs,
# follows the Head bone alone; the weights fade to that over HEAD_FADE below the plane (the scarf).
HEAD_N = (J["Head"] - J["Neck"]).normalized()
HEAD_FADE = 0.05 * S
head_g = groups["Head"]
rigid = 0
for v in me.vertices:
    d = (v.co - J["Head"]).dot(HEAD_N)
    t = smooth(-HEAD_FADE, 0.0, d)
    if t <= 0.0:
        continue
    for g in v.groups:
        if g.group != head_g.index:
            g.weight *= (1.0 - t)
    cur = sum(g.weight for g in v.groups if g.group != head_g.index)
    head_g.add([v.index], max(0.0, 1.0 - cur) if t < 1.0 else 1.0, "REPLACE")
    rigid += t >= 1.0
# The scarf is knitted wool round his neck: bone heat lets the shoulders pull its wrap into a wedge,
# so the wrap follows the Neck bone alone and the tails hanging down his chest the Spine1 bone alone.
# Scarf vertices are found by their colour in the texture (red wool, not golden fur).
col = next(n.image for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image
           and any(l.to_socket.name == "Base Color" for l in me.materials[0].node_tree.links if l.from_node == n))
cw, ch = col.size
cpx = col.pixels[:]
vuv = {}
for poly in me.polygons:
    for vi, li in zip(poly.vertices, poly.loop_indices):
        vuv.setdefault(vi, me.uv_layers.active.data[li].uv.copy())
neck_z = J["Neck"].z - 0.03 * S
cand = set()
for v in me.vertices:
    uv = vuv.get(v.index)
    if uv is None or (v.co - J["Head"]).dot(HEAD_N) > -HEAD_FADE:
        continue
    if v.co.y > J["Neck"].y + 0.1 * S:  # nothing past the shoulders is scarf
        continue
    i = (min(ch - 1, int(uv.y * ch)) * cw + min(cw - 1, int(uv.x * cw))) * 4
    r, g, b = cpx[i], cpx[i + 1], cpx[i + 2]
    if r > 0.25 and g < 0.45 * r and b < 0.45 * r:  # red wool
        cand.add(v.index)
# The tails' snowflakes and stripes are cream, and their edges blend: close the red selection over
# the mesh (grow it four rings, then shrink it four), so every stitch inside the scarf comes along.
adj = {}
for e in me.edges:
    a0, b0 = e.vertices
    adj.setdefault(a0, []).append(b0)
    adj.setdefault(b0, []).append(a0)
allowed = {v.index for v in me.vertices if (v.co - J["Head"]).dot(HEAD_N) <= -HEAD_FADE and v.co.y <= J["Neck"].y + 0.1 * S}
grown = set(cand)
for _ in range(4):
    grown |= {n for i in grown for n in adj.get(i, ()) if n in allowed}
closed = set(grown)
for _ in range(4):
    closed = {i for i in closed if all(n in closed for n in adj.get(i, ()))}
sel = closed | cand
scarf = 0
for vi in sel:
    v = me.vertices[vi]
    bone_name = "Neck" if v.co.z > neck_z else "Spine1"
    for g2 in v.groups:
        g2.weight = 0.0
    groups[bone_name].add([vi], 1.0, "REPLACE")
    scarf += 1
print("SCARF %d vertices bound rigid (wrap to Neck, tails to Spine1)" % scarf)
for v in me.vertices:  # normalise, and drop what's too faint to matter
    tot = sum(g.weight for g in v.groups)
    for g in v.groups:
        g.weight /= tot
for v in me.vertices:  # the check: nothing ahead of the plane follows any other bone
    if (v.co - J["Head"]).dot(HEAD_N) > 0.0:
        other = sum(g.weight for g in v.groups if g.group != head_g.index)
        assert other < 1e-4, "vertex %d above the jaw line follows another bone (%.3f)" % (v.index, other)
print("SKIN %d vertices on %d bones (%.0f per bone), %d rigid on the head" % (
    len(me.vertices), len(arm_data.bones), len(me.vertices) / len(arm_data.bones), rigid))

# --- 4. the loops -------------------------------------------------------------------------------
REST = {b.name: b.matrix_local.copy() for b in arm_data.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in arm_data.bones}
ORDER = [b[0] for b in BONES]
X, Yax, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
TAU = math.tau
LEGS = {  # key: upper, lower, paw bones; which way the middle joint points; where the paw stands
    "LF": ("LeftArm", "LeftForeArm", "LeftHand", 1.0), "RF": ("RightArm", "RightForeArm", "RightHand", 1.0),
    "LH": ("LeftUpLeg", "LeftLeg", "LeftFoot", -1.0), "RH": ("RightUpLeg", "RightLeg", "RightFoot", -1.0),
}
STANCE_X = 0.10 * S  # how far out from the centre line each paw stands
# where the wrist or hock sits when he stands square: just behind the shoulder, a little behind the hip
STAND_Y = {"LF": J["LeftArm"].y + 0.035 * S, "RF": J["RightArm"].y + 0.035 * S,
           "LH": J["LeftUpLeg"].y + 0.075 * S, "RH": J["RightUpLeg"].y + 0.075 * S}
MAX_EXTENSION = 0.95


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


# Each paw's sole: turned level about the wrist or hock, and how high that joint then sits.
def paw_setup():
    out = {}
    normals = [v.normal.copy() for v in me.vertices]
    for key, (up, lo, paw, _s) in LEGS.items():
        gi = groups[paw].index
        mine = [v.index for v in me.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
        pivot = REST[paw].translation
        n = Vector()
        for i in mine:
            if normals[i].z < -0.6:
                n += normals[i]
        n.normalize()
        level = -math.degrees(math.atan2(n.y, -n.z))  # the turn about X that points the sole straight down
        r = rot_x(level)
        low = min((r @ (V[i] - pivot)).z for i in mine)
        out[key] = {"level": level, "height": -low, "verts": len(mine)}
        print("PAW %s: %d vertices, sole %.0f deg off level in the rest pose, joint %.3f m above the ground" % (key, len(mine), level, -low))
    return out


PAW = paw_setup()
LEN = {k: ((REST[lo].translation - REST[up].translation).length, (REST[paw].translation - REST[lo].translation).length)
       for k, (up, lo, paw, _s) in LEGS.items()}


def basis_rot(name, axis, deg):
    """A rotation about an axis of the model (not the bone), as the bone's own rotation."""
    r = Matrix.Rotation(math.radians(deg), 3, axis)
    return (REST[name].to_3x3().inverted() @ r @ REST[name].to_3x3()).to_quaternion()


def compose(*qs):
    out = Quaternion()
    for q in qs:
        out = out @ q
    return out


class Pose:
    """One frame: body bones set by rotation, legs solved to their paws."""

    def __init__(self):
        self.rot = {}
        self.loc = {}
        self.mat = {}
        self.stats = {}

    def zero(self, name):
        """Where the bone sits with no rotation of its own, given its parent's pose."""
        par = PARENT[name]
        if par is None:
            return REST[name].copy()
        return self.matrix(par) @ REST[par].inverted() @ REST[name]

    def matrix(self, name):
        if name not in self.mat:
            basis = Matrix.Translation(self.loc.get(name, Vector())) @ self.rot.get(name, Quaternion()).to_matrix().to_4x4()
            self.mat[name] = self.zero(name) @ basis
        return self.mat[name]

    def aim(self, name, direction=None, world_rot=None):
        """Points a bone along `direction` (least twist), or gives it an orientation outright."""
        m0 = self.zero(name)
        if world_rot is None:
            y0 = (m0.to_3x3() @ Yax).normalized()
            world_rot = y0.rotation_difference(direction.normalized()).to_matrix() @ m0.to_3x3()
        m = Matrix.Translation(m0.translation) @ world_rot.to_4x4()
        self.rot[name] = (m0.inverted() @ m).to_quaternion()
        self.mat[name] = m

    def leg(self, key, joint, pitch=0.0):
        """Solves a leg so its wrist or hock is at `joint`; the paw is level, tipped by `pitch` degrees
        (toes down)."""
        up, lo, paw, s = LEGS[key]
        l1, l2 = LEN[key]
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
        self.aim(paw, world_rot=rot_x(PAW[key]["level"] + pitch) @ REST[paw].to_3x3())
        self.stats[key] = (reach / (l1 + l2), (self.matrix(paw).translation - joint).length)


def path(u, duty, step, lift, carry=0.3):
    """Where a paw is at stride phase u, as (metres back of its standing spot, height, how far through
    the swing: -1 on the ground). On the ground it travels back at a steady pace. In the air it
    follows through, swings forward past its landing spot and is already moving back when it lands."""
    if u < duty:
        return step * (u / duty - 0.5), 0.0, -1.0
    w = (u - duty) / (1.0 - duty)
    m = carry * step * (1.0 - duty) / duty
    h00, h10, h01, h11 = 2 * w ** 3 - 3 * w ** 2 + 1, w ** 3 - 2 * w ** 2 + w, -2 * w ** 3 + 3 * w ** 2, w ** 3 - w ** 2
    y = h00 * step * 0.5 + h10 * m + h01 * -step * 0.5 + h11 * m
    z = lift * math.sin(math.pi * w) ** 1.2 * (1.0 - 0.3 * w)
    return y, z, w


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


def paws(p, gait, t, shift=None):
    """Sets every paw on its path for this moment of a gait."""
    for key, phase in gait["phase"].items():
        fore = key[1] == "F"
        y, z, w = path((t - phase) % 1.0, gait["duty"], gait["step"], gait["lift_fore" if fore else "lift_hind"], gait.get("carry", 0.3))
        sx = STANCE_X * (1 if key[0] == "L" else -1) * gait.get("narrow", 1.0)
        off = gait.get("fore_y" if fore else "hind_y", 0.0)
        joint = Vector((sx, STAND_Y[key] + off + y, PAW[key]["height"] + z))
        if shift:
            joint += shift.get(key, Vector())
        # in the air the paw folds back at the wrist (forepaws more than hind), then reaches for the ground
        pitch = 0.0 if w < 0 else (gait["fold_fore"] if fore else gait["fold_hind"]) * math.sin(math.pi * min(1.0, w * 1.25)) ** 1.0
        p.leg(key, joint, pitch)


def body(p, dz=0.0, dx=0.0, dy=0.0, pitch=0.0, roll=0.0, yaw=0.0, arch=0.0, chest=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0),
         tail=((0, 0), (0, 0), (0, 0))):
    """The trunk. pitch: nose down. arch: the back rounds (his hindquarters tuck under, his chest
    curls down). chest, neck, head: (nod down, turn to his left, tilt) in degrees. tail: per bone
    (lift, swing)."""
    p.loc["Hips"] = REST["Hips"].to_3x3().inverted() @ Vector((dx, dy, dz))
    p.rot["Hips"] = compose(basis_rot("Hips", X, pitch - 0.45 * arch), basis_rot("Hips", Yax, roll), basis_rot("Hips", Z, yaw))
    p.rot["Spine1"] = compose(basis_rot("Spine1", X, arch + chest[0]), basis_rot("Spine1", Z, chest[1]), basis_rot("Spine1", Yax, chest[2]))
    p.rot["Neck"] = compose(basis_rot("Neck", X, neck[0]), basis_rot("Neck", Z, neck[1]), basis_rot("Neck", Yax, neck[2]))
    p.rot["Head"] = compose(basis_rot("Head", X, head[0]), basis_rot("Head", Z, head[1]), basis_rot("Head", Yax, head[2]))
    for i, (lift, swing) in enumerate(tail):
        p.rot["Tail%d" % (i + 1)] = compose(basis_rot("Tail%d" % (i + 1), X, lift), basis_rot("Tail%d" % (i + 1), Z, swing))


STILL = {"phase": {"LH": 0, "LF": 0, "RH": 0, "RF": 0}, "duty": 1.0, "step": 0.0, "lift_fore": 0, "lift_hind": 0, "fold_fore": 0, "fold_hind": 0, "crouch": 0.0, "cap": 0.92}
WALK = {"T": 0.60, "duty": 0.64, "step": 0.25 * S, "phase": {"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75},
        "lift_fore": 0.07 * S, "lift_hind": 0.055 * S, "fold_fore": 45, "fold_hind": 14, "crouch": 0.022 * S}
TROT = {"T": 0.40, "duty": 0.44, "step": 0.25 * S, "phase": {"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5},
        "lift_fore": 0.075 * S, "lift_hind": 0.06 * S, "fold_fore": 55, "fold_hind": 20, "crouch": 0.03 * S, "carry": 0.25}
RUN = {"T": 0.36, "duty": 0.25, "step": 0.30 * S, "phase": {"LH": 0.0, "RH": 0.14, "RF": 0.50, "LF": 0.64},
       "lift_fore": 0.11 * S, "lift_hind": 0.10 * S, "fold_fore": 75, "fold_hind": 30, "crouch": 0.035 * S, "carry": 0.16,
       "fore_y": -0.03 * S, "hind_y": -0.02 * S, "narrow": 0.8}


def idle(t):
    """Eight seconds standing square: breathing, a shift of weight, a long look to one side and a
    glance to the other with the head held between, a tilt of the head, and two bursts of wagging
    that swing his hindquarters with them."""
    p = Pose()
    br = math.sin(TAU * t * 4)
    shift = ease(0.5 + 0.5 * math.sin(TAU * (t - 0.1))) - 0.5
    look = bump(t, 0.08, 0.06, 0.2, 0.08) - 0.8 * bump(t, 0.56, 0.04, 0.1, 0.07)
    lift = bump(t, 0.06, 0.07, 0.24, 0.1)
    tilt = bump(t, 0.2, 0.03, 0.08, 0.05)
    wag_on = bump(t, 0.3, 0.03, 0.22, 0.06) + 0.7 * bump(t, 0.72, 0.03, 0.14, 0.06)
    wag = wag_on * math.sin(TAU * t * 26)
    body(p, dz=-STILL["crouch"] + 0.0025 * S * br, dx=0.012 * S * shift + 0.004 * S * wag, roll=1.6 * shift, yaw=1.6 * wag,
         chest=(-0.8 * br, 0, -1.2 * shift), neck=(-6.0 * lift + 1.0 * br, 20.0 * look, 0),
         head=(-4.0 * lift, 16.0 * look, 9.0 * tilt),
         tail=((-8 * wag_on, 22 * wag), (-4 * wag_on, 26 * math.sin(TAU * t * 26 - 0.6) * wag_on), (0, 24 * math.sin(TAU * t * 26 - 1.2) * wag_on)))
    paws(p, STILL, 0.0)
    return p


def walk(t):
    g = WALK
    p = Pose()
    dip = math.cos(TAU * (t * 2 + 0.06))  # he sinks onto each foreleg as it takes his weight
    sway = math.sin(TAU * (t + 0.08))
    nod = math.sin(TAU * (t * 2 - 0.1))
    sw = math.sin(TAU * (t - 0.15))
    body(p, dz=-g["crouch"] + 0.004 * S * dip, dx=0.007 * S * sway, roll=1.8 * sway, yaw=2.2 * math.sin(TAU * t),
         chest=(0.8 * dip, -3.4 * math.sin(TAU * t), -2.4 * sway), neck=(3.0 + 6.0 * nod, 1.2 * math.sin(TAU * t), 0),
         head=(-4.0 * nod, 0, 1.4 * sway),
         tail=((6, 9 * sw), (2, 12 * math.sin(TAU * (t - 0.25))), (0, 12 * math.sin(TAU * (t - 0.35)))))
    paws(p, g, t)
    return p


def trot(t):
    g = TROT
    p = Pose()
    bob = -math.cos(2 * TAU * (t - g["duty"] / 2))  # lowest as each diagonal pair carries him, highest in the air between
    sway = math.sin(TAU * (t + 0.05))
    body(p, dz=-g["crouch"] + 0.018 * S * bob, roll=1.4 * sway, yaw=1.6 * math.sin(TAU * t), pitch=0.6 * bob,
         chest=(0, -2.4 * math.sin(TAU * t), -1.8 * sway), neck=(-5.0 - 1.6 * bob, 0, 0), head=(2.0 + 1.2 * math.sin(2 * TAU * (t - 0.3)), 0, 1.0 * sway),
         tail=((-10 + 3 * bob, 7 * sway), (-6 + 4 * math.sin(2 * TAU * (t - 0.32)), 10 * math.sin(TAU * (t - 0.1))), (-4 + 5 * math.sin(2 * TAU * (t - 0.42)), 10 * math.sin(TAU * (t - 0.2)))))
    paws(p, g, t)
    return p


def run(t):
    """A rotary gallop. The hind paws land (t=0) and drive; he stretches out and flies (about 0.4);
    the forepaws land (0.5) and he rolls over them; then he gathers, back arched, hind legs coming
    through under him (about 0.9)."""
    g = RUN
    p = Pose()
    arch = 18.0 * math.cos(TAU * (t - 0.93))  # most gathered just before the hind paws land again
    pitch = 5.0 * math.sin(TAU * (t - 0.36))  # nose down as the forepaws land, up as the hind ones drive
    height = 0.03 * S * math.cos(2 * TAU * (t - 0.42)) + 0.012 * S * math.cos(TAU * (t - 0.42))  # up in each flight
    reach = math.cos(TAU * (t - 0.40))  # the head and neck stretch forward in the long flight
    body(p, dz=-g["crouch"] + height, pitch=pitch, arch=arch, dy=-0.012 * S * reach,
         neck=(4.0 - 0.75 * arch - 0.7 * pitch + 5.0 * reach, 0, 0), head=(-2.0 - 0.3 * pitch - 3.0 * reach, 0, 0),
         tail=((-24 + 8 * math.cos(TAU * (t - 0.05)), 0), (-12 + 12 * math.cos(TAU * (t - 0.2)), 0), (-6 + 14 * math.cos(TAU * (t - 0.35)), 0)))
    paws(p, g, t)
    return p


def make_action(name, seconds, pose_at, gait=None):
    """Keys the loop. With a gait, finds the body height first: it starts high and comes down a
    little at a time until no leg is stretched past the gait's cap (MAX_EXTENSION unless it says),
    so he stands as tall as his legs allow rather than crouching like a cat stalking."""
    frames = int(round(seconds * FPS))
    cap = gait.get("cap", MAX_EXTENSION) if gait else MAX_EXTENSION
    if gait is not None:
        gait["crouch"] = -0.08 * S
    while True:
        poses = [pose_at(f / frames) for f in range(frames + 1)]
        ext = max(s[0] for p in poses for s in p.stats.values())
        if ext <= cap or gait is None:
            break
        gait["crouch"] += 0.002 * S
    slip = max(s[1] for p in poses for s in p.stats.values())
    assert ext <= MAX_EXTENSION, "%s: a leg reaches %.0f%% of its length" % (name, ext * 100)
    assert slip < 0.001, "%s: a paw misses its spot by %.4f m" % (name, slip)
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
        speed = gait["step"] / (gait["duty"] * gait["T"])
        line += "; crouch %.3f m; STRIDE %.3f m/s" % (gait["crouch"], speed)
        STRIDES[name] = round(speed, 3)
    print(line)
    return act


STRIDES = {}
for b in rig.pose.bones:
    b.rotation_mode = "QUATERNION"
make_action("Idle", 8.0, idle, STILL)
make_action("Walk", WALK["T"], walk, WALK)
make_action("Trot", TROT["T"], trot, TROT)
make_action("Run", RUN["T"], run, RUN)
bpy.context.scene.render.fps = FPS
print("STRIDE %s" % json.dumps(STRIDES))

# --- 6. textures and export ---------------------------------------------------------------------
mat = me.materials[0]
mat.name = ID
nt = mat.node_tree
bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
for n in list(nt.nodes):
    if n.type == "TEX_IMAGE" and n.image:
        img = n.image
        if img == IMAGES.get("rm"):  # the fur is matt all over: one roughness does it
            for l in [l for l in nt.links if l.from_node == n]:
                nt.links.remove(l)
            continue
        if max(img.size) > TEX:
            img.scale(TEX, TEX)
        img.name = "%s_%s" % (ID, "normal" if img == IMAGES.get("normal") else "color")
if bsdf:
    for sock in ("Roughness", "Metallic"):
        for l in [l for l in nt.links if l.to_socket == bsdf.inputs[sock]]:
            nt.links.remove(l)
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0

ob.name = me.name = "model"
out = os.path.join(PROJECT, "assets", "props", ID + ".glb")
if "--no-export" not in argv:
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    rig.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=90, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_draco_mesh_compression_enable=False)
    print("RIGGED %s: %d -> %d faces, %d bones, textures %d px -> %s" % (ID, before, len(me.polygons), len(arm_data.bones), TEX, out))

# --- optional: review renders -------------------------------------------------------------------
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    if "--debug-patch" in argv:
        dm = bpy.data.materials.new("patch_debug")
        dm.diffuse_color = (1, 0, 1, 1)
        me.materials.append(dm)
        for fi in PATCH_FACES:
            me.polygons[fi].material_index = len(me.materials) - 1
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.2
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    sc.world = w
    floor_me = bpy.data.meshes.new("floor")
    floor_me.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("floor", floor_me)
    fm = bpy.data.materials.new("floor")
    fm.diffuse_color = (0.42, 0.5, 0.36, 1)
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.5, 0.36, 1)
    floor_me.materials.append(fm)
    sc.collection.objects.link(floor)
    sc.view_settings.view_transform = "Standard"
    sc.render.engine = "BLENDER_EEVEE"
    if "--cpu-render" in argv:  # Cycles on the CPU: EEVEE can stall while a game window holds the GPU
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 24
        sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 560, 420
    sc.render.film_transparent = False
    views = {"side": (Vector((1, 0, 0.12)), 1.25), "front": (Vector((0.45, -1, 0.3)), 1.1), "below": (Vector((0.5, -0.5, -1)), 1.1),
             "back": (Vector((-0.6, 1, 0.35)), 1.1), "under": (Vector((-0.4, -1, -0.45)), 0.75),
             "chest": (Vector((-1, -0.7, 0.1)), 0.45, EXTRA_PAW + Vector((0, 0.06 * S, 0.14 * S)))}

    def shot(fname, view, hide_floor=False):
        d, scale = views[view][:2]
        d = d.normalized()
        c = views[view][2] if len(views[view]) > 2 else Vector((0, 0, HEIGHT * 0.45))
        cam.location = c + d * 4
        cam.data.ortho_scale = scale * HEIGHT / 0.62
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sun.rotation_euler = ((c - (c + (d + Vector((0.3, -0.2, 0.9))).normalized())).to_track_quat("-Z", "Y")).to_euler()
        floor.hide_render = hide_floor or d.z < 0
        sc.render.filepath = os.path.join(RENDER, fname)
        bpy.ops.render.render(write_still=True)

    rig.animation_data.action = None
    for tr in rig.animation_data.nla_tracks:
        tr.mute = True
    for v in ("side", "front", "back", "below", "under", "chest"):
        shot("rest_%s.png" % v, v)
    plan = {"Idle": ((0.0, 0.18, 0.35, 0.62), ("side", "front")), "Walk": ([i / 8 for i in range(8)], ("side", "front")),
            "Trot": ([i / 8 for i in range(8)], ("side", "front")), "Run": ([i / 8 for i in range(8)], ("side", "front"))}
    for act_name, (fracs, vs) in plan.items():
        act = bpy.data.actions[act_name]
        rig.animation_data.action = act
        n = int(act.frame_range[1] - act.frame_range[0])
        for fr in fracs:
            sc.frame_set(int(round(1 + fr * n)))
            for v in vs:
                shot("%s_%03d_%s.png" % (act_name, int(round(fr * 100)), v), v)
    print("RENDERED", RENDER)
