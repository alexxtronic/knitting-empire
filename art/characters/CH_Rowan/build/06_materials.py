"""
CH_Rowan phase 06: look-development materials (procedural, for the review renders).

  Blender --background --python build/06_materials.py -- --master CH_Rowan_master.blend

Rebuilds the node trees of the materials the other phases assign by name. Colours are the
median sRGB of the same patch in ref/sheet.png (linear values below). These are Blender
materials for review; the game texture (one painted 2048 px set) is baked from them later.
"""
import bpy, sys, os, math, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import argv_after_dashes, open_master, save_master
from spec import EYE


class G:
    """A small node-graph builder."""

    def __init__(self, name):
        self.m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        if bpy.app.version < (5, 0, 0):
            self.m.use_nodes = True
        self.nt = self.m.node_tree
        self.nt.nodes.clear()
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        self.b = self.nt.nodes.new("ShaderNodeBsdfPrincipled")
        self.nt.links.new(self.b.outputs[0], self.out.inputs[0])

    def set(self, sock, v):
        if hasattr(v, "is_output") or hasattr(v, "links"):
            self.nt.links.new(v, sock)
        elif isinstance(v, (tuple, list)) and len(v) == 3 and sock.type == "RGBA":
            sock.default_value = (*v, 1.0)
        else:
            sock.default_value = v

    def p(self, **kw):
        names = {"color": "Base Color", "rough": "Roughness", "metal": "Metallic", "normal": "Normal",
                 "sss": "Subsurface Weight", "sheen": "Sheen Weight", "coat": "Coat Weight", "spec": "Specular IOR Level"}
        for k, v in kw.items():
            self.set(self.b.inputs[names[k]], v)
        col = kw.get("color")
        if isinstance(col, (tuple, list)):
            self.m.diffuse_color = (*col, 1.0)

    def math(self, op, a, b=None, clamp=False):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self.set(n.inputs[0], a)
        if b is not None:
            self.set(n.inputs[1], b)
        return n.outputs[0]

    def ramp(self, v, a, b, lo=0.0, hi=1.0):
        """smoothstep from a to b, mapped to lo..hi."""
        n = self.nt.nodes.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP" if a < b else "LINEAR"
        if a > b:                                # falling ramp: flip it
            a, b, lo, hi = b, a, hi, lo
            n.interpolation_type = "SMOOTHSTEP"
        self.set(n.inputs[0], v)
        n.inputs[1].default_value, n.inputs[2].default_value = a, b
        n.inputs[3].default_value, n.inputs[4].default_value = lo, hi
        return n.outputs[0]

    def mix(self, f, a, b):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        self.set(n.inputs[0], f)
        self.set(n.inputs[6], a)
        self.set(n.inputs[7], b)
        return n.outputs[2]

    def uv(self):
        n = self.nt.nodes.new("ShaderNodeUVMap")
        s = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(n.outputs[0], s.inputs[0])
        return n.outputs[0], s.outputs[0], s.outputs[1]

    def pos(self, obj=False):
        if obj:
            return self.nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        return self.nt.nodes.new("ShaderNodeNewGeometry").outputs["Position"]

    def xyz(self, v):
        s = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(v, s.inputs[0])
        return s.outputs[0], s.outputs[1], s.outputs[2]

    def vec(self, x, y, z):
        c = self.nt.nodes.new("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            self.set(c.inputs[i], v)
        return c.outputs[0]

    def noise(self, vector=None, scale=5.0, detail=2.0):
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        if vector is not None:
            self.nt.links.new(vector, n.inputs["Vector"])
        return n.outputs[0]

    def bump(self, height, strength=0.5, dist=0.002):
        n = self.nt.nodes.new("ShaderNodeBump")
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = dist
        self.nt.links.new(height, n.inputs["Height"])
        return n.outputs[0]

    def blob(self, P, c, r, r0, r1):
        """1 inside an ellipsoid (centre c, radii r), fading out between scaled radius r0 and r1. Mirrored in x."""
        x, y, z = self.xyz(P)
        ax = self.math("ABSOLUTE", x)
        dx = self.math("DIVIDE", self.math("SUBTRACT", ax, c[0]), r[0])
        dy = self.math("DIVIDE", self.math("SUBTRACT", y, c[1]), r[1])
        dz = self.math("DIVIDE", self.math("SUBTRACT", z, c[2]), r[2])
        v = self.nt.nodes.new("ShaderNodeVectorMath")
        v.operation = "LENGTH"
        self.nt.links.new(self.vec(dx, dy, dz), v.inputs[0])
        return self.ramp(v.outputs["Value"], r1, r0)


def skin():
    g = G("CH_Rowan_Skin")
    P = g.pos()
    base = (0.780, 0.340, 0.180)                         # ref forehead / hand, a warm peach
    cheek = g.blob(P, (0.046, -0.110, 1.614), (0.030, 0.030, 0.024), 0.35, 1.25)
    nose = g.blob(P, (0.0, -0.158, 1.613), (0.016, 0.016, 0.014), 0.4, 1.3)
    ear = g.blob(P, (0.092, 0.016, 1.628), (0.012, 0.022, 0.030), 0.3, 1.2)
    c = g.mix(g.math("MULTIPLY", cheek, 0.78), base, (0.800, 0.170, 0.085))       # ref cheek
    c = g.mix(g.math("MULTIPLY", nose, 0.58), c, (0.820, 0.180, 0.090))
    c = g.mix(g.math("MULTIPLY", ear, 0.30), c, (0.800, 0.200, 0.115))
    # the closed, smiling mouth: a dark line that rises to the corners, a soft lower lip under it
    x, y, z = g.xyz(P)
    ax = g.math("ABSOLUTE", x)
    xr = g.math("DIVIDE", ax, 0.040)
    zline = g.math("ADD", 1.5840, g.math("MULTIPLY", g.math("MULTIPLY", xr, xr), 0.0080))
    dzs = g.math("SUBTRACT", z, zline)
    front = g.ramp(y, -0.095, -0.105)
    lip = g.math("MULTIPLY", g.ramp(dzs, -0.0100, -0.0055), g.ramp(dzs, -0.0002, -0.0020))
    lip = g.math("MULTIPLY", g.math("MULTIPLY", lip, g.ramp(ax, 0.036, 0.024)), front)
    c = g.mix(g.math("MULTIPLY", lip, 0.60), c, (0.600, 0.150, 0.105))            # ref lower lip
    line = g.math("MULTIPLY", g.ramp(g.math("ABSOLUTE", dzs), 0.0018, 0.0006), g.ramp(ax, 0.043, 0.037))
    c = g.mix(g.math("MULTIPLY", g.math("MULTIPLY", line, front), 0.9), c, (0.160, 0.035, 0.025))
    # stubble under the beard and the hair, so their edges are a clean painted line
    def attr(name):
        n = g.nt.nodes.new("ShaderNodeAttribute")
        n.attribute_name = name
        return g.ramp(n.outputs["Fac"], 0.12, 0.62)       # a soft stubble edge
    fb, fh = attr("beard"), attr("hair")
    c = g.mix(fb, c, (0.185, 0.080, 0.040))
    c = g.mix(fh, c, (0.110, 0.046, 0.021))
    furry = g.math("MAXIMUM", fb, fh)
    g.p(color=c, rough=g.ramp(furry, 0.0, 1.0, 0.50, 0.90), sss=0.06)
    g.b.inputs["Subsurface Radius"].default_value = (0.012, 0.005, 0.003)
    g.b.inputs["Subsurface Scale"].default_value = 0.5
    g.m.diffuse_color = (*base, 1.0)


def knit(name, color, fu=118.0, fv=132.0, strength=0.9):
    """Stocking stitch from the metric UVs: columns of V stitches, 8.5 mm wide (the reference's chunky knit)."""
    g = G(name)
    _, u, v = g.uv()
    a = g.math("FRACT", g.math("MULTIPLY", u, fu))
    tri = g.math("ABSOLUTE", g.math("SUBTRACT", g.math("MULTIPLY", a, 2.0), 1.0))       # 0 between columns, 1 mid column
    row = g.math("ADD", g.math("MULTIPLY", v, fv), g.math("MULTIPLY", tri, 0.45))
    h = g.math("ADD", g.math("MULTIPLY", g.math("SINE", g.math("MULTIPLY", row, 2 * math.pi)), 0.5), 0.5)
    h = g.math("MULTIPLY", h, g.ramp(tri, 0.0, 0.40))
    at = g.nt.nodes.new("ShaderNodeAttribute")             # ribbed bands: plain ribs, 11 mm apart, run along the garment
    at.attribute_name = "rib"
    ribf = g.ramp(at.outputs["Fac"], 0.35, 0.65)
    hr = g.math("ADD", g.math("MULTIPLY", g.math("SINE", g.math("MULTIPLY", u, 2 * math.pi / 0.011)), 0.5), 0.5)
    h = g.math("ADD", h, g.math("MULTIPLY", g.math("SUBTRACT", hr, h), ribf))
    heather = g.noise(g.pos(), 900.0, 3.0)
    col = g.mix(g.ramp(heather, 0.35, 0.70), tuple(c * 0.72 for c in color), tuple(c * 1.25 for c in color))
    col = g.mix(g.ramp(h, 0.0, 0.5, 0.45, 0.0), col, tuple(c * 0.35 for c in color))     # darker in the valleys
    g.p(color=col, rough=0.95, sheen=0.35, normal=g.bump(h, strength, 0.0025), spec=0.2)
    g.m.diffuse_color = (*color, 1.0)


def cloth(name, color, twill=700.0, rough=0.85, strength=0.25, stitch=None):
    g = G(name)
    _, u, v = g.uv()
    d = g.math("SINE", g.math("MULTIPLY", g.math("ADD", u, v), twill * 2 * math.pi))
    n = g.noise(g.pos(), 350.0, 4.0)
    h = g.math("ADD", g.math("MULTIPLY", d, 0.5), n)
    col = g.mix(g.ramp(n, 0.3, 0.75), tuple(c * 0.8 for c in color), tuple(c * 1.3 for c in color))
    if stitch:                                             # painted by 04_outfit.py in the metric UV space
        img = bpy.data.images.load(stitch, check_existing=True)
        img.reload()
        img.colorspace_settings.name = "Non-Color"
        t = g.nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.extension = "CLIP"
        g.nt.links.new(g.vec(g.math("DIVIDE", u, 2.5), g.math("DIVIDE", g.math("ADD", v, 0.3), 0.85), 0.0), t.inputs["Vector"])
        r_, g_, _b = g.xyz(t.outputs["Color"])
        col = g.mix(g.math("MULTIPLY", g_, 0.55), col, tuple(c * 0.25 for c in color))      # seam shadow
        col = g.mix(g.math("MULTIPLY", r_, 0.95), col, (0.420, 0.200, 0.060))               # ref: tan topstitching
        h = g.math("ADD", h, g.math("MULTIPLY", r_, 2.0))
    g.p(color=col, rough=rough, normal=g.bump(h, strength, 0.0008), spec=0.25)
    g.m.diffuse_color = (*color, 1.0)


def plain(name, color, rough, metal=0.0, noise_bump=0.0, scale=400.0, coat=0.0, spec=0.5):
    g = G(name)
    kw = dict(color=color, rough=rough, metal=metal, coat=coat, spec=spec)
    if noise_bump > 0:
        kw["normal"] = g.bump(g.noise(g.pos(), scale, 4.0), noise_bump, 0.0008)
    g.p(**kw)


def hair(name, dark, light, along=14.0, across=520.0, strength=0.45, obj_noise=False):
    g = G(name)
    if obj_noise:                                        # short fur: fine isotropic grain
        n = g.noise(g.pos(), 1700.0, 3.0)
    else:                                                # strands running along each lock
        _, u, v = g.uv()
        n = g.noise(g.vec(g.math("MULTIPLY", u, across), g.math("MULTIPLY", v, along), 0.0), 1.0, 3.0)
    col = g.mix(g.ramp(n, 0.32, 0.72), dark, light)
    g.p(color=col, rough=0.62, normal=g.bump(n, strength, 0.0015), spec=0.3)
    g.m.diffuse_color = (*light, 1.0)


def eyes():
    plain("CH_Rowan_EyeWhite", (0.900, 0.880, 0.860), 0.10, coat=0.6)
    plain("CH_Rowan_Pupil", (0.004, 0.004, 0.006), 0.06, coat=1.0)
    g = G("CH_Rowan_Iris")
    x, y, z = g.xyz(g.pos(obj=True))
    r = g.math("SQRT", g.math("ADD", g.math("MULTIPLY", x, x), g.math("MULTIPLY", z, z)))
    streak = g.noise(g.vec(g.math("MULTIPLY", g.math("ARCTAN2", x, z), 6.0), 0.0, 0.0), 3.0, 2.0)
    c = g.mix(g.ramp(r, 0.0070, 0.0112), (0.060, 0.150, 0.300), (0.130, 0.270, 0.450))      # ref: clear blue
    c = g.mix(g.math("MULTIPLY", g.ramp(streak, 0.3, 0.8), 0.30), c, (0.260, 0.430, 0.620))
    c = g.mix(g.ramp(r, 0.0122, 0.0141), c, (0.015, 0.035, 0.080))                          # dark rim
    g.p(color=c, rough=0.08, coat=1.0)
    g.m.diffuse_color = (0.10, 0.34, 0.66, 1.0)


def build():
    skin()
    knit("CH_Rowan_Sweater", (0.130, 0.106, 0.090))                     # ref sweater
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cloth("CH_Rowan_Denim", (0.015, 0.018, 0.028), stitch=os.path.join(here, "textures", "CH_Rowan_JeansStitch.png"))                      # ref jeans, read as dark indigo
    cloth("CH_Rowan_DenimCuff", (0.300, 0.265, 0.235), strength=0.35)   # ref cuff
    plain("CH_Rowan_BootLeather", (0.170, 0.058, 0.024), 0.42, noise_bump=0.12, scale=260.0, coat=0.15)
    plain("CH_Rowan_BootSole", (0.300, 0.185, 0.085), 0.85, noise_bump=0.2, scale=500.0)
    plain("CH_Rowan_BootLace", (0.360, 0.220, 0.100), 0.9, noise_bump=0.4, scale=1500.0)
    plain("CH_Rowan_Belt", (0.105, 0.043, 0.022), 0.5, noise_bump=0.1, scale=300.0)
    plain("CH_Rowan_Brass", (0.650, 0.440, 0.170), 0.32, metal=0.9)
    hair("CH_Rowan_Hair", (0.135, 0.056, 0.025), (0.265, 0.112, 0.050), strength=0.35)  # ref hair, shadow to highlight
    hair("CH_Rowan_Beard", (0.150, 0.064, 0.030), (0.300, 0.135, 0.066), obj_noise=True, strength=0.9)
    hair("CH_Rowan_Brow", (0.060, 0.022, 0.009), (0.110, 0.040, 0.016), obj_noise=True, strength=0.5)
    eyes()
    plain("CH_Rowan_Teeth", (0.860, 0.830, 0.760), 0.28)
    plain("CH_Rowan_Gum", (0.560, 0.190, 0.190), 0.4)
    plain("CH_Rowan_Tongue", (0.620, 0.210, 0.220), 0.38, noise_bump=0.15, scale=900.0)
    plain("CH_Rowan_MouthInside", (0.120, 0.022, 0.026), 0.6)
    print("[06_materials] rebuilt", len([m for m in bpy.data.materials if m.name.startswith("CH_Rowan_")]), "materials")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--master", required=True)
    a = p.parse_args(argv_after_dashes())
    open_master(a.master)
    build()
    save_master(a.master)
