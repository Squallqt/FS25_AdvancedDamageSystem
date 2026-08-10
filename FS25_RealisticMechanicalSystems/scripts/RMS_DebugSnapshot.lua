RMS_DebugSnapshot = {}

RMS_DebugSnapshot.REQUEST_INTERVAL_MS = 500
RMS_DebugSnapshot.MAX_SNAPSHOT_AGE_MS = 1500
RMS_DebugSnapshot.ENTRY_TYPE_NUMBER = 0
RMS_DebugSnapshot.ENTRY_TYPE_BOOLEAN = 1
RMS_DebugSnapshot.ENTRY_TYPE_STRING = 2
RMS_DebugSnapshot.ENTRY_TYPE_TABLE = 3

RMS_DebugSnapshot.lastRequestedVehicle = nil
RMS_DebugSnapshot.lastRequestTime = -math.huge

local DEBUG_SECTIONS = {
    "service",
    "airIntake",
    "drivetrain",
    "engine",
    "transmission",
    "hydraulics",
    "cooling",
    "electrical",
    "chassis",
    "fuel",
    "battery",
    "radiator",
    "engineTemp",
    "transmissionTemp",
    "aiWorker"
}

local function copyPlainValue(value, visited)
    local valueType = type(value)
    if valueType == "number" or valueType == "boolean" or valueType == "string" then
        return value
    end
    if valueType ~= "table" then
        return nil
    end

    visited = visited or {}
    if visited[value] then
        return nil
    end
    visited[value] = true

    local result = {}
    for key, childValue in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local copiedValue = copyPlainValue(childValue, visited)
            if copiedValue ~= nil then
                result[key] = copiedValue
            end
        end
    end

    visited[value] = nil
    return result
end

local function copyDebugData(debugData)
    local result = {}

    for _, sectionName in ipairs(DEBUG_SECTIONS) do
        local section = copyPlainValue((debugData or {})[sectionName])
        if section ~= nil then
            result[sectionName] = section
        end
    end

    return result
end

local function copyFactorStats(factorStats)
    local result = {}

    for systemKey, stats in pairs(factorStats or {}) do
        if type(stats) == "table" then
            local copiedStats = {}
            for statKey, statValue in pairs(stats) do
                if type(statKey) == "string"
                        and string.sub(statKey, 1, 1) ~= "_"
                        and type(statValue) == "number"
                        and statValue == statValue
                        and statValue ~= math.huge
                        and statValue ~= -math.huge then
                    copiedStats[statKey] = statValue
                end
            end
            result[systemKey] = copiedStats
        end
    end

    return result
end

local function writeSnapshotValue(streamId, value)
    local valueType = type(value)

    if valueType == "table" then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_TABLE, 2)

        local keys = {}
        for key, _ in pairs(value) do
            if type(key) == "string" or type(key) == "number" then
                table.insert(keys, key)
            end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then
                return a < b
            end
            return tostring(a) < tostring(b)
        end)

        streamWriteUInt16(streamId, #keys)
        for _, key in ipairs(keys) do
            local isNumericKey = type(key) == "number"
            streamWriteBool(streamId, isNumericKey)
            if isNumericKey then
                streamWriteInt32(streamId, key)
            else
                streamWriteString(streamId, key)
            end
            writeSnapshotValue(streamId, value[key])
        end
    elseif valueType == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_NUMBER, 2)
        streamWriteFloat32(streamId, value)
    elseif valueType == "boolean" then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_BOOLEAN, 2)
        streamWriteBool(streamId, value)
    elseif valueType == "string" then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_STRING, 2)
        streamWriteString(streamId, value)
    else
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_TABLE, 2)
        streamWriteUInt16(streamId, 0)
    end
end

local function readSnapshotValue(streamId)
    local valueType = streamReadUIntN(streamId, 2)

    if valueType == RMS_DebugSnapshot.ENTRY_TYPE_NUMBER then
        return streamReadFloat32(streamId)
    elseif valueType == RMS_DebugSnapshot.ENTRY_TYPE_BOOLEAN then
        return streamReadBool(streamId)
    elseif valueType == RMS_DebugSnapshot.ENTRY_TYPE_STRING then
        return streamReadString(streamId)
    end

    local value = {}
    local keyCount = streamReadUInt16(streamId)
    for _ = 1, keyCount do
        local isNumericKey = streamReadBool(streamId)
        local key = isNumericKey and streamReadInt32(streamId) or streamReadString(streamId)
        value[key] = readSnapshotValue(streamId)
    end
    return value
end

function RMS_DebugSnapshot.build(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return nil
    end

    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    local preheatState = tonumber(spec.preheatState) or RMS_Preheat.STATE.IDLE
    local glowHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER or nil
    local glowHardStartStatus = glowHardStartEffect ~= nil
        and glowHardStartEffect.extraData ~= nil
        and glowHardStartEffect.extraData.status
        or "NONE"
    local glowHardStartBlocked = glowHardStartEffect ~= nil
        and glowHardStartEffect.extraData ~= nil
        and glowHardStartEffect.extraData.blockStart == true
        and spec.preheatWasRequired == true

    return {
        debugData = copyDebugData(spec.debugData),
        factorStats = copyFactorStats(spec.factorStats),
        state = {
            isUnderRoof = spec.isUnderRoof == true,
            avgDynamicMotorLoad = tonumber(spec.avgDynamicMotorLoad) or 0,
            avgSpeed = tonumber(spec.avgSpeed) or 0,
            avgAbsDiffAcc = tonumber(spec.avgAbsDiffAcc) or 0,
            avgTireGroundFrictionCoeff = tonumber(spec.avgTireGroundFrictionCoeff) or 0,
            activeDraftMaxForce = tonumber(spec.activeDraftMaxForce) or 0,
            activeDraftEffectiveForceCap = tonumber(spec.activeDraftEffectiveForceCap) or 0,
            chassisBrakePedal = spec.chassisBrakeState.pedal,
            acceleratorPedal = motor ~= nil and motor.lastAcceleratorPedal or 0,
            isCranking = spec.isCranking == true,
            batteryTempC = tonumber(spec.batteryTempC) or 0,
            preheatState = preheatState,
            preheatStateName = RMS_Preheat.getStateName(preheatState),
            preheatIsDiesel = RMS_Preheat.isDieselVehicle(vehicle),
            preheatEngineTemperatureC = RMS_Preheat.getEngineTemperatureC(vehicle),
            preheatLampTestActive = spec.preheatLampTestActive == true,
            preheatLampTestRemainingMs = tonumber(spec.preheatLampTestRemainingMs) or 0,
            preheatRemainingMs = tonumber(spec.preheatRemainingMs) or 0,
            preheatRequiredMs = tonumber(spec.preheatRequiredMs) or 0,
            preheatWasRequired = spec.preheatWasRequired == true,
            preheatAutomaticCrank = spec.preheatAutomaticCrank == true,
            preheatAutomaticCrankElapsedMs = tonumber(spec.preheatAutomaticCrankElapsedMs) or 0,
            preheatGlowPlugFailureSeverity = RMS_Preheat.getGlowPlugFailureSeverity(vehicle),
            preheatColdStartFaultSeverity = tonumber(spec.preheatColdStartFaultSeverity) or 0,
            preheatGlowHardStartStatus = tostring(glowHardStartStatus),
            preheatGlowHardStartBlocked = glowHardStartBlocked,
            pendingServicePrice = tonumber(spec.pendingServicePrice),
            pendingSelectedBreakdowns = copyPlainValue(spec.pendingSelectedBreakdowns or {}),
            pendingInspectionQueue = copyPlainValue(spec.pendingInspectionQueue or {}),
            pendingRepairQueue = copyPlainValue(spec.pendingRepairQueue or {}),
            pendingMaintenanceServiceStart = tonumber(spec.pendingMaintenanceServiceStart),
            pendingMaintenanceServiceTarget = tonumber(spec.pendingMaintenanceServiceTarget),
            pendingPreventiveSystemStressStart = copyPlainValue(spec.pendingPreventiveSystemStressStart or {}),
            pendingPreventiveSystemStressTarget = copyPlainValue(spec.pendingPreventiveSystemStressTarget or {}),
            pendingOverhaulSystemStart = copyPlainValue(spec.pendingOverhaulSystemStart or {}),
            pendingOverhaulSystemTarget = copyPlainValue(spec.pendingOverhaulSystemTarget or {}),
            pendingOverhaulSystemStressStart = copyPlainValue(spec.pendingOverhaulSystemStressStart or {}),
            pendingOverhaulSystemStressTarget = copyPlainValue(spec.pendingOverhaulSystemStressTarget or {}),
            pendingRepairSystemStressStart = copyPlainValue(spec.pendingRepairSystemStressStart or {}),
            pendingRepairSystemStressTarget = copyPlainValue(spec.pendingRepairSystemStressTarget or {}),
            aiWorkerApplyTimer = spec.aiWorkerPid.applyTimer,
            implements = copyPlainValue(spec.implements or {}),
            isImplementLowered = spec.isImplementLowered == true,
            isImplementOperating = spec.isImplementOperating == true,
            isImplementLifted = spec.isImplementLifted == true,
            operatingMass = tonumber(spec.operatingMass) or 0,
            liftedMass = tonumber(spec.liftedMass) or 0,
            hasConnectedPto = spec.hasConnectedPto == true,
            isPtoActive = spec.isPtoActive == true,
            isHarvesting = spec.isHarvesting == true
        }
    }
end

function RMS_DebugSnapshot.write(streamId, snapshot)
    writeSnapshotValue(streamId, snapshot or {})
end

function RMS_DebugSnapshot.read(streamId)
    return readSnapshotValue(streamId)
end

function RMS_DebugSnapshot.apply(vehicle, snapshot)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(snapshot) ~= "table" then
        return
    end

    spec.rmsDebugSnapshot = snapshot
    spec.rmsDebugSnapshotReceivedAt = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
end

function RMS_DebugSnapshot.get(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return nil
    end

    local receivedAt = tonumber(spec.rmsDebugSnapshotReceivedAt)
    local now = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
    if receivedAt == nil or now - receivedAt > RMS_DebugSnapshot.MAX_SNAPSHOT_AGE_MS then
        return nil
    end

    return spec.rmsDebugSnapshot
end

function RMS_DebugSnapshot.request(vehicle)
    if vehicle == nil or vehicle.isServer or g_client == nil or not RMS_Config.DEBUG then
        return
    end
    if g_currentMission == nil or not g_currentMission.isMasterUser then
        return
    end
    if RMS_DebugSnapshotRequestEvent == nil then
        return
    end

    local now = g_currentMission.time or g_time or 0
    if RMS_DebugSnapshot.lastRequestedVehicle ~= vehicle then
        RMS_DebugSnapshot.lastRequestedVehicle = vehicle
        RMS_DebugSnapshot.lastRequestTime = -math.huge
    end
    if now - RMS_DebugSnapshot.lastRequestTime < RMS_DebugSnapshot.REQUEST_INTERVAL_MS then
        return
    end

    RMS_DebugSnapshot.lastRequestTime = now
    RMS_DebugSnapshotRequestEvent.send(vehicle)
end
