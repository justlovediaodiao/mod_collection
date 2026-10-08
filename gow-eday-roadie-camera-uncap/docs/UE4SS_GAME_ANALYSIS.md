# UE4SS Game Analysis

## Role of UE4SS

UE4SS reflection established the object identities, state tags, Blueprint class, properties, UFunction layout, and blackboard key that led to the native investigation. The released mod does not load UE4SS.

## Verified Runtime Objects

```text
PlayerController
/Game/Fairlight/Gameplay/BlueprintClasses/Controllers/
BP_PlayerController_Campaign.BP_PlayerController_Campaign_C

Pawn
BP_Pawn_Marcus_Casual_Holster_C

CameraManager
PlayerCameraManager_CamBridge_BP_C
native base: TCPlayerCameraManager_CamBridge

Movement
FLCharacterMovementContextComponent
Pawn.CharacterMovement
native base: TCCharacterMovementContextComponent

Input handler
InputHandler_Hero_BP_C
native base: TCInputHandler

PlayerInput
TCEnhancedPlayerInput

InputComponent
TCEnhancedInputComponent

Input subsystem
EnhancedInputLocalPlayerSubsystem
```

Runtime UObject addresses and exported JMap addresses are process-local and must never be reused after a restart.

## State Identification

A real Roadie Run frame has both states:

```text
PawnState.Sprinting
PawnState.RoadieRun
```

`PawnState.PreRoadieRun` is the entry transition and must be kept separate from the sustained Roadie Run state.

Useful protection states discovered through reflection include:

```text
PawnState.Targeting
PawnState.IsScoped
CharacterMovement.bIsTargetting
IsGamePaused
IsLookInputIgnored
ShouldLockControlRotation
PawnInputHandler.bUseExternalLookInputs
PawnInputHandler.bWasPaused
TCInput.InputMode.Game
Pawn.AnimInfoCover.CurrentState
```

`FairlightCoverComponent.CurrentCoverState == 0` is not a valid no-cover test in this build; the observed no-cover value is 9. `PawnState.Allow.EnterInteract` is an ability tag, not proof of active interaction.

## Input Findings

For `PawnInputHandler.CachedLastLookInputs`:

```text
Y = horizontal look input
X = vertical look input
```

`InputYawScale` remained 2.5 across the ordinary, PreRoadieRun, RoadieRun, and exit states. The right-stick horizontal input did not drop by half during Roadie Run.

Recorded frames with comparable input showed approximately:

```text
ordinary camera: 130 degrees/second
Roadie Run camera: 65 degrees/second
```

This placed the defect after input generation.

## Target Camera Processor

Class path:

```text
/Game/Fairlight/Gameplay/Camera/Characters/Common/Blueprints/
ViewRotationModifiers/CamBridge_ViewProcessor_SpeedLimits_RoadieRun.
CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C
```

Native base:

```text
/Script/TCCamBridge.TCCamBridgeViewProcessor
```

Instances are stored in the CameraManager `ViewRotationProcessors` array.

Verified reflected properties:

| Property | Type | Offset | Default |
|---|---|---:|---:|
| `Blackboard` | UObject | `0x90` | N/A |
| `Pitch Speed Key` | struct | `0x98` | N/A |
| `DefaultYawSpeed` | double | `0xA8` | 65.0 |
| `DefaultPitchSpeed` | double | `0xB0` | 50.0 |

## BlueprintProcessViewRotation

The function receives:

```text
DeltaTime
CamBridgeActor
TargetActor
InViewRotation
InDeltaRot
OutViewRotation
OutDeltaRot
```

Relevant reflected local variables:

```text
YawSpeedKey       offset 0x78
MaxYawSpeed       offset 0x88
CurrentYawSpeed   offset 0x90
```

The complete parameter/local frame is `0x1F8` bytes in the verified build. UE5 `FRotator` contains three doubles:

```text
+0x00 Pitch
+0x08 Yaw
+0x10 Roll
```

Verified Yaw locations in the frame:

```text
InViewRotation.Yaw  = Params + 0x20
InDeltaRot.Yaw      = Params + 0x38
OutViewRotation.Yaw = Params + 0x50
OutDeltaRot.Yaw     = Params + 0x68
MaxYawSpeed         = Params + 0x88
CurrentYawSpeed     = Params + 0x90
```

The `MaxYawSpeed` and `CurrentYawSpeed` offsets are Blueprint frame locals. They are not persistent processor fields and must not be treated as durable state after the call returns.

## Blackboard Key

The Blueprint bytecode constant for `YawSpeedKey` resolves to:

```text
Camera.Tuning.RoadieRun.MaxYawSpeed
```

`GetSpeedLimitValue` implements:

```text
if BlackboardContainsKey(Blackboard, BBKey):
    ValueOut = TCGameplayBlackboardDataType_Float.GetBlackboardValue(...)
else:
    ValueOut = FallbackValue
```

The reflected fallback is 65, while the effective runtime native clamp measured later is exactly 70 degrees/second. The active blackboard or cached runtime value therefore overrides the Blueprint default in the tested session.

## Rejected Data-Level Adjustments

These writes succeeded but did not change camera behavior:

```text
active processor DefaultYawSpeed: 65 -> 1000
PawnInputHandler.InputOwnerBlackboard
Camera.Tuning.RoadieRun.MaxYawSpeed: 70 -> 1000
```

`PawnInputHandler.InputOwnerBlackboard` is not sufficient evidence for the blackboard consumed by the active processor, and a successful write is not evidence that the camera chain used the value.

## UE4SS-to-Native Handoff

The native investigation begins from these UE4SS results:

1. Exact class: `CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C`.
2. Exact function: `BlueprintProcessViewRotation`.
3. Exact state split: ordinary, PreRoadieRun, RoadieRun, and exit.
4. Exact FRotator parameter layout.
5. Evidence that input is intact and the reduction occurs in the camera processing chain.

The next step is to resolve the current-process UFunction, observe it through `ProcessEvent`, then follow the native wrapper and its callers. Do not search for a standalone x64 implementation of the Blueprint function.
