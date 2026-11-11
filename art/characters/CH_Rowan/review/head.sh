#!/bin/bash
# Rebuild the head-side phases and render the lit head beside the reference. Args: phases to run.
B=/Applications/Blender.app/Contents/MacOS/Blender
for s in "$@"; do $B --background --python build/$s.py -- --master CH_Rowan_master.blend 2>&1 | grep -E "Traceback|line [0-9]|rror|\[05" | grep -v "Not freed" | tail -5; done
$B --background --python review/look.py -- --blend CH_Rowan_master.blend --out review/beauty --name head --z 1.44 1.83 --views 0,90 --res 760 --aspect 0.85 --lit --samples 36 2>&1 | grep -E "Traceback|line [0-9]" | tail -5
uv run --no-project --with pillow python review/cmp_head.py
