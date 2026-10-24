"""Read-only, VID/PID-scoped Windows touch probe. Does not install/change drivers.

HIDAPI on Windows RECONSTRUCTS report descriptors from preparsed data. This file
must never be used as evidence of reading the original on-wire descriptor bytes.
Dependency: hidapi 0.15.0 in build/touch_probe_20261024/deps (local tool only).
"""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/touch_probe_20261024'
sys.path.insert(0,str(OUT/'deps'))
import hid

def fields(descriptor):
    g={'page':0,'size':0,'count':0,'id':0,'min':0,'max':0}
    stack=[];local=[];positions={};result=[];index=0
    while index<len(descriptor):
        prefix=descriptor[index];index+=1
        if prefix==254: raise ValueError('Long HID items require explicit review')
        size=(0,1,2,4)[prefix&3];kind=(prefix>>2)&3;tag=prefix>>4
        payload=descriptor[index:index+size];assert len(payload)==size;index+=size
        value=int.from_bytes(payload,'little');signed=int.from_bytes(payload,'little',signed=True)
        if kind==1:
            if tag==0:g['page']=value
            elif tag==1:g['min']=signed
            elif tag==2:g['max']=signed if g['min']<0 else value
            elif tag==7:g['size']=value
            elif tag==8:g['id']=value
            elif tag==9:g['count']=value
            elif tag==10:stack.append(g.copy())
            elif tag==11:g=stack.pop()
        elif kind==2 and tag==0:local.append(value)
        elif kind==0:
            if tag in (8,9,11):
                category={8:'input',9:'output',11:'feature'}[tag];key=(category,g['id'])
                offset=positions.get(key,8 if g['id'] else 0)
                for n in range(g['count']):
                    usage=local[min(n,len(local)-1)] if local else None
                    result.append({'kind':category,'report_id':g['id'],'bit':offset+n*g['size'],
                        'width':g['size'],'usage_page':g['page'],'usage':usage,'constant':bool(value&1),
                        'logical_min':g['min'],'logical_max':g['max']})
                positions[key]=offset+g['size']*g['count']
            local=[]
    return result,{f'{a}:{b}':(bits+7)//8 for (a,b),bits in positions.items()}

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    devices=hid.enumerate(0x1a86,0xe5e3)
    if len(devices)!=1:raise RuntimeError('Expected exactly one 1A86:E5E3 touch device')
    device=devices[0];assert device['usage_page']==13 and device['usage']==4
    handle=hid.device()
    try:
        handle.open_path(device['path'])
        descriptor=bytes(handle.get_report_descriptor())
        feature=bytes(handle.get_feature_report(2,2))
        report_fields,lengths=fields(descriptor)
        assert lengths['input:1']==52 and feature==bytes([2,6])
        inputs=[x for x in report_fields if x['kind']=='input' and not x['constant']]
        for n in range(6):
            bit=(1+8*n)*8
            for offset,page,usage,width in [(0,13,0x42,1),(8,13,0x51,8),(16,1,0x30,16),(32,1,0x31,16)]:
                assert any(x['bit']==bit+offset and x['usage_page']==page and x['usage']==usage and x['width']==width for x in inputs),(n,offset)
        (OUT/'windows_reconstructed_report_descriptor.bin').write_bytes(descriptor)
        (OUT/'contact_count_feature.bin').write_bytes(feature)
        (OUT/'field_map.json').write_text(json.dumps({'lengths':lengths,'fields':report_fields},indent=2)+'\n')
        summary={'vid_pid':'1a86:e5e3','device':device['product_string'],
            'descriptor_origin':'Windows HIDAPI reconstruction; not original USB report descriptor',
            'descriptor_length':len(descriptor),'descriptor_sha256':hashlib.sha256(descriptor).hexdigest(),
            'max_contacts_feature_hex':feature.hex(),'report_lengths':lengths,'six_slot_layout_checked':True,
            'raw_usb_descriptor_obtained':False,'driver_changed':False,'fpga_touch_implemented':False}
        (OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
        print(json.dumps(summary))
    finally:handle.close()

if __name__=='__main__':main()
