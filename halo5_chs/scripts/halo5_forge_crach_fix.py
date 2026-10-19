"""Apply the Halo 5: Forge font-cache overflow crash fix.

Same patch as halo5forge_fontcrash_patcher, but it waits for halo5forge.exe,
applies the in-memory patch once, then exits.

    original: lea rcx,[r10+0x530]; mov edx,1; call longjmp; int3
    patched : mov rax,<scratch>; add rsp,0x28; ret; nop x3
"""

import ctypes
from ctypes import wintypes
import sys
import time

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)

EXE_NAME = "halo5forge.exe"
PATCH_RVA = 0x2ED738C
BLOCK_SIZE = 18

EXPECTED = bytes(
    [
        0x49, 0x8D, 0x8A, 0x30, 0x05, 0x00, 0x00,  # lea rcx,[r10+0x530]
        0xBA, 0x01, 0x00, 0x00, 0x00,              # mov edx,1
        0xE8, 0xC7, 0x57, 0xB8, 0xFF,              # call longjmp
        0xCC,                                      # int3
    ]
)

TH32CS_SNAPPROCESS = 0x00000002
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_OPERATION = 0x0008
PROCESS_VM_READ = 0x0010
PROCESS_VM_WRITE = 0x0020

LIST_MODULES_ALL = 0x03

MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
PAGE_READWRITE = 0x04
PAGE_EXECUTE_READWRITE = 0x40


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
        ("th32ModuleID", wintypes.DWORD),
        ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD),
        ("pcPriClassBase", ctypes.c_long),
        ("dwFlags", wintypes.DWORD),
        ("szExeFile", wintypes.WCHAR * 260),
    ]


kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
kernel32.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
kernel32.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.ReadProcessMemory.argtypes = [
    wintypes.HANDLE,
    wintypes.LPCVOID,
    wintypes.LPVOID,
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
]
kernel32.WriteProcessMemory.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    wintypes.LPCVOID,
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
]
kernel32.VirtualProtectEx.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    ctypes.c_size_t,
    wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD),
]
kernel32.VirtualAllocEx.restype = wintypes.LPVOID
kernel32.VirtualAllocEx.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    ctypes.c_size_t,
    wintypes.DWORD,
    wintypes.DWORD,
]
kernel32.FlushInstructionCache.argtypes = [
    wintypes.HANDLE,
    wintypes.LPCVOID,
    ctypes.c_size_t,
]
psapi.EnumProcessModulesEx.argtypes = [
    wintypes.HANDLE,
    ctypes.POINTER(wintypes.HMODULE),
    wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD),
    wintypes.DWORD,
]
psapi.GetModuleBaseNameW.argtypes = [
    wintypes.HANDLE,
    wintypes.HMODULE,
    wintypes.LPWSTR,
    wintypes.DWORD,
]


def log(message):
    print(message, flush=True)


def find_process(name):
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == INVALID_HANDLE_VALUE:
        return 0
    try:
        entry = PROCESSENTRY32W()
        entry.dwSize = ctypes.sizeof(entry)
        if kernel32.Process32FirstW(snapshot, ctypes.byref(entry)):
            while True:
                if entry.szExeFile.lower() == name.lower():
                    return entry.th32ProcessID
                if not kernel32.Process32NextW(snapshot, ctypes.byref(entry)):
                    break
    finally:
        kernel32.CloseHandle(snapshot)
    return 0


def find_module_base(process, module_name):
    modules = (wintypes.HMODULE * 1024)()
    needed = wintypes.DWORD()
    if not psapi.EnumProcessModulesEx(
        process,
        modules,
        ctypes.sizeof(modules),
        ctypes.byref(needed),
        LIST_MODULES_ALL,
    ):
        return 0
    count = needed.value // ctypes.sizeof(wintypes.HMODULE)
    for i in range(min(count, len(modules))):
        base_name = ctypes.create_unicode_buffer(260)
        if psapi.GetModuleBaseNameW(
            process, modules[i], base_name, len(base_name)
        ) and base_name.value.lower() == module_name.lower():
            return ctypes.cast(modules[i], ctypes.c_void_p).value
    return 0


def apply_patch(process, base):
    target = base + PATCH_RVA
    current = ctypes.create_string_buffer(BLOCK_SIZE)
    read = ctypes.c_size_t()
    if not kernel32.ReadProcessMemory(
        process, ctypes.c_void_p(target), current, BLOCK_SIZE, ctypes.byref(read)
    ) or read.value != BLOCK_SIZE:
        log("[-] failed to read target memory (error %d)" % ctypes.get_last_error())
        return False
    if current.raw != EXPECTED:
        log("[-] unexpected bytes at target; refusing to patch")
        return False

    scratch = kernel32.VirtualAllocEx(
        process, None, 64, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE
    )
    if not scratch:
        log("[-] VirtualAllocEx failed (error %d)" % ctypes.get_last_error())
        return False

    patch = bytearray(BLOCK_SIZE)
    patch[0:2] = b"\x48\xB8"  # mov rax, imm64
    patch[2:10] = (scratch & 0xFFFFFFFFFFFFFFFF).to_bytes(8, "little")
    patch[10:14] = b"\x48\x83\xC4\x28"  # add rsp,0x28
    patch[14] = 0xC3  # ret
    patch[15:18] = b"\x90\x90\x90"
    patch_bytes = bytes(patch)

    old = wintypes.DWORD()
    if not kernel32.VirtualProtectEx(
        process,
        ctypes.c_void_p(target),
        BLOCK_SIZE,
        PAGE_EXECUTE_READWRITE,
        ctypes.byref(old),
    ):
        log("[-] VirtualProtectEx failed (error %d)" % ctypes.get_last_error())
        return False

    written = ctypes.c_size_t()
    ok = kernel32.WriteProcessMemory(
        process,
        ctypes.c_void_p(target),
        patch_bytes,
        BLOCK_SIZE,
        ctypes.byref(written),
    )
    kernel32.VirtualProtectEx(
        process, ctypes.c_void_p(target), BLOCK_SIZE, old.value, ctypes.byref(old)
    )
    if not ok or written.value != BLOCK_SIZE:
        log("[-] WriteProcessMemory failed (error %d)" % ctypes.get_last_error())
        return False
    kernel32.FlushInstructionCache(process, ctypes.c_void_p(target), BLOCK_SIZE)
    return True


def patch_process(pid):
    process = kernel32.OpenProcess(
        PROCESS_QUERY_INFORMATION
        | PROCESS_VM_OPERATION
        | PROCESS_VM_READ
        | PROCESS_VM_WRITE,
        False,
        pid,
    )
    if not process:
        log("[-] OpenProcess failed (error %d)" % ctypes.get_last_error())
        return False
    try:
        base = find_module_base(process, EXE_NAME)
        if not base:
            return None
        log("[*] module base 0x%X, target 0x%X" % (base, base + PATCH_RVA))
        if apply_patch(process, base):
            log("[+] patched")
            return True
        return False
    finally:
        kernel32.CloseHandle(process)


def main(timeout=120):
    log("Halo 5: Forge font-crash fix")
    log("[i] waiting for %s (up to %d seconds) ..." % (EXE_NAME, timeout))

    end = time.time() + timeout
    while time.time() < end:
        pid = find_process(EXE_NAME)
        if pid:
            result = patch_process(pid)
            if result is not None:
                return 0 if result else 1
        time.sleep(0.2)
    log("[-] timed out waiting for the game")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
