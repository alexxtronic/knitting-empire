"""Put a sculpted body on a character's existing rig and animations.

Run headless:
  Blender -b tools/character_build/<id>/<id>.blend -P tools/rig_sculpt.py -- \
      <project_dir> <colored.ply> <out_id> [--faces 24000] [--tex 2048] [--render DIR]

Takes a body mesh, either a vertex-coloured .ply (image-to-sculpt plus tools/project_colors.py, or
tools/run_triposr.py; +Z up, facing -Y, any scale) or a textured .glb/.gltf (e.g. from tripo.ai: glTF's
+Y up and +Z front, which Blender turns into +Z up and facing -Y), and the character .blend made by
tools/build_character.py, then:

  1. scales the sculpt to the rig's height, feet on the ground, torso over the spine;
  2. decimates it to a game budget; a .ply is unwrapped and its vertex colours baked into one texture,
     a .glb keeps its own UVs and base-colour texture;
  3. aims a copy of the rig's arms along the sculpt's arms (found from the arm's outer outline;
     generated turnarounds stand in a wider A-pose than the rig), binds the mesh to it with automatic
     weights, then splits arm skin from body skin by distance along the surface so a hand resting on
     a thigh doesn't move with the leg (or the arm sink into the body), swings the arms back to the
     rig's rest pose and applies that, so the mesh now matches the real rig's rest pose;
  4. swaps the procedural body for the sculpt on the real rig (bones, animations and knitting
     props are untouched) and exports assets/<out_id>.glb, plus a turntable/pose check with --render.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, PLY, OUT_ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]
FACES = int(argv[argv.index("--faces") + 1]) if "--faces" in argv else 24000
TEX = int(argv[argv.index("--tex") + 1]) if "--tex" in argv else 2048
RENDER = argv[argv.index("--render") + 1] if "--render" in argv else None

scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == "ARMATURE")
old_body = next(o for o in scene.objects if o.type == "MESH" and o.parent == rig and o.name != "KnitProps")
bones = rig.data.bones
head_top = max((old_body.matrix_world @ Vector(c)).z for c in old_body.bound_box)
print("RIG", rig.name, "body", old_body.name, "height", round(head_top, 3))


def select_only(*objs):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    for o in scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


# ----------------------------------------------------------------------------- 1. import and place
TEXTURED = PLY.lower().endswith((".glb", ".gltf"))
if TEXTURED:
    bpy.ops.import_scene.gltf(filepath=PLY)
    parts = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    for o in [o for o in bpy.context.selected_objects if o.type != "MESH"]:
        for c in o.children:
            c.matrix_parent_inverse = Matrix.Identity(4)
    select_only(*parts)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(parts) > 1:
        bpy.ops.object.join()
    hi = bpy.context.view_layer.objects.active
else:
    bpy.ops.wm.ply_import(filepath=PLY)
    hi = bpy.context.selected_objects[0]
hi.name = OUT_ID + "_hi"
V = np.array([v.co[:] for v in hi.data.vertices])
z0, h = V[:, 2].min(), V[:, 2].max() - V[:, 2].min()
s = head_top / h
torso = V[(V[:, 2] - z0 > 0.59 * h) & (V[:, 2] - z0 < 0.73 * h)]
cx, cy = np.median(torso[:, 0]), np.median(torso[:, 1])
hi.data.transform(Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation((-cx, -cy, -z0)))
hi.data.update()
print("SCULPT scale", round(s, 4), "verts", len(hi.data.vertices))

# ----------------------------------------------------------------------------- 2. game mesh + texture
def color_material(name, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    if image is None:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = hi.data.color_attributes[0].name
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(attr.outputs["Color"], em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.nodes.active = tex
    return m


def decimate(ob):
    select_only(ob)
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, FACES / len(ob.data.polygons))
    bpy.ops.object.modifier_apply(modifier="dec")


if TEXTURED:
    # a modelled mesh with its own UVs and texture: keep both. Weld the vertices glTF split along
    # every UV seam (UVs live on the face corners, so they survive), or the decimator can't collapse
    # across those seams and stops at several times the budget; then use the model's own base colour.
    lo = hi
    lo.name = lo.data.name = OUT_ID + "Mesh"
    bm = bmesh.new()
    bm.from_mesh(lo.data)
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    print("WELDED", n0, "->", len(bm.verts), "verts")
    bm.to_mesh(lo.data)
    bm.free()
    if lo.data.has_custom_normals:
        select_only(lo)
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    decimate(lo)
    mats = list(lo.data.materials)
    lo.data.materials.clear()
    for i, m in enumerate(mats):
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        link = bsdf.inputs["Base Color"].links
        img = link[0].from_node.image if link and link[0].from_node.type == "TEX_IMAGE" else None
        if img is None:
            raise SystemExit("material %s has no base-colour texture" % m.name)
        img.name = OUT_ID + ("_albedo" if i == 0 else "_albedo%d" % i)
        if max(img.size) > TEX:
            img.scale(TEX, TEX)
        img.pack()  # embedded in the .glb; Godot extracts it on import as assets/<id>_<id>_albedo.png
        lo.data.materials.append(color_material(OUT_ID.capitalize() + ("" if i == 0 else str(i)), img))
        print("TEXTURE", img.name, tuple(img.size))
    for p in lo.data.polygons:
        p.use_smooth = True
    print("GAME MESH faces", len(lo.data.polygons))
else:
    lo = hi.copy()
    lo.data = hi.data.copy()
    lo.name = lo.data.name = OUT_ID + "Mesh"
    scene.collection.objects.link(lo)
    decimate(lo)
    # irons out the ripples a silhouette-only fit leaves
    sm = lo.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.iterations, sm.lambda_factor, sm.use_volume_preserve = 6, 0.6, True
    bpy.ops.object.modifier_apply(modifier="smooth")
    for p in lo.data.polygons:
        p.use_smooth = True
    print("GAME MESH faces", len(lo.data.polygons))

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")

    img = bpy.data.images.new(OUT_ID + "_albedo", TEX, TEX)
    img.colorspace_settings.name = "sRGB"
    hi.data.materials.clear()
    hi.data.materials.append(color_material("bake_src"))
    lo.data.materials.clear()
    lo.data.materials.append(color_material(OUT_ID.capitalize(), img))

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = 0.02
    scene.render.bake.max_ray_distance = 0.05
    scene.render.bake.margin = 6
    select_only(lo, hi)
    hi.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type="EMIT")
    img.pack()  # embedded in the .glb; Godot extracts it on import as assets/<id>_<id>_albedo.png
    print("BAKED", img.name, TEX)
    bpy.data.objects.remove(hi)

# ----------------------------------------------------------------------------- 3. bind in the sculpt's pose
L = np.array([v.co[:] for v in lo.data.vertices])
temp = rig.copy()
temp.data = rig.data.copy()
temp.animation_data_clear()
scene.collection.objects.link(temp)
for pb in temp.pose.bones:  # the copy keeps whatever pose the rig was last evaluated in; start from rest
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
swing = {}
select_only(temp)
bpy.ops.object.mode_set(mode="EDIT")
eb = temp.data.edit_bones
seg = {}  # bone -> (head, tail) of the aimed copy, in the mesh's space
for side, sx in (("Left", 1), ("Right", -1)):
    sh = eb[side + "UpperArm"].head.copy()
    tip = eb[side + "Hand"].tail.copy()
    # the arm's angle from its outer outline: in every slice between armpit and wrist the outermost
    # point on this side is the outside of the arm, whether the arm hangs wide (generated A-pose
    # turnarounds) or close against the body (tripo.ai). Fit a line through those points.
    pts = []
    for z in np.arange(sh.z - 0.12, tip.z + 0.12, -0.02):
        sl = L[(np.abs(L[:, 2] - z) < 0.008) & (L[:, 0] * sx > 0)]
        if len(sl):
            pts.append((z, (sl[:, 0] * sx).max()))
    pts = np.array(pts)
    slope = np.polyfit(pts[:, 0], pts[:, 1], 1)[0]  # outward x per metre of height
    want = Vector((-slope * sx, 0.0, -1.0)).normalized()
    have = Vector((tip.x - sh.x, 0.0, tip.z - sh.z)).normalized()
    ang = math.atan2(have.cross(want).y, have.dot(want))
    R = Matrix.Translation(sh) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Translation(-sh)
    for b in ("UpperArm", "LowerArm", "Hand"):
        eb[side + b].transform(R)
    swing[side] = (sh, -ang)
    print("ARM", side, "slices", len(pts), "rig", round(math.degrees(math.atan2(abs(have.x), -have.z)), 1),
          "sculpt", round(math.degrees(math.atan2(abs(want.x), -want.z)), 1), "deg")
for b in eb:
    seg[b.name] = (np.array((temp.matrix_world @ b.head)[:]), np.array((temp.matrix_world @ b.tail)[:]))
bpy.ops.object.mode_set(mode="OBJECT")

select_only(lo, temp)
lo.select_set(True)
bpy.context.view_layer.objects.active = temp
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
print("WEIGHTS groups", len(lo.vertex_groups))


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def geodesic(seeds, adj, n):
    import heapq
    d = np.full(n, np.inf)
    q = [(0.0, int(i)) for i in seeds]
    for _, i in q:
        d[i] = 0.0
    heapq.heapify(q)
    while q:
        di, i = heapq.heappop(q)
        if di > d[i]:
            continue
        for j, w in adj[i]:
            if di + w < d[j]:
                d[j] = di + w
                heapq.heappush(q, (di + w, j))
    return d


# Automatic weights go by straight-line distance, so where a hand rests against a thigh or a forearm
# against the sweater, skin of one is bound to the other's bones and the arm sinks into the body when
# it moves. Split arm skin from body skin by distance along the surface instead: grown out from the
# forearm on one side and from the thigh and waist on the other, the two only meet where they touch.
n = len(L)
adj = [[] for _ in range(n)]
for e in lo.data.edges:
    i, j = e.vertices
    w = float(np.linalg.norm(L[i] - L[j]))
    adj[i].append((j, w))
    adj[j].append((i, w))
gidx = {g.name: g.index for g in lo.vertex_groups}
for side, sx in (("Left", 1), ("Right", -1)):
    arm_bones = [side + b for b in ("Shoulder", "UpperArm", "LowerArm", "Hand")]
    sh_z = seg[side + "UpperArm"][0][2]
    wrist = seg[side + "Hand"][0]
    elbow = seg[side + "LowerArm"][0]
    d_fore = seg_dist(L, elbow, wrist)
    d_hand = seg_dist(L, *seg[side + "Hand"])
    d_thigh = seg_dist(L, *seg[side + "UpperLeg"])
    side_ok = L[:, 0] * sx > 0.02
    seeds_arm = np.where(side_ok & (d_fore < 0.05) & (L[:, 2] > wrist[2] + 0.06))[0]
    seeds_body = np.where(side_ok & (((d_thigh < 0.07) & (L[:, 2] < seg[side + "Hand"][1][2] - 0.03))
                                     | ((np.abs(L[:, 0]) < 0.05) & (np.abs(L[:, 2] - elbow[2]) < 0.1))))[0]
    if not len(seeds_arm) or not len(seeds_body):
        print("SPLIT", side, "skipped: no seeds")
        continue
    ga, gb = geodesic(seeds_arm, adj, n), geodesic(seeds_body, adj, n)
    zone = side_ok & (L[:, 2] < sh_z - 0.15)
    is_arm = zone & (ga < gb)
    is_body = zone & ~is_arm
    moved = 0
    for i in np.where(zone)[0]:
        v = lo.data.vertices[i]
        keep_arm = bool(is_arm[i])
        for g in list(v.groups):
            name = lo.vertex_groups[g.group].name
            if (name in arm_bones) != keep_arm and g.weight > 0.0:
                lo.vertex_groups[g.group].remove([int(i)])
                moved += 1
        if not any(g.weight > 1e-4 for g in v.groups):  # stripped bare: give it the nearest allowed bone
            names = arm_bones[1:] if keep_arm else ["Hips", side + "UpperLeg", "Spine"]
            best = min(names, key=lambda b: seg_dist(L[i:i + 1], *seg[b])[0])
            lo.vertex_groups[gidx[best]].add([int(i)], 1.0, "REPLACE")
    print("SPLIT", side, "arm verts", int(is_arm.sum()), "body verts", int(is_body.sum()), "weights moved", moved,
          "hand verts", int((is_arm & (d_hand < 0.06)).sum()))

# swing the arms back to the real rig's rest angle and bake that into the mesh
select_only(temp)
bpy.ops.object.mode_set(mode="POSE")
for side, (sh, ang) in swing.items():
    pb = temp.pose.bones[side + "UpperArm"]
    pb.matrix = Matrix.Translation(sh) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Translation(-sh) @ pb.bone.matrix_local
    bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="OBJECT")
select_only(lo)
mod = next(m for m in lo.modifiers if m.type == "ARMATURE")
bpy.ops.object.modifier_apply(modifier=mod.name)
lo.parent = None
lo.matrix_world = Matrix.Identity(4)
bpy.data.objects.remove(temp)

# ----------------------------------------------------------------------------- 4. onto the real rig, export
bpy.data.objects.remove(old_body)
lo.parent = rig
am = lo.modifiers.new("Armature", "ARMATURE")
am.object = rig
rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()

assets = os.path.join(PROJECT, "assets")
build = os.path.join(PROJECT, "tools", "character_build", OUT_ID)
os.makedirs(build, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(build, OUT_ID + ".blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(assets, OUT_ID + ".glb"), export_format="GLB", export_apply=True,
                          export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
                          export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
print("EXPORTED", os.path.join(assets, OUT_ID + ".glb"), "faces", len(lo.data.polygons))

# ----------------------------------------------------------------------------- check renders
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 480, 720
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("w") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.55, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam

    rig.animation_data.use_nla = False  # the stored NLA tracks would blend every loop together

    def shoot(path, yaw_deg, action=None, frame=0):
        rig.animation_data.action = bpy.data.actions[action] if action else None
        if action is None:
            for pb in rig.pose.bones:
                pb.matrix_basis = Matrix.Identity(4)
        scene.frame_set(frame)
        a = math.radians(yaw_deg)
        cam.location = (3.2 * math.sin(a), -3.2 * math.cos(a), 1.0)
        cam.rotation_euler = (math.radians(88), 0, a)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    for yaw in (0, 45, 90, 180, 270):
        shoot(os.path.join(RENDER, f"turn_{yaw:03d}.png"), yaw)
    for act in ("Idle", "Walk", "SitKnit", "Talk", "Work"):
        rng = bpy.data.actions[act].frame_range
        shoot(os.path.join(RENDER, f"pose_{act}.png"), 30, act, int((rng[0] + rng[1]) / 2))
    print("RENDERED", RENDER)
