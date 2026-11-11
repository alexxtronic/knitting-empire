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

# 3. lit renders: turnaround at the reference's five angles, head, face test (mouth open, eyes turned),
#    the body without the outfit, and wireframes; then the three review sheets
OUT="CH_Rowan_Sweater,CH_Rowan_Jeans,CH_Rowan_Belt,CH_Rowan_Boot_L,CH_Rowan_Boot_R"
L="$B --background --python review/look.py -- --blend $M"
$L --out review/beauty --name turn --views 0,315,90,135,180 --res 900 --aspect 0.46 --lit --samples 36 2>&1 | grep -E "Traceback|Error:" || true
$L --out review/beauty --name head --z 1.44 1.83 --views 0,40,90 --res 760 --aspect 0.85 --lit --samples 40 2>&1 | grep -E "Traceback|Error:" || true
$L --out review/face --name open --z 1.44 1.83 --views 0,40 --res 760 --aspect 0.85 --lit --samples 40 --pose jaw=16,eyes=22:0 2>&1 | grep -E "Traceback|Error:" || true
$L --out review/nude --name lit --views 0,315,90,180 --res 800 --aspect 0.46 --lit --samples 28 --hide $OUT 2>&1 | grep -E "Traceback|Error:" || true
$L --out review/wire --name wire --views 0,90 --res 900 --aspect 0.46 --clay --wire --hide $OUT,CH_Rowan_Hair,CH_Rowan_Beard 2>&1 | grep -E "Traceback|Error:" || true
$L --out review/wire --name headwire --z 1.46 1.80 --views 0,60 --res 900 --aspect 0.8 --clay --wire --only CH_Rowan_Head 2>&1 | grep -E "Traceback|Error:" || true
$PY review/sheets.py
