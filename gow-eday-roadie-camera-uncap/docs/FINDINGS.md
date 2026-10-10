# Final Findings

## Root Cause

Roadie Run camera slowdown is not caused by reduced right-stick input or a changed global sensitivity scale.

Two downstream operations create the discontinuity:

1. `CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C:BlueprintProcessViewRotation` limits horizontal output to an effective 70 degrees/second.
2. Roadie character-orientation synchronization calls `SetControlRotation` after ordinary controller update and restores the slow character-facing Yaw during the transition.

A separate Roadie movement override uses rotation type `1`, restricting sprint
steering during large camera turns. Changing the Roadie tuning value to the
native default type `2` restores sprint steering. Ordinary movement also uses
type `1`, so a global getter override can alter ordinary facing and block firing
when the character faces away from the aim direction.

The ordinary controller acceleration curve remains valid and reaches approximately 411.7 degrees/second. It should be preserved, not replaced with a fixed speed.

## Implemented Correction

- Dynamically resolve the target processor class FName in the current process.
- Recover the Yaw removed by the Roadie speed processor at its native wrapper exit.
- Add only that difference to the final camera-chain ViewRotation.
- Pair the ordinary and Roadie `SetControlRotation` calls by controller, replacing
  only the later Roadie Yaw with the ordinary per-frame Yaw.
- Before the native rotation-stack push, map `1` to `2` only for
  `FairlightMovementContextRoadieRunTuning`, identified by its current-process FName.
- Preserve Pitch, Roll, Enhanced Input, dead zones, sensitivity, and the normal gamepad acceleration curve.

## Why Simpler Changes Fail

- Changing `DefaultYawSpeed` does not control an active cached or blackboard-provided value.
- Writing the Pawn input handler blackboard does not prove that the active camera processor consumes that object.
- Editing ProcessEvent output after Blueprint execution is overwritten by native wrapper blending and later control-rotation synchronization.
- Editing only the processor-chain final view does not cover the PreRoadie transition or the second controller commit.
- Input-layer scaling would alter ordinary controller behavior and unrelated camera modes.

## Runtime Scope

The released C++ mod:

- has no UE4SS or Cheat Engine runtime dependency;
- identifies the Blueprint processor by current-process FName rather than a stale UObject address;
- restricts controller synchronization to two verified native caller identities and the same PlayerController;
- requires unique executable AOB matches containing the original hook bytes;
- leaves the global movement getter, non-Roadie tuning, and rotation types other than `1` unchanged;
- installs no hooks if signature resolution fails.

## Verified Result

With the controller held through ordinary movement into Roadie Run, camera speed remains continuous. The initial sprint slowdown and subsequent speed recovery are removed, and the Roadie camera matches ordinary movement behavior.

Sprint trajectory follows large Roadie camera turns.
