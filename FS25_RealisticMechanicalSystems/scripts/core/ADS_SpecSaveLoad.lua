local log_dbg = ADS_Utils.createLogger("[ADS_SPEC]")
local getIsElectricVehicle = ADS_Utils.getIsElectricVehicle
local ensureFactorStats = AdvancedDamageSystem.ensureFactorStats
local refreshExclusionState = AdvancedDamageSystem.refreshExclusionState
local getSyncOperatingTime = AdvancedDamageSystem.getSyncOperatingTime
local captureSystemsSync = AdvancedDamageSystem.captureSystemsSync

-- ==========================================================
--                      HELPER FUNCTIONS
-- ==========================================================

local PTO_SHARP_ANGLE_EXCLUDED_TYPES = {
    combineDrivable = true,
    combineCutter = true,
    combineCutterFruitPreparer = true,
    cottonHarvester = true,
    riceHarvester = true,
    vineHarvester = true,
    balerDrivable = true,
    selfPropelledMower = true,
    woodHarvester = true,
    ricePlanter = true
}

local function createEmptyFactorStats(systems)
    local result = {}
    if type(systems) ~= "table" then
        return result
    end

    for systemKey, _ in pairs(systems) do
        result[systemKey] = {
            total = 0,
            stress = 0,
            _prevStress = 0,
            _avgStress = 0,
            operatingHours = -1
        }
    end

    return result
end

local function flattenFactorStats(factorStats)
    local flat = {}
    if type(factorStats) ~= "table" then
        return flat
    end

    for systemKey, stats in pairs(factorStats) do
        if type(stats) == "table" then
            for statKey, statValue in pairs(stats) do
                local numericValue = tonumber(statValue)
                if numericValue ~= nil then
                    flat[string.format("%s.%s", tostring(systemKey), tostring(statKey))] = numericValue
                end
            end
        end
    end

    return flat
end

local function applyFlattenedFactorStats(spec, flattenedMap)
    if spec == nil then
        return
    end

    if type(spec.factorStats) ~= "table" then
        spec.factorStats = {}
    end

    if type(flattenedMap) ~= "table" then
        return
    end

    for flatKey, value in pairs(flattenedMap) do
        local systemKey, statKey = string.match(tostring(flatKey), "([^%.]+)%.(.+)")
        local numericValue = tonumber(value)
        if systemKey ~= nil and statKey ~= nil and numericValue ~= nil then
            if type(spec.factorStats[systemKey]) ~= "table" then
                spec.factorStats[systemKey] = {}
            end
            spec.factorStats[systemKey][statKey] = numericValue
        end
    end
end

local function getIsUnsupportedVehicle(vehicle)
    return getIsElectricVehicle(vehicle)
end

local function getIsAuxiliaryMachine(vehicle)
    return not vehicle:getIsTabbable()
end

local function getIsVehicleNeedLubricate(vehicle)
    if vehicle == nil then
        return false
    end

    local vtype = vehicle.type ~= nil and vehicle.type.name or ""
    if vtype == "car" or vtype == "carFillable" or vtype == "motorbike" then
        return false
    end

    return not ADS_Drivetrain.getIsRoadVehicleCategory(vehicle)
end

local function getIsTruck(vehicle)
    if vehicle == nil or g_storeManager == nil or vehicle.configFileName == nil then
        return false
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local categoryName = storeItem ~= nil and tostring(storeItem.categoryName or "") or ""
    return string.upper(categoryName) == "TRUCKS"
end

local function getIsVehicleNeedBlowOut(vehicle)
    local vtype = vehicle.type ~= nil and vehicle.type.name or ""

    if getIsTruck(vehicle) or vtype == "car" or vtype == "carFillable" or vtype == "motorbike" then
        return false
    end

    return true
end

-- ============================================================
--                       SAVE & LOAD
-- ============================================================

function AdvancedDamageSystem:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_AdvancedDamageSystem
    if spec ~= nil and not spec.isExcludedByDefault then
        if spec.isExcludedByUser ~= nil then
            xmlFile:setValue(key .. "#userExclusion", spec.isExcludedByUser)
        end
        local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
        local realOperatingTime = spec.realOperatingTime
        if (realOperatingTime == nil or realOperatingTime <= 0) and currentOperatingTime > 0 then
            realOperatingTime = currentOperatingTime
            spec.realOperatingTime = realOperatingTime
        end
        xmlFile:setValue(key .. "#service", spec.serviceLevel or 1.0)
        xmlFile:setValue(key .. "#condition", spec.conditionLevel or 1.0)
        xmlFile:setValue(key .. "#realOperatingTime", realOperatingTime or currentOperatingTime)
        if xmlFile.handle ~= nil then
            setXMLFloat(xmlFile.handle, key .. "#realOperatingTime", tonumber(realOperatingTime or currentOperatingTime) or 0)
        end
        local breakdownString = ADS_Utils.serializeBreakdowns(spec.activeBreakdowns)
        xmlFile:setValue(key .. "#breakdowns", breakdownString)
        xmlFile:setValue(key .. "#state", spec.currentState or AdvancedDamageSystem.STATUS.READY)
        xmlFile:setValue(key .. "#plannedState", spec.plannedState or AdvancedDamageSystem.STATUS.READY)
        xmlFile:setValue(key .. "#maintenanceTimer", AdvancedDamageSystem.sanitizeNumber(spec.maintenanceTimer, 0, 0))
        xmlFile:setValue(key .. "#engineTemperature", AdvancedDamageSystem.sanitizeNumber(spec.engineTemperature, 20, -80, 160))
        xmlFile:setValue(key .. "#transmissionTemperature", AdvancedDamageSystem.sanitizeNumber(spec.transmissionTemperature, 20, -80, 180))
        xmlFile:setValue(key .. "#batterySoc", AdvancedDamageSystem.sanitizeNumber(spec.batterySoc, 1.0, 0, 1))
        xmlFile:setValue(key .. "#batteryChargeAh", AdvancedDamageSystem.sanitizeNumber(spec.batteryChargeAh, 0, 0, 10000))
        xmlFile:setValue(key .. "#batteryTempC", AdvancedDamageSystem.sanitizeNumber(spec.batteryTempC, 20, -80, 85))
        xmlFile:setValue(key .. "#radiatorClogging", math.max(spec.radiatorClogging or 0, 0))
        xmlFile:setValue(key .. "#airIntakeClogging", math.max(spec.airIntakeClogging or 0, 0))
        xmlFile:setValue(key .. "#lubricationLevel", math.clamp(spec.lubricationLevel or 1.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#lubricationUsedThisPeriod", spec.lubricationUsedThisPeriod == true)
        xmlFile:setValue(key .. "#thermostatState", AdvancedDamageSystem.sanitizeNumber(spec.thermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#transmissionThermostatState", AdvancedDamageSystem.sanitizeNumber(spec.transmissionThermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#serviceOptionOne", spec.serviceOptionOne or "")
        xmlFile:setValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo or "")
        xmlFile:setValue(key .. "#serviceOptionThree", spec.serviceOptionThree or false)
        xmlFile:setValue(key .. "#workshopType", spec.workshopType or "")
        xmlFile:setValue(key .. "#pendingSelectedBreakdowns", table.concat(spec.pendingSelectedBreakdowns or {}, ","))
        xmlFile:setValue(key .. "#pendingServicePrice", ADS_Utils.encodeOptionalFloat(spec.pendingServicePrice))
        xmlFile:setValue(key .. "#pendingInspectionQueue", table.concat(spec.pendingInspectionQueue or {}, ","))
        xmlFile:setValue(key .. "#pendingRepairQueue", table.concat(spec.pendingRepairQueue or {}, ","))
        xmlFile:setValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex or 0)
        xmlFile:setValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime or 0)
        xmlFile:setValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime or 0)
        xmlFile:setValue(key .. "#pendingMaintenanceServiceStart", ADS_Utils.encodeOptionalFloat(spec.pendingMaintenanceServiceStart))
        xmlFile:setValue(key .. "#pendingMaintenanceServiceTarget", ADS_Utils.encodeOptionalFloat(spec.pendingMaintenanceServiceTarget))
        xmlFile:setValue(key .. "#pendingPreventiveSystemStressStart", ADS_Utils.serializeNumericMap(spec.pendingPreventiveSystemStressStart))
        xmlFile:setValue(key .. "#pendingPreventiveSystemStressTarget", ADS_Utils.serializeNumericMap(spec.pendingPreventiveSystemStressTarget))
        xmlFile:setValue(key .. "#systemsState", ADS_Utils.serializeSystemsState(spec.systems))
        xmlFile:setValue(key .. "#factorStats", ADS_Utils.serializeNumericMap(flattenFactorStats(spec.factorStats)))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStart", ADS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStart))
        xmlFile:setValue(key .. "#pendingOverhaulSystemTarget", ADS_Utils.serializeNumericMap(spec.pendingOverhaulSystemTarget))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStressStart", ADS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStressStart))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStressTarget", ADS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStressTarget))
        xmlFile:setValue(key .. "#pendingRepairSystemStressStart", ADS_Utils.serializeNumericMap(spec.pendingRepairSystemStressStart))
        xmlFile:setValue(key .. "#pendingRepairSystemStressTarget", ADS_Utils.serializeNumericMap(spec.pendingRepairSystemStressTarget))
        xmlFile:setValue(key .. "#pendingRepairSystemStressStartRatio", ADS_Utils.serializeNumericMap(spec.pendingRepairSystemStressStartRatio))

        ADS_Drivetrain.saveToXMLFile(self, xmlFile, key)

        if spec.maintenanceLog and #spec.maintenanceLog > 0 then
            for i, entry in ipairs(spec.maintenanceLog) do
                local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, i - 1)
                
                xmlFile:setValue(entryKey .. "#id", entry.id or 0)
                xmlFile:setValue(entryKey .. "#type", entry.type or "")
                xmlFile:setValue(entryKey .. "#price", entry.price or 0)
                xmlFile:setValue(entryKey .. "#date", ADS_Utils.serializeDate(entry.date)) 
                xmlFile:setValue(entryKey .. "#location", entry.location or "UNKNOWN")
                xmlFile:setValue(entryKey .. "#optionOne", entry.optionOne or "NONE")
                xmlFile:setValue(entryKey .. "#optionTwo", entry.optionTwo or "NONE")
                xmlFile:setValue(entryKey .. "#optionThree", entry.optionThree or false)
                xmlFile:setValue(entryKey .. "#isVisible", tostring(ADS_Utils.normalizeBoolValue(entry.isVisible, true)))
                xmlFile:setValue(entryKey .. "#isCompleted", ADS_Utils.normalizeBoolValue(entry.isCompleted, true))

                if entry.conditionData then
                    local condKey = entryKey .. ".conditionData"
                    xmlFile:setValue(condKey .. "#year", entry.conditionData.year or 0)
                    xmlFile:setValue(condKey .. "#operatingHours", entry.conditionData.operatingHours or 0)
                    xmlFile:setValue(condKey .. "#age", entry.conditionData.age or 0)
                    xmlFile:setValue(condKey .. "#condition", entry.conditionData.condition or 1)
                    xmlFile:setValue(condKey .. "#service", entry.conditionData.service or 1)
                    xmlFile:setValue(condKey .. "#reliability", entry.conditionData.reliability or 1)
                    xmlFile:setValue(condKey .. "#maintainability", entry.conditionData.maintainability or 1)
                    xmlFile:setValue(condKey .. "#systems", ADS_Utils.serializeSystemsState(ADS_Utils.createSystemsSnapshot(entry.conditionData.systems)))
                    xmlFile:setValue(condKey .. "#batterySoc", entry.conditionData.batterySoc or 1)

                    if entry.conditionData.activeBreakdowns then
                        xmlFile:setValue(condKey .. "#activeBreakdowns", ADS_Utils.serializeBreakdowns(entry.conditionData.activeBreakdowns))
                    end
                    
                    if entry.conditionData.selectedBreakdowns and #entry.conditionData.selectedBreakdowns > 0 then
                        xmlFile:setValue(condKey .. "#selectedBreakdowns", table.concat(entry.conditionData.selectedBreakdowns, ","))
                    end
                    
                    if entry.conditionData.activeEffects then
                        xmlFile:setValue(condKey .. "#activeEffects", ADS_Utils.serializeEffectSnapshot(entry.conditionData.activeEffects))
                    end
                    
                    if entry.conditionData.activeIndicators then
                        local indKeys = {}
                        for indId, _ in pairs(entry.conditionData.activeIndicators) do 
                            table.insert(indKeys, tostring(indId)) 
                        end
                        xmlFile:setValue(condKey .. "#activeIndicators", table.concat(indKeys, ","))
                    end
                end
            end
        end
        
    end
end

function AdvancedDamageSystem:onLoad(savegame)
    self.spec_AdvancedDamageSystem.isExcludedVehicle = false
    self.spec_AdvancedDamageSystem.isExcludedByDefault = false
    self.spec_AdvancedDamageSystem.isExcludedByRule = false
    self.spec_AdvancedDamageSystem.isExcludedByUser = nil
    self.spec_AdvancedDamageSystem.isElectricVehicle = false
    self.spec_AdvancedDamageSystem.isTruck = getIsTruck(self)
    self.spec_AdvancedDamageSystem.isVehicleNeedLubricate = false
    self.spec_AdvancedDamageSystem.isVehicleNeedBlowOut = false

    self.spec_AdvancedDamageSystem.baseServiceLevel = 1.0
    self.spec_AdvancedDamageSystem.baseConditionLevel = 1.0
    self.spec_AdvancedDamageSystem.serviceLevel = self.spec_AdvancedDamageSystem.baseServiceLevel
    self.spec_AdvancedDamageSystem.conditionLevel = self.spec_AdvancedDamageSystem.baseConditionLevel

    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local existingRealOperatingTime = tonumber(self.spec_AdvancedDamageSystem.realOperatingTime) or 0
    self.spec_AdvancedDamageSystem.realOperatingTime = math.max(existingRealOperatingTime, currentOperatingTime)
    self.spec_AdvancedDamageSystem._prevConditionLevel = 0
    self.spec_AdvancedDamageSystem._allowAdsOperatingTimeWrite = false

    self.spec_AdvancedDamageSystem.systems = {
        engine = { name = AdvancedDamageSystem.SYSTEMS.ENGINE, condition = 1.0, stress = 0.0, enabled = true },
        transmission = { name = AdvancedDamageSystem.SYSTEMS.TRANSMISSION, condition = 1.0, stress = 0.0, enabled = true },
        hydraulics = { name = AdvancedDamageSystem.SYSTEMS.HYDRAULICS, condition = 1.0, stress = 0.0, enabled = true },
        cooling = { name = AdvancedDamageSystem.SYSTEMS.COOLING, condition = 1.0, stress = 0.0, enabled = true },
        electrical = { name = AdvancedDamageSystem.SYSTEMS.ELECTRICAL, condition = 1.0, stress = 0.0, enabled = true },
        chassis = { name = AdvancedDamageSystem.SYSTEMS.CHASSIS, condition = 1.0, stress = 0.0, enabled = true },
        fuel = { name = AdvancedDamageSystem.SYSTEMS.FUEL, condition = 1.0, stress = 0.0, enabled = true }
    }
    self.spec_AdvancedDamageSystem.factorStats = createEmptyFactorStats(self.spec_AdvancedDamageSystem.systems)
    ensureFactorStats(self.spec_AdvancedDamageSystem, self)

    --- engine consumptables
    self.spec_AdvancedDamageSystem.airIntakeClogging = 0.0

    self.spec_AdvancedDamageSystem.extraConditionWear = 0
    self.spec_AdvancedDamageSystem.extraServiceWear = 0
    self.spec_AdvancedDamageSystem.extraEngineHeat = 0
    self.spec_AdvancedDamageSystem.extraTransmissionHeat = 0
    self.spec_AdvancedDamageSystem.extraCurrentPeak = 0
    
    self.spec_AdvancedDamageSystem.reliability = 1.0
    self.spec_AdvancedDamageSystem.maintainability = 1.0
    self.spec_AdvancedDamageSystem.year = ADS_VehicleYears.DEFAULT_YEAR

    self.spec_AdvancedDamageSystem.activeBreakdowns = {}
    self.spec_AdvancedDamageSystem.activeEffects = {}
    self.spec_AdvancedDamageSystem.activeIndicators = {}
    self.spec_AdvancedDamageSystem.activeFunctions = {}
    self.spec_AdvancedDamageSystem.originalFunctions = {}
    self.spec_AdvancedDamageSystem.dynamicBreakdowns = {}

    self.spec_AdvancedDamageSystem.maintenanceLog = {}
    
    self.spec_AdvancedDamageSystem._fuelUsageRaw  = 0
    self.spec_AdvancedDamageSystem.lastBlinkingWarningMessage = ""
    self.spec_AdvancedDamageSystem.blinkingWarningTimer = 0
    self.spec_AdvancedDamageSystem.coldEngineExposureMs = 0
    self.spec_AdvancedDamageSystem.coldEngineWarningShown = false
    self.spec_AdvancedDamageSystem.pendingSideNotifications = {}

    self.spec_AdvancedDamageSystem.startButtonActionEvents = {}
    self.spec_AdvancedDamageSystem.startButtonDown = false
    self.spec_AdvancedDamageSystem.startButtonHeld = false
    self.spec_AdvancedDamageSystem.startButtonUp = false
    ADS_Preheat.initSpec(self)

    self.spec_AdvancedDamageSystem.drivetrainActionEvents = {}
    ADS_Drivetrain.initSpec(self)

    self.spec_AdvancedDamageSystem.radiatorClogging = 0.0
    self.spec_AdvancedDamageSystem.lubricationLevel = 1.0
    self.spec_AdvancedDamageSystem.lubricationUsedThisPeriod = true
    self.spec_AdvancedDamageSystem.fieldInspectionSoundActive = false
    self.spec_AdvancedDamageSystem.fieldInspectionActivePlayers = {}

    self.spec_AdvancedDamageSystem.batterySoc = 1.0
    self.spec_AdvancedDamageSystem.batteryChargeAh = nil
    self.spec_AdvancedDamageSystem.batteryHealth = 1.0
    self.spec_AdvancedDamageSystem.batteryCapacityAh = ADS_Config.ELECTRICAL.BATTERY_NOMINAL_CAPACITY
    self.spec_AdvancedDamageSystem.batteryTempC = 0
    self.spec_AdvancedDamageSystem.batteryOpenCircuitVoltageV = 12.7
    self.spec_AdvancedDamageSystem.rawBatteryTerminalVoltageV = 12.7
    self.spec_AdvancedDamageSystem.batteryTerminalVoltageV = 12.7
    self.spec_AdvancedDamageSystem.rawSystemVoltageV = 12.7
    self.spec_AdvancedDamageSystem.systemVoltageV = 12.7
    self.spec_AdvancedDamageSystem.alternatorHealth = 1.0
    self.spec_AdvancedDamageSystem.iAltAvail = 0
    self.spec_AdvancedDamageSystem.iLoads = 0
    self.spec_AdvancedDamageSystem.externalPowerConnection = nil

    self.spec_AdvancedDamageSystem.engineTemperature = -99
    self.spec_AdvancedDamageSystem.rawEngineTemperature = -99
    self.spec_AdvancedDamageSystem._netTargetEngineTemp = nil
    self.spec_AdvancedDamageSystem._smoothedMotorLoad = 0
    self.spec_AdvancedDamageSystem._netDynamicMotorLoad = 0
    self.spec_AdvancedDamageSystem.radiatorHealth = 1.0
    self.spec_AdvancedDamageSystem.fanClutchHealth = 1.0
    self.spec_AdvancedDamageSystem.thermostatState = 0.0
    self.spec_AdvancedDamageSystem.thermostatHealth = 1.0
    self.spec_AdvancedDamageSystem.thermostatStuckedPosition = nil
    self.spec_AdvancedDamageSystem.engTermPID = {
        integral = 0,
        lastError = 0
    }

    self.spec_AdvancedDamageSystem.transmissionTemperature = -99
    self.spec_AdvancedDamageSystem.rawTransmissionTemperature = -99
    self.spec_AdvancedDamageSystem._netTargetTransmissionTemp = nil
    self.spec_AdvancedDamageSystem.transmissionThermostatState = 0.0
    self.spec_AdvancedDamageSystem.transmissionThermostatHealth = 1.0
    self.spec_AdvancedDamageSystem.transmissionThermostatStuckedPosition = nil
    self.spec_AdvancedDamageSystem.transTermPID = {
        integral = 0,
        lastError = 0
    }
    self.spec_AdvancedDamageSystem.aiWorkerPid = {
        integral = 0,
        lastError = 0,
        filteredStress = 0,
        currentReduction = 0,
        baseCruiseSpeed = nil,
        applyTimer = 0,
        lastAppliedSpeed = nil
    }

    self.spec_AdvancedDamageSystem.debugData = {
        service = {
            totalWearRate = 0
        },
        condition = 0,
        airIntake = {
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
        },
        externalPower = {
            isValidConnection = false,
            distance = 0
        },
        drivetrain = {
        },

        engine = {
            condition = 0,
            stress = 0,
            totalWearRate = 0, 
            expiredServiceFactor = 0,
            motorLoadFactor = 0, 
            coldMotorFactor = 0, 
            hotMotorFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        transmission = {
            condition = 0,
            stress = 0,
            totalWearRate = 0, 
            expiredServiceFactor = 0,
            pullOverloadFactor = 0,
            heavyTrailerFactor = 0,
            heavyTrailerMassRatio = 0,
            wheelSlipFactor = 0,
            luggingFactor = 0,
            coldMotorFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0,
            pullOverloadTimer = 0
        },

        hydraulics = {
            condition = 0,
            stress = 0,
            totalWearRate = 0,
            expiredServiceFactor = 0,
            heavyLiftFactor = 0,
            heavyLiftMassRatio = 0,
            operatingFactor = 0,
            vibFactor = 0,
            vibSignal = 0,
            vibRaw = 0,
            vibFieldMultiplier = 1,
            coldOilFactor = 0,
            sharpAngleFactor = 0,
            ptoSharpAngleDeg = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        cooling = {
            condition = 0,
            stress = 0,
            totalWearRate = 0,
            expiredServiceFactor = 0,
            highCoolingFactor = 0,
            overheatFactor = 0,
            coldShockFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        electrical = {
            condition = 0,
            stress = 0,
            totalWearRate = 0,
            expiredServiceFactor = 0,
            vibFactor = 0,
            vibSignal = 0,
            vibRaw = 0,
            vibFieldMultiplier = 1,
            lightsFactor = 0,
            crankingStressFactor = 0,
            overheatFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        chassis = {
            condition = 0,
            stress = 0,
            totalWearRate = 0,
            expiredServiceFactor = 0,
            vibFactor = 0,
            vibSignal = 0,
            vibRaw = 0,
            vibWheelCount = 0,
            vibSpeedFactor = 0,
            vibSpeedKmh = 0,
            vibAvgDensityType = 0,
            vibFieldMultiplier = 1,
            steerLoadFactor = 0,
            steerLowSpeedFactor = 0,
            steerGroundFrictionCoeff = 0,
            steerGroundFrictionFactor = 0,
            steerGroundContact = 0,
            steerMoving = false,
            brakeMassFactor = 0,
            brakeMassRatio = 0,
            brakePedal = 0,
            parkingBrakeFactor = 0,
            parkingBrakeActive = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        fuel = {
            condition = 0,
            stress = 0,
            totalWearRate = 0,
            expiredServiceFactor = 0,
            lowFuelStarvationFactor = 0,
            coldFuelFactor = 0,
            idleDepositFactor = 0,
            highPressureFactor = 0,
            idleTimer = 0,
            fuelLevel = 0,
            fuelTemperature = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        battery = {
            soc = 1.0,
            iAltAvail = 0,
            iLoads = 0,
            baseLoadA = 0,
            lightsLoadA = 0,
            cabFanA = 0,
            winterHeaterA = 0,
            peakPulseA = 0,
            iNet = 0,
            dAh = 0,
            altFactor = 0
        },

        radiator = {
            fieldFactor = 1.0,
            dustFactor = 0.0,
            debrisFactor = 0.0,
            workFactor = 1.0,
            wetness = 0,
            wetnessFactor = 1.0,
            baseWetnessFactor = 1.0,
            isOnField = false,
            hasDust = false,
            hasDebris = false,
            totalMultiplier = 0.0
        },

        engineTemp = {
            totalHeat = 0, 
            totalCooling = 0, 
            radiatorCooling = 0, 
            speedCooling = 0, 
            convectionCooling = 0,
            stiction = 0,
            waxSpeed = 0,
            kp = 0
        },

        transmissionTemp = {
            totalHeat = 0, 
            totalCooling = 0, 
            radiatorCooling = 0, 
            speedCooling = 0, 
            convectionCooling = 0,
            loadFactor = 0,
            slipFactor = 0,
            pullFactor = 0,
            wheelSlipFactor = 0,
            accFactor = 0,
            speedLimit = 0,
            cvtSlipActive = 0,
            cvtSlipLocked = 0,
            extraTransmissionHeat = 0,
            stiction = 0,
            waxSpeed = 0,
            kp = 0
        },

        aiWorker = {
            stress = 0,
            filteredStress = 0,
            error = 0,
            integral = 0,
            derivative = 0,
            reduction = 0,
            targetSpeed = 0,
            appliedSpeed = 0,
            baseCruiseSpeed = 0,
            loadStress = 0,
            engineStress = 0,
            transStress = 0
        }
    }

    self.spec_AdvancedDamageSystem.isExcludedFromPTOSharpAngleFactor = false
    self.spec_AdvancedDamageSystem.isUnderRoof = true
    self.spec_AdvancedDamageSystem.roofRaycastHit = false
    self.spec_AdvancedDamageSystem.roofRaycastResult = nil
    self.spec_AdvancedDamageSystem.roofLastRaycastTime = nil
    self.spec_AdvancedDamageSystem.roofWasStationary = false
    self.spec_AdvancedDamageSystem.dynamicMotorLoad = 0
    self.spec_AdvancedDamageSystem.avgDynamicMotorLoad = 0
    self.spec_AdvancedDamageSystem.avgSpeed = 0
    self.spec_AdvancedDamageSystem.activeDraftMaxForce = 0
    self.spec_AdvancedDamageSystem.activeDraftEffectiveForceCap = 0
    self.spec_AdvancedDamageSystem.isCranking = false
    self.spec_AdvancedDamageSystem.wheelSlipIntensity = 0
    self.spec_AdvancedDamageSystem._wheelSlipPreviousSample = 0
    self.spec_AdvancedDamageSystem._wheelSlipOlderSample = 0
    self.spec_AdvancedDamageSystem.wheelSlipTutorialTimer = 0
    self.spec_AdvancedDamageSystem.luggingTutorialTimer = 0
    self.spec_AdvancedDamageSystem.avgTireGroundFrictionCoeff = 0
    self.spec_AdvancedDamageSystem.avgGroundSurfaceFactor = 0
    self.spec_AdvancedDamageSystem.implements = {}
    self.spec_AdvancedDamageSystem.isImplementLifted = false
    self.spec_AdvancedDamageSystem.isImplementLowered = false
    self.spec_AdvancedDamageSystem.isImplementOperating = false
    self.spec_AdvancedDamageSystem.liftedMass = 0
    self.spec_AdvancedDamageSystem.operatingMass = 0
    self.spec_AdvancedDamageSystem.isPtoActive = false
    self.spec_AdvancedDamageSystem.maxConnectedPtoAngleDeg = 0
    self.spec_AdvancedDamageSystem.ptoConnectionIsTrailerHitch = false
    self.spec_AdvancedDamageSystem.hasConnectedPto = false
    self.spec_AdvancedDamageSystem.hydraulicsMoveAlphaCache = {}
    self.spec_AdvancedDamageSystem.hydraulicsLiftRatioCache = {}
    self.spec_AdvancedDamageSystem.chassisVibState = {
        prevSuspension = {},
        smoothed = 0,
        raw = 0,
        signal = 0,
        wheelCount = 0,
        speedFactor = 0,
        avgDensityType = 0,
        fieldMultiplier = 1
    }
    self.spec_AdvancedDamageSystem.chassisSteerState = {
        prevPosition = nil,
        position = 0,
        angleMagnitude = 0,
        inputMagnitude = 0,
        deltaRate = 0,
        rateFactor = 0,
        groundContact = 0,
        isLowSpeedActive = false,
        isMoving = false
    }
    self.spec_AdvancedDamageSystem.chassisBrakeState = {
        pedal = 0,
        massRatio = 0,
        trailerMass = 0,
        totalMass = 0,
        hpTrailerMassRatio = 1000,
        hpGrossMassRatio = 1000,
        isBraking = false,
        isBrakingByAxis = false
    }
    self.spec_AdvancedDamageSystem.fuelState = {
        level = 0,
        currentUsageRatio = 0,
        temperature = 0,
        idleTimer = 0
    }
    self.spec_AdvancedDamageSystem.isHarvesting = false

    self.spec_AdvancedDamageSystem.onUpdateTimer = ADS_Config.ON_UPDATE_DELAY
    self.spec_AdvancedDamageSystem.updateVehicleStateTimerOne = ADS_Config.UPDATE_VEHICLE_STATE_DELAY_ONE
    self.spec_AdvancedDamageSystem.updateVehicleStateTimerTwo = ADS_Config.UPDATE_VEHICLE_STATE_DELAY_TWO
    self.spec_AdvancedDamageSystem.updateVehicleStateTimerThree = ADS_Config.UPDATE_VEHICLE_STATE_DELAY_THREE
    self.spec_AdvancedDamageSystem.metaUpdateTimer = math.random() * ADS_Config.META_UPDATE_DELAY
    self.spec_AdvancedDamageSystem.maintenanceTimer = 0
    self.spec_AdvancedDamageSystem.currentState = AdvancedDamageSystem.STATUS.READY
    self.spec_AdvancedDamageSystem.plannedState = AdvancedDamageSystem.STATUS.READY
    self.spec_AdvancedDamageSystem.workshopType = AdvancedDamageSystem.WORKSHOP.DEALER
    self.spec_AdvancedDamageSystem.serviceOptionOne = nil
    self.spec_AdvancedDamageSystem.serviceOptionTwo = nil
    self.spec_AdvancedDamageSystem.serviceOptionThree = false
    self.spec_AdvancedDamageSystem.pendingSelectedBreakdowns = {}
    self.spec_AdvancedDamageSystem.pendingServicePrice = nil
    self.spec_AdvancedDamageSystem.pendingInspectionQueue = {}
    self.spec_AdvancedDamageSystem.pendingRepairQueue = {}
    self.spec_AdvancedDamageSystem.pendingProgressStepIndex = 0
    self.spec_AdvancedDamageSystem.pendingProgressTotalTime = 0
    self.spec_AdvancedDamageSystem.pendingProgressElapsedTime = 0
    self.spec_AdvancedDamageSystem.pendingMaintenanceServiceStart = nil
    self.spec_AdvancedDamageSystem.pendingMaintenanceServiceTarget = nil
    self.spec_AdvancedDamageSystem.pendingPreventiveSystemStressStart = {}
    self.spec_AdvancedDamageSystem.pendingPreventiveSystemStressTarget = {}
    self.spec_AdvancedDamageSystem.pendingOverhaulSystemStart = {}
    self.spec_AdvancedDamageSystem.pendingOverhaulSystemTarget = {}
    self.spec_AdvancedDamageSystem.pendingOverhaulSystemStressStart = {}
    self.spec_AdvancedDamageSystem.pendingOverhaulSystemStressTarget = {}
    self.spec_AdvancedDamageSystem.pendingRepairSystemStressStart = {}
    self.spec_AdvancedDamageSystem.pendingRepairSystemStressTarget = {}
    self.spec_AdvancedDamageSystem.pendingRepairSystemStressStartRatio = {}


    if self.isServer then
        local spec = self.spec_AdvancedDamageSystem
        spec.adsDirtyFlag = self:getNextDirtyFlag()
        spec.adsPendingByConnection = {}
    end
end

function AdvancedDamageSystem:onPostLoad(savegame)
    local spec = self.spec_AdvancedDamageSystem
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0

    spec.isExcludedByDefault = getIsUnsupportedVehicle(self)
    spec.isExcludedByRule = getIsAuxiliaryMachine(self)
    spec.isExcludedByUser = nil
    if savegame ~= nil then
        local exclusionKey = savegame.key .. ".AdvancedDamageSystem#userExclusion"
        spec.isExcludedByUser = savegame.xmlFile:getValue(exclusionKey)
    end
    refreshExclusionState(spec)
    if spec.isExcludedByDefault then return end

    if spec ~= nil and savegame ~= nil then
        local key = savegame.key .. ".AdvancedDamageSystem"

        spec.serviceLevel = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#service", spec.serviceLevel), spec.serviceLevel or 1.0, 0.001)
        spec.conditionLevel = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#condition", spec.conditionLevel), spec.conditionLevel or 1.0, 0.001, 1.0)
        spec.currentState = savegame.xmlFile:getValue(key .. "#state", spec.currentState)
        spec.plannedState = savegame.xmlFile:getValue(key .. "#plannedState", spec.plannedState)
        spec.maintenanceTimer = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#maintenanceTimer", spec.maintenanceTimer), spec.maintenanceTimer or 0, 0)
        
        local loadedRealOperatingTime = nil
        if savegame.xmlFile:hasProperty(key .. "#realOperatingTime") then
            loadedRealOperatingTime = savegame.xmlFile:getValue(key .. "#realOperatingTime")
        end
        if loadedRealOperatingTime == nil and savegame.xmlFile.handle ~= nil then
            loadedRealOperatingTime = getXMLFloat(savegame.xmlFile.handle, key .. "#realOperatingTime")
        end
        if loadedRealOperatingTime ~= nil then
            spec.realOperatingTime = AdvancedDamageSystem.sanitizeNumber(loadedRealOperatingTime, currentOperatingTime, 0)
        else
            spec.realOperatingTime = currentOperatingTime
        end

        -- Load Breakdowns
        local breakdownString = savegame.xmlFile:getValue(key .. "#breakdowns", "")
        if breakdownString and breakdownString ~= "" then
            spec.activeBreakdowns = ADS_Utils.deserializeBreakdowns(breakdownString)
        else
            spec.activeBreakdowns = {}
        end

        -- Load Simple Variables
        spec.engineTemperature = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#engineTemperature", spec.engineTemperature), 20, -80, 160)
        spec.transmissionTemperature = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#transmissionTemperature", spec.transmissionTemperature), spec.engineTemperature, -80, 180)
        spec.batterySoc = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#batterySoc", spec.batterySoc), 1.0, 0, 1)
        local loadedBatteryChargeAh = savegame.xmlFile:getValue(key .. "#batteryChargeAh", spec.batteryChargeAh)
        spec.batteryChargeAh = loadedBatteryChargeAh ~= nil and AdvancedDamageSystem.sanitizeNumber(loadedBatteryChargeAh, 0, 0, 10000) or nil
        spec.batteryTempC = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#batteryTempC", spec.batteryTempC), 20, -80, 85)
        spec.radiatorClogging = math.max(savegame.xmlFile:getValue(key .. "#radiatorClogging", spec.radiatorClogging), 0)
        spec.airIntakeClogging = math.max(savegame.xmlFile:getValue(key .. "#airIntakeClogging", spec.airIntakeClogging), 0)
        spec.lubricationLevel = math.clamp(savegame.xmlFile:getValue(key .. "#lubricationLevel", spec.lubricationLevel), 0.0, 1.0)
        spec.lubricationUsedThisPeriod = savegame.xmlFile:getValue(key .. "#lubricationUsedThisPeriod", true)
        spec.thermostatState = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#thermostatState", spec.thermostatState), spec.thermostatState or 0, 0.0, 1.0)
        spec.transmissionThermostatState = AdvancedDamageSystem.sanitizeNumber(savegame.xmlFile:getValue(key .. "#transmissionThermostatState", spec.transmissionThermostatState), spec.transmissionThermostatState or 0, 0.0, 1.0)
        if spec.engTermPID ~= nil then
            spec.engTermPID.mechPos = spec.thermostatState
        end
        if spec.transTermPID ~= nil then
            spec.transTermPID.mechPos = spec.transmissionThermostatState
        end
        spec.serviceOptionOne = savegame.xmlFile:getValue(key .. "#serviceOptionOne", spec.serviceOptionOne)
        spec.serviceOptionTwo = savegame.xmlFile:getValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo)
        if spec.serviceOptionOne == "" then spec.serviceOptionOne = nil end
        if spec.serviceOptionTwo == "" then spec.serviceOptionTwo = nil end
        spec.serviceOptionThree = savegame.xmlFile:getValue(key .. "#serviceOptionThree", spec.serviceOptionThree)
        ADS_Drivetrain.loadFromSavegame(self, savegame.xmlFile, key)
        local loadedWorkshopType = savegame.xmlFile:getValue(key .. "#workshopType", "")
        if loadedWorkshopType ~= nil and loadedWorkshopType ~= "" then
            spec.workshopType = loadedWorkshopType
        end
        spec.pendingServicePrice = ADS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingServicePrice", spec.pendingServicePrice))
        spec.pendingSelectedBreakdowns = {}
        local pendingSelBdStr = savegame.xmlFile:getValue(key .. "#pendingSelectedBreakdowns", "")
        if pendingSelBdStr ~= nil and pendingSelBdStr ~= "" then
            for item in string.gmatch(pendingSelBdStr, "([^,]+)") do
                table.insert(spec.pendingSelectedBreakdowns, item)
            end
        end
        spec.pendingInspectionQueue = {}
        local pendingInspectionQueueStr = savegame.xmlFile:getValue(key .. "#pendingInspectionQueue", "")
        if pendingInspectionQueueStr ~= nil and pendingInspectionQueueStr ~= "" then
            for item in string.gmatch(pendingInspectionQueueStr, "([^,]+)") do
                table.insert(spec.pendingInspectionQueue, item)
            end
        end

        spec.pendingRepairQueue = {}
        local pendingRepairQueueStr = savegame.xmlFile:getValue(key .. "#pendingRepairQueue", "")
        if pendingRepairQueueStr ~= nil and pendingRepairQueueStr ~= "" then
            for item in string.gmatch(pendingRepairQueueStr, "([^,]+)") do
                table.insert(spec.pendingRepairQueue, item)
            end
        end

        spec.pendingProgressStepIndex = savegame.xmlFile:getValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex)
        spec.pendingProgressTotalTime = savegame.xmlFile:getValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime)
        spec.pendingProgressElapsedTime = savegame.xmlFile:getValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime)
        spec.pendingMaintenanceServiceStart = ADS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingMaintenanceServiceStart", spec.pendingMaintenanceServiceStart))
        spec.pendingMaintenanceServiceTarget = ADS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingMaintenanceServiceTarget", spec.pendingMaintenanceServiceTarget))
        spec.pendingPreventiveSystemStressStart = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingPreventiveSystemStressStart", ""))
        spec.pendingPreventiveSystemStressTarget = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingPreventiveSystemStressTarget", ""))
        spec.pendingOverhaulSystemStart = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStart", ""))
        spec.pendingOverhaulSystemTarget = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemTarget", ""))
        spec.pendingOverhaulSystemStressStart = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStressStart", ""))
        spec.pendingOverhaulSystemStressTarget = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStressTarget", ""))
        spec.pendingRepairSystemStressStart = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressStart", ""))
        spec.pendingRepairSystemStressTarget = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressTarget", ""))
        spec.pendingRepairSystemStressStartRatio = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressStartRatio", ""))
        local loadedFactorStatsFlat = ADS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#factorStats", ""))

        local loadedSystemsStateRaw = ADS_Utils.deserializeSystemsState(savegame.xmlFile:getValue(key .. "#systemsState", ""))
        local loadedSystemsState = {}
        for loadedKey, loadedData in pairs(loadedSystemsStateRaw) do
            loadedSystemsState[string.lower(tostring(loadedKey))] = loadedData
        end
        local hasSerializedSystemsState = next(loadedSystemsState) ~= nil

        if spec.systems == nil then
            spec.systems = {}
        end
        for systemKey, systemData in pairs(spec.systems) do
            if type(systemData) ~= "table" then
                systemData = {
                    condition = tonumber(systemData) or 1.0,
                    stress = 0.0,
                    enabled = true
                }
                spec.systems[systemKey] = systemData
            end

            local loadedData = loadedSystemsState[string.lower(tostring(systemKey))]
            if loadedData ~= nil then
                systemData.condition = math.clamp(tonumber(loadedData.condition) or systemData.condition or 1.0, 0.001, 1.0)
                systemData.stress = math.max(tonumber(loadedData.stress) or systemData.stress or 0.0, 0.0)
                systemData.enabled = ADS_Utils.normalizeBoolValue(loadedData.enabled, systemData.enabled ~= false)
            else
                if not hasSerializedSystemsState and spec.conditionLevel ~= nil then
                    systemData.condition = math.clamp(tonumber(spec.conditionLevel) or systemData.condition or 1.0, 0.001, 1.0)
                else
                    systemData.condition = math.clamp(tonumber(systemData.condition) or 1.0, 0.001, 1.0)
                end
                systemData.stress = math.max(tonumber(systemData.stress) or 0.0, 0.0)
                systemData.enabled = ADS_Utils.normalizeBoolValue(systemData.enabled, true)
            end

            systemData.name = ADS_Utils.getSystemNameByKey(AdvancedDamageSystem.SYSTEMS, systemKey)
        end
        ensureFactorStats(spec, self)
        applyFlattenedFactorStats(spec, loadedFactorStatsFlat)
        ensureFactorStats(spec, self)

        -- Load Maintenance Log
        spec.maintenanceLog = {}
        local i = 0
        while true do
            local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, i)
            if not savegame.xmlFile:hasProperty(entryKey) then
                break
            end

            local entry = {
                id = savegame.xmlFile:getValue(entryKey .. "#id"),
                type = savegame.xmlFile:getValue(entryKey .. "#type"),
                price = savegame.xmlFile:getValue(entryKey .. "#price"),
                date = ADS_Utils.deserializeDate(savegame.xmlFile:getValue(entryKey .. "#date")),
                conditionData = {}
            }
            local condKey = entryKey .. ".conditionData"

            if savegame.xmlFile:hasProperty(condKey) then
                entry.location = savegame.xmlFile:getValue(entryKey .. "#location", "UNKNOWN")
                entry.optionOne = savegame.xmlFile:getValue(entryKey .. "#optionOne", "NONE")
                entry.optionTwo = savegame.xmlFile:getValue(entryKey .. "#optionTwo", "NONE")
                entry.optionThree = savegame.xmlFile:getValue(entryKey .. "#optionThree", false)
                entry.isVisible = ADS_Utils.normalizeBoolValue(savegame.xmlFile:getValue(entryKey .. "#isVisible", true), true)
                entry.isCompleted = ADS_Utils.normalizeBoolValue(savegame.xmlFile:getValue(entryKey .. "#isCompleted", true), true)

                entry.conditionData.year = savegame.xmlFile:getValue(condKey .. "#year", 0)
                entry.conditionData.operatingHours = savegame.xmlFile:getValue(condKey .. "#operatingHours", 0)
                entry.conditionData.age = savegame.xmlFile:getValue(condKey .. "#age", 0)
                entry.conditionData.condition = savegame.xmlFile:getValue(condKey .. "#condition", 1)
                entry.conditionData.service = savegame.xmlFile:getValue(condKey .. "#service", 1)
                entry.conditionData.reliability = savegame.xmlFile:getValue(condKey .. "#reliability", 1)
                entry.conditionData.maintainability = savegame.xmlFile:getValue(condKey .. "#maintainability", 1)
                entry.conditionData.systems = ADS_Utils.createSystemsSnapshot(ADS_Utils.deserializeSystemsState(savegame.xmlFile:getValue(condKey .. "#systems", "")))
                entry.conditionData.batterySoc = savegame.xmlFile:getValue(condKey .. "#batterySoc", 1)

                local bdStr = savegame.xmlFile:getValue(condKey .. "#activeBreakdowns", "")
                entry.conditionData.activeBreakdowns = ADS_Utils.deserializeBreakdowns(bdStr) or {}

                local selBdStr = savegame.xmlFile:getValue(condKey .. "#selectedBreakdowns", "")
                entry.conditionData.selectedBreakdowns = ADS_Utils.parseCsvList(selBdStr)

                entry.conditionData.activeEffects = ADS_Utils.deserializeEffectSnapshot(savegame.xmlFile:getValue(condKey .. "#activeEffects", ""))

                entry.conditionData.activeIndicators = {}
                local indicatorIds = ADS_Utils.parseCsvList(savegame.xmlFile:getValue(condKey .. "#activeIndicators", ""))
                for _, indId in ipairs(indicatorIds) do
                    entry.conditionData.activeIndicators[indId] = true
                end

                table.insert(spec.maintenanceLog, entry)
            end

            i = i + 1
        end

        -- Fill defaults
        if spec.serviceLevel == nil then spec.serviceLevel = spec.baseServiceLevel end
        if spec.conditionLevel == nil then spec.conditionLevel = spec.baseConditionLevel end
        if spec.maintenanceTimer == nil then spec.maintenanceTimer = 0 end
        if spec.currentState == nil then spec.currentState = AdvancedDamageSystem.STATUS.READY end
        if spec.plannedState == nil then spec.plannedState = AdvancedDamageSystem.STATUS.READY end
        if spec.serviceOptionThree == nil then spec.serviceOptionThree = false end
        if spec.pendingSelectedBreakdowns == nil then spec.pendingSelectedBreakdowns = {} end
        if spec.pendingInspectionQueue == nil then spec.pendingInspectionQueue = {} end
        if spec.pendingRepairQueue == nil then spec.pendingRepairQueue = {} end
        if spec.pendingProgressStepIndex == nil then spec.pendingProgressStepIndex = 0 end
        if spec.pendingProgressTotalTime == nil then spec.pendingProgressTotalTime = 0 end
        if spec.pendingProgressElapsedTime == nil then spec.pendingProgressElapsedTime = 0 end
        if spec.pendingPreventiveSystemStressStart == nil then spec.pendingPreventiveSystemStressStart = {} end
        if spec.pendingPreventiveSystemStressTarget == nil then spec.pendingPreventiveSystemStressTarget = {} end
        if spec.pendingOverhaulSystemStart == nil then spec.pendingOverhaulSystemStart = {} end
        if spec.pendingOverhaulSystemTarget == nil then spec.pendingOverhaulSystemTarget = {} end
        if spec.pendingOverhaulSystemStressStart == nil then spec.pendingOverhaulSystemStressStart = {} end
        if spec.pendingOverhaulSystemStressTarget == nil then spec.pendingOverhaulSystemStressTarget = {} end
        if spec.pendingRepairSystemStressStart == nil then spec.pendingRepairSystemStressStart = {} end
        if spec.pendingRepairSystemStressTarget == nil then spec.pendingRepairSystemStressTarget = {} end
        if spec.pendingRepairSystemStressStartRatio == nil then spec.pendingRepairSystemStressStartRatio = {} end
        if spec.aiWorkerPid == nil then
            spec.aiWorkerPid = {
                integral = 0,
                lastError = 0,
                filteredStress = 0,
                currentReduction = 0,
                baseCruiseSpeed = nil,
                applyTimer = 0,
                lastAppliedSpeed = nil
            }
        end
        self:updateConditionLevel()
    else
        spec.realOperatingTime = currentOperatingTime
    end

    if (spec.realOperatingTime == nil or spec.realOperatingTime <= 0) and currentOperatingTime > 0 then
        spec.realOperatingTime = currentOperatingTime
    end

    spec.isUnderRoof = self:isUnderRoof()

    spec.fieldInspection = spec.fieldInspection or {
        isActive = false,
        elapsedTime = 0,
        duration = ADS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION,
        startTime = 0,
        targetNode = nil,
        targetVehicle = nil
    }

    -- Sounds Loading
    local xmlSoundFile = loadXMLFile("ads_sounds", AdvancedDamageSystem.modDirectory .. "sounds/ads_sounds.xml")
    if spec.samples == nil then
        spec.samples = {}
    end
    
    if xmlSoundFile ~= nil then
        local soundManager = g_soundManager
        local modDir = AdvancedDamageSystem.modDirectory
        local root = self.rootNode
        local i3d = self.i3dMappings
        
        spec.samples.starterCranking = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "starterCranking", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.starterCrankingEnd = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "starterCrankingEnd", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.alarm = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "alarm", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.warning = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "warning", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.transmissionShiftFailed1 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "transmissionShiftFailed1", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.transmissionShiftFailed2 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "transmissionShiftFailed2", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.transmissionShiftFailed3 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "transmissionShiftFailed3", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.brakes1 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "brakes1", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.brakes2 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "brakes2", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.brakes3 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "brakes3", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.turboWhistle = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "turboWhistle", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.fanNoice = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "fanNoice", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.wheelHubBearingNoise = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "wheelHubBearingNoise", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.vibrationNoice = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "vibrationNoice", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.wheelSeizureGrind = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "wheelSeizureGrind", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.gearDisengage1 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "gearDisengage1", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.engineKnocking = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "engineKnocking", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.valveTrainNoise = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "valveTrainNoise", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.inspection = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "inspection", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        delete(xmlSoundFile)
    else
        log_dbg("ERROR: AdvancedDamageSystem - Could not load ads_sounds.xml")
    end

    spec.rawEngineTemperature = spec.engineTemperature
    spec.rawTransmissionTemperature = spec.transmissionTemperature

    spec.isElectricVehicle = getIsElectricVehicle(self)
    spec.isDieselVehicle = ADS_Preheat.isDieselVehicle(self)
    spec.hydraulicsMoveAlphaCache = {}
    spec.hydraulicsLiftRatioCache = {}

    local function resetIsMovingRecursive(vehicleObj, visited)
        if vehicleObj == nil or visited[vehicleObj] then
            return
        end
        visited[vehicleObj] = true

        if vehicleObj.spec_attacherJoints ~= nil then
            if vehicleObj.spec_attacherJoints.attacherJoints ~= nil then
                for _, jointDesc in pairs(vehicleObj.spec_attacherJoints.attacherJoints) do
                    if jointDesc ~= nil then
                        jointDesc.isMoving = false
                    end
                end
            end

            if vehicleObj.spec_attacherJoints.attachedImplements ~= nil then
                for _, implementData in pairs(vehicleObj.spec_attacherJoints.attachedImplements) do
                    if implementData ~= nil and implementData.object ~= nil then
                        resetIsMovingRecursive(implementData.object, visited)
                    end
                end
            end
        end
    end

    local function enableOrDisableSystems(vehicle)
        local spec = vehicle.spec_AdvancedDamageSystem
        for _, systemData in pairs(spec.systems) do
            -- disable engine for electric vehicles
            if systemData.name == AdvancedDamageSystem.SYSTEMS.ENGINE then
                if spec.isElectricVehicle then
                    systemData.enabled = false
                end
            -- disable transsmision for electric vehicles
            elseif systemData.name == AdvancedDamageSystem.SYSTEMS.TRANSMISSION then
                if spec.isElectricVehicle then
                    systemData.enabled = false
                end
            -- disable hydralic for trucks, cars, motorbikes
            elseif systemData.name == AdvancedDamageSystem.SYSTEMS.HYDRAULICS then
                local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
                local vtype = vehicle.type.name
                if storeItem.categoryName == "TRUCKS" or vtype == "car" or vtype == "carFillable" or vtype == "motorbike" then
                    systemData.enabled = false
                end
            -- disable cooling for trucks, cars, motorbikes
            elseif systemData.name == AdvancedDamageSystem.SYSTEMS.COOLING then
                if spec.isElectricVehicle then
                    systemData.enabled = false
                end
            -- electrical is  applicable for all vehicles
            elseif systemData.name == AdvancedDamageSystem.SYSTEMS.ELECTRICAL then
            -- chassis is applicable for all vehicles
            elseif systemData.name == AdvancedDamageSystem.SYSTEMS.CHASSIS  then
            --- disable fuel system for electric vehicles
            elseif systemData.name == AdvancedDamageSystem.SYSTEMS.FUEL then
                if spec.isElectricVehicle then
                    systemData.enabled = false
                end
            else
                systemData.enabled = true
            end
        end
    end

    local vtype = self.type.name
    spec.isExcludedFromPTOSharpAngleFactor = PTO_SHARP_ANGLE_EXCLUDED_TYPES[vtype] == true
    enableOrDisableSystems(self)
    spec.isVehicleNeedLubricate = getIsVehicleNeedLubricate(self)
    spec.isVehicleNeedBlowOut = getIsVehicleNeedBlowOut(self)
    resetIsMovingRecursive(self, {})

    --- for deneral wear and tear calculations
    spec._prevConditionLevel = self:getConditionLevel()

    --- for dirty-flag comparison
    --- [1] state
    spec._lastSyncState_currentState = spec.currentState
    spec._lastSyncState_plannedState = spec.plannedState
    spec._lastSyncState_maintenanceTimer = spec.maintenanceTimer
    --- [2] service context
    spec._lastSyncServiceContext_optionOne = spec.serviceOptionOne
    spec._lastSyncServiceContext_optionTwo = spec.serviceOptionTwo
    spec._lastSyncServiceContext_optionThree = spec.serviceOptionThree
    spec._lastSyncServiceContext_workshopType = spec.workshopType
    --- [3] telemetry
    spec._lastSyncTelemetry_operatingTime = getSyncOperatingTime(self)
    spec._lastSyncTelemetry_realOperatingTime = spec.realOperatingTime
    spec._lastSyncTelemetry_fuelUsageRaw = spec._fuelUsageRaw
    spec._lastSyncTelemetry_dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or 0
    --- [4] thermal
    spec._lastSyncThermal_rawEngineTemperature = spec.rawEngineTemperature
    spec._lastSyncThermal_rawTransmissionTemperature = spec.rawTransmissionTemperature
    spec._lastSyncThermal_thermostatState = spec.thermostatState
    spec._lastSyncThermal_transmissionThermostatState = spec.transmissionThermostatState
    --- [5] electrical
    spec._lastSyncElectrical_batterySoc = spec.batterySoc
    spec._lastSyncElectrical_batteryChargeAh = spec.batteryChargeAh
    spec._lastSyncElectrical_batteryTerminalVoltage = spec.batteryTerminalVoltageV
    spec._lastSyncElectrical_systemVoltage = spec.systemVoltageV
    spec._lastSyncElectrical_preheatState = spec.preheatState
    spec._lastSyncElectrical_preheatLampTestActive = spec.preheatLampTestActive
    spec._lastSyncElectrical_preheatWasRequired = spec.preheatWasRequired
    spec._lastSyncElectrical_preheatColdStartFaultSeverity = spec.preheatColdStartFaultSeverity
    --- [6] fieldcare
    spec._lastSyncFieldcare_radiatorClogging = spec.radiatorClogging
    spec._lastSyncFieldcare_airIntakeClogging = spec.airIntakeClogging
    spec._lastSyncFieldcare_lubricationLevel = spec.lubricationLevel
    spec._lastSyncFieldcare_inspectionSoundActive = spec.fieldInspectionSoundActive
    --- [7] wear
    spec._lastSyncWear_serviceLevel = spec.serviceLevel
    spec._lastSyncWear_conditionLevel = spec.conditionLevel
    captureSystemsSync(spec)
    --- [8] breakdowns
    spec._lastSyncBreakdowns_serialized = ADS_Utils.serializeBreakdowns(spec.activeBreakdowns or {})
    --- [9] service
    spec._lastSyncServiceProgress_elapsed = spec.pendingProgressElapsedTime
    spec._lastSyncServiceProgress_step = spec.pendingProgressStepIndex
    spec._lastSyncServiceProgress_total = spec.pendingProgressTotalTime

    ADS_Electrical.initVoltagesFromSoc(self)

    self:recalculateAndApplyEffects()
end

function AdvancedDamageSystem:onDelete()
    local spec = self.spec_AdvancedDamageSystem

    if spec and spec.samples then
        g_soundManager:deleteSamples(spec.samples)
    end

    if ADS_Main and ADS_Main.vehicles and self.uniqueId and ADS_Main.vehicles[self.uniqueId] then
        if ADS_Main.previousKey == self.uniqueId then
            ADS_Main.previousKey = nil
        end
        ADS_Main.vehicles[self.uniqueId] = nil
        ADS_Main.numVehicles = ADS_Main.numVehicles - 1
    end
end
