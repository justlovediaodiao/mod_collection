# MEC BeatLink AutoConnect

A native mod_loader mod for Mirror's Edge Catalyst:

- Automatically connects BeatLink when the game starts.
- Blocks game-window topmost requests through `SetWindowPos`.

## Requirements

- Windows x64
- [mod_loader](https://github.com/justlovediaodiao/mod_loader)
- [BeatLink](https://github.com/synthic/BeatLink)

The helper uses BeatLink's existing runtime. No separate .NET installation is required.

## Install

Follow the mod_loader installation instructions, then copy the `mods/` folder from the build artifact to the game directory:

```text
<game>\mods\beatlink_auto.dll
<game>\mods\config.ini
```

If `config.ini` already exists, merge the `[beatlink_auto]` section.

Copy `helper/BeatLinkAutoConnect.exe` next to `BeatLink.exe`, then set its absolute path in `mods/config.ini`:

```ini
[beatlink_auto]
path=D:\Apps\BeatLink\BeatLinkAutoConnect.exe
```

If the path contains Chinese characters, save the INI file as UTF-16 LE.

Log in through BeatLink once before starting the game to save your authentication token.

Logs: `<game>\mod.log` and `<BeatLink>\BeatLinkAutoConnect.log`.

## Build

Requires the Visual Studio C++ desktop tools, Windows SDK, CMake 3.24+, and .NET 10 SDK. Run from this project directory:

```powershell
cmake -S . -B build -A x64
cmake --build build --config Release --parallel
dotnet publish helper/BeatLinkAutoConnect.csproj --configuration Release --output build/helper
```

Outputs: `build\Release\beatlink_auto.dll` and `build\helper\BeatLinkAutoConnect.exe`.

The **MEC BeatLink AutoConnect** GitHub Actions workflow packages the mod and config under `mods/`, and the single helper EXE under `helper/`. 


## UI AutoScale Mod

[Mirrors_Edge_Catalyst_UI_AutoScale.fbmod](Mirrors_Edge_Catalyst_UI_AutoScale.fbmod) enables UI scaling in Mirror's Edge Catalyst for high-resolution displays.

Install this mod using **FrostyModManager**:

1. Open FrostyModManager and select Mirror's Edge Catalyst.
2. Import `Mirrors_Edge_Catalyst_UI_AutoScale.fbmod` and apply it to the game.
3. Launch the game through FrostyModManager with the mod enabled.