# FH2 Impulse Triggers

Enables impulse trigger vibration for Forza Horizon 2 running on Azimuth.

## Requirements

- Windows x64 and Azimuth 0.9.7.
- An Xbox controller with impulse triggers. The mod uses the first controller in the Windows gamepad list.
- [mod_loader](https://github.com/justlovediaodiao/mod_loader).

## Installation

1. Install mod_loader next to `azimuth.exe`.
2. Copy `fh2_impulse_triggers.dll` into the `mods` directory beside `azimuth.exe`.

## Build

Requires Visual Studio C++ desktop tools, Windows SDK and CMake 3.20+.
Run from this project directory:

```powershell
cmake -S . -B build -A x64
cmake --build build --config Release --parallel
```

The **Build fh2_impulse_triggers** GitHub Actions workflow uploads only the DLL.
