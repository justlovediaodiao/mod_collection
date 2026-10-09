# Final Findings

## Root Cause

Roadie Run camera slowdown is not caused by reduced right-stick input or a changed global sensitivity scale.

Two downstream operations create the discontinuity:

1. `CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C:BlueprintProcessViewRotation` limits horizontal output to an effective 70 degrees/second.
2. Roadie character-orientation synchronization calls `SetControlRotation` after ordinary controller update and restores the slow character-facing Yaw during the transition.

A separate Roadie movement override uses rotation type `1`, restricting sprint
steering during large camera turns. The native default type `2` restores
camera-relative steering.

The ordinary controller acceleration curve remains valid and reaches approximately 411.7 degrees/second. It should be preserved, not replaced with a fixed speed.

## Required Behavior

For the same controller input, horizontal camera response must be identical in ordinary movement, PreRoadieRun, sustained Roadie Run, and the exit transition.

Sprint trajectory must follow large camera turns during Roadie Run.

## Implemented Correction

- Dynamically resolve the target processor class FName in the current process.
- Recover the Yaw removed by the Roadie speed processor at its native wrapper exit.
- Add only that difference to the final camera-chain ViewRotation.
- Pair the ordinary and Roadie `SetControlRotation` calls through synchronized shared state keyed by controller.
- Replace only the later Roadie Yaw with the ordinary per-frame Yaw.
- Map movement rotation type `1` to the native default type `2`.
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
- modifies camera Yaw and movement rotation type only;
- identifies the Blueprint processor by current-process FName rather than a stale UObject address;
- restricts controller synchronization to two verified native caller identities and the same PlayerController;
- validates the original executable bytes before installation;
- preserves movement rotation types other than `1`;
- aborts without patching an unsupported game build.

## Verified Result

With the controller held through ordinary movement into Roadie Run, camera speed remains continuous. The initial sprint slowdown and subsequent speed recovery are removed, and the Roadie camera matches ordinary movement behavior.

Sprint trajectory follows large Roadie camera turns.
