extends Node3D
## Someone sitting and reading (Alex, 2026-11-16: how people held books "looks so terrible": a closed
## book lay on one thigh while their hands rested on their knees). Now they hold an open book up in
## both hands in front of their chest, tipped toward their face, and look down into it.
##
## ReadingPose.attach(who) puts the book on a seated character (Nora or a villager) and returns it;
## ReadingPose.detach(who) takes it away. The book is a child of the character named "ReadingBook",
## built from Catalog boxes: two blocks of pages in a shallow V on a cover. It is placed from the
## character's own bones (between the hips and the neck, a forearm in front), so a tall Giorgio and a
## small Barbara both hold it where their hands can reach. Each hand is brought to the outer edge of
## its page by WardrobeView.ReachIK (two-bone IK on the upper and lower arm), and main._gaze_for()
## turns the head to look_point() while it is there.

const WardrobeView = preload("res://scripts/wardrobe_view.gd")
const Catalog = preload("res://scripts/catalog.gd")

const NODE := "ReadingBook"
const COVERS := {"plum": Color(0.42, 0.2, 0.36), "forest": Color(0.19, 0.33, 0.22), "wine": Color(0.48, 0.13, 0.16),
	"navy": Color(0.15, 0.2, 0.36), "mustard": Color(0.72, 0.55, 0.18)}
const PAGE := Vector2(0.13, 0.19) # one page, across and up
const SPREAD := 0.2 # the pages rise from the spine to their outer edges (radians)
const UP := 0.36 # the book's centre, from the hips toward the neck
const OUT := 0.3 # and in front of the body (metres)
const HOLD := Vector3(0.12, 0.0, -0.035) # where each palm holds it, in the book's own space
const TILT := 0.75 # 1 faces the eyes square on, 0 lies flat

var who: Node3D
var body = null # the character's Body (null for one drawn as plain shapes)
var reach: Array = [] # the two ReachIK arms
var _w := 0.0
var _placed := false


## Hands the character an open book. `cover` is one of COVERS (random if empty).
static func attach(person: Node3D, cover := "") -> Node3D:
	detach(person)
	var b = load("res://scripts/reading_pose.gd").new()
	b.name = NODE
	b.who = person
	b.body = person.get("body")
	person.add_child(b)
	b._build(COVERS.get(cover, COVERS.values()[randi() % COVERS.size()]))
	b._place()
	if b.body != null and b.body.skeleton != null:
		for side in [1, -1]:
			var ik := WardrobeView.ReachIK.new()
			ik.body = person
			ik.side = side
			b.body.skeleton.add_child(ik) # last, so it runs after the loop and the look-at
			b.reach.append(ik)
	return b


static func detach(person: Node3D) -> void:
	var b = person.get_node_or_null(NODE)
	if b == null:
		return
	for ik in b.reach:
		if is_instance_valid(ik):
			ik.queue_free()
	b.reach.clear()
	person.remove_child(b)
	b.queue_free()


static func holding(person: Node3D) -> Node3D:
	return person.get_node_or_null(NODE)


## Where the reader's eyes go: the middle of the pages.
func look_point() -> Vector3:
	return global_transform * Vector3(0, 0.01, 0.02)


## The palm's spot for her right hand (side 1) or left (-1), in the world.
func hand_point(side: int) -> Vector3:
	# her right is -x of the character (and of the book, which faces her)
	return global_transform * Vector3(-HOLD.x * float(side), HOLD.y, HOLD.z)


func _build(cover: Color) -> void:
	var paper := Color(0.95, 0.92, 0.84)
	for s in [-1.0, 1.0]:
		var leaf := Node3D.new()
		add_child(leaf)
		leaf.rotation.z = SPREAD * s # outer edges up from the spine
		Catalog.box(leaf, Vector3(PAGE.x + 0.008, 0.006, PAGE.y + 0.012), Vector3(s * (PAGE.x * 0.5 + 0.004), -0.004, 0), cover)
		Catalog.box(leaf, Vector3(PAGE.x, 0.016, PAGE.y), Vector3(s * PAGE.x * 0.5, 0.008, 0), paper)
		# a few lines of print, so it reads as a page from across the room
		for i in 7:
			var z := -PAGE.y * 0.36 + i * PAGE.y * 0.12
			Catalog.box(leaf, Vector3(PAGE.x * 0.66, 0.002, 0.008), Vector3(s * PAGE.x * 0.52, 0.0165, z), Color(0.55, 0.52, 0.48))
	Catalog.box(self, Vector3(0.012, 0.012, PAGE.y + 0.012), Vector3(0, -0.006, 0), cover.darkened(0.25)) # the spine


## In front of the chest, from the character's own bones as the seated loop poses them (read every
## frame: at attach() they may still stand as they walked up), its pages turned toward the eyes.
func _place(smooth := 1.0) -> void:
	var inv := who.global_transform.affine_inverse()
	var hips := Vector3(0, 0.12, 0)
	var neck := Vector3(0, 0.62, 0.02)
	var eyes := Vector3(0, 0.78, 0.08)
	if body != null and body.skeleton != null:
		var sk: Skeleton3D = body.skeleton
		var got := func(n: String, d: Vector3) -> Vector3:
			var i := sk.find_bone(n)
			return inv * (sk.global_transform * sk.get_bone_global_pose(i).origin) if i >= 0 else d
		hips = got.call("Hips", hips)
		neck = got.call("Neck", neck)
		eyes = got.call("Head", eyes) + Vector3(0, 0.06, 0.06)
	var c := Vector3(0, hips.y + (neck.y - hips.y) * UP, maxf(hips.z, neck.z) + OUT)
	var face := (eyes - c).normalized()
	var n := Vector3.UP.lerp(face, TILT).normalized() # the pages' normal
	var x := Vector3.RIGHT - n * n.dot(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(n).normalized() # up the page, away from her
	if z.dot(Vector3.BACK) < 0.0: # the character faces +z: the page's top is the far edge
		z = -z
		x = -x
	var b := Basis(x, n, z).orthonormalized()
	if not _placed:
		position = c
		basis = b
		_placed = true
	else: # follow the seated loop's breathing and sway, smoothly
		position = position.lerp(c, smooth)
		basis = basis.slerp(b, smooth).orthonormalized()


func _process(delta: float) -> void:
	_place(clampf(delta * 8.0, 0.0, 1.0))
	_w = move_toward(_w, 1.0, delta * 2.5)
	for ik in reach:
		if is_instance_valid(ik):
			ik.target = hand_point(ik.side)
			ik.weight = _w
