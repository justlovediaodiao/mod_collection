# Borderlands 4 Mod Pack

This directory contains two independent Borderlands 4 mods:

| Mod | Effect |
|---|---|
| `BL4_LootLuck_300` | Sets the `LootLuck` difficulty-balance value to `300`. |
| `BL4_XP_200` | Sets total combat experience gain to `200%` (a `100%` bonus over the base rate). |

The mods can be installed together or used separately.

## Installation

Copy all three files (`.pak`, `.utoc`, and `.ucas`) from each desired mod directory into `OakGame\Content\Paks\`.

To uninstall a mod, remove its matching `.pak`, `.utoc`, and `.ucas` files.

## Custom values

The included PowerShell scripts can create variants with different values.
Run them from this directory with PowerShell 7 (`pwsh`) and use one of the
included mod directories as the source.

Create a loot-luck variant with a value of `500`:

```powershell
pwsh ./make_bl4_lootluck_mod.ps1 500 ./BL4_LootLuck_300
```

Create a variant that grants `300%` total combat XP:

```powershell
pwsh ./make_bl4_xp_mod.ps1 300 ./BL4_XP_200
```

Each script writes a new `BL4_LootLuck_<value>` or `BL4_XP_<value>` directory
without modifying the source files. The XP argument represents the total XP
rate: `100` is the base rate, `200` is double XP, and `300` is triple XP.

## Notes

- [`UE5_IoStore_runtime_extraction_and_patching.md`](UE5_IoStore_runtime_extraction_and_patching.md)
  documents the analysis and fixed-length patching method used for these
  files.
