# Halo CE Cinematic Frame Generation Mod

## Installation

1. Install [UE4SS for Halo Campaign Evolved](https://www.nexusmods.com/halocampaignevolved/mods/9) for the game.

2. Create the following directory inside the UE4SS `ue4ss\Mods\` directory:

   ```text
   CinematicFGFix\Scripts
   ```

3. Copy [`main.lua`](main.lua) into the `Scripts` directory.

4. Create an empty `enabled.txt` file in the `CinematicFGFix` directory.

5. Start the game and enable NVIDIA frame generation in the graphics settings.

The final directory structure should be:

```text
ue4ss\
└── Mods\
    └── CinematicFGFix\
        ├── enabled.txt
        └── Scripts\
            └── main.lua
```

## Configuration

Open `main.lua` and edit these values near the top of the file:

```lua
local CINEMATIC_VIDEO_FPS = 30
local FRAME_GENERATION_MULTIPLIER = 2
```

- Set `CINEMATIC_VIDEO_FPS` to the frame rate of the cinematic videos. Keep it at `30` for the original videos, or set it to `60` when using the 60 FPS videos from A Lot of Videos for Campaign Evolved.
- Set `FRAME_GENERATION_MULTIPLIER` to the frame-generation mode: `2` for 2x, `3` for 3x, or `4` for 4x frame generation...
