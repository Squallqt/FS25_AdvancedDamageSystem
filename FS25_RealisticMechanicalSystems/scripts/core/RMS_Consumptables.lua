-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Consumable upkeep of a vehicle: radiator and air intake clogging, lubrication, field inspection
RMS_Consumptables = RMS_Consumptables or {}

---Flags the field inspection sound dirty when the set of inspecting players becomes empty or not
-- @param table vehicle vehicle
-- @param table spec vehicle spec
local function updateFieldInspectionSoundActive(vehicle, spec)
    local isActive = next(spec.fieldInspectionActivePlayers) ~= nil
    if spec.fieldInspectionSoundActive ~= isActive then
        spec.fieldInspectionSoundActive = isActive
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Registers a player as inspecting this vehicle until the configured duration elapses
-- @param table player player
-- @param boolean isActive true when the inspection starts
function RMS_Consumptables:setFieldInspectionPlayerActive(player, isActive)
    if not self.isServer or player == nil then
        return
    end

    local spec = self.spec_RealisticMechanicalSystems
    if isActive then
        spec.fieldInspectionActivePlayers[player] = g_time + RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    else
        spec.fieldInspectionActivePlayers[player] = nil
    end

    updateFieldInspectionSoundActive(self, spec)
end

---Drops the players whose inspection elapsed on the server, plays the sound on a client
function RMS_Consumptables:updateFieldInspectionSound()
    local spec = self.spec_RealisticMechanicalSystems

    if self.isServer then
        for player, endTime in pairs(spec.fieldInspectionActivePlayers) do
            if endTime <= g_time then
                spec.fieldInspectionActivePlayers[player] = nil
            end
        end
        updateFieldInspectionSoundActive(self, spec)
    end

    if self.isClient and spec.samples ~= nil then
        RMS_SoundManager.setSamplePlaying(spec.samples.inspection, not spec.isExcludedVehicle and spec.fieldInspectionSoundActive)
    end
end

---Accumulates radiator clogging from ground wetness, field work, dust and debris, capped at the dirt level
-- @param float dt time since last call in ms
-- @param boolean? canAccumulate true while the vehicle is operating
function RMS_Consumptables:updateRadiatorClogging(dt, canAccumulate)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    if not spec.isVehicleNeedBlowOut then
        spec.radiatorClogging = 0
        return
    end

    local dirtLevel = self:getDirtAmount()
    if canAccumulate == false then
        spec.radiatorClogging = math.min(spec.radiatorClogging, dirtLevel)
        return
    end

    if spec.debugData == nil then
        spec.debugData = {}
    end
    if spec.debugData.radiator == nil then
        spec.debugData.radiator = {
            fieldFactor = 1.0,
            dustFactor = 0.0,
            debrisFactor = 0.0,
            wetness = 0,
            wetnessFactor = 1.0,
            baseWetnessFactor = 1.0,
            isOnField = false,
            hasDust = false,
            hasDebris = false,
            totalMultiplier = 0.0
        }
    end
    local dbg = spec.debugData.radiator

    local lastSpeed = self:getLastSpeed()
    local washableSpec = self.spec_washable
    local weather = g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.weather or nil
    local wetness = weather ~= nil and weather:getGroundWetness() or 0
    local baseWetnessFactor = math.max(1 - wetness, 0)
    local wetnessFactor = math.max(baseWetnessFactor ^ 3, 0)
    local isOnField = self:getIsOnField()
    local hasDust = isOnField and spec.isImplementLowered and lastSpeed > 0.1
    local fieldFactor = 0.5
    local dustFactor = hasDust and 1.0 or 0.0
    local debrisFactor = spec.hasDebris and 2.0 or 0.0

    if washableSpec ~= nil then
        fieldFactor = isOnField and (washableSpec.fieldMultiplier or 1.0) or 0.5
    end

    dbg.fieldFactor = fieldFactor
    dbg.dustFactor = dustFactor
    dbg.debrisFactor = debrisFactor
    dbg.wetness = wetness
    dbg.wetnessFactor = wetnessFactor
    dbg.baseWetnessFactor = baseWetnessFactor
    dbg.isOnField = isOnField
    dbg.hasDust = hasDust
    dbg.hasDebris = spec.hasDebris
    dbg.totalMultiplier = 0.0

    if lastSpeed > 0.5 and spec.radiatorClogging < dirtLevel then
        if washableSpec == nil then
            return
        end

        local dirtDuration = ((washableSpec.dirtDuration or 0) / 4) * (RMS_Config.CORE.BASE_SERVICE_WEAR * 10)
        local totalMultiplier = wetnessFactor * (fieldFactor + dustFactor + debrisFactor) * C.CLOGGING_SPEED
        dbg.totalMultiplier = totalMultiplier

        local change = dirtDuration * totalMultiplier * dt
        spec.radiatorClogging = math.min(spec.radiatorClogging + change, dirtLevel)
    else
        if spec.radiatorClogging > dirtLevel then
            spec.radiatorClogging = dirtLevel
        end
    end
end

---Accumulates air intake clogging on the same inputs as the radiator, with its own weighting
-- @param float dt time since last call in ms
function RMS_Consumptables:updateAirFilterClogging(dt)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    if not spec.isVehicleNeedBlowOut then
        spec.airFilterClogging = 0
        spec.airFilterResidue = 0
        return
    end

    if spec.debugData == nil then
        spec.debugData = {}
    end
    if spec.debugData.airFilter == nil then
        spec.debugData.airFilter = {
            fieldFactor = 1.0,
            dustFactor = 0.0,
            debrisFactor = 0.0,
            wetness = 0,
            wetnessFactor = 1.0,
            baseWetnessFactor = 1.0,
            isOnField = false,
            hasDust = false,
            hasDebris = false,
            totalMultiplier = 0.0
        }
    end
    local dbg = spec.debugData.airFilter

    local dirtLevel = self:getDirtAmount()
    local lastSpeed = self:getLastSpeed()
    local washableSpec = self.spec_washable
    local weather = g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.weather or nil
    local wetness = weather ~= nil and weather:getGroundWetness() or 0
    local baseWetnessFactor = math.max(1 - wetness, 0)
    local wetnessFactor = baseWetnessFactor
    local isOnField = self:getIsOnField()
    local hasDust = isOnField and spec.isImplementLowered and lastSpeed > 0.1
    local fieldFactor = 1.0
    local dustFactor = hasDust and 2.0 or 0.0
    local debrisFactor = spec.hasDebris and 1.0 or 0.0

    if washableSpec ~= nil then
        fieldFactor = isOnField and (washableSpec.fieldMultiplier or 2.0) or 1.0
    end

    dbg.fieldFactor = fieldFactor
    dbg.dustFactor = dustFactor
    dbg.debrisFactor = debrisFactor
    dbg.wetness = wetness
    dbg.wetnessFactor = wetnessFactor
    dbg.baseWetnessFactor = baseWetnessFactor
    dbg.isOnField = isOnField
    dbg.hasDust = hasDust
    dbg.hasDebris = spec.hasDebris
    dbg.totalMultiplier = 0.0

    -- air filter clogging from working hours in dust
    if lastSpeed > 0.5 and spec.airFilterClogging < 1.0 then
        if washableSpec == nil then
            return
        end

        local dirtDuration = ((washableSpec.dirtDuration or 0) / 4) * (RMS_Config.CORE.BASE_SERVICE_WEAR * 10)
        local totalMultiplier = wetnessFactor * (fieldFactor + dustFactor + debrisFactor) * C.CLOGGING_SPEED
        dbg.totalMultiplier = totalMultiplier

        local change = dirtDuration * totalMultiplier * dt
        spec.airFilterClogging = math.min(spec.airFilterClogging + change, 1.0)

        -- dust embedded in the media, cleared by a replacement only
        local residueShare = tonumber(C.AIR_FILTER_BLOWOUT_RESIDUE_SHARE) or 0
        spec.airFilterResidue = math.min((spec.airFilterResidue or 0) + change * residueShare, spec.airFilterClogging)
    end
end

---Clears radiator and air intake clogging at the configured cleaning speed
-- @param float dt time since last call in ms
function RMS_Consumptables:cleanRadiatorAndAirFilter(dt)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local prevRadiatorClogging = tonumber(spec.radiatorClogging) or 0
    local prevAirFilterClogging = tonumber(spec.airFilterClogging) or 0
    local airFilterResidue = math.clamp(tonumber(spec.airFilterResidue) or 0, 0, 1)
    local cleaningDelta = (C.CLEANING_SPEED / 1000) * dt

    spec.radiatorClogging = math.max(prevRadiatorClogging - cleaningDelta, 0)
    -- blowing out stops at the residue
    spec.airFilterClogging = math.max(prevAirFilterClogging - cleaningDelta, airFilterResidue)

    if RMS_Config.TUTORIAL_MESSAGES ~= nil and RMS_Config.TUTORIAL_MESSAGES.RAD_OR_FILTER_CLOGGED ~= nil and not RMS_Config.TUTORIAL_MESSAGES.RAD_OR_FILTER_CLOGGED then
        RMS_Config.TUTORIAL_MESSAGES.RAD_OR_FILTER_CLOGGED = true
    end

    if self.isServer then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Drops the lubrication level once per period, unless the vehicle was greased during it
function RMS_Consumptables:onLubricationPeriodChanged()
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer or spec == nil or spec.isExcludedVehicle or not spec.isVehicleNeedLubricate then
        return
    end

    if not spec.lubricationUsedThisPeriod then
        spec.lubricationLevel = math.max(
            (tonumber(spec.lubricationLevel) or 1.0) - C.LUBRICATION_REDUCE_PER_PERIOD,
            0
        )
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end

    spec.lubricationUsedThisPeriod = false
end

---Consumes lubrication over the operating time, marking the period as used while the motor runs
-- @param float operatingDt operating time since last call in ms
-- @param integer motorState motor state
function RMS_Consumptables:updateLubricationLevel(operatingDt, motorState)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if not spec.isVehicleNeedLubricate then
        return
    end

    if motorState == MotorState.ON then
        spec.lubricationUsedThisPeriod = true
    end

    spec.lubricationLevel = math.max(
        spec.lubricationLevel - C.LUBRICATION_REDUCE_PER_OPERATING_HOUR * operatingDt / (60 * 60 * 1000),
        0
    )
end

---Consumes engine oil and drains any leaking fluid over the operating time
-- @param float operatingDt operating time since last call in ms
function RMS_Consumptables:updateFluidLevels(operatingDt)
    local C = RMS_Config.FLUIDS
    local spec = self.spec_RealisticMechanicalSystems
    local hours = (tonumber(operatingDt) or 0) / (60 * 60 * 1000)
    if hours <= 0 or spec.systems == nil then
        return
    end

    -- an engine burns oil over its service interval, a worn one burns much more
    if spec.systems.engine.enabled and not spec.isElectricVehicle then
        local interval = math.max(tonumber(self:getMaintenanceInterval()) or 0, 0.001)
        local condition = math.clamp(tonumber(spec.systems.engine.condition) or 1, 0, 1)
        local load = math.clamp(tonumber(spec.dynamicMotorLoad) or 0.5, 0, 1)
        local loadFactor = (1 - C.ENGINE_OIL_LOAD_SHARE * 0.5) + C.ENGINE_OIL_LOAD_SHARE * load
        local rate = (C.ENGINE_OIL_CONSUMPTION_PER_INTERVAL / interval) * (1 + C.ENGINE_OIL_WEAR_CONSUMPTION * (1 - condition)) * loadFactor
        spec.engineOilLevel = math.max((tonumber(spec.engineOilLevel) or 1) - rate * hours, 0)
    end

    -- the other three fluids only go down through a leak
    if spec.systems.cooling.enabled then
        spec.coolantLevel = math.max((tonumber(spec.coolantLevel) or 1) - (tonumber(spec.coolantLeakRate) or 0) * hours, 0)
    end

    if spec.systems.transmission.enabled then
        spec.transmissionOilLevel = math.max((tonumber(spec.transmissionOilLevel) or 1) - (tonumber(spec.transmissionOilLeakRate) or 0) * hours, 0)
    end

    if spec.systems.hydraulics.enabled then
        spec.hydraulicFluidLevel = math.max((tonumber(spec.hydraulicFluidLevel) or 1) - (tonumber(spec.hydraulicFluidLeakRate) or 0) * hours, 0)
    end
end

---Returns how much fluid the machine is missing, in whole charges
-- @return float share sum of what every fluid it carries is missing
function RMS_Consumptables:getMissingFluidShare()
    local spec = self.spec_RealisticMechanicalSystems
    local missing = 0

    for levelKey, systemKey in pairs({engineOilLevel = "engine", coolantLevel = "cooling",
                                      transmissionOilLevel = "transmission", hydraulicFluidLevel = "hydraulics"}) do
        local systemData = spec.systems ~= nil and spec.systems[systemKey] or nil
        if systemData ~= nil and systemData.enabled ~= false then
            missing = missing + (1 - math.clamp(tonumber(spec[levelKey]) or 1, 0, 1))
        end
    end

    return missing
end

---Fills back the fluids nothing leaks any more
function RMS_Consumptables:topUpRepairedLeaks()
    local spec = self.spec_RealisticMechanicalSystems
    local filled = false

    for levelKey, rateKey in pairs({coolantLevel = "coolantLeakRate",
                                    transmissionOilLevel = "transmissionOilLeakRate",
                                    hydraulicFluidLevel = "hydraulicFluidLeakRate"}) do
        if (tonumber(spec[rateKey]) or 0) <= 0 and (tonumber(spec[levelKey]) or 1) < 1.0 then
            spec[levelKey] = 1.0
            filled = true
        end
    end

    if filled and self.isServer then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Fills every fluid the machine carries back up
function RMS_Consumptables:refillVehicleFluids()
    local spec = self.spec_RealisticMechanicalSystems
    spec.engineOilLevel = 1.0
    spec.coolantLevel = 1.0
    spec.transmissionOilLevel = 1.0
    spec.hydraulicFluidLevel = 1.0

    if self.isServer then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Restores one grease gun charge of lubrication, capped at full
function RMS_Consumptables:lubricateVehicle()
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems

    spec.lubricationLevel = math.min(spec.lubricationLevel + C.LUBRICATION_RESTORE_PER_USE, 1.0)
    spec.lubricationUsedThisPeriod = true

    if RMS_Config.TUTORIAL_MESSAGES ~= nil and RMS_Config.TUTORIAL_MESSAGES.NEEDS_LUBRICATION ~= nil and not RMS_Config.TUTORIAL_MESSAGES.NEEDS_LUBRICATION then
        RMS_Config.TUTORIAL_MESSAGES.NEEDS_LUBRICATION = true
    end

    if self.isServer then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Starts a field inspection, refused while the motor runs or a service is in progress
-- @return boolean started true when the inspection began
function RMS_Consumptables:startFieldVisualInspectionProcess()
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return false
    end

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        if self.isClient and g_currentMission ~= nil then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_field_inspection_engine_must_be_stopped"), 2200)
        end
        return false
    end

    if self:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY then
        return false
    end

    local inspection = spec.fieldInspection
    if inspection == nil then
        return false
    end

    if inspection.isActive then
        return false
    end

    inspection.isActive = true
    inspection.elapsedTime = 0
    inspection.duration = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    inspection.startTime = g_time
    inspection.targetVehicle = self

    local node = self.rootNode
    if (node == nil or node == 0) and self.components ~= nil and self.components[1] ~= nil then
        node = self.components[1].node
    end
    inspection.targetNode = node

    RMS_FieldInspectionEvent.send(self, true)

    return true
end
