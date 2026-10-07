from pathlib import Path
import sys,struct
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import numpy as np
from lut_files import decode_dds,encode_dds
data=np.arange(8*23*4,dtype=np.float32).reshape(8,23,4)-100
raw=bytearray(encode_dds(data));struct.pack_into('<I',raw,24,1);struct.pack_into('<I',raw,28,2);raw+=bytes(11*4*16)
assert np.array_equal(decode_dds(raw),data)
for mutate in ('truncated','mips','volume','cube','array'):
 bad=bytearray(raw)
 if mutate=='truncated':bad=bad[:-1]
 elif mutate=='mips':struct.pack_into('<I',bad,28,99)
 elif mutate=='volume':struct.pack_into('<I',bad,8,0x80100f)
 elif mutate=='cube':struct.pack_into('<I',bad,112,512)
 else:struct.pack_into('<I',bad,140,2)
 try:decode_dds(bad)
 except ValueError:pass
 else:raise AssertionError(mutate)
print('PASS full DDS mip chain and depth-one support; truncated, impossible, volume, cube and array files rejected')
