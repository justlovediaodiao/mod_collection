# UE4SS Adaptation Guide

## Purpose

UE4SS is the reflection and discovery environment for this game. It is not a runtime dependency of the released C++ mod. This document records the compatibility changes required to restore reflection after either the game or UE4SS changes.

## Verified Baseline

| Item | Verified value |
|---|---|
| Engine | Unreal Engine 5.6.1 |
| Configuration | Shipping, STATS disabled |
| Game changelist | 4894958 |
| UE4SS | `v3.0.1-1161-g6eb3d9bc` |
| Game module | `GoWEDay.exe` |

All addresses, hashes, signatures, structure offsets, and vtable slots in this document are build-specific.

## UE4SS IAT Guard

The baseline UE4SS DLL crashes in `PLH::IatHook::FindIatThunkInModule` while walking a malformed or nonstandard import descriptor. The failing module can expose one or more of these conditions:

- `OriginalFirstThunk == 0`;
- an import RVA outside `OptionalHeader.SizeOfImage`;
- a resolved thunk or import-name RVA outside the mapped image.

Verified original UE4SS DLL:

```text
SHA256 F176DC36FD2BC7B8211DDE6BA54ADE6F66DA5C8F3A79E3017A85B45C215E8242
```

Verified function and patch sites:

```text
PLH::IatHook::FindIatThunkInModule RVA: 0xC1F6B0
RVA 0xC1F7E4 expected: 45 8B 3C 24 48 8B 4D 28
RVA 0xC1F806 expected: 48 85 C0 78 57
```

The compatibility patch adds two guards before any `base + RVA` dereference:

1. Reject a zero `OriginalFirstThunk` and any RVA greater than or equal to `SizeOfImage`.
2. Apply the same upper-bound check to the resolved thunk/name RVA.

Equivalent source-level behavior is:

```cpp
if (descriptor.OriginalFirstThunk == 0 ||
    descriptor.OriginalFirstThunk >= image_size) {
    return not_found;
}

if (resolved_rva >= image_size) {
    return not_found;
}
```

The verified binary patch stores the guards in an executable `.iatfix` section
and redirects only the two checked instruction sites. Its first invalid-entry
exit rejoins at RVA `0xC1F89D`; valid entries rejoin at `0xC1F7EC`. The second
guard rejects an out-of-image result through RVA `0xC1F862` and resumes valid
parsing at RVA `0xC1F80B`.

The verified patched DLL hash is:

```text
SHA256 35FDD9DB1C08EAA7698154262CFF88D4A48830A13CAA3BA22F929C3EA86D2D7B
```

An invalid import entry must be treated as not found. Do not fabricate an address or skip validation for the entire module.

### Reapplying the guard to a new UE4SS version

1. Preserve the untouched DLL and record its SHA-256 hash.
2. Confirm from a crash dump that the failure remains in the IAT import walk.
3. Locate `PLH::IatHook::FindIatThunkInModule` using the matching PDB. Without symbols, locate the loop over `IMAGE_IMPORT_DESCRIPTOR` and the read of `OriginalFirstThunk`.
4. Trace every import RVA through `module_base + RVA` to the first dereference.
5. Add `RVA != 0` and `RVA < SizeOfImage` checks before each dereference.
6. Record the new function RVA, injection RVAs, expected original bytes, input hash, and output hash.
7. Refuse to patch when either the input hash or expected bytes differ.
8. Verify the resulting PE section table, `SizeOfImage`, `SizeOfCode`, and every injected relative branch.

First test an official newer UE4SS DLL without modification. Do not carry the binary patch forward when upstream already fixed the parser.

## Dynamic FUObjectArray

The game does not keep `FUObjectArray` at a stable image RVA. `UObjectBase::AllocateUObjectIndex` reads an encoded global pointer and decodes it with XOR.

Verified signature:

```text
48 8B 0D ?? ?? ?? ?? 48 BB 99 69 8D B8 2A 65 85 5F 48 33 CB 75 2B B9 B8 00 00 00
```

Verified decode:

```text
global = match + 7 + *(int32_t*)(match + 3)
encoded = *(uint64_t*)global
FUObjectArray = encoded XOR 0x5F85652AB88D6999
```

Verified count fields:

```text
FUObjectArray + 0x20 = MaxElements
FUObjectArray + 0x24 = NumElements
```

Accept the result only when:

```text
0x10000 <= pointer < 0x0000800000000000
1 <= NumElements <= MaxElements <= 100000000
```

### Relocating after a game update

1. Locate the `UObjectBase::AllocateUObjectIndex` path.
2. Find its RIP-relative read of the object-array global.
3. Follow all pointer transformations before the value is used. Re-derive XOR, ADD, rotate, or other decoding operations; never reuse the old constant without confirming the instructions.
4. Build a signature from stable surrounding instructions and wildcard only address-dependent displacement bytes.
5. Reconfirm `MaxElements`, `NumElements`, and object storage offsets against the updated engine layout.
6. Require a unique validated result.
7. Test at least two fresh launches. The heap address should change while object counts remain plausible.

## ProcessEvent Layout

Verified `UObject::ProcessEvent` information:

```text
RVA: 0x171C310
vtable slot: 77 (zero based)
vtable byte offset: 0x268
```

Slot 76 is a trivial return function and is not `ProcessEvent`.

For the verified UE4SS layout, the `[UObject]` section contains the deleting destructor, 76 placeholder entries, and then `ProcessEvent`. Unknown neighboring functions must remain placeholders.

### Relocating after a game update

1. Obtain a valid UObject and its vtable.
2. Locate the engine function that receives `UObject*`, `UFunction*`, and parameter memory and dispatches native or script functions.
3. Find that function in the UObject vtable and calculate `slot * 8`.
4. Disassemble adjacent entries and reject destructors, reference collectors, and trivial returns.
5. Validate the selected slot with a read-only BlueprintPure call that returns a known value.
6. Recheck the slot even when the reported Unreal Engine version is unchanged.

## Required UE4SS Settings

Use these values as the safe baseline:

```ini
[EngineVersionOverride]
MajorVersion = 5
MinorVersion = 6
DebugBuild = false
Stats = false

[General]
bUseUObjectArrayCache = false
bForceGUObjectArrayForIteration = true
DefaultExecuteInGameThreadMethod = EngineTick

[Hooks]
HookEngineTick = 1
HookProcessInternal = 0
HookProcessLocalScriptFunction = 0
HookUObjectProcessEvent = 0
HookProcessConsoleExec = 0
```

Enable one additional hook at a time during validation. Do not enable the full hook set as a first compatibility test.

## Lua Threading Rules

UObject enumeration and property access must run on the game thread:

```lua
ExecuteInGameThread(function()
    -- UObject work
end)
```

For repeated work, schedule the next game-thread callback from the current callback. Do not combine asynchronous Lua state callbacks such as `LoopAsync` or `RegisterKeyBindAsync` with UObject access in this build. Use synchronous `RegisterKeyBind`, then enter the game thread from its callback.

## Acceptance Criteria

An adaptation is complete only when all of the following pass:

1. The IAT guard strictly matches the recorded input DLL and original instructions.
2. The dynamic object-array signature produces plausible counts on multiple launches.
3. Local PlayerController, Pawn, CameraManager, movement, and Enhanced Input objects enumerate successfully.
4. The ProcessEvent slot passes a real read-only UFunction call.
5. EngineTick callbacks survive map changes and Pawn recreation.
6. Capture logs contain no `READ_ERROR`, Lua registry corruption, or accidental full JMap export.
7. Campaign gameplay, camera control, pause, and resume remain stable.

The verified baseline produced 244 samples with no read errors.

## Update Scope

- Game-only update: relocate `FUObjectArray`, engine structure offsets, ProcessEvent, Blueprint layouts, and native RVAs.
- UE4SS-only update: retest the official DLL, then reapply only the IAT guard if the same parser defect remains.
- Game and UE4SS update: treat every binary patch, signature, structure offset, vtable layout, and native RVA as invalid until revalidated.
