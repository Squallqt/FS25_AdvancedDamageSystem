local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")
local hasCVTAddon = RMS_Utils.hasCVTAddon

-- ==========================================================
--                      HELPER FUNCTIONS
-- ==========================================================

local function hasEnteredPlayerInVehicleChain(rootVehicle)
    if rootVehicle == nil then
        return false
    end

    if rootVehicle.getIsEntered ~= nil and rootVehicle:getIsEntered() then
        return true
    end

    if rootVehicle.getChildVehicles ~= nil then
        for _, childVehicle in ipairs(rootVehicle:getChildVehicles()) do
            if childVehicle ~= nil and childVehicle.getIsEntered ~= nil and childVehicle:getIsEntered() then
                return true
            end
        end
    end

    return false
end

-- ==========================================================
--                       BREAKDOWNS
-- ==========================================================

local function buildGeneralWearBreakdown(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if not spec then
        return
    end

    local generalWearBreakdown = RMS_Utils.shallowCopy(RMS_Breakdowns.BreakdownRegistry.GENERAL_WEAR)
    local stage = RMS_Utils.shallowCopy(generalWearBreakdown.stages[1])
    stage.effects = {}
    generalWearBreakdown.stages = { stage }

    local effects = stage.effects
    local systems = RealisticMechanicalSystems.SYSTEMS

    for _, systemData in pairs(spec.systems) do
        local systemName = systemData.name
        local systemCondition = vehicle:getSystemConditionLevel(systemName)
        local effect = nil
        local isLateStage = systemCondition <= RMS_Config.CORE.GENERAL_WEAR_LATE_STAGE_THRESHOLD
        
        if systemData.enabled and systemCondition <= RMS_Config.CORE.GENERAL_WEAR_EARLY_STAGE_THRESHOLD  then
            
            --- ENGINE
            if systemName == systems.ENGINE then

                --- early stage
                effect = {
                    id = "ENGINE_TORQUE_MODIFIER",
                    value = function()
                        local baseEffect = -0.30
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end,
                    aggregation = "sum"
                }
                if effect ~= nil then table.insert(effects, effect) end

                --- oil smoke from engine wear
                effect = {
                    id = "EXHAUST_OIL",
                    value = function()
                        local baseEffect = 0.55
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 2
                        return baseEffect * multiplier
                    end,
                    aggregation = "max"
                }
                if effect ~= nil then table.insert(effects, effect) end

            --- TRANSMISSION
            elseif systemName == systems.TRANSMISSION then
                local motor = vehicle:getMotor()
                if not motor then return false end
                
                local isManual = motor.minForwardGearRatio == nil
                local isPowerShift = motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
                local isCvt = motor.minForwardGearRatio ~= nil

                --- early stage
                if isManual and hasCVTAddon(vehicle) then
                    effect = {
                        id = "TRANSMISSION_SLIP_EFFECT", 
                        value = function ()
                            local baseEffect = 0.30
                            local condition = systemCondition
                            local multiplier = (1 - condition) ^ 3
                            return baseEffect * multiplier
                        end, 
                        aggregation = "max"
                    }
                    if effect ~= nil then table.insert(effects, effect) end

                elseif isPowerShift and hasCVTAddon(vehicle) then
                    effect = { 
                        id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 
                        value = function ()
                            local baseEffect = 0.30
                            local condition = systemCondition
                            local multiplier = (1 - condition) ^ 3
                            return baseEffect * multiplier
                        end,
                        extraData = {timer = 0, status = "IDLE", duration = 1000, backup = 0}, 
                        aggregation = "max"
                    }
                    if effect ~= nil then table.insert(effects, effect) end

                elseif isCvt and not hasCVTAddon(vehicle) then
                    effect = { 
                        id = "CVT_MAX_RATIO_MODIFIER", 
                        value = function ()
                            local baseEffect = 0.30
                            local condition = systemCondition
                            local multiplier = (1 - condition) ^ 3
                            return baseEffect * multiplier
                        end,
                        aggregation = "max" 
                    }
                    if effect ~= nil then table.insert(effects, effect) end
                end

            --- HYDRAULIC
            elseif systemName == systems.HYDRAULICS then
                effect = {
                    id = "HYDRAULIC_SPEED_MODIFIER", 
                    value = function ()
                        local baseEffect = -0.30
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end,
                    aggregation = "min"
                }
                if effect ~= nil then table.insert(effects, effect) end
            
            --- FUEL
            elseif systemName == systems.FUEL then

                --- ealry stage
                effect = {
                    id = "FUEL_CONSUMPTION_MODIFIER", 
                    value = function ()
                        local baseEffect = 0.60
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end, 
                    aggregation = "sum" 
                }
                if effect ~= nil then table.insert(effects, effect) end

            --- CHASSIS
            elseif systemName == systems.CHASSIS then
                
                --- early stage
                effect = {
                    id = "BRAKE_FORCE_MODIFIER", 
                    value = function ()
                        local baseEffect = -0.60
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end,  
                    aggregation = "min",  
                    extraData = {timer = 0, soundPlayed = false}
                }
                if effect ~= nil then table.insert(effects, effect) end

                --- late stage
                effect = {
                    id = "STEERING_SENSITIVITY_MODIFIER", 
                    value = function ()
                        local baseEffect = 0.30
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end,   
                    aggregation = "max" 
                }
                if isLateStage and effect ~= nil then table.insert(effects, effect) end

            --- COOLING
            elseif systemName == systems.COOLING then
                
                --- early stage
                effect = {
                    id = "RADIATOR_HEALTH_MODIFIER", 
                    value = function ()
                        local baseEffect = -0.20
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end,  
                    aggregation = "min",  
                }
                if effect ~= nil then table.insert(effects, effect) end

            --- ELECTRICAL
            elseif systemName == systems.ELECTRICAL then

                --- early stage
                effect = {
                    id = "ALTERNATOR_HEALTH_MODIFIER", 
                    value = function ()
                        local baseEffect = -0.60
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end,   
                    aggregation = "min"
                }
                if effect ~= nil then table.insert(effects, effect) end

                effect = {
                    id = "BATTERY_HEALTH_MODIFIER", 
                    value = function ()
                        local baseEffect = -0.60
                        local condition = systemCondition
                        local multiplier = (1 - condition) ^ 3
                        return baseEffect * multiplier
                    end,  
                    aggregation = "min"
                }
                if effect ~= nil then table.insert(effects, effect) end

                --- late stage
                effect = {
                        id = "ENGINE_HARD_START_MODIFIER",
                        value = function ()
                        local baseEffect = 6
                            local condition = systemCondition
                            local multiplier = (1 - condition) ^ 3
                            return math.max(baseEffect * multiplier, 2)
                        end,  
                        aggregation = "max",
                        extraData = {timer = 0, status = 'IDLE'}
                }
                if isLateStage and effect ~= nil and effect.value() >= 2 then table.insert(effects, effect) end

            end 
        end
    end

    return generalWearBreakdown
end

local function getBreakdownDefinition(vehicle, breakdownId)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and spec.dynamicBreakdowns ~= nil and spec.dynamicBreakdowns[breakdownId] ~= nil then
        return spec.dynamicBreakdowns[breakdownId]
    end
    return RMS_Breakdowns.BreakdownRegistry[breakdownId]
end

function RealisticMechanicalSystems:tryTriggerBreakdown(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or dt == 0 then
        return
    end

    local probabilityData = RMS_Config.CORE.BREAKDOWN_PROBABILITIES
    local conditionEffectiveFloor = RMS_Config.CORE.CONDITION_EFFECTIVE_FLOOR or 0.15

    for systemName, systemData in pairs(spec.systems) do
        if systemData.name == RealisticMechanicalSystems.SYSTEMS.TRANSMISSION and hasCVTAddon(self) then
            -- skip transmission breakdowns if CVT addon is present
        else
            local systemCondition = math.max(systemData.condition or 1.0, 0.001)
            local effectiveCondition = math.max(systemCondition, conditionEffectiveFloor)
            local systemStress = math.max(systemData.stress or 0.0, 0.0)
            local stressThreshold = probabilityData.STRESS_THRESHOLD
            local hourlyProb = 0.0

            local stressRatio = math.max(systemStress / effectiveCondition, 0.0)
            if stressRatio >= stressThreshold then
                local failureChancePerFrame = RealisticMechanicalSystems.calculateBreakdownProbability(stressRatio, probabilityData, dt)
                hourlyProb = 1 - (1 - failureChancePerFrame) ^ (3600000 / dt)

                local random = math.random()
                if random < failureChancePerFrame or systemStress >= effectiveCondition then
                    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemData.name)
                    if systemKey == nil or systemKey == "" then
                        systemKey = string.lower(tostring(systemData.name or ""))
                    end

                    local breakdownId = self:getRandomBreakdownBySystem(systemKey)
                    if breakdownId ~= nil then
                        local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
                        if registryEntry ~= nil and registryEntry.stages ~= nil and #registryEntry.stages > 0 then
                            local criticalOutcomeChance = RMS_Utils.getCriticalFailureChance(systemCondition)
                            if math.random() < criticalOutcomeChance then
                                self:addBreakdown(breakdownId, #registryEntry.stages)
                            else
                                local stage = 1
                                if systemCondition <= RMS_Config.CORE.GENERAL_WEAR_LATE_STAGE_THRESHOLD then
                                    stage = 3
                                elseif systemCondition <= RMS_Config.CORE.GENERAL_WEAR_EARLY_STAGE_THRESHOLD then
                                    stage = 2
                                end
                                self:addBreakdown(breakdownId, stage)
                            end
                        end
                    else
                        local activeBreakdowns = self:getActiveBreakdowns()
                        local lowestStage = math.huge
                        local lowerStageBreakdownId = nil
                        local targetStage = nil

                        for activeBreakdownId, breakdownData in pairs(activeBreakdowns) do
                            if type(breakdownData) == "table" and breakdownData.isActive ~= false then
                                local registryEntry = getBreakdownDefinition(self, activeBreakdownId)
                                if registryEntry ~= nil and registryEntry.stages ~= nil and #registryEntry.stages > 0 then
                                    local breakdownSystem = registryEntry.system
                                    if type(breakdownSystem) == "string" and RealisticMechanicalSystems.SYSTEMS[breakdownSystem] ~= nil then
                                        breakdownSystem = RealisticMechanicalSystems.SYSTEMS[breakdownSystem]
                                    end

                                    local breakdownSystemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, breakdownSystem)
                                    if breakdownSystemKey == nil or breakdownSystemKey == "" then
                                        breakdownSystemKey = string.lower(tostring(breakdownSystem or ""))
                                    end

                                    local currentStage = math.max(math.floor(tonumber(breakdownData.stage) or 1), 1)
                                    local maxStage = #registryEntry.stages

                                    if breakdownSystemKey == systemKey and currentStage < maxStage and currentStage < lowestStage then
                                        lowestStage = currentStage
                                        lowerStageBreakdownId = activeBreakdownId
                                        targetStage = currentStage + 1
                                    end
                                end
                            end
                        end

                        if lowerStageBreakdownId ~= nil and targetStage ~= nil then
                            self:changeBreakdownStage(lowerStageBreakdownId, targetStage)
                            log_dbg(string.format(
                                "Increased stage of existing breakdown [%s] to stage %d for system=%s",
                                tostring(lowerStageBreakdownId),
                                tonumber(targetStage) or 0,
                                tostring(systemKey)
                            ))
                        end
                    end

                    systemData.stress = systemStress * RMS_Config.CORE.STRESS_COOLDOWN
                    systemStress = math.max(systemData.stress or 0.0, 0.0)

                    local cooledStressRatio = math.max(systemStress / effectiveCondition, 0.0)
                    if cooledStressRatio >= stressThreshold then
                        local cooledFailureChancePerFrame = RealisticMechanicalSystems.calculateBreakdownProbability(cooledStressRatio, probabilityData, dt)
                        hourlyProb = 1 - (1 - cooledFailureChancePerFrame) ^ (3600000 / dt)
                    else
                        hourlyProb = 0.0
                    end
                end
            end

            if RMS_Config.DEBUG and spec.debugData[systemName] ~= nil then
                local criticalChance = math.clamp((1 - systemCondition) ^ probabilityData.CRITICAL_DEGREE, probabilityData.CRITICAL_MIN, probabilityData.CRITICAL_MAX)
                spec.debugData[systemName].breakdownProbability = hourlyProb
                spec.debugData[systemName].critBreakdownProbability = criticalChance
            end
        end
    end
end

function RealisticMechanicalSystems:getRandomBreakdown()
    if not self.spec_RealisticMechanicalSystems then
        return nil
    end

    local activeBreakdowns = self:getActiveBreakdowns()
    local applicableBreakdowns = {}
    local totalProbability = 0

    for id, breakdownData in pairs(RMS_Breakdowns.BreakdownRegistry) do
        if not activeBreakdowns[id] and breakdownData.isSelectable then
            local isApplicable = true
            if breakdownData.isApplicable ~= nil then
                isApplicable = breakdownData.isApplicable(self)
            end

            if isApplicable then
                local probability = 1.0 
                if breakdownData.probability ~= nil then
                    probability = breakdownData.probability(self)
                end

                if probability > 0 then
                    table.insert(applicableBreakdowns, {id = id, probability = probability})
                    totalProbability = totalProbability + probability
                end
            end
        end
    end

    if #applicableBreakdowns == 0 or totalProbability <= 0 then
        return nil
    end

    local randomNumber = math.random() * totalProbability

    local cumulativeProbability = 0
    for _, breakdown in ipairs(applicableBreakdowns) do
        cumulativeProbability = cumulativeProbability + breakdown.probability
        if randomNumber <= cumulativeProbability then
            return breakdown.id
        end
    end
    return nil
end

function RealisticMechanicalSystems:getRandomBreakdownBySystem(systemName)
    if not self.spec_RealisticMechanicalSystems then
        return nil
    end

    local spec = self.spec_RealisticMechanicalSystems

    if systemName == nil then
        return nil
    end

    local targetSystem = systemName
    if type(targetSystem) == "string" and RealisticMechanicalSystems.SYSTEMS[targetSystem] ~= nil then
        targetSystem = RealisticMechanicalSystems.SYSTEMS[targetSystem]
    end

    local targetSystemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, targetSystem)
    if targetSystemKey == nil or targetSystemKey == "" then
        targetSystemKey = string.lower(tostring(targetSystem))
    end
    local targetSystemData = spec.systems[targetSystemKey]
    if type(targetSystemData) ~= "table" then
        return nil
    end

    local activeBreakdowns = self:getActiveBreakdowns()
    local applicableBreakdowns = {}
    local totalProbability = 0

    for id, breakdownData in pairs(RMS_Breakdowns.BreakdownRegistry) do
        local breakdownSystem = breakdownData.system
        if type(breakdownSystem) == "string" and RealisticMechanicalSystems.SYSTEMS[breakdownSystem] ~= nil then
            breakdownSystem = RealisticMechanicalSystems.SYSTEMS[breakdownSystem]
        end

        local breakdownSystemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, breakdownSystem)
        if breakdownSystemKey == nil or breakdownSystemKey == "" then
            breakdownSystemKey = string.lower(tostring(breakdownSystem or ""))
        end

        if not activeBreakdowns[id] and breakdownData.isSelectable and breakdownSystemKey == targetSystemKey then
            local isApplicable = true
            if breakdownData.isApplicable ~= nil then
                isApplicable = breakdownData.isApplicable(self)
            end

            if isApplicable then
                local probability = 1.0 
                if breakdownData.probability ~= nil then
                    probability = breakdownData.probability(self)
                end

                if probability > 0 then
                    table.insert(applicableBreakdowns, {id = id, probability = probability})
                    totalProbability = totalProbability + probability
                    log_dbg(string.format(
                        "Breakdown candidate [%s] system=%s weight=%.6f",
                        tostring(id),
                        tostring(targetSystemKey),
                        tonumber(probability) or 0
                    ))
                end
            end
        end
    end

    if #applicableBreakdowns == 0 or totalProbability <= 0 then
        log_dbg(string.format(
            "Breakdown selection skipped for system=%s candidates=%d totalWeight=%.6f",
            tostring(targetSystemKey),
            #applicableBreakdowns,
            tonumber(totalProbability) or 0
        ))
        return nil
    end

    local randomNumber = math.random() * totalProbability
    log_dbg(string.format(
        "Breakdown selection random system=%s random=%.6f totalWeight=%.6f",
        tostring(targetSystemKey),
        tonumber(randomNumber) or 0,
        tonumber(totalProbability) or 0
    ))

    local cumulativeProbability = 0
    for _, breakdown in ipairs(applicableBreakdowns) do
        cumulativeProbability = cumulativeProbability + breakdown.probability
        log_dbg(string.format(
            "Breakdown roll [%s] cumulative=%.6f threshold=%.6f",
            tostring(breakdown.id),
            tonumber(cumulativeProbability) or 0,
            tonumber(randomNumber) or 0
        ))
        if randomNumber <= cumulativeProbability then
            log_dbg(string.format(
                "Breakdown selected [%s] system=%s random=%.6f cumulative=%.6f",
                tostring(breakdown.id),
                tostring(targetSystemKey),
                tonumber(randomNumber) or 0,
                tonumber(cumulativeProbability) or 0
            ))
            return breakdown.id
        end
    end

    log_dbg(string.format(
        "Breakdown selection fell through system=%s random=%.6f totalWeight=%.6f",
        tostring(targetSystemKey),
        tonumber(randomNumber) or 0,
        tonumber(totalProbability) or 0
    ))
    return nil
end

function RealisticMechanicalSystems:addBreakdown(breakdownId, stageOrOptions)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec then return end

    local options
    if type(stageOrOptions) == "table" then
        options = stageOrOptions
    else
        options = {
            stage = stageOrOptions,
            isActive = true,
        }
    end

    local activeBreakdowns = self:getActiveBreakdowns()
    local breakdownRegistry = RMS_Breakdowns ~= nil and RMS_Breakdowns.BreakdownRegistry or nil
    if breakdownRegistry == nil then
        log_dbg("addBreakdown skipped: BreakdownRegistry is nil for id:", tostring(breakdownId))
        return
    end
    
    local activeBreakdownsCount = 0
    for _, breakdownData in pairs(activeBreakdowns) do
        if type(breakdownData) == "table" and breakdownData.isActive ~= false then
            activeBreakdownsCount = activeBreakdownsCount + 1
        end
    end

    local registryEntry = breakdownRegistry[breakdownId]
    if registryEntry == nil then
        log_dbg("addBreakdown skipped: unknown breakdown id:", tostring(breakdownId))
        return
    end

    if activeBreakdownsCount >= RMS_Config.CORE.CONCURRENT_BREAKDOWN_LIMIT_PER_VEHICLE and registryEntry.isSelectable then
        return nil 
    end

    if self:hasBreakdown(breakdownId) then
        return
    end

    local currentIsActive = false
    if options.isActive == nil then
        currentIsActive = true
    else
        currentIsActive = options.isActive
    end

    local resumeTimer = math.max(tonumber(options.resumeTimer) or 0, 0)
    if not currentIsActive and resumeTimer <= 0 then
        local serviceScale = RMS_Config.CORE.REFERENCE_SERVICE_WEAR / RMS_Config.CORE.BASE_SERVICE_WEAR
        resumeTimer = RMS_Config.CORE.REPEAT_BREAKDOWN_TIME * serviceScale * (math.random() + 0.5)
    end

    spec.activeBreakdowns[breakdownId] = {
        stage = math.max(math.floor(tonumber(options.stage) or 1), 1),
        progressTimer = math.max(tonumber(options.progressTimer) or 0, 0),
        isVisible = RMS_Utils.normalizeBoolValue(options.isVisible, false),
        isSelectedForRepair = RMS_Utils.normalizeBoolValue(options.isSelectedForRepair, true),
        isActive = currentIsActive,
        resumeTimer = resumeTimer,
        source = options.source or RealisticMechanicalSystems.BREAKDOWN_SOURCES.RANDOM
    }
    
    self:recalculateAndApplyEffects()

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
end

function RealisticMechanicalSystems:suspendBreakdown(breakdownId, resumeTimer)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns then
        return
    end

    local breakdown = spec.activeBreakdowns[breakdownId]
    if breakdown == nil then
        return
    end

    breakdown.isActive = false
    breakdown.resumeTimer = math.max(tonumber(resumeTimer) or 0, 0)
    breakdown.source = RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX

    self:recalculateAndApplyEffects()

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
end

function RealisticMechanicalSystems:removeBreakdown(...)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return
    end
    
    local idsToRemove = {...}

    if #idsToRemove == 0 then
        spec.activeBreakdowns = {}
        self:recalculateAndApplyEffects()
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
        return
    end

    local removedCount = 0
    for _, id in ipairs(idsToRemove) do
        if spec.activeBreakdowns[id] then
            spec.activeBreakdowns[id] = nil
            removedCount = removedCount + 1
        end
    end
    
    if removedCount > 0 then
        self:recalculateAndApplyEffects()
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

function RealisticMechanicalSystems:hasBreakdown(breakdownId)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return false
    end

    if breakdownId == nil then
        for activeBreakdownId, _ in pairs(spec.activeBreakdowns) do
            local breakdownDef = RMS_Breakdowns.BreakdownRegistry[activeBreakdownId]
            if breakdownDef ~= nil and breakdownDef.isSelectable == true then
                return true
            end
        end

        return false
    end

    return spec.activeBreakdowns[breakdownId] ~= nil
end

function RealisticMechanicalSystems:hasEffect(effectId)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeEffects or next(spec.activeEffects) == nil then
        return false
    end

    if effectId == nil then
        return next(spec.activeEffects) ~= nil
    end

    return spec.activeEffects[effectId] ~= nil
end

function RealisticMechanicalSystems:hasSystemBreakdowns(system)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return false
    end

    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system)
    if systemKey == nil or systemKey == "" then
        systemKey = type(system) == "string" and string.lower(system) or ""
    end

    if systemKey == "" then
        return false
    end

    for breakdownId, _ in pairs(spec.activeBreakdowns) do
        local registryBreakdown = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if registryBreakdown ~= nil then
            local breakdownSystemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, registryBreakdown.system)
            if breakdownSystemKey == systemKey then
                return true
            end
        end
    end

    return false
end

function RealisticMechanicalSystems:changeBreakdownStage(breakdownId, targetStageOrReverse)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil or spec.activeBreakdowns[breakdownId] == nil then
        return
    end
    
    local registryBreakdown = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    local breakdown = spec.activeBreakdowns[breakdownId]
    if registryBreakdown == nil or registryBreakdown.stages == nil or #registryBreakdown.stages == 0 then
        return
    end

    local currentStage = math.max(math.floor(tonumber(breakdown.stage) or 1), 1)
    local targetStage = currentStage + 1

    if type(targetStageOrReverse) == "boolean" then
        if targetStageOrReverse then
            targetStage = currentStage - 1
        end
    elseif type(targetStageOrReverse) == "number" then
        targetStage = math.floor(targetStageOrReverse)
    end

    targetStage = math.min(math.max(targetStage, 1), #registryBreakdown.stages)

    if targetStage ~= currentStage then
        breakdown.stage = targetStage
        self:recalculateAndApplyEffects()

        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

function RealisticMechanicalSystems:processBreakdowns(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return
    end

    local C = RMS_Config.CORE
    local effectsNeedRecalculation = false

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[id]

        if registryEntry then
            breakdown.isActive = breakdown.isActive ~= false
            breakdown.resumeTimer = math.max(tonumber(breakdown.resumeTimer) or 0, 0)

            if not breakdown.isActive then
                if breakdown.resumeTimer > 0 then
                    breakdown.resumeTimer = math.max(breakdown.resumeTimer - dt, 0)
                end

                if breakdown.resumeTimer <= 0 then
                    breakdown.resumeTimer = 0
                    breakdown.isActive = true
                    effectsNeedRecalculation = true
                end
            elseif registryEntry.stages[breakdown.stage] then
                local stageData = registryEntry.stages[breakdown.stage]
                
                if stageData.progressMultiplier and stageData.progressMultiplier > 0 then
                    
                    local canProgress = true
                    if registryEntry.isCanProgress ~= nil then
                        canProgress = registryEntry.isCanProgress(self)
                    end

                    if canProgress then
                        breakdown.progressTimer = breakdown.progressTimer or 0
                        breakdown.progressTimer = breakdown.progressTimer + dt
                        
                        local serviceScale = C.REFERENCE_SERVICE_WEAR / C.BASE_SERVICE_WEAR
                        local stageDuration = C.BASE_BREAKDOWN_PROGRESS_TIME * stageData.progressMultiplier * serviceScale

                        if breakdown.progressTimer >= stageDuration then
                            local maxStages = #registryEntry.stages
                            
                            if breakdown.stage < maxStages then
                                breakdown.stage = breakdown.stage + 1
                                breakdown.progressTimer = 0
                                effectsNeedRecalculation = true

                                if breakdown.stage == maxStages and registryEntry.stages[breakdown.stage].detectionChance > 0 then
                                    breakdown.isVisible = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if effectsNeedRecalculation then
        self:recalculateAndApplyEffects()

        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

function RealisticMechanicalSystems:processGeneralWearBreakdown()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not self.isServer then
        return
    end

    local generalWearId = "GENERAL_WEAR"

    if not RMS_Config.CORE.GENERAL_WEAR_ENABLED then
        if self:hasBreakdown(generalWearId) then
            self:removeBreakdown(generalWearId)
        end
        return
    end

    local isGeneralWearShouldBe = false
    local needToRecalculate = math.abs(self:getConditionLevel() - spec._prevConditionLevel) > RMS_Config.CORE.BASE_SYSTEMS_WEAR / 5
    
    for _, systemData in pairs(spec.systems) do
        if systemData.enabled and systemData.condition <= RMS_Config.CORE.GENERAL_WEAR_EARLY_STAGE_THRESHOLD  then
            isGeneralWearShouldBe = true
        end
    end
    if isGeneralWearShouldBe and not self:hasBreakdown(generalWearId) then
        self:addBreakdown(generalWearId)
        spec._prevConditionLevel = self:getConditionLevel()
        return
    elseif not isGeneralWearShouldBe and self:hasBreakdown(generalWearId) then
        self:removeBreakdown(generalWearId)
        spec._prevConditionLevel = self:getConditionLevel()
        return
    end

    if needToRecalculate and isGeneralWearShouldBe then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
        self:recalculateAndApplyEffects()
        spec._prevConditionLevel = self:getConditionLevel()
    end
end

function RealisticMechanicalSystems:recalculateAndApplyEffects()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec then return end

    if spec.isExcludedVehicle then
        spec.dynamicBreakdowns.GENERAL_WEAR = nil
        local previouslyActiveEffects = spec.activeEffects or {}
        spec.activeEffects = {}

        for effectId, applicator in pairs(RMS_Breakdowns.EffectApplicators) do
            if previouslyActiveEffects[effectId] ~= nil and applicator.remove then
                applicator.remove(self, applicator)
            end
        end

        self:recalculateAndApplyIndicators()
        return
    end

    if self:hasBreakdown("GENERAL_WEAR") then
        spec.dynamicBreakdowns.GENERAL_WEAR = buildGeneralWearBreakdown(self)
    else
        spec.dynamicBreakdowns.GENERAL_WEAR = nil
    end

    local previouslyActiveEffects = spec.activeEffects or {}
    local aggregatedEffects = {}
    local unknownBreakdownIds = {}

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = getBreakdownDefinition(self, id)

        if registryEntry == nil then
            table.insert(unknownBreakdownIds, id)
        elseif breakdown.isActive ~= false and registryEntry.stages[breakdown.stage] then
            local stageData = registryEntry.stages[breakdown.stage]

            if stageData.effects then
                for _, effectData in ipairs(stageData.effects) do
                    local effectId = effectData.id
                    local strategy = effectData.aggregation or "sum"

                    local newValue
                    if type(effectData.value) == 'function' then
                        newValue = effectData.value(self)
                    else
                        newValue = effectData.value
                    end

                    local existingEffect = aggregatedEffects[effectId]

                    if existingEffect == nil then
                        local newEffect = RMS_Utils.deepCopy(effectData)
                        newEffect.value = newValue
                        aggregatedEffects[effectId] = newEffect
                    else
                        if strategy == "sum" then
                            if math.abs(newValue) > math.abs(existingEffect.value) then
                                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
                            end
                            existingEffect.value = existingEffect.value + newValue

                        elseif strategy == "multiply" then
                            if math.abs(newValue - 1) > math.abs(existingEffect.value - 1) then
                                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
                            end
                            existingEffect.value = existingEffect.value * newValue

                        elseif strategy == "min" then
                            if newValue < existingEffect.value then
                                existingEffect.value = newValue
                                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
                            end

                        elseif strategy == "max" then
                            if newValue > existingEffect.value then
                                existingEffect.value = newValue
                                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
                            end

                        elseif strategy == "boolean_or" then
                            local wasActive = existingEffect.value ~= nil and existingEffect.value ~= false and existingEffect.value ~= 0
                            local isActive = newValue ~= nil and newValue ~= false and newValue ~= 0
                            existingEffect.value = existingEffect.value or newValue

                            if isActive then
                                if effectId == "ENGINE_FAILURE" then
                                    local newExtraData = RMS_Utils.deepCopy(effectData.extraData)

                                    if existingEffect.extraData == nil then
                                        existingEffect.extraData = newExtraData
                                    elseif newExtraData ~= nil then
                                        local existingStarter = existingEffect.extraData.starter == true
                                        local newStarter = newExtraData.starter == true

                                        if existingStarter and not newStarter then
                                            existingEffect.extraData = newExtraData
                                        else
                                            existingEffect.extraData.starter = existingStarter or newStarter

                                            if existingEffect.extraData.message == nil and newExtraData.message ~= nil then
                                                existingEffect.extraData.message = newExtraData.message
                                            end
                                            if existingEffect.extraData.reason == nil and newExtraData.reason ~= nil then
                                                existingEffect.extraData.reason = newExtraData.reason
                                            end
                                            if newExtraData.disableAi == true then
                                                existingEffect.extraData.disableAi = true
                                            end
                                        end
                                    end
                                elseif isActive and not wasActive then
                                    existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #unknownBreakdownIds > 0 then
        for _, unknownId in ipairs(unknownBreakdownIds) do
            spec.activeBreakdowns[unknownId] = nil
        end
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end

    spec.activeEffects = aggregatedEffects

    for effectId, applicator in pairs(RMS_Breakdowns.EffectApplicators) do
        local isCurrentlyActive = spec.activeEffects[effectId] ~= nil
        local wasPreviouslyActive = previouslyActiveEffects[effectId] ~= nil

        if isCurrentlyActive then
            if applicator.apply then
                applicator.apply(self, spec.activeEffects[effectId], applicator)
            end

            if self.isClient and not wasPreviouslyActive then
                local currentEffect = spec.activeEffects[effectId]
                local rootVehicle = self.rootVehicle or self
                local hasEnteredPlayer = hasEnteredPlayerInVehicleChain(rootVehicle)

                if currentEffect ~= nil
                        and currentEffect.extraData ~= nil
                        and currentEffect.extraData.message ~= nil
                        and not hasEnteredPlayer then
                    spec.pendingSideNotifications = spec.pendingSideNotifications or {}
                    table.insert(spec.pendingSideNotifications, g_i18n:getText(currentEffect.extraData.message))
                end
            end
        elseif wasPreviouslyActive then
            if applicator.remove then
                applicator.remove(self, applicator)
            end
        end
    end
    
    self:recalculateAndApplyIndicators()
end

function RealisticMechanicalSystems:recalculateAndApplyIndicators()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec then return end

    spec.activeIndicators = {} 
    if spec.isExcludedVehicle then return end

    local aggregatedIndicatorData = {} 

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[id]
        if registryEntry and registryEntry.stages[breakdown.stage] then
            local stageData = registryEntry.stages[breakdown.stage]

            if stageData.indicators then
                for _, indicatorDef in ipairs(stageData.indicators) do
                    local id = indicatorDef.id
                    
                    if aggregatedIndicatorData[id] == nil then
                        aggregatedIndicatorData[id] = {
                            color = indicatorDef.color,
                            switchOnConditions = {},
                            switchOffConditions = {},
                            blinkWhileActive = false
                        }
                    end

                    local currentData = aggregatedIndicatorData[id]

                    local newPriority = RMS_Breakdowns.COLOR_PRIORITY[indicatorDef.color] or 0
                    local existingPriority = RMS_Breakdowns.COLOR_PRIORITY[currentData.color] or 0
                    
                    if newPriority > existingPriority then
                        currentData.color = indicatorDef.color
                    end

                    if indicatorDef.switchOn then
                        table.insert(currentData.switchOnConditions, indicatorDef.switchOn)
                    end
                    if indicatorDef.switchOff then
                        table.insert(currentData.switchOffConditions, indicatorDef.switchOff)
                    end
                    currentData.blinkWhileActive = currentData.blinkWhileActive or indicatorDef.blinkWhileActive == true
                end
            end
        end
    end

    for id, data in pairs(aggregatedIndicatorData) do
        local finalIndicator = {
            color = data.color,
            isActive = false,
            blinkWhileActive = data.blinkWhileActive,
        }

        finalIndicator.switchOn = function(vehicle)
            for _, condition in ipairs(data.switchOnConditions) do
                local result = false
                if type(condition) == 'function' then
                    result = condition(vehicle)
                elseif type(condition) == 'boolean' then
                    result = condition
                end
                
                if result then
                    return true
                end
            end
            return false
        end

        finalIndicator.switchOff = function(vehicle)
            for _, condition in ipairs(data.switchOffConditions) do
                local result = false
                if type(condition) == 'function' then
                    result = condition(vehicle)
                elseif type(condition) == 'boolean' then
                    result = condition
                end
                
                if result then
                    return true
                end
            end
            return false
        end

        spec.activeIndicators[id] = finalIndicator
    end
end
