# Textures from the web

Source scans the build scripts read. Nothing here ships in the game as it is: the scripts squeeze each
map to a small tiling square and mix it into their own textures.

| Folder | What | From | Licence |
|---|---|---|---|
| `wool_boucle/` | normal map (1k) of a woven boucle wool, about 31 x 39 cm | [Poly Haven: Wool Boucle](https://polyhaven.com/a/wool_boucle), by colormass and Rico Cilliers | CC0 |
| `poly_wool_herringbone/` | colour map (1k) of a herringbone wool, about 27 x 28 cm | [Poly Haven: Poly Wool Herringbone](https://polyhaven.com/a/poly_wool_herringbone), by colormass and Rico Cilliers | CC0 |

Used by `house_furniture/build.py` (`plaid()`): the tartan's fibre speckle is the herringbone's colour
map and its woven relief the boucle's normal map.

To add one: download only the maps a script needs (1k JPG is plenty) into a folder named after the
asset, and add a row here with its page and licence. CC0 only.
