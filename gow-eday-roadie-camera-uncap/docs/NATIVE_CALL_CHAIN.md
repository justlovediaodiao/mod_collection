# Native Call-Chain Analysis and Update Procedure

## Verified Build Anchors

All values are RVAs from `GoWEDay.exe` unless otherwise stated.

| Symbol or site | RVA | Expected bytes at patched site |
|---|---:|---|
| `FNamePool` | `0xEBA1CC0` | validated by FName 0 = `None` |
| `UObject::ProcessEvent` | `0x171C310` | function entry |
| processor wrapper exit | `0x157C43F` | `C5 F8 77 4C 8D 9C 24 20 01 00 00` |
| processor-chain commit | `0x157C08F` | `C5 F8 77 4C 8D 9C 24 B8 01 00 00` |
| `SetControlRotation` | `0x15588F8` | `48 8B C4 48 89 58 08` |
| ordinary `UpdateRotation` set return | `0x15584E7` | caller identity |
| Roadie orientation-sync set return | `0x20EF6A0` | caller identity |

The C++ mod validates every patched instruction sequence before changing executable memory.

## Runtime AOB Resolution

The RVAs above identify the verified baseline only. The released mod does not
use them for runtime location. It scans executable sections and requires one
module match for each signature.

| Target | AOB | Result offset |
|---|---|---:|
| processor wrapper exit | `C4 E2 E1 B9 D1 C5 FB 11 51 10 C5 F8 77 4C 8D 9C 24 20 01 00 00` | `+10` |
| processor-chain commit | `48 8B CB C5 F8 77 E8 ?? ?? ?? ?? C5 F8 77 4C 8D 9C 24 B8 01 00 00` | `+11` |
| `SetControlRotation` | `48 8B C4 48 89 58 08 57 48 81 EC F0 00 00 00 C5 F8 29 70 E8 C5 FB 10 72 10 C5 F8 29 78 D8 C5 FB 10 7A 08` | `+0` |
| ordinary set return | `48 8B 06 48 8D 55 F7 48 8B CE FF 90 E8 07 00 00 48 8B CE E8 ?? ?? ?? ?? 48 85 C0` | `+16` |
| Roadie set return | `48 8B 07 48 8D 54 24 20 C5 FB 11 54 24 28 48 8B CF C5 F8 77 FF 90 E8 07 00 00 C5 F8 28 74 24 60` | `+26` |

`FNamePool` uses one independently verified signature:

```text
48 8D 1D ?? ?? ?? ?? 0F 1F 00 41 8B 04 24 8B C8 C1 E9 10 0F B7 C0
```

The RIP-relative `lea` resolves `FNamePool.Blocks`; subtracting `0x10`
produces the pool base. The current full-module audit produced one match and
resolved RVA `0xEBA1CC0`. The resolver then requires FName 0 to equal `None`
and requires the target class name to exist before installing hooks.

Signatures relocate unchanged code; they do not make changed machine code or
changed stack layouts compatible. Zero or multiple matches stop installation.

## Loader Initialization

`mod_loader` can load the mod before the campaign package has registered the
target Blueprint class. The mod therefore validates the executable image and
all three original instruction sequences first, then waits on its worker thread
until the current-process FName pool contains the target class. It installs the
three hooks once and never relies on a UObject address from an earlier process.

An executable mismatch is fatal and is never retried. A missing target FName is
treated as normal package-loading state and is retried without patching code.

## Blueprint Dispatch

`CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C:BlueprintProcessViewRotation` is Blueprint bytecode. It has no standalone native function body.

The verified dispatch path is:

```text
processor virtual call
  -> native Blueprint wrapper
  -> UObject::ProcessEvent
  -> Blueprint VM
  -> native wrapper weighting/blending
  -> processor-chain caller
```

The ProcessEvent call is at `0x157C7BE`; its return address is `0x157C7C4`. The containing wrapper spans approximately `0x157C680..0x157C7EF`.

The wrapper caller spans `0x157C0EC..0x157C460`. It calls the Blueprint wrapper at `0x157C24A`, then applies processor weight and per-axis blending. The verified exit site is `0x157C43F`.

At that exit, offsets relative to the current hook RSP are:

```text
+0x170  FRotator* input view
+0x178  FRotator* input delta
+0x180  FRotator* output view
+0x188  FRotator* output delta
```

Yaw is `+0x08` in every FRotator.

## Processor Loop

The outer camera function calls each processor through virtual slot `0x2D0` at `0x157BF40`. The observed sustained Roadie order is:

```text
PitchRestriction_RoadieRun
SpeedLimits_RoadieRun
Pitch_Centering
Ascender
ViewRotationProcessor_Default
```

Observed Yaw behavior:

| Processor | Input/output effect |
|---|---|
| PitchRestriction_RoadieRun | no Yaw delta reduction |
| SpeedLimits_RoadieRun | clamps Yaw delta to 70 degrees/second |
| Pitch_Centering | passes Yaw delta unchanged |
| Ascender | passes Yaw delta unchanged |
| Default | adds delta to view and returns zero delta |

The outer function copies the completed rotations to its output pointers near `0x157BF78..0x157BF8D`. Its final commit site is `0x157C08F`.

## Controller Update Path

The camera function returns into `APlayerController::UpdateRotation` at `0x1558492`.

Relevant sequence:

```text
0x155843D  load RotationInput
0x155846B  obtain current control rotation
0x155848C  call PlayerCameraManager processing (vtable +0x8F0)
0x1558492  return from camera processing
0x15584E1  call SetControlRotation (vtable +0x7E8)
0x15584E7  return from the ordinary control-rotation commit
```

The ordinary commit already contains the corrected full controller response after the processor-chain correction.

## Roadie Orientation Synchronization

A second function beginning at `0x20EF568` reads the player controller and derives a rotation from the character/root transform:

```text
0x20EF5D8  GetControlRotation (vtable +0x7E0)
0x20EF5EE  read transform/quaternion data
0x20EF69A  SetControlRotation (vtable +0x7E8)
0x20EF6A0  return from the second commit
```

This second commit is active during the Roadie transition and attempts to restore the slow character-facing Yaw after ordinary `UpdateRotation` has already produced the correct camera Yaw. It explains why correcting only ProcessEvent or only the processor-chain output does not produce stable visual behavior.

## Verified Numeric Behavior

Typical full-stick samples:

```text
input delta:   approximately 4 to 8 degrees per frame
limited delta: approximately 0.9 to 1.5 degrees per frame
effective cap: exactly 70 degrees/second
ordinary controller curve: rises to approximately 411.7 degrees/second
```

The ordinary controller acceleration curve crosses from ordinary movement into Roadie without resetting. The discontinuity is produced by the Roadie speed processor and the second controller-rotation commit, not by Enhanced Input.

## Final Three-Site Correction

### 1. Processor wrapper exit

Identify the processor by comparing its class FName ID with the current-process ID for:

```text
CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C
```

Capture:

```text
raw = input_delta.yaw
limited = output_delta.yaw
```

### 2. Processor-chain commit

Apply only the removed Yaw amount:

```text
output_view.yaw += raw - limited
```

Pitch and Roll are untouched.

### 3. SetControlRotation pairing

On the ordinary `UpdateRotation` caller (`0x15584E7`), save the controller pointer and requested Yaw for the current thread. On the Roadie orientation-sync caller (`0x20EF6A0`), replace only requested Yaw with that saved value when the controller and thread match.

This pairing covers PreRoadie transition frames before the sustained Roadie processor appears, while preserving the ordinary gamepad response.

## Relocation Procedure After a Game Update

The executable reference implementation is
[`reference/Roadie-CameraUncap.lua`](reference/Roadie-CameraUncap.lua). It uses the
same three sites and correction rules as the C++ mod. Use it as the first live
test after relocating a new build, then transfer only verified values to
`src/mod.cpp` and `src/hooks.asm`.

### Running the Cheat Engine reference

1. Start the game and enter Campaign so the Roadie camera class is registered.
2. Attach Cheat Engine to `GoWEDay.exe`.
3. Execute `docs/reference/Roadie-CameraUncap.lua` from Cheat Engine's Lua engine.
4. Test ordinary movement, PreRoadie, sustained Roadie Run, and exit with a
   controller.
5. Run `RoadieCameraUncap.status()` to write the three counters to the status log.
6. Run `RoadieCameraUncap.stop()` before detaching Cheat Engine or closing it
   while the game remains open.

The script has no timed capture or phase controls. It enables the correction
immediately and writes `Roadie-CameraUncap-status.log` next to the script when it
was loaded with `dofile`; pasted scripts use the current user's temporary
directory. `stop()` records the final counters automatically. The Lua version
uses one shared validation state because the verified camera path executes on
the game thread; the released C++ implementation uses thread-local state and
is the distribution implementation.

After an update, the script must reject the build until the six signatures,
three expected-byte arrays, stolen instruction lengths, stack offsets, and
replayed instructions have all been revalidated. A successful assembly is not sufficient:
all three counters must advance in the appropriate Roadie transitions, and the
controller validation matrix below must pass before updating the C++ source.

### Phase A: re-establish reflection anchors

1. Complete the UE4SS adaptation checklist.
2. Resolve the target Blueprint class and `BlueprintProcessViewRotation` UFunction in the new process.
3. Reconfirm the parameter structure, FRotator size, and current Roadie blackboard key.
4. Reconfirm that `InDeltaRot.Yaw` remains ordinary while `OutDeltaRot.Yaw` is reduced.

### Phase B: relocate Blueprint dispatch

1. Relocate `ProcessEvent` and verify its UObject vtable slot.
2. Filter ProcessEvent by the dynamically resolved target UFunction object.
3. Record the native return address of the target invocation.
4. Use PE exception/unwind entries to obtain the containing wrapper bounds.
5. Identify the caller that applies axis weights and copies output rotations.
6. Derive argument-pointer offsets from the actual call setup; do not reuse `+0x170..+0x188` without confirming the new prologue and frame size.

### Phase C: relocate the outer chain

1. Follow the wrapper caller into the processor iteration loop.
2. Record input/output Yaw before and after every processor.
3. Identify the final copy/commit point after all processors and optional post-processing.
4. Verify that adding `raw - limited` there reaches the caller-local ViewRotation.

### Phase D: relocate controller commits

1. Follow the outer function return into `APlayerController::UpdateRotation`.
2. Identify the ordinary `SetControlRotation` call and record its return address.
3. Trace all later `SetControlRotation` calls on the same controller.
4. Find the call whose requested Yaw advances at the limited rate.
5. Confirm its owning function computes character-facing rotation and is active through the Roadie transition.
6. Update both caller signatures and result offsets used for pairing.

### Phase E: update the mod

1. Update any AOB that no longer resolves uniquely in `src/mod.cpp`.
2. Update all expected original-byte arrays.
3. If a stolen instruction changes, update the corresponding replay sequence in `src/hooks.asm` and its stolen length.
4. Reconfirm all stack offsets and Windows x64 alignment at each detour.
5. Build with the MSVC x64 toolchain.

## Validation Matrix

Test with a controller and hold the same horizontal stick deflection through each transition:

```text
ordinary -> PreRoadieRun -> RoadieRun -> exit
```

Required results:

- no slowdown on the first sprint frame;
- no speed jump when sustained Roadie begins;
- no change when leaving Roadie;
- identical ordinary and Roadie horizontal response;
- unchanged Pitch and Roll;
- no effect in ADS, menus, pause, cover transitions, executions, cinematics, or external camera control;
- stable behavior across map loads and Pawn recreation.

Reject the update if any expected byte differs, any target is outside the image, the target FName cannot be resolved, or paired SetControlRotation calls no longer use the same controller.
