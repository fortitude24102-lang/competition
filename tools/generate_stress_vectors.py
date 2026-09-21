import struct,zlib,pathlib
tiers=(16,32,64,96,128); rec=[]; desc=[]; tag=0
for n in tiers:
    cmds=[]
    for i in range(n+2):
        op=1 if i<n+1 else 6; cmds.append(struct.pack('<BBHHHIIHHIIHH',op,255,0,tag,0,0,0,16 if op==1 else 0,16 if op==1 else 0,1920,1920,0x07e0,0)); tag=(tag+1)&65535
    body=b''.join(cmds); desc.append(struct.pack('<IIHHI',n,len(cmds), (tag-len(cmds))&65535,(tag-1)&65535,n*256)); rec.append(body)
body=b''.join(d+b for d,b in zip(desc,rec)); hdr=struct.pack('<4sHHHHIIIII',b'SVEC',1,32,16,32,len(tiers),0x20260921,sum(len(x)//32 for x in rec),zlib.crc32(body)&0xffffffff,0)
pathlib.Path('tb/vectors').mkdir(parents=True,exist_ok=True); pathlib.Path('tb/vectors/stress_vectors.bin').write_bytes(hdr+body)
