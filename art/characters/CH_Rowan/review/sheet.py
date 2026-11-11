import sys
from PIL import Image
d=sys.argv[1]; views=sys.argv[2].split(','); scale=float(sys.argv[3]) if len(sys.argv)>3 else 0.5
ims=[Image.open(f'{d}/{v}.png').convert('RGBA') for v in views]
W=sum(i.width for i in ims); H=max(i.height for i in ims)
sheet=Image.new('RGB',(W,H),(238,238,238)); x=0
for i in ims:
    sheet.paste(i,(x,0),i); x+=i.width
sheet=sheet.resize((int(W*scale),int(H*scale))); sheet.save(f'{d}/sheet.jpg',quality=85); print(sheet.size)
