# Borderlands 4 Dynamic FPS

A native `mod_loader` mod for Borderlands 4.

- NVIDIA frame generation inactive: 60 FPS
- NVIDIA frame generation actively presenting generated frames: 120 FPS

The mod queries the game's NVIDIA Streamline DLSS-G state and checks the number
of frames actually presented. It updates the RTSS limit for the current game
profile based on whether generated frames are really being inserted.

## Requirements

- [mod_loader](https://github.com/justlovediaodiao/mod_loader)
- RivaTuner Statistics Server (RTSS) running while the game is running
- An NVIDIA GPU supported by the game's DLSS Frame Generation implementation

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
```

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
