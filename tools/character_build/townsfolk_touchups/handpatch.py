import bpy, bmesh, numpy as np, sys, os
a=sys.argv[sys.argv.index("--")+1:]; proj,cid=a[0],a[1]
body=max([o for o in bpy.data.objects if o.type=='MESH' and "Eye" not in o.name], key=lambda o:len(o.data.vertices))
gi={g.name:g.index for g in body.vertex_groups}
bm=bmesh.new(); bm.from_mesh(body.data)
dl=bm.verts.layers.deform.active; uvl=bm.loops.layers.uv.active
hw=lambda v: max(v[dl].get(gi["LeftHand"],0),v[dl].get(gi["RightHand"],0))
inhand=lambda f: np.mean([hw(v) for v in f.verts])>0.3
removed=0
for _ in range(10):
    kill=[f for f in bm.faces if inhand(f) and sum(e.is_boundary for e in f.edges)>=2]
    if not kill: break
    bmesh.ops.delete(bm,geom=kill,context='FACES'); removed+=len(kill)
    loose=[v for v in bm.verts if not v.link_faces]; bmesh.ops.delete(bm,geom=loose,context='VERTS')
bedges=[e for e in bm.edges if e.is_boundary and hw(e.verts[0])>0.3]
res=bmesh.ops.holes_fill(bm,edges=bedges,sides=200)
new=res["faces"]
bmesh.ops.triangulate(bm,faces=new)
newf=[f for f in bm.faces if any(l[uvl].uv.length==0 for l in f.loops) and inhand(f)]
# uv of each new loop: the uv the same vertex has in an old face
for f in bm.faces:
    for l in f.loops:
        if l[uvl].uv.length==0:
            for l2 in l.vert.link_loops:
                if l2[uvl].uv.length>0: l[uvl].uv=l2[uvl].uv.copy(); break
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
left=sum(1 for e in bm.edges if e.is_boundary and hw(e.verts[0])>0.3)
print("PATCH",cid,"slivers removed",removed,"filled",len(new),"hand boundary left",left)
bm.to_mesh(body.data); body.data.update()
bpy.ops.wm.save_mainfile()
