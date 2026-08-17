-- Monster Hunter Wilds - task reward quantity multiplier
local MULTIPLIER = 2
local MAX_QUANTITY = 99

local ORIGINALS_KEY = "__MHWILDS_REWARD_MULTIPLIER_ORIGINALS"
local originals = rawget(_G, ORIGINALS_KEY)
if type(originals) ~= "table" then
    originals = {}
    rawset(_G, ORIGINALS_KEY, originals)
end

local frame = 0
local applied = false
local last_error = nil

local function number(value)
    if type(value) == "number" then
        return value
    end
    return value and value.m_value or nil
end

local function scalar(object, field, key)
    if object == nil then
        return 0
    end

    local current = number(object[field])
    if current == nil then
        return 0
    end

    if originals[key] == nil then
        originals[key] = current
    end

    local wanted = originals[key]
    if wanted > 0 then
        wanted = math.min(wanted * MULTIPLIER, MAX_QUANTITY)
    end

    if current ~= wanted then
        object[field] = wanted
        return 1
    end
    return 0
end

local function array(values, key)
    local changed = 0
    if values == nil then
        return changed
    end

    for index, wrapped in pairs(values) do
        local current = number(wrapped)
        if current ~= nil then
            local item_key = key .. "[" .. tostring(index) .. "]"
            if originals[item_key] == nil then
                originals[item_key] = current
            end

            local wanted = originals[item_key]
            if wanted > 0 then
                wanted = math.min(wanted * MULTIPLIER, MAX_QUANTITY)
            end

            if current ~= wanted then
                values[index] = wanted
                changed = changed + 1
            end
        end
    end
    return changed
end

local function entries(values, field, key)
    local changed = 0
    if values == nil then
        return changed
    end

    for index, entry in pairs(values) do
        changed = changed + scalar(
            entry,
            field,
            key .. "[" .. tostring(index) .. "]"
        )
    end
    return changed
end

local function monster_rewards(setting)
    local changed = 0
    local enemy = setting._EnemyRewardSettingData
    if enemy == nil then
        return changed
    end

    local table_list = enemy._RewardTable and enemy._RewardTable._items or nil
    if table_list then
        for table_index, reward_table in pairs(table_list) do
            local values = reward_table and reward_table._Values or nil
            if values then
                for entry_index, entry in pairs(values) do
                    local key = "monster.main[" .. tostring(table_index) ..
                        "][" .. tostring(entry_index) .. "]"
                    changed = changed + scalar(entry, "_RewardNumStory", key .. ".story")
                    changed = changed + array(
                        entry and entry._RewardNumEx or nil,
                        key .. ".ex"
                    )
                end
            end
        end
    end

    local extra = enemy.AddRewardTable or enemy._AddRewardTable
    if extra and extra._Values then
        for index, entry in pairs(extra._Values) do
            local key = "monster.extra[" .. tostring(index) .. "]"
            changed = changed + scalar(entry, "_RewardNumStory", key .. ".story")
            changed = changed + scalar(entry, "_RewardNumEx", key .. ".ex")
        end
    end
    return changed
end

local function quest_boxes(setting)
    local changed = 0

    local common = setting._CommonQuestRewardData
    changed = changed + entries(
        common and common._Values or nil,
        "_num",
        "quest.common"
    )

    local additional = setting._AddQuestRewardData
    changed = changed + entries(
        additional and additional._Values or nil,
        "_num",
        "quest.additional"
    )

    return changed
end

local function investigation_rewards(setting)
    local changed = 0
    local ex = setting._ExQuestRewardSetting
    if ex == nil then
        return changed
    end

    changed = changed + entries(ex._SkillGemRewardTbl, "_Num", "ex.skill_gem")
    changed = changed + entries(ex._ArtianRewardTbl, "_Num", "ex.artian")
    changed = changed + entries(ex._AmuletRewardTbl, "_Num", "ex.amulet")

    local groups = {
        { ex._SkillGemRewardTblByEm, "_SkillGemRewardTbl", "_SkillGemRewardTbl_SpOffer", "skill_gem" },
        { ex._ArtianRewardTblByEm, "_ArtianRewardTbl", "_ArtianRewardTbl_SpOffer", "artian" },
        { ex._AmuletRewardTblByEm, "_AmuletRewardTbl", "_AmuletRewardTbl_SpOffer", "amulet" },
    }

    for _, group in ipairs(groups) do
        if group[1] then
            for index, parent in pairs(group[1]) do
                local key = "ex." .. group[4] .. "[" .. tostring(index) .. "]"
                changed = changed + entries(
                    parent and parent[group[2]] or nil,
                    "_Num",
                    key .. ".normal"
                )
                changed = changed + entries(
                    parent and parent[group[3]] or nil,
                    "_Num",
                    key .. ".special"
                )
            end
        end
    end

    if ex._SwarmSpOfferRewardByEm then
        for swarm_index, swarm in pairs(ex._SwarmSpOfferRewardByEm) do
            local tables = swarm and swarm._RewardItemTbl or nil
            if tables then
                for table_index, reward_table in pairs(tables) do
                    changed = changed + entries(
                        reward_table and reward_table._RewardItemTbl or nil,
                        "_Num",
                        "ex.swarm[" .. tostring(swarm_index) ..
                            "][" .. tostring(table_index) .. "]"
                    )
                end
            end
        end
    end
    return changed
end

local function update()
    local manager = sdk.get_managed_singleton("app.VariousDataManager")
    local setting = manager and manager._Setting or nil
    if setting == nil then
        return false
    end

    local changed = monster_rewards(setting) +
        quest_boxes(setting) +
        investigation_rewards(setting)

    if changed > 0 then
        log.info(
            "[MHWILDS Reward Multiplier] applied x" ..
            tostring(MULTIPLIER) .. "; changed=" .. tostring(changed)
        )
    end
    return true
end

re.on_frame(function()
    if applied then
        return
    end

    frame = frame + 1
    if frame % 300 ~= 0 then
        return
    end

    local ok, result = pcall(update)
    if ok then
        last_error = nil
        if result then
            applied = true
        end
    elseif tostring(result) ~= last_error then
        last_error = tostring(result)
        log.error("[MHWILDS Reward Multiplier] " .. last_error)
    end
end)
