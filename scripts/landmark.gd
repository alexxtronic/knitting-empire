extends Node3D
## A clickable thing in the world that isn't furniture: signposts, the for-sale sign.

var kind := ""
var title := ""


func display_name() -> String:
	return title
