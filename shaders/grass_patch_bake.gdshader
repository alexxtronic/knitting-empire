// Bakes the grass's light and dark patches (grass_patches.gdshaderinc) into a texture over grass.gd's
// REGION once, so each blade reads its patch with one lookup instead of sixteen hashes per vertex.
// R is the broad drift and G the clumps, each -1..1 stored as 0..1.
shader_type canvas_item;

uniform vec4 rect; // x, z, width, depth in metres

#include "res://shaders/grass_patches.gdshaderinc"

void fragment() {
	vec2 k = grass_patches(rect.xy + UV * rect.zw);
	COLOR = vec4(k * 0.5 + 0.5, 0.0, 1.0);
}
