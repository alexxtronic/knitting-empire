"""Export audit of a GLB, without Blender: what the game will be given.

    python3 art/world_assets/lantern/audit.py [assets/props/lantern.glb]

Prints the node (name, transform), triangles per material, the bounding box in glTF's axes (Y up, the
front toward +Z), each material's maps, emission and alpha mode, the images' sizes, and the extensions
used. Exits 1 if the mesh is Draco- or meshopt-compressed, if a material that should glow has no
emission, or if the triangle count is over 12,000.
"""
import json
import struct
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "assets/props/lantern.glb"
with open(path, "rb") as f:
    magic, version, length = struct.unpack("<4sII", f.read(12))
    clen, ctype = struct.unpack("<I4s", f.read(8))
    doc = json.loads(f.read(clen))
    blen, btype = struct.unpack("<I4s", f.read(8))
    blob = f.read(blen)
bad = []
print("file:", path, "%.2f MB" % (length / 1e6), "glTF", version)
used = doc.get("extensionsUsed", [])
print("extensions used:", used or "none", "| required:", doc.get("extensionsRequired", []) or "none")
for e in used:
    if "draco" in e.lower() or "meshopt" in e.lower():
        bad.append("compressed with " + e)
for n in doc["nodes"]:
    print("node:", n.get("name"), "mesh" in n and "mesh %d" % n["mesh"] or "", "translation", n.get("translation", [0, 0, 0]),
          "rotation", n.get("rotation", [0, 0, 0, 1]), "scale", n.get("scale", [1, 1, 1]))
total = 0
lo, hi = [1e9] * 3, [-1e9] * 3
for m in doc["meshes"]:
    for p in m["primitives"]:
        tris = doc["accessors"][p["indices"]]["count"] // 3
        pos = doc["accessors"][p["attributes"]["POSITION"]]
        lo = [min(a, b) for a, b in zip(lo, pos["min"])]
        hi = [max(a, b) for a, b in zip(hi, pos["max"])]
        total += tris
        print("mesh %s primitive: material %s, %d triangles, %d vertices, attributes %s" % (
            m["name"], doc["materials"][p["material"]]["name"], tris, pos["count"], sorted(p["attributes"])))
print("triangles:", total)
print("bounding box (glTF: x right, y up, z toward the front): min", [round(v, 4) for v in lo], "max", [round(v, 4) for v in hi],
      "size", [round(b - a, 4) for a, b in zip(lo, hi)])
if total > 12000:
    bad.append("%d triangles" % total)


def tex(t):
    if t is None:
        return "-"
    img = doc["images"][doc["textures"][t["index"]]["source"]]
    return img.get("name", "?")


for m in doc["materials"]:
    pbr = m.get("pbrMetallicRoughness", {})
    print("material %s: alphaMode %s, doubleSided %s" % (m["name"], m.get("alphaMode", "OPAQUE"), m.get("doubleSided", False)))
    print("   base colour %s factor %s | metallic-roughness %s (metallic %s, roughness %s) | normal %s" % (
        tex(pbr.get("baseColorTexture")), pbr.get("baseColorFactor", [1, 1, 1, 1]), tex(pbr.get("metallicRoughnessTexture")),
        pbr.get("metallicFactor", 1), pbr.get("roughnessFactor", 1), tex(m.get("normalTexture"))))
    print("   emission %s factor %s %s" % (tex(m.get("emissiveTexture")), m.get("emissiveFactor", [0, 0, 0]),
                                           m.get("extensions", {}) or ""))
    if m.get("emissiveTexture") is None or max(m.get("emissiveFactor", [0, 0, 0])) <= 0:
        bad.append(m["name"] + " has no emission")
for i in doc.get("images", []):
    bv = doc["bufferViews"][i["bufferView"]]
    data = blob[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
    w, h = struct.unpack(">II", data[16:24]) if data[:8] == b"\x89PNG\r\n\x1a\n" else (0, 0)
    print("image %s: %s, %d x %d, %.0f kB, colour type %s" % (i.get("name"), i.get("mimeType"), w, h, bv["byteLength"] / 1e3,
                                                             {2: "RGB", 6: "RGBA", 0: "grey"}.get(data[25], data[25])))
print("AUDIT", "FAIL: " + "; ".join(bad) if bad else "PASS")
sys.exit(1 if bad else 0)
