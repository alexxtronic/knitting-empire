"""Lay the review renders out as one sheet: python sheet.py (run from this folder, needs Pillow)."""
from PIL import Image, ImageDraw
import glob, os
names = sorted(glob.glob('review/[0-9][0-9]_*.png'))
small = [n for n in names if int(os.path.basename(n)[:2]) <= 15]
tw, th = 520, 289
cols = 3
rows = (len(small) + cols - 1) // cols
s = Image.new('RGB', (cols * tw, rows * (th + 18)), 'white'); d = ImageDraw.Draw(s)
for k, n in enumerate(small):
    im = Image.open(n).convert('RGB').resize((tw, th), Image.LANCZOS)
    x, y = (k % cols) * tw, (k // cols) * (th + 18)
    s.paste(im, (x, y + 18)); d.text((x + 6, y + 3), os.path.basename(n)[3:-4].replace('_', ' '), fill=(40, 40, 40))
s.save('review/sheet_eyes.png')
faces = [n for n in names if int(os.path.basename(n)[:2]) > 15]
if faces:
    f = Image.new('RGB', (len(faces) * 600, 618), 'white'); d = ImageDraw.Draw(f)
    for k, n in enumerate(faces):
        f.paste(Image.open(n).convert('RGB').resize((600, 600), Image.LANCZOS), (k * 600, 18)); d.text((k * 600 + 6, 3), os.path.basename(n)[3:-4].replace('_', ' '), fill=(40, 40, 40))
    f.save('review/sheet_face.png')
print('sheets', len(small), len(faces))
