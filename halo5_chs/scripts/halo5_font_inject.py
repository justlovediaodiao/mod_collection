"""h5hook.py - 把 Halo 5 Forge 的 cht 字体读取重定向到本地补丁字体。

改写 kernelbase!CreateFile2 的函数序言 (inline detour)。

用法:
    python h5hook.py

先运行脚本再启动游戏, 或游戏已在运行时直接运行。安装后会持续等待钩子
触发并打印日志; 按 Ctrl+C 退出。
"""
import ctypes
import ctypes.wintypes as w
import os
import struct
import time

import capstone
from capstone import x86 as cs_x86

MODULE = 'halo5forge.exe'
LOCALAPPDATA = os.environ.get('LOCALAPPDATA') or os.path.join(os.path.expanduser('~'), 'AppData', 'Local')
FONTDIR = os.path.join(LOCALAPPDATA, 'Packages',
                       'Microsoft.Halo5Forge_8wekyb3d8bbwe', 'LocalState', 'fonts')
CHT = os.path.join(FONTDIR, 'font_package_cht.bin')
CHT4K = os.path.join(FONTDIR, 'font_package_cht_4k.bin')


def log(*a):
    print(*a, flush=True)


# ---------------------------------------------------------------- win32 ----
k32 = ctypes.WinDLL('kernel32', use_last_error=True)
k32.OpenProcess.restype = w.HANDLE
k32.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
k32.VirtualAllocEx.restype = ctypes.c_void_p
k32.VirtualAllocEx.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.c_size_t, w.DWORD, w.DWORD]
k32.VirtualProtectEx.restype = w.BOOL
k32.VirtualProtectEx.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.c_size_t, w.DWORD, ctypes.POINTER(w.DWORD)]
k32.WriteProcessMemory.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.CreateToolhelp32Snapshot.restype = w.HANDLE
k32.CreateToolhelp32Snapshot.argtypes = [w.DWORD, w.DWORD]
k32.OpenThread.restype = w.HANDLE
k32.OpenThread.argtypes = [w.DWORD, w.BOOL, w.DWORD]
k32.SuspendThread.restype = w.DWORD
k32.SuspendThread.argtypes = [w.HANDLE]
k32.ResumeThread.restype = w.DWORD
k32.ResumeThread.argtypes = [w.HANDLE]
k32.CloseHandle.argtypes = [w.HANDLE]
k32.WaitForSingleObject.restype = w.DWORD
k32.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
for _fn in ('Module32FirstW', 'Module32NextW', 'Process32FirstW', 'Process32NextW',
            'Thread32First', 'Thread32Next'):
    getattr(k32, _fn).argtypes = [w.HANDLE, ctypes.c_void_p]


class ME(ctypes.Structure):
    _fields_ = [('dwSize', w.DWORD), ('th32ModuleID', w.DWORD), ('th32ProcessID', w.DWORD),
                ('GlblcntUsage', w.DWORD), ('ProccntUsage', w.DWORD), ('modBaseAddr', ctypes.c_void_p),
                ('modBaseSize', w.DWORD), ('hModule', w.HMODULE), ('szModule', ctypes.c_wchar * 256),
                ('szExePath', ctypes.c_wchar * 260)]


class TE(ctypes.Structure):
    _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('th32ThreadID', w.DWORD),
                ('th32OwnerProcessID', w.DWORD), ('tpBasePri', ctypes.c_long), ('tpDeltaPri', ctypes.c_long),
                ('dwFlags', w.DWORD)]


class PE(ctypes.Structure):
    _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('th32ProcessID', w.DWORD),
                ('th32DefaultHeapID', ctypes.c_void_p), ('th32ModuleID', w.DWORD),
                ('cntThreads', w.DWORD), ('th32ParentProcessID', w.DWORD), ('pcPriClassBase', ctypes.c_long),
                ('dwFlags', w.DWORD), ('szExeFile', ctypes.c_wchar * 260)]


def find_pid(name=MODULE):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PE(); pe.dwSize = ctypes.sizeof(PE)
    if k32.Process32FirstW(snap, ctypes.byref(pe)):
        while True:
            if pe.szExeFile.lower() == name.lower():
                k32.CloseHandle(snap); return pe.th32ProcessID
            if not k32.Process32NextW(snap, ctypes.byref(pe)):
                break
    k32.CloseHandle(snap); return None


class H5:
    def __init__(self, pid):
        self.pid = pid
        self.h = k32.OpenProcess(0x1F0FFF, False, pid)
        if not self.h:
            raise OSError('OpenProcess failed %d' % ctypes.get_last_error())
        snap = k32.CreateToolhelp32Snapshot(0x8, pid)
        me = ME(); me.dwSize = ctypes.sizeof(ME); self.mods = {}
        if k32.Module32FirstW(snap, ctypes.byref(me)):
            while True:
                self.mods[me.szModule.lower()] = (me.modBaseAddr, me.modBaseSize)
                if not k32.Module32NextW(snap, ctypes.byref(me)):
                    break
        k32.CloseHandle(snap)

    def read(self, addr, n):
        b = (ctypes.c_ubyte * n)(); c = ctypes.c_size_t(0)
        if not k32.ReadProcessMemory(self.h, ctypes.c_void_p(addr), b, n, ctypes.byref(c)):
            return None
        return bytes(b)

    def write(self, addr, data):
        old = w.DWORD(0)
        k32.VirtualProtectEx(self.h, ctypes.c_void_p(addr), len(data), 0x40, ctypes.byref(old))
        b = (ctypes.c_ubyte * len(data)).from_buffer_copy(data); c = ctypes.c_size_t(0)
        ok = k32.WriteProcessMemory(self.h, ctypes.c_void_p(addr), b, len(data), ctypes.byref(c))
        k32.VirtualProtectEx(self.h, ctypes.c_void_p(addr), len(data), old.value, ctypes.byref(w.DWORD(0)))
        return bool(ok)

    def alloc(self, size):
        return k32.VirtualAllocEx(self.h, None, size, 0x3000, 0x40)


def suspend_threads(pid):
    snap = k32.CreateToolhelp32Snapshot(0x4, 0); hs = []
    te = TE(); te.dwSize = ctypes.sizeof(TE)
    if k32.Thread32First(snap, ctypes.byref(te)):
        while True:
            if te.th32OwnerProcessID == pid:
                h = k32.OpenThread(0x0002, False, te.th32ThreadID)
                if h:
                    k32.SuspendThread(h); hs.append(h)
            if not k32.Thread32Next(snap, ctypes.byref(te)):
                break
    k32.CloseHandle(snap); return hs


def resume_threads(hs):
    for h in hs:
        k32.ResumeThread(h); k32.CloseHandle(h)


# ------------------------------------------------------------- helpers ----
def resolve_export(h5, dll, name):
    base = h5.mods[dll.lower()][0]
    e = struct.unpack_from('<I', h5.read(base + 0x3C, 4), 0)[0]
    opt = e + 0x18
    magic = struct.unpack_from('<H', h5.read(base + opt, 2), 0)[0]
    dd = opt + (0x70 if magic == 0x20B else 0x60)
    exp_rva = struct.unpack_from('<I', h5.read(base + dd, 4), 0)[0]
    d = h5.read(base + exp_rva, 40)
    nfunc, nname, af, an, ao = struct.unpack_from('<IIIII', d, 20)
    names = h5.read(base + an, 4 * nname)
    ords = h5.read(base + ao, 2 * nname)
    funcs = h5.read(base + af, 4 * nfunc)
    for i in range(nname):
        nr = struct.unpack_from('<I', names, 4 * i)[0]
        s = h5.read(base + nr, 64).split(b'\0')[0].decode('latin1')
        if s == name:
            ov = struct.unpack_from('<H', ords, 2 * i)[0]
            return base + struct.unpack_from('<I', funcs, 4 * ov)[0]
    return None


# 汇编源码 (已用 llvm-mc 预先汇编成下面的机器码, 运行时不再依赖 llvm):
#
#     # rcx = LPCWSTR lpFileName
#     mov r10, rcx                # 保存路径指针，r10 用于逐字符扫描
# scan:
#     movzx eax, word ptr [r10]   # 读到字符串结尾就放行
#     test eax, eax
#     je done
#     # 匹配 "font_package"
#     movzx eax, word ptr [r10+0]
#     cmp eax, 0x66
#     jne next
#     movzx eax, word ptr [r10+2]
#     cmp eax, 0x6F
#     jne next
#     movzx eax, word ptr [r10+4]
#     cmp eax, 0x6E
#     jne next
#     movzx eax, word ptr [r10+6]
#     cmp eax, 0x74
#     jne next
#     movzx eax, word ptr [r10+8]
#     cmp eax, 0x5F
#     jne next
#     movzx eax, word ptr [r10+10]
#     cmp eax, 0x70
#     jne next
#     movzx eax, word ptr [r10+12]
#     cmp eax, 0x61
#     jne next
#     movzx eax, word ptr [r10+14]
#     cmp eax, 0x63
#     jne next
#     movzx eax, word ptr [r10+16]
#     cmp eax, 0x6B
#     jne next
#     movzx eax, word ptr [r10+18]
#     cmp eax, 0x61
#     jne next
#     movzx eax, word ptr [r10+20]
#     cmp eax, 0x67
#     jne next
#     movzx eax, word ptr [r10+22]
#     cmp eax, 0x65
#     jne next
#     # 偏移 24 处匹配 "_cht"
#     movzx eax, word ptr [r10+24]
#     cmp eax, 0x5F
#     jne next
#     movzx eax, word ptr [r10+26]
#     cmp eax, 0x63
#     jne next
#     movzx eax, word ptr [r10+28]
#     cmp eax, 0x68
#     jne next
#     movzx eax, word ptr [r10+30]
#     cmp eax, 0x74
#     jne next
#     movzx eax, word ptr [r10+32]  # 再判断是否为 _4k 版本
#     cmp eax, 0x5F
#     jne use_cht
#     movzx eax, word ptr [r10+34]
#     cmp eax, 0x34
#     jne use_cht
#     movabs rcx, 0x2222222222222222   # 重定向到 font_package_cht_4k.bin
#     movabs r11, 0x3333333333333333   # 触发标志 = 2 (4k)
#     mov byte ptr [r11], 2
#     jmp done
# use_cht:
#     movabs rcx, 0x1111111111111111   # 重定向到 font_package_cht.bin
#     movabs r11, 0x3333333333333333   # 触发标志 = 1 (普通)
#     mov byte ptr [r11], 1
# done:
#     movabs rax, 0x4444444444444444   # 跳回 CreateFile2 原始序言
#     jmp rax
# next:
#     add r10, 2
#     jmp scan
#
# 机器码中的 0x11.. / 0x22.. / 0x33.. / 0x44.. 是占位地址,
# 安装时分别替换为 cht 路径、4k 路径、触发标志、跳板地址。
STUB = bytes.fromhex(
    '4989ca410fb70285c00f8411010000410fb70283f8660f8510010000410fb742'
    '0283f86f0f8502010000410fb7420483f86e0f85f4000000410fb7420683f874'
    '0f85e6000000410fb7420883f85f0f85d8000000410fb7420a83f8700f85ca00'
    '0000410fb7420c83f8610f85bc000000410fb7420e83f8630f85ae000000410f'
    'b7421083f86b0f85a0000000410fb7421283f8610f8592000000410fb7421483'
    'f8670f8584000000410fb7421683f865757a410fb7421883f85f7570410fb742'
    '1a83f8637566410fb7421c83f868755c410fb7421e83f8747552410fb7422083'
    'f85f7524410fb7422283f834751a48b9222222222222222249bb333333333333'
    '333341c60302eb1848b9111111111111111149bb333333333333333341c60301'
    '48b84444444444444444ffe04983c202e9cefeffff'
)

PLACEHOLDERS = (0x1111111111111111, 0x2222222222222222,
                0x3333333333333333, 0x4444444444444444)


def stub_bytes(cht, k4, flag, tramp):
    code = bytes(STUB)
    for old, new in zip(PLACEHOLDERS, (cht, k4, flag, tramp)):
        pat = struct.pack('<Q', old)
        if pat not in code:
            raise RuntimeError('stub error: %X' % old)
        code = code.replace(pat, struct.pack('<Q', new))
    return code


def absjmp(addr):
    return b'\xff\x25\x00\x00\x00\x00' + struct.pack('<Q', addr)


def plan(h5, func):
    data = h5.read(func, 48)
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64); md.detail = True
    total = 0
    for ins in md.disasm(data, func):
        for op in ins.operands:
            if op.type == cs_x86.X86_OP_MEM and op.mem.base == cs_x86.X86_REG_RIP:
                raise SystemExit('prologue has RIP-relative at +%x, aborting' % (ins.address - func))
        if ins.group(capstone.CS_GRP_JUMP) or ins.group(capstone.CS_GRP_CALL):
            raise SystemExit('prologue has rel branch at +%x, aborting' % (ins.address - func))
        total += ins.size
        if total >= 14:
            return total, data[:total]
    raise SystemExit('prologue too short')


# -------------------------------------------------------------- install ----
def install(h5):
    func = resolve_export(h5, 'kernelbase.dll', 'CreateFile2')
    if not func:
        raise SystemExit('cannot resolve kernelbase!CreateFile2')
    head = h5.read(func, 2)
    if head == b'\xff\x25':
        log('[i] CreateFile2 已装过钩子, 跳过')
        return None
    n, orig = plan(h5, func)
    cave = h5.alloc(0x2000)
    if not cave:
        raise SystemExit('VirtualAllocEx failed')
    cht, k4 = cave, cave + 0x200
    code, tramp, flag = cave + 0x400, cave + 0x800, cave + 0xC00
    h5.write(cht, (CHT + '\0').encode('utf-16-le'))
    h5.write(k4, (CHT4K + '\0').encode('utf-16-le'))
    h5.write(code, stub_bytes(cht, k4, flag, tramp))
    h5.write(tramp, orig + absjmp(func + n))
    h5.write(flag, b'\0')
    patch = absjmp(code) + b'\x90' * (n - 14)
    hs = suspend_threads(h5.pid)
    try:
        h5.write(func, patch)
    finally:
        resume_threads(hs)
    log('[OK] pid=%d  CreateFile2=%X  patch=%dB  hook=%X' % (h5.pid, func, n, code))
    return flag


def main(timeout=120):
    log('[i] 等待 %s (最多 %d 秒) ...' % (MODULE, timeout))
    end = time.time() + timeout
    h5 = None
    while time.time() < end:
        pid = find_pid()
        if pid:
            try:
                h5 = H5(pid)
            except OSError:
                h5 = None
            else:
                if h5.mods.get('kernelbase.dll') and resolve_export(h5, 'kernelbase.dll', 'CreateFile2'):
                    break
                h5 = None
        time.sleep(0.1)
    if h5 is None:
        log('[-] 没等到游戏')
        return

    flag = install(h5)
    if flag is None:
        return
    log('[i] 安装完成, 等待触发')
    while k32.WaitForSingleObject(h5.h, 0) == 0x102:  # WAIT_TIMEOUT
        v = h5.read(flag, 1)
        if v in (b'\x01', b'\x02'):
            h5.write(flag, b'\x00')
            log('[OK] 已重定向 %s' % ('font_package_cht_4k.bin' if v == b'\x02'
                                        else 'font_package_cht.bin'))
            log('[i] 安装成功')
            break
        time.sleep(0.2)
    else:
        log('[-] 未触发重定向，安装失败')


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
