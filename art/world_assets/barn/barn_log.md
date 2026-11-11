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

## Not done yet

- Storing pets: the stalls are closed and empty. What goes in them, and how, is for Alex to say.
- She cannot go into the stalls (their gates do not open).
- Triangles are above the style guide's 15,000 for a building.

## Licences

All geometry and textures generated by the scripts. No third-party assets.
