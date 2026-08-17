-- Monster Hunter Wilds - quest HR point multiplier
local MULTIPLIER = 2
local MAX_VALUE = 2147483647

local HR_FIELDS = {
    "_HunterRankPoint",
    "_HunterRankPoint2",
    "_HunterRankPoint3",
}

local frame = 0
local applied = false
local last_error = nil

local function number(value)
    if type(value) == "number" then
        return value
    end
    return value and value.m_value or nil
end

local function multiply(object, field)
    if object == nil then
        return 0
    end

    local value = number(object[field])
    if value == nil or value <= 0 then
        return 0
    end

    object[field] = math.min(value * MULTIPLIER, MAX_VALUE)
    return 1
end

local function update()
    local manager = sdk.get_managed_singleton("app.VariousDataManager")
    local setting = manager and manager._Setting or nil
    if setting == nil then
        return false
    end

    local changed = 0

    local enemy_quest = setting._EnemyQuestData
    local enemy_values = enemy_quest and enemy_quest._Values or nil
    local mission_reward = setting._MissionRewardData
    local mission_values = mission_reward and mission_reward._Values or nil
    if enemy_values == nil or mission_values == nil then
        return false
    end

    for _, entry in pairs(enemy_values) do
        for _, field in ipairs(HR_FIELDS) do
            changed = changed + multiply(entry, field)
        end
    end

    for _, entry in pairs(mission_values) do
        changed = changed + multiply(entry, "_HunterRankPoint")
    end

    log.info(
        "[MHWILDS HR Multiplier] applied x" ..
        tostring(MULTIPLIER) .. "; changed=" .. tostring(changed)
    )
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
        log.error("[MHWILDS HR Multiplier] " .. last_error)
    end
end)
