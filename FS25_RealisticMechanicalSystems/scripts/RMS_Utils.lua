RMS_Utils = {}

function RMS_Utils.getLockedHookLiftContainer(vehicle)
    local hookLift = vehicle ~= nil and vehicle.spec_hookLiftTrailer or nil
    local attachedContainer = hookLift ~= nil and hookLift.attachedContainer or nil
    local container = attachedContainer ~= nil and attachedContainer.object or nil

    if hookLift == nil or hookLift.containerLockState ~= true or container == nil or container.spec_hookLiftContainer == nil then
        return nil
    end

    return container
end

function RMS_Utils.getChancePerFrameFromMeanTime(dt, meanTimeInMinutes)
    if meanTimeInMinutes <= 0 then
        return 1.0
    end
    local meanTimeInMs = meanTimeInMinutes * 60 * 1000
    return dt / meanTimeInMs
end

local function getIsCarsStoreCategory(vehicle)
    if vehicle == nil or vehicle.configFileName == nil or g_storeManager == nil then
        return false
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return false
    end

    if storeItem.categoryNames ~= nil then
        for _, categoryName in ipairs(storeItem.categoryNames) do
            if string.upper(tostring(categoryName or "")) == "CARS" then
                return true
            end
        end
    end

    return string.upper(tostring(storeItem.categoryName or "")) == "CARS"
end

function RMS_Utils.hasPtoOutputCapability(vehicle)
    if getIsCarsStoreCategory(vehicle) then
        return false
    end

    local ptoSpec = vehicle ~= nil and vehicle.spec_powerTakeOffs or nil
    return ptoSpec ~= nil
        and type(ptoSpec.outputPowerTakeOffs) == "table"
        and #ptoSpec.outputPowerTakeOffs > 0
end

function RMS_Utils.hasHydraulicCapability(vehicle)
    if getIsCarsStoreCategory(vehicle) then
        return false
    end

    local attacherJointsSpec = vehicle ~= nil and vehicle.spec_attacherJoints or nil
    if attacherJointsSpec ~= nil then
        for _, jointDesc in pairs(attacherJointsSpec.attacherJoints) do
            local jointType = jointDesc.jointType
            local isTrailerJoint = jointType == AttacherJoints.JOINTTYPE_TRAILER
                or jointType == AttacherJoints.JOINTTYPE_TRAILERLOW
                or jointType == AttacherJoints.JOINTTYPE_TRAILERCAR
            if jointDesc.allowsLowering and not isTrailerJoint then
                return true
            end
        end
    end

    local cylinderedSpec = vehicle ~= nil and vehicle.spec_cylindered or nil
    return cylinderedSpec ~= nil and #cylinderedSpec.movingTools > 0
end

function RMS_Utils.getConnectedPtoData(vehicle)
    local data = {
        isActive = false,
        torque = 0,
        rpm = 0,
        power = 0,
        connectedVehicles = {},
        activeLinks = {}
    }
    local visited = {}

    local function walk(vehicleObj)
        if vehicleObj == nil or visited[vehicleObj] then
            return
        end
        visited[vehicleObj] = true

        if vehicleObj.getOutputPowerTakeOffs == nil then
            return
        end

        local outputs = vehicleObj:getOutputPowerTakeOffs()
        for _, output in pairs(outputs) do
            local consumer = output.connectedVehicle
            if output.connectedInput ~= nil and consumer ~= nil then
                data.connectedVehicles[consumer] = true

                local isActive = consumer:getIsPowerTakeOffActive()
                local torque = 0
                if consumer.getConsumedPtoTorque ~= nil then
                    local consumedTorque = consumer:getConsumedPtoTorque()
                    torque = tonumber(consumedTorque) or 0
                end
                local rpm = consumer.getPtoRpm ~= nil and (tonumber(consumer:getPtoRpm()) or 0) or 0
                local power = torque * rpm * math.pi / 30

                data.torque = data.torque + torque
                data.rpm = math.max(data.rpm, rpm)
                data.power = data.power + power

                if isActive then
                    data.isActive = true
                    data.activeLinks[output] = true
                end

                walk(consumer)
            end
        end
    end

    walk(vehicle)
    return data
end

function RMS_Utils.setConnectedPtoConsumersTurnedOn(vehicle, isTurnedOn)
    local changed = false
    local ptoData = RMS_Utils.getConnectedPtoData(vehicle)

    for consumer, _ in pairs(ptoData.connectedVehicles) do
        if consumer.getIsTurnedOn ~= nil
            and consumer.setIsTurnedOn ~= nil
            and consumer:getIsTurnedOn() ~= isTurnedOn then
            consumer:setIsTurnedOn(isTurnedOn)
            changed = true
        end
    end

    return changed
end

function RMS_Utils.calculateQuadraticMultiplier(level, threshold, lessIsWorse, customMax)
    if (lessIsWorse and level >= threshold) or (not lessIsWorse and level <= threshold) then
        return 0.0
    end
    if lessIsWorse then
        local lowerBound = tonumber(customMax)
        local denominator = threshold

        if lowerBound ~= nil and lowerBound < threshold then
            denominator = math.max(threshold - lowerBound, 0.0001)
            level = math.max(level, lowerBound)
        else
            denominator = math.max(threshold, 0.0001)
        end

        local normalizedValue = (threshold - level) / denominator
        return normalizedValue * normalizedValue
    else
        local normalizedValue = (level - threshold) / ((customMax or 1) - threshold)
        return normalizedValue * normalizedValue
    end
end

function RMS_Utils.getEstimatedMTBF(systemCondition, systemStress)
    local probabilityData = RMS_Config.CORE.BREAKDOWN_PROBABILITIES
    if type(systemStress) == "table" then
        probabilityData = systemStress
        systemStress = nil
    end

    local condition = math.max(math.min(systemCondition or 1.0, 1.0), 0.001)
    if systemStress == nil then
        local wear = 1 - condition
        local exponent = math.max(probabilityData.DEGREE - probabilityData.DEGREE * wear, 0.1)
        local calculatedMtbf = probabilityData.MAX_MTBF + (probabilityData.MIN_MTBF - probabilityData.MAX_MTBF) * (wear ^ exponent)
        return math.max(calculatedMtbf, probabilityData.MIN_MTBF)
    end

    local stress = math.max(systemStress, 0.0)
    local stressThreshold = probabilityData.STRESS_THRESHOLD or 0.0
    local effectiveCondition = math.max(condition, RMS_Config.CORE.CONDITION_EFFECTIVE_FLOOR or 0.15)
    if stress / effectiveCondition < stressThreshold then
        return math.huge
    end

    local stressOverload = math.max(effectiveCondition - stress, 0.001)
    local wear = 1 - math.max(0, math.min(1, stressOverload))
    local exponent = math.max(probabilityData.DEGREE - probabilityData.DEGREE * wear, 0.1)
    local calculatedMtbf = probabilityData.MAX_MTBF + (probabilityData.MIN_MTBF - probabilityData.MAX_MTBF) * (wear ^ exponent)
    local mtbfInMinutes = math.max(calculatedMtbf, probabilityData.MIN_MTBF)
    return mtbfInMinutes
end

function RMS_Utils.getCriticalFailureChance(condition)
    local probability = RMS_Config.CORE.BREAKDOWN_PROBABILITIES
    return math.clamp((1 - condition) ^ probability.CRITICAL_DEGREE, probability.CRITICAL_MIN, probability.CRITICAL_MAX)
end

function RMS_Utils.convertHoursToHoursAndMinutes(totalHours)
    if totalHours == nil then
        return 0, 0
    end
    local hours, fraction = math.modf(totalHours)
    local minutes = math.floor((fraction * 60) + 0.5)
    
    return hours, minutes
end

function RMS_Utils.updateMoneyBoxLayout(labelElement, valueElement, boxElement, bgElement, labelText, valueText)
    if labelElement == nil or valueElement == nil or boxElement == nil or bgElement == nil then
        return
    end

    if labelElement.setText ~= nil then
        labelElement:setText(tostring(labelText or ""))
    end
    if valueElement.setText ~= nil then
        valueElement:setText(tostring(valueText or ""))
    end

    if boxElement.invalidateLayout ~= nil then
        boxElement:invalidateLayout()
    end

    local targetWidth = nil
    if boxElement.flowSizes ~= nil then
        targetWidth = boxElement.flowSizes[1]
    end

    if targetWidth == nil or targetWidth <= 0 then
        return
    end

    local horizontalPadding = 50 * (g_pixelSizeScaledX or 0)
    local bgHeight = (bgElement.size ~= nil and bgElement.size[2]) or ((boxElement.size ~= nil and boxElement.size[2]) or 0.03)
    targetWidth = targetWidth + horizontalPadding

    if bgElement.setSize ~= nil then
        bgElement:setSize(targetWidth, bgHeight)
    end

    if bgElement.invalidateLayout ~= nil then
        bgElement:invalidateLayout()
    end
end

function RMS_Utils.tableToString(tbl)
    if not tbl or next(tbl) == nil then
        return "{}" 
    end
    
    local parts = {}
    for k, v in pairs(tbl) do
        local valueStr
        if type(v) == 'table' then
            valueStr = RMS_Utils.tableToString(v)
        else
            valueStr = tostring(v)
        end
        table.insert(parts, string.format("%s = %s", tostring(k), valueStr))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

function RMS_Utils.getKeyByValue(tbl, value)
    for key, val in pairs(tbl) do
        if val == value then
            return key
        end
    end
    return nil
end

function RMS_Utils.getUniqueUserIdByConnection(connection)
    local user = g_currentMission.userManager:getUserByConnection(connection)
    if user == nil then
        return nil
    end
    return user:getUniqueUserId()
end

-- ==========================================================
--                          SERIALIZATION   
-- ==========================================================

function RMS_Utils.serializeBreakdowns(breakdownsTable)
    local parts = {}
    for id, breakdown in pairs(breakdownsTable) do
        local visible = breakdown.isVisible and 1 or 0
        local selected = breakdown.isSelectedForRepair and 1 or 0
        local active = breakdown.isActive ~= false and 1 or 0
        local resumeTimer = math.max(tonumber(breakdown.resumeTimer) or 0, 0)
        local source = math.max(math.floor(tonumber(breakdown.source) or 0), 0)
        local effectTargetIndex = math.max(math.floor(tonumber(breakdown.effectTargetIndex) or 0), 0)

        local system = string.format("%s,%d,%.2f,%d,%d,%d,%.2f,%d,%d", id, breakdown.stage, breakdown.progressTimer or 0, visible, selected, active, resumeTimer, source, effectTargetIndex)
        table.insert(parts, system)
    end
    return table.concat(parts, ";")
end

function RMS_Utils.serializeDate(dateTable)
    if dateTable == nil or dateTable.day == nil then
        return ""
    end
    return string.format("%d,%d,%d", dateTable.day, dateTable.month, dateTable.year)
end

function RMS_Utils.encodeDelimitedString(value)
    if value == nil then
        return ""
    end

    return (tostring(value):gsub("([^%w%-%._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

function RMS_Utils.decodeDelimitedString(value)
    if value == nil or value == "" then
        return ""
    end

    return (tostring(value):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function RMS_Utils.deserializeDate(dateString)
    if dateString == nil or dateString == "" then
        return {}
    end
    
    local day, month, year = string.match(dateString, "([^,]+),([^,]+),([^,]+)")
    if day and month and year then
        return {
            day = tonumber(day),
            month = tonumber(month),
            year = tonumber(year)
        }
    end
    return {}
end

function RMS_Utils.deserializeBreakdowns(breakdownString)
    local breakdowns = {}
    if breakdownString == nil or breakdownString == "" then
        return breakdowns
    end
    
    for part in string.gmatch(breakdownString, "([^;]+)") do
        local id, stage, timer, isVisible, isSelected, isActive, resumeTimer, source, effectTargetIndex = string.match(part, "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),?([^,]*)")
        
        if id then
            breakdowns[id] = {
                stage = tonumber(stage),
                progressTimer = tonumber(timer),
                isVisible = (tonumber(isVisible) == 1),
                isSelectedForRepair = (tonumber(isSelected) == 1),
                isActive = (tonumber(isActive) == 1),
                resumeTimer = math.max(tonumber(resumeTimer) or 0, 0),
                source = tonumber(source) or RealisticMechanicalSystems.BREAKDOWN_SOURCES.RANDOM,
                effectTargetIndex = math.max(math.floor(tonumber(effectTargetIndex) or 0), 0)
            }
        end
    end
    return breakdowns
end

-- ==========================================================
--                   STRING FORMATTING
-- ==========================================================

-- service --------------------------------------------------

function RMS_Utils.formatFinishTime(finishTime, daysToAdd)
   if finishTime == nil then
        return ""
    end
    
    local finishTimeHours, finishTimeMinutes = RMS_Utils.convertHoursToHoursAndMinutes(finishTime)
    local daysText = ""

    if daysToAdd == 1 then
        daysText = g_i18n:getText('rms_spec_tomorrow_at')
    elseif daysToAdd == 2 then
        daysText =  g_i18n:getText('rms_spec_day_after_tomorrow_at')
    elseif daysToAdd > 2 then
        daysText = g_i18n:getText('rms_spec_in_days_at')
        daysText = string.gsub(daysText, "{days}", daysToAdd)
    end

    return string.format("%s%02d:%02d", daysText, finishTimeHours, finishTimeMinutes)
end

function RMS_Utils.formatDuration(duration)
    if duration == nil then
        return ""
    end
    local durationHours, durationMinutes = RMS_Utils.convertHoursToHoursAndMinutes(duration)
    local days = math.floor(durationHours / 24)
    local daysText = ""
    if days > 0 then
        durationHours = durationHours - days * 24
        daysText = string.format("%s %s ", days, g_i18n:getText('rms_spec_day_s'))
    end

    local durationText = ""
    if durationHours == 0 and durationMinutes > 0 then
        durationText = string.format(g_i18n:getText('rms_spec_duration_format_minutes'), durationMinutes, g_i18n:getText('rms_spec_minute_s'))
    elseif durationHours > 0 and durationMinutes == 0 then
        durationText = string.format(g_i18n:getText('rms_spec_duration_format_hours'), durationHours, g_i18n:getText('rms_spec_hour_s'))
    elseif durationHours > 0 and durationMinutes > 0 then
        local hoursText = string.format(g_i18n:getText('rms_spec_duration_format_hours'), durationHours, g_i18n:getText('rms_spec_hour_s'))
        local minutesText = string.format(g_i18n:getText('rms_spec_duration_format_minutes'), durationMinutes, g_i18n:getText('rms_spec_minute_s'))
        durationText = string.format(g_i18n:getText('rms_spec_duration_format_combined'), hoursText, minutesText)
    end

    return string.format("%s%s", daysText, durationText)
end

-- condition and service levels -----------------------------

RMS_Utils.CONDITION_LEVELS = {0.8, 0.6, 0.4, 0.2}

local CONDITION_STATE_NAMES = {"EXCELLENT", "GOOD", "NORMAL", "BAD", "TERRIBLE"}

-- Returns the condition tier, 1 for the best and 5 for the worst.
function RMS_Utils.getConditionTier(condition)
    local levels = RMS_Utils.CONDITION_LEVELS
    for tier = 1, #levels do
        if condition >= levels[tier] then
            return tier
        end
    end
    return #levels + 1
end

function RMS_Utils.formatCondition(condition, isCompleteInspection)
    local STATES = RealisticMechanicalSystems.STATES
    if isCompleteInspection == nil then
        return g_i18n:getText(STATES.UNKNOWN)
    end
    if isCompleteInspection then
        return string.format("%.0f%%", condition * 100)
    end
    return g_i18n:getText(STATES[CONDITION_STATE_NAMES[RMS_Utils.getConditionTier(condition)]])
end

function RMS_Utils.getServiceIntervalRemainingRatio(service)
    local threshold = math.clamp(tonumber(RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD) or 0.5, 0.0, 0.9999)
    local activeRange = math.max(1.0 - threshold, 0.0001)
    return math.clamp(((tonumber(service) or 0.0) - threshold) / activeRange, 0.0, 1.0)
end

function RMS_Utils.formatService(service, isCompleteInspection)
    local STATES = RealisticMechanicalSystems.STATES
    -- No report in the log.
    if isCompleteInspection == nil then
        return g_i18n:getText(STATES.UNKNOWN)
    end
    if isCompleteInspection then
        return string.format("%.0f%%", RMS_Utils.getServiceIntervalRemainingRatio(service) * 100)
    end
    service = tonumber(service) or 0.0
    if service >= 0.9 then
        return g_i18n:getText(STATES.OPTIMAL)
    elseif service >= 0.7 then
        return g_i18n:getText(STATES.GOOD)
    elseif service >= 0.6 then
        return g_i18n:getText(STATES.RECOMMENDED)
    elseif service >= 0.5 then
        return g_i18n:getText(STATES.REQUIRED)
    else
        return g_i18n:getText(STATES.OVERDUE)
    end
end

-- time -----------------------------------------------------

function RMS_Utils.formatTimeAgo(pastDate) -- expects a table with year and month fields, returns a localized string like "5 months ago" or "This month"
    if type(pastDate) ~= "table" or not pastDate.year or not pastDate.month then
        return g_i18n:getText('rms_spec_never')
    end

    local env = g_currentMission and g_currentMission.environment
    if not env then
        return ""
    end

    local currentMonthsTotal = env.currentYear * 12 + env.currentPeriod
    local pastMonthsTotal = pastDate.year * 12 + pastDate.month

    local monthsAgo = math.max(0, currentMonthsTotal - pastMonthsTotal)

    if monthsAgo == 0 then
        return g_i18n:getText('rms_spec_this_month')
    else
        return string.format(
            g_i18n:getText('rms_spec_months_ago_format'), 
            monthsAgo, 
            g_i18n:getText('rms_spec_months_ago_unit')
        )
    end
end

-- operating hours ---------------------------------------------------

function RMS_Utils.formatOperatingHours(currentHours, intervalHours)
    return string.format("%.1f / %.1f %s", currentHours, intervalHours, g_i18n:getText('rms_spec_op_hours_short'))
end

-- others ---------------------------------------------------------------

function RMS_Utils.getValueLabel(value, ideal, high, mid, low, ...)
-- getValueLabel(63, 90, 75, 50, 25, "Excellent", "Good", "Average", "Poor", "Critical")
    local labels = {...}
    if value >= ideal then
        return labels[1]
    elseif value >= high then
        return labels[2]
    elseif value >= mid then
        return labels[3]
    elseif value >= low then
        return labels[4]
    else
        return labels[5]
    end
end

function RMS_Utils.getValueLabelInverted(value, ideal, low, mid, high, ...)
-- getValueLabelInverted(63, 10, 25, 50, 75, "Excellent", "Good", "Average", "Poor", "Critical")
    local labels = {...}
    if value <= ideal then
        return labels[1]
    elseif value <= low then
        return labels[2]
    elseif value <= mid then
        return labels[3]
    elseif value <= high then
        return labels[4]
    else
        return labels[5]
    end
end

-- reliabolity and maintenability ------------------------------------

function RMS_Utils.formatReliability(value)
    if value < 1.0 then return g_i18n:getText('rms_spec_state_budget')
    elseif value < 1.1 then return g_i18n:getText('rms_spec_state_standard')
    elseif value < 1.2 then return g_i18n:getText('rms_spec_state_premium')
    else return g_i18n:getText('rms_spec_state_legendary') end        
end


function RMS_Utils.formatMaintainability(value)
    if value < 1.0 then return g_i18n:getText('rms_spec_state_low')
    elseif value < 1.1 then return g_i18n:getText('rms_spec_state_average')
    elseif value < 1.2 then return g_i18n:getText('rms_spec_state_high')
    else return g_i18n:getText('rms_spec_state_workhorse') end        
end

-- ==========================================================
--                   COLORS FORMATTING
-- ==========================================================

local COLOR_IDEAL  = {0.12, 0.88, 0.0, 1.0}  -- super green
local COLOR_GREEN  = {0.3, 0.7, 0.0, 1.0}    -- green
local COLOR_YELLOW = {0.85, 0.78, 0.2, 1.0}  -- yellow
local COLOR_ORANGE = {0.85, 0.5, 0.15, 1.0}  -- orange
local COLOR_RED    = {0.8, 0.2, 0.2, 1.0}    -- red
local COLOR_UNKNOWN = {0.5, 0.5, 0.5, 1.0}   -- grey

local SERVICE_COLOR_LEVELS = {0.9, 0.5, 0.2, 0.001}

local function lerpColor(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        a[4] + (b[4] - a[4]) * t,
    }
end

function RMS_Utils.getValueColor(value, ideal, high, mid, low, smooth)
    local c

    if smooth then
        if value >= ideal then
            c = COLOR_IDEAL
        elseif value >= high then
            local t = 1.0 - (value - high) / (ideal - high)
            c = lerpColor(COLOR_IDEAL, COLOR_GREEN, t)
        elseif value >= mid then
            local t = 1.0 - (value - mid) / (high - mid)
            c = lerpColor(COLOR_GREEN, COLOR_YELLOW, t)
        elseif value >= low then
            local t = 1.0 - (value - low) / (mid - low)
            c = lerpColor(COLOR_YELLOW, COLOR_ORANGE, t)
        else
            local t = math.min(1.0, (low - value) / low)
            c = lerpColor(COLOR_ORANGE, COLOR_RED, t)
        end
    else
        if value >= ideal then
            c = COLOR_IDEAL
        elseif value >= high then
            c = COLOR_GREEN
        elseif value >= mid then
            c = COLOR_YELLOW
        elseif value >= low then
            c = COLOR_ORANGE
        else
            c = COLOR_RED
        end
    end

    return c[1], c[2], c[3], c[4]
end

function RMS_Utils.getConditionColor(condition, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(COLOR_UNKNOWN)
    end

    local ideal, high, mid, low = unpack(RMS_Utils.CONDITION_LEVELS)
    return RMS_Utils.getValueColor(condition, ideal, high, mid, low, false)
end

function RMS_Utils.getServiceColor(service, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(COLOR_UNKNOWN)
    end

    local ideal, high, mid, low = unpack(SERVICE_COLOR_LEVELS)
    return RMS_Utils.getValueColor(RMS_Utils.getServiceIntervalRemainingRatio(service), ideal, high, mid, low, isCompleteInspection)
end

function RMS_Utils.getValueColorInverted(value, ideal, low, mid, high, smooth)
    local c

    if smooth then
        if value <= ideal then
            c = COLOR_IDEAL
        elseif value <= low then
            local t = (value - ideal) / (low - ideal)
            c = lerpColor(COLOR_IDEAL, COLOR_GREEN, t)
        elseif value <= mid then
            local t = (value - low) / (mid - low)
            c = lerpColor(COLOR_GREEN, COLOR_YELLOW, t)
        elseif value <= high then
            local t = (value - mid) / (high - mid)
            c = lerpColor(COLOR_YELLOW, COLOR_ORANGE, t)
        else
            local t = math.min(1.0, (value - high) / high)
            c = lerpColor(COLOR_ORANGE, COLOR_RED, t)
        end
    else
        if value <= ideal then
            c = COLOR_IDEAL
        elseif value <= low then
            c = COLOR_GREEN
        elseif value <= mid then
            c = COLOR_YELLOW
        elseif value <= high then
            c = COLOR_ORANGE
        else
            c = COLOR_RED
        end
    end

    return c[1], c[2], c[3], c[4]
end

-- ==========================================================
--                  GENERIC HELPERS
-- ==========================================================

local SAVEGAME_OPTIONAL_FLOAT_SENTINEL = -1

function RMS_Utils.normalizeBoolValue(value, defaultValue)
    if value == nil then
        return defaultValue == true
    end

    if type(value) == "boolean" then
        return value
    end

    if type(value) == "number" then
        return value ~= 0
    end

    if type(value) == "string" then
        local v = string.lower(value)
        if v == "false" or v == "0" or v == "off" or v == "no" then
            return false
        end
        if v == "true" or v == "1" or v == "on" or v == "yes" then
            return true
        end
    end

    return value and true or false
end

function RMS_Utils.normalizeNumberValue(value, defaultValue)
    if value == nil then
        return defaultValue
    end

    local num = tonumber(value)
    if num == nil then
        return defaultValue
    end

    return num
end

function RMS_Utils.encodeOptionalFloat(value)
    if value == nil then
        return SAVEGAME_OPTIONAL_FLOAT_SENTINEL
    end

    local num = tonumber(value)
    if num == nil then
        return SAVEGAME_OPTIONAL_FLOAT_SENTINEL
    end

    return num
end

function RMS_Utils.decodeOptionalFloat(value)
    local num = tonumber(value)
    if num == nil or num < 0 then
        return nil
    end

    return num
end

function RMS_Utils.parseCsvList(csvString)
    local result = {}
    if csvString == nil or csvString == "" then
        return result
    end

    for item in string.gmatch(csvString, "([^,]+)") do
        local trimmed = tostring(item):gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(result, trimmed)
        end
    end

    return result
end

function RMS_Utils.serializeEffectSnapshot(effects)
    local entries = {}
    if effects == nil then
        return ""
    end

    for effectId, effectData in pairs(effects) do
        local key = tostring(effectId or "")
        if key ~= "" then
            local encodedValue = ""

            if type(effectData) == "table" then
                local numericValue = tonumber(effectData.value)
                if numericValue ~= nil then
                    encodedValue = string.format("%.6f", numericValue)
                end
            elseif type(effectData) == "number" then
                encodedValue = string.format("%.6f", effectData)
            end

            table.insert(entries, string.format("%s|%s", key, tostring(encodedValue)))
        end
    end

    table.sort(entries)
    return table.concat(entries, ";")
end

function RMS_Utils.deserializeEffectSnapshot(serialized)
    local result = {}
    if serialized == nil or serialized == "" then
        return result
    end

    if not string.find(serialized, "|") then
        for _, effectId in ipairs(RMS_Utils.parseCsvList(serialized)) do
            result[effectId] = true
        end
        return result
    end

    for entry in string.gmatch(serialized, "([^;]+)") do
        local effectId, rawValue = string.match(entry, "([^|]+)|([^|]*)")
        if effectId ~= nil and effectId ~= "" then
            local value = tonumber(rawValue)
            if value ~= nil then
                result[effectId] = {
                    id = effectId,
                    value = value
                }
            else
                result[effectId] = true
            end
        end
    end

    return result
end

function RMS_Utils.getSystemNameByKey(systems, systemKey)
    if systems == nil then
        return tostring(systemKey)
    end

    local normalized = string.lower(tostring(systemKey))
    for enumKey, systemName in pairs(systems) do
        if string.lower(tostring(enumKey)) == normalized then
            return systemName
        end
    end

    return tostring(systemKey)
end

function RMS_Utils.serializeSystemsState(systems)
    local entries = {}
    if systems == nil then
        return ""
    end

    for systemKey, systemData in pairs(systems) do
        local condition = 1.0
        local stress = 0.0
        local enabled = true

        if type(systemData) == "table" then
            condition = tonumber(systemData.condition) or 1.0
            stress = tonumber(systemData.stress) or 0.0
            enabled = RMS_Utils.normalizeBoolValue(systemData.enabled, true)
        else
            condition = tonumber(systemData) or 1.0
        end

        table.insert(entries, string.format("%s|%.6f|%.6f|%d", tostring(systemKey), condition, stress, enabled and 1 or 0))
    end

    table.sort(entries)
    return table.concat(entries, ";")
end

function RMS_Utils.deserializeSystemsState(serialized)
    local result = {}
    if serialized == nil or serialized == "" then
        return result
    end

    local separator = ";"
    if not string.find(serialized, ";") then
        separator = ","
    end
    local pattern = "([^" .. separator .. "]+)"

    for entry in string.gmatch(serialized, pattern) do
        local parts = {}
        for part in string.gmatch(entry .. "|", "(.-)|") do
            table.insert(parts, part)
        end

        local key = parts[1]
        if key ~= nil and key ~= "" then
            local condition = tonumber(parts[2]) or 1.0
            local stress = tonumber(parts[3]) or 0.0
            local enabled = RMS_Utils.normalizeBoolValue(tonumber(parts[4]), true)

            result[key] = {
                condition = condition,
                stress = stress,
                enabled = enabled
            }
        end
    end

    return result
end

function RMS_Utils.createSystemsSnapshot(systems)
    local snapshot = {}
    if systems == nil then
        return snapshot
    end

    for systemKey, systemData in pairs(systems) do
        if type(systemData) == "table" then
            snapshot[systemKey] = {
                condition = tonumber(systemData.condition) or 1.0,
                stress = tonumber(systemData.stress) or 0.0,
                enabled = RMS_Utils.normalizeBoolValue(systemData.enabled, true)
            }
        else
            snapshot[systemKey] = {
                condition = tonumber(systemData) or 1.0,
                stress = 0.0,
                enabled = true
            }
        end
    end

    return snapshot
end

function RMS_Utils.serializeNumericMap(valueMap)
    local entries = {}
    if valueMap == nil then
        return ""
    end

    for key, value in pairs(valueMap) do
        local numericValue = tonumber(value)
        if numericValue ~= nil then
            table.insert(entries, string.format("%s|%.6f", tostring(key), numericValue))
        end
    end

    table.sort(entries)
    return table.concat(entries, ";")
end

function RMS_Utils.deserializeNumericMap(serialized)
    local result = {}
    if serialized == nil or serialized == "" then
        return result
    end

    local separator = ";"
    if not string.find(serialized, ";") then
        separator = ","
    end
    local pattern = "([^" .. separator .. "]+)"

    for entry in string.gmatch(serialized, pattern) do
        local key, valueStr = string.match(entry, "([^|]+)|([^|]+)")
        if key ~= nil then
            local numericValue = tonumber(valueStr)
            if numericValue ~= nil then
                result[key] = numericValue
            end
        end
    end

    return result
end

function RMS_Utils.getSystemKey(systems, systemName)
    if systems == nil then
        return ""
    end
    return string.lower(RMS_Utils.getKeyByValue(systems, systemName) or "")
end

function RMS_Utils.getEffectiveSystemWeight(vehicle, systemName, systems)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(spec.systems) ~= "table" or type(systemName) ~= "string" then
        return 0
    end

    local systemWeights = RMS_Config ~= nil and RMS_Config.CORE ~= nil and RMS_Config.CORE.SYSTEM_WEIGHTS or nil
    if type(systemWeights) ~= "table" then
        return 0
    end

    local function getConfiguredWeight(systemKey)
        if systemKey == nil then
            return 0
        end

        local directWeight = tonumber(systemWeights[systemKey])
        if directWeight ~= nil then
            return math.max(directWeight, 0)
        end

        local loweredKey = string.lower(tostring(systemKey))
        for weightedKey, weight in pairs(systemWeights) do
            if string.lower(tostring(weightedKey)) == loweredKey then
                return math.max(tonumber(weight) or 0, 0)
            end
        end

        return 0
    end

    local function resolveSystemKey(name)
        if spec.systems[name] ~= nil then
            return name
        end

        if type(systems) == "table" then
            local enumValue = systems[string.upper(name)]
            if type(enumValue) == "string" then
                local enumKey = string.lower(string.upper(name))
                if spec.systems[enumKey] ~= nil then
                    return enumKey
                end
            end

            local systemKeyByValue = RMS_Utils.getKeyByValue(systems, name)
            if type(systemKeyByValue) == "string" then
                local loweredEnumKey = string.lower(systemKeyByValue)
                if spec.systems[loweredEnumKey] ~= nil then
                    return loweredEnumKey
                end
            end
        end

        local loweredName = string.lower(name)
        for existingKey, _ in pairs(spec.systems) do
            if string.lower(tostring(existingKey)) == loweredName then
                return existingKey
            end
        end

        return loweredName
    end

    local resolvedSystemKey = resolveSystemKey(systemName)
    local targetSystemData = spec.systems[resolvedSystemKey]
    if targetSystemData == nil or (type(targetSystemData) == "table" and targetSystemData.enabled == false) then
        return 0
    end

    local targetWeight = getConfiguredWeight(resolvedSystemKey)
    if targetWeight <= 0 then
        return 0
    end

    local totalEnabledWeight = 0
    for existingKey, systemData in pairs(spec.systems) do
        if type(systemData) ~= "table" or systemData.enabled ~= false then
            local configuredWeight = getConfiguredWeight(existingKey)
            if configuredWeight > 0 then
                totalEnabledWeight = totalEnabledWeight + configuredWeight
            end
        end
    end

    if totalEnabledWeight <= 0 then
        return 0
    end

    return targetWeight / totalEnabledWeight
end

function RMS_Utils.shallowCopy(original)
    local result = {}
    if type(original) ~= "table" then
        return result
    end
    for key, value in pairs(original) do
        result[key] = value
    end
    return result
end

function RMS_Utils.deepCopy(original, seen)
    if type(original) ~= "table" then
        return original
    end

    seen = seen or {}
    if seen[original] ~= nil then
        return seen[original]
    end

    local result = {}
    seen[original] = result

    for key, value in pairs(original) do
        local copiedKey = RMS_Utils.deepCopy(key, seen)
        result[copiedKey] = RMS_Utils.deepCopy(value, seen)
    end

    return result
end

-- ==========================================================
--           MAINTENANCE LOG STREAM SERIALIZATION
-- ==========================================================

function RMS_Utils.serializeMaintenanceLogEntry(entry)
    if entry == nil then return "" end
    local cd = entry.conditionData or {}
    local serializedSystems = RMS_Utils.encodeDelimitedString(RMS_Utils.serializeSystemsState(RMS_Utils.createSystemsSnapshot(cd.systems)))
    local serializedBreakdowns = RMS_Utils.encodeDelimitedString(RMS_Utils.serializeBreakdowns(cd.activeBreakdowns or {}))
    local serializedSelectedBreakdowns = RMS_Utils.encodeDelimitedString(table.concat(cd.selectedBreakdowns or {}, ","))
    local serializedEffects = RMS_Utils.encodeDelimitedString(RMS_Utils.serializeEffectSnapshot(cd.activeEffects))
    local activeIndicatorIds = {}
    for indicatorId, isActive in pairs(cd.activeIndicators or {}) do
        if isActive then
            table.insert(activeIndicatorIds, tostring(indicatorId))
        end
    end
    table.sort(activeIndicatorIds)
    local serializedIndicators = RMS_Utils.encodeDelimitedString(table.concat(activeIndicatorIds, ","))
    local parts = {
        tostring(entry.id or 0),
        tostring(entry.type or ""),
        tostring(entry.price or 0),
        RMS_Utils.serializeDate(entry.date),
        tostring(entry.location or "UNKNOWN"),
        tostring(entry.optionOne or "NONE"),
        tostring(entry.optionTwo or "NONE"),
        tostring(entry.optionThree or false),
        tostring(RMS_Utils.normalizeBoolValue(entry.isVisible, true)),
        tostring(RMS_Utils.normalizeBoolValue(entry.isCompleted, true)),
        tostring(cd.year or 0),
        tostring(cd.operatingHours or 0),
        tostring(cd.age or 0),
        tostring(cd.condition or 1),
        tostring(cd.service or 1),
        tostring(cd.reliability or 1),
        tostring(cd.maintainability or 1),
        serializedSystems,
        tostring(cd.batterySoc or 1),
        serializedEffects,
        serializedBreakdowns,
        serializedSelectedBreakdowns,
        serializedIndicators
    }
    return table.concat(parts, "|")
end

function RMS_Utils.deserializeMaintenanceLogEntry(serialized)
    if serialized == nil or serialized == "" then return nil end
    local parts = {}
    for part in string.gmatch(serialized .. "|", "(.-)|") do
        table.insert(parts, part)
    end
    if #parts < 10 then return nil end

    local result = {
        id = tonumber(parts[1]) or 0,
        type = parts[2] ~= "" and parts[2] or nil,
        price = tonumber(parts[3]) or 0,
        date = RMS_Utils.deserializeDate(parts[4]),
        location = parts[5] ~= "" and parts[5] or "UNKNOWN",
        optionOne = parts[6] ~= "" and parts[6] or "NONE",
        optionTwo = parts[7] ~= "" and parts[7] or "NONE",
        optionThree = RMS_Utils.normalizeBoolValue(parts[8], false),
        isVisible = RMS_Utils.normalizeBoolValue(parts[9], true),
        isCompleted = RMS_Utils.normalizeBoolValue(parts[10], true),
        conditionData = {
            year = tonumber(parts[11]) or 0,
            operatingHours = tonumber(parts[12]) or 0,
            age = tonumber(parts[13]) or 0,
            condition = tonumber(parts[14]) or 1,
            service = tonumber(parts[15]) or 1,
            reliability = tonumber(parts[16]) or 1,
            maintainability = tonumber(parts[17]) or 1,
            systems = RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(RMS_Utils.decodeDelimitedString(parts[18] or ""))),
            batterySoc = tonumber(parts[19]) or 1,
            activeBreakdowns = RMS_Utils.deserializeBreakdowns(RMS_Utils.decodeDelimitedString(parts[21] or "")),
            selectedBreakdowns = RMS_Utils.parseCsvList(RMS_Utils.decodeDelimitedString(parts[22] or "")),
            activeEffects = RMS_Utils.deserializeEffectSnapshot(RMS_Utils.decodeDelimitedString(parts[20] or "")),
            activeIndicators = {}
        }
    }
    for _, indicatorId in ipairs(RMS_Utils.parseCsvList(RMS_Utils.decodeDelimitedString(parts[23] or ""))) do
        if indicatorId ~= nil and indicatorId ~= "" then
            result.conditionData.activeIndicators[indicatorId] = true
        end
    end
    return result
end

-- ==========================================================
--                  SHARED VEHICLE HELPERS
-- ==========================================================

function RMS_Utils.hasCVTAddon(vehicle)
    local spec_CVTaddon = vehicle ~= nil and vehicle.spec_CVTaddon or nil
    local cvtAddonConfig = spec_CVTaddon ~= nil and (tonumber(spec_CVTaddon.CVTconfig) or 0) or 0
    return spec_CVTaddon ~= nil
        and spec_CVTaddon.CVTcfgExists
        and cvtAddonConfig ~= 0
        and cvtAddonConfig ~= 8
end

function RMS_Utils.hasCVTTransmission(vehicle)
    local motor = vehicle ~= nil and vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    return motor ~= nil and motor.minForwardGearRatio ~= nil
end

function RMS_Utils.getIsElectricVehicle(vehicle)
    local hasElectricConsumer = false
    local hasCombustionConsumer = false

    if vehicle.spec_motorized and vehicle.spec_motorized.consumers then
        for _, consumer in pairs(vehicle.spec_motorized.consumers) do
            if consumer.fillType == FillType.ELECTRICCHARGE then
                hasElectricConsumer = true
            elseif consumer.fillType == FillType.DIESEL
                    or consumer.fillType == FillType.METHANE then
                hasCombustionConsumer = true
            end
        end
    end

    return hasElectricConsumer and not hasCombustionConsumer
end

-- Returns the heavy trailer power to mass ratio threshold and full effect ratio of the vehicle class.
function RMS_Utils.getHeavyTrailerRatioLevels(isTruck)
    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    if isTruck then
        return C.HEAVY_TRAILER_TRUCK_MASS_RATIO_THRESHOLD, C.HEAVY_TRAILER_TRUCK_MASS_RATIO_FULL_EFFECT
    end
    return C.HEAVY_TRAILER_MASS_RATIO_THRESHOLD, C.HEAVY_TRAILER_MASS_RATIO_FULL_EFFECT
end

function RMS_Utils.createLogger(prefix)
    return function(...)
        if RMS_Config ~= nil and RMS_Config.DEBUG then
            local args = {...}
            for i = 1, #args do
                args[i] = tostring(args[i])
            end
            print(prefix .. " " .. table.concat(args, " "))
        end
    end
end

function RMS_Utils.resolveConsoleSystemKey(spec, rawSystem)
    if rawSystem == nil or rawSystem == "" then
        return nil
    end

    local normalized = string.lower(rawSystem)
    for key, _ in pairs(spec.systems or {}) do
        if string.lower(tostring(key)) == normalized then
            return key
        end
    end

    return false
end
