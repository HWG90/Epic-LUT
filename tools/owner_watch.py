"""Watch the launching game's lifetime using process IDs, without opening its memory."""
import ctypes,os

def process_alive(pid):
    if os.name!='nt':raise RuntimeError('Owner tracking requires Windows')
    enum=ctypes.WinDLL('psapi',use_last_error=True).EnumProcesses
    enum.argtypes=[ctypes.POINTER(ctypes.c_uint32),ctypes.c_uint32,ctypes.POINTER(ctypes.c_uint32)]
    enum.restype=ctypes.c_int
    capacity=4096
    while capacity<=65536:
        values=(ctypes.c_uint32*capacity)();used=ctypes.c_uint32()
        if not enum(values,ctypes.sizeof(values),ctypes.byref(used)):raise ctypes.WinError(ctypes.get_last_error())
        if used.value<ctypes.sizeof(values):return pid in values[:used.value//4]
        capacity*=2
    raise RuntimeError('Process inventory exceeds owner-watch budget')
