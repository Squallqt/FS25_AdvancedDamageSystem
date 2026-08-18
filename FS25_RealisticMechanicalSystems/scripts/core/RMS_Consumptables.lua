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
function RMS_Consumptables:updateRadiatorClogging(dt)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    if not spec.isVehicleNeedBlowOut then
        spec.radiatorClogging = 0
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

    local dirtLevel = self:getDirtAmount()
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
function RMS_Consumptables:updateAirIntakeClogging(dt)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    if not spec.isVehicleNeedBlowOut then
        spec.airIntakeClogging = 0
        return
    end

    if spec.debugData == nil then
        spec.debugData = {}
    end
    if spec.debugData.airIntake == nil then
        spec.debugData.airIntake = {
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
    local dbg = spec.debugData.airIntake

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

    if lastSpeed > 0.5 and spec.airIntakeClogging < dirtLevel then
        if washableSpec == nil then
            return
        end
        
        local dirtDuration = ((washableSpec.dirtDuration or 0) / 4) * (RMS_Config.CORE.BASE_SERVICE_WEAR * 10)
        local totalMultiplier = wetnessFactor * (fieldFactor + dustFactor + debrisFactor) * C.CLOGGING_SPEED
        dbg.totalMultiplier = totalMultiplier

        local change = dirtDuration * totalMultiplier * dt
        spec.airIntakeClogging = math.min(spec.airIntakeClogging + change, dirtLevel)
    else
        if spec.airIntakeClogging > dirtLevel then
            spec.airIntakeClogging = dirtLevel
        end
    end
end

---Clears radiator and air intake clogging at the configured cleaning speed
-- @param float dt time since last call in ms
function RMS_Consumptables:cleanRadiatorAndAirIntake(dt)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local prevRadiatorClogging = tonumber(spec.radiatorClogging) or 0
    local prevAirIntakeClogging = tonumber(spec.airIntakeClogging) or 0
    local cleaningDelta = (C.CLEANING_SPEED / 1000) * dt

    spec.radiatorClogging = math.max(prevRadiatorClogging - cleaningDelta, 0)
    spec.airIntakeClogging = math.max(prevAirIntakeClogging - cleaningDelta, 0)

    if RMS_Config.TUTORIAL_MESSAGES ~= nil and RMS_Config.TUTORIAL_MESSAGES.RAD_OR_INTAKE_CLOGGED ~= nil and not RMS_Config.TUTORIAL_MESSAGES.RAD_OR_INTAKE_CLOGGED then
        RMS_Config.TUTORIAL_MESSAGES.RAD_OR_INTAKE_CLOGGED = true
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

    if self.isClient and RMS_Hud ~= nil then
        RMS_Hud.showNotification(string.format(g_i18n:getText("rms_field_inspection_progress"), 0), inspection.duration)
    end

    return true
end
