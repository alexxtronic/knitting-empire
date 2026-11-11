"""Lays the hero renders out on one sheet, four across."""
import os
import sys

from PIL import Image

d = sys.argv[1]
names = sorted(f for f in os.listdir(d) if f.endswith(".png") and not f.startswith("sheet"))
cols = 4
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGB", (480 * cols, 480 * rows), "white")
for i, n in enumerate(names):
    im = Image.open(os.path.join(d, n)).convert("RGB").resize((480, 480), Image.LANCZOS)
    sheet.paste(im, (480 * (i % cols), 480 * (i // cols)))
sheet.save(os.path.join(d, "sheet.png"))
print(names)
