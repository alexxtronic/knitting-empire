import bpy, sys, numpy as np
a=sys.argv[sys.argv.index("--")+1:]
proj, cid, dry = a[0], a[1], "--dry" in a
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
body=max([o for o in bpy.data.objects if o.type=='MESH' and o.parent==arm and "Eye" not in o.name], key=lambda o:len(o.data.vertices))
me=body.data
gi={g.index:g.name for g in body.vertex_groups}
hand=np.zeros(len(me.vertices))
for v in me.vertices:
    for g in v.groups:
        n=gi.get(g.group,"")
        if n.endswith("Hand") or "Index" in n or "Thumb" in n: hand[v.index]+=g.weight
img=None
for m in me.materials:
    for n in m.node_tree.nodes:
        if n.type=='TEX_IMAGE' and n.image and 'albedo' in n.image.name: img=n.image
W,H=img.size
px=np.array(img.pixels[:],dtype=np.float32).reshape(H,W,4)
mask=np.zeros((H,W),bool)
uv=me.uv_layers.active.data
def tri(P):
    P=np.array(P); x0,y0=np.floor(P.min(0)).astype(int)-1; x1,y1=np.ceil(P.max(0)).astype(int)+1
    x0,y0=max(x0,0),max(y0,0); x1,y1=min(x1,W-1),min(y1,H-1)
    if x1<x0 or y1<y0: return
    ys,xs=np.mgrid[y0:y1+1,x0:x1+1]+0.5
    (ax,ay),(bx,by),(cx,cy)=P
    den=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
    if abs(den)<1e-9: return
    l1=((by-cy)*(xs-cx)+(cx-bx)*(ys-cy))/den; l2=((cy-ay)*(xs-cx)+(ax-cx)*(ys-cy))/den; l3=1-l1-l2
    e=-1.5/max(abs(den),1)**0.5
    mask[y0:y1+1,x0:x1+1]|=(l1>=e)&(l2>=e)&(l3>=e)
nf=0
for p in me.polygons:
    if np.mean([hand[i] for i in p.vertices])>0.6:
        pts=[(uv[li].uv[0]*W, uv[li].uv[1]*H) for li in p.loop_indices]
        for k in range(1,len(pts)-1): tri([pts[0],pts[k],pts[k+1]])
        nf+=1
rgb=px[...,:3]; lum=rgb@np.array([0.3,0.59,0.11])
med=np.median(lum[mask]); medc=np.median(rgb[mask],axis=0)
TH=float(a[a.index("--th")+1]) if "--th" in a else 0.5
dark=mask&(lum<TH*med)
print("HANDFIX",cid,"faces",nf,"texels",int(mask.sum()),"median",round(float(med),3),"dark",int(dark.sum()))
if not dry and dark.any():
    # fill each dark texel from the nearest good hand texel (grow the good colour inward), else the median
    good=mask&~dark
    out=rgb.copy(); todo=dark.copy()
    for _ in range(40):
        if not todo.any(): break
        acc=np.zeros_like(out); cnt=np.zeros(todo.shape)
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
            g=np.roll(good,(dy,dx),(0,1)); c=np.roll(out,(dy,dx),(0,1))
            acc+=c*g[...,None]; cnt+=g
        fill=todo&(cnt>0)
        out[fill]=acc[fill]/cnt[fill][:,None]; good=good|fill; todo=todo&~fill
    out[todo]=medc
    px[...,:3]=out
    img.pixels.foreach_set(px.ravel()); img.pack()
    bpy.ops.wm.save_mainfile()
    import os
    for o in bpy.context.scene.objects: o.select_set(False)
    bpy.ops.export_scene.gltf(filepath=os.path.join(proj,"assets",cid+"_eyes.glb"), export_format="GLB", export_apply=False,
        export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
        export_morph=True, export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
    print("HANDFIX exported", cid)
