#!/bin/bash
# Double-click to play. Needs Godot 4.7+ installed in /Applications.
# First imports any model or texture that changed since the last import: running the game alone
# never does, so a rebuilt model (the Bretton Oaks house's garage, 2026-11-24) kept its old look.
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Importing changed models and textures..."
/Applications/Godot.app/Contents/MacOS/Godot --headless --path "$DIR" --import > /tmp/knitting_empire_import.log 2>&1
open -n -a /Applications/Godot.app --args --path "$DIR"
