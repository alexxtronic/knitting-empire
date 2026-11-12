# barn — build log

The farm barn, copied from Alex's reference render, with a working barn interior. Built by script
(`build.py`) with the method used for the park bench and the trash can: details read from the
reference, built headless in Blender, renders compared with the reference, sent to Alex for review
before it goes in the game.

## Brief

"Make this barn. Make sure the interior is also like a barn interior, as we'll be able to enter the barn
and store our pets in there." The barn only: no path, plants, barrel or hay bales outside (hay bales and
barrels are separate props).

The reference image reached this session in the chat only, not as a file, so `ref/` is empty and there
is no side-by-side sheet. Drop the image in `ref/reference.png` to keep it with the asset.

## Assumptions

- Size: 5.6 x 5.0 m over the walls, eaves at 2.7 m, ridge at 5.3 m, weathervane tip at about 7.4 m. The
  barn in the game today is a 5 x 4 m box; this one is a little bigger so four stalls and an aisle fit,
  with stalls 1.6 x 1.4 m (a sheep is about 1.2 m long).
- Unseen in the reference: the back and the left side (built like the right side, the back with a gable
  window), and the whole interior (designed here).

## Inventory (outside, from the reference)

- red vertical board walls on a footing of grey stone blocks
- cream timber frame: corner posts, a tie beam across the front, a curved knee brace at each end of it
- double doors: red boards, cream frame with a cross brace on each leaf, two black strap hinges per leaf,
  two black ring handles
- a lit four-pane window in a thick cream frame in the front gable and in the side wall
- steep roof of thick dark-brown shakes in lapped, staggered rows; thick tan barge boards along the
  gables; the round end of the ridge beam at the peak; a tan ridge board
- a cupola toward the back: red with cream posts, a louvred vent in each face, a hipped shake roof, a ball
  finial and a gold weathervane (an arrow with a rooster on it)

## Interior (designed)

- plank floor with trodden straw; the stone footing shows along the foot of the walls
- four stalls, two each side of a centre aisle, over the back two thirds: board partitions with a cap rail
  and posts, a railed gate with a cross brace and latch on the aisle, straw bedding and a water bucket in each
- front left: three hay bales and a loose pile. Front right: a feed trough on legs, sacks, a barrel
- back of the aisle: a ladder against the wall, a pitchfork, a lantern on a bracket
- bare board walls inside (the walls are two skins: red outside, bare wood inside)

## Built in parts, for the game

The game shows an inside by hiding what is in the way (the house's walls drop when they face the camera).
The GLB therefore holds separate objects: `base` (floor, footing), `wall_front|back|left|right` at full
height with their gables, `wall_*_low` (the same wall as a 0.62 m stub), `door_l` and `door_r` with their
origins on the hinge line, `roof` (with the cupola) and `interior`. The corner posts go with the side walls.

## Result

26,916 triangles in all (roof 6,166, interior 8,078). Textures are small tiling maps made by the script
(256 and 512 px, colour and normal) plus flat colours for iron, glass glow, gold and sacks. 2.3 MB GLB.

## Review rounds

- Round 0 (first look): shakes too many and too thin, with board seams; barge boards thin; knee braces
  thin and hooked; cupola and weathervane small; straw lay in neat ovals; inner boards full of large knots.
  All changed.
- Round 1: wall red too bright against the reference → deeper red; the back window sat behind the ladder
  and lantern → moved up into the gable; mesh lightened (footing and shakes, 32,100 → 26,916 triangles).
- Round 2 (`review/round2/`): sent to Alex.

## In the game (2026-11-11)

Alex approved the model ("Yes, install it").

- `assets/props/barn.glb` stands where the box barn stood (`World.build_barn`, at 21.5, -9.5, doors to +Z).
  The box barn's code is kept as a fallback for a missing model.
- Walking: the walls either side of the doorway, the two rows of stalls and the hay and feed corners block
  the way (`World.barn_blocks`); the doorway, the front of the barn and the aisle are free. The ground
  under the floor is cleared of grass (`World.barn_floor`).
- `World.update_barn`, every frame: the doors swing open when she is within about 2.6 m of them or inside,
  and shut behind her; while she is inside, the roof is hidden and the walls facing the camera are swapped
  for their stubs (not when Walls Up is on), as in the house; a lantern light comes up as daylight goes.
- The world editor still moves and turns the barn, with its obstacles. Turned to an angle that is not a
  quarter turn, the obstacles become boxes round the turned walls and the inside may be closed off.
- Autotest: `_barn_checks` (the parts, walking in, opening up, closing again); `--only=barn` runs just it.
  Pictures in `review/in_game/`.

## The flock sleeps in the barn (2026-11-11)

Alex: the sheep should walk into the stalls by themselves at night.

- The four stall gates are now parts of their own (`gate_l0`, `gate_l1`, `gate_r0`, `gate_r1`), hinged at
  the end nearer the doors; 17 parts in all.
- `main.gd` `_update_flock`: from 19:30 each sheep walks from the pen, out of its gate, through the barn
  doors and down the aisle into her stall, and stands there facing the aisle; from 6:30 she walks back to
  the pen. Past four sheep, a second one shares each stall. A game that starts at night finds them already
  housed. No barn (deleted in the editor), no bedtime.
- `sheep.gd`: `walk_route`, `place`, `housed`; she walks home at 0.8 m/s, twice her grazing amble.
- `World.update_barn` opens the barn doors for sheep on the move and swings a stall gate in for a sheep
  passing it; both shut again behind her.
- The world editor: moving the pen no longer drags a housed sheep out of the barn.
- Autotest: `_flock_checks`. The rest of the autotest keeps bedtime off, so its sheep stay in the pen.

## Panelled walls and real straw (2026-11-12)

Alex: "give the barn dark red wood panels for the walls", then "the hay in the barn looks bad, try to redo
it to be more straw-like".

- The inner skin of every wall and gable is now dark red boards (`barn_panel`, `#7a2a20`) in place of the
  bare wood; the outside was red already. Stalls, gates and the roof deck stay bare wood.
- Straw: the heaps were smooth striped blobs. `strew()` now lays loose stalks (flat strips, each showing
  one strand of the straw texture) every which way: 75 trodden about each patch of floor (no blob under
  them), 120 over each stall's bedding, 150 over the loose pile, strays on the bales and in the trough.
  The colour is a paler straw gold (`#e6bb4c`) than the orange hay. 28,220 triangles in all.
- In the game the barn also has the plank floor every building has (`Planks`, shade "barn"), laid just
  over the model's boards and under the straw.
- Renders in `review/round3/`.

## Not done yet

- She cannot go into the stalls herself. Shearing a housed sheep is done from the aisle.
- Only the sheep sleep there; there are no other animals yet.
- Triangles are above the style guide's 15,000 for a building.

## Licences

All geometry and textures generated by the scripts. No third-party assets.
