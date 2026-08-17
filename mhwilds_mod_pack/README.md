# Monster Hunter Wilds Mod Pack

This project contains three small, independent REFramework Lua mods:

| Script | Function | Default |
|---|---|---:|
| `MHWILDS_Meal_100.lua` | Sets confirmed probability-based meal effects to 100% | 100% |
| `MHWILDS_Reward_Multiplier.lua` | Multiplies in-quest and quest-result item quantities | 2x |
| `MHWILDS_HR_Multiplier.lua` | Multiplies quest-related Hunter Rank points | 2x |

The scripts can be installed together or removed individually.

## Installation

Copy the included `reframework` directory into the Monster Hunter Wilds game
directory. The final layout should be:

```text
MonsterHunterWilds/
└─ reframework/
   └─ autorun/
      ├─ MHWILDS_Meal_100.lua
      ├─ MHWILDS_Reward_Multiplier.lua
      └─ MHWILDS_HR_Multiplier.lua
```

Use a current Monster Hunter Wilds build of REFramework.

## Configuration

The reward multiplier is defined at the top of
`MHWILDS_Reward_Multiplier.lua`:

```lua
local MULTIPLIER = 2
```

The HR multiplier is defined at the top of `MHWILDS_HR_Multiplier.lua`:

```lua
local MULTIPLIER = 2
```

The meal script sets its five confirmed probability fields to `100` and
normally does not need configuration.

## Scope

### Meal effects

Modified:

- Defender Meal (Hi) activation probability
- Defender Meal (Lo) activation probability
- additional carve activation probability
- wound-break additional reward activation probability
- additional gathering activation probability

The script does not change effect strength and does not grant meal skills that
the player did not activate.

### Reward quantities

Modified:

- common and additional quest rewards
- target monster, carve, tail, part-break, and wound-break rewards
- special investigation rewards such as decorations, Artian parts, and
  talismans

Not modified:

- probability, weight, reward slots, or roll counts
- fixed story-item rewards
- field gathering, field drops, or gimmick rewards
- money, Guild Points, investigation points, or HR points

### HR points

The script modifies the globally enumerable enemy-quest and mission-reward HR
tables. It does not modify Guild Points, Palico experience, money,
investigation points, or item rewards.

Some special quests store HR directly in their individual
`QuestData._HRPoint` resource. Those quests may not be covered by the current
minimal implementation.

## Data documentation

The public data sources, object relationships, and field semantics for all
three mods are consolidated in [`DATA.md`](DATA.md).
