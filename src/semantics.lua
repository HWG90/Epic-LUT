-- Independently authored descriptions of public LUT research. Unknown fields remain explicitly unknown.
local S={}
S.columns={
 'Primary color / shader mode','Bump map / inversion controls','Bump mask 1 color','Bump mask 1','Bump mask 2',
 'Bump mask 2 inner color','Bump mask 2 outer color','Metallic mask','Unknown 9','Gloss / roughness mask',
 'Roughness / rim','Unknown 12','Curvature gradient','Emissive strength','Lighting tint override','Unknown 16',
 'Camo color 1','Camo color 2','Camo color 3','Camo color 4','Mask 5 inversion','Camo controls','Bump scaling / matte-gloss'}
S.color_columns={[1]=true,[3]=true,[6]=true,[7]=true,[13]=true,[15]=true,[17]=true,[18]=true,[19]=true,[20]=true}
S.short_columns={'Base','Bump','D1','M1','M2','In','Out','Metal','?9','Gloss','Rim','?12','Curv','Glow','Tint','?16','C1','C2','C3','C4','Inv','Camo','Scale'}
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
 [1]='RGB sets primary color. Alpha selects shader behavior; curvature, emission and camo can depend on it.',
 [2]='R selects bump-map index 0-25. G controls intensity; B/A affect mask inversion.',
 [3]='RGB colors the first bump mask. Zero RGB disables its color contribution.',
 [4]='First bump-mask layer. Signed values can reverse where its channels apply.',
 [5]='Second bump-mask layer, above the first mask.',
 [6]='Inner color of the second bump mask, strongest where that mask is strong.',
 [7]='Outer color of the second bump mask. Alpha affects metallic-mask inversion.',
 [8]='RGBA metallic masks. Negative mask values may invert influence.',
 [9]='Unconfirmed mapping. Raw channels only.',
 [10]='RGBA gloss/roughness masks; signed values change influence.',
 [11]='R: roughness. B: rim effect; depends on primary alpha mode.',
 [12]='Unconfirmed mapping. Raw channels only.',
 [13]='RGB curvature gradient; A intensity. Requires a compatible primary alpha mode.',
 [14]='R: emissive strength, commonly 0.001-0.06. Other channels are unconfirmed.',
 [15]='Usually keep RGBA at zero. Nonzero tint depends on lighting.',
 [16]='Unconfirmed mapping. Raw channels only.',
 [17]='First camo color. Alpha influences camo roughness; behavior depends on primary alpha mode.',
 [18]='Second camo color. Alpha also participates in the fifth bump mask.',
 [19]='Third camo color. Alpha also participates in the fifth bump mask.',
 [20]='Fourth camo color; its use depends on pattern type. Alpha also affects the fifth mask.',
 [21]='Alpha changes fifth-mask inversion; RGB behavior is unconfirmed.',
 [22]='Camo strength, scale and pattern. Large scalar values can be valid. A selects pattern -1 (off) through 5.',
 [23]='Bump-map scaling and matte/gloss controls. Some effects depend on overlapping masks.'}
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
    if column==22 and channel==1 then lo,hi,step=0,512,.01 end
    lo=math.max(-1e10,math.min(lo,value));hi=math.min(1e10,math.max(hi,value))
    if hi<=lo then hi=lo+1 end
    return lo,hi,step
end
return S
