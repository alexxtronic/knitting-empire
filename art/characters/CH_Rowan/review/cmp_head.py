# Reference head beside the built head (front and side) at the same scale.
from PIL import Image
ref=Image.open('ref/sheet.png').convert('RGB')
def refcrop(axis, zlo=1.44, zhi=1.83, halfw=0.166):
    mpp=1.80/767; y0=int(776-(zhi/mpp)); y1=int(776-(zlo/mpp)); hw=int(halfw/mpp)
    return ref.crop((axis-hw,max(0,y0),axis+hw,y1))
ims=[refcrop(218), Image.open('review/beauty/head_000.png').convert('RGB'), refcrop(972), Image.open('review/beauty/head_090.png').convert('RGB')]
h=560; ims=[i.resize((int(i.width*h/i.height),h),Image.LANCZOS) for i in ims]
W=sum(i.width for i in ims); s=Image.new('RGB',(W,h),'white'); x=0
for i in ims: s.paste(i,(x,0)); x+=i.width
s.save('review/beauty/headcmp.jpg',quality=88)
