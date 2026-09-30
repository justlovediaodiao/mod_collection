# FH6 Save Tools

A Collection Journal save tool for Forza Horizon 6. It can inspect items, build an edit plan, update completion states and points, verify encryption, and write the modified save back.

## Files

| File | Purpose |
|---|---|
| `Start-Session.ps1` | Back up save files and create a working directory for the operation |
| `Crypto.ps1` | Use Forza Crypto Tool to decrypt, encrypt, and verify the encrypted result |
| `Analyze.ps1` | Read the Collection Journal and game definitions, and list unfinished items |
| `New-Plan.ps1` | Select items, calculate point changes, and include linked category completion items |
| `Edit.ps1` | Apply the plan to the plaintext save and verify the result |
| `Apply.ps1` | Write the modified save back or restore the original files |
| `Inspect.ps1` | Inspect the save structure and game definitions separately |
| `Common.ps1` / `Strings.ps1` | Shared operations and localized name lookup |
| `Inspector.cs` / `JournalEditor.cs` | Save structure inspection and item editing |
| `vendor/Fh6ProfileEditorDocument.cs` | FH6 plaintext save parser |

## Requirements

- The scripts use **pwsh 7**.
- Download `ForzaCryptoTool.exe` from [Forza Crypto Tool](https://github.com/DVS-code/Forza-Crypto-Tool/releases) for decryption and encryption. The client uses an online service and uploads a save copy or edited plaintext. Analysis and editing run locally.
- Supply the game installation directory. It must contain `media/ObjectModelGame.zip` and `media/Stripped/StringTables/EN.zip` for item definitions and English names.
- Supply the current save directory. It must contain `C_ProfileData` and `C_ProfileData_SCopy`.

The editor currently supports unfinished items with one objective, progress type 1, and a 75-byte record. Unsupported formats or inconsistent point totals stop the operation.

## Usage

**Back up → Decrypt → Analyze → Select items → Edit → Encrypt and verify → Write back**.

Open pwsh 7 in the repository directory and replace these paths:

```powershell
$gameDirectory = '<game installation directory>'
$saveDirectory = '<current save directory>'
$cryptoTool = '<full path to ForzaCryptoTool.exe>'
$workDirectory = Join-Path $PWD ('sessions\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$sessionPath = Join-Path $workDirectory 'session.json'
```

### 1. Back up

Exit the game normally and wait for it to finish saving, then run:

```powershell
.\Start-Session.ps1 -SaveDirectory $saveDirectory -OutputDirectory $workDirectory
```

The script backs up the main save, its synchronized copy, and `C_ProfileBackup` if present. It records the SHA256 of each original file. The output directory must not exist yet.

Use the current save and a new working directory for every operation. Saving in the game can change the version directory, so check the save path again each time.

### 2. Decrypt and analyze

```powershell
.\Crypto.ps1 -Mode Decrypt -SessionPath $sessionPath -CryptoToolPath $cryptoTool
.\Analyze.ps1 -SessionPath $sessionPath -GameDirectory $gameDirectory
```

Results are written to `$workDirectory`:

| File | Contents |
|---|---|
| `original.bin` | Original plaintext save |
| `collection.json` | All items, category points, currency buckets, and the source file hash |
| `unfinished.json` / `unfinished.md` | Unfinished items and their IDs |
| `inspection/` | Save structure and extracted game definitions |

Item names use English by default. To read another installed string table, pass its language code, for example `-Language CHS` or `-Language JP`.

View unfinished items:

```powershell
$collection = Get-Content (Join-Path $workDirectory 'collection.json') -Raw | ConvertFrom-Json
$collection.Items |
    Where-Object { -not $_.Completed } |
    Select-Object Campaign, Category, Name, Reward, CollectionItemId, SupportedEditable, StatusReliable |
    Format-Table -Wrap
```

- `SupportedEditable`: the record meets the editor format requirements.
- `StatusReliable`: the points calculated from completed items match the category points stored in the save.

The plan builder requires both values to be true. When a category has all its points, its items are treated as collected. This avoids reporting lower-stage objectives as unfinished when a higher stage has superseded them.

### 3. Select items

Copy the `CollectionItemId` values of the items you want to complete:

```powershell
$ids = @(
    '<first item ID>'
    '<second item ID>'
)

.\New-Plan.ps1 -SessionPath $sessionPath -ItemId $ids -IncludeCategoryCompletions
Get-Content (Join-Path $workDirectory 'plan.json')
```

You can also filter by category and item names, then pass their IDs:

```powershell
$category = '<category name>'
$names = @('<first item name>', '<second item name>')
$selected = @($collection.Items | Where-Object {
    $_.Category -eq $category -and $_.Name -in $names -and (-not $_.Completed)
})

$selected | Select-Object Category, Name, Reward, CollectionItemId | Format-Table
.\New-Plan.ps1 -SessionPath $sessionPath -ItemId ([string[]]$selected.CollectionItemId) -IncludeCategoryCompletions
```

Different categories can contain items with the same name. The actual edit always uses IDs.

`plan.json` contains item identities, current and target progress, and currency values before and after the edit. Review the plan before applying it. Scripts stop if an output already exists.

#### Linked category completion items

Editing a save does not trigger the completion events that occur during normal gameplay. When a category becomes complete, its matching item in the Horizon Legend category may still hold an old count.

`-IncludeCategoryCompletions` finds categories that reach their maximum points after the edit, adds the corresponding Horizon Legend items from the same campaign, and includes their reward points. Target counts come from game definitions; they are not all set to 1.

To fix only linked items, select their IDs directly. The final, self-referencing Horizon Legend item is excluded from automatic linking.

### 4. Edit the plaintext

```powershell
.\Edit.ps1 -SessionPath $sessionPath -PlanPath (Join-Path $workDirectory 'plan.json')
```

This creates `edited.bin` and `edit-report.json`. The tool checks that:

- The source hash matches the plan.
- Item, challenge, and objective identities and current states match the expected values.
- Serialization before and after editing can be parsed again without changes.
- Binary differences occur only in the selected item state regions.
- BXML changes are limited to the specified currency attributes, with the tree structure preserved.
- The property section, database section, and other binary records retain their original bytes.

Points are calculated from each item reward. Both category points and the campaign total are updated.

### 5. Encrypt and verify

```powershell
.\Crypto.ps1 -Mode Encrypt -SessionPath $sessionPath -CryptoToolPath $cryptoTool
```

After creating `C_ProfileData_modified`, the tool decrypts it again into `roundtrip.bin`. Its SHA256 must match `edited.bin` before `verification.json` is created.

Client logs are stored as `*.stdout.txt` and `*.stderr.txt` in the working directory. Check them if an operation fails. Do not skip verification before writing back.

### 6. Write back

Make sure the game has fully exited, then run:

```powershell
.\Apply.ps1 -SessionPath $sessionPath
```

The script checks that the current files still match the originals backed up at the start. It then writes `C_ProfileData` and `C_ProfileData_SCopy` and checks their hashes. If writing fails, it attempts to restore both original files from the backup.

If the current save has changed, the script stops. Back up the latest save and restart from decryption.

Launch the game and check the items, category points, and linked completion states. Save normally and load again to confirm that the changes persist. A matching encryption roundtrip proves that encryption preserved the edit; the tool does not modify reward claim history or progression thread levels.

## Restore a backup

```powershell
.\Apply.ps1 -SessionPath $sessionPath -Restore
```

Restoring requires the game to be closed and both current files to still match the modified copy from this operation. After another game save, changed paths or hashes may prevent this shortcut from restoring, so newer progress is not overwritten.

## Data structures and extensions

### Plaintext save

The plaintext contains four sections:

| Section | Contents | Operation |
|---|---|---|
| `profile` | Player property tree | Preserve |
| `savestate` | BXML state tree | Update `Total` in the specified currency buckets |
| `binary` | Career record list | Update the selected Collection Journal items |
| `database` | SQLite database | Preserve the original bytes |

The Collection Journal binary record is located by the name `CollectionCampaignSaveState` and serializer `BaseChallengeSaveState`. Fixed record ordinals and absolute offsets are not used.

### Item definitions

Game assets with an `.xml` extension actually contain BXML. The tool first parses `source/manifest.xml` inside `ObjectModelGame.zip`, then locates campaign, category, collection item, and challenge definitions by type.

`Challenges/Key` in a category list is a `CollectionItemId`. `Challenge/Key` inside a collection item is a `ChallengeId`. These are different IDs. Objective definitions supply the `GoalId`, stat threshold, and comparison method.

Names are resolved using `.str` files in the selected language ZIP. The default is `EN.zip`.

### Supported objective records

The tool calculates FNV-1a 64-bit hashes of GUID strings and matches them against little-endian integers in the save. The initial value is `14695981039346656037`, and the multiplier is `1099511628211`. Raw 16-byte GUID representations cannot be substituted.

Using the first matching item hash as the relative origin `p`, the supported fields are:

| Relative offset | Contents |
|---|---|
| `+0` / `+8` | Repeated CollectionItemId hash |
| `+16` | ChallengeId hash |
| `+24` | Preserve the original value |
| `+28` | Objective count; the editor requires 1 |
| `+32` | GoalId hash |
| `+40` | Objective completion flag |
| `+41` | Progress type; the editor requires 1 |
| `+42` | UInt32 objective progress |
| `+46 ... +62` | State tail updated using the supported native completion format |
| `+63 ... +70` | Completion time field |
| `+71 ... +74` | Preserve the original bytes |

Target progress comes from the threshold in the game definition. Records with multiple objectives contain separate progress data, so their layout cannot be inferred using a fixed stride. Supporting another format requires corresponding parsing, precondition checks, and difference verification.

BXML values use a shared string table. Edits use `BxmlState.Intern` to create or reference the new value, then update the target attribute index. Do not overwrite a shared old string directly.

## Source

`vendor/Fh6ProfileEditorDocument.cs` comes from the `public-client` branch of [DVS-code / Forza-Crypto-Tool](https://github.com/DVS-code/Forza-Crypto-Tool). Its original path is `src/ForzaCryptoTool.Core/Fh6ProfileEditorDocument.cs`.

The other files provide Collection Journal analysis, edit planning, state editing, and save writing. Decryption and encryption are handled by the external client.
