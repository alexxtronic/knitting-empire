# Textures from the web

Source scans the build scripts read. Nothing here ships in the game as it is: the scripts squeeze each
map to a small tiling square and mix it into their own textures.

| Folder | What | From | Licence |
|---|---|---|---|
| `wool_boucle/` | normal map (1k) of a woven boucle wool, about 31 x 39 cm | [Poly Haven: Wool Boucle](https://polyhaven.com/a/wool_boucle), by colormass and Rico Cilliers | CC0 |
| `poly_wool_herringbone/` | colour map (1k) of a herringbone wool, about 27 x 28 cm | [Poly Haven: Poly Wool Herringbone](https://polyhaven.com/a/poly_wool_herringbone), by colormass and Rico Cilliers | CC0 |
| `knitted_fleece/` | colour map (1k) of a fine knitted fleece, about 27 x 27 cm | [Poly Haven: Knitted Fleece](https://polyhaven.com/a/knitted_fleece), by colormass and Rico Cilliers | CC0 |
| `wood_floor/` | colour and normal maps (1k) of oak floorboards, 1.7 x 1.7 m | [Poly Haven: Wood Floor](https://polyhaven.com/a/wood_floor), by Dimitrios Savva | CC0 |
| `wood_planks/` | colour and normal maps (1k) of honey pine boards, 1.5 x 1.5 m | [Poly Haven: Wood Planks](https://polyhaven.com/a/wood_planks), by Amal Kumar | CC0 |
| `oak_veneer_01/` | colour and normal maps (1k) of light oak veneer, 1.83 x 1.83 m | [Poly Haven: Oak Veneer 01](https://polyhaven.com/a/oak_veneer_01), by Jenelle van Heerden | CC0 |
| `wood_table_001/` | colour and normal maps (1k) of a dark walnut-like table top, 1.5 x 1.5 m | [Poly Haven: Wood Table 001](https://polyhaven.com/a/wood_table_001), by Dimitrios Savva and Rico Cilliers | CC0 |

Used by `house_furniture/build.py` (`plaid()`): the tartan's fibre speckle is the herringbone's colour
map and its woven relief the boucle's normal map; and by `rug_red()`: the fleece's colour map is the
fine speckle on the knitted rug's yarn. The sweater's stitch tiles (`sweater/build.py`) take the same fleece speckle. The four wood scans become the
Cappuccino Cafe's wood (`cafe_wood/build.py`, `assets/textures/wood/`: floor, boards, oak, walnut).

To add one: download only the maps a script needs (1k JPG is plenty) into a folder named after the
asset, and add a row here with its page and licence. CC0 only.
