import bpy, numpy as np, sys, os
a=sys.argv[sys.argv.index("--")+1:]; proj,cid=a[0],a[1]; write="--write" in a
body=max([o for o in bpy.data.objects if o.type=='MESH' and "Eye" not in o.name], key=lambda o:len(o.data.vertices))
me=body.data; co=np.array([(body.matrix_world@v.co)[:] for v in me.vertices]); print('MW',body.matrix_world)
img=[n.image for m in me.materials for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and 'albedo' in n.image.name][0]
W,H=img.size; px=np.array(img.pixels[:],dtype=np.float32).reshape(H,W,4)
EZ=1.437; MID=-0.00375; DX=0.0506
RIN=float(a[a.index("--rin")+1]); ROUT=float(a[a.index("--rout")+1]); FRONT=float(a[a.index("--front")+1])
ring=np.zeros(len(me.polygons),bool)
def yface(c):
    k=co[(np.abs(co[:,0]-c[0])<0.006)&(np.abs(co[:,2]-c[2])<0.006),1]
    return k.min() if len(k) else c[1]
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
RINGS=[((arm.matrix_world@arm.data.bones[n].head_local).x+(-1 if n.startswith('Right') else 1)*float(a[a.index('--dx')+1]),(arm.matrix_world@arm.data.bones[n].head_local).z+float(a[a.index('--dz')+1])) for n in ('LeftEye','RightEye')]; print('RINGS',RINGS); AX=float(a[a.index("--ax")+1]); AZ=float(a[a.index("--az")+1])
for p in me.polygons:
    c=co[list(p.vertices)].mean(0)
    for cx,cz in RINGS:
        r=np.hypot((c[0]-cx)/AX,(c[2]-cz)/AZ)
        if RIN<r<ROUT and c[1]<-0.05 and c[1]<=yface(c)+FRONT: ring[p.index]=True
    MX=sum(x for x,_ in RINGS)/2; EZ=sum(z for _,z in RINGS)/2
    if abs(c[0]-MX)<0.03 and c[2]<EZ-0.012: ring[p.index]=False  # the nose
    if abs(c[0]-MX)<0.02 and abs(c[2]-(EZ+0.005))<0.012 and c[1]<=yface(c)+FRONT: ring[p.index]=True  # the bridge
print("RED faces",ring.sum())
mask=np.zeros((H,W),bool); uv=me.uv_layers.active.data
def tri(P):
    P=np.array(P); x0,y0=np.floor(P.min(0)).astype(int)-1; x1,y1=np.ceil(P.max(0)).astype(int)+1
    x0,y0=max(x0,0),max(y0,0); x1,y1=min(x1,W-1),min(y1,H-1)
    if x1<x0 or y1<y0: return
    ys,xs=np.mgrid[y0:y1+1,x0:x1+1]+0.5
    (ax,ay),(bx,by),(cx,cy)=P
    den=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
    if abs(den)<1e-9: return
    l1=((by-cy)*(xs-cx)+(cx-bx)*(ys-cy))/den; l2=((cy-ay)*(xs-cx)+(ax-cx)*(ys-cy))/den; l3=1-l1-l2
    e=-0.35/max(abs(den),1)**0.5
    mask[y0:y1+1,x0:x1+1]|=(l1>=e)&(l2>=e)&(l3>=e)
for p in me.polygons:
    if ring[p.index]:
        pts=[(uv[l].uv[0]*W, uv[l].uv[1]*H) for l in p.loop_indices]
        for k in range(1,len(pts)-1): tri([pts[0],pts[k],pts[k+1]])
rgb=px[...,:3]; lum=rgb.mean(2); med=np.median(lum[mask])
red=np.array([0.50,0.05,0.06])
rgb[mask]=np.clip(red[None,:]*(0.65+0.35*np.clip(lum[mask]/med,0.5,1.5))[:,None],0,1)  # an even lacquer, a little of the bake's shading kept
px[...,:3]=rgb; img.pixels.foreach_set(px.ravel()); img.pack()
if write: bpy.ops.wm.save_mainfile()
bpy.ops.export_scene.gltf(filepath=os.path.join(proj,"assets",cid+"_eyes.glb") if write else a[a.index("--out")+1], export_format="GLB", export_apply=False,
    export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
    export_morph=True, export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
