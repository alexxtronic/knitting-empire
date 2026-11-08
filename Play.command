#!/bin/bash
# Double-click to play. Needs Godot 4.7+ installed in /Applications.
DIR="$(cd "$(dirname "$0")" && pwd)"
open -n -a /Applications/Godot.app --args --path "$DIR"
