"""Compose the three review sheets from the renders made by review/gates.sh."""
from PIL import Image, ImageDraw

def row(names, h):
    a = [Image.open(n).convert('RGB') for n in names]
    a = [i.resize((int(i.width * h / i.height), h), Image.LANCZOS) for i in a]
    W = sum(i.width for i in a); s = Image.new('RGB', (W, h), 'white'); x = 0
    for i in a:
        s.paste(i, (x, 0)); x += i.width
    return s

ref = [Image.open(f'ref/{n}.png').convert('RGB') for n in ('front', 'tq_front', 'side', 'tq_back', 'back')]
ren = [Image.open(f'review/beauty/turn_{v}.png').convert('RGB') for v in ('000', '315', '090', '135', '180')]
H, cell = 793, 360
row1 = Image.new('RGB', (cell * 5, H), 'white'); row2 = Image.new('RGB', (cell * 5, H), 'white')
for i, (a, b) in enumerate(zip(ref, ren)):
    row1.paste(a, (i * cell, 0)); s = (767 / 1.80) * 1.86 / b.height        # 1 m in the render = 1 m in the reference
    b2 = b.resize((int(b.width * s), int(b.height * s)), Image.LANCZOS); gy = int(b2.height * (1.84 / 1.86))
    row2.paste(b2, (i * cell + (cell - b2.width) // 2, 777 - gy))
sheet = Image.new('RGB', (cell * 5, H * 2 + 60), 'white'); d = ImageDraw.Draw(sheet)
d.text((10, 6), "REFERENCE", fill=(60, 60, 60)); sheet.paste(row1, (0, 24))
d.text((10, H + 34), "CH_Rowan build (Blender, same scale)", fill=(60, 60, 60)); sheet.paste(row2, (0, H + 54))
sheet.save('review/01_compare_turnaround.png')

mpp = 1.80 / 767
def refhead(axis):
    return ref_sheet.crop((axis - int(0.166 / mpp), max(0, int(776 - 1.83 / mpp)), axis + int(0.166 / mpp), int(776 - 1.44 / mpp)))
ref_sheet = Image.open('ref/sheet.png').convert('RGB')
top = row(['review/beauty/head_000.png', 'review/beauty/head_040.png', 'review/beauty/head_090.png'], 640)
rh = [refhead(218), refhead(972)]
rh = [i.resize((int(i.width * 640 / i.height), 640), Image.LANCZOS) for i in rh]
bot = row(['review/face/open_000.png', 'review/face/open_040.png'], 640)
W = max(top.width + rh[0].width, bot.width + rh[1].width)
s = Image.new('RGB', (W, 1330), 'white'); d = ImageDraw.Draw(s)
s.paste(rh[0], (0, 20)); s.paste(top, (rh[0].width, 20)); s.paste(rh[1], (0, 690)); s.paste(bot, (rh[1].width, 690))
d.text((10, 4), "Reference (left) and the head at rest", fill=(60, 60, 60))
d.text((10, 672), "Reference side (left) and the face test: jaw opened 16 degrees on its hinge, eyes turned 22 degrees", fill=(60, 60, 60))
s.save('review/02_head_and_face_test.png')

a = row(['review/nude/lit_000.png', 'review/nude/lit_315.png', 'review/nude/lit_090.png', 'review/nude/lit_180.png'], 800)
b = row(['review/wire/wire_000.png', 'review/wire/wire_090.png', 'review/wire/headwire_000.png', 'review/wire/headwire_060.png'], 800)
s = Image.new('RGB', (max(a.width, b.width), 1650), 'white'); d = ImageDraw.Draw(s)
s.paste(a, (0, 20)); s.paste(b, (0, 845))
d.text((10, 4), "Body with the outfit hidden (hair, beard and brows are separate objects too)", fill=(60, 60, 60))
d.text((10, 828), "Topology: all quads, a row at every joint; lid loops inside each eye opening, lip loops inside the mouth", fill=(60, 60, 60))
s.save('review/03_body_and_topology.png')
for n in ('01_compare_turnaround', '02_head_and_face_test', '03_body_and_topology'):
    i = Image.open(f'review/{n}.png'); i.resize((1500, int(i.height * 1500 / i.width))).save(f'review/{n}_small.jpg', quality=84)
print('sheets done')
