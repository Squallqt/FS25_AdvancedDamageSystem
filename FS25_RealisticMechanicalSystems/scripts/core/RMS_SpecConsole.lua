local ensureFactorStats = RealisticMechanicalSystems.ensureFactorStats
local getVehicleOperatingHours = RealisticMechanicalSystems.getVehicleOperatingHours
local getSyncOperatingTime = RealisticMechanicalSystems.getSyncOperatingTime
local initializeVehicleConditionFromVanillaPrice = RealisticMechanicalSystems.initializeVehicleConditionFromVanillaPrice

-- ==========================================================
--                      CONSOLE COMMANDS
-- ==========================================================

RealisticMechanicalSystems.ConsoleCommands = {}

function RealisticMechanicalSystems.ConsoleCommands:getTargetVehicle()
    if RealisticMechanicalSystems.ConsoleCommands._overrideVehicle ~= nil then
        local v = RealisticMechanicalSystems.ConsoleCommands._overrideVehicle
        if v.spec_RealisticMechanicalSystems ~= nil then
            return v
        end
        print("RMS Error: Override vehicle does not have RealisticMechanicalSystems support.")
        return nil
    end
    local vehicle = g_localPlayer ~= nil
        and g_localPlayer.getCurrentVehicle ~= nil
        and g_localPlayer:getCurrentVehicle()
        or nil
    if not vehicle or not vehicle.spec_RealisticMechanicalSystems then
        print("RMS Error: You must be in a vehicle with RealisticMechanicalSystems support.")
        return nil
    end
    return vehicle
end

local function parseArguments(argString, ...)
    local extraArgs = { ... }
    local hasExtraArgs = #extraArgs > 0

    if hasExtraArgs then
        local args = {}

        local function appendToken(token)
            if token == nil then
                return
            end
            token = tostring(token)
            if token == "" then
                return
            end

            if string.find(token, "%s") then
                for splitToken in string.gmatch(token, "[^%s]+") do
                    table.insert(args, splitToken)
                end
            else
                table.insert(args, token)
            end
        end

        appendToken(argString)
        for _, extraArg in ipairs(extraArgs) do
            appendToken(extraArg)
        end

    return args
end

    if argString == nil or type(argString) ~= 'string' or argString == '' then
        return {}
    end

    local args = {}
    for arg in string.gmatch(argString, "[^%s]+") do
        table.insert(args, arg)
    end
    return args
end

local function parsePathTokens(path)
    local tokens = {}
    if type(path) ~= "string" or path == "" then
        return tokens
    end

    for token in string.gmatch(path, "[^%.]+") do
        local numberToken = tonumber(token)
        if numberToken ~= nil then
            table.insert(tokens, numberToken)
        else
            table.insert(tokens, token)
        end
    end

    return tokens
end

local function parseConsoleValue(rawValue)
    if rawValue == nil then
        return nil, false
    end

    local lowerValue = string.lower(tostring(rawValue))
    if lowerValue == "true" then
        return true, true
    end
    if lowerValue == "false" then
        return false, true
    end
    if lowerValue == "nil" then
        return nil, true
    end

    local numberValue = tonumber(rawValue)
    if numberValue ~= nil then
        return numberValue, true
    end

    return rawValue, true
end

local function resolvePathParent(rootTable, fullPath)
    if type(rootTable) ~= "table" then
        return nil, nil, nil, "Root is not a table."
    end

    local tokens = parsePathTokens(fullPath)
    if #tokens == 0 then
        return nil, nil, nil, "Path is empty."
    end

    local current = rootTable
    for i = 1, #tokens - 1 do
        local key = tokens[i]
        if type(current) ~= "table" then
            return nil, nil, nil, string.format("Path segment '%s' is not a table.", tostring(key))
        end

        current = current[key]
        if current == nil then
            return nil, nil, nil, string.format("Path segment '%s' does not exist.", tostring(key))
        end
    end

    return current, tokens[#tokens], tokens
end

local function getPrimaryFuelConsumerInfo(vehicle)
    if vehicle == nil or vehicle.spec_motorized == nil or vehicle.spec_motorized.consumers == nil then
        return nil, nil
    end

    local preferredTypes = {}
    if FillType ~= nil then
        if FillType.DIESEL ~= nil then table.insert(preferredTypes, FillType.DIESEL) end
        if FillType.METHANE ~= nil then table.insert(preferredTypes, FillType.METHANE) end
        if FillType.ELECTRICCHARGE ~= nil then table.insert(preferredTypes, FillType.ELECTRICCHARGE) end
    end

    local function isPreferred(fillType)
        for _, preferredType in ipairs(preferredTypes) do
            if fillType == preferredType then
                return true
            end
        end
        return false
    end

    local fallbackConsumer = nil
    local defFillType = FillType ~= nil and FillType.DEF or nil
    for _, consumer in pairs(vehicle.spec_motorized.consumers) do
        if consumer ~= nil and consumer.fillUnitIndex ~= nil and consumer.fillType ~= nil then
            if isPreferred(consumer.fillType) then
                return consumer.fillUnitIndex, consumer.fillType
            end

            if fallbackConsumer == nil and (defFillType == nil or consumer.fillType ~= defFillType) then
                fallbackConsumer = consumer
            end
        end
    end

    if fallbackConsumer ~= nil then
        return fallbackConsumer.fillUnitIndex, fallbackConsumer.fillType
    end

    return nil, nil
end

local function syncConsoleCloggingState(vehicle, spec, parent, key)
    if vehicle == nil or spec == nil or parent ~= spec then
        return false
    end

    if key ~= "radiatorClogging" and key ~= "airIntakeClogging" then
        return false
    end

    spec.radiatorClogging = math.clamp(tonumber(spec.radiatorClogging) or 0, 0.0, 1.0)
    spec.airIntakeClogging = math.clamp(tonumber(spec.airIntakeClogging) or 0, 0.0, 1.0)

    if vehicle.spec_washable ~= nil and vehicle.setDirtAmount ~= nil and vehicle.getDirtAmount ~= nil then
        local currentDirtAmount = math.clamp(tonumber(vehicle:getDirtAmount()) or 0, 0.0, 1.0)
        local requiredDirtAmount = math.max(spec.radiatorClogging or 0, spec.airIntakeClogging or 0)
        if requiredDirtAmount > currentDirtAmount + 0.0001 then
            vehicle:setDirtAmount(requiredDirtAmount)
        end
    end

    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)

    return true
end

local function printSpecValueRecursive(prefix, value, visited, depth)
    visited = visited or {}
    depth = depth or 0

    if type(value) ~= "table" then
        print(string.format("%s = %s", prefix, tostring(value)))
        return
    end

    if visited[value] then
        print(string.format("%s = <recursive>", prefix))
        return
    end

    visited[value] = true
    print(string.format("%s = {", prefix))

    local keys = {}
    for key, _ in pairs(value) do
        table.insert(keys, key)
    end

    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            if type(a) == "number" or type(a) == "string" then
                return a < b
            end
        end
        return tostring(a) < tostring(b)
    end)

    local indent = string.rep("  ", depth + 1)
    for _, key in ipairs(keys) do
        local childPrefix = string.format("%s[%s]", prefix, tostring(key))
        local childValue = value[key]
        if type(childValue) == "table" then
            print(string.format("%s[%s] = {", indent, tostring(key)))
            printSpecValueRecursive(indent .. "  ", childValue, visited, depth + 1)
            print(string.format("%s}", indent))
        else
            print(string.format("%s[%s] = %s", indent, tostring(key), tostring(childValue)))
        end
    end

    print(string.format("%s}", string.rep("  ", depth)))
end

function RealisticMechanicalSystems.ConsoleCommands:setConfigVar(rawArgs, rawValue)
    if not g_currentMission:getIsServer() then
        RMS_ConsoleCommandEvent.sendToServer("setConfigVar", rawArgs, rawValue, nil)
        return
    end
    local path = nil
    local valueToken = nil

    if rawValue ~= nil then
        path = tostring(rawArgs)
        valueToken = tostring(rawValue)
    else
        local args = parseArguments(rawArgs)
        path = args and args[1] or nil
        valueToken = args and args[2] or nil
    end

    if path == nil or valueToken == nil then
        print("RMS Error: Usage: rms_setConfigVar <path> <value>")
        print("Example: rms_setConfigVar CORE.BASE_SYSTEMS_WEAR 0.02")
        return
    end

    local value, valueParsed = parseConsoleValue(valueToken)
    if not valueParsed then
        print("RMS Error: Failed to parse value.")
        return
    end

    local parent, key, _, err = resolvePathParent(RMS_Config, path)
    if parent == nil then
        print(string.format("RMS Error: Invalid RMS_Config path '%s': %s", path, tostring(err)))
        return
    end

    local oldValue = parent[key]
    parent[key] = value

    print(string.format("RMS: RMS_Config.%s changed: %s -> %s", path, tostring(oldValue), tostring(value)))
end

function RealisticMechanicalSystems.ConsoleCommands:setSpecVar(rawArgs, rawValue)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setSpecVar", rawArgs, rawValue, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local path = nil
    local valueToken = nil

    if rawValue ~= nil then
        path = tostring(rawArgs)
        valueToken = tostring(rawValue)
    else
        local args = parseArguments(rawArgs)
        path = args and args[1] or nil
        valueToken = args and args[2] or nil
    end

    if path == nil or valueToken == nil then
        print("RMS Error: Usage: rms_setSpecVar <path> <value>")
        print("Example: rms_setSpecVar systems.engine.condition 0.85")
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local value, valueParsed = parseConsoleValue(valueToken)
    if not valueParsed then
        print("RMS Error: Failed to parse value.")
        return
    end

    local parent, key, _, err = resolvePathParent(spec, path)
    if parent == nil then
        print(string.format("RMS Error: Invalid RMS spec path '%s': %s", path, tostring(err)))
        return
    end

    local oldValue = parent[key]
    parent[key] = value

    local syncedCloggingState = syncConsoleCloggingState(vehicle, spec, parent, key)

    print(string.format("RMS: spec_RealisticMechanicalSystems.%s changed on '%s': %s -> %s", path, vehicle:getFullName(), tostring(oldValue), tostring(value)))
    if syncedCloggingState then
        print(string.format(
            "RMS: clogging state synced on '%s' (dirt=%.2f, radiator=%.2f, airIntake=%.2f).",
            vehicle:getFullName(),
            vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount() or 0,
            tonumber(spec.radiatorClogging) or 0,
            tonumber(spec.airIntakeClogging) or 0
        ))
    end
end

function RealisticMechanicalSystems.ConsoleCommands:printSpecVar(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("printSpecVar", rawArgs, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local args = parseArguments(rawArgs)
    local path = args and args[1] or nil
    if path == nil then
        print("RMS Error: Usage: rms_printSpecVar <path>")
        print("Example: rms_printSpecVar systems.engine")
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local parent, key, _, err = resolvePathParent(spec, path)
    if parent == nil then
        print(string.format("RMS Error: Invalid RMS spec path '%s': %s", path, tostring(err)))
        return
    end

    local value = parent[key]
    if value == nil then
        print(string.format("RMS: spec_RealisticMechanicalSystems.%s = nil", path))
        return
    end

    if type(value) == "table" then
        print(string.format("RMS: spec_RealisticMechanicalSystems.%s on '%s':", path, vehicle:getFullName()))
        printSpecValueRecursive("spec_RealisticMechanicalSystems." .. path, value, {}, 0)
    else
        print(string.format(
            "RMS: spec_RealisticMechanicalSystems.%s on '%s' = %s",
            path,
            vehicle:getFullName(),
            tostring(value)
        ))
    end
end

function RealisticMechanicalSystems.ConsoleCommands:listBreakdowns()
    print("--- Available Breakdowns ---")
    
    local breakdownIds = {}
    for id, data in pairs(RMS_Breakdowns.BreakdownRegistry) do
        table.insert(breakdownIds, string.format(" - %s (%s)", id, data.part or data.system or "No name"))
    end

    if #breakdownIds > 0 then
        table.sort(breakdownIds)
        print(table.concat(breakdownIds, "\n"))
    else
        print("  No breakdowns found in the registry.")
    end
    print("----------------------------")
end

function RealisticMechanicalSystems.ConsoleCommands:addBreakdown(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("addBreakdown", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    if not args or not args[1] then
        local randomId = vehicle:getRandomBreakdown()
        if randomId then
            vehicle:addBreakdown(randomId, 1)
            print(string.format("RMS: Added random breakdown '%s' to '%s'.", randomId, vehicle:getFullName()))
        end
        return
    end

    local breakdownId = string.upper(args[1])
    local stage = tonumber(args[2]) or 1

    local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if not registryEntry then
        print(string.format("RMS Error: Breakdown with ID '%s' not found.", breakdownId))
        self:listBreakdowns()
        return
    end
    
    local maxStages = #registryEntry.stages
    if stage < 1 or stage > maxStages then
        print(string.format("RMS Error: Invalid stage '%d' for breakdown '%s'. Valid stages are 1 to %d.", stage, breakdownId, maxStages))
        return
    end

    if registryEntry.isApplicable ~= nil and not registryEntry.isApplicable(vehicle) then
        print(string.format("RMS Error: Breakdown with ID '%s' not applicable to %s", breakdownId, vehicle:getFullName()))
        return
    end
    
    vehicle:addBreakdown(breakdownId, stage)
    print(string.format("RMS: Added breakdown '%s' at stage %d to '%s'.", breakdownId, stage, vehicle:getFullName()))
end

function RealisticMechanicalSystems.ConsoleCommands:removeBreakdown(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("removeBreakdown", rawArgs, nil, vehicle) end
        return
    end
    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    if args and args[1] then
        local breakdownId = string.upper(args[1])
        vehicle:removeBreakdown(breakdownId)
    else
        vehicle:removeBreakdown() 
    end
end

function RealisticMechanicalSystems.ConsoleCommands:changeBreakdownStage(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("changeBreakdownStage", rawArgs, nil, vehicle) end
        return
    end
    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local advancedCount = 0

    local function parseStageArg(rawValue)
        if rawValue == nil then
            return nil
        end

        local lowered = string.lower(tostring(rawValue))
        if lowered == "true" or lowered == "reverse" or lowered == "down" or lowered == "prev" then
            return true
        end

        local numeric = tonumber(rawValue)
        if numeric ~= nil then
            return numeric
        end

        return nil
    end

    if not args or not args[1] then
        if next(spec.activeBreakdowns) == nil then
            print("RMS: No active breakdowns to advance.")
            return
        end

        for id, breakdown in pairs(vehicle:getActiveBreakdowns()) do
            local previousStage = breakdown.stage
            vehicle:changeBreakdownStage(id)
            if breakdown.stage ~= previousStage then
                print(string.format("RMS: Changed breakdown '%s' from stage %d to stage %d.", id, previousStage, breakdown.stage))
                advancedCount = advancedCount + 1
            else
                print(string.format("RMS: Breakdown '%s' stage unchanged (%d).", id, breakdown.stage))
            end
        end
    else
        local breakdownId = string.upper(args[1])
        local foundBreakdown = spec.activeBreakdowns[breakdownId]

        if not foundBreakdown then
            print(string.format("RMS Error: Active breakdown with ID '%s' not found on this vehicle.", breakdownId))
            return
        end

        local previousStage = foundBreakdown.stage
        vehicle:changeBreakdownStage(breakdownId, parseStageArg(args[2]))
        if foundBreakdown.stage ~= previousStage then
            print(string.format("RMS: Changed breakdown '%s' from stage %d to stage %d.", breakdownId, previousStage, foundBreakdown.stage))
            advancedCount = advancedCount + 1
        else
            print(string.format("RMS: Breakdown '%s' stage unchanged (%d).", breakdownId, foundBreakdown.stage))
        end
    end

    if advancedCount > 0 then
        print(string.format("RMS: Recalculated effects for '%s'.", vehicle:getFullName()))
    end
end

function RealisticMechanicalSystems.ConsoleCommands:setSystemCondition(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setSystemCondition", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end
    
    local spec = vehicle.spec_RealisticMechanicalSystems

    local function resolveSystemKey(rawSystem)
        return RMS_Utils.resolveConsoleSystemKey(spec, rawSystem)
    end

    local requestedSystem = args and args[1] or nil
    if requestedSystem == nil then
        print("RMS Error: Missing system. Usage: rms_setSystemCondition [system] [0.0-1.0]")
        return
    end

    local systemKey = resolveSystemKey(requestedSystem)

    if systemKey == false then
        local availableSystems = {}
        for key, _ in pairs(spec.systems or {}) do
            table.insert(availableSystems, tostring(key))
        end
        table.sort(availableSystems)
        print(string.format("RMS Error: Unknown system '%s'. Available systems: %s", tostring(requestedSystem), table.concat(availableSystems, ", ")))
        return
    end

    local value = tonumber(args and args[2] or nil)
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end

    local systemData = spec.systems[systemKey]
    if type(systemData) == "table" then
        systemData.condition = value
    else
        spec.systems[systemKey] = value
    end
    print(string.format("RMS: Set condition for system '%s' on '%s' to %.2f.", tostring(systemKey), vehicle:getFullName(), value))

    vehicle:updateConditionLevel()
end

function RealisticMechanicalSystems.ConsoleCommands:setCondition(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setCondition", rawArgs, nil, vehicle) end
        return
    end

    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local targetCondition = tonumber(args and args[1] or nil)
    if targetCondition == nil or targetCondition < 0 or targetCondition > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end

    local changedSystems = 0

    for _, systemData in pairs(spec.systems or {}) do
        if type(systemData) == "table" and systemData.enabled ~= false then
            systemData.condition = targetCondition
            changedSystems = changedSystems + 1
        end
    end

    if changedSystems == 0 then
        print("RMS Error: No enabled systems were found on the current vehicle.")
        return
    end

    vehicle:updateConditionLevel()
    print(string.format("RMS: Set condition for %d enabled systems on '%s' to %.3f. Final overall condition: %.3f.",
        changedSystems, vehicle:getFullName(), targetCondition, vehicle.spec_RealisticMechanicalSystems.conditionLevel or 0))
end

function RealisticMechanicalSystems.ConsoleCommands:setSystemStress(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setSystemStress", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems

    local function resolveSystemKey(rawSystem)
        return RMS_Utils.resolveConsoleSystemKey(spec, rawSystem)
    end

    local requestedSystem = args and args[1] or nil
    if requestedSystem == nil then
        print("RMS Error: Missing system. Usage: rms_setSystemStress [system] [>=0.0]")
        return
    end

    local systemKey = resolveSystemKey(requestedSystem)

    if systemKey == false then
        local availableSystems = {}
        for key, _ in pairs(spec.systems or {}) do
            table.insert(availableSystems, tostring(key))
        end
        table.sort(availableSystems)
        print(string.format("RMS Error: Unknown system '%s'. Available systems: %s", tostring(requestedSystem), table.concat(availableSystems, ", ")))
        return
    end

    local value = tonumber(args and args[2] or nil)
    if value == nil or value < 0 then
        print("RMS Error: Invalid value. Please provide a number >= 0.0.")
        return
    end

    local systemData = spec.systems[systemKey]
    if type(systemData) == "table" then
        systemData.stress = value
    else
        spec.systems[systemKey] = { condition = systemData or 1.0, stress = value }
    end
    print(string.format("RMS: Set stress for system '%s' on '%s' to %.4f.", tostring(systemKey), vehicle:getFullName(), value))
end

function RealisticMechanicalSystems.ConsoleCommands:setSystemStressMultiplier(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setSystemStressMultiplier", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local multipliers = RMS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS

    if multipliers == nil then
        print("RMS Error: SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS is missing in config.")
        return
    end

    local value = 1.0
    if args and args[1] then
        local parsedValue = tonumber(args[1])
        if parsedValue == nil or parsedValue < 0 then
            print("RMS Error: Invalid value. Please provide a number >= 0.0.")
            return
        end
        value = parsedValue
    end

    local function resolveSystemKey(rawSystem)
        return RMS_Utils.resolveConsoleSystemKey(spec, rawSystem)
    end

    local requestedSystem = args and args[2] or nil
    local systemKey = resolveSystemKey(requestedSystem)

    if systemKey == false then
        local availableSystems = {}
        for key, _ in pairs(spec.systems or {}) do
            table.insert(availableSystems, tostring(key))
        end
        table.sort(availableSystems)
        print(string.format("RMS Error: Unknown system '%s'. Available systems: %s", tostring(requestedSystem), table.concat(availableSystems, ", ")))
        return
    end

    if systemKey == nil then
        for key, _ in pairs(multipliers) do
            if type(key) == "string" then
                multipliers[key] = value
            end
        end
        print(string.format("RMS: Set stress accumulation multiplier for all systems to %.4f.", value))
    else
        multipliers[systemKey] = value
        print(string.format("RMS: Set stress accumulation multiplier for system '%s' to %.4f.", tostring(systemKey), value))
    end
end

function RealisticMechanicalSystems.ConsoleCommands:setService(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setService", rawArgs, nil, vehicle) end
        return
    end
    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end
    
    local spec = vehicle.spec_RealisticMechanicalSystems
    local value = 1.0

    if args and args[1] then
        local parsedValue = tonumber(args[1])
        if parsedValue == nil or parsedValue < 0 or parsedValue > 1 then
            print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
            return
        end
        value = parsedValue
    end
    
    spec.serviceLevel = value

    local interval = vehicle:getMaintenanceInterval()
    local currentHours = spec.realOperatingTime / (60 * 60 * 1000) or vehicle:getFormattedOperatingTime() or 0
    local serviceExpiredThreshold = math.clamp(tonumber(RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD) or 0.5, 0, 0.9999)
    local activeServiceRange = math.max(1 - serviceExpiredThreshold, 0.0001)
    local hoursSinceService = ((1 - value) / activeServiceRange) * interval
    local targetOpHours = currentHours - hoursSinceService
    local found = false
    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE or entry.id == 1 then
            entry.conditionData.operatingHours = targetOpHours
            entry.conditionData.service = value
            if vehicle.isServer then
                RMS_LogEntrySyncEvent.sendToClients(vehicle, entry)
            end
            found = true
            break
        end
    end
    if not found and vehicle.isServer then
        vehicle:addEntryToMaintenanceLog(RealisticMechanicalSystems.STATUS.INSPECTION, RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD, "NONE", false, 0)
        local entry = spec.maintenanceLog[#spec.maintenanceLog]
        entry.conditionData.operatingHours = targetOpHours
        entry.conditionData.service = value
        entry.isVisible = false
        RMS_LogEntrySyncEvent.sendToClients(vehicle, entry)
    end

    print(string.format("RMS: Set Service level for '%s' to %.2f.", vehicle:getFullName(), value))
end

function RealisticMechanicalSystems.ConsoleCommands:resetVehicle()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("resetVehicle", nil, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end
    
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.conditionLevel = 1.0
    spec.serviceLevel = 1.0
    vehicle:removeBreakdown()

    local currentHours = vehicle:getFormattedOperatingTime()
    local found = false
    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE or entry.id == 1 then
            entry.conditionData.operatingHours = currentHours
            entry.conditionData.condition = 1.0
            entry.conditionData.service = 1.0
            if vehicle.isServer then
                RMS_LogEntrySyncEvent.sendToClients(vehicle, entry)
            end
            found = true
            break
        end
    end
    if not found and vehicle.isServer then
        vehicle:addEntryToMaintenanceLog(RealisticMechanicalSystems.STATUS.INSPECTION, RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD, "NONE", false, 0)
        local entry = spec.maintenanceLog[#spec.maintenanceLog]
        entry.conditionData.operatingHours = currentHours
        entry.conditionData.condition = 1.0
        entry.conditionData.service = 1.0
        entry.isVisible = false
        RMS_LogEntrySyncEvent.sendToClients(vehicle, entry)
    end

    print(string.format("RMS: Fully reset state for '%s'.", vehicle:getFullName()))
end

function RealisticMechanicalSystems.ConsoleCommands:reinitializeVehicle()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("reinitializeVehicle", nil, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local ok, targetCondition = initializeVehicleConditionFromVanillaPrice(vehicle, true)
    if not ok then
        print(string.format("RMS Error: Failed to reinitialize '%s'.", vehicle:getFullName()))
        return
    end

    print(string.format(
        "RMS: Reinitialized '%s' from vanilla resale price. Target condition: %.3f, final overall condition: %.3f.",
        vehicle:getFullName(),
        targetCondition or 0,
        vehicle.spec_RealisticMechanicalSystems.conditionLevel or 0
    ))
end

function RealisticMechanicalSystems.ConsoleCommands:startMaintance(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("startMaintance", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY then
        print(string.format("RMS Error: Vehicle '%s' is already under service (%s).", vehicle:getFullName(), spec.currentState))
        return
    end

    if not args or not args[1] then
        print("RMS Error: Missing argument. Usage: rms_startService <type> [count]")
        print("Available types: inspection, maintenance, repair, overhaul")
        return
    end

    local maintenanceType = string.lower(args[1])
    local isValidType = false

    for stateName, state in pairs(RealisticMechanicalSystems.STATUS) do
        if string.lower(stateName) == maintenanceType then
            isValidType = true
            maintenanceType = state
            break
        end
    end
    
    if not isValidType or maintenanceType == RealisticMechanicalSystems.STATUS.READY then
        print("RMS Error: Invalid maintenance type '"..maintenanceType.."'")
        print("Available types: inspection, maintenance, repair, overhaul")
        return
    end

    local breakdownCount = tonumber(args[2]) or 1
    local optionOne, optionTwo, optionThree

    if maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        optionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
        optionTwo = "NONE"
        optionThree = false
    elseif maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionOne = RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD
        optionTwo = RealisticMechanicalSystems.PART_TYPES.OEM
        optionThree = false
    elseif maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionOne = RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
        optionTwo = RealisticMechanicalSystems.PART_TYPES.OEM
        optionThree = false

        local visibleRepairableCount = 0
        local selected = 0
        for breakdownId, breakdown in pairs(vehicle:getActiveBreakdowns()) do
            local isRepairable = breakdown ~= nil and breakdown.isVisible == true
            if isRepairable then
                visibleRepairableCount = visibleRepairableCount + 1
            end

            if selected < breakdownCount and isRepairable then
                breakdown.isSelectedForRepair = true
                selected = selected + 1
            else
                breakdown.isSelectedForRepair = false
            end
        end

        if visibleRepairableCount == 0 then
            print(string.format("RMS Error: Vehicle '%s' has no visible breakdowns for repair.", vehicle:getFullName()))
            return
        end

        if selected == 0 then
            print(string.format("RMS Error: No breakdowns selected for repair on '%s'.", vehicle:getFullName()))
            return
        end
    elseif maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionOne = RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD
        optionTwo = "NONE"
        optionThree = false
    end

    vehicle:initService(maintenanceType, RealisticMechanicalSystems.WORKSHOP.OWN, optionOne, optionTwo, optionThree)

    if spec.currentState == maintenanceType and (spec.maintenanceTimer or 0) > 0 then
        local finishTime, days = vehicle:getServiceFinishTime()
        print(string.format("RMS: Started '%s' for '%s'. Remaining time: %.1f sec. Finishes in %d day(s) at %.2f.", maintenanceType, vehicle:getFullName(), spec.maintenanceTimer / 1000, days or 0, finishTime or 0))
    else
        print(string.format("RMS Error: Failed to start '%s' for '%s'.", maintenanceType, vehicle:getFullName()))
    end
end

function RealisticMechanicalSystems.ConsoleCommands:finishMaintance()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("finishMaintance", nil, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.currentState == RealisticMechanicalSystems.STATUS.READY then
        print(string.format("RMS: Vehicle '%s' is not under service.", vehicle:getFullName()))
        return
    end

    local currentState = spec.currentState
    local finished, err = RealisticMechanicalSystems.forceFinishService(vehicle)

    if not finished then
        print(string.format("RMS Error: Failed to force-finish service for '%s': %s", vehicle:getFullName(), tostring(err)))
        return
    end

    print(string.format("RMS: Service '%s' force-finished for '%s'.", currentState, vehicle:getFullName()))
end

function RealisticMechanicalSystems.ConsoleCommands:getServiceState()
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local progressPercent = 0
    if (spec.pendingProgressTotalTime or 0) > 0 then
        progressPercent = math.floor(math.max(0, math.min((spec.pendingProgressElapsedTime or 0) / spec.pendingProgressTotalTime, 1)) * 100)
    end

    local selectedForRepairCount = 0
    local activeBreakdownsCount = 0
    for _, breakdown in pairs(spec.activeBreakdowns or {}) do
        activeBreakdownsCount = activeBreakdownsCount + 1
        if breakdown ~= nil and breakdown.isSelectedForRepair then
            selectedForRepairCount = selectedForRepairCount + 1
        end
    end

    print("--- RMS Service State ---")
    print(string.format("Vehicle: %s", vehicle:getFullName()))
    print(string.format("State: current=%s planned=%s workshop=%s", tostring(spec.currentState), tostring(spec.plannedState), tostring(spec.workshopType)))
    print(string.format("Timer: maintenanceTimer=%.0fms elapsed=%.0fms total=%.0fms progress=%d%% stepIndex=%d",
        spec.maintenanceTimer or 0, spec.pendingProgressElapsedTime or 0, spec.pendingProgressTotalTime or 0, progressPercent, spec.pendingProgressStepIndex or 0))
    print(string.format("Options: optionOne=%s optionTwo=%s optionThree=%s price=%s",
        tostring(spec.serviceOptionOne), tostring(spec.serviceOptionTwo), tostring(spec.serviceOptionThree), tostring(spec.pendingServicePrice)))
    local pendingOverhaulSystemsCount = 0
    for _, _ in pairs(spec.pendingOverhaulSystemTarget or {}) do
        pendingOverhaulSystemsCount = pendingOverhaulSystemsCount + 1
    end

    print(string.format("Targets: serviceStart=%s serviceTarget=%s overhaulSystems=%d",
        tostring(spec.pendingMaintenanceServiceStart), tostring(spec.pendingMaintenanceServiceTarget), pendingOverhaulSystemsCount))
    print(string.format("Levels: service=%.4f condition=%.4f", spec.serviceLevel or 0, spec.conditionLevel or 0))
    print(string.format("Queues: selected=%d inspection=%d repair=%d", #(spec.pendingSelectedBreakdowns or {}), #(spec.pendingInspectionQueue or {}), #(spec.pendingRepairQueue or {})))
    print(string.format("Breakdowns: active=%d selectedForRepair=%d", activeBreakdownsCount, selectedForRepairCount))

    if #(spec.pendingSelectedBreakdowns or {}) > 0 then
        print("pendingSelectedBreakdowns: " .. table.concat(spec.pendingSelectedBreakdowns, ", "))
    end
    if #(spec.pendingInspectionQueue or {}) > 0 then
        print("pendingInspectionQueue: " .. table.concat(spec.pendingInspectionQueue, ", "))
    end
    if #(spec.pendingRepairQueue or {}) > 0 then
        print("pendingRepairQueue: " .. table.concat(spec.pendingRepairQueue, ", "))
    end
end

function RealisticMechanicalSystems.ConsoleCommands:showServiceLog(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local log = spec.maintenanceLog or {}
    local args = parseArguments(rawArgs)

    if #log == 0 then
        print("RMS: Service log is empty.")
        return
    end

    local function formatDate(date)
        if date == nil then
            return "n/a"
        end
        return string.format("%02d/%02d/%04d", date.day or 0, date.month or 0, date.year or 0)
    end

    local function formatList(value)
        if value == nil or #value == 0 then
            return "-"
        end
        return table.concat(value, ", ")
    end

    local function printLogEntry(index, entry, verbose)
        local cond = entry.conditionData or {}
        local selectedBreakdowns = cond.selectedBreakdowns or {}
        local activeBreakdownsCount = 0
        for _, _ in pairs(cond.activeBreakdowns or {}) do
            activeBreakdownsCount = activeBreakdownsCount + 1
        end

        print(string.format("[%d] id=%s type=%s date=%s price=%s visible=%s completed=%s",
            index, tostring(entry.id), tostring(entry.type), formatDate(entry.date), tostring(entry.price), tostring(entry.isVisible), tostring(entry.isCompleted ~= false)))
        print(string.format("    options: one=%s two=%s three=%s location=%s",
            tostring(entry.optionOne), tostring(entry.optionTwo), tostring(entry.optionThree), tostring(entry.location)))

        if verbose then
            print(string.format("    conditionData: year=%s opHours=%s age=%s condition=%s service=%s reliability=%s maintainability=%s",
                tostring(cond.year), tostring(cond.operatingHours), tostring(cond.age), tostring(cond.condition), tostring(cond.service), tostring(cond.reliability), tostring(cond.maintainability)))
            local systemsCount = 0
            for _, _ in pairs(cond.systems or {}) do
                systemsCount = systemsCount + 1
            end
            print(string.format("    conditionData: batterySoc=%s systems=%d",
                tostring(cond.batterySoc), systemsCount))
            print(string.format("    conditionData: activeBreakdowns=%d selectedBreakdowns=%d", activeBreakdownsCount, #selectedBreakdowns))
            print("    selectedBreakdowns: " .. formatList(selectedBreakdowns))
        end
    end

    if args ~= nil and args[1] ~= nil then
        local index = tonumber(args[1])
        if index == nil or index < 1 or index > #log then
            print(string.format("RMS Error: Invalid log index '%s'. Valid range: 1..%d", tostring(args[1]), #log))
            return
        end

        print(string.format("--- RMS Service Log Entry %d/%d ---", index, #log))
        printLogEntry(index, log[index], true)
        return
    end

    print(string.format("--- RMS Service Log (%d entries) ---", #log))
    for i, entry in ipairs(log) do
        printLogEntry(i, entry, false)
    end
end

function RealisticMechanicalSystems.ConsoleCommands:getDebugVehicleInfo(rawArgs)
    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end
    
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motor = vehicle:getMotor()

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    print("--- Vehicle Debug Info ---")
    print(string.format("RawBrand: %s", g_brandManager:getBrandByIndex(vehicle:getBrand()).name))
    print(string.format("Name: %s", vehicle:getFullName()))
    print(string.format("Type/Category: %s/%s", vehicle.type.name, storeItem.categoryName))
    print(string.format("Property state: %s", vehicle.propertyState))
    print(string.format("Transmission: %s, %s, %s", motor.minForwardGearRatio, motor.gearType, motor.groupType))
    print(string.format("RMS transmission type: %s", tostring(vehicle:getTransmissionType())))
    print(string.format("XML/shop transmission name: %s", tostring(RealisticMechanicalSystems.getTransmissionNameFromXML(vehicle))))

    local hasTurboBaseSound = false
    local hasTurboCurrentConfigSound = false
    local hasTurboAnyConfigSound = false
    local hasTurboLoadedSample = false
    local turboMotorConfigKey = "-"
    local turboConfigIndices = {}
    local motorConfigCount = 0

    if vehicle.xmlFile ~= nil and vehicle.xmlFile.hasProperty ~= nil then
        hasTurboBaseSound = vehicle.xmlFile:hasProperty("vehicle.motorized.sounds.blowOffValve")

        local motorConfigIndex = 1
        if vehicle.configurations ~= nil and vehicle.configurations.motor ~= nil then
            motorConfigIndex = math.max(tonumber(vehicle.configurations.motor) or 1, 1)
        end

        turboMotorConfigKey = string.format("vehicle.motorized.motorConfigurations.motorConfiguration(%d)", motorConfigIndex - 1)
        hasTurboCurrentConfigSound = vehicle.xmlFile:hasProperty(turboMotorConfigKey .. ".sounds.blowOffValve")

        local maxScanCount = 64
        for idx = 0, maxScanCount - 1 do
            local cfgKey = string.format("vehicle.motorized.motorConfigurations.motorConfiguration(%d)", idx)
            if not vehicle.xmlFile:hasProperty(cfgKey) then
                break
            end

            motorConfigCount = motorConfigCount + 1
            if vehicle.xmlFile:hasProperty(cfgKey .. ".sounds.blowOffValve") then
                hasTurboAnyConfigSound = true
                table.insert(turboConfigIndices, tostring(idx + 1))
            end
        end
    end

    local spec_motorized = vehicle.spec_motorized
    if spec_motorized ~= nil and spec_motorized.samples ~= nil then
        hasTurboLoadedSample = spec_motorized.samples.blowOffValve ~= nil
    end

    local turboConfigList = (#turboConfigIndices > 0) and table.concat(turboConfigIndices, ",") or "-"
    local hasTurbo = hasTurboBaseSound or hasTurboCurrentConfigSound or hasTurboAnyConfigSound or hasTurboLoadedSample
    print(string.format(
        "Turbo detect: %s | base=%s | cfgCurrent=%s | cfgAny=%s (%s/%d) | sample=%s | motorCfgKey=%s",
        tostring(hasTurbo),
        tostring(hasTurboBaseSound),
        tostring(hasTurboCurrentConfigSound),
        tostring(hasTurboAnyConfigSound),
        turboConfigList,
        motorConfigCount,
        tostring(hasTurboLoadedSample),
        tostring(turboMotorConfigKey)
    ))

    for _, entry in ipairs(spec.maintenanceLog) do
        for _, breakdown in pairs(entry.conditionData.selectedBreakdowns) do
            print(breakdown)
        end
    end

    if vehicle.spec_attacherJoints and vehicle.spec_attacherJoints.attachedImplements then
        for _, v in pairs(vehicle.spec_attacherJoints.attachedImplements) do
            if v.object.speedLimit ~= nil then
                print(v.object:getFullName() .. " " .. v.object.speedLimit)
            end
	    end
    end

    if args and args[1] then
        print("--------------------------")

        if vehicle.type and vehicle.type.specializationNames then
            local specNamesCopy = {}
            for _, specName in ipairs(vehicle.type.specializationNames) do
                table.insert(specNamesCopy, specName)
            end
            
            table.sort(specNamesCopy)
            
            print("Attached Specializations (" .. #specNamesCopy .. " total):")
            for i, specName in ipairs(specNamesCopy) do
                print(string.format("  %d. %s", i, specName))
            end
        else
            print("No specializations found for this vehicle type.")
        end
        
        print("--------------------------")
    end
end

function RealisticMechanicalSystems.ConsoleCommands:setDirtAmount(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setDirtAmount", rawArgs, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        print("RMS Error: No target vehicle found. Please enter a vehicle.")
        return 
    end

    if vehicle.spec_washable == nil then
        print(string.format("RMS Error: Vehicle '%s' is not washable.", vehicle:getFullName()))
        return
    end

    local args = parseArguments(rawArgs)
    
    if not args or not args[1] then
        print("RMS Error: Missing argument. Usage: rms_setDirtAmount <amount>")
        print("Please provide a dirt amount between 0.0 (clean) and 1.0 (fully dirty).")
        return
    end

    local value = tonumber(args[1])
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end
    
    vehicle:setDirtAmount(value)
    
    print(string.format("RMS: Set Dirt amount for '%s' to %.2f.", vehicle:getFullName(), value))
end

function RealisticMechanicalSystems.ConsoleCommands:setFuelLevel(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setFuelLevel", rawArgs, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local args = parseArguments(rawArgs)
    if not args or not args[1] then
        print("RMS Error: Usage: rms_setFuelLevel <value>")
        print("Value: 0.0..1.0 or 0..100 (percent)")
        print("Example: rms_setFuelLevel 0.25")
        print("Example: rms_setFuelLevel 25")
        return
    end

    local inputValue = tonumber(args[1])
    if inputValue == nil then
        print("RMS Error: Invalid value. Expected number.")
        return
    end

    if inputValue > 1 then
        if inputValue <= 100 then
            inputValue = inputValue / 100
        else
            print("RMS Error: Value must be 0.0..1.0 or 0..100.")
            return
        end
    end

    if inputValue < 0 or inputValue > 1 then
        print("RMS Error: Value must be between 0.0 and 1.0 (or 0..100%).")
        return
    end

    local fillUnitIndex, fillType = getPrimaryFuelConsumerInfo(vehicle)
    if fillUnitIndex == nil or fillType == nil then
        print(string.format("RMS Error: Fuel consumer not found for '%s'.", vehicle:getFullName()))
        return
    end

    local capacity = tonumber(vehicle:getFillUnitCapacity(fillUnitIndex)) or 0
    if capacity <= 0 then
        print(string.format("RMS Error: Invalid fuel capacity for '%s' (fillUnit %s).", vehicle:getFullName(), tostring(fillUnitIndex)))
        return
    end

    local currentLevel = tonumber(vehicle:getFillUnitFillLevel(fillUnitIndex)) or 0
    local targetLevel = math.clamp(capacity * inputValue, 0, capacity)
    local delta = targetLevel - currentLevel

    if math.abs(delta) > 0.0001 then
        vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), fillUnitIndex, delta, fillType, ToolType.UNDEFINED)
    end

    local resultLevel = tonumber(vehicle:getFillUnitFillLevel(fillUnitIndex)) or targetLevel
    local resultRatio = resultLevel / math.max(capacity, 0.0001)
    print(string.format(
        "RMS: Fuel level set on '%s' -> %.1f / %.1f L (%.1f%%), fillType=%s, fillUnit=%s",
        vehicle:getFullName(),
        resultLevel,
        capacity,
        resultRatio * 100,
        tostring(fillType),
        tostring(fillUnitIndex)
    ))
end

function RealisticMechanicalSystems.ConsoleCommands:setHorsePower(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setHorsePower", rawArgs, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local args = parseArguments(rawArgs)
    if not args or not args[1] then
        print("RMS Error: Usage: rms_setHorsePower <hp>")
        return
    end

    local targetHp = tonumber(args[1])
    if targetHp == nil or targetHp <= 0 then
        print("RMS Error: Horsepower must be a positive number.")
        return
    end

    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    if motor == nil or motor.torqueCurve == nil or motor.torqueCurve.keyframes == nil then
        print(string.format("RMS Error: Vehicle '%s' has no editable motor torque curve.", vehicle:getFullName()))
        return
    end

    local currentPeakKw = tonumber(motor.peakMotorPower) or 0
    if currentPeakKw <= 0 then
        print(string.format("RMS Error: Vehicle '%s' has invalid peak motor power.", vehicle:getFullName()))
        return
    end

    local targetPeakKw = targetHp / 1.36
    local scale = targetPeakKw / currentPeakKw
    local scaledKeys = 0

    for _, keyframe in ipairs(motor.torqueCurve.keyframes) do
        if type(keyframe) == "table" then
            if keyframe[1] ~= nil then
                keyframe[1] = keyframe[1] * scale
                scaledKeys = scaledKeys + 1
            elseif keyframe.value ~= nil then
                keyframe.value = keyframe.value * scale
                scaledKeys = scaledKeys + 1
            end
        end
    end

    if scaledKeys == 0 then
        print(string.format("RMS Error: Failed to scale torque curve for '%s'.", vehicle:getFullName()))
        return
    end

    motor.peakMotorTorque = motor.torqueCurve:getMaximum()
    motor.peakMotorPower = 0
    motor.peakMotorPowerRotSpeed = 0

    local numKeyFrames = #motor.torqueCurve.keyframes
    if numKeyFrames >= 2 then
        for i = 2, numKeyFrames do
            local v0 = motor.torqueCurve.keyframes[i - 1]
            local v1 = motor.torqueCurve.keyframes[i]
            local torque0 = motor.torqueCurve:getFromKeyframes(v0, v0, i - 1, i - 1, 0)
            local torque1 = motor.torqueCurve:getFromKeyframes(v1, v1, i, i, 0)
            local rpm
            local torque

            if math.abs(torque0 - torque1) > 0.0001 then
                rpm = (v1.time * torque0 - v0.time * torque1) / (2.0 * (torque0 - torque1))
                rpm = math.min(math.max(rpm, v0.time), v1.time)
                torque = motor.torqueCurve:getFromKeyframes(v0, v1, i - 1, i, (v1.time - rpm) / (v1.time - v0.time))
            else
                rpm = v0.time
                torque = torque0
            end

            local power = torque * rpm
            if power > motor.peakMotorPower then
                motor.peakMotorPower = power
                motor.peakMotorPowerRotSpeed = rpm
            end
        end

        motor.peakMotorPower = motor.peakMotorPower * math.pi / 30
        motor.peakMotorPowerRotSpeed = motor.peakMotorPowerRotSpeed * math.pi / 30
    elseif numKeyFrames == 1 then
        local v = motor.torqueCurve.keyframes[1]
        local rotSpeed = v.time * math.pi / 30
        local torque = motor.torqueCurve:getFromKeyframes(v, v, 1, 1, 0)
        motor.peakMotorPower = rotSpeed * torque
        motor.peakMotorPowerRotSpeed = rotSpeed
    end

    if vehicle.updateMotorProperties ~= nil then
        vehicle:updateMotorProperties()
    end

    local function refreshAttachedPeakPower(rootVehicle)
        if rootVehicle == nil or rootVehicle.getAttachedImplements == nil then
            return
        end

        local rootPeakMotorPower = rootVehicle.getMotor ~= nil and rootVehicle:getMotor().peakMotorPower or math.huge
        for _, implement in pairs(rootVehicle:getAttachedImplements()) do
            local object = implement ~= nil and implement.object or nil
            if object ~= nil then
                if object.spec_powerConsumer ~= nil then
                    object.spec_powerConsumer.sourceMotorPeakPower = rootPeakMotorPower
                end
                refreshAttachedPeakPower(object)
            end
        end
    end

    refreshAttachedPeakPower(vehicle)

    local specMotorized = vehicle.spec_motorized
    if specMotorized ~= nil and specMotorized.motorizedNode ~= nil and I3DUtil ~= nil and I3DUtil.wakeUpObject ~= nil then
        I3DUtil.wakeUpObject(specMotorized.motorizedNode)
    end

    print(string.format(
        "RMS: Set horsepower for '%s' to %.1f hp (was %.1f hp).",
        vehicle:getFullName(),
        (tonumber(motor.peakMotorPower) or 0) * 1.36,
        currentPeakKw * 1.36
    ))
end

function RealisticMechanicalSystems.ConsoleCommands:setOperatingTime(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setOperatingTime", rawArgs, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local args = parseArguments(rawArgs)
    if not args or not args[1] then
        print("RMS Error: Usage: rms_setOperatingTime <hours>")
        print("Example: rms_setOperatingTime 22.1")
        return
    end

    local hours = tonumber(args[1])
    if hours == nil or hours < 0 then
        print("RMS Error: Operating time must be a number >= 0.")
        return
    end

    local operatingTimeMs = hours * 60 * 60 * 1000
    local previousOperatingTimeMs = getSyncOperatingTime(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems

    spec._allowRMSOperatingTimeWrite = true
    vehicle:setOperatingTime(operatingTimeMs, false)
    spec._allowRMSOperatingTimeWrite = false
    spec.realOperatingTime = operatingTimeMs

    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.TELEMETRY)

    print(string.format(
        "RMS: Operating time for '%s' changed: %.2f h -> %.2f h (%.0f ms).",
        vehicle:getFullName(),
        previousOperatingTimeMs / (60 * 60 * 1000),
        operatingTimeMs / (60 * 60 * 1000),
        operatingTimeMs
    ))
end

function RealisticMechanicalSystems.ConsoleCommands:setPlowMaxForce(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setPlowMaxForce", rawArgs, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local args = parseArguments(rawArgs)
    if not args or not args[1] then
        print("RMS Error: Usage: rms_setPlowMaxForce <kN>")
        return
    end

    local targetMaxForce = tonumber(args[1])
    if targetMaxForce == nil or targetMaxForce < 0 then
        print("RMS Error: Max force must be a number >= 0.")
        return
    end

    local implement = nil
    if vehicle.getSelectedImplement ~= nil then
        local selectedImplement = vehicle:getSelectedImplement()
        local selectedObject = selectedImplement ~= nil and selectedImplement.object or nil
        if selectedObject ~= nil and selectedObject.spec_powerConsumer ~= nil then
            implement = selectedObject
        end
    end

    if implement == nil and vehicle.getAttachedImplements ~= nil then
        for _, attachedImplement in pairs(vehicle:getAttachedImplements()) do
            local object = attachedImplement ~= nil and attachedImplement.object or nil
            if object ~= nil and object.spec_plow ~= nil and object.spec_powerConsumer ~= nil then
                implement = object
                break
            end
        end
    end

    if implement == nil and vehicle.getAttachedImplements ~= nil then
        for _, attachedImplement in pairs(vehicle:getAttachedImplements()) do
            local object = attachedImplement ~= nil and attachedImplement.object or nil
            if object ~= nil and object.spec_powerConsumer ~= nil then
                implement = object
                break
            end
        end
    end

    if implement == nil or implement.spec_powerConsumer == nil then
        print(string.format("RMS Error: No attached plow/implement with powerConsumer found for '%s'.", vehicle:getFullName()))
        return
    end

    local specPowerConsumer = implement.spec_powerConsumer
    local previousMaxForce = tonumber(specPowerConsumer.maxForce) or 0
    specPowerConsumer.maxForce = targetMaxForce
    if specPowerConsumer.maxForceOrig ~= nil then
        specPowerConsumer.maxForceOrig = targetMaxForce
    end

    print(string.format(
        "RMS: Set maxForce for '%s' to %.2f kN (was %.2f kN).",
        implement.getFullName ~= nil and implement:getFullName() or tostring(implement.configFileName or "implement"),
        specPowerConsumer.maxForce,
        previousMaxForce
    ))
end

function RealisticMechanicalSystems.ConsoleCommands:resetFactorStats()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("resetFactorStats", nil, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local factorStats = ensureFactorStats(spec, vehicle)

    for _, systemStats in pairs(factorStats) do
        if type(systemStats) == "table" then
            for key, value in pairs(systemStats) do
                if key ~= "operatingHours" and tonumber(value) ~= nil then
                    systemStats[key] = 0
                end
            end
            systemStats.total = 0
            systemStats.stress = 0
            systemStats.operatingHours = getVehicleOperatingHours(vehicle)
        end
    end

    print(string.format("RMS: Factor stats reset for '%s'.", vehicle:getFullName()))
end

function RealisticMechanicalSystems.ConsoleCommands:toggleHudDebugView(rawArgs)
    local args = parseArguments(rawArgs)
    local requestedMode = args and args[1] and string.lower(tostring(args[1])) or nil
    local currentMode = tostring((RMS_Hud ~= nil and RMS_Hud.debugViewMode) or "default")
    local nextMode = "default"

    if requestedMode == nil or requestedMode == "" or requestedMode == "toggle" then
        if currentMode == "factorStats" then
            nextMode = "default"
        else
            nextMode = "factorStats"
        end
    elseif requestedMode == "default" or requestedMode == "normal" then
        nextMode = "default"
    elseif requestedMode == "stats" or requestedMode == "stat" or requestedMode == "factorstats" or requestedMode == "factor_stats" then
        nextMode = "factorStats"
    else
        print("RMS Error: Usage: rms_toggleHudDebugView [default|stats|toggle]")
        return
    end

    if RMS_Hud ~= nil then
        RMS_Hud.debugViewMode = nextMode
    end

    print(string.format("RMS: HUD debug view mode = %s", nextMode))
end

function RealisticMechanicalSystems.ConsoleCommands:setExcluded(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setExcluded", rawArgs, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local args = parseArguments(rawArgs)
    local rawValue = args and args[1] and string.lower(tostring(args[1])) or nil

    if rawValue == nil then
        print(string.format(
            "RMS: '%s' exclusion state: user=%s, rule=%s, unsupported=%s, effective=%s. Usage: rms_setExcluded <true|false>",
            vehicle:getFullName(),
            tostring(spec.isExcludedByUser),
            tostring(spec.isExcludedByRule == true),
            tostring(spec.isExcludedByDefault == true),
            tostring(spec.isExcludedVehicle == true)
        ))
        return
    end

    local isExcluded
    if rawValue == "true" or rawValue == "1" or rawValue == "on" or rawValue == "yes" then
        isExcluded = true
    elseif rawValue == "false" or rawValue == "0" or rawValue == "off" or rawValue == "no" then
        isExcluded = false
    else
        print("RMS Error: Usage: rms_setExcluded <true|false>")
        return
    end

    local changed, reason = vehicle:setRMSUserExcluded(isExcluded)
    if reason == "default" then
        print(string.format("RMS: '%s' is not supported by RMS and cannot be managed.", vehicle:getFullName()))
        return
    end

    if not changed then
        print(string.format("RMS: '%s' is already %s by the user flag.", vehicle:getFullName(), isExcluded and "excluded" or "included"))
        return
    end

    print(string.format("RMS: '%s' is now %s.", vehicle:getFullName(), isExcluded and "excluded from RMS" or "managed by RMS"))
end

function RealisticMechanicalSystems.ConsoleCommands:debug()
    if not g_currentMission:getIsServer() then
        RMS_ConsoleCommandEvent.sendToServer("debug", nil, nil, nil)
        return
    end
    if RMS_Config.DEBUG then
        RMS_Config.DEBUG = false
    else
        RMS_Config.DEBUG = true
    end
    if g_server ~= nil and RMS_SettingsSyncEvent ~= nil then
        g_server:broadcastEvent(RMS_SettingsSyncEvent.new())
    end
end

addConsoleCommand("rms_listBreakdowns", "Lists all available breakdown IDs.", "listBreakdowns", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_addBreakdown", "Adds a breakdown. Usage: rms_addBreakdown [id] [stage]", "addBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_removeBreakdown", "Removes a breakdown. Usage: rms_removeBreakdown [id]", "removeBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_advanceBreakdown", "Advances a breakdown to the next stage. Usage: rms_advanceBreakdown [id]", "changeBreakdownStage", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setCondition", "Sets condition for all enabled systems. Usage: rms_setCondition [0.0-1.0]", "setCondition", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSystemCondition", "Sets system condition. Usage: rms_setSystemCondition [system] [0.0-1.0]", "setSystemCondition", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSystemStress", "Sets system stress. Usage: rms_setSystemStress [system] [>=0.0]", "setSystemStress", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSystemStressMultiplier", "Sets stress accumulation multiplier. Usage: rms_setSystemStressMultiplier [>=0.0] [system]", "setSystemStressMultiplier", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setService", "Sets vehicle service. Usage: rms_setService [0.0-1.0]", "setService", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_resetVehicle", "Resets vehicle state.", "resetVehicle", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_reinitializeVehicle", "Reinitializes vehicle from vanilla resale price logic.", "reinitializeVehicle", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_startService", "Starts service. Usage: rms_startService <type> [count]", "startMaintance", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_finishService", "Instantly finishes current service.", "finishMaintance", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_getServiceState", "Prints current service/workshop state variables.", "getServiceState", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_showServiceLog", "Shows service log. Usage: rms_showServiceLog [index]", "showServiceLog", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_getDebugVehicleInfo", "Vehicle debug info", "getDebugVehicleInfo", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setDirtAmount", "Sets vehicle dirt amount. Usage: rms_setDirtAmount [0.0-1.0]", "setDirtAmount", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setFuelLevel", "Sets vehicle fuel level. Usage: rms_setFuelLevel [0.0-1.0 or 0..100]", "setFuelLevel", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setHorsePower", "Sets horsepower on current vehicle. Usage: rms_setHorsePower [hp]", "setHorsePower", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setOperatingTime", "Sets operating time on current vehicle. Usage: rms_setOperatingTime [hours]", "setOperatingTime", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setPlowMaxForce", "Sets maxForce on selected/attached plow. Usage: rms_setPlowMaxForce [kN]", "setPlowMaxForce", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_resetFactorStats", "Resets accumulated factor stats for current vehicle.", "resetFactorStats", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_toggleHudDebugView", "Switch debug HUD view. Usage: rms_toggleHudDebugView [default|stats|toggle]", "toggleHudDebugView", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setExcluded", "Excludes or includes the current vehicle in RMS. Usage: rms_setExcluded <true|false>", "setExcluded", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_debug", "Enbales/disabled RMS debug", "debug", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setConfigVar", "Sets RMS_Config variable. Usage: rms_setConfigVar <path> <value>", "setConfigVar", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSpecVar", "Sets RMS specialization variable on current vehicle. Usage: rms_setSpecVar <path> <value>", "setSpecVar", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_printSpecVar", "Prints RMS specialization variable on current vehicle. Usage: rms_printSpecVar <path>", "printSpecVar", RealisticMechanicalSystems.ConsoleCommands)
