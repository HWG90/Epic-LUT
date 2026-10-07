"""Bounded semantic LUT remapping. Unknown target fields always retain their originals."""
from lut_files import load,validate
import numpy as np

COLORS={23:{0,2,5,6,12,14,16,17,18,19},16:{0,1,2,3},3:{0}}
KNOWN={23:set(range(23))-{8,11,15},16:set(range(16)),3:{0,1}}

def remap(source,original,preserve_material=False,preserve_emission=False):
    source=validate(source);original=validate(original);sw=source.shape[1];tw=original.shape[1]
    if sw not in KNOWN or tw not in KNOWN:raise ValueError('Unclassified shader layout; no confirmed semantic mapping')
    # Endpoints align; a one-row source repeats. No filtering/clamping of float values.
    rows=np.floor(np.linspace(0,source.shape[0]-1,original.shape[0])+.5).astype(int)
    sampled=source[rows];out=original.copy()
    if sw!=tw:
        out[:,0,:3]=sampled[:,0,:3]
        return validate(out),'base color RGB only; other layout fields retained'
    for col in sorted(KNOWN[tw]):
        if tw==23 and col==13:
            if not preserve_emission:out[:,col,0]=sampled[:,col,0]
            # Emission GBA meanings remain uncertain; never infer them.
        elif preserve_material:
            if col in COLORS[tw]:out[:,col,:3]=sampled[:,col,:3]
        else:out[:,col]=sampled[:,col]
    return validate(out),'known semantic fields; unknown fields retained'

def plan(editor,kind,preserve_material=False,preserve_emission=False):
    if kind not in ('armor','helmet'):raise ValueError('Choose Armor or Helmet')
    live=editor.live()or {};targets=[v for v in live.get('luts',[])if v.get('kind')==kind]
    sources=[{'resource':v.get('resource'),'name':v['name'],'data':load(editor.file(v['name']))}for v in editor.imports]
    if not sources and editor.data is not None:sources=[{'resource':editor.resource,'name':editor.path.name,'data':editor.data}]
    sources=[v for v in sources if v['data'].shape[1]in KNOWN]
    if not targets:raise ValueError('No equipped '+kind+' LUTs are available')
    records=[];report=[]
    for target in targets:
        eligible=sources if target['width']in KNOWN else []
        if not eligible:report.append({'target':target['hash'],'status':'skipped','reason':'No confirmed semantic layout mapping'});continue
        exact=[v for v in eligible if v['resource']==target['hash']]
        if len(exact)>1:raise ValueError('More than one archive palette matches '+target['hash'])
        source=(exact or sorted(eligible,key=lambda v:(v['data'].shape[1]!=target['width'],abs(v['data'].shape[0]-target['height']),v['resource']or '',v['name'])))[0]
        original=load(editor.file(target['original']))
        if original.shape!=(target['height'],target['width'],4):raise ValueError('Original snapshot shape changed')
        data,detail=remap(source['data'],original,preserve_material,preserve_emission)
        records.append((editor.file(target['working']),data))
        report.append({'target':target['hash'],'source':source['resource']or source['name'],'status':'applied','match':'exact resource'if exact else 'semantic remap','detail':detail,'source_rows':source['data'].shape[0],'target_rows':target['height']})
    return records,report
