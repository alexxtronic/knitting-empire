"""Joint positions and placements shared by the CH_Rowan phase scripts (metres, his left = +X)."""
import math
import numpy as np
from common import norm

HEIGHT = 1.80                                          # top of the hair

# arms: sleeve axis traced on ref/front.png (centre 0.2025 at z 1.225, 0.2625 at z 1.082, wrist 0.313 at z 0.936)
SHOULDER = np.array([0.150, 0.0, 1.385])
UPPER_DIR = norm(np.array([0.358, -0.070, -0.934]))   # 21 degrees out, a little forward
UPPER_LEN = 0.260
FORE_DIR = norm(np.array([0.330, -0.150, -0.930]))
FORE_LEN = 0.222
ELBOW = SHOULDER + UPPER_DIR * UPPER_LEN
WRIST = ELBOW + FORE_DIR * FORE_LEN                    # (0.316, -0.051, 0.936)
HAND_DIR = norm(np.array([0.220, -0.090, -0.970]))    # front view: hand 0.936 down to 0.750

# feet and boots: ankle centre (front view 92%: 0.138; side view heel at +0.110), toes turned out
BOOT_X, BOOT_Y, BOOT_YAW = 0.131, 0.020, 7.0
SOLE_T = 0.028                                         # boot sole; the bare foot stands on top of it

# neck: the head and the body meet on this ring (same vertices on both objects)
NECK_Z, NECK_R, NECK_Y = 1.500, 0.0605, -0.012

# head
EYE = np.array([0.0387, -0.086, 1.657])               # his left eyeball centre: front view pupils 0.077 apart
EYE_R = 0.0255
JAW_PIVOT = np.array([0.0, 0.012, 1.628])             # jaw hinge, just in front of the ear (side view)


def boot_world(P, side):
    """Boot space (x across, y toward the toe, z up) to world for his left (side=+1) or right foot."""
    P = np.asarray(P, dtype=float)
    yaw = math.radians(BOOT_YAW)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    wx = x * math.cos(yaw) + y * math.sin(yaw)
    wy = -(y * math.cos(yaw) - x * math.sin(yaw))
    out = np.stack([BOOT_X + wx, BOOT_Y + wy, z], axis=-1)
    if side < 0:
        out[..., 0] *= -1
    return out
