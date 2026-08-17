-- Monster Hunter Wilds - meal skill probability 100%
local TARGET = 100

local FIELDS = {
    "_Defence_Probabiliry",
    "_Defence_S_Probabiliry",
    "_HagitoriAdd_Probabiliry",
    "_ScarBreakerAdd_Probabiliry",
    "_CollectUp_Rate",
}

local ga = sdk.find_type_definition("app.GA")
local get_player_param = ga and ga:get_method("get_PlParam") or nil
local player_param_type = get_player_param and get_player_param:get_return_type() or nil
local get_meal_param = player_param_type and
    player_param_type:get_method("get_MealSkillParam") or nil
local meal_param_type = sdk.find_type_definition("app.user_data.PlayerMealSkillParam")

local frame = 0
local applied = false
local last_error = nil

local function update()
    local player_param = get_player_param:call(nil)
    local meal_param = player_param and get_meal_param:call(player_param) or nil
    if meal_param == nil then
        return false
    end

    local changed = false
    for _, field in ipairs(FIELDS) do
        local current = sdk.get_native_field(meal_param, meal_param_type, field)
        if current ~= TARGET then
            sdk.set_native_field(meal_param, meal_param_type, field, TARGET)
            changed = true
        end
    end

    if changed then
        log.info("[MHWILDS Meal Skills 100%] Probability overrides applied")
    end
    return true
end

if get_player_param == nil or get_meal_param == nil or meal_param_type == nil then
    log.error("[MHWILDS Meal Skills 100%] Required game symbols were not found")
else
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
            log.error("[MHWILDS Meal Skills 100%] " .. last_error)
        end
    end)
end
