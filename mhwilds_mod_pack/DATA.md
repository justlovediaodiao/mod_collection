# Monster Hunter Wilds Data Notes

This document records the public data sources and business meaning behind the
three mods in this project. It intentionally omits implementation,
debugging, and test instructions. The Lua files are the authoritative source
for implementation details.

## Source hierarchy

Three kinds of public information are useful, and they answer different
questions.

### Extracted UserData

The most useful source for actual game values is the
[`dtlnor/MHWs-in-json`](https://github.com/dtlnor/MHWs-in-json) repository.
It contains extracted `.user.3` resources converted to readable JSON under:

```text
natives/STM/
```

Links in this document use commit
[`25e07c3`](https://github.com/dtlnor/MHWs-in-json/tree/25e07c3ae9e6eaee8adb2a38296af7c1012b3891)
as a reproducible baseline. A later game update may require comparing that
baseline with a newer dump, such as
[`dzxrly/MHWS-in-json`](https://github.com/dzxrly/MHWS-in-json).

Extracted UserData answers questions such as:

- which resources contain a value;
- the original numeric value;
- how tables reference one another;
- which item, monster, reward category, or quest entry owns a field.

### RSZ type schema

The
[`kvasszn/ree-save-editor`](https://github.com/kvasszn/ree-save-editor)
repository publishes compressed Wilds schemas:

- [`rszmhwilds.json.gz`](https://github.com/kvasszn/ree-save-editor/blob/4125e497f1ae84cc746bb4a99da612c48bea161e/assets/mhwilds/rszmhwilds.json.gz)
- [`enumsmhwilds.json.gz`](https://github.com/kvasszn/ree-save-editor/blob/4125e497f1ae84cc746bb4a99da612c48bea161e/assets/mhwilds/enumsmhwilds.json.gz)

The RSZ schema answers questions such as:

- exact managed type names;
- exact field names;
- signedness and integer width;
- whether a field is scalar, array, object, or enum.

The enum dump provides symbolic names for numeric enum values. It is
especially useful for preventing unsupported guesses based only on field
suffixes.

### Live runtime metadata

[`REFramework`](https://github.com/praydog/REFramework) exposes the live
managed types and objects used by the Lua mods. Runtime metadata is the final
authority after a game update because a public dump may be older than the
installed game.

Public dumps are reverse-engineering evidence, not an official Capcom API.
Field names may be misspelled by the game and must be used exactly as stored.

## Shared data root

Reward and HR data are referenced by:

[`VariousDataManagerSetting.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/System/SystemSetting/VariousDataManagerSetting.user.3.json)

Its relevant references are:

| Runtime member | UserData resource | Business domain |
|---|---|---|
| `_EnemyRewardSettingData` | `GameDesign/Common/Enemy/EnemyRewardDataSetting.user` | monster materials and monster-related rewards |
| `_CommonQuestRewardData` | `GameDesign/Mission/_UserData/_Reward/CommonRewardData.user` | common quest result items |
| `_AddQuestRewardData` | `GameDesign/Mission/_UserData/_Reward/AddRewardData.user` | additional quest result items |
| `_ExQuestRewardSetting` | `GameDesign/Environment/UserData/ExFieldPattern/ExFieldPattern_Default/ExQuestRewardSetting.user` | investigation special rewards |
| `_EnemyQuestData` | `GameDesign/Common/Enemy/EnemyQuestData.user` | per-enemy Guild Points, HR points, Palico experience, and money |
| `_MissionRewardData` | `GameDesign/Mission/_UserData/_Reward/MissionRewardData.user` | fixed mission completion values |

Meal parameters do not come from this manager. They belong to the player
global parameter data.

## Meal effect data

Primary source:

[`PlayerMealSkillParam.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Player/ActionData/Common/GlobalParam/Part/PlayerMealSkillParam.user.3.json)

Managed type:

```text
app.user_data.PlayerMealSkillParam
```

### Confirmed probability fields

| Field | Original value | Business meaning |
|---|---:|---|
| `_Defence_Probabiliry` | `25.0` | activation chance of the stronger Defender meal effect |
| `_Defence_S_Probabiliry` | `12.5` | activation chance of the weaker Defender meal effect |
| `_HagitoriAdd_Probabiliry` | `50` | chance of an additional carve |
| `_ScarBreakerAdd_Probabiliry` | `40` | chance of an additional reward from a wound break |
| `_CollectUp_Rate` | `30` | chance of an additional gathering result |

The game misspells `Probability` as `Probabiliry`. This spelling is part of
the real field name.

These values are percentages. `25.0` means 25%, while `100` means a guaranteed
check.

### Adjacent effect-strength fields

| Field | Original value | Business meaning |
|---|---:|---|
| `_Defence_DamageRate` | `0.7` | a successful stronger Defender check leaves 70% of incoming damage |
| `_Defence_S_DamageRate` | `0.7` | a successful weaker Defender check leaves 70% of incoming damage |
| `_CollectUp_AddPick` | `1` | number of additional gathering results after a successful check |

Probability and effect strength are separate concepts. Making the activation
chance 100% does not change the 0.7 damage multiplier or the number of extra
gathering results.

Not every field containing `Rate` represents a probability. Some are damage,
stamina, ride, or timing multipliers. Likewise,
`_Uneven_IntervalList[*]._Probability` is a weighted choice between possible
intervals, not an independent proc chance. Setting every weight to 100 would
change the distribution rather than guarantee continuous activation.

## Quest reward quantity data

The reward model separates four concepts:

| Concept | Typical fields | Meaning |
|---|---|---|
| item identity | `_itemId`, `_IdStory`, `_IdEx`, `_ItemID` | which item is awarded |
| quantity | `_num`, `_Num`, `_RewardNumStory`, `_RewardNumEx` | number of items produced by one selected result |
| selection chance | `_probability`, `_probabilityStory`, `_probabilityEx` | probability associated with a reward entry |
| weighted selection | `_Weight`, `_Weight_Normal`, `_Weight_Yummy` | relative weight inside a reward pool |

Quantity is not the same as probability, slot count, or roll count. An entry
with quantity `1` may be selected many times into separate result slots. A
quantity multiplier changes the stack size of each selected result; it does
not create more selections or make rare entries more likely.

### Common and additional quest result items

Sources:

- [`CommonRewardData.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Mission/_UserData/_Reward/CommonRewardData.user.3.json)
- [`AddRewardData.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Mission/_UserData/_Reward/AddRewardData.user.3.json)

Both use:

```text
app.user_data.QuestGeneralRewardData.cData
```

| Field | Business meaning |
|---|---|
| `_tableId` | groups entries into a reward table |
| `_dataId` | identifies an entry within the data set |
| `_itemId` | awarded item |
| `_num` | item quantity when the entry is selected |
| `_probability` | selection probability |
| `_commonLotType` | common reward-lot behavior |
| `_addLotType` | additional reward-lot behavior |

The common and additional tables are separate result-box sources even though
they use the same entry type.

### Monster rewards

Index source:

[`EnemyRewardDataSetting.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Common/Enemy/EnemyRewardDataSetting.user.3.json)

This setting references one `EnemyRewardData` resource per enemy, for example:

[`EM0001_00_0.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Common/Enemy/EM0001_00_0.user.3.json)

It also references:

[`EnemyRewardAddData.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Common/Enemy/EnemyRewardAddData.user.3.json)

Representative `EnemyRewardData.cData` fields:

| Field | Business meaning |
|---|---|
| `_rewardType` | reward category, such as a general monster or break-related reward |
| `_partsIndex` | monster-part association when the reward is tied to a part |
| `_lotType` | reward-lot behavior |
| `_IdStory` | item used by the Story reward profile |
| `_RewardNumStory` | Story-profile quantity |
| `_probabilityStory` | Story-profile probability |
| `_IdEx[]` | item alternatives used by EX reward profiles |
| `_RewardNumEx[]` | quantity corresponding to each EX item alternative |
| `_probabilityEx[]` | probability corresponding to each EX alternative |

The enum dump confirms:

```text
app.QuestDef.RANK
INVALID = 0
STORY   = 1
EX      = 2
```

This supports interpreting the `Story` and `Ex` suffixes as separate quest
contexts. The arrays are parallel: item, quantity, and probability at the same
index describe one alternative.

These resources cover the data used by target rewards, carving, tails, part
breaks, wound breaks, and other monster-related reward categories. The exact
category behind a numeric `_rewardType` should be resolved through the enum
dump rather than guessed from its number.

### Investigation special rewards

Source:

[`ExQuestRewardSetting.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Environment/UserData/ExFieldPattern/ExFieldPattern_Default/ExQuestRewardSetting.user.3.json)

The main reward families are:

| Table family | Business meaning |
|---|---|
| `_SkillGemRewardTbl` | decoration or skill-gem appraisal rewards |
| `_ArtianRewardTbl` | Artian weapon-part rewards |
| `_AmuletRewardTbl` | talisman or amulet rewards |
| `*RewardTblByEm` | enemy-specific overrides |
| `*RewardTbl_SpOffer` | special-offer variants |
| `_SwarmSpOfferRewardByEm` | enemy/swarm-specific special-offer item rewards |

Representative fields:

| Field | Business meaning |
|---|---|
| `_Rank` | reward rank or tier |
| `_ItemID` | awarded appraisal item or reward item |
| `_Num` | quantity when selected |
| `_Weight_Normal` | weight in the normal selection profile |
| `_Weight_Yummy` | weight in an alternate enhanced selection profile |

The exact gameplay condition represented by `Yummy` should not be inferred
from the English word alone. The data proves that it is a separate weight
profile; identifying its trigger requires tracing the consumer or matching
controlled game results.

### Reward data deliberately outside this project

The quantity mod does not use:

| Runtime member | Business domain |
|---|---|
| `_MissionRewardData` | fixed mission completion values and story rewards |
| `_GimmickRewardSettingData` | environmental gimmick rewards |
| `_GimmickAddRewardSettingData` | additional gimmick rewards |
| `_GimmickCollectNumTable` | field collection quantities |

This separation is why fixed story-item rewards, field gathering, field
drops, and gimmick rewards are outside the mod's intended scope.

## Hunter Rank point data

### Per-enemy HR profiles

Source:

[`EnemyQuestData.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Common/Enemy/EnemyQuestData.user.3.json)

Managed entry type:

```text
app.user_data.EnemyQuestData.cData
```

Each large-enemy entry groups three parallel reward profiles:

```text
_GuildPoint
_HunterRankPoint
_OtomoExp
_Reward

_GuildPoint2
_HunterRankPoint2
_Reward2

_GuildPoint3
_HunterRankPoint3
_Reward3
```

Business meaning:

| Field family | Meaning |
|---|---|
| `_GuildPoint*` | Guild Points associated with the enemy reward profile |
| `_HunterRankPoint*` | Hunter Rank points associated with the profile |
| `_Reward*` | money associated with the profile |
| `_OtomoExp` | Palico experience |

The three HR values are alternative profiles, not three HR awards paid
simultaneously. The game selects the applicable profile for the current
enemy/quest context.

The exact selection rule for profiles 1, 2, and 3 is not confirmed by the
public data. They must not be described as Low Rank, High Rank, and Master
Rank. `QuestDef.RANK` has only `STORY` and `EX`, so it cannot directly explain
three numbered profiles. Other enums such as `EM_REWARD_RANK` and
`LEGENDARY_ID` exist, but their existence does not prove that either selects
these fields.

Public records frequently give profiles 2 and 3 identical HR values while
profile 1 differs. That confirms parallel profiles but does not identify the
selector.

### Mission reward HR

Source:

[`MissionRewardData.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Mission/_UserData/_Reward/MissionRewardData.user.3.json)

Relevant field:

```text
app.user_data.MissionRewardData.cData._HunterRankPoint
```

This is a separate mission-completion HR source. It is not the same as the
per-enemy profiles and may contribute independently.

### Per-quest embedded HR

The RSZ schema confirms:

```text
app.user_data.QuestData._HRPoint: System.UInt32
```

A concrete source is:

[`Ms109009_QuestData.user.3.json`](https://github.com/dtlnor/MHWs-in-json/blob/25e07c3ae9e6eaee8adb2a38296af7c1012b3891/natives/STM/GameDesign/Mission/Mission109009/_Quest/Ms109009_QuestData.user.3.json)

Individual mission resources can therefore carry HR directly. These
per-quest resources are distinct from the globally referenced
`EnemyQuestData` and `MissionRewardData` tables. This explains why a
table-based HR multiplier may cover field surveys and investigations while
missing some optional, event, challenge, or special quests.

The schema also contains:

```text
app.MissionRewardUtil.MissionRewardInfo.AddHunterRankPoint: System.Int32
```

The name indicates an aggregated HR component, but the field alone does not
prove when it is populated or whether it is exclusively quest-derived.

## Confidence rules for future analysis

Use the following evidence levels when extending this document:

1. A field name and type in the RSZ schema confirm structure only.
2. A populated UserData record confirms that the field carries real data.
3. Neighboring fields and parallel arrays support a business interpretation.
4. Enum names can identify categories, but only when the consuming field is
   confirmed to use that enum.
5. The exact gameplay trigger for a profile requires either consumer tracing
   or controlled in-game comparison.

Do not turn a plausible interpretation into a confirmed statement without
evidence at the appropriate level.

