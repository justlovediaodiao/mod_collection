# Runtime Scripts

Halo 5: Forge is a UWP application, so its installation files cannot be patched
directly because of permission restrictions. These scripts patch the running
game process instead.

Run the script as before launching the game.

## `halo5_font_inject.py`

This script is only needed when playing Halo 5 through Halo 5: Forge. When
playing through Forge, only subtitles are displayed in Simplified Chinese;
other text comes from Forge's own resources and remains Traditional Chinese
because this patch cannot cover it.

The script injects the patched Simplified Chinese font into the game process.
It hooks `kernelbase!CreateFile2` and redirects Traditional Chinese font package
reads to the translated font files.

Requires Python 3 with `capstone`.

```powershell
python .\halo5_font_inject.py
```

## `halo5_forge_crach_fix.py`

After launching Halo 5: Forge, pressing Enter to enter the menu can crash the
game on some PCs. The crash is caused by a bug in the game's font-rendering
cache logic. This script waits for `halo5forge.exe`, applies an in-memory patch
to fix the bug, and then exits.

```powershell
python .\halo5_forge_crach_fix.py
```
