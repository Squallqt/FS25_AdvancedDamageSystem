local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")
local getIsElectricVehicle = RMS_Utils.getIsElectricVehicle
local ensureFactorStats = RealisticMechanicalSystems.ensureFactorStats
local refreshExclusionState = RealisticMechanicalSystems.refreshExclusionState
local getSyncOperatingTime = RealisticMechanicalSystems.getSyncOperatingTime
local captureSystemsSync = RealisticMechanicalSystems.captureSystemsSync

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
    return not vehicle.xmlFile:getValue("vehicle.enterable#isTabbable", true)
end

local function getIsVehicleNeedLubricate(vehicle)
    if vehicle == nil then
        return false
    end

    local vtype = vehicle.type ~= nil and vehicle.type.name or ""
    if vtype == "car" or vtype == "carFillable" or vtype == "motorbike" then
        return false
    end

    return not RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
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

function RealisticMechanicalSystems:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_RealisticMechanicalSystems
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
        local breakdownString = RMS_Utils.serializeBreakdowns(spec.activeBreakdowns)
        xmlFile:setValue(key .. "#breakdowns", breakdownString)
        xmlFile:setValue(key .. "#state", spec.currentState or RealisticMechanicalSystems.STATUS.READY)
        xmlFile:setValue(key .. "#plannedState", spec.plannedState or RealisticMechanicalSystems.STATUS.READY)
        xmlFile:setValue(key .. "#maintenanceTimer", RealisticMechanicalSystems.sanitizeNumber(spec.maintenanceTimer, 0, 0))
        xmlFile:setValue(key .. "#engineTemperature", RealisticMechanicalSystems.sanitizeNumber(spec.engineTemperature, 20, -80, 160))
        xmlFile:setValue(key .. "#transmissionTemperature", RealisticMechanicalSystems.sanitizeNumber(spec.transmissionTemperature, 20, -80, 180))
        xmlFile:setValue(key .. "#batterySoc", RealisticMechanicalSystems.sanitizeNumber(spec.batterySoc, 1.0, 0, 1))
        xmlFile:setValue(key .. "#batteryChargeAh", RealisticMechanicalSystems.sanitizeNumber(spec.batteryChargeAh, 0, 0, 10000))
        xmlFile:setValue(key .. "#batteryTempC", RealisticMechanicalSystems.sanitizeNumber(spec.batteryTempC, 20, -80, 85))
        xmlFile:setValue(key .. "#radiatorClogging", math.max(spec.radiatorClogging or 0, 0))
        xmlFile:setValue(key .. "#airIntakeClogging", math.max(spec.airIntakeClogging or 0, 0))
        xmlFile:setValue(key .. "#lubricationLevel", math.clamp(spec.lubricationLevel or 1.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#lubricationUsedThisPeriod", spec.lubricationUsedThisPeriod == true)
        xmlFile:setValue(key .. "#thermostatState", RealisticMechanicalSystems.sanitizeNumber(spec.thermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#transmissionThermostatState", RealisticMechanicalSystems.sanitizeNumber(spec.transmissionThermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#serviceOptionOne", spec.serviceOptionOne or "")
        xmlFile:setValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo or "")
        xmlFile:setValue(key .. "#serviceOptionThree", spec.serviceOptionThree or false)
        xmlFile:setValue(key .. "#workshopType", spec.workshopType or "")
        xmlFile:setValue(key .. "#pendingSelectedBreakdowns", table.concat(spec.pendingSelectedBreakdowns or {}, ","))
        xmlFile:setValue(key .. "#pendingServicePrice", RMS_Utils.encodeOptionalFloat(spec.pendingServicePrice))
        xmlFile:setValue(key .. "#pendingInspectionQueue", table.concat(spec.pendingInspectionQueue or {}, ","))
        xmlFile:setValue(key .. "#pendingRepairQueue", table.concat(spec.pendingRepairQueue or {}, ","))
        xmlFile:setValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex or 0)
        xmlFile:setValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime or 0)
        xmlFile:setValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime or 0)
        xmlFile:setValue(key .. "#pendingMaintenanceServiceStart", RMS_Utils.encodeOptionalFloat(spec.pendingMaintenanceServiceStart))
        xmlFile:setValue(key .. "#pendingMaintenanceServiceTarget", RMS_Utils.encodeOptionalFloat(spec.pendingMaintenanceServiceTarget))
        xmlFile:setValue(key .. "#pendingPreventiveSystemStressStart", RMS_Utils.serializeNumericMap(spec.pendingPreventiveSystemStressStart))
        xmlFile:setValue(key .. "#pendingPreventiveSystemStressTarget", RMS_Utils.serializeNumericMap(spec.pendingPreventiveSystemStressTarget))
        xmlFile:setValue(key .. "#systemsState", RMS_Utils.serializeSystemsState(spec.systems))
        xmlFile:setValue(key .. "#factorStats", RMS_Utils.serializeNumericMap(flattenFactorStats(spec.factorStats)))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStart", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStart))
        xmlFile:setValue(key .. "#pendingOverhaulSystemTarget", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemTarget))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStressStart", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStressStart))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStressTarget", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStressTarget))
        xmlFile:setValue(key .. "#pendingRepairSystemStressStart", RMS_Utils.serializeNumericMap(spec.pendingRepairSystemStressStart))
        xmlFile:setValue(key .. "#pendingRepairSystemStressTarget", RMS_Utils.serializeNumericMap(spec.pendingRepairSystemStressTarget))
        xmlFile:setValue(key .. "#pendingRepairSystemStressStartRatio", RMS_Utils.serializeNumericMap(spec.pendingRepairSystemStressStartRatio))

        RMS_Drivetrain.saveToXMLFile(self, xmlFile, key)

        if spec.maintenanceLog and #spec.maintenanceLog > 0 then
            for i, entry in ipairs(spec.maintenanceLog) do
                local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, i - 1)
                
                xmlFile:setValue(entryKey .. "#id", entry.id or 0)
                xmlFile:setValue(entryKey .. "#type", entry.type or "")
                xmlFile:setValue(entryKey .. "#price", entry.price or 0)
                xmlFile:setValue(entryKey .. "#date", RMS_Utils.serializeDate(entry.date)) 
                xmlFile:setValue(entryKey .. "#location", entry.location or "UNKNOWN")
                xmlFile:setValue(entryKey .. "#optionOne", entry.optionOne or "NONE")
                xmlFile:setValue(entryKey .. "#optionTwo", entry.optionTwo or "NONE")
                xmlFile:setValue(entryKey .. "#optionThree", entry.optionThree or false)
                xmlFile:setValue(entryKey .. "#isVisible", tostring(RMS_Utils.normalizeBoolValue(entry.isVisible, true)))
                xmlFile:setValue(entryKey .. "#isCompleted", RMS_Utils.normalizeBoolValue(entry.isCompleted, true))

                if entry.conditionData then
                    local condKey = entryKey .. ".conditionData"
                    xmlFile:setValue(condKey .. "#year", entry.conditionData.year or 0)
                    xmlFile:setValue(condKey .. "#operatingHours", entry.conditionData.operatingHours or 0)
                    xmlFile:setValue(condKey .. "#age", entry.conditionData.age or 0)
                    xmlFile:setValue(condKey .. "#condition", entry.conditionData.condition or 1)
                    xmlFile:setValue(condKey .. "#service", entry.conditionData.service or 1)
                    xmlFile:setValue(condKey .. "#reliability", entry.conditionData.reliability or 1)
                    xmlFile:setValue(condKey .. "#maintainability", entry.conditionData.maintainability or 1)
                    xmlFile:setValue(condKey .. "#systems", RMS_Utils.serializeSystemsState(RMS_Utils.createSystemsSnapshot(entry.conditionData.systems)))
                    xmlFile:setValue(condKey .. "#batterySoc", entry.conditionData.batterySoc or 1)

                    if entry.conditionData.activeBreakdowns then
                        xmlFile:setValue(condKey .. "#activeBreakdowns", RMS_Utils.serializeBreakdowns(entry.conditionData.activeBreakdowns))
                    end
                    
                    if entry.conditionData.selectedBreakdowns and #entry.conditionData.selectedBreakdowns > 0 then
                        xmlFile:setValue(condKey .. "#selectedBreakdowns", table.concat(entry.conditionData.selectedBreakdowns, ","))
                    end
                    
                    if entry.conditionData.activeEffects then
                        xmlFile:setValue(condKey .. "#activeEffects", RMS_Utils.serializeEffectSnapshot(entry.conditionData.activeEffects))
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

function RealisticMechanicalSystems:onLoad(savegame)
    self.spec_RealisticMechanicalSystems.isExcludedVehicle = false
    self.spec_RealisticMechanicalSystems.isExcludedByDefault = false
    self.spec_RealisticMechanicalSystems.isExcludedByRule = false
    self.spec_RealisticMechanicalSystems.isExcludedByUser = nil
    self.spec_RealisticMechanicalSystems.isElectricVehicle = false
    self.spec_RealisticMechanicalSystems.isTruck = getIsTruck(self)
    self.spec_RealisticMechanicalSystems.isVehicleNeedLubricate = false
    self.spec_RealisticMechanicalSystems.isVehicleNeedBlowOut = false

    self.spec_RealisticMechanicalSystems.baseServiceLevel = 1.0
    self.spec_RealisticMechanicalSystems.baseConditionLevel = 1.0
    self.spec_RealisticMechanicalSystems.serviceLevel = self.spec_RealisticMechanicalSystems.baseServiceLevel
    self.spec_RealisticMechanicalSystems.conditionLevel = self.spec_RealisticMechanicalSystems.baseConditionLevel

    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local existingRealOperatingTime = tonumber(self.spec_RealisticMechanicalSystems.realOperatingTime) or 0
    self.spec_RealisticMechanicalSystems.realOperatingTime = math.max(existingRealOperatingTime, currentOperatingTime)
    self.spec_RealisticMechanicalSystems._prevConditionLevel = 0
    self.spec_RealisticMechanicalSystems._allowRMSOperatingTimeWrite = false

    self.spec_RealisticMechanicalSystems.systems = {
        engine = { name = RealisticMechanicalSystems.SYSTEMS.ENGINE, condition = 1.0, stress = 0.0, enabled = true },
        transmission = { name = RealisticMechanicalSystems.SYSTEMS.TRANSMISSION, condition = 1.0, stress = 0.0, enabled = true },
        hydraulics = { name = RealisticMechanicalSystems.SYSTEMS.HYDRAULICS, condition = 1.0, stress = 0.0, enabled = true },
        cooling = { name = RealisticMechanicalSystems.SYSTEMS.COOLING, condition = 1.0, stress = 0.0, enabled = true },
        electrical = { name = RealisticMechanicalSystems.SYSTEMS.ELECTRICAL, condition = 1.0, stress = 0.0, enabled = true },
        chassis = { name = RealisticMechanicalSystems.SYSTEMS.CHASSIS, condition = 1.0, stress = 0.0, enabled = true },
        fuel = { name = RealisticMechanicalSystems.SYSTEMS.FUEL, condition = 1.0, stress = 0.0, enabled = true }
    }
    self.spec_RealisticMechanicalSystems.factorStats = createEmptyFactorStats(self.spec_RealisticMechanicalSystems.systems)
    ensureFactorStats(self.spec_RealisticMechanicalSystems, self)

    --- engine consumptables
    self.spec_RealisticMechanicalSystems.airIntakeClogging = 0.0

    self.spec_RealisticMechanicalSystems.extraConditionWear = 0
    self.spec_RealisticMechanicalSystems.extraServiceWear = 0
    self.spec_RealisticMechanicalSystems.extraEngineHeat = 0
    self.spec_RealisticMechanicalSystems.extraTransmissionHeat = 0
    self.spec_RealisticMechanicalSystems.extraCurrentPeak = 0
    
    self.spec_RealisticMechanicalSystems.reliability = 1.0
    self.spec_RealisticMechanicalSystems.maintainability = 1.0
    self.spec_RealisticMechanicalSystems.year = RMS_VehicleYears.DEFAULT_YEAR

    self.spec_RealisticMechanicalSystems.activeBreakdowns = {}
    self.spec_RealisticMechanicalSystems.activeEffects = {}
    self.spec_RealisticMechanicalSystems.activeIndicators = {}
    self.spec_RealisticMechanicalSystems.activeFunctions = {}
    self.spec_RealisticMechanicalSystems.originalFunctions = {}
    self.spec_RealisticMechanicalSystems.dynamicBreakdowns = {}

    self.spec_RealisticMechanicalSystems.maintenanceLog = {}
    
    self.spec_RealisticMechanicalSystems._fuelUsageRaw  = 0
    self.spec_RealisticMechanicalSystems.lastBlinkingWarningMessage = ""
    self.spec_RealisticMechanicalSystems.blinkingWarningTimer = 0
    self.spec_RealisticMechanicalSystems.coldEngineExposureMs = 0
    self.spec_RealisticMechanicalSystems.coldEngineWarningShown = false
    self.spec_RealisticMechanicalSystems.pendingSideNotifications = {}

    self.spec_RealisticMechanicalSystems.startButtonActionEvents = {}
    self.spec_RealisticMechanicalSystems.startButtonDown = false
    self.spec_RealisticMechanicalSystems.startButtonHeld = false
    self.spec_RealisticMechanicalSystems.startButtonUp = false
    RMS_Preheat.initSpec(self)

    self.spec_RealisticMechanicalSystems.drivetrainActionEvents = {}
    RMS_Drivetrain.initSpec(self)

    self.spec_RealisticMechanicalSystems.radiatorClogging = 0.0
    self.spec_RealisticMechanicalSystems.lubricationLevel = 1.0
    self.spec_RealisticMechanicalSystems.lubricationUsedThisPeriod = true
    self.spec_RealisticMechanicalSystems.fieldInspectionSoundActive = false
    self.spec_RealisticMechanicalSystems.fieldInspectionActivePlayers = {}

    self.spec_RealisticMechanicalSystems.batterySoc = 1.0
    self.spec_RealisticMechanicalSystems.batteryChargeAh = nil
    self.spec_RealisticMechanicalSystems.batteryHealth = 1.0
    self.spec_RealisticMechanicalSystems.batteryCapacityAh = RMS_Config.ELECTRICAL.BATTERY_NOMINAL_CAPACITY
    self.spec_RealisticMechanicalSystems.batteryTempC = 0
    self.spec_RealisticMechanicalSystems.batteryOpenCircuitVoltageV = 12.7
    self.spec_RealisticMechanicalSystems.rawBatteryTerminalVoltageV = 12.7
    self.spec_RealisticMechanicalSystems.batteryTerminalVoltageV = 12.7
    self.spec_RealisticMechanicalSystems.rawSystemVoltageV = 12.7
    self.spec_RealisticMechanicalSystems.systemVoltageV = 12.7
    self.spec_RealisticMechanicalSystems.alternatorHealth = 1.0
    self.spec_RealisticMechanicalSystems.iAltAvail = 0
    self.spec_RealisticMechanicalSystems.iLoads = 0
    self.spec_RealisticMechanicalSystems.externalPowerConnection = nil

    self.spec_RealisticMechanicalSystems.engineTemperature = -99
    self.spec_RealisticMechanicalSystems.rawEngineTemperature = -99
    self.spec_RealisticMechanicalSystems._netTargetEngineTemp = nil
    self.spec_RealisticMechanicalSystems._smoothedMotorLoad = 0
    self.spec_RealisticMechanicalSystems._netDynamicMotorLoad = 0
    self.spec_RealisticMechanicalSystems.radiatorHealth = 1.0
    self.spec_RealisticMechanicalSystems.fanClutchHealth = 1.0
    self.spec_RealisticMechanicalSystems.thermostatState = 0.0
    self.spec_RealisticMechanicalSystems.thermostatHealth = 1.0
    self.spec_RealisticMechanicalSystems.thermostatStuckedPosition = nil
    self.spec_RealisticMechanicalSystems.engTermPID = {
        integral = 0,
        lastError = 0
    }

    self.spec_RealisticMechanicalSystems.transmissionTemperature = -99
    self.spec_RealisticMechanicalSystems.rawTransmissionTemperature = -99
    self.spec_RealisticMechanicalSystems._netTargetTransmissionTemp = nil
    self.spec_RealisticMechanicalSystems.transmissionThermostatState = 0.0
    self.spec_RealisticMechanicalSystems.transmissionThermostatHealth = 1.0
    self.spec_RealisticMechanicalSystems.transmissionThermostatStuckedPosition = nil
    self.spec_RealisticMechanicalSystems.transTermPID = {
        integral = 0,
        lastError = 0
    }
    self.spec_RealisticMechanicalSystems.aiWorkerPid = {
        integral = 0,
        lastError = 0,
        filteredStress = 0,
        currentReduction = 0,
        baseCruiseSpeed = nil,
        applyTimer = 0,
        lastAppliedSpeed = nil
    }

    self.spec_RealisticMechanicalSystems.debugData = {
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

    self.spec_RealisticMechanicalSystems.isExcludedFromPTOSharpAngleFactor = false
    self.spec_RealisticMechanicalSystems.isUnderRoof = true
    self.spec_RealisticMechanicalSystems.roofRaycastHit = false
    self.spec_RealisticMechanicalSystems.roofRaycastResult = nil
    self.spec_RealisticMechanicalSystems.roofLastRaycastTime = nil
    self.spec_RealisticMechanicalSystems.roofWasStationary = false
    self.spec_RealisticMechanicalSystems.dynamicMotorLoad = 0
    self.spec_RealisticMechanicalSystems.avgDynamicMotorLoad = 0
    self.spec_RealisticMechanicalSystems.avgSpeed = 0
    self.spec_RealisticMechanicalSystems.activeDraftMaxForce = 0
    self.spec_RealisticMechanicalSystems.activeDraftEffectiveForceCap = 0
    self.spec_RealisticMechanicalSystems.isCranking = false
    self.spec_RealisticMechanicalSystems.wheelSlipIntensity = 0
    self.spec_RealisticMechanicalSystems._wheelSlipPreviousSample = 0
    self.spec_RealisticMechanicalSystems._wheelSlipOlderSample = 0
    self.spec_RealisticMechanicalSystems.wheelSlipTutorialTimer = 0
    self.spec_RealisticMechanicalSystems.luggingTutorialTimer = 0
    self.spec_RealisticMechanicalSystems.avgTireGroundFrictionCoeff = 0
    self.spec_RealisticMechanicalSystems.avgGroundSurfaceFactor = 0
    self.spec_RealisticMechanicalSystems.implements = {}
    self.spec_RealisticMechanicalSystems.isImplementLifted = false
    self.spec_RealisticMechanicalSystems.isImplementLowered = false
    self.spec_RealisticMechanicalSystems.isImplementOperating = false
    self.spec_RealisticMechanicalSystems.liftedMass = 0
    self.spec_RealisticMechanicalSystems.operatingMass = 0
    self.spec_RealisticMechanicalSystems.isPtoActive = false
    self.spec_RealisticMechanicalSystems.maxConnectedPtoAngleDeg = 0
    self.spec_RealisticMechanicalSystems.ptoConnectionIsTrailerHitch = false
    self.spec_RealisticMechanicalSystems.hasConnectedPto = false
    self.spec_RealisticMechanicalSystems.hydraulicsMoveAlphaCache = {}
    self.spec_RealisticMechanicalSystems.hydraulicsLiftRatioCache = {}
    self.spec_RealisticMechanicalSystems.chassisVibState = {
        prevSuspension = {},
        smoothed = 0,
        raw = 0,
        signal = 0,
        wheelCount = 0,
        speedFactor = 0,
        avgDensityType = 0,
        fieldMultiplier = 1
    }
    self.spec_RealisticMechanicalSystems.chassisSteerState = {
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
    self.spec_RealisticMechanicalSystems.chassisBrakeState = {
        pedal = 0,
        massRatio = 0,
        trailerMass = 0,
        totalMass = 0,
        hpTrailerMassRatio = 1000,
        hpGrossMassRatio = 1000,
        isBraking = false,
        isBrakingByAxis = false
    }
    self.spec_RealisticMechanicalSystems.fuelState = {
        level = 0,
        currentUsageRatio = 0,
        temperature = 0,
        idleTimer = 0
    }
    self.spec_RealisticMechanicalSystems.isHarvesting = false

    self.spec_RealisticMechanicalSystems.onUpdateTimer = RMS_Config.ON_UPDATE_DELAY
    self.spec_RealisticMechanicalSystems.updateVehicleStateTimerOne = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_ONE
    self.spec_RealisticMechanicalSystems.updateVehicleStateTimerTwo = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_TWO
    self.spec_RealisticMechanicalSystems.updateVehicleStateTimerThree = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_THREE
    self.spec_RealisticMechanicalSystems.metaUpdateTimer = math.random() * RMS_Config.META_UPDATE_DELAY
    self.spec_RealisticMechanicalSystems.maintenanceTimer = 0
    self.spec_RealisticMechanicalSystems.currentState = RealisticMechanicalSystems.STATUS.READY
    self.spec_RealisticMechanicalSystems.plannedState = RealisticMechanicalSystems.STATUS.READY
    self.spec_RealisticMechanicalSystems.workshopType = RealisticMechanicalSystems.WORKSHOP.DEALER
    self.spec_RealisticMechanicalSystems.serviceOptionOne = nil
    self.spec_RealisticMechanicalSystems.serviceOptionTwo = nil
    self.spec_RealisticMechanicalSystems.serviceOptionThree = false
    self.spec_RealisticMechanicalSystems.pendingSelectedBreakdowns = {}
    self.spec_RealisticMechanicalSystems.pendingServicePrice = nil
    self.spec_RealisticMechanicalSystems.pendingInspectionQueue = {}
    self.spec_RealisticMechanicalSystems.pendingRepairQueue = {}
    self.spec_RealisticMechanicalSystems.pendingProgressStepIndex = 0
    self.spec_RealisticMechanicalSystems.pendingProgressTotalTime = 0
    self.spec_RealisticMechanicalSystems.pendingProgressElapsedTime = 0
    self.spec_RealisticMechanicalSystems.pendingMaintenanceServiceStart = nil
    self.spec_RealisticMechanicalSystems.pendingMaintenanceServiceTarget = nil
    self.spec_RealisticMechanicalSystems.pendingPreventiveSystemStressStart = {}
    self.spec_RealisticMechanicalSystems.pendingPreventiveSystemStressTarget = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemStart = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemTarget = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemStressStart = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemStressTarget = {}
    self.spec_RealisticMechanicalSystems.pendingRepairSystemStressStart = {}
    self.spec_RealisticMechanicalSystems.pendingRepairSystemStressTarget = {}
    self.spec_RealisticMechanicalSystems.pendingRepairSystemStressStartRatio = {}


    if self.isServer then
        local spec = self.spec_RealisticMechanicalSystems
        spec.rmsDirtyFlag = self:getNextDirtyFlag()
        spec.rmsPendingByConnection = {}
    end
end

function RealisticMechanicalSystems:onPostLoad(savegame)
    local spec = self.spec_RealisticMechanicalSystems
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0

    spec.isExcludedByDefault = getIsUnsupportedVehicle(self)
    spec.isExcludedByRule = getIsAuxiliaryMachine(self)
    spec.isExcludedByUser = nil
    if savegame ~= nil then
        local exclusionKey = savegame.key .. ".RealisticMechanicalSystems#userExclusion"
        spec.isExcludedByUser = savegame.xmlFile:getValue(exclusionKey)
    end
    refreshExclusionState(spec)
    if spec.isExcludedByDefault then return end

    if spec ~= nil and savegame ~= nil then
        local key = savegame.key .. ".RealisticMechanicalSystems"

        spec.serviceLevel = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#service", spec.serviceLevel), spec.serviceLevel or 1.0, 0.001)
        spec.conditionLevel = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#condition", spec.conditionLevel), spec.conditionLevel or 1.0, 0.001, 1.0)
        spec.currentState = savegame.xmlFile:getValue(key .. "#state", spec.currentState)
        spec.plannedState = savegame.xmlFile:getValue(key .. "#plannedState", spec.plannedState)
        spec.maintenanceTimer = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#maintenanceTimer", spec.maintenanceTimer), spec.maintenanceTimer or 0, 0)
        
        local loadedRealOperatingTime = nil
        if savegame.xmlFile:hasProperty(key .. "#realOperatingTime") then
            loadedRealOperatingTime = savegame.xmlFile:getValue(key .. "#realOperatingTime")
        end
        if loadedRealOperatingTime == nil and savegame.xmlFile.handle ~= nil then
            loadedRealOperatingTime = getXMLFloat(savegame.xmlFile.handle, key .. "#realOperatingTime")
        end
        if loadedRealOperatingTime ~= nil then
            spec.realOperatingTime = RealisticMechanicalSystems.sanitizeNumber(loadedRealOperatingTime, currentOperatingTime, 0)
        else
            spec.realOperatingTime = currentOperatingTime
        end

        -- Load Breakdowns
        local breakdownString = savegame.xmlFile:getValue(key .. "#breakdowns", "")
        if breakdownString and breakdownString ~= "" then
            spec.activeBreakdowns = RMS_Utils.deserializeBreakdowns(breakdownString)
        else
            spec.activeBreakdowns = {}
        end

        -- Load Simple Variables
        spec.engineTemperature = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#engineTemperature", spec.engineTemperature), 20, -80, 160)
        spec.transmissionTemperature = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#transmissionTemperature", spec.transmissionTemperature), spec.engineTemperature, -80, 180)
        spec.batterySoc = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#batterySoc", spec.batterySoc), 1.0, 0, 1)
        local loadedBatteryChargeAh = savegame.xmlFile:getValue(key .. "#batteryChargeAh", spec.batteryChargeAh)
        spec.batteryChargeAh = loadedBatteryChargeAh ~= nil and RealisticMechanicalSystems.sanitizeNumber(loadedBatteryChargeAh, 0, 0, 10000) or nil
        spec.batteryTempC = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#batteryTempC", spec.batteryTempC), 20, -80, 85)
        spec.radiatorClogging = math.max(savegame.xmlFile:getValue(key .. "#radiatorClogging", spec.radiatorClogging), 0)
        spec.airIntakeClogging = math.max(savegame.xmlFile:getValue(key .. "#airIntakeClogging", spec.airIntakeClogging), 0)
        spec.lubricationLevel = math.clamp(savegame.xmlFile:getValue(key .. "#lubricationLevel", spec.lubricationLevel), 0.0, 1.0)
        spec.lubricationUsedThisPeriod = savegame.xmlFile:getValue(key .. "#lubricationUsedThisPeriod", true)
        spec.thermostatState = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#thermostatState", spec.thermostatState), spec.thermostatState or 0, 0.0, 1.0)
        spec.transmissionThermostatState = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#transmissionThermostatState", spec.transmissionThermostatState), spec.transmissionThermostatState or 0, 0.0, 1.0)
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
        RMS_Drivetrain.loadFromSavegame(self, savegame.xmlFile, key)
        local loadedWorkshopType = savegame.xmlFile:getValue(key .. "#workshopType", "")
        if loadedWorkshopType ~= nil and loadedWorkshopType ~= "" then
            spec.workshopType = loadedWorkshopType
        end
        spec.pendingServicePrice = RMS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingServicePrice", spec.pendingServicePrice))
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
        spec.pendingMaintenanceServiceStart = RMS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingMaintenanceServiceStart", spec.pendingMaintenanceServiceStart))
        spec.pendingMaintenanceServiceTarget = RMS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingMaintenanceServiceTarget", spec.pendingMaintenanceServiceTarget))
        spec.pendingPreventiveSystemStressStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingPreventiveSystemStressStart", ""))
        spec.pendingPreventiveSystemStressTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingPreventiveSystemStressTarget", ""))
        spec.pendingOverhaulSystemStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStart", ""))
        spec.pendingOverhaulSystemTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemTarget", ""))
        spec.pendingOverhaulSystemStressStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStressStart", ""))
        spec.pendingOverhaulSystemStressTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStressTarget", ""))
        spec.pendingRepairSystemStressStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressStart", ""))
        spec.pendingRepairSystemStressTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressTarget", ""))
        spec.pendingRepairSystemStressStartRatio = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressStartRatio", ""))
        local loadedFactorStatsFlat = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#factorStats", ""))

        local loadedSystemsStateRaw = RMS_Utils.deserializeSystemsState(savegame.xmlFile:getValue(key .. "#systemsState", ""))
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
                systemData.enabled = RMS_Utils.normalizeBoolValue(loadedData.enabled, systemData.enabled ~= false)
            else
                if not hasSerializedSystemsState and spec.conditionLevel ~= nil then
                    systemData.condition = math.clamp(tonumber(spec.conditionLevel) or systemData.condition or 1.0, 0.001, 1.0)
                else
                    systemData.condition = math.clamp(tonumber(systemData.condition) or 1.0, 0.001, 1.0)
                end
                systemData.stress = math.max(tonumber(systemData.stress) or 0.0, 0.0)
                systemData.enabled = RMS_Utils.normalizeBoolValue(systemData.enabled, true)
            end

            systemData.name = RMS_Utils.getSystemNameByKey(RealisticMechanicalSystems.SYSTEMS, systemKey)
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
                date = RMS_Utils.deserializeDate(savegame.xmlFile:getValue(entryKey .. "#date")),
                conditionData = {}
            }
            local condKey = entryKey .. ".conditionData"

            if savegame.xmlFile:hasProperty(condKey) then
                entry.location = savegame.xmlFile:getValue(entryKey .. "#location", "UNKNOWN")
                entry.optionOne = savegame.xmlFile:getValue(entryKey .. "#optionOne", "NONE")
                entry.optionTwo = savegame.xmlFile:getValue(entryKey .. "#optionTwo", "NONE")
                entry.optionThree = savegame.xmlFile:getValue(entryKey .. "#optionThree", false)
                entry.isVisible = RMS_Utils.normalizeBoolValue(savegame.xmlFile:getValue(entryKey .. "#isVisible", true), true)
                entry.isCompleted = RMS_Utils.normalizeBoolValue(savegame.xmlFile:getValue(entryKey .. "#isCompleted", true), true)

                entry.conditionData.year = savegame.xmlFile:getValue(condKey .. "#year", 0)
                entry.conditionData.operatingHours = savegame.xmlFile:getValue(condKey .. "#operatingHours", 0)
                entry.conditionData.age = savegame.xmlFile:getValue(condKey .. "#age", 0)
                entry.conditionData.condition = savegame.xmlFile:getValue(condKey .. "#condition", 1)
                entry.conditionData.service = savegame.xmlFile:getValue(condKey .. "#service", 1)
                entry.conditionData.reliability = savegame.xmlFile:getValue(condKey .. "#reliability", 1)
                entry.conditionData.maintainability = savegame.xmlFile:getValue(condKey .. "#maintainability", 1)
                entry.conditionData.systems = RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(savegame.xmlFile:getValue(condKey .. "#systems", "")))
                entry.conditionData.batterySoc = savegame.xmlFile:getValue(condKey .. "#batterySoc", 1)

                local bdStr = savegame.xmlFile:getValue(condKey .. "#activeBreakdowns", "")
                entry.conditionData.activeBreakdowns = RMS_Utils.deserializeBreakdowns(bdStr) or {}

                local selBdStr = savegame.xmlFile:getValue(condKey .. "#selectedBreakdowns", "")
                entry.conditionData.selectedBreakdowns = RMS_Utils.parseCsvList(selBdStr)

                entry.conditionData.activeEffects = RMS_Utils.deserializeEffectSnapshot(savegame.xmlFile:getValue(condKey .. "#activeEffects", ""))

                entry.conditionData.activeIndicators = {}
                local indicatorIds = RMS_Utils.parseCsvList(savegame.xmlFile:getValue(condKey .. "#activeIndicators", ""))
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
        if spec.currentState == nil then spec.currentState = RealisticMechanicalSystems.STATUS.READY end
        if spec.plannedState == nil then spec.plannedState = RealisticMechanicalSystems.STATUS.READY end
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
        duration = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION,
        startTime = 0,
        targetNode = nil,
        targetVehicle = nil
    }

    -- Sounds Loading
    local xmlSoundFile = loadXMLFile("rmsSounds", RealisticMechanicalSystems.modDirectory .. "sounds/rms_sounds.xml")
    if spec.samples == nil then
        spec.samples = {}
    end
    
    if xmlSoundFile ~= nil then
        local soundManager = g_soundManager
        local modDir = RealisticMechanicalSystems.modDirectory
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
        log_dbg("ERROR: RealisticMechanicalSystems - Could not load rms_sounds.xml")
    end

    spec.rawEngineTemperature = spec.engineTemperature
    spec.rawTransmissionTemperature = spec.transmissionTemperature

    spec.isElectricVehicle = getIsElectricVehicle(self)
    spec.isDieselVehicle = RMS_Preheat.isDieselVehicle(self)
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
        local spec = vehicle.spec_RealisticMechanicalSystems
        for _, systemData in pairs(spec.systems) do
            -- disable engine for electric vehicles
            if systemData.name == RealisticMechanicalSystems.SYSTEMS.ENGINE then
                if spec.isElectricVehicle then
                    systemData.enabled = false
                end
            -- disable transsmision for electric vehicles
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.TRANSMISSION then
                if spec.isElectricVehicle then
                    systemData.enabled = false
                end
            -- disable hydralic for trucks, cars, motorbikes
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.HYDRAULICS then
                local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
                local vtype = vehicle.type.name
                if storeItem.categoryName == "TRUCKS" or vtype == "car" or vtype == "carFillable" or vtype == "motorbike" then
                    systemData.enabled = false
                end
            -- disable cooling for trucks, cars, motorbikes
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.COOLING then
                if spec.isElectricVehicle then
                    systemData.enabled = false
                end
            -- electrical is  applicable for all vehicles
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.ELECTRICAL then
            -- chassis is applicable for all vehicles
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.CHASSIS  then
            --- disable fuel system for electric vehicles
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.FUEL then
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
    spec._lastSyncBreakdowns_serialized = RMS_Utils.serializeBreakdowns(spec.activeBreakdowns or {})
    --- [9] service
    spec._lastSyncServiceProgress_elapsed = spec.pendingProgressElapsedTime
    spec._lastSyncServiceProgress_step = spec.pendingProgressStepIndex
    spec._lastSyncServiceProgress_total = spec.pendingProgressTotalTime

    RMS_Electrical.initVoltagesFromSoc(self)

    self:recalculateAndApplyEffects()
end

function RealisticMechanicalSystems:onDelete()
    local spec = self.spec_RealisticMechanicalSystems

    if spec and spec.samples then
        g_soundManager:deleteSamples(spec.samples)
    end

    if RMS_Main and RMS_Main.vehicles and self.uniqueId and RMS_Main.vehicles[self.uniqueId] then
        if RMS_Main.previousKey == self.uniqueId then
            RMS_Main.previousKey = nil
        end
        RMS_Main.vehicles[self.uniqueId] = nil
        RMS_Main.numVehicles = RMS_Main.numVehicles - 1
    end
end
