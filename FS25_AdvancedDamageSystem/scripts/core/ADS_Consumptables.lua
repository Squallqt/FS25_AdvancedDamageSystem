ADS_Consumptables = ADS_Consumptables or {}

-- ==========================================================
--                  HELPER FUNCTIONS
-- ==========================================================

local function raiseFieldcareDirty(vehicle, spec)
    if vehicle ~= nil
        and vehicle.isServer
        and spec ~= nil
        and spec.adsDirtyFlag_fieldcare ~= nil
        and vehicle.raiseDirtyFlags ~= nil then
        vehicle:raiseDirtyFlags(spec.adsDirtyFlag_fieldcare)
    end
end

local function updateFieldInspectionSoundActive(vehicle, spec)
    local isActive = next(spec.fieldInspectionActivePlayers) ~= nil
    if spec.fieldInspectionSoundActive ~= isActive then
        spec.fieldInspectionSoundActive = isActive
        raiseFieldcareDirty(vehicle, spec)
    end
end

function ADS_Consumptables:setFieldInspectionPlayerActive(player, isActive)
    if not self.isServer or player == nil then
        return
    end

    local spec = self.spec_AdvancedDamageSystem
    if isActive then
        spec.fieldInspectionActivePlayers[player] = g_time + ADS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    else
        spec.fieldInspectionActivePlayers[player] = nil
    end

    updateFieldInspectionSoundActive(self, spec)
end

function ADS_Consumptables:updateFieldInspectionSound()
    local spec = self.spec_AdvancedDamageSystem

    if self.isServer then
        for player, endTime in pairs(spec.fieldInspectionActivePlayers) do
            if endTime <= g_time then
                spec.fieldInspectionActivePlayers[player] = nil
            end
        end
        updateFieldInspectionSoundActive(self, spec)
    end

    if self.isClient and spec.samples ~= nil then
        ADS_SoundManager.setSamplePlaying(spec.samples.inspection, not spec.isExcludedVehicle and spec.fieldInspectionSoundActive)
    end
end

-- ==========================================================
--                      ENGINE
-- ==========================================================




-- ==========================================================
--          RADIATOR AND AIR INTAKE CLOGGING
-- ==========================================================

function ADS_Consumptables:updateRadiatorClogging(dt)
    local C = ADS_Config.FIELD_CARE
    local spec = self.spec_AdvancedDamageSystem
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
    local hasDebris = spec.isHarvesting
    local fieldFactor = 0.5
    local dustFactor = hasDust and 1.0 or 0.0
    local debrisFactor = hasDebris and 2.0 or 0.0

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
    dbg.hasDebris = hasDebris
    dbg.totalMultiplier = 0.0

    if lastSpeed > 0.5 and spec.radiatorClogging < dirtLevel then
        if washableSpec == nil then
            return
        end

        local dirtDuration = ((washableSpec.dirtDuration or 0) / 4) * (ADS_Config.CORE.BASE_SERVICE_WEAR * 10)
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

function ADS_Consumptables:updateAirIntakeClogging(dt)
    local C = ADS_Config.FIELD_CARE
    local spec = self.spec_AdvancedDamageSystem
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
    local hasDebris = spec.isHarvesting
    local fieldFactor = 1.0
    local dustFactor = hasDust and 2.0 or 0.0
    local debrisFactor = hasDebris and 1.0 or 0.0

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
    dbg.hasDebris = hasDebris
    dbg.totalMultiplier = 0.0

    if lastSpeed > 0.5 and spec.airIntakeClogging < dirtLevel then
        if washableSpec == nil then
            return
        end
        
        local dirtDuration = ((washableSpec.dirtDuration or 0) / 4) * (ADS_Config.CORE.BASE_SERVICE_WEAR * 10)
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

function ADS_Consumptables:cleanRadiatorAndAirIntake(dt)
    local C = ADS_Config.FIELD_CARE
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then
        return
    end

    local prevRadiatorClogging = tonumber(spec.radiatorClogging) or 0
    local prevAirIntakeClogging = tonumber(spec.airIntakeClogging) or 0
    local cleaningDelta = (C.CLEANING_SPEED / 1000) * dt

    spec.radiatorClogging = math.max(prevRadiatorClogging - cleaningDelta, 0)
    spec.airIntakeClogging = math.max(prevAirIntakeClogging - cleaningDelta, 0)

    --- tutorial message
    if ADS_Config.TUTORIAL_MESSAGES ~= nil and ADS_Config.TUTORIAL_MESSAGES.RAD_OR_INTAKE_CLOGGED ~= nil and not ADS_Config.TUTORIAL_MESSAGES.RAD_OR_INTAKE_CLOGGED then
        ADS_Config.TUTORIAL_MESSAGES.RAD_OR_INTAKE_CLOGGED = true
    end

    if self.isServer then
        raiseFieldcareDirty(self, spec)
    end
end

-- ==========================================================
--                  LUBRICATION
-- ==========================================================

function ADS_Consumptables:updateLubricationLevel(operatingDt, motorState)
    local C = ADS_Config.FIELD_CARE
    local spec = self.spec_AdvancedDamageSystem
    if not spec.isVehicleNeedLubricate then
        return
    end

    local currentGameTime = ADS_Utils.getCurrentGameTime()
    local isMotorRunning = motorState == MotorState.ON
    local periodDuration = ADS_Utils.getCurrentPeriodDuration()
    local completedPeriods = math.floor((currentGameTime - spec.lastLubricationGameTime) / periodDuration)

    if completedPeriods > 0 then
        spec.lubricationLevel = math.max(
            spec.lubricationLevel - completedPeriods * C.LUBRICATION_REDUCE_PER_PERIOD,
            0
        )
        spec.lastLubricationGameTime = spec.lastLubricationGameTime + completedPeriods * periodDuration
    end

    if isMotorRunning then
        spec.lastLubricationGameTime = currentGameTime
    end

    spec.lubricationLevel = math.max(
        spec.lubricationLevel - C.LUBRICATION_REDUCE_PER_OPERATING_HOUR * operatingDt / (60 * 60 * 1000),
        0
    )
end

function ADS_Consumptables:lubricateVehicle()
    local C = ADS_Config.FIELD_CARE
    local spec = self.spec_AdvancedDamageSystem

    spec.lubricationLevel = math.min(spec.lubricationLevel + C.LUBRICATION_RESTORE_PER_USE, 1.0)
    spec.lastLubricationGameTime = ADS_Utils.getCurrentGameTime()

    --- tutorial message
    if ADS_Config.TUTORIAL_MESSAGES ~= nil and ADS_Config.TUTORIAL_MESSAGES.NEEDS_LUBRICATION ~= nil and not ADS_Config.TUTORIAL_MESSAGES.NEEDS_LUBRICATION then
        ADS_Config.TUTORIAL_MESSAGES.NEEDS_LUBRICATION = true
    end

    if self.isServer then
        raiseFieldcareDirty(self, spec)
    end
end

function ADS_Consumptables:startFieldVisualInspectionProcess()
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil or spec.isExcludedVehicle then
        return false
    end

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        if self.isClient and g_currentMission ~= nil then
            g_currentMission:showBlinkingWarning(g_i18n:getText("ads_field_inspection_engine_must_be_stopped"), 2200)
        end
        return false
    end

    if self:getCurrentStatus() ~= AdvancedDamageSystem.STATUS.READY then
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
    inspection.duration = ADS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    inspection.startTime = g_time
    inspection.targetVehicle = self

    local node = self.rootNode
    if (node == nil or node == 0) and self.components ~= nil and self.components[1] ~= nil then
        node = self.components[1].node
    end
    inspection.targetNode = node

    ADS_FieldInspectionEvent.send(self, true)

    if self.isClient and ADS_Hud ~= nil then
        ADS_Hud.showNotification(string.format(g_i18n:getText("ads_field_inspection_progress"), 0), inspection.duration)
    end

    return true
end
