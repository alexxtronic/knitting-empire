import bpy, bmesh, numpy as np, sys, os
a=sys.argv[sys.argv.index("--")+1:]
proj, cid, dry = a[0], a[1], "--dry" in a
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
body=max([o for o in bpy.data.objects if o.type=='MESH' and "Eye" not in o.name], key=lambda o:len(o.data.vertices))
me=body.data; n=len(me.vertices)
co=np.array([v.co[:] for v in me.vertices])
gi={g.index:g.name for g in body.vertex_groups}
nb=[[] for _ in range(n)]
for e in me.edges:
    i,j=e.vertices; nb[i].append(j); nb[j].append(i)
elen=np.median([np.linalg.norm(co[e.vertices[0]]-co[e.vertices[1]]) for e in me.edges])
w=np.zeros(n)
for side in ("Left","Right"):
    hb=arm.data.bones[side+"Hand"]
    h=np.array((body.matrix_world.inverted()@(arm.matrix_world@hb.head_local))[:]); t=np.array((body.matrix_world.inverted()@(arm.matrix_world@hb.tail_local))[:])
    ax=t-h; L=np.linalg.norm(ax); ax/=L
    hw=np.zeros(n)
    gidx=[k for k,v in gi.items() if v==side+"Hand"]
    for v in me.vertices:
        for g in v.groups:
            if g.group in gidx: hw[v.index]=g.weight
    along=((co-h)@ax)/L
    f=np.clip((along-0.25)/0.35,0,1)*np.clip((hw-0.4)/0.3,0,1)
    w=np.maximum(w,f*f*(3-2*f))
zone=np.where(w>0)[0]
def lap(c):
    m=np.array([c[nb[i]].mean(0) if nb[i] else c[i] for i in range(n)])
    return m-c
d=np.linalg.norm(lap(co)[zone],axis=1)/elen
print("HANDSMOOTH",cid,"zone",len(zone),"spike p95 %.2f max %.2f"%(np.percentile(d,95),d.max()))
if not dry:
    c=co.copy(); W=w[:,None]
    for _ in range(int(a[a.index("--iters")+1]) if "--iters" in a else 25):
        c=c+0.5*W*lap(c)
        if '--plain' not in a: c=c-0.53*W*lap(c)
    d2=np.linalg.norm(lap(c)[zone],axis=1)/elen
    print("HANDSMOOTH after p95 %.2f max %.2f moved max %.4f m"%(np.percentile(d2,95),d2.max(),np.linalg.norm(c-co,axis=1).max()))
    me.vertices.foreach_set("co",c.astype(np.float32).ravel()); me.update()
    bpy.ops.wm.save_mainfile()
    bpy.ops.export_scene.gltf(filepath=os.path.join(proj,"assets",cid+"_eyes.glb"), export_format="GLB", export_apply=False,
        export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
        export_morph=True, export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
    print("HANDSMOOTH exported",cid)
