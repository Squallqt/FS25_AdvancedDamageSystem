local getSyncOperatingTime = AdvancedDamageSystem.getSyncOperatingTime

-- ============================================================
--                         NETWORK STREAMS
-- ============================================================

function AdvancedDamageSystem:onWriteStream(streamId, connection)
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then return end

    if spec.adsPendingByConnection ~= nil then
        spec.adsPendingByConnection[connection] = 0
    end

    if streamWriteBool(streamId, spec.isExcludedByUser ~= nil) then
        streamWriteBool(streamId, spec.isExcludedByUser)
    end
    streamWriteBool(streamId, spec.isExcludedVehicle == true)
    if spec.isExcludedVehicle then return end

    -- [Group 1] State
    streamWriteString(streamId, spec.currentState or "")
    streamWriteString(streamId, spec.plannedState or "")
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.maintenanceTimer, 0, 0))
    streamWriteBool(streamId, spec.startButtonHeld)

    -- [Group 2] Service context
    streamWriteString(streamId, spec.serviceOptionOne or "")
    streamWriteString(streamId, spec.serviceOptionTwo or "")
    streamWriteBool(streamId, spec.serviceOptionThree or false)
    streamWriteString(streamId, spec.workshopType or "")

    -- [Group 3] Telemetry
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(getSyncOperatingTime(self), 0, 0))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.realOperatingTime, getSyncOperatingTime(self), 0))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec._fuelUsageRaw, 0, 0, 10000))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.dynamicMotorLoad, 0, 0, 1.5))

    -- [Group 4] Thermal
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.rawEngineTemperature, 20, -80, 160))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.rawTransmissionTemperature, 20, -80, 180))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.thermostatState, 0, 0, 1))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.transmissionThermostatState, 0, 0, 1))

    -- [Group 5] Electrical
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.batterySoc, 1.0, 0, 1))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.batteryChargeAh, 0, 0, 10000))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.batteryTerminalVoltageV, 12.7, 0, 30))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.systemVoltageV, 12.7, 0, 30))
    streamWriteUInt8(streamId, math.floor(AdvancedDamageSystem.sanitizeNumber(spec.preheatState, ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.FAILED)))
    streamWriteBool(streamId, spec.preheatLampTestActive == true)
    streamWriteBool(streamId, spec.preheatWasRequired == true)
    streamWriteUInt8(streamId, math.floor(AdvancedDamageSystem.sanitizeNumber(spec.preheatColdStartFaultSeverity, 0, 0, 4)))

    -- [Group 6] Field care
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.radiatorClogging, 0, 0))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.airIntakeClogging, 0, 0))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.lubricationLevel, 1.0, 0.0, 1.0))
    streamWriteBool(streamId, spec.fieldInspectionSoundActive)

    -- [Group 7] Wear
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.serviceLevel, 1.0, 0.001))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.conditionLevel, 1.0, 0.001, 1.0))
    streamWriteString(streamId, ADS_Utils.serializeSystemsState(spec.systems))

    -- [Group 8] Breakdowns
    streamWriteString(streamId, ADS_Utils.serializeBreakdowns(spec.activeBreakdowns or {}))

    -- [Group 9] Service progress
    streamWriteInt32(streamId, spec.pendingProgressStepIndex or 0)
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.pendingProgressTotalTime, 0, 0))
    streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.pendingProgressElapsedTime, 0, 0))

    -- [Group 10] Maintenance log (variable-length: count + entries)
    local logCount = spec.maintenanceLog and #spec.maintenanceLog or 0
    streamWriteUInt16(streamId, logCount)
    for i = 1, logCount do
        local entry = spec.maintenanceLog[i]
        streamWriteString(streamId, ADS_Utils.serializeMaintenanceLogEntry(entry))
    end

    -- [Group 11] Drivetrain
    ADS_Drivetrain.writeStreamState(self, streamId)

end

function AdvancedDamageSystem:onReadStream(streamId, connection)
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then return end

    spec.isExcludedByUser = nil
    if streamReadBool(streamId) then
        spec.isExcludedByUser = streamReadBool(streamId)
    end
    spec.isExcludedVehicle = streamReadBool(streamId)
    if spec.isExcludedVehicle then return end
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0

    -- [Group 1] State
    spec.currentState = streamReadString(streamId)
    spec.plannedState = streamReadString(streamId)
    spec.maintenanceTimer = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
    spec.startButtonHeld = streamReadBool(streamId)

    -- [Group 2] Service context
    spec.serviceOptionOne = streamReadString(streamId)
    spec.serviceOptionTwo = streamReadString(streamId)
    spec.serviceOptionThree = streamReadBool(streamId)
    spec.workshopType = streamReadString(streamId)
    if spec.serviceOptionOne == "" then spec.serviceOptionOne = nil end
    if spec.serviceOptionTwo == "" then spec.serviceOptionTwo = nil end
    if spec.workshopType == "" then spec.workshopType = nil end

    -- [Group 3] Telemetry
    self:setOperatingTime(AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), currentOperatingTime, 0), true)
    spec.realOperatingTime = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), currentOperatingTime, 0)
    if (spec.realOperatingTime == nil or spec.realOperatingTime <= 0) and currentOperatingTime > 0 then
        spec.realOperatingTime = currentOperatingTime
    end
    local syncFuelRaw = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 10000)
    spec._fuelUsageRaw = syncFuelRaw
    spec._netDynamicMotorLoad = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1.5)
    spec.dynamicMotorLoad = spec._netDynamicMotorLoad
    if not self.isServer and self.spec_motorized ~= nil then
        self.spec_motorized.lastFuelUsage = syncFuelRaw
    end

    -- [Group 4] Thermal
    local syncRawEngTemp = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 20, -80, 160)
    local syncRawTransTemp = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), syncRawEngTemp, -80, 180)
    spec.rawEngineTemperature = syncRawEngTemp
    spec.rawTransmissionTemperature = syncRawTransTemp
    spec._netTargetEngineTemp = syncRawEngTemp
    spec._netTargetTransmissionTemp = syncRawTransTemp
    spec.engineTemperature = syncRawEngTemp
    spec.transmissionTemperature = syncRawTransTemp
    spec.thermostatState = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1)
    if spec.engTermPID ~= nil then
        spec.engTermPID.mechPos = spec.thermostatState
    end
    spec.transmissionThermostatState = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1)
    if spec.transTermPID ~= nil then
        spec.transTermPID.mechPos = spec.transmissionThermostatState
    end

    -- [Group 5] Electrical
    spec.batterySoc = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0, 1)
    spec.batteryChargeAh = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 10000)
    spec.batteryTerminalVoltageV = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 12.7, 0, 30)
    spec.rawBatteryTerminalVoltageV = spec.batteryTerminalVoltageV
    spec.systemVoltageV = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), spec.batteryTerminalVoltageV, 0, 30)
    spec.rawSystemVoltageV = spec.systemVoltageV
    spec.preheatState = math.floor(AdvancedDamageSystem.sanitizeNumber(streamReadUInt8(streamId), ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.FAILED))
    spec.preheatLampTestActive = streamReadBool(streamId)
    spec.preheatWasRequired = streamReadBool(streamId)
    spec.preheatColdStartFaultSeverity = math.floor(AdvancedDamageSystem.sanitizeNumber(streamReadUInt8(streamId), 0, 0, 4))

    -- [Group 6] Field care
    spec.radiatorClogging = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
    spec.airIntakeClogging = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
    spec.lubricationLevel = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0.0, 1.0)
    spec.fieldInspectionSoundActive = streamReadBool(streamId)

    -- [Group 7] Wear
    spec.serviceLevel = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0.001)
    spec.conditionLevel = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0.001, 1.0)
    local loadedSystems = ADS_Utils.deserializeSystemsState(streamReadString(streamId))
    for sysKey, sysData in pairs(loadedSystems) do
        if spec.systems[sysKey] ~= nil then
            spec.systems[sysKey].condition = sysData.condition
            spec.systems[sysKey].stress = sysData.stress
            spec.systems[sysKey].enabled = sysData.enabled
        end
    end

    -- [Group 8] Breakdowns
    spec.activeBreakdowns = ADS_Utils.deserializeBreakdowns(streamReadString(streamId))

    -- [Group 9] Service progress
    spec.pendingProgressStepIndex = streamReadInt32(streamId)
    spec.pendingProgressTotalTime = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
    spec.pendingProgressElapsedTime = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)

    -- [Group 10] Maintenance log (variable-length)
    local logCount = streamReadUInt16(streamId)
    spec.maintenanceLog = {}
    for i = 1, logCount do
        local entry = ADS_Utils.deserializeMaintenanceLogEntry(streamReadString(streamId))
        if entry ~= nil then
            table.insert(spec.maintenanceLog, entry)
        end
    end

    -- [Group 11] Drivetrain
    ADS_Drivetrain.readStreamState(self, streamId)

    self:recalculateAndApplyEffects()
    self:recalculateAndApplyIndicators()
end

function AdvancedDamageSystem:onWriteUpdateStream(streamId, connection, dirtyMask)
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then return end

    if not connection:getIsServer() then
        local pending = spec.adsPendingByConnection[connection] or 0
        spec.adsPendingByConnection[connection] = 0

        -- [1] State
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.STATE) ~= 0) then
            streamWriteString(streamId, spec.currentState or "")
            streamWriteString(streamId, spec.plannedState or "")
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.maintenanceTimer, 0, 0))
        end

        -- [2] Service context
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.SERVICE_CONTEXT) ~= 0) then
            streamWriteString(streamId, spec.serviceOptionOne or "")
            streamWriteString(streamId, spec.serviceOptionTwo or "")
            streamWriteBool(streamId, spec.serviceOptionThree or false)
            streamWriteString(streamId, spec.workshopType or "")
        end

        -- [3] Telemetry
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.TELEMETRY) ~= 0) then
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(getSyncOperatingTime(self), 0, 0))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.realOperatingTime, 0, 0))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec._fuelUsageRaw, 0, 0, 10000))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.dynamicMotorLoad, 0, 0, 1.5))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.wheelSlipIntensity, 0, 0, 1))
        end

        -- [4] Thermal
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.THERMAL) ~= 0) then
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.rawEngineTemperature, 20, -80, 160))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.rawTransmissionTemperature, 20, -80, 180))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.thermostatState, 0, 0, 1))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.transmissionThermostatState, 0, 0, 1))
        end

        -- [5] Electrical
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.ELECTRICAL) ~= 0) then
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.batterySoc, 1.0, 0, 1))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.batteryChargeAh, 0, 0, 10000))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.batteryTerminalVoltageV, 12.7, 0, 30))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.systemVoltageV, 12.7, 0, 30))
            streamWriteUInt8(streamId, math.floor(AdvancedDamageSystem.sanitizeNumber(spec.preheatState, ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.FAILED)))
            streamWriteBool(streamId, spec.preheatLampTestActive == true)
            streamWriteBool(streamId, spec.preheatWasRequired == true)
            streamWriteUInt8(streamId, math.floor(AdvancedDamageSystem.sanitizeNumber(spec.preheatColdStartFaultSeverity, 0, 0, 4)))
        end

        -- [6] Field care
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.FIELDCARE) ~= 0) then
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.radiatorClogging, 0, 0))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.airIntakeClogging, 0, 0))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.lubricationLevel, 1.0, 0.0, 1.0))
            streamWriteBool(streamId, spec.fieldInspectionSoundActive)
        end

        -- [7] Wear
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.WEAR) ~= 0) then
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.serviceLevel, 1.0, 0.001))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.conditionLevel, 1.0, 0.001, 1.0))
            streamWriteString(streamId, ADS_Utils.serializeSystemsState(spec.systems))
        end

        -- [8] Breakdowns
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.BREAKDOWNS) ~= 0) then
            streamWriteString(streamId, ADS_Utils.serializeBreakdowns(spec.activeBreakdowns or {}))
        end

        -- [9] Service progress
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.SERVICE_PROGRESS) ~= 0) then
            streamWriteInt32(streamId, spec.pendingProgressStepIndex or 0)
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.pendingProgressTotalTime, 0, 0))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.pendingProgressElapsedTime, 0, 0))
        end

        -- [11] Drivetrain
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.DRIVETRAIN) ~= 0) then
            ADS_Drivetrain.writeStreamState(self, streamId)
        end

        -- [10] Tutorial data (MP clients only)
        if streamWriteBool(streamId, bit32.band(pending, AdvancedDamageSystem.SYNC_GROUP.TUTORIAL_DATA) ~= 0) then
            local fuelState = spec.fuelState
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(fuelState.idleTimer, 0, 0, 600))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(fuelState.level, 0, 0, 1))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.luggingTutorialTimer, 0, 0, 5000))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.wheelSlipTutorialTimer, 0, 0, 3000))
            local brakeState = spec.chassisBrakeState
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(brakeState.hpTrailerMassRatio, 1000, 0, 10000))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(brakeState.trailerMass, 0, 0))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(brakeState.hpGrossMassRatio, 1000, 0, 10000))
            local steerState = spec.chassisSteerState
            streamWriteBool(streamId, steerState.groundContact > 0)
            streamWriteBool(streamId, steerState.isMoving == true)
            streamWriteBool(streamId, spec.isCranking == true)
            local elecSys = spec.systems ~= nil and spec.systems.electrical or nil
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(elecSys ~= nil and elecSys.crankingTimer or 0, 0, 0, 10000))
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.liftedMass, 0, 0))
            streamWriteBool(streamId, spec.isPtoActive == true)
            streamWriteBool(streamId, spec.hasConnectedPto == true)
            streamWriteBool(streamId, spec.ptoConnectionIsTrailerHitch == true)
            streamWriteFloat32(streamId, AdvancedDamageSystem.sanitizeNumber(spec.maxConnectedPtoAngleDeg, 0, 0, 180))
        end
    end
end

function AdvancedDamageSystem:onReadUpdateStream(streamId, timestamp, connection)
    local spec = self.spec_AdvancedDamageSystem
    if spec == nil then return end
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0

    if connection:getIsServer() then
        -- [1] State
        if streamReadBool(streamId) then
            spec.currentState = streamReadString(streamId)
            spec.plannedState = streamReadString(streamId)
            spec.maintenanceTimer = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
        end

        -- [2] Service context
        if streamReadBool(streamId) then
            spec.serviceOptionOne = streamReadString(streamId)
            spec.serviceOptionTwo = streamReadString(streamId)
            spec.serviceOptionThree = streamReadBool(streamId)
            spec.workshopType = streamReadString(streamId)
            if spec.serviceOptionOne == "" then spec.serviceOptionOne = nil end
            if spec.serviceOptionTwo == "" then spec.serviceOptionTwo = nil end
            if spec.workshopType == "" then spec.workshopType = nil end
        end

        -- [3] Telemetry
        if streamReadBool(streamId) then
            self:setOperatingTime(AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), currentOperatingTime, 0), true)
            spec.realOperatingTime = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), currentOperatingTime, 0)
            if (spec.realOperatingTime == nil or spec.realOperatingTime <= 0) and currentOperatingTime > 0 then
                spec.realOperatingTime = currentOperatingTime
            end
            spec._fuelUsageRaw = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 10000)
            spec._netDynamicMotorLoad = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1.5)
            spec.dynamicMotorLoad = spec._netDynamicMotorLoad
            spec.wheelSlipIntensity = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1)
        end

        -- [4] Thermal
        if streamReadBool(streamId) then
            local syncRawEngTemp = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 20, -80, 160)
            local syncRawTransTemp = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), syncRawEngTemp, -80, 180)
            spec.rawEngineTemperature = syncRawEngTemp
            spec.rawTransmissionTemperature = syncRawTransTemp
            spec._netTargetEngineTemp = syncRawEngTemp
            spec._netTargetTransmissionTemp = syncRawTransTemp
            spec.thermostatState = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1)
            if spec.engTermPID ~= nil then
                spec.engTermPID.mechPos = spec.thermostatState
            end
            spec.transmissionThermostatState = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1)
            if spec.transTermPID ~= nil then
                spec.transTermPID.mechPos = spec.transmissionThermostatState
            end
        end

        -- [5] Electrical
        if streamReadBool(streamId) then
            spec.batterySoc = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0, 1)
            spec.batteryChargeAh = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 10000)
            spec.batteryTerminalVoltageV = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 12.7, 0, 30)
            spec.rawBatteryTerminalVoltageV = spec.batteryTerminalVoltageV
            spec.systemVoltageV = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), spec.batteryTerminalVoltageV, 0, 30)
            spec.rawSystemVoltageV = spec.systemVoltageV
            spec.preheatState = math.floor(AdvancedDamageSystem.sanitizeNumber(streamReadUInt8(streamId), ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.IDLE, ADS_Preheat.STATE.FAILED))
            spec.preheatLampTestActive = streamReadBool(streamId)
            spec.preheatWasRequired = streamReadBool(streamId)
            spec.preheatColdStartFaultSeverity = math.floor(AdvancedDamageSystem.sanitizeNumber(streamReadUInt8(streamId), 0, 0, 4))
        end

        -- [6] Field care
        if streamReadBool(streamId) then
            spec.radiatorClogging = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
            spec.airIntakeClogging = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
            spec.lubricationLevel = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0.0, 1.0)
            spec.fieldInspectionSoundActive = streamReadBool(streamId)
        end

        -- [7] Wear
        if streamReadBool(streamId) then
            spec.serviceLevel = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0.001)
            spec.conditionLevel = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1.0, 0.001, 1.0)
            local loadedSystems = ADS_Utils.deserializeSystemsState(streamReadString(streamId))
            for sysKey, sysData in pairs(loadedSystems) do
                if spec.systems[sysKey] ~= nil then
                    spec.systems[sysKey].condition = sysData.condition
                    spec.systems[sysKey].stress = sysData.stress
                    spec.systems[sysKey].enabled = sysData.enabled
                end
            end
        end

        -- [8] Breakdowns
        if streamReadBool(streamId) then
            spec.activeBreakdowns = ADS_Utils.deserializeBreakdowns(streamReadString(streamId))
            self:recalculateAndApplyEffects()
            self:recalculateAndApplyIndicators()
        end

        -- [9] Service progress
        if streamReadBool(streamId) then
            spec.pendingProgressStepIndex = streamReadInt32(streamId)
            spec.pendingProgressTotalTime = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
            spec.pendingProgressElapsedTime = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
        end

        -- [11] Drivetrain
        if streamReadBool(streamId) then
            ADS_Drivetrain.readStreamState(self, streamId)
        end

        -- [10] Tutorial data (MP clients only)
        if streamReadBool(streamId) then
            local fuelState = spec.fuelState
            fuelState.idleTimer = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 600)
            fuelState.level     = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 1)
            spec.luggingTutorialTimer   = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 5000)
            spec.wheelSlipTutorialTimer = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 3000)
            local brakeState = spec.chassisBrakeState
            brakeState.hpTrailerMassRatio = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1000, 0, 10000)
            brakeState.trailerMass = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
            brakeState.hpGrossMassRatio = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 1000, 0, 10000)
            local steerState = spec.chassisSteerState
            steerState.groundContact = streamReadBool(streamId) and 1 or 0
            steerState.isMoving      = streamReadBool(streamId)
            spec.isCranking          = streamReadBool(streamId)
            local elecSys = spec.systems ~= nil and spec.systems.electrical or nil
            local crankingTimer = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 10000)
            if elecSys ~= nil then
                elecSys.crankingTimer = crankingTimer
            end
            spec.liftedMass           = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
            spec.isPtoActive          = streamReadBool(streamId)
            spec.hasConnectedPto      = streamReadBool(streamId)
            spec.ptoConnectionIsTrailerHitch = streamReadBool(streamId)
            spec.maxConnectedPtoAngleDeg = AdvancedDamageSystem.sanitizeNumber(streamReadFloat32(streamId), 0, 0, 180)
        end
    end
end
