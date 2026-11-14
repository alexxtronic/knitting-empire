"""The wild animals' shapes and colours, read off their reference sheets (ref/<id>.png).

Every measurement is in units of the reference figure's height, read off the side view on a grid
(`u` right from the nose tip, so toward the tail; `v` up from the ground; `x` out to the animal's side,
judged from the front three-quarter view). `unit` is how many metres one unit is in the game: the
figure's height there. build.py turns u, v, x into Blender's -Y front, +Z up, +X the animal's left.

Shapes (all u, v, then sizes in units):
  torso, extra:  ellipsoids (u, v, half-width, half-length, half-height), blended like clay
  fore, hind:    the leg's joints top to toe (u, v, radius); fore: shoulder, elbow, wrist, toe;
                 hind: hip, knee, hock, toe. The radius is the leg's thickness there.
  head, snout:   ellipsoids; nose (u, v, r); eye (u, v, x, r)
  ears:          kind (pointy, long, round), base (u, v, x), length, width, tilt back and splay (deg)
  tail:          its centre line (u, v, radius) from the root; flat=True makes a paddle (the beaver)
Colours are sRGB hex; paint(p) picks one for each point of the fur (see build.py's Paint).
"""


def soft(x, a, b):
    """0 below a, 1 above b, smooth between (a > b runs the other way)."""
    if a == b:
        return 1.0 if x >= a else 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# --- rarity -----------------------------------------------------------------------------------------
# Scaled to how many of each live in the world (rough world population estimates, 2020s): sheep the most
# common by far (about 1.3 billion, farmed), then rabbits (hundreds of millions, wild and kept), red foxes
# and raccoons (tens of millions), beavers, coyotes and mink (millions), sables and lynx (Eurasian lynx
# in the tens of thousands), and wild chinchillas (critically endangered: a few thousand in the Andes).
RARITY = {"sheep": "common", "rabbit": "common", "fox": "rare", "raccoon": "rare", "beaver": "ultra_rare",
          "coyote": "ultra_rare", "mink": "ultra_rare", "sable": "legendary", "lynx": "legendary", "chinchilla": "mythic"}


def _rabbit(p):
    c = p.mix("#d49a63", "#e3b07a", p.n)  # fawn, lighter on top of each tuft
    c = p.over(c, "#c98a55", soft(p.v, 0.45, 0.62) * soft(p.u, 0.3, 0.5) * 0.5)  # a deeper back
    belly = max(p.part_is("chest") * soft(p.v, 0.42, 0.3), soft(p.v, 0.16, 0.08) * p.part_is("torso"),
                p.part_is("cheek") * soft(p.v, 0.5, 0.44), p.part_is("snout") * soft(p.v, 0.5, 0.46))
    c = p.over(c, "#f1dcb8", belly)
    c = p.over(c, "#f0d9b5", p.part_is("paw") * soft(p.v, 0.07, 0.03))
    c = p.over(c, "#f7f2ea", p.part_is("tail"))
    c = p.over(c, "#efa595", p.ear_in)  # inside the ears
    c = p.over(c, "#e3b07a", p.ear_rim)
    c = p.over(c, "#8a5a3c", p.brow)
    return c


def _fox(p):
    c = p.mix("#d8602a", "#e8793a", p.n)
    c = p.over(c, "#b84a1e", soft(p.v, 0.4, 0.5) * p.part_is("torso") * 0.6)
    cream = max(p.part_is("chest"), p.part_is("cheek") * soft(p.v, 0.64, 0.56), p.part_is("snout") * soft(p.v, 0.66, 0.6),
                p.part_is("torso") * soft(p.v, 0.22, 0.15) * soft(p.u, 0.62, 0.5))
    c = p.over(c, "#f4e3c6", cream)
    stocking = (p.part_is("leg_f") + p.part_is("leg_h") + p.part_is("paw")) * soft(p.v, 0.22, 0.17)
    c = p.over(c, "#4a2c22", min(1.0, stocking))
    c = p.over(c, "#f5ead8", p.part_is("tail") * soft(p.tail_s, 0.58, 0.72))  # the white tip
    c = p.over(c, "#3d2620", p.ear_out)
    c = p.over(c, "#e8968a", p.ear_in)
    c = p.over(c, "#f3e4cc", p.ear_tuft)
    c = p.over(c, "#7b3417", p.brow)
    return c


def _raccoon(p):
    c = p.mix("#8c735e", "#a88d74", p.n)
    c = p.over(c, "#6e5a4a", soft(p.v, 0.62, 0.78) * p.part_is("torso") * 0.7)
    cream = max(p.part_is("chest") * 0.85, p.part_is("cheek") * soft(p.v, 0.66, 0.6), p.part_is("snout"))
    c = p.over(c, "#e6cfac", cream)
    # the mask: a dark band through the eyes, sloping down toward the cheeks, cream above it
    mid = 0.735 - 0.3 * (p.u - 0.15)
    band = p.head_like * soft(abs(p.v - mid), 0.065, 0.04) * soft(p.u, 0.1, 0.14) * soft(p.u, 0.44, 0.38)
    above = p.head_like * soft(p.v - mid, 0.06, 0.085) * soft(p.v, 0.88, 0.85) * soft(p.u, 0.12, 0.16) * soft(p.u, 0.4, 0.34)
    c = p.over(c, "#ecdabb", above)
    c = p.over(c, "#3a302b", band)
    c = p.over(c, "#4a3b33", min(1.0, (p.part_is("leg_f") + p.part_is("leg_h") + p.part_is("paw")) * soft(p.v, 0.3, 0.22)))
    rings = 0.5 + 0.5 * __import__("math").cos(p.tail_s * 6.283 * 2.5)
    c = p.over(c, "#dcc6a2", p.part_is("tail") * soft(rings, 0.45, 0.6))
    c = p.over(c, "#453831", p.part_is("tail") * soft(rings, 0.45, 0.3))
    c = p.over(c, "#453831", p.part_is("tail") * soft(p.tail_s, 0.85, 0.95))
    c = p.over(c, "#3e322c", p.ear_in)
    c = p.over(c, "#efe0c4", p.ear_rim)
    return c


def _beaver(p):
    c = p.mix("#b0521f", "#c96a2e", p.n)
    c = p.over(c, "#8c3e17", soft(p.v, 0.7, 0.85) * p.part_is("torso") * 0.6)
    tan = max(p.part_is("chest") * soft(p.v, 0.55, 0.45), p.part_is("cheek") * soft(p.v, 0.72, 0.62) * soft(p.u, 0.32, 0.2),
              p.part_is("snout"))
    c = p.over(c, "#d9a46c", tan)
    c = p.over(c, "#5c3426", min(1.0, (p.part_is("leg_f") + p.part_is("leg_h") + p.part_is("paw")) * soft(p.v, 0.2, 0.14)))
    c = p.over(c, "#6b3a28", p.ear_in + p.ear_out)
    return c


def _coyote(p):
    c = p.mix("#b88a64", "#c99a70", p.n)
    c = p.over(c, "#8f7c72", soft(p.v, 0.55, 0.7) * min(1.0, p.part_is("torso") + p.part_is("neck")) * 0.85)  # grizzled saddle
    c = p.over(c, "#6f625c", soft(p.n, 0.55, 0.8) * soft(p.v, 0.6, 0.72) * p.part_is("torso") * 0.6)
    cream = max(p.part_is("chest") * 0.9, p.part_is("cheek") * soft(p.v, 0.74, 0.68), p.part_is("snout") * soft(p.v, 0.71, 0.67),
                p.part_is("torso") * soft(p.v, 0.45, 0.38))
    c = p.over(c, "#f0dcc0", cream)
    c = p.over(c, "#d6965c", min(1.0, p.part_is("leg_f") + p.part_is("leg_h") + p.part_is("paw")) * soft(p.v, 0.42, 0.3))
    c = p.over(c, "#efdcc0", p.part_is("paw") * 0.6)
    c = p.over(c, "#c47c46", p.part_is("snout") * soft(p.v, 0.69, 0.73))  # the tan bridge of the nose
    c = p.over(c, "#9a8478", p.part_is("tail") * 0.8)
    c = p.over(c, "#3a2c26", p.part_is("tail") * soft(p.tail_s, 0.66, 0.8))
    c = p.over(c, "#c98a52", p.ear_out)
    c = p.over(c, "#f2e2cc", p.ear_in)
    return c


def _mink(p):
    c = p.mix("#4a2618", "#5e3222", p.n)
    c = p.over(c, "#3b1d12", soft(p.v, 0.55, 0.72) * p.part_is("torso") * 0.5)
    c = p.over(c, "#3a1c12", min(1.0, p.part_is("tail") + (p.part_is("leg_f") + p.part_is("leg_h") + p.part_is("paw")) * 0.6))
    chin = max(p.part_is("snout") * soft(p.v, 0.73, 0.69), p.part_is("cheek") * soft(p.v, 0.71, 0.67))
    c = p.over(c, "#efe0cc", chin)
    c = p.over(c, "#c48a62", p.ear_in)
    c = p.over(c, "#6a3a26", p.ear_rim)
    return c


def _sable(p):
    c = p.mix("#a5622c", "#c27c3e", p.n)
    c = p.over(c, "#7a4524", soft(p.v, 0.6, 0.72) * p.part_is("torso") * 0.5)
    c = p.over(c, "#8a5530", p.head_like * 0.7)
    dark = min(1.0, p.part_is("tail") + (p.part_is("leg_f") + p.part_is("leg_h") + p.part_is("paw")) * soft(p.v, 0.4, 0.28))
    c = p.over(c, "#5a3020", dark)
    throat = max(p.part_is("chest"), p.part_is("neck") * soft(p.v, 0.66, 0.58), p.part_is("cheek") * soft(p.v, 0.7, 0.64))
    c = p.over(c, "#f0c27a", throat)
    c = p.over(c, "#f2dcc0", p.ear_rim)
    c = p.over(c, "#d9a77a", p.ear_in)
    return c


def _lynx(p):
    c = p.mix("#c49a72", "#d8b48e", p.n)
    cream = max(p.part_is("chest"), p.part_is("cheek"), p.part_is("snout") * soft(p.v, 0.74, 0.7),
                p.part_is("torso") * soft(p.v, 0.46, 0.4), p.part_is("paw") * 0.7)
    c = p.over(c, "#eadac0", cream * 0.8)  # a warm cream ruff, not white
    c = p.over(c, "#6a4a38", p.spot * (1.0 - p.head_like) * (1.0 - p.part_is("chest")) * (1.0 - p.part_is("tail")) * 0.85)
    c = p.over(c, "#1e1a18", p.part_is("tail") * soft(p.tail_s, 0.45, 0.6))
    c = p.over(c, "#7a5a44", p.ear_out)
    c = p.over(c, "#f0e2cc", p.ear_in)
    c = p.over(c, "#1e1a18", soft(p.ear_s, 0.7, 0.82))  # the tufts
    return c


def _chinchilla(p):
    c = p.mix("#8f95a7", "#aab0c0", p.n)  # blue-grey, lighter on top of each tuft
    c = p.over(c, "#7d8395", soft(p.v, 0.4, 0.58) * p.part_is("torso") * 0.55)  # a deeper back
    cream = max(p.part_is("chest") * soft(p.v, 0.5, 0.38), p.part_is("cheek") * soft(p.v, 0.6, 0.52),
                p.part_is("snout") * soft(p.v, 0.6, 0.54), p.part_is("torso") * soft(p.v, 0.2, 0.1) * soft(p.u, 0.7, 0.55))
    c = p.over(c, "#f2ede4", cream)
    c = p.over(c, "#e8b6ae", p.part_is("paw") * soft(p.v, 0.08, 0.04))  # pink feet
    tail = p.part_is("tail")
    c = p.over(c, "#9ba1b2", tail * soft(p.tail_s, 0.0, 0.25))
    c = p.over(c, "#6b7082", tail * soft(p.tail_s, 0.35, 0.85) * 0.85)  # the plume darkens to its tip
    c = p.over(c, "#868b9c", p.ear_out)
    c = p.over(c, "#efa49c", p.ear_in)
    c = p.over(c, "#f3ece2", p.ear_tuft)
    c = p.over(c, "#5c6070", p.brow)
    return c


SPECIES = {
    "rabbit": dict(
        name="Rabbit", unit=0.42, fur="#d49a63",
        shoulder=(0.22, 0.25), hip=(0.58, 0.28), leg_x=(0.075, 0.09),
        fore=[(0.22, 0.25, 0.06), (0.22, 0.14, 0.048), (0.17, 0.05, 0.042), (0.1, 0.025, 0.042)],
        hind=[(0.58, 0.28, 0.1), (0.5, 0.17, 0.09), (0.62, 0.06, 0.055), (0.46, 0.03, 0.05)],
        torso=[(0.27, 0.3, 0.13, 0.13, 0.15), (0.42, 0.29, 0.15, 0.15, 0.18), (0.6, 0.27, 0.16, 0.13, 0.2)],
        extra=[("chest", (0.18, 0.26, 0.12, 0.1, 0.13)), ("cheek", (0.15, 0.47, 0.13, 0.08, 0.075))],
        neck=(0.25, 0.41, 0.1, 0.09, 0.1), head=(0.19, 0.535, 0.14, 0.15, 0.15),
        snout=(0.06, 0.49, 0.06, 0.06, 0.05), nose=(0.008, 0.5, 0.016, "#e98d8a"),
        eye=(0.12, 0.555, 0.098, 0.042, "#4a2614"), brow=None,
        ears=dict(kind="long", base=(0.29, 0.655, 0.06), length=0.37, width=0.2, tilt=16, splay=14, turn=55),
        tail=[(0.74, 0.35, 0.08)], tail_ball=True,
        fluff=0.012, paint=_rabbit, gait="hop",
    ),
    "fox": dict(
        name="Red fox", unit=0.68, fur="#d8602a",
        shoulder=(0.3, 0.34), hip=(0.6, 0.34), leg_x=(0.08, 0.085),
        fore=[(0.3, 0.34, 0.09), (0.29, 0.19, 0.08), (0.27, 0.07, 0.075), (0.2, 0.035, 0.065)],
        hind=[(0.6, 0.34, 0.11), (0.57, 0.2, 0.09), (0.67, 0.08, 0.07), (0.56, 0.035, 0.065)],
        torso=[(0.33, 0.37, 0.13, 0.12, 0.15), (0.46, 0.365, 0.13, 0.12, 0.165), (0.59, 0.35, 0.13, 0.12, 0.15)],
        extra=[("chest", (0.2, 0.36, 0.14, 0.12, 0.15)), ("cheek", (0.22, 0.55, 0.2, 0.12, 0.09)),
               ("neck", (0.4, 0.6, 0.13, 0.08, 0.12)), ("head", (0.2, 0.76, 0.1, 0.1, 0.06))],
        neck=(0.33, 0.5, 0.11, 0.1, 0.11), head=(0.25, 0.645, 0.21, 0.19, 0.16),
        snout=(0.075, 0.578, 0.065, 0.075, 0.055), nose=(0.004, 0.6, 0.024, "#2a1d1a"),
        eye=(0.155, 0.665, 0.085, 0.05, "#7a3d14"), brow=None,
        ears=dict(kind="pointy", base=(0.35, 0.74, 0.12), length=0.27, width=0.24, tilt=6, splay=12, turn=30),
        tail=[(0.68, 0.34, 0.08), (0.78, 0.42, 0.15), (0.81, 0.56, 0.18), (0.8, 0.7, 0.15), (0.84, 0.8, 0.09)],
        fluff=0.014, paint=_fox, gait="dog",
    ),
    "raccoon": dict(
        name="Raccoon", unit=0.42, fur="#8c735e",
        shoulder=(0.45, 0.45), hip=(0.98, 0.45), leg_x=(0.11, 0.12),
        fore=[(0.45, 0.45, 0.1), (0.45, 0.25, 0.08), (0.43, 0.07, 0.07), (0.35, 0.03, 0.06)],
        hind=[(0.98, 0.45, 0.13), (0.92, 0.27, 0.09), (0.97, 0.08, 0.07), (0.86, 0.03, 0.06)],
        torso=[(0.5, 0.53, 0.2, 0.2, 0.28), (0.78, 0.54, 0.22, 0.22, 0.29), (1.02, 0.51, 0.21, 0.2, 0.27)],
        extra=[("chest", (0.38, 0.42, 0.17, 0.12, 0.2)), ("cheek", (0.3, 0.6, 0.2, 0.12, 0.09))],
        neck=(0.45, 0.66, 0.16, 0.13, 0.15), head=(0.28, 0.69, 0.19, 0.2, 0.19),
        snout=(0.08, 0.635, 0.07, 0.08, 0.06), nose=(0.012, 0.645, 0.028, "#2b2220"),
        eye=(0.2, 0.72, 0.11, 0.032, "#3a2414"), brow=None,
        ears=dict(kind="round", base=(0.3, 0.86, 0.12), length=0.15, width=0.15, tilt=5, splay=18, turn=25),
        tail=[(1.16, 0.56, 0.1), (1.27, 0.46, 0.15), (1.36, 0.33, 0.15), (1.4, 0.2, 0.12)],
        fluff=0.014, paint=_raccoon, gait="dog",
    ),
    "beaver": dict(
        name="Beaver", unit=0.38, fur="#b0521f",
        shoulder=(0.42, 0.42), hip=(1.05, 0.42), leg_x=(0.15, 0.17),
        fore=[(0.42, 0.42, 0.1), (0.42, 0.22, 0.075), (0.4, 0.07, 0.06), (0.3, 0.025, 0.05)],
        hind=[(1.05, 0.42, 0.14), (0.98, 0.25, 0.11), (1.12, 0.07, 0.07), (0.88, 0.025, 0.06)],
        torso=[(0.55, 0.56, 0.27, 0.25, 0.33), (0.88, 0.56, 0.3, 0.28, 0.37), (1.15, 0.5, 0.26, 0.24, 0.32)],
        extra=[("chest", (0.35, 0.45, 0.2, 0.14, 0.22)), ("cheek", (0.2, 0.7, 0.2, 0.12, 0.1))],
        neck=(0.45, 0.68, 0.2, 0.14, 0.2), head=(0.3, 0.76, 0.22, 0.23, 0.2),
        snout=(0.1, 0.73, 0.1, 0.1, 0.1), nose=(0.03, 0.81, 0.04, "#4a2a22"),
        eye=(0.27, 0.84, 0.15, 0.035, "#4a2210"), brow=None, teeth=(0.075, 0.6, 0.045, 0.09, "#f0a030"),
        ears=dict(kind="round", base=(0.52, 0.88, 0.17), length=0.07, width=0.08, tilt=0, splay=30, turn=30),
        tail=[(1.25, 0.2, 0.17), (1.42, 0.12, 0.17), (1.6, 0.05, 0.13)], flat_tail=True, tail_color="#5e3a2c",
        fluff=0.012, paint=_beaver, gait="waddle",
    ),
    "coyote": dict(
        name="Coyote", unit=0.76, fur="#b88a64",
        shoulder=(0.42, 0.52), hip=(0.84, 0.52), leg_x=(0.07, 0.075),
        fore=[(0.42, 0.52, 0.065), (0.45, 0.33, 0.045), (0.42, 0.08, 0.035), (0.34, 0.025, 0.035)],
        hind=[(0.84, 0.52, 0.09), (0.79, 0.33, 0.06), (0.93, 0.12, 0.04), (0.84, 0.025, 0.035)],
        torso=[(0.44, 0.57, 0.12, 0.13, 0.18), (0.63, 0.57, 0.12, 0.14, 0.18), (0.84, 0.55, 0.12, 0.14, 0.17)],
        extra=[("chest", (0.32, 0.52, 0.12, 0.11, 0.15)), ("neck", (0.33, 0.66, 0.12, 0.1, 0.12)),
               ("cheek", (0.27, 0.71, 0.12, 0.08, 0.07))],
        neck=(0.36, 0.66, 0.1, 0.1, 0.12), head=(0.25, 0.77, 0.12, 0.13, 0.12),
        snout=(0.09, 0.69, 0.05, 0.09, 0.05), nose=(0.004, 0.705, 0.02, "#2a1f1c"),
        eye=(0.175, 0.78, 0.07, 0.026, "#6a3c14"), brow=None,
        ears=dict(kind="pointy", base=(0.27, 0.86, 0.075), length=0.2, width=0.14, tilt=4, splay=10, turn=25),
        tail=[(0.97, 0.6, 0.06), (1.04, 0.47, 0.08), (1.08, 0.32, 0.09), (1.1, 0.18, 0.08), (1.09, 0.08, 0.04)],
        fluff=0.012, paint=_coyote, gait="dog", gaze=1.0,
    ),
    "mink": dict(
        name="Mink", unit=0.3, fur="#4a2618",
        shoulder=(0.53, 0.42), hip=(1.18, 0.42), leg_x=(0.09, 0.1),
        fore=[(0.53, 0.42, 0.1), (0.54, 0.22, 0.08), (0.52, 0.07, 0.065), (0.43, 0.025, 0.055)],
        hind=[(1.18, 0.42, 0.13), (1.12, 0.25, 0.1), (1.22, 0.08, 0.07), (1.1, 0.025, 0.055)],
        torso=[(0.55, 0.45, 0.14, 0.16, 0.24), (0.8, 0.49, 0.15, 0.18, 0.27), (1.05, 0.51, 0.16, 0.18, 0.28),
               (1.22, 0.47, 0.15, 0.14, 0.24)],
        extra=[("chest", (0.42, 0.45, 0.12, 0.1, 0.18)), ("cheek", (0.22, 0.72, 0.11, 0.08, 0.06)),
               ("neck", (0.36, 0.78, 0.13, 0.1, 0.12))],
        neck=(0.43, 0.68, 0.15, 0.14, 0.2), head=(0.28, 0.82, 0.15, 0.2, 0.16),
        snout=(0.08, 0.75, 0.06, 0.08, 0.06), nose=(0.008, 0.775, 0.026, "#2a1a14"),
        eye=(0.22, 0.83, 0.1, 0.03, "#2a1408"), brow=None, liner="#1e0e08",
        ears=dict(kind="round", base=(0.4, 0.92, 0.1), length=0.09, width=0.11, tilt=5, splay=20, turn=25),
        tail=[(1.3, 0.5, 0.09), (1.42, 0.45, 0.12), (1.58, 0.36, 0.14), (1.75, 0.25, 0.14), (1.95, 0.15, 0.08)],
        fluff=0.01, paint=_mink, gait="bound", gaze=1.2,
    ),
    "sable": dict(
        name="Sable", unit=0.34, fur="#a5622c",
        shoulder=(0.46, 0.42), hip=(1.0, 0.42), leg_x=(0.09, 0.1),
        fore=[(0.46, 0.42, 0.09), (0.48, 0.22, 0.07), (0.47, 0.07, 0.06), (0.39, 0.025, 0.05)],
        hind=[(1.0, 0.42, 0.11), (0.95, 0.25, 0.085), (1.05, 0.08, 0.06), (0.97, 0.025, 0.05)],
        torso=[(0.5, 0.49, 0.13, 0.15, 0.21), (0.75, 0.52, 0.14, 0.17, 0.22), (0.98, 0.5, 0.14, 0.17, 0.21)],
        extra=[("chest", (0.33, 0.48, 0.13, 0.12, 0.15)), ("cheek", (0.24, 0.7, 0.12, 0.09, 0.06))],
        neck=(0.42, 0.63, 0.13, 0.12, 0.17), head=(0.29, 0.79, 0.15, 0.19, 0.16),
        snout=(0.08, 0.73, 0.055, 0.08, 0.055), nose=(0.006, 0.745, 0.025, "#2a1a14"),
        eye=(0.18, 0.79, 0.095, 0.03, "#3a1e0c"), brow=None,
        ears=dict(kind="round", base=(0.32, 0.88, 0.1), length=0.15, width=0.14, tilt=5, splay=18, turn=25),
        tail=[(1.1, 0.5, 0.08), (1.2, 0.42, 0.11), (1.35, 0.3, 0.14), (1.5, 0.2, 0.13), (1.58, 0.13, 0.07)],
        fluff=0.012, paint=_sable, gait="bound", gaze=1.2,
    ),
    "lynx": dict(
        name="Lynx", unit=0.9, fur="#c49a72", spots=0.05,
        shoulder=(0.25, 0.45), hip=(0.64, 0.45), leg_x=(0.08, 0.085),
        fore=[(0.25, 0.45, 0.08), (0.25, 0.28, 0.07), (0.22, 0.08, 0.065), (0.17, 0.04, 0.075)],
        hind=[(0.64, 0.45, 0.1), (0.6, 0.3, 0.08), (0.68, 0.1, 0.065), (0.62, 0.04, 0.075)],
        torso=[(0.25, 0.5, 0.12, 0.12, 0.16), (0.42, 0.53, 0.12, 0.14, 0.15), (0.6, 0.53, 0.12, 0.13, 0.15)],
        extra=[("chest", (0.16, 0.5, 0.13, 0.1, 0.15)), ("cheek", (0.17, 0.66, 0.15, 0.1, 0.1))],
        neck=(0.24, 0.64, 0.11, 0.1, 0.12), head=(0.17, 0.775, 0.13, 0.13, 0.12),
        snout=(0.055, 0.72, 0.06, 0.05, 0.05), nose=(0.004, 0.735, 0.02, "#c47862"),
        eye=(0.1, 0.79, 0.075, 0.026, "#c8861e"), brow=None,
        ears=dict(kind="pointy", base=(0.2, 0.86, 0.075), length=0.18, width=0.17, tilt=2, splay=8, turn=4),
        tail=[(0.67, 0.6, 0.05), (0.73, 0.62, 0.07), (0.78, 0.62, 0.05)],
        fluff=0.014, paint=_lynx, gait="dog", gaze=1.4,
    ),
    "chinchilla": dict(
        name="Wild chinchilla", unit=0.32, fur="#9aa0b2",
        shoulder=(0.3, 0.26), hip=(0.62, 0.28), leg_x=(0.1, 0.12),
        fore=[(0.3, 0.26, 0.07), (0.29, 0.15, 0.055), (0.28, 0.05, 0.045), (0.21, 0.028, 0.045)],
        hind=[(0.62, 0.28, 0.11), (0.56, 0.17, 0.1), (0.7, 0.06, 0.06), (0.52, 0.035, 0.055)],
        torso=[(0.38, 0.3, 0.2, 0.17, 0.26), (0.57, 0.28, 0.22, 0.18, 0.27), (0.74, 0.25, 0.2, 0.14, 0.23)],
        extra=[("chest", (0.26, 0.3, 0.17, 0.12, 0.2)), ("cheek", (0.15, 0.53, 0.14, 0.09, 0.08))],
        neck=(0.33, 0.48, 0.16, 0.12, 0.13), head=(0.24, 0.63, 0.17, 0.19, 0.17),
        snout=(0.07, 0.56, 0.07, 0.07, 0.06), nose=(0.008, 0.575, 0.02, "#d8949a"),
        eye=(0.19, 0.635, 0.12, 0.05, "#5a3218"), brow=None, liner="#2e2420",
        ears=dict(kind="long", base=(0.36, 0.76, 0.1), length=0.3, width=0.3, tilt=10, splay=16, turn=70),
        tail=[(0.86, 0.22, 0.08), (0.96, 0.4, 0.15), (0.99, 0.6, 0.19), (0.96, 0.78, 0.19), (0.88, 0.9, 0.12)],
        fluff=0.016, paint=_chinchilla, gait="hop", gaze=1.3,
    ),
}
