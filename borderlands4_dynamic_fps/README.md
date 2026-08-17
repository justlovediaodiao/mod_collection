# Borderlands 4 Dynamic FPS

A native `mod_loader` mod for Borderlands 4.

- Menus: 60 FPS
- Gameplay: 120 FPS
- Works with keyboard, mouse, and controller input

The mod hooks the game's verified Unreal Engine `MenuOpen` and `MenuClose`
functions and updates the RTSS frame limit for the current game profile.

## Requirements

- [mod_loader](https://github.com/justlovediaodiao/mod_loader)
- RivaTuner Statistics Server (RTSS) running while the game is running
- `unrealsdk.dll` from the OAK2 SDK

The GitHub Actions artifact includes both the mod and the required
`unrealsdk.dll`.

## Installation

Extract the artifact into:

```text
Borderlands 4/OakGame/Binaries/Win64/
```

The resulting layout must be:

```text
Win64/
|-- mods/
|   `-- borderlands4_dynamic_fps.dll
`-- Plugins/
    `-- unrealsdk.dll
```

Do not remove `Plugins/unrealsdk.dll`; the mod requires it at runtime.

## RTSS profile permissions

The game process must be able to update its RTSS profile. Ensure that your
Windows user has **Modify** permission for:

```text
C:\Program Files (x86)\RivaTuner Statistics Server\Profiles
```

You can set this through **Properties > Security > Edit**, then grant your user
or the `Users` group **Modify** permission. If the game profile already exists,
also verify the permissions of its `.cfg` file. Without write permission, the
mod may load normally while the frame limit never changes.

## Building

Use Visual Studio with the C++ workload and CMake:

```text
cmake -S . -B build -A x64
cmake --build build --config Release
```

Output:

```text
build/Release/borderlands4_dynamic_fps.dll
```
