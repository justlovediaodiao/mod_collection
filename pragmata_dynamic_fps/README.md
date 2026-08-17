# PRAGMATA Dynamic FPS

A native REFramework plugin that switches the RTSS frame limit based on the current PRAGMATA UI state:

- Menus and title flow: 60 FPS
- Gameplay: 120 FPS


## Requirements

- Windows x64
- REFramework Nightly
- RTSS with `RTSSHooks64.dll` injected into the game
- Permission to update the PRAGMATA RTSS profile

Run the game and RTSS at the same privilege level. If RTSS is elevated, either run the game as administrator or grant your user write access to:

```text
C:\Program Files (x86)\RivaTuner Statistics Server\Profiles
```

## Install

Copy `pragmata_dynamic_fps.dll` to:

```text
<game>\reframework\plugins\
```

## Build

```powershell
git clone --depth 1 https://github.com/praydog/REFramework.git C:\src\REFramework
cmake -S . -B build -A x64 -DREFRAMEWORK_NIGHTLY_SDK_DIR=C:\src\REFramework
cmake --build build --config Release --parallel
```

The output is `build\Release\pragmata_dynamic_fps.dll`.

## PRAGMATA_JumpHeight.CT

A CheatEngine table to modify jump height.