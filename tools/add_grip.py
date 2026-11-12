"""Adds a 'grip_R' shape key to a character's body: the right hand's fingers curled round a handle
that runs front to back across the palm (the fist a tool is held in), the thumb and palm pushed out
of the handle. The rig has no finger bones, so the game turns the key on while she holds a tool.

Run it on the eyes model's blend (after tools/add_eyes.py, which starts that blend afresh), then
import. It saves the blend and exports assets/<id>_eyes.glb with add_eyes.py's export settings.

    Blender -b tools/character_build/<id>_eyes/<id>_eyes.blend -P tools/add_grip.py -- "$PWD" <id> [--review]

The hand's measurements (rest pose, Blender metres) are per character: GRIPS below. The game's
TOOL_FIST in scripts/main.gd must match the handle's centre and axis here.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, CID = argv[0], argv[1]
REVIEW = "--review" in argv

# Nora's right hand hangs at her side, palm in (+x), fingers down, knuckles at z 0.725; the
# fingers fan front (index, y -0.105) to back (little finger, y -0.02). The handle: a cylinder
# along y through (HX, HZ), radius R, against the palm just below the finger roots.
GRIPS = {
    "nora_tripo": dict(zk=0.725, hx=-0.194, hz=0.716, r=0.021, theta_max=3.25,
                      bands=(-0.034, -0.061, -0.09), thumb=dict(x=-0.212, y=-0.088, z=0.80)),
}
G = GRIPS[CID]


def body_mesh():
    return max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.vertices))


def main():
    body = body_mesh()
    me = body.data
    gi = body.vertex_groups["RightHand"].index
    mw = body.matrix_world
    inv = mw.inverted()
    if not me.shape_keys:
        body.shape_key_add(name="Basis", from_mix=False)
    if "grip_R" in me.shape_keys.key_blocks:
        body.shape_key_remove(me.shape_keys.key_blocks["grip_R"])
    key = body.shape_key_add(name="grip_R", from_mix=False)

    def w_hand(v):
        return sum(g.weight for g in v.groups if g.group == gi)

    P = {v.index: mw @ v.co for v in me.vertices if w_hand(v) > 0.3}
    hx, hz, R, zk = G["hx"], G["hz"], G["r"], G["zk"]
    th = G["thumb"]

    def band(p):
        return sum(1 for b in G["bands"] if p.y < b)

    def is_thumb(p):
        return p.x > th["x"] and p.y < th["y"] and p.z < th["z"]

    fingers = {i: p for i, p in P.items() if p.z < zk and not is_thumb(p) and w_hand(me.vertices[i]) > 0.5}
    # each finger's palm side at its root: the innermost of its vertices just below the knuckle
    xs = {}
    for i, p in fingers.items():
        if p.z > zk - 0.03:
            b = band(p)
            xs[b] = max(xs.get(b, -9.0), p.x)
    print("[grip] fingers", len(fingers), "palm side per finger", {b: round(x, 4) for b, x in sorted(xs.items())})
    moved = {}
    for i, p in fingers.items():
        x0 = xs.get(band(p), hx - R)
        rf = max(R, hx - x0)              # this finger wraps the handle at its own distance from it
        n = x0 - p.x                       # depth from the finger's palm side toward its back
        s = zk - p.z                       # how far down the finger
        # bend about the finger's middle, so its back stretches a little and its pad tucks in
        theta = s / (rf + 0.009)
        theta = G["theta_max"] * math.tanh(theta / G["theta_max"])
        rad = rf + n
        # the bend only starts at the knuckle: a vertex level with it stays where it is
        c = Vector((hx, p.y, zk))
        q = c + Vector((-rad * math.cos(theta), 0.0, -rad * math.sin(theta)))
        q.x += 0.0
        moved[i] = q
    # nothing passes through the handle: the thumb, the palm and any finger pushed out to its skin
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
        key.data[i].co = inv @ q
    key.value = 0.0
    print("[grip] moved", len(moved), "vertices; handle at x %.3f z %.3f r %.3f" % (hx, hz, R))


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
