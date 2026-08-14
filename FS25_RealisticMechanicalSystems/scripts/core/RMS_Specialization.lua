RealisticMechanicalSystems = {
    STATUS = {
        READY = 'rms_spec_state_ready',
        INSPECTION = 'rms_spec_state_inspection',
        MAINTENANCE = 'rms_spec_state_maintenance',
        REPAIR = 'rms_spec_state_repair',
        OVERHAUL = 'rms_spec_state_overhaul',
        BROKEN = 'rms_spec_state_broken'
    },

    STATES = {
        EXCELLENT = 'rms_spec_state_excellent',
        GOOD = 'rms_spec_state_good',
        NORMAL = 'rms_spec_state_normal',
        BAD = 'rms_spec_state_bad',
        TERRIBLE = 'rms_spec_state_terrible',
        UNKNOWN = 'rms_spec_state_unknown',
        OPTIMAL = "rms_spec_state_optimal",
        RECOMMENDED = "rms_spec_state_recommended",
        REQUIRED = "rms_spec_state_required",
        OVERDUE = "rms_spec_state_overdue",
        LEGENDARY = "rms_spec_state_legendary",
        PREMIUM = "rms_spec_state_premium",
        BUDGET = "rms_spec_state_budget",
        LOW = "rms_spec_state_low",
        AVERAGE = "rms_spec_state_average",
        HIGH = "rms_spec_state_high",
        WORKHORSE = "rms_spec_state_workhorse"
    },

    SYNC_GROUP = {
        STATE = 1,
        SERVICE_CONTEXT = 2,
        TELEMETRY = 4,
        THERMAL = 8,
        ELECTRICAL = 16,
        FIELDCARE = 32,
        WEAR = 64,
        BREAKDOWNS = 128,
        SERVICE_PROGRESS = 256,
        TUTORIAL_DATA = 512,
        DRIVETRAIN = 1024
    },

    SYSTEMS = {
        ENGINE = "rms_spec_system_engine",
        TRANSMISSION = "rms_spec_system_transmission",
        HYDRAULICS = "rms_spec_system_hydraulics",
        COOLING = "rms_spec_system_cooling",
        ELECTRICAL = "rms_spec_system_electrical",
        CHASSIS = "rms_spec_system_chassis",
        FUEL = "rms_spec_system_fuel",
        PTO = "rms_spec_system_pto"
    },

    BREAKDOWN_SOURCES = {
        RANDOM = 1,
        POOR_PARTS = 2,
        QUICK_FIX = 3
    },

    WORKSHOP = {
    DEALER  = "rms_spec_workshop_dealer",
    MOBILE  = "rms_spec_workshop_mobile",
    OWN     = "rms_spec_workshop_own",
    },

    PART_TYPES = {
    OEM         = "rms_spec_part_types_oem",
    USED        = "rms_spec_part_types_used",
    AFTERMARKET = "rms_spec_part_types_aftermarket",
    PREMIUM     = "rms_spec_part_types_premium",
    },

    INSPECTION_TYPES = {
    STANDARD = "rms_spec_inspection_standard",
    VISUAL   = "rms_spec_inspection_visual",
    COMPLETE = "rms_spec_inspection_complete",
    },

    MAINTENANCE_TYPES = {
    STANDARD = "rms_spec_maintenance_standard",
    MINIMAL  = "rms_spec_maintenance_minimal",
    EXTENDED = "rms_spec_maintenance_extended",
    PREVENTIVE = "rms_spec_maintenance_preventive",
    },

    REPAIR_TYPES = {
    LOW    = "rms_spec_repair_type_fix",
    MEDIUM = "rms_spec_repair_type_replacement",
    HIGH = "rms_spec_repair_type_advanced",
    },

    OVERHAUL_TYPES = {
    STANDARD = "rms_spec_overhaul_standard",
    PARTIAL  = "rms_spec_overhaul_partial",
    FULL     = "rms_spec_overhaul_full",
    },

    TRANSMISSION_TYPES = {
    MANUAL      = "manual",
    MANUAL_POWERSHIFT = "manual_powershift",
    AUTOMATIC   = "automatic",
    POWERSHIFT  = "powershift",
    VARIABLE    = "variable",
    CVT         = "variable",
    UNKNOWN     = "unknown",
    },
}

-- Display order of the vehicle systems.
RealisticMechanicalSystems.SYSTEMS_ORDER = {
    RealisticMechanicalSystems.SYSTEMS.ENGINE,
    RealisticMechanicalSystems.SYSTEMS.TRANSMISSION,
    RealisticMechanicalSystems.SYSTEMS.HYDRAULICS,
    RealisticMechanicalSystems.SYSTEMS.COOLING,
    RealisticMechanicalSystems.SYSTEMS.ELECTRICAL,
    RealisticMechanicalSystems.SYSTEMS.CHASSIS,
    RealisticMechanicalSystems.SYSTEMS.FUEL,
    RealisticMechanicalSystems.SYSTEMS.PTO
}

-- Display order of the part quality options.
RealisticMechanicalSystems.PART_TYPES_ORDER = {
    RealisticMechanicalSystems.PART_TYPES.OEM,
    RealisticMechanicalSystems.PART_TYPES.USED,
    RealisticMechanicalSystems.PART_TYPES.AFTERMARKET,
    RealisticMechanicalSystems.PART_TYPES.PREMIUM
}

RealisticMechanicalSystems.modDirectory = g_currentModDirectory

function RealisticMechanicalSystems.isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function RealisticMechanicalSystems.sanitizeNumber(value, fallback, minValue, maxValue)
    local sanitized = tonumber(value)
    local safeFallback = tonumber(fallback)

    if not RealisticMechanicalSystems.isFiniteNumber(safeFallback) then
        safeFallback = 0
    end

    if not RealisticMechanicalSystems.isFiniteNumber(sanitized) then
        sanitized = safeFallback
    end

    if minValue ~= nil then
        local minNumber = tonumber(minValue)
        if RealisticMechanicalSystems.isFiniteNumber(minNumber) and sanitized < minNumber then
            sanitized = minNumber
        end
    end

    if maxValue ~= nil then
        local maxNumber = tonumber(maxValue)
        if RealisticMechanicalSystems.isFiniteNumber(maxNumber) and sanitized > maxNumber then
            sanitized = maxNumber
        end
    end

    return sanitized
end

source(g_currentModDirectory .. "scripts/core/RMS_Thermal.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Electrical.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Preheat.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Exhaust.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Breakdowns.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Consumptables.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Drivetrain.lua")

RealisticMechanicalSystems.FACTOR_STATS_ALIASES = {
    expiredServiceFactor = "sf",
    -- engine
    motorLoadFactor = "mlf",
    airIntakeCloggingFactor = "aicf",
    coldMotorFactor = "cmf",
    hotMotorFactor = "hmf",
    -- transmission
    pullOverloadFactor = "pof",
    heavyTrailerFactor = "htf",
    luggingFactor = "lf",
    wheelSlipFactor = "wsf",
    drivetrainWindupFactor = "dwf",
    coldTransFactor = "ctf",
    hotTransFactor = "hotf",
    -- hydraulic
    heavyLiftFactor = "hlf",
    operatingFactor = "of",
    coldOilFactor = "cof",
    hotOilFactor = "hof",
    vibFactor = "vf",
    -- cooling
    highCoolingFactor = "hcf",
    overheatFactor = "ohf",
    coldShockFactor = "csf",

    -- electrical
    weatherExposureFactor = "wef",
    lightsFactor = "ltf",
    crankingStressFactor = "crf",

    -- chassis
    steerLoadFactor = "slf",
    brakeMassFactor = "bmf",

    --fuel
    lowFuelStarvationFactor = "lff",
    coldFuelFactor = "cff",
    idleDepositFactor = "idf",
    highPressureFactor = "hpf",
    lubricationFactor = "lubf",
    instantDamageFactor = "idfg",
    ptoLoadFactor = "plf",
    ptoEngagementFactor = "pef"
}

RealisticMechanicalSystems.FACTOR_STATS_KEYS = {}
for _, alias in pairs(RealisticMechanicalSystems.FACTOR_STATS_ALIASES) do
    RealisticMechanicalSystems.FACTOR_STATS_KEYS[alias] = true
end

-- ==========================================================
--                          HELPER FUNCTIONS
-- ==========================================================

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")

local function getVehicleOperatingHours(vehicle)
    if vehicle == nil then
        return 0
    end

    if vehicle.getOperatingTime ~= nil then
        local operatingTime = tonumber(vehicle:getOperatingTime())
        if operatingTime ~= nil then
            return operatingTime / (60 * 60 * 1000)
        end
    end

    if vehicle.getFormattedOperatingTime ~= nil then
        return tonumber(vehicle:getFormattedOperatingTime()) or 0
    end

    return 0
end
RealisticMechanicalSystems.getVehicleOperatingHours = getVehicleOperatingHours

local function ensureFactorStats(spec, vehicle)
    if spec == nil then
        return {}
    end

    if type(spec.factorStats) ~= "table" then
        spec.factorStats = {}
    end

    for systemKey, _ in pairs(spec.systems or {}) do
        if type(spec.factorStats[systemKey]) ~= "table" then
            spec.factorStats[systemKey] = {}
        end

        local stats = spec.factorStats[systemKey]
        stats.total = tonumber(stats.total) or 0
        stats.stress = tonumber(stats.stress) or 0
        stats._prevStress = tonumber(stats._prevStress) or 0
        stats._avgStress = tonumber(stats._avgStress) or 0
        stats.operatingHours = tonumber(stats.operatingHours)
        if stats.operatingHours == nil then
            stats.operatingHours = -1
        end
    end

    return spec.factorStats
end
RealisticMechanicalSystems.ensureFactorStats = ensureFactorStats

local function getTransmissionNameFromXML(vehicle)
    if vehicle == nil then
        return nil
    end

    local motorConfigIndex = 1
    if vehicle.configurations ~= nil and vehicle.configurations.motor ~= nil then
        motorConfigIndex = math.max(tonumber(vehicle.configurations.motor) or 1, 1)
    end

    if vehicle.xmlFile ~= nil and vehicle.xmlFile.getValue ~= nil then
        local key = string.format("vehicle.motorized.motorConfigurations.motorConfiguration(%d).transmission#name", motorConfigIndex - 1)
        local name = vehicle.xmlFile:getValue(key)
        if name ~= nil then
            return tostring(name)
        end
    end

    local storeItem = g_storeManager ~= nil and vehicle.configFileName ~= nil and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    if storeItem ~= nil and storeItem.specs ~= nil and type(storeItem.specs.transmission) == "table" then
        return storeItem.specs.transmission[motorConfigIndex] or storeItem.specs.transmission[1]
    end

    return nil
end

local function getTransmissionType(vehicle)
    local transmissionTypes = RealisticMechanicalSystems.TRANSMISSION_TYPES
    if vehicle == nil or vehicle.getMotor == nil then
        return transmissionTypes.UNKNOWN
    end

    local motor = vehicle:getMotor()
    if motor == nil then
        return transmissionTypes.UNKNOWN
    end

    local transmissionName = getTransmissionNameFromXML(vehicle)
    if transmissionName ~= nil then
        local normalizedName = string.lower(tostring(transmissionName))
        if string.find(normalizedName, "manual", 1, true) ~= nil
            and (string.find(normalizedName, "powershift", 1, true) ~= nil
            or string.find(normalizedName, "power shift", 1, true) ~= nil) then
            return transmissionTypes.MANUAL_POWERSHIFT
        elseif string.find(normalizedName, "powershift", 1, true) ~= nil
            or string.find(normalizedName, "power shift", 1, true) ~= nil then
            return transmissionTypes.POWERSHIFT
        elseif string.find(normalizedName, "variable", 1, true) ~= nil
            or string.find(normalizedName, "cvt", 1, true) ~= nil then
            return transmissionTypes.VARIABLE
        elseif string.find(normalizedName, "automatic", 1, true) ~= nil
            or string.find(normalizedName, "auto", 1, true) ~= nil then
            return transmissionTypes.AUTOMATIC
        elseif string.find(normalizedName, "manual", 1, true) ~= nil then
            return transmissionTypes.MANUAL
        end
    end

    if motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT then
        if motor.forwardGears ~= nil or motor.backwardGears ~= nil then
            return transmissionTypes.MANUAL_POWERSHIFT
        end

        return transmissionTypes.POWERSHIFT
    end

    if motor.minForwardGearRatio ~= nil then
        return transmissionTypes.VARIABLE
    end

    if motor.forwardGears ~= nil or motor.backwardGears ~= nil then
        return transmissionTypes.MANUAL
    end

    return transmissionTypes.UNKNOWN
end

RealisticMechanicalSystems.getTransmissionType = getTransmissionType
RealisticMechanicalSystems.getTransmissionNameFromXML = getTransmissionNameFromXML

local hasCVTAddon = RMS_Utils.hasCVTAddon
local hasCVTTransmission = RMS_Utils.hasCVTTransmission

local function refreshExclusionState(spec)
    if spec.isExcludedByUser ~= nil then
        spec.isExcludedVehicle = spec.isExcludedByDefault or spec.isExcludedByUser
    else
        spec.isExcludedVehicle = spec.isExcludedByDefault or spec.isExcludedByRule
    end
end
RealisticMechanicalSystems.refreshExclusionState = refreshExclusionState

RealisticMechanicalSystems.SYNC_GROUP_ALL = 2047

function RealisticMechanicalSystems.raiseRMSDirty(vehicle, groupBits)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or not vehicle.isServer or spec.rmsDirtyFlag == nil then
        return
    end

    for connection, mask in pairs(spec.rmsPendingByConnection) do
        spec.rmsPendingByConnection[connection] = bit32.bor(mask, groupBits)
    end

    vehicle:raiseDirtyFlags(spec.rmsDirtyFlag)
end

function RealisticMechanicalSystems.raiseRMSDirtyForConnection(vehicle, groupBits, connection)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local mask = spec.rmsPendingByConnection[connection]
    if mask == nil then
        return
    end

    spec.rmsPendingByConnection[connection] = bit32.bor(mask, groupBits)
    vehicle:raiseDirtyFlags(spec.rmsDirtyFlag)
end

function RealisticMechanicalSystems:setRMSUserExcluded(isExcluded, noEventSend)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return false, "unsupported"
    end

    if spec.isExcludedByDefault then
        return false, "default"
    end

    local requestedValue = isExcluded == true
    if spec.isExcludedByUser == requestedValue then
        return false, "unchanged"
    end

    spec.isExcludedByUser = requestedValue
    refreshExclusionState(spec)

    if spec.isExcludedVehicle then
        if self.isClient then
            RMS_Exhaust.reset(self)
        end
        spec.pendingSideNotifications = {}
    else
        spec.lubricationUsedThisPeriod = true
    end

    self:recalculateAndApplyEffects()
    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP_ALL)

    if self.isClient and RMS_Main ~= nil and RMS_Main.hud ~= nil
            and g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil
            and g_localPlayer:getCurrentVehicle() == self then
        RMS_Main.hud:setVehicle(self)
        RMS_Main.hud:setVisible(not spec.isExcludedVehicle, true)
    end

    if self.isServer and not noEventSend and RMS_VehicleExclusionEvent ~= nil then
        RMS_VehicleExclusionEvent.sendToClients(self, spec.isExcludedByUser)
    end

    return true
end

local function getSafeMissionTimeScale()
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local timeScale = (missionInfo and missionInfo.timeScale) or 1
    if timeScale <= 0 then
        timeScale = 1
    end
    return timeScale
end
RealisticMechanicalSystems.getSafeMissionTimeScale = getSafeMissionTimeScale

-- ==========================================================
--                         DIRTY FLAGS HELPERS
-- ==========================================================

local SYSTEM_SYNC_EPSILON = 0.001

local function canRaiseDirtyFlag(vehicle, spec)
    return vehicle ~= nil and vehicle.isServer and spec ~= nil and spec.rmsDirtyFlag ~= nil
end

local function getSyncOperatingTime(vehicle)
    if vehicle == nil then
        return 0
    end

    if vehicle.getOperatingTime ~= nil then
        return tonumber(vehicle:getOperatingTime()) or 0
    end

    return tonumber(vehicle.operatingTime) or 0
end
RealisticMechanicalSystems.getSyncOperatingTime = getSyncOperatingTime

local function serializeBreakdownsForDirtyCheck(breakdownsTable)
    local parts = {}

    for id, breakdown in pairs(breakdownsTable or {}) do
        local stage = math.max(math.floor(tonumber(breakdown.stage) or 1), 1)
        local visible = breakdown.isVisible and 1 or 0
        local selected = breakdown.isSelectedForRepair and 1 or 0
        local active = breakdown.isActive ~= false and 1 or 0
        local source = math.max(math.floor(tonumber(breakdown.source) or 0), 0)

        table.insert(parts, string.format("%s,%d,%d,%d,%d,%d", id, stage, visible, selected, active, source))
    end

    table.sort(parts)

    return table.concat(parts, ";")
end

local function syncFloatChanged(a, b, epsilon)
    local valueA = RealisticMechanicalSystems.sanitizeNumber(a, 0)
    local valueB = RealisticMechanicalSystems.sanitizeNumber(b, 0)
    return math.abs(valueA - valueB) > (epsilon or 0)
end

local function markStateDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if spec._lastSyncState_currentState ~= spec.currentState or
       spec._lastSyncState_plannedState ~= spec.plannedState or
       syncFloatChanged(spec._lastSyncState_maintenanceTimer, spec.maintenanceTimer, 1.0) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.STATE)
            spec._lastSyncState_currentState = spec.currentState
            spec._lastSyncState_plannedState = spec.plannedState
            spec._lastSyncState_maintenanceTimer = spec.maintenanceTimer
            return true
    end

    return false
end

local function markServiceContextDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if spec._lastSyncServiceContext_optionOne ~= spec.serviceOptionOne or
       spec._lastSyncServiceContext_optionTwo ~= spec.serviceOptionTwo or
       spec._lastSyncServiceContext_optionThree ~= spec.serviceOptionThree or
       spec._lastSyncServiceContext_workshopType ~= spec.workshopType then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)
            spec._lastSyncServiceContext_optionOne = spec.serviceOptionOne
            spec._lastSyncServiceContext_optionTwo = spec.serviceOptionTwo
            spec._lastSyncServiceContext_optionThree = spec.serviceOptionThree
            spec._lastSyncServiceContext_workshopType = spec.workshopType
            return true
    end

    return false
end

local function markTelemetryDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    local operatingTime = getSyncOperatingTime(vehicle)
    local realOperatingTime = spec.realOperatingTime or 0
    local dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or 0
    local wheelSlip = tonumber(spec.wheelSlipIntensity) or 0

    if syncFloatChanged(spec._lastSyncTelemetry_operatingTime, operatingTime, 60000.0) or
       syncFloatChanged(spec._lastSyncTelemetry_realOperatingTime, realOperatingTime, 60000.0) or
       syncFloatChanged(spec._lastSyncTelemetry_fuelUsageRaw, spec._fuelUsageRaw, 0.3) or
       syncFloatChanged(spec._lastSyncTelemetry_dynamicMotorLoad, dynamicMotorLoad, 0.01) or
       syncFloatChanged(spec._lastSyncTelemetry_wheelSlip, wheelSlip, 0.01) or
       syncFloatChanged(spec._lastSyncTelemetry_liftedMass, spec.liftedMass, 10.0) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.TELEMETRY)
            spec._lastSyncTelemetry_operatingTime = operatingTime
            spec._lastSyncTelemetry_realOperatingTime = realOperatingTime
            spec._lastSyncTelemetry_fuelUsageRaw = spec._fuelUsageRaw
            spec._lastSyncTelemetry_dynamicMotorLoad = dynamicMotorLoad
            spec._lastSyncTelemetry_wheelSlip = wheelSlip
            spec._lastSyncTelemetry_liftedMass = spec.liftedMass
            return true
    end

    return false
end

local function markThermalDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncThermal_rawEngineTemperature, spec.rawEngineTemperature, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_rawTransmissionTemperature, spec.rawTransmissionTemperature, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_thermostatState, spec.thermostatState, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_transmissionThermostatState, spec.transmissionThermostatState, 0.05) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.THERMAL)
            spec._lastSyncThermal_rawEngineTemperature = spec.rawEngineTemperature
            spec._lastSyncThermal_rawTransmissionTemperature = spec.rawTransmissionTemperature
            spec._lastSyncThermal_thermostatState = spec.thermostatState
            spec._lastSyncThermal_transmissionThermostatState = spec.transmissionThermostatState
            return true
    end

    return false
end

local function markElectricalDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncElectrical_batterySoc, spec.batterySoc, 0.01) or
       syncFloatChanged(spec._lastSyncElectrical_batteryChargeAh, spec.batteryChargeAh, 0.01) or
       syncFloatChanged(spec._lastSyncElectrical_batteryTerminalVoltage, spec.batteryTerminalVoltageV, 0.01) or
       syncFloatChanged(spec._lastSyncElectrical_systemVoltage, spec.systemVoltageV, 0.01) or
       spec._lastSyncElectrical_preheatState ~= spec.preheatState or
       spec._lastSyncElectrical_preheatLampTestActive ~= spec.preheatLampTestActive or
       spec._lastSyncElectrical_preheatWasRequired ~= spec.preheatWasRequired or
       spec._lastSyncElectrical_preheatColdStartFaultSeverity ~= spec.preheatColdStartFaultSeverity then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
            spec._lastSyncElectrical_batterySoc = spec.batterySoc
            spec._lastSyncElectrical_batteryChargeAh = spec.batteryChargeAh
            spec._lastSyncElectrical_batteryTerminalVoltage = spec.batteryTerminalVoltageV
            spec._lastSyncElectrical_systemVoltage = spec.systemVoltageV
            spec._lastSyncElectrical_preheatState = spec.preheatState
            spec._lastSyncElectrical_preheatLampTestActive = spec.preheatLampTestActive
            spec._lastSyncElectrical_preheatWasRequired = spec.preheatWasRequired
            spec._lastSyncElectrical_preheatColdStartFaultSeverity = spec.preheatColdStartFaultSeverity
            return true
    end

    return false
end

local function markFieldcareDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncFieldcare_radiatorClogging, spec.radiatorClogging, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_airIntakeClogging, spec.airIntakeClogging, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_lubricationLevel, spec.lubricationLevel, 0.005) or
       spec._lastSyncFieldcare_inspectionSoundActive ~= spec.fieldInspectionSoundActive then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
            spec._lastSyncFieldcare_radiatorClogging = spec.radiatorClogging
            spec._lastSyncFieldcare_airIntakeClogging = spec.airIntakeClogging
            spec._lastSyncFieldcare_lubricationLevel = spec.lubricationLevel
            spec._lastSyncFieldcare_inspectionSoundActive = spec.fieldInspectionSoundActive
            return true
    end

    return false
end

local function getSystemsSyncChanged(spec)
    local lastSystems = spec._lastSyncWear_systems
    if lastSystems == nil then
        return true
    end

    local count = 0
    for sysKey, sysData in pairs(spec.systems) do
        count = count + 1

        local last = lastSystems[sysKey]
        if last == nil then
            return true
        end

        if syncFloatChanged(last.condition, sysData.condition, SYSTEM_SYNC_EPSILON) or
           syncFloatChanged(last.stress, sysData.stress, SYSTEM_SYNC_EPSILON) or
           last.enabled ~= (sysData.enabled ~= false) then
            return true
        end
    end

    return count ~= spec._lastSyncWear_systemsCount
end

local function captureSystemsSync(spec)
    local snapshot = {}
    local count = 0

    for sysKey, sysData in pairs(spec.systems) do
        snapshot[sysKey] = {
            condition = sysData.condition,
            stress = sysData.stress,
            enabled = sysData.enabled ~= false
        }
        count = count + 1
    end

    spec._lastSyncWear_systems = snapshot
    spec._lastSyncWear_systemsCount = count
end
RealisticMechanicalSystems.captureSystemsSync = captureSystemsSync

local function markWearDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncWear_serviceLevel, spec.serviceLevel, 0.001) or
       syncFloatChanged(spec._lastSyncWear_conditionLevel, spec.conditionLevel, 0.001) or
       spec._lastSyncWear_ptoEngagementSequence ~= spec.ptoEngagementSequence or
       getSystemsSyncChanged(spec) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.WEAR)
            spec._lastSyncWear_serviceLevel = spec.serviceLevel
            spec._lastSyncWear_conditionLevel = spec.conditionLevel
            spec._lastSyncWear_ptoEngagementSequence = spec.ptoEngagementSequence
            captureSystemsSync(spec)
            return true
    end

    return false
end

local function markBreakdownsDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    local serializedBreakdowns = serializeBreakdownsForDirtyCheck(spec.activeBreakdowns)
    if spec._lastSyncBreakdowns_serialized ~= serializedBreakdowns then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
            spec._lastSyncBreakdowns_serialized = serializedBreakdowns
            return true
    end

    return false
end

local function markServiceProgressDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncServiceProgress_elapsed, spec.pendingProgressElapsedTime,500.0) or
       spec._lastSyncServiceProgress_step ~= spec.pendingProgressStepIndex or
       syncFloatChanged(spec._lastSyncServiceProgress_total, spec.pendingProgressTotalTime, 500.0) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS)
            spec._lastSyncServiceProgress_elapsed = spec.pendingProgressElapsedTime
            spec._lastSyncServiceProgress_step = spec.pendingProgressStepIndex
            spec._lastSyncServiceProgress_total = spec.pendingProgressTotalTime
            return true
    end

    return false
end

local function getTutorialSyncConnection(vehicle)
    local connection = vehicle:getOwnerConnection()
    if connection == nil then
        return nil
    end

    local uniqueUserId = RMS_Utils.getUniqueUserIdByConnection(connection)
    if uniqueUserId == nil then
        return nil
    end

    local state = RMS_Config.TUTORIAL_PLAYER_STATES[tostring(uniqueUserId)]
    if state ~= nil and not state.tutorialMode then
        return nil
    end

    return connection
end

local function markTutorialDataDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    local tutorialConnection = getTutorialSyncConnection(vehicle)
    if tutorialConnection == nil then
        spec._lastSyncTutorial_connection = nil
        return false
    end

    local fuelState = spec.fuelState
    local idleTimer  = tonumber(fuelState.idleTimer)  or 0
    local fuelLevel  = tonumber(fuelState.level)      or 0
    local luggingTimer    = tonumber(spec.luggingTutorialTimer)    or 0
    local wheelSlipTimer  = tonumber(spec.wheelSlipTutorialTimer)  or 0
    local brakeState  = spec.chassisBrakeState
    local hpTrailerMassRatio = tonumber(brakeState.hpTrailerMassRatio) or 1000
    local trailerMass = tonumber(brakeState.trailerMass) or 0
    local hpGrossMassRatio = tonumber(brakeState.hpGrossMassRatio) or 1000
    local isCranking  = spec.isCranking == true
    local steerState    = spec.chassisSteerState
    local groundContact = steerState.groundContact > 0
    local isMoving      = steerState.isMoving == true
    local elecSys      = spec.systems ~= nil and spec.systems.electrical or nil
    local crankingTimer = elecSys ~= nil and (tonumber(elecSys.crankingTimer) or 0) or 0

    if spec._lastSyncTutorial_connection ~= tutorialConnection                          or
       syncFloatChanged(spec._lastSyncTutorial_idleTimer,       idleTimer,       1.0)   or
       syncFloatChanged(spec._lastSyncTutorial_fuelLevel,       fuelLevel,       0.01)  or
       syncFloatChanged(spec._lastSyncTutorial_luggingTimer,    luggingTimer,    100.0) or
       syncFloatChanged(spec._lastSyncTutorial_wheelSlipTimer,  wheelSlipTimer,  100.0) or
       syncFloatChanged(spec._lastSyncTutorial_hpTrailerMassRatio, hpTrailerMassRatio, 0.1) or
       syncFloatChanged(spec._lastSyncTutorial_trailerMass,     trailerMass,     0.01)  or
       syncFloatChanged(spec._lastSyncTutorial_hpGrossMassRatio, hpGrossMassRatio, 0.1) or
       spec._lastSyncTutorial_isCranking    ~= isCranking                              or
       spec._lastSyncTutorial_groundContact ~= groundContact                           or
       spec._lastSyncTutorial_isMoving      ~= isMoving                                or
       syncFloatChanged(spec._lastSyncTutorial_crankingTimer,   crankingTimer,   100.0) then
            RealisticMechanicalSystems.raiseRMSDirtyForConnection(vehicle, RealisticMechanicalSystems.SYNC_GROUP.TUTORIAL_DATA, tutorialConnection)
            spec._lastSyncTutorial_connection      = tutorialConnection
            spec._lastSyncTutorial_idleTimer       = idleTimer
            spec._lastSyncTutorial_fuelLevel       = fuelLevel
            spec._lastSyncTutorial_luggingTimer    = luggingTimer
            spec._lastSyncTutorial_wheelSlipTimer  = wheelSlipTimer
            spec._lastSyncTutorial_hpTrailerMassRatio = hpTrailerMassRatio
            spec._lastSyncTutorial_trailerMass     = trailerMass
            spec._lastSyncTutorial_hpGrossMassRatio = hpGrossMassRatio
            spec._lastSyncTutorial_isCranking      = isCranking
            spec._lastSyncTutorial_groundContact   = groundContact
            spec._lastSyncTutorial_isMoving        = isMoving
            spec._lastSyncTutorial_crankingTimer   = crankingTimer
            return true
    end

    return false
end

function RealisticMechanicalSystems.raiseServiceLifecycleDirtyFlags(vehicle)
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local raised = false

    if markStateDirty(vehicle, spec) then
        raised = true
    end
    if markServiceContextDirty(vehicle, spec) then
        raised = true
    end
    if markWearDirty(vehicle, spec) then
        raised = true
    end
    if markBreakdownsDirty(vehicle, spec) then
        raised = true
    end
    if markServiceProgressDirty(vehicle, spec) then
        raised = true
    end

    return raised
end

function RealisticMechanicalSystems.forceFinishService(vehicle)
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or not vehicle.isServer then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.currentState == RealisticMechanicalSystems.STATUS.READY then
        return false
    end

    local remainingMs = math.max(spec.maintenanceTimer or 0, 0)
    local missionInfo = g_currentMission and g_currentMission.missionInfo or nil
    local timeScale = (missionInfo and missionInfo.timeScale) or 1
    if timeScale <= 0 then
        timeScale = 1
    end

    local forceDt = math.max(math.ceil(remainingMs / timeScale) + 1, 1)

    local previousWorkshopOpen = nil
    if RMS_Main ~= nil then
        previousWorkshopOpen = RMS_Main.isWorkshopOpen
        RMS_Main.isWorkshopOpen = true
    end

    local ok, err = pcall(function()
        vehicle:processService(forceDt)
    end)

    if RMS_Main ~= nil and previousWorkshopOpen ~= nil then
        RMS_Main.isWorkshopOpen = previousWorkshopOpen
    end

    if not ok then
        log_dbg(string.format("Failed to force-finish service for '%s': %s", vehicle:getFullName(), tostring(err)))
        return false, err
    end

    if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY then
        spec.pendingProgressElapsedTime = spec.pendingProgressTotalTime or 0
        spec.maintenanceTimer = 0
        vehicle:completeService()
    end

    return true
end

-- ==========================================================
--                          REGISTRATION
-- ==========================================================

function RealisticMechanicalSystems.initSpecialization()
    local schema = Vehicle.xmlSchema
    local schemaSavegame = Vehicle.xmlSchemaSavegame

    schema:setXMLSpecializationType("RealisticMechanicalSystems")

    local baseKey = "vehicles.vehicle(?).RealisticMechanicalSystems"
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#userExclusion", "User decision overriding the automatic exclusion, absent when the user has no opinion")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#service", "Service Level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#condition", "Condition Level")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#breakdowns", "Active Breakdowns")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#state", "Current State")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#plannedState", "Planned State")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#maintenanceTimer", "Maintenance Timer")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#realOperatingTime", "Real Operating Time")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#engineTemperature", "Engine Temperature")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionTemperature", "Transmission Temperature")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#batterySoc", "Battery State Of Charge")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#batteryChargeAh", "Battery Absolute Charge")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#batteryTempC", "Battery Temperature")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#radiatorClogging", "Radiator clogging level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#airIntakeClogging", "Air intake clogging level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#wetStackingLevel", "Wet stacking deposit level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#lubricationLevel", "Lubrication level")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#lubricationUsedThisPeriod", "Whether the vehicle was used during the current period")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#thermostatState", "Engine Thermostat Position")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionThermostatState", "Transmission Thermostat Position")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#serviceOptionOne", "Current Service Option One")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#serviceOptionTwo", "Current Service Option Two")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#serviceOptionThree", "Current Service Option Three")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#workshopType", "Workshop Type")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingSelectedBreakdowns", "Pending Selected Breakdowns")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingServicePrice", "Pending Service Price")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingInspectionQueue", "Pending Inspection Queue")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingRepairQueue", "Pending Repair Queue")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#pendingProgressStepIndex", "Pending Progress Step Index")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingProgressTotalTime", "Pending Progress Total Time")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingProgressElapsedTime", "Pending Progress Elapsed Time")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingMaintenanceServiceStart", "Pending Maintenance Service Start")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingMaintenanceServiceTarget", "Pending Maintenance Service Target")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingPreventiveSystemStressStart", "Pending preventive per-system stress start values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingPreventiveSystemStressTarget", "Pending preventive per-system stress target values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#systemsState", "Systems state snapshot")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#factorStats", "Per-system accumulated factor stats")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingOverhaulSystemStart", "Pending overhaul per-system start values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingOverhaulSystemTarget", "Pending overhaul per-system target values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingOverhaulSystemStressStart", "Pending overhaul per-system stress start values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingOverhaulSystemStressTarget", "Pending overhaul per-system stress target values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingRepairSystemStressStart", "Pending repair per-system stress start values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingRepairSystemStressTarget", "Pending repair per-system stress target values")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingRepairSystemStressStartRatio", "Pending repair per-system stress start ratios")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#driveMode", "Drivetrain mode (0=4x2, 1=4WD, 2=AUTO)")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#diffLockRequested", "Differential lock requested")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#parkBrake", "Parking brake engaged")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#ptoEngagementCount", "PTO engagement count")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#ptoEngagementCounter", "Weighted PTO engagement counter")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#ptoLastEngagementRatio", "Last measured PTO engagement power ratio")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#ptoEngagementSequence", "Severe PTO engagement sequence")

    local logKey = baseKey .. ".maintenanceLog.entry(?)"
    schemaSavegame:register(XMLValueType.INT,    logKey .. "#id", "Entry ID")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#type", "Maintenance Type")
    schemaSavegame:register(XMLValueType.FLOAT,  logKey .. "#price", "Price")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#date", "Date")
    
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#location", "Workshop Location")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#optionOne", "Option One")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#optionTwo", "Option Two")
    schemaSavegame:register(XMLValueType.BOOL,   logKey .. "#optionThree", "Option Three")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#isVisible", "is Visible in Log")
    schemaSavegame:register(XMLValueType.BOOL,   logKey .. "#isCompleted", "Is Completed")
    local condKey = logKey .. ".conditionData"
    schemaSavegame:register(XMLValueType.INT,    condKey .. "#year", "Vehicle Year")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#operatingHours", "Operating Hours")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#age", "Vehicle Age")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#condition", "Condition Level")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#service", "Service Level")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#activeBreakdowns", "Active Breakdowns")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#selectedBreakdowns", "Selected Breakdowns")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#activeEffects", "Active Effects")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#activeIndicators", "Active Indicators")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#reliability", "Reliability")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#maintainability", "Maintainability")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#systems", "Per-system snapshot")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#batterySoc", "Battery State Of Charge")
    
    schema:setXMLSpecializationType()
end

function RealisticMechanicalSystems.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onPostUpdateTick", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", RealisticMechanicalSystems)
end

function RealisticMechanicalSystems.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanMotorRun", RMS_Breakdowns.getCanMotorRun)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanStartAIVehicle", RMS_Breakdowns.getCanStartAIVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "startMotor", RMS_Breakdowns.startMotor)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateDamageAmount", RealisticMechanicalSystems.updateDamageAmount)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setLightsTypesMask", RMS_Breakdowns.setLightsTypesMask)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", RMS_Breakdowns.getSpeedLimitOverwrite)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", RMS_Breakdowns.updateVehiclePhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateConsumers", RMS_Breakdowns.updateConsumersOverwrite)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSellPrice", RealisticMechanicalSystems.getSellPrice)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateMotorTemperature", RealisticMechanicalSystems.updateMotorTemperature)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setOperatingTime", RealisticMechanicalSystems.setOperatingTime)

    
end

function RealisticMechanicalSystems.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "rmsUpdate", RealisticMechanicalSystems.rmsUpdate)
    SpecializationUtil.registerFunction(vehicleType, "updateVehicleStateSnapshot", RealisticMechanicalSystems.updateVehicleStateSnapshot)
    SpecializationUtil.registerFunction(vehicleType, "setRMSUserExcluded", RealisticMechanicalSystems.setRMSUserExcluded)
    
    SpecializationUtil.registerFunction(vehicleType, "recalculateAndApplyEffects", RealisticMechanicalSystems.recalculateAndApplyEffects)
    SpecializationUtil.registerFunction(vehicleType, "recalculateAndApplyIndicators", RealisticMechanicalSystems.recalculateAndApplyIndicators)
    
    SpecializationUtil.registerFunction(vehicleType, "tryTriggerBreakdown", RealisticMechanicalSystems.tryTriggerBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "getRandomBreakdownBySystem", RealisticMechanicalSystems.getRandomBreakdownBySystem)
    SpecializationUtil.registerFunction(vehicleType, "getRandomBreakdown", RealisticMechanicalSystems.getRandomBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "addBreakdown", RealisticMechanicalSystems.addBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "suspendBreakdown", RealisticMechanicalSystems.suspendBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "removeBreakdown", RealisticMechanicalSystems.removeBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "hasBreakdown", RealisticMechanicalSystems.hasBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "hasSystemBreakdowns", RealisticMechanicalSystems.hasSystemBreakdowns)
    SpecializationUtil.registerFunction(vehicleType, "processBreakdowns", RealisticMechanicalSystems.processBreakdowns)
    SpecializationUtil.registerFunction(vehicleType, "changeBreakdownStage", RealisticMechanicalSystems.changeBreakdownStage)
    SpecializationUtil.registerFunction(vehicleType, "getActiveBreakdowns", RealisticMechanicalSystems.getActiveBreakdowns)
    SpecializationUtil.registerFunction(vehicleType, "hasEffect", RealisticMechanicalSystems.hasEffect)
    SpecializationUtil.registerFunction(vehicleType, "processGeneralWearBreakdown", RealisticMechanicalSystems.processGeneralWearBreakdown)
    
    SpecializationUtil.registerFunction(vehicleType, "initService", RealisticMechanicalSystems.initService)
    SpecializationUtil.registerFunction(vehicleType, "processService", RealisticMechanicalSystems.processService)
    SpecializationUtil.registerFunction(vehicleType, "completeService", RealisticMechanicalSystems.completeService)
    SpecializationUtil.registerFunction(vehicleType, "cancelService", RealisticMechanicalSystems.cancelService)

    SpecializationUtil.registerFunction(vehicleType, "getServiceLevel", RealisticMechanicalSystems.getServiceLevel)
    SpecializationUtil.registerFunction(vehicleType, "getConditionLevel", RealisticMechanicalSystems.getConditionLevel)
    SpecializationUtil.registerFunction(vehicleType, "getSystemConditionLevel", RealisticMechanicalSystems.getSystemConditionLevel)
    SpecializationUtil.registerFunction(vehicleType, "getSystemStressLevel", RealisticMechanicalSystems.getSystemStressLevel)
    SpecializationUtil.registerFunction(vehicleType, "updateServiceLevel", RealisticMechanicalSystems.updateServiceLevel)
    SpecializationUtil.registerFunction(vehicleType, "updateConditionLevel", RealisticMechanicalSystems.updateConditionLevel)

    SpecializationUtil.registerFunction(vehicleType, "updateSystemConditionAndStress", RealisticMechanicalSystems.updateSystemConditionAndStress)
    SpecializationUtil.registerFunction(vehicleType, "updateEngineSystem", RealisticMechanicalSystems.updateEngineSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateTransmissionSystem", RealisticMechanicalSystems.updateTransmissionSystem)
    SpecializationUtil.registerFunction(vehicleType, "getTransmissionType", RealisticMechanicalSystems.getTransmissionType)
    SpecializationUtil.registerFunction(vehicleType, "updateHydraulicsSystem", RealisticMechanicalSystems.updateHydraulicsSystem)
    SpecializationUtil.registerFunction(vehicleType, "updatePtoSystem", RealisticMechanicalSystems.updatePtoSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateCoolingSystem", RealisticMechanicalSystems.updateCoolingSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateElectricalSystem", RealisticMechanicalSystems.updateElectricalSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateChassisSystem", RealisticMechanicalSystems.updateChassisSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateFuelSystem", RealisticMechanicalSystems.updateFuelSystem)
    SpecializationUtil.registerFunction(vehicleType, "applyInstantDamageToSystem", RealisticMechanicalSystems.applyInstantDamageToSystem)
    
    SpecializationUtil.registerFunction(vehicleType, "isUnderService", RealisticMechanicalSystems.isUnderService)
    SpecializationUtil.registerFunction(vehicleType, "isUnderRoof", RealisticMechanicalSystems.isUnderRoof)
    SpecializationUtil.registerFunction(vehicleType, "isUnderRoofRaycastCallback", RealisticMechanicalSystems.isUnderRoofRaycastCallback)
    SpecializationUtil.registerFunction(vehicleType, "getCurrentStatus", RealisticMechanicalSystems.getCurrentStatus)
    
    SpecializationUtil.registerFunction(vehicleType, "updateThermalSystems", RMS_Thermal.updateThermalSystems)
    SpecializationUtil.registerFunction(vehicleType, "updateEngineThermalModel", RMS_Thermal.updateEngineThermalModel)
    SpecializationUtil.registerFunction(vehicleType, "updateTransmissionThermalModel", RMS_Thermal.updateTransmissionThermalModel)
    SpecializationUtil.registerFunction(vehicleType, "getSmoothedTemperature", RMS_Thermal.getSmoothedTemperature)
     
    SpecializationUtil.registerFunction(vehicleType, "updateBatteryChargingModel", RMS_Electrical.updateBatteryChargingModel)
    SpecializationUtil.registerFunction(vehicleType, "syncDeadBatteryEffect", RMS_Electrical.syncDeadBatteryEffect)
    SpecializationUtil.registerFunction(vehicleType, "syncVoltageSagEffect", RMS_Electrical.syncVoltageSagEffect)
    SpecializationUtil.registerFunction(vehicleType, "establishExternalPowerConnection", RMS_Electrical.establishExternalPowerConnection)
    SpecializationUtil.registerFunction(vehicleType, "clearExternalPowerConnection", RMS_Electrical.clearExternalPowerConnection)
    
    SpecializationUtil.registerFunction(vehicleType, "updateDrivetrain", RMS_Drivetrain.updateDrivetrain)

    SpecializationUtil.registerFunction(vehicleType, "updateRadiatorClogging", RMS_Consumptables.updateRadiatorClogging)
    SpecializationUtil.registerFunction(vehicleType, "updateAirIntakeClogging", RMS_Consumptables.updateAirIntakeClogging)
    SpecializationUtil.registerFunction(vehicleType, "cleanRadiatorAndAirIntake", RMS_Consumptables.cleanRadiatorAndAirIntake)
    SpecializationUtil.registerFunction(vehicleType, "updateLubricationLevel", RMS_Consumptables.updateLubricationLevel)
    SpecializationUtil.registerFunction(vehicleType, "lubricateVehicle", RMS_Consumptables.lubricateVehicle)
    SpecializationUtil.registerFunction(vehicleType, "startFieldVisualInspectionProcess", RMS_Consumptables.startFieldVisualInspectionProcess)
    SpecializationUtil.registerFunction(vehicleType, "setFieldInspectionPlayerActive", RMS_Consumptables.setFieldInspectionPlayerActive)
    SpecializationUtil.registerFunction(vehicleType, "updateFieldInspectionSound", RMS_Consumptables.updateFieldInspectionSound)

    SpecializationUtil.registerFunction(vehicleType, "resetAiWorkerCruiseControlState", RealisticMechanicalSystems.resetAiWorkerCruiseControlState)
    SpecializationUtil.registerFunction(vehicleType, "getAiWorkerImplementSpeedLimit", RealisticMechanicalSystems.getAiWorkerImplementSpeedLimit)
    SpecializationUtil.registerFunction(vehicleType, "updateAiWorkerCruiseControl", RealisticMechanicalSystems.updateAiWorkerCruiseControl)
    SpecializationUtil.registerFunction(vehicleType, "isWarrantyRepairCovered", RealisticMechanicalSystems.isWarrantyRepairCovered)

    SpecializationUtil.registerFunction(vehicleType, "getServicePrice", RealisticMechanicalSystems.getServicePrice)
    SpecializationUtil.registerFunction(vehicleType, "getServiceDuration", RealisticMechanicalSystems.getServiceDuration)
    SpecializationUtil.registerFunction(vehicleType, "getServiceFinishTime", RealisticMechanicalSystems.getServiceFinishTime)
    SpecializationUtil.registerFunction(vehicleType, "getBreakdownRepairPrice", RealisticMechanicalSystems.getBreakdownRepairPrice)
    
    SpecializationUtil.registerFunction(vehicleType, "addEntryToMaintenanceLog", RealisticMechanicalSystems.addEntryToMaintenanceLog)
    SpecializationUtil.registerFunction(vehicleType, "getLastInspectedCondition", RealisticMechanicalSystems.getLastInspectedCondition)
    SpecializationUtil.registerFunction(vehicleType, "getLastInspectedService", RealisticMechanicalSystems.getLastInspectedService)
    SpecializationUtil.registerFunction(vehicleType, "getLastInspectionDate", RealisticMechanicalSystems.getLastInspectionDate)
    SpecializationUtil.registerFunction(vehicleType, "getLastMaintenanceDate", RealisticMechanicalSystems.getLastMaintenanceDate)
    SpecializationUtil.registerFunction(vehicleType, "getMaintenanceInterval", RealisticMechanicalSystems.getMaintenanceInterval)
    SpecializationUtil.registerFunction(vehicleType, "getHoursSinceLastMaintenance", RealisticMechanicalSystems.getHoursSinceLastMaintenance)
    SpecializationUtil.registerFunction(vehicleType, "getLastServiceOptions", RealisticMechanicalSystems.getLastServiceOptions)
    SpecializationUtil.registerFunction(vehicleType, "getOverhaulPerformedCount", RealisticMechanicalSystems.getOverhaulPerformedCount)
    
end

-- ==========================================================
--                        EVENTS
-- ==========================================================

function RealisticMechanicalSystems:onLeaveVehicle(wasEntered)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    spec.lastBlinkingWarningMessage = ""
    spec.blinkingWarningTimer = 0

    local hadStartInput = spec.startButtonDown or spec.startButtonHeld or spec.startButtonUp
    spec.startButtonDown = false
    spec.startButtonHeld = false
    spec.startButtonUp = false

    if hadStartInput then
        RMS_StartButtonEvent.send(self, false, false, false)
    end

    if self.isServer
        and not self:getIsMotorStarted()
        and spec.preheatState ~= RMS_Preheat.STATE.IDLE then
        RMS_Breakdowns.cancelStarterCranking(self)
        RMS_Preheat.reset(self, false)
        if self:getMotorState() ~= MotorState.OFF then
            self:setMotorState(MotorState.OFF)
        end
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
    end
end

function RealisticMechanicalSystems.updateStartButtonActionEvents(self)
    if not self.isClient or not self:getIsActiveForInput(true) then
        return
    end

    local spec = self.spec_RealisticMechanicalSystems
    local motorizedSpec = self.spec_motorized
    if spec == nil or motorizedSpec == nil or spec.startButtonActionEvents == nil then
        return
    end

    local automaticMotorStartEnabled = g_currentMission ~= nil
        and g_currentMission.missionInfo ~= nil
        and g_currentMission.missionInfo.automaticMotorStartEnabled == true

    for inputAction, actionEvent in pairs(spec.startButtonActionEvents) do
        local actionEventId = actionEvent.actionEventId
        local registeredEvent = actionEventId ~= nil
            and g_inputBinding.events ~= nil
            and g_inputBinding.events[actionEventId]
            or nil

        if registeredEvent ~= nil then
            g_inputBinding:setActionEventActive(actionEventId, true)

            if inputAction == InputAction.TOGGLE_MOTOR_STATE then
                g_inputBinding:setActionEventTextVisibility(actionEventId, not automaticMotorStartEnabled)

                local motorState = self:getMotorState()
                if motorState == MotorState.STARTING or motorState == MotorState.ON or RMS_Preheat.isFailed(self) then
                    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
                    g_inputBinding:setActionEventText(actionEventId, motorizedSpec.turnOffText)
                else
                    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
                    g_inputBinding:setActionEventText(actionEventId, motorizedSpec.turnOnText)
                end
            else
                g_inputBinding:setActionEventTextVisibility(actionEventId, false)
            end
        end
    end
end

function RealisticMechanicalSystems:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end

    local spec = self.spec_RealisticMechanicalSystems
    local motorizedSpec = self.spec_motorized
    if spec == nil or motorizedSpec == nil then
        return
    end

    self:clearActionEventsTable(spec.startButtonActionEvents)

    RMS_Drivetrain.registerActionEvents(self, isActiveForInputIgnoreSelection)

    if not isActiveForInputIgnoreSelection then
        return
    end

    local startInputActions = {
        InputAction.TOGGLE_MOTOR_STATE,
        InputAction.MOTOR_STATE_ON or "MOTOR_STATE_ON"
    }

    for _, inputAction in ipairs(startInputActions) do
        local motorizedActionEvent = motorizedSpec.actionEvents[inputAction]
        if motorizedActionEvent ~= nil and motorizedActionEvent.actionEventId ~= nil then
            g_inputBinding:removeActionEvent(motorizedActionEvent.actionEventId)
        end
        motorizedSpec.actionEvents[inputAction] = nil

        -- One composite event owns both the vanilla action and the RMS held-state tracking.
        local _, actionEventId = self:addActionEvent(
            spec.startButtonActionEvents,
            inputAction,
            self,
            RMS_Breakdowns.onStartButtonAction,
            true,
            true,
            false,
            true,
            nil,
            nil,
            true
        )

        if actionEventId ~= nil then
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
        end
    end

    RealisticMechanicalSystems.updateStartButtonActionEvents(self)
end

-- ==========================================================
--                        UPDATE
-- ==========================================================

local function getConditionLevelFromSellPrice(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return 1.0
    end

    local price = StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations)
    if price == nil or price <= 0 then
        price = storeItem.price or vehicle:getPrice() or 0
    end

    local repaintPrice = Wearable.calculateRepaintPrice(price, vehicle:getWearTotalAmount())
    local repairPrice = vehicle:getRepairPrice()
    local vanillaSellPrice = Vehicle.calculateSellPrice(storeItem, vehicle.age, vehicle.operatingTime, price, repairPrice, repaintPrice)
    local rmsSellPriceForCondition = vanillaSellPrice + repairPrice + (repaintPrice * 0.75)
    local targetCondition = math.clamp(rmsSellPriceForCondition / price, 0.01, 1.0)
    return targetCondition
end

local function initializeVehicleConditionFromVanillaPrice(vehicle, resetBreakdowns)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if vehicle == nil or spec == nil or spec.isExcludedVehicle then
        return false
    end

    spec.serviceLevel = 1 - vehicle:getDamageAmount()

    local targetCondition = getConditionLevelFromSellPrice(vehicle)
    for _, systemData in pairs(spec.systems or {}) do
        if type(systemData) == "table" then
            local random = math.random() * 0.2 + 0.9
            systemData.condition = math.clamp(targetCondition * random, 0.2, 1.0)
            systemData.stress = 0
        end
    end

    vehicle:updateConditionLevel()
    vehicle:setDamageAmount(0.0, true)

    if resetBreakdowns then
        vehicle:removeBreakdown()

        if vehicle:getOperatingTime() > 0 then
            local operatingHours = tonumber(vehicle:getFormattedOperatingTime()) or 0
            local lifespanRatio = RMS_Config.CORE.REFERENCE_SYSTEMS_WEAR / RMS_Config.CORE.BASE_SYSTEMS_WEAR
            local chance = operatingHours / (100 * lifespanRatio)
            chance = math.clamp(chance * RMS_Config.CORE.USED_VEHICLE_BREAKDOWN_PRESENCE_CHANGE_MUL, 0, RMS_Config.CORE.USED_VEHICLE_BREAKDOWN_PRESENCE_CHANGE_MAX)
            if math.random() < chance then
                vehicle:addBreakdown(vehicle:getRandomBreakdown())
            end
        end
    end

    return true, targetCondition
end
RealisticMechanicalSystems.initializeVehicleConditionFromVanillaPrice = initializeVehicleConditionFromVanillaPrice

local function registerVehicle(vehicle)
    if RMS_Main and RMS_Main.vehicles and RMS_Main.vehicles[vehicle.uniqueId] == nil then
        local ownerFarmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or vehicle.ownerFarmId
        local hasSupportedPropertyState = vehicle.propertyState == VehiclePropertyState.OWNED
            or vehicle.propertyState == VehiclePropertyState.LEASED
            or vehicle.propertyState == VehiclePropertyState.MISSION
        local hasValidOwnerFarm = ownerFarmId ~= nil
            and ownerFarmId ~= FarmManager.SPECTATOR_FARM_ID
            and g_farmManager:getFarmById(ownerFarmId) ~= nil

        if hasSupportedPropertyState and hasValidOwnerFarm then

            local spec = vehicle.spec_RealisticMechanicalSystems
            if spec == nil then return end

            --- Registration in RMS_Main.vehicles
            RMS_Main.vehicles[vehicle.uniqueId] = vehicle
            RMS_Main.numVehicles = RMS_Main.numVehicles + 1
    
            --- if first mod load or used vehicle
            if vehicle.isServer then
                    local isUsedVehicle = vehicle:getFormattedOperatingTime() > 0.01 and spec.conditionLevel == spec.baseConditionLevel
                    if isUsedVehicle then
                        -- Used vehicle logic
                        initializeVehicleConditionFromVanillaPrice(vehicle, true)
                    end

                    --- Initial report for a new vehicle only, a used one stays uninspected.
                    if not isUsedVehicle and (spec.maintenanceLog == nil or #spec.maintenanceLog == 0) then
                        vehicle:addEntryToMaintenanceLog(RealisticMechanicalSystems.STATUS.INSPECTION, RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD, "NONE", false, 0)
                    end
            end

            --- Updating vehicle's production year
            local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
            if storeItem ~= nil then
                spec.year = RMS_VehicleYears.getYear(storeItem)
            end

            --- Updating vehicle's reliability and maintainability
            spec.reliability, spec.maintainability = RealisticMechanicalSystems.getBrandReliability(vehicle)

            local factorStats = ensureFactorStats(spec, vehicle)
            local currentOperatingHours = getVehicleOperatingHours(vehicle)
            for _, systemStats in pairs(factorStats) do
                if type(systemStats) == "table" then
                    local operatingHours = tonumber(systemStats.operatingHours)
                    if operatingHours == nil or operatingHours < 0 then
                        systemStats.operatingHours = currentOperatingHours
                    end
                end
            end
        end
    end
end

local function syncColdEngineEffect(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end

    if vehicle.isServer then
        local engTemp = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)
        local breakdownId = 'COLD_ENGINE'

        if engTemp <= -10 and not vehicle:hasBreakdown(breakdownId) then
            vehicle:addBreakdown(breakdownId)
        elseif engTemp > -10 and vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        end
    end
end

local function syncOverheatProtection(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end
    local rawEngineTemp = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)
    local rawTransmissionTemp = hasCVTTransmission(vehicle) and not hasCVTAddon(vehicle) and RealisticMechanicalSystems.sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, -99, -99, 180) or -99

    if vehicle.isServer and spec.year >= 2000 then
        local overheatProtectionId = 'OVERHEAT_PROTECTION'
        local overheatProtection = vehicle:getActiveBreakdowns()[overheatProtectionId]
        if overheatProtection and rawTransmissionTemp < 100 and rawEngineTemp < 100 then
            vehicle:removeBreakdown(overheatProtectionId)
        end
        if vehicle:getIsMotorStarted() then
            if (rawTransmissionTemp > 105 or rawEngineTemp > 105) and not overheatProtection then
                vehicle:addBreakdown(overheatProtectionId, 1)
                RMS_SoundManager.playSample(spec.samples.alarm)
                RMS_EffectSyncEvent.send(vehicle, overheatProtectionId, "ALARM")
            elseif overheatProtection then
                if vehicle:getCruiseControlState() ~= 0 then
                    vehicle:setCruiseControlState(0, true)
                end
                if (rawTransmissionTemp > 125 or rawEngineTemp > 125) and overheatProtection.stage < 4 then
                    vehicle:changeBreakdownStage(overheatProtectionId)
                    RMS_SoundManager.playSample(spec.samples.alarm)
                    RMS_EffectSyncEvent.send(vehicle, overheatProtectionId, "ALARM")
                elseif (rawTransmissionTemp > 115 or rawEngineTemp > 115) and overheatProtection.stage < 3 then
                    vehicle:changeBreakdownStage(overheatProtectionId)
                    RMS_SoundManager.playSample(spec.samples.alarm)
                    RMS_EffectSyncEvent.send(vehicle, overheatProtectionId, "ALARM")
                elseif (rawTransmissionTemp > 110 or rawEngineTemp > 110) and overheatProtection.stage < 2 then
                    vehicle:changeBreakdownStage(overheatProtectionId)
                    RMS_SoundManager.playSample(spec.samples.alarm)
                    RMS_EffectSyncEvent.send(vehicle, overheatProtectionId, "ALARM")
                end
            end
        end
    else
        if vehicle.isServer then
            local engineFailedEffect = spec.activeEffects.ENGINE_FAILURE
            if rawEngineTemp > 125 and not engineFailedEffect then
                if math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, 3) then
                    vehicle:addBreakdown('ENGINE_JAM')
                end
            end
        end
    end
end

local function syncAirIntakeCloggingEffect(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then return end

    local breakdownId = 'AIRINTAKE_CLOGGING'
    local shouldBeStage = 0
    local threshold = RMS_Config.FIELD_CARE.AIR_INTAKE_BREAKDOWN_THRESHOLD 

    if spec.airIntakeClogging > threshold then
        if spec.airIntakeClogging > (threshold + (threshold / 3 * 2)) then
            shouldBeStage = 3
        elseif spec.airIntakeClogging > (threshold + (threshold / 3)) then
            shouldBeStage = 2
        else
            shouldBeStage = 1
        end
        if not vehicle:hasBreakdown(breakdownId) then
            vehicle:addBreakdown(breakdownId, shouldBeStage)
        else
            local currentStage = vehicle:getActiveBreakdowns()[breakdownId].stage
            if currentStage ~= shouldBeStage then
                vehicle:changeBreakdownStage(breakdownId, shouldBeStage)
            end
        end
    else
        if vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        end
    end
end

local function syncDisableAiWorkers(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then
        return
    end

    if spec.activeEffects ~= nil and next(spec.activeEffects) ~= nil then
        for _, effectData in pairs(spec.activeEffects) do
            if effectData ~= nil and effectData.extraData ~= nil and effectData.extraData.disableAi then
                local isCriticalOverload = effectData.extraData.criticalOverload == true
                local shouldDisableAi = not isCriticalOverload
                    or (RMS_Config.CORE.AI_DISABLE_ON_CRITICAL_OVERLOAD
                        and (vehicle.propertyState ~= 4 or RMS_Config.CORE.CONTRACT_VEHICLE_PROTECTION))

                if shouldDisableAi then
                    local autoDriveActive = vehicle.ad ~= nil
                        and vehicle.ad.stateModule ~= nil
                        and vehicle.ad.stateModule.isActive ~= nil
                        and vehicle.ad.stateModule:isActive()

                    if autoDriveActive and vehicle.stopAutoDrive ~= nil then
                        vehicle.ad.isStoppingWithError = true

                        if vehicle.ad.stateModule.setLoopsDone ~= nil then
                            vehicle.ad.stateModule:setLoopsDone(0)
                        end

                        vehicle:stopAutoDrive()
                    end

                    if vehicle:getIsAIActive() and vehicle.stopCurrentAIJob ~= nil then
                        vehicle:stopCurrentAIJob(AIMessageErrorVehicleBroken.new())
                    end

                    return
                end
            end
        end
    end
end

local COLD_ENGINE_WARNING_MESSAGE = 'rms_spec_cold_engine_message'

local function getColdEngineStress(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA

    if not vehicle:getIsMotorStarted()
            or spec.isElectricVehicle
            or vehicle:getIsAIActive()
            or spec.engineTemperature >= C.COLD_MOTOR_TEMP_THRESHOLD then
        return 0
    end

    local motorLoad = math.clamp(spec._smoothedMotorLoad, 0, 1)
    if motorLoad <= C.MOTOR_OVERLOADED_THRESHOLD then
        return 0
    end

    local motor = vehicle.spec_motorized.motor
    local rpmLoad = math.clamp(motor:getLastModulatedMotorRpm() / motor.maxRpm, 0, 1)
    local temperatureFactor = RMS_Utils.calculateQuadraticMultiplier(
        spec.engineTemperature,
        C.COLD_MOTOR_TEMP_THRESHOLD,
        true
    )
    local loadFactor = math.clamp(RMS_Utils.calculateQuadraticMultiplier(
        motorLoad,
        C.MOTOR_OVERLOADED_THRESHOLD,
        false
    ), 0, 1)
    local rpmFactor = 1 - C.COLD_MOTOR_RPM_INFLUENCE
        + C.COLD_MOTOR_RPM_INFLUENCE * rpmLoad * rpmLoad

    return temperatureFactor * loadFactor * rpmFactor
end
RealisticMechanicalSystems.getColdEngineStress = getColdEngineStress

local function syncBlinkingWarning(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isClient then return end

    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    if spec.engineTemperature >= C.COLD_MOTOR_TEMP_THRESHOLD then
        spec.coldEngineExposureMs = 0
        spec.coldEngineWarningShown = false
    end

    if RMS_Config.CORE ~= nil and RMS_Config.CORE.ENABLE_WARNING_MESSAGES == false then
        return
    end

    local repeatDelayMs = 180000

    if spec.blinkingWarningTimer == nil then
        spec.blinkingWarningTimer = 0
    end

    if spec.lastBlinkingWarningMessage == nil then
        spec.lastBlinkingWarningMessage = ""
    end

    if spec.blinkingWarningTimer > 0 then
        spec.blinkingWarningTimer = math.max(spec.blinkingWarningTimer - dt, 0)
    end

    local candidateMessage = nil
    local isActiveForInput = vehicle:getIsActiveForInput(true)
    local isAiActive = vehicle:getIsAIActive()
    local isUnderService = vehicle:isUnderService()
    local isMotorStarted = vehicle:getIsMotorStarted()
    local coldEngineStress = 0

    if isMotorStarted and isActiveForInput and not isAiActive and not spec.isElectricVehicle then
        local spec_motorized = vehicle.spec_motorized
        local motor = spec_motorized ~= nil and spec_motorized.motor or nil
        if motor ~= nil then
            local lastRpm = tonumber(motor:getLastModulatedMotorRpm()) or 0
            local maxRpm = math.max(tonumber(motor.maxRpm) or 0, 0.0001)
            local rpmLoad = lastRpm / maxRpm
            local motorLoad = 0

            if vehicle.getMotorLoad ~= nil then
                motorLoad = tonumber(vehicle:getMotorLoad()) or 0
            elseif vehicle.getMotorLoadPercentage ~= nil then
                motorLoad = tonumber(vehicle:getMotorLoadPercentage()) or 0
            end

            if spec.engineTemperature > -90 then
                coldEngineStress = getColdEngineStress(vehicle)
                if coldEngineStress > 0 then
                    spec.coldEngineExposureMs = spec.coldEngineExposureMs + dt
                end

                if coldEngineStress > 0
                        and spec.coldEngineExposureMs >= C.COLD_MOTOR_WARNING_EXPOSURE_MS
                        and not spec.coldEngineWarningShown then
                    candidateMessage = COLD_ENGINE_WARNING_MESSAGE
                elseif spec.engineTemperature >= RMS_Config.CORE.ENGINE_FACTOR_DATA.OVERHEAT_MOTOR_THRESHOLD + 5 and motorLoad > 0.3 then
                    candidateMessage = 'rms_spec_overheat_engine_message'
                end
            end

            if candidateMessage == nil and hasCVTTransmission(vehicle) and spec.transmissionTemperature > -90 then
                if spec.transmissionTemperature >= RMS_Config.CORE.TRANSMISSION_FACTOR_DATA.OVERHEAT_TRANSMISSION_THRESHOLD + 5 and rpmLoad > 0.75 then
                    candidateMessage = 'rms_spec_overheat_transmission_message'
                end
            end
        end
    end

    if coldEngineStress == 0 then
        spec.coldEngineExposureMs = math.max(spec.coldEngineExposureMs - dt, 0)
    end

    --- Messages from breakdowns
    if spec.activeEffects ~= nil and next(spec.activeEffects) ~= nil then
        for _, effectData in pairs(spec.activeEffects) do
            if effectData ~= nil and effectData.extraData ~= nil and effectData.extraData.message ~= nil then
                if candidateMessage == nil and isActiveForInput and not isUnderService then
                    candidateMessage = effectData.extraData.message
                end
            end
        end
    end

    if candidateMessage ~= nil
            and isActiveForInput
            and not isAiActive
            and not isUnderService
            and (spec.blinkingWarningTimer == 0 or spec.lastBlinkingWarningMessage ~= candidateMessage) then
        g_currentMission:showBlinkingWarning(g_i18n:getText(candidateMessage), 3600)
        spec.lastBlinkingWarningMessage = candidateMessage
        spec.blinkingWarningTimer = repeatDelayMs
        if candidateMessage == COLD_ENGINE_WARNING_MESSAGE then
            spec.coldEngineWarningShown = true
        end
    end
end

local function syncSideNotifications(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isClient then
        return
    end

    if RMS_Config.CORE ~= nil and RMS_Config.CORE.ENABLE_WARNING_MESSAGES == false then
        return
    end

    if spec.pendingSideNotifications == nil or next(spec.pendingSideNotifications) == nil then
        return
    end

    if vehicle:getOwnerFarmId() ~= g_currentMission:getFarmId()
            or g_currentMission.hud == nil
            or g_currentMission.hud.addSideNotification == nil then
        return
    end

    for _, notificationText in ipairs(spec.pendingSideNotifications) do
        g_currentMission.hud:addSideNotification(RMS_Breakdowns.COLORS.WARNING, vehicle:getFullName() .. ": " .. notificationText)
    end

    spec.pendingSideNotifications = {}
end

local function syncFuelConsumption(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end

    if vehicle.isServer and vehicle.spec_motorized ~= nil then
        if vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then
            spec._fuelUsageRaw = RealisticMechanicalSystems.sanitizeNumber(vehicle.spec_motorized.lastFuelUsage, 0, 0, 10000)
        else
            spec._fuelUsageRaw = 0
        end
    end
    if vehicle.isClient and not vehicle.isServer and vehicle.spec_motorized ~= nil then
        vehicle.spec_motorized.lastFuelUsage = RealisticMechanicalSystems.sanitizeNumber(spec._fuelUsageRaw, 0, 0, 10000)
    end
end

local function syncCVTaddonBreakdown(vehicle)
    if not hasCVTAddon(vehicle) then return end
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then return end

    local breakdownId = 'CVT_ADDON_MALFUNCTION'
    local spec_CVTaddon = vehicle.spec_CVTaddon
    if spec_CVTaddon ~= nil then
        local shouldHaveBreakdown = spec_CVTaddon.CVTdamage > 60.0
        local shouldBeStage = 1
        if spec_CVTaddon.CVTdamage > 90.0 then
            shouldBeStage = 4
        elseif spec_CVTaddon.CVTdamage > 80.0 then
            shouldBeStage = 3
        elseif spec_CVTaddon.CVTdamage > 70.0 then
            shouldBeStage = 2
        end

        if shouldHaveBreakdown and not vehicle:hasBreakdown(breakdownId) then
            vehicle:addBreakdown(breakdownId, shouldBeStage)
        elseif not shouldHaveBreakdown and vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        elseif shouldHaveBreakdown and vehicle:hasBreakdown(breakdownId) then
            local currentStage = vehicle:getActiveBreakdowns()[breakdownId].stage
            if currentStage ~= shouldBeStage then
                vehicle:changeBreakdownStage(breakdownId, shouldBeStage)
            end
        end
    else
        if vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        end
    end
end

local function syncOverloadWarning(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then return end
    local period = 60000
    local wearScale = RMS_Config.CORE.BASE_SYSTEMS_WEAR / RMS_Config.CORE.REFERENCE_SYSTEMS_WEAR
    local avgStressWarningThreshold = RMS_Config.CORE.AVG_STRESS_WARNING_THRESHOLD * RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER * wearScale
    local avgStressCriticalThreshold = RMS_Config.CORE.AVG_STRESS_CRITICAL_THRESHOLD * RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER * wearScale
    local sampleDurationMs = math.max(tonumber(dt) or 0, 1)
    local isMotorStarted = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()

    local factorStats = ensureFactorStats(spec, vehicle)
    local stressMultipliers = RMS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS or {}
    local globalStressMultiplier = math.max(tonumber(RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER) or 1.0, 0.0)

    local overloadFactorAliasesBySystem = {
        engine = { "mlf", "hmf", "lf" },
        transmission = { "pof", "htf", "lf", "wsf", "hotf" }
    }

    local shouldStage = 0
    local maxAvgStress = 0
    for systemName, systemData in pairs(factorStats) do
        if type(systemData) == "table" then
            local systemStressMultiplier = tonumber(stressMultipliers[systemName]) or 1.0
            local selectedAliases = overloadFactorAliasesBySystem[tostring(systemName)]
            local currentStress = 0

            if type(selectedAliases) == "table" then
                for _, alias in ipairs(selectedAliases) do
                    currentStress = currentStress + math.max(tonumber(systemData[alias]) or 0, 0)
                end
                currentStress = currentStress * systemStressMultiplier * globalStressMultiplier
            end

            if not isMotorStarted then
                systemData._prevStress = currentStress
                systemData._avgStress = 0
                systemData._avgStressSamples = {}

                if RMS_Config.DEBUG and spec.debugData ~= nil and spec.debugData[systemName] ~= nil then
                    spec.debugData[systemName]._avgStress = 0
                end
            else
            local previousStress = tonumber(systemData._prevStress)
            if previousStress == nil then
                previousStress = currentStress
            end

            local deltaStress = math.max(currentStress - previousStress, 0)
            local sampleRatePerHour = deltaStress * (60 * 60 * 1000) / sampleDurationMs
            systemData._prevStress = currentStress

            if type(systemData._avgStressSamples) ~= "table" then
                systemData._avgStressSamples = {}
            end

            local samples = systemData._avgStressSamples
            if sampleRatePerHour > 0 or #samples > 0 then
                table.insert(samples, {
                    durationMs = sampleDurationMs,
                    ratePerHour = sampleRatePerHour
                })
            end

            local totalSamplesDurationMs = 0
            local weightedSum = 0
            for _, sample in ipairs(samples) do
                local durationMs = math.max(tonumber(sample.durationMs) or 0, 0)
                local ratePerHour = tonumber(sample.ratePerHour) or 0
                totalSamplesDurationMs = totalSamplesDurationMs + durationMs
                weightedSum = weightedSum + ratePerHour * durationMs
            end

            while #samples > 0 and totalSamplesDurationMs > period do
                local oldest = samples[1]
                local oldestDurationMs = math.max(tonumber(oldest.durationMs) or 0, 0)
                local overflowMs = totalSamplesDurationMs - period

                if oldestDurationMs <= overflowMs then
                    totalSamplesDurationMs = totalSamplesDurationMs - oldestDurationMs
                    weightedSum = weightedSum - (tonumber(oldest.ratePerHour) or 0) * oldestDurationMs
                    table.remove(samples, 1)
                else
                    oldest.durationMs = oldestDurationMs - overflowMs
                    totalSamplesDurationMs = totalSamplesDurationMs - overflowMs
                    weightedSum = weightedSum - (tonumber(oldest.ratePerHour) or 0) * overflowMs
                end
            end

            if weightedSum <= 0 or totalSamplesDurationMs <= 0 then
                systemData._avgStress = 0
                systemData._avgStressSamples = {}
                samples = systemData._avgStressSamples
            else
                systemData._avgStress = math.max(weightedSum / period, 0)
                if systemData._avgStress > maxAvgStress then maxAvgStress = systemData._avgStress end
            end

            if RMS_Config.DEBUG and spec.debugData ~= nil and spec.debugData[systemName] ~= nil then
                spec.debugData[systemName]._avgStress = systemData._avgStress
            end

            local affectsOverloadBreakdown = type(selectedAliases) == "table" and #selectedAliases > 0
            if affectsOverloadBreakdown then
                if systemData._avgStress > avgStressCriticalThreshold then
                    shouldStage = 2
                elseif systemData._avgStress > avgStressWarningThreshold and shouldStage == 0 then
                    shouldStage = 1
                end
            end
            end
        end
    end
    local breakdownId = "STRESS_OVERLOAD"
    local activeBreakdowns = spec.activeBreakdowns or {}
    local currentBreakdown = activeBreakdowns[breakdownId]

    if shouldStage > 0 then
        if currentBreakdown == nil then
            vehicle:addBreakdown(breakdownId, shouldStage)
        elseif currentBreakdown.stage < shouldStage then
            vehicle:changeBreakdownStage(breakdownId, shouldStage)
        end
    elseif currentBreakdown ~= nil and maxAvgStress < avgStressWarningThreshold * 0.5 then
        vehicle:removeBreakdown(breakdownId)
    end
end

local function getSmoothedMotorLoad(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end

    if vehicle:getIsMotorStarted() then
        local rawLoad = math.max(vehicle:getMotorLoadPercentage() or 0, 0)
        local loadTau = 300
        local loadAlpha = math.min(dt / (loadTau + dt), 1)
        spec._smoothedMotorLoad = (spec._smoothedMotorLoad or 0) + loadAlpha * (rawLoad - (spec._smoothedMotorLoad or 0))
    else
        spec._smoothedMotorLoad = 0
    end
end

function RealisticMechanicalSystems:onUpdate(dt, ...)
    local spec = self.spec_RealisticMechanicalSystems
    self:updateFieldInspectionSound()
    if spec.isExcludedVehicle then return end

    self:updateVehicleStateSnapshot(dt)
    if self.isServer then
        self:updateThermalSystems(dt, false, true)
    end
    RealisticMechanicalSystems.updateStartButtonActionEvents(self)
    RMS_Preheat.update(self, dt)

    local updateDelay = RMS_Config.ON_UPDATE_DELAY
    spec.onUpdateTimer = spec.onUpdateTimer + dt

    if spec.onUpdateTimer < updateDelay then
        return
    end

    -- State-based callbacks must only evaluate the current state once. Discard
    -- missed sampling intervals instead of replaying them with stale data.
    spec.onUpdateTimer = spec.onUpdateTimer % updateDelay
    local updateDt = updateDelay

    --- Registration in RMS_Main.vehicles and first load checks.
    registerVehicle(self)

    --- Temperature smoothing
    self:getSmoothedTemperature(updateDt)

    --- Fuel consumption
    syncFuelConsumption(self)

    --- smoothedMotorLoad
    getSmoothedMotorLoad(self, updateDt)

    --- Checking for cold engine effect
    syncColdEngineEffect(self)

    --- Checking for dead battery if motor is off
    self:syncDeadBatteryEffect()

    --- Checking for dead alternator or dead battery
    self:syncVoltageSagEffect(updateDt)

    --- Checking for airintake clogging
    syncAirIntakeCloggingEffect(self)
    
    --- Overheat protection for vehcile > 2000 year and engine failure from overheating for < 2000
    syncOverheatProtection(self, updateDt)

    --- CVT addon breakdown sync
    syncCVTaddonBreakdown(self)
    
    --- Blinking warning for currently controlled vehicle
    syncBlinkingWarning(self, updateDt)

    --- Side notifications for vehicles without players at the moment of the effect event
    syncSideNotifications(self)

    --- Disable AI workers for critical effects
    syncDisableAiWorkers(self)

    --- 4WD / differential lock management
    self:updateDrivetrain(updateDt)

    --- just in case, reset damage amount to 0 if it's not
    if self.isServer and self.getDamageAmount ~= nil and self:getDamageAmount() ~= 0 then self:setDamageAmount(0.0, true) end
    
    --- AI worker overload, temp control
    if RMS_Config.CORE.AI_OVERLOAD_AND_OVERHEAT_CONTROL then
        self:updateAiWorkerCruiseControl(updateDt)
    end

    --- Enables the thermal model for neutral vehicles on the map, should the player happen to use them
    if self.isServer and RMS_Main and RMS_Main.vehicles and RMS_Main.vehicles[self.uniqueId] == nil and self:getIsControlled() then
        self:updateThermalSystems(updateDt, true, false)
    end

    --- Exhaust smoke colour, opacity and plume size
    if self.isClient then
        RMS_Exhaust.update(self, updateDt)
    end

    --- Random and permanent effects from breakdowns. Skip if spec.activeEffects is empty
    if spec ~= nil and spec.activeFunctions ~= nil and next(spec.activeFunctions) ~= nil then
        for _ , func in pairs(spec.activeFunctions) do
            func(self, updateDt)
        end
    end
end

function RealisticMechanicalSystems:onPostUpdateTick(dt, ...)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isClient or spec.isExcludedVehicle then return end

    RMS_Exhaust.applyShader(self)
end

function RealisticMechanicalSystems:rmsUpdate(dt, isWorkshopOpen)
    local spec = self.spec_RealisticMechanicalSystems
    if spec.isExcludedVehicle then return end

    -- OP Time update for RMS vehicles
    local motorState = self.getMotorState ~= nil and self:getMotorState() or nil
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local operatingDt = 0

    if (spec.realOperatingTime == nil or spec.realOperatingTime <= 0) and currentOperatingTime > 0 then
        spec.realOperatingTime = currentOperatingTime
    end

    if motorState == MotorState.ON then
        operatingDt = dt or 0
        if g_modIsLoaded ~= nil and g_modIsLoaded["FS25_ingameTimeOperatingHours"] then
            local timeScale = getSafeMissionTimeScale()
            operatingDt = dt * timeScale
        end

        spec.realOperatingTime = (spec.realOperatingTime or 0) + dt
        spec._allowRMSOperatingTimeWrite = true
        self:setOperatingTime(currentOperatingTime + operatingDt, false)
        spec._allowRMSOperatingTimeWrite = false
    end

    self:updateThermalSystems(dt, true, false)
    self:updateBatteryChargingModel(dt)

    if self:isUnderService() then
        self:processService(dt)
    else
        if self:getIsOperating() and self.propertyState ~= 4 then
            self:updateRadiatorClogging(dt)
            self:updateAirIntakeClogging(dt)
            self:processBreakdowns(dt)
            self:tryTriggerBreakdown(dt)
        end

        -- service
        self:updateServiceLevel(dt)
        -- systems
        self:updateEngineSystem(dt)
        self:updateTransmissionSystem(dt)
        self:updateHydraulicsSystem(dt)
        self:updatePtoSystem(dt)
        self:updateCoolingSystem(dt)
        self:updateElectricalSystem(dt)
        self:updateChassisSystem(dt)
        self:updateFuelSystem(dt)
        -- condtition
        self:updateConditionLevel()
        -- general wear
        self:processGeneralWearBreakdown()
        -- lubrication level
        self:updateLubricationLevel(operatingDt, motorState)
        --- Overload warnings / rolling avg stress
        syncOverloadWarning(self, dt)
    end

    -- Raise dirty flags for changed data
    if self.isServer then
        markStateDirty(self, spec)
        markServiceContextDirty(self, spec)
        markTelemetryDirty(self, spec)
        markThermalDirty(self, spec)
        markElectricalDirty(self, spec)
        markFieldcareDirty(self, spec)
        markWearDirty(self, spec)
        markBreakdownsDirty(self, spec)
        markServiceProgressDirty(self, spec)
        markTutorialDataDirty(self, spec)
    end
end

-- ==========================================================
--                OVERWRITTEN FUNCTIONS
-- ==========================================================

function RealisticMechanicalSystems.updateDamageAmount(wearable, superFunc, dt)
	if wearable.spec_RealisticMechanicalSystems ~= nil and not wearable.spec_RealisticMechanicalSystems.isExcludedVehicle then
		return 0
	else
		return superFunc(wearable, dt)
	end
end

function RealisticMechanicalSystems.setOperatingTime(self, superFunc, operatingTime, isLoading)
    local spec = self.spec_RealisticMechanicalSystems
    if spec ~= nil and not spec.isExcludedVehicle and not isLoading and not spec._allowRMSOperatingTimeWrite then
        return
    end

    superFunc(self, operatingTime, isLoading)
end

function RealisticMechanicalSystems.getSellPrice(self, superFunc)
	if self.spec_RealisticMechanicalSystems ~= nil and not self.spec_RealisticMechanicalSystems.isExcludedVehicle then
		local overallCondition = self:getConditionLevel() or 1.0
        local price = self:getPrice() or 0
        local repaintPrice = Wearable.calculateRepaintPrice(price, self:getWearTotalAmount()) * 0.25
        local repairPrice = self:getServicePrice(
            RealisticMechanicalSystems.STATUS.REPAIR,
            RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM,
            RealisticMechanicalSystems.PART_TYPES.OEM, false, RealisticMechanicalSystems.WORKSHOP.DEALER, true)
        return math.clamp(price * overallCondition - repaintPrice - repairPrice, price * 0.03, price * 0.8)
	else
		return superFunc(self)
	end
end

function RealisticMechanicalSystems.updateMotorTemperature(self, superFunc, dt)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle or hasCVTAddon(self) then
        return superFunc(self, dt)
    else
        local spec_motorized = self.spec_motorized
        if spec_motorized ~= nil then
            self.spec_motorized.motorTemperature.value = RealisticMechanicalSystems.sanitizeNumber(spec.engineTemperature, 20, -80, 160)
        end
    end
end

-- ==========================================================
--                        GETTERS
-- ==========================================================

function RealisticMechanicalSystems:getServiceLevel()
    return self.spec_RealisticMechanicalSystems.serviceLevel
end

function RealisticMechanicalSystems:getConditionLevel()
    return self.spec_RealisticMechanicalSystems.conditionLevel
end

function RealisticMechanicalSystems:getSystemConditionLevel(systemName)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)
    return spec.systems[systemKey].condition
end

function RealisticMechanicalSystems:getSystemStressLevel(systemName)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)
    return spec.systems[systemKey].stress
end

function RealisticMechanicalSystems:isUnderRoofRaycastCallback()
    local spec = self.spec_RealisticMechanicalSystems
    if spec ~= nil then
        spec.roofRaycastHit = true
    end
end

function RealisticMechanicalSystems:isUnderRoof()
    local spec = self.spec_RealisticMechanicalSystems
    local node = self.rootNode
    if (node == nil or node == 0) and self.components ~= nil and self.components[1] ~= nil then
        node = self.components[1].node
    end

    if node == nil or node == 0 then
        return false
    end

    local x, y, z = getWorldTranslation(node)
    local mission = g_currentMission
    local isIndoorMask = false

    if mission ~= nil and mission.indoorMask ~= nil then
        if mission.indoorMask.getIsIndoorAtWorldPosition ~= nil then
            isIndoorMask = mission.indoorMask:getIsIndoorAtWorldPosition(x, z) == true
        else
            local handle, firstChannel, numChannels = mission.indoorMask:getDensityMapData()
            if handle ~= nil and handle ~= 0 and mission.terrainSize ~= nil and mission.terrainSize > 0 then
                local maskSize = getBitVectorMapSize(handle)
                if maskSize ~= nil and maskSize > 0 then
                    local terrainHalfSize = mission.terrainSize * 0.5
                    local worldToDensityMap = maskSize / mission.terrainSize
                    local xI = math.floor((x + terrainHalfSize) * worldToDensityMap)
                    local zI = math.floor((z + terrainHalfSize) * worldToDensityMap)

                    if xI >= 0 and xI < maskSize and zI >= 0 and zI < maskSize then
                        local maskValue = getBitVectorMapPoint(handle, xI, zI, firstChannel, numChannels)
                        local indoorValue = IndoorMask ~= nil and IndoorMask.INDOOR or 1
                        isIndoorMask = maskValue == indoorValue
                    end
                end
            end
        end
    end

    local movementVehicle = self.rootVehicle or self
    local speed = movementVehicle.getLastSpeed ~= nil and math.abs(tonumber(movementVehicle:getLastSpeed(true)) or 0) or 0
    local stationarySpeedLimit = tonumber(RMS_Config.ROOF_STATIONARY_SPEED_LIMIT) or 0.5
    local isStationary = speed <= stationarySpeedLimit

    if not isStationary then
        if spec ~= nil then
            spec.roofWasStationary = false
            spec.roofLastRaycastTime = nil
            spec.roofRaycastResult = nil
        end
        return isIndoorMask
    end

    if spec == nil then
        return isIndoorMask
    end

    local now = (mission ~= nil and mission.time) or g_time or 0
    local raycastInterval = tonumber(RMS_Config.ROOF_RAYCAST_INTERVAL) or 5000
    local lastRaycastTime = tonumber(spec.roofLastRaycastTime)
    local needsRaycast = spec.roofWasStationary ~= true
        or lastRaycastTime == nil
        or now < lastRaycastTime
        or now - lastRaycastTime >= raycastInterval

    spec.roofWasStationary = true

    if needsRaycast and raycastClosest ~= nil and CollisionFlag ~= nil then
        spec.roofLastRaycastTime = now
        spec.roofRaycastHit = false

        local roofMask = CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING
        raycastClosest(
            x,
            y + (tonumber(RMS_Config.ROOF_RAYCAST_START_OFFSET) or 1),
            z,
            0,
            1,
            0,
            tonumber(RMS_Config.ROOF_RAYCAST_DISTANCE) or 40,
            "isUnderRoofRaycastCallback",
            self,
            roofMask
        )

        spec.roofRaycastResult = spec.roofRaycastHit == true
    end

    if spec.roofRaycastResult ~= nil then
        return spec.roofRaycastResult == true
    end

    return isIndoorMask
end

function RealisticMechanicalSystems:isUnderService()
    return self.spec_RealisticMechanicalSystems.currentState ~= RealisticMechanicalSystems.STATUS.READY
end

function RealisticMechanicalSystems:getCurrentStatus()
    return self.spec_RealisticMechanicalSystems.currentState
end

function RealisticMechanicalSystems:getActiveBreakdowns()
    return self.spec_RealisticMechanicalSystems.activeBreakdowns
end

function RealisticMechanicalSystems.getBrandReliability(vehicle, storeItem)
    local year = RMS_VehicleYears.DEFAULT_YEAR
    local brandName = 'LIZARD'
    local name = 'LIZARD'

    if vehicle ~= nil then
        name = vehicle:getName()
        local brand = g_brandManager:getBrandByIndex(vehicle:getBrand())
        if not brand then
            return 1.0, 1.0
        end

        brandName = brand.name
        storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)

    elseif storeItem ~= nil then
        name = storeItem.name
        brandName = storeItem.brandNameRaw
    end

    if storeItem ~= nil then
        year = RMS_VehicleYears.getYear(storeItem)
    end

    local yearFactor = 0
    if year < RMS_Config.CORE.RELIABILITY_YEAR_FACTOR_THRESHOLD then
        yearFactor = math.max(RMS_Config.CORE.RELIABILITY_YEAR_FACTOR_THRESHOLD - year, 0) * RMS_Config.CORE.RELIABILITY_YEAR_FACTOR
    end

    local modelData = RMS_Config.BRANDS[name]

    if modelData ~= nil then
        return modelData[1], modelData[2]
    end

    local brandData = RMS_Config.BRANDS[brandName]

    if brandData ~= nil then
        return brandData[1], brandData[2] + yearFactor
    else
        return 1.0, 1.0
    end
end

function RealisticMechanicalSystems.calculateBreakdownProbability(level, p, dt)
    local threshold = math.clamp(tonumber(RMS_Config.CORE.BREAKDOWN_PROBABILITIES.STRESS_THRESHOLD) or 1.0, 0.0, 0.999)
    local clampedLevel = math.max(tonumber(level) or 0, 0.0)
    local normalizedLevel = math.clamp((clampedLevel - threshold) / math.max(1 - threshold, 0.001), 0.0, 1.0)

    local calculatedMtbf = p.MAX_MTBF + (p.MIN_MTBF - p.MAX_MTBF) * normalizedLevel ^ (math.max(p.DEGREE - p.DEGREE * normalizedLevel, 0.1))
    local mtbfInMinutes = math.max(calculatedMtbf, p.MIN_MTBF)
    local mtbfInMillis = mtbfInMinutes * 60 * 1000

    if mtbfInMillis <= 0 then
        return 1.0
    end

    return 1 - math.exp(-dt / mtbfInMillis)
end

-- ==========================================================
--                   SPECIALIZATION MODULES
-- ==========================================================

source(g_currentModDirectory .. "scripts/core/RMS_SpecSaveLoad.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecStreams.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecVehicleState.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecWear.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecBreakdowns.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecService.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecAiWorker.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecConsole.lua")
