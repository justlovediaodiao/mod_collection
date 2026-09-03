# Borderlands 4 Mod Pack

This directory contains one combined Borderlands 4 mod:

| Mod | Effect |
|---|---|
| `BL4_XP_200_LootLuck_300` | Sets total combat experience gain to `200%` (a `100%` bonus over the base rate) and the `LootLuck` value to `300`. |

## Installation

Copy all three files (`.pak`, `.utoc`, and `.ucas`) from
`BL4_XP_200_LootLuck_300` into `OakGame\Content\Paks\`.

To uninstall the mod, remove its matching `.pak`, `.utoc`, and `.ucas` files.

## Custom values

The included PowerShell script can create variants with different XP and loot
luck values. Run it from this directory with PowerShell 7 (`pwsh`) and use the
included mod directory as the source.

Create a variant with `300%` total combat XP and a `LootLuck` value of `500`:

```powershell
pwsh ./make_bl4_xp_loot_mod.ps1 300 500 ./BL4_XP_200_LootLuck_300
```

The arguments are the total XP percentage, the `LootLuck` value, and the source
directory, in that order. The script writes a new
`BL4_XP_<XPPercent>_LootLuck_<LootLuck>` directory without modifying the source
files. An XP value of `100` is the base rate, `200` is double XP, and `300` is
triple XP.

## Notes

- [`UE5_IoStore_runtime_extraction_and_patching.md`](UE5_IoStore_runtime_extraction_and_patching.md)
  documents the analysis and fixed-length patching method used for these
  files.
