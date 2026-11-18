import bpy, bmesh, numpy as np, sys, os
a=sys.argv[sys.argv.index("--")+1:]; proj,cid=a[0],a[1]
body=max([o for o in bpy.data.objects if o.type=='MESH' and "Eye" not in o.name], key=lambda o:len(o.data.vertices))
gi={g.name:g.index for g in body.vertex_groups}
bm=bmesh.new(); bm.from_mesh(body.data)
dl=bm.verts.layers.deform.active; uvl=bm.loops.layers.uv.active
hw=lambda v: max(v[dl].get(gi["LeftHand"],0),v[dl].get(gi["RightHand"],0))
fs=[f for f in bm.faces if np.mean([hw(v) for v in f.verts])>0.3]
def uva(f):
    u=[l[uvl].uv for l in f.loops]; return abs((u[1]-u[0]).cross(u[2]-u[0]))/2 if len(u)==3 else 0
r={f:uva(f)/max(f.calc_area(),1e-9) for f in fs}
med=np.median(list(r.values()))
bad=[f for f in fs if r[f]>8*med]
good=set(fs)-set(bad)
fixed=0
for f in bad:
    src=None
    for v in f.verts:
        for g in v.link_faces:
            if g in good: src=g; break
        if src: break
    if src:
        c=sum((l[uvl].uv for l in src.loops), src.loops[0][uvl].uv*0)/len(src.loops)
        for l in f.loops: l[uvl].uv=c.copy()
        fixed+=1
print("UVFIX",cid,"hand faces",len(fs),"stretched",len(bad),"fixed",fixed)
bm.to_mesh(body.data); body.data.update(); bpy.ops.wm.save_mainfile()
bpy.ops.export_scene.gltf(filepath=os.path.join(proj,"assets",cid+"_eyes.glb"), export_format="GLB", export_apply=False,
    export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
    export_morph=True, export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
