#!/bin/bash
# Review gates for CH_Rowan: silhouette compare against the reference panels, mesh validation,
# the face articulation test and the bare-body check. Run from art/characters/CH_Rowan.
set -e
B=${BLENDER_BIN:-/Applications/Blender.app/Contents/MacOS/Blender}
SK=../../../.claude/skills/blender-image-to-3d
M=CH_Rowan_master.blend
PY="uv run --no-project --with pillow python"

# 1. silhouettes from the fixed views (Workbench), compared with the reference panels
$B --background --python $SK/scripts/review_render.py -- --blend $M --out review/gate --collections LOW \
   --views front,side,back --mode silhouette --res 1024 2>&1 | grep -E "^rendered|Error" || true
for v in front:front side:side back:back; do
  r=${v%%:*}; f=${v##*:}
  $PY $SK/scripts/compose_review.py --ref ref/$f.png --render review/gate/silhouette_$r.png \
      --out review/gate/compare_$f.png --measure --gameplay-px 128 2>&1 | tail -3
done

# 2. validation (topology, transforms, UVs, naming, triangle count)
$B --background --python $SK/scripts/validate.py -- --blend $M --collections LOW \
   --out review/gate/validate.json --budget-tris 60000 --require-uv 2>&1 | grep -E "FAIL|WARN|PASS|tris|total" | head -40 || true

# 3. face: mouth open and eyes turned; 4. the body without the outfit
OUT="CH_Rowan_Sweater,CH_Rowan_Jeans,CH_Rowan_Belt,CH_Rowan_Boot_L,CH_Rowan_Boot_R"
$B --background --python review/look.py -- --blend $M --out review/face --name open --z 1.46 1.83 --views 0,40 \
   --res 720 --aspect 0.85 --pose jaw=17,eyes=24:0 2>&1 | grep -E "LOOK|Error" || true
$B --background --python review/look.py -- --blend $M --out review/face --name rest --z 1.46 1.83 --views 0,40 \
   --res 720 --aspect 0.85 2>&1 | grep -E "LOOK|Error" || true
$B --background --python review/look.py -- --blend $M --out review/nude --name body --views 0,45,90,180 \
   --res 800 --aspect 0.46 --hide $OUT 2>&1 | grep -E "LOOK|Error" || true
