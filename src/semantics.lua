-- Independently authored descriptions of public LUT research. Unknown fields remain explicitly unknown.
local S={}
S.columns={
 'Base color / mode','Detail texture / mask controls','Detail color A','Detail mask A','Detail mask B',
 'Detail inner color','Detail outer color / metal','Metal mask','Unknown 9','Gloss mask',
 'Roughness / rim','Unknown 12','Curvature color','Emission','Tint override','Unknown 16',
 'Camo color 1','Camo color 2','Camo color 3','Camo color 4','Camo fade','Camo selector / scale','Detail profile'}
S.color_columns={[1]=true,[3]=true,[6]=true,[7]=true,[13]=true,[15]=true,[17]=true,[18]=true,[19]=true,[20]=true}
function S.columns_for(width)
    if width==23 then return S.columns end
    if width==3 then return {'Pattern color','Pattern material / opacity','Unconfirmed pattern effects'}end
    if width==16 then return {'Cape base color','Cape overlay A','Cape overlay B','Cape detail gradient','Icon position 1','Icon focus 1','Icon effects 1','Icon position 2','Icon focus 2','Icon effects 2','Icon position 3','Icon focus 3','Icon effects 3','Icon position 4','Icon focus 4','Icon effects 4'}end
    local names={};for i=1,width do names[i]='Unclassified float column '..i end;return names
end
function S.is_color(width,column)
    if width==23 then return S.color_columns[column]end
    return (width==3 and column==1) or (width==16 and column<=4)
end
S.hints={
 [1]='RGB: base color. Alpha: shader mode; keep unchanged unless explicitly editing it.',
 [2]='R: detail index 0-25. G: intensity. B/A: mask inversion controls.',
 [8]='RGBA metallic masks. Negative mask values may invert influence.',
 [9]='Unconfirmed mapping. Raw channels only.',[10]='RGBA gloss/roughness masks; signed values change influence.',
 [11]='R: roughness. B: rim effect; depends on base alpha mode.',[12]='Unconfirmed mapping. Raw channels only.',
 [13]='RGB curvature color; A intensity; depends on base alpha mode.',[14]='R: emission strength; the other channels are unconfirmed.',
 [15]='Nonzero tint can depend on lighting.',[16]='Unconfirmed mapping. Raw channels only.',
 [21]='A: camo fade; RGB effects are unconfirmed.',[22]='R: selector enable (20). G/B: scale. A: pattern index -1 (off) through 5.',
 [23]='XY/detail profile and gloss controls; alpha is unconfirmed.'}
function S.index(row,column,channel,width,height)
    assert(row%1==0 and row>=1 and row<=height and column%1==0 and column>=1 and column<=width and channel%1==0 and channel>=1 and channel<=4,'Invalid grid cell')
    return ((row-1)*width+column-1)*4+channel-1
end
local safe_colors={[1]=true,[3]=true,[6]=true,[7]=true,[17]=true,[18]=true,[19]=true,[20]=true}
function S.safe_cell(column,channel)
    return (safe_colors[column] and channel<=3) or (column==21 and channel==4) or column==22
end
function S.safe_lookup_cell(width,column,channel)
    if width==23 then return S.safe_cell(column,channel)end
    return S.is_color(width,column) and channel<=3
end
function S.protect(original,data,width,height)
    local ffi=require('ffi');local out=ffi.new('float[?]',width*height*4);ffi.copy(out,original,width*height*16)
    for row=1,height do for column=1,width do for channel=1,4 do
        if S.safe_lookup_cell(width,column,channel)then local i=S.index(row,column,channel,width,height);out[i]=data[i]end
    end end end
    return out
end
function S.range(column,channel,value)
    local lo,hi,step=-25,25,.001
    if S.color_columns[column] and channel<=3 then lo,hi,step=0,1,.0001 end
    if column==2 and channel==1 then lo,hi,step=0,25,1 end
    if column==11 and channel==1 then lo,hi,step=0,10,.001 end
    if column==14 and channel==1 then lo,hi,step=0,.06,.0001 end
    if column==22 and channel==4 then lo,hi,step=-1,5,1 end
    lo=math.max(-1e10,math.min(lo,value));hi=math.min(1e10,math.max(hi,value))
    if hi<=lo then hi=lo+1 end
    return lo,hi,step
end
return S
