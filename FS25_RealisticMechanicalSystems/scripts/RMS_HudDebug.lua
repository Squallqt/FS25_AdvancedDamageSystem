-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Debug HUD pages, showing the live simulation values of the active vehicle

local hasCVTTransmission = RMS_Utils.hasCVTTransmission
local hasCVTAddon = RMS_Utils.hasCVTAddon


---Draws the prebuilt debug lines of the active vehicle
-- @param table cache prebuilt debug lines
function RMS_Hud:renderActiveVehicleDebugCache(cache)
    if cache == nil then
        return
    end

    local panel = cache.panel
    if panel ~= nil then
        local color = panel.color or {0, 0, 0, 0.7}
        self:drawPanelBackground(
            panel.x,
            panel.y,
            panel.width,
            panel.height,
            color
        )
    end

    local commands = cache.commands
    if commands == nil or #commands == 0 then
        return
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)

    local lastBold = nil
    for _, command in ipairs(commands) do
        local isBold = command.bold == true
        if lastBold ~= isBold then
            setTextBold(isBold)
            lastBold = isBold
        end

        local color = command.color or {1, 1, 1, 1}
        setTextColor(color[1], color[2], color[3], color[4] or 1)
        renderText(command.x, command.y, command.size, command.text or "")
    end

    if lastBold then
        setTextBold(false)
    end

    setTextColor(1, 1, 1, 1)
end

---Builds and draws the debug panel of the active vehicle
function RMS_Hud:drawActiveVehicleHUD()
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motor = vehicle:getMotor()
    if motor == nil then
        return
    end

    local panel = self.activeVehicleDebugPanel
    local debugSnapshot = nil
    if not vehicle.isServer then
        RMS_DebugSnapshot.request(vehicle)
        debugSnapshot = RMS_DebugSnapshot.get(vehicle)
        if debugSnapshot == nil then
            local statusHeight = 0.075
            self:drawPanelBackground(panel.x, panel.y, panel.width, statusHeight, {0, 0, 0, 0.7})
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
            setTextBold(true)
            setTextColor(1, 1, 1, 1)
            renderText(
                panel.x + panel.padding,
                panel.y + statusHeight - panel.padding,
                self.text.headerSize,
                vehicle:getFullName() .. " | Waiting for server debug snapshot..."
            )
            setTextBold(false)
            return
        end
    end

    local debugData = vehicle.isServer and (spec.debugData or {}) or (debugSnapshot.debugData or {})
    local factorStatsSource = vehicle.isServer and (spec.factorStats or {}) or (debugSnapshot.factorStats or {})
    local debugState = not vehicle.isServer and (debugSnapshot.state or {}) or {}

    ---Returns a debug value, the stored one when the live one is unavailable
    -- @param string key debug value key
    -- @param any liveValue value read from the vehicle
    -- @return any value value to display
    local function getDebugStateValue(key, liveValue)
        if vehicle.isServer then
            return liveValue
        end
        local snapshotValue = debugState[key]
        if snapshotValue == nil then
            return liveValue
        end
        return snapshotValue
    end

    local cache = self.activeVehicleDebugCache
    local now = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
    if cache.vehicle == vehicle and cache.commands ~= nil and (now - (cache.lastUpdateTime or 0)) < (cache.refreshIntervalMs or 100) then
        self:renderActiveVehicleDebugCache(cache)
        return
    end

    local textSettings = self.text
    local fontStep = 0.001
    local activeHeaderSize = textSettings.headerSize + fontStep
    local activeNormalSize = textSettings.normalSize + fontStep
    local activeLineHeight = panel.lineHeight + fontStep
    local sectionGap = activeLineHeight * 0.65

    if RMS_Hud.debugViewMode == "factorStats" then
        self:drawFactorStatsVehicleHUD(
            vehicle,
            spec,
            debugData,
            factorStatsSource,
            panel,
            activeHeaderSize,
            activeNormalSize,
            activeLineHeight,
            sectionGap
        )
        return
    end

    local queuedCommands = {}

    ---Queues one text to draw at a position
    -- @param float x x position
    -- @param float y y position
    -- @param float size text size
    -- @param string text text to draw
    -- @param table? color rgba channels
    -- @param boolean? isBold true for bold text
    local function queueText(x, y, size, text, color, isBold)
        table.insert(queuedCommands, {
            x = x,
            y = y,
            size = size,
            text = text,
            color = color or {1, 1, 1, 1},
            bold = isBold == true
        })
    end

    ---Appends one line to a debug section
    -- @param table target section lines
    -- @param string text line text
    -- @param table? color rgba channels
    -- @param float? sizeScale text size scale
    local function addLine(target, text, color, sizeScale)
        table.insert(target, {
            text = text,
            color = color or {1, 1, 1, 1},
            sizeScale = sizeScale or 1.0
        })
    end

    ---Cuts a line into as many lines as its width needs, continuations carry a hanging indent
    -- @param string text line text
    -- @param float size text size
    -- @param float maxWidth width available inside the card
    -- @return table parts one entry per drawn line
    local function wrapLineToWidth(text, size, maxWidth)
        if maxWidth <= 0 or getTextWidth(size, text) <= maxWidth then
            return {text}
        end

        local parts = {}
        local indent = ""
        local current = nil

        for word in string.gmatch(text, "%S+") do
            local candidate = (current == nil) and (indent .. word) or (current .. " " .. word)
            if current ~= nil and getTextWidth(size, candidate) > maxWidth then
                table.insert(parts, current)
                indent = "  "
                current = indent .. word
            else
                current = candidate
            end
        end

        if current ~= nil then
            table.insert(parts, current)
        end

        return parts
    end

    ---Returns the colour of a temperature
    -- @param float? temp temperature in degrees
    -- @return table color rgba channels
    local function getTempColor(temp)
        if temp > 105 then
            return {1, 0.6, 0.6, 1}
        elseif temp > 95 then
            return {1, 1, 0.6, 1}
        end

        return {0.6, 0.8, 1, 1}
    end

    ---Packs several entries onto as few lines as the limit allows
    -- @param table entries entries to pack
    -- @param integer maxPerLine entries allowed on one line
    -- @param table? color rgba channels
    -- @param float? sizeScale text size scale
    -- @return table lines packed lines
    local function packEntries(entries, maxPerLine, color, sizeScale)
        local lines = {}
        if #entries == 0 then
            addLine(lines, "None", color, sizeScale)
            return lines
        end

        local lineEntries = {}
        for i, entry in ipairs(entries) do
            table.insert(lineEntries, entry)
            if #lineEntries >= maxPerLine or i == #entries then
                addLine(lines, table.concat(lineEntries, ", "), color, sizeScale)
                lineEntries = {}
            end
        end

        return lines
    end

    ---Renders a list as a comma separated string
    -- @param table? list values to render
    -- @return string text rendered list
    local function listToString(list)
        if list == nil or #list == 0 then
            return "-"
        end

        return table.concat(list, ",")
    end

    ---Builds the display entries of a pending stress transition, from its start to its target
    -- @param table? startMap value at the start of the service
    -- @param table? targetMap value at the end of the service
    -- @param function currentValueGetter returns the value of a system now
    -- @param function formatter formats one value
    -- @return table entries display entries
    local function buildPendingSystemTransitionEntries(startMap, targetMap, currentValueGetter, formatter)
        local entries = {}
        startMap = startMap or {}
        targetMap = targetMap or {}

        for systemKey, startValue in pairs(startMap) do
            local targetValue = targetMap[systemKey]
            if targetValue ~= nil then
                local currentValue = currentValueGetter(systemKey)
                table.insert(entries, string.format(
                    "%s: %s->%s (cur %s)",
                    tostring(systemKey),
                    formatter(startValue),
                    formatter(targetValue),
                    formatter(currentValue)
                ))
            end
        end

        table.sort(entries)
        return entries
    end

    ---Localizes a debug value when it is an l10n key
    -- @param any value value to localize
    -- @return string text displayable text
    local function localizeDebugValue(value)
        if value == nil then
            return "-"
        end

        if type(value) == "boolean" then
            local key = value and "rms_ws_option_yes" or "rms_ws_option_no"
            if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
                return g_i18n:getText(key)
            end
            return tostring(value)
        end

        local key = tostring(value)
        if key == "" then
            return "-"
        end

        if g_i18n ~= nil and g_i18n.hasText ~= nil then
            if g_i18n:hasText(key) then
                return g_i18n:getText(key)
            end
            return key
        end

        return key
    end

    ---Returns the colour of a condition factor
    -- @param float? value factor value
    -- @return table color rgba channels
    local function getConditionFactorColor(value)
        local v = math.max(value or 0, 0)
        local green = {0.72, 1.0, 0.72, 1}
        local yellow = {1.0, 1.0, 0.62, 1}
        local red = {1.0, 0.62, 0.62, 1}

        if v <= 0.01 then
            local t = math.max(math.min(v / 0.01, 1), 0)
            return {
                green[1] + (yellow[1] - green[1]) * t,
                green[2] + (yellow[2] - green[2]) * t,
                green[3] + (yellow[3] - green[3]) * t,
                1
            }
        end

        local t = math.max(math.min((v - 0.01) / 0.01, 1), 0)
        return {
            yellow[1] + (red[1] - yellow[1]) * t,
            yellow[2] + (red[2] - yellow[2]) * t,
            yellow[3] + (red[3] - yellow[3]) * t,
            1
        }
    end

    ---Returns the readable name of a breakdown source
    -- @param integer? source breakdown source
    -- @return string label source name
    local function getBreakdownSourceLabel(source)
        if source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
            return "PARTS"
        elseif source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX then
            return "QFIX"
        end
        return "RAND"
    end

    local breakdownEntries = {}
    if spec.activeBreakdowns and next(spec.activeBreakdowns) ~= nil then
        for id, breakdown in pairs(spec.activeBreakdowns) do
            local visible = breakdown.isVisible and "V" or "-"
            local selected = breakdown.isSelectedForRepair and "S" or "-"
            local active = breakdown.isActive ~= false and "A" or "-"
            local resumeTimerS = math.max((tonumber(breakdown.resumeTimer) or 0) / 1000, 0)
            local source = getBreakdownSourceLabel(breakdown.source)
            local stage = tonumber(breakdown.stage) or 0
            local progressTimerS = math.max((tonumber(breakdown.progressTimer) or 0) / 1000, 0)

            table.insert(breakdownEntries, string.format(
                "%s[st:%d|pr:%.0fs|rs:%.0fs|%s%s%s|src:%s]",
                id,
                stage,
                progressTimerS,
                resumeTimerS,
                visible,
                selected,
                active,
                source
            ))
        end
    end
    table.sort(breakdownEntries)
    local breakdownLines = packEntries(breakdownEntries, 4, {1, 0.8, 0.8, 1}, 0.95)

    local effectEntries = {}
    if spec.activeEffects and next(spec.activeEffects) ~= nil then
        for id, effect in pairs(spec.activeEffects) do
            table.insert(effectEntries, string.format("%s:%.2f", id, effect.value))
        end
    end
    table.sort(effectEntries)
    local effectLines = packEntries(effectEntries, 4, {0.8, 0.8, 1, 1}, 0.95)

    local aiCruiseLines = {}
    if vehicle:getIsAIActive() and debugData.aiWorker then
        local dbg = debugData.aiWorker
        local pidState = spec.aiWorkerPid or {}
        local cruiseSpeed = vehicle:getCruiseControlSpeed() or 0
        local ccState = vehicle:getCruiseControlState() or 0

        addLine(aiCruiseLines, string.format(
            "cc: %.1f (s:%d) | stress: %.3f (f: %.3f | l/e/t: %.3f/%.3f/%.3f) | e/i/d: %.3f/%.3f/%.3f | red: %.2f | base/tgt/app: %.1f/%.1f/%.1f | t: %.0fms",
            cruiseSpeed,
            ccState,
            dbg.stress or 0,
            dbg.filteredStress or 0,
            dbg.loadStress or 0,
            dbg.engineStress or 0,
            dbg.transStress or 0,
            dbg.error or 0,
            dbg.integral or 0,
            dbg.derivative or 0,
            dbg.reduction or 0,
            dbg.baseCruiseSpeed or 0,
            dbg.targetSpeed or 0,
            dbg.appliedSpeed or 0,
            getDebugStateValue("aiWorkerApplyTimer", pidState.applyTimer or 0)
        ), {0.75, 1, 0.85, 1}, 0.95)
    end

    local bcw = RMS_Config.CORE.BASE_SYSTEMS_WEAR

    ---Formats a ratio as a percentage
    -- @param float? value ratio
    -- @return string text formatted percentage
    local function asPercent(value)
        return (value or 0) * 100
    end

    ---Formats an applied multiplier
    -- @param float? value multiplier
    -- @return string text formatted multiplier
    local function formatAppliedMultiplier(value)
        local formatted = string.format("%.2f", tonumber(value) or 0)
        formatted = formatted:gsub("(%..-)0+$", "%1")
        formatted = formatted:gsub("%.$", "")
        return "x" .. formatted
    end

    ---Returns the condition of a system
    -- @param string systemKey system key
    -- @return float condition system condition
    local function getSystemCondition(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.condition or 0
        end
        return systemData or 0
    end

    ---Returns the stress of a system
    -- @param string systemKey system key
    -- @return float stress system stress
    local function getSystemStress(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.stress or 0
        end
        return 0
    end

    ---Tells whether a system is enabled on this vehicle
    -- @param string systemKey system key
    -- @return boolean isEnabled true when the system is tracked
    local function isSystemEnabled(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.enabled ~= false
        end
        return true
    end

    local engineDbg = debugData.engine or {}
    local transmissionDbg = debugData.transmission or {}
    local hydraulicsDbg = debugData.hydraulics or {}
    local coolingDbg = debugData.cooling or {}
    local electricalDbg = debugData.electrical or {}
    local chassisDbg = debugData.chassis or {}
    local fuelDbg = debugData.fuel or {}
    local ptoDbg = debugData.pto or {}
    local serviceDbg = debugData.service or {}
    local batteryDbg = debugData.battery or {}
    local drivetrainDbg = debugData.drivetrain or {}

    local overviewLines = {}
    local serviceWearRate = serviceDbg.totalWearRate or RMS_Config.CORE.BASE_SERVICE_WEAR or 0
    local weatherFactor = RMS_Main.currentWeatherFactor
    local dirtLevel = vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount() or 0
    local radiatorClogging = spec.radiatorClogging
    local airFilterClogging = spec.airFilterClogging
    local airFilterResidue = spec.airFilterResidue
    local lubricationLevel = spec.lubricationLevel
    local paintState = math.max(1 - (vehicle.getWearTotalAmount ~= nil and vehicle:getWearTotalAmount() or 0), 0)
    local radiatorDbg = debugData.radiator or {}
    local airFilterDbg = debugData.airFilter or {}
    local radiatorMultiplier = radiatorDbg.totalMultiplier or 0
    local airFilterMultiplier = airFilterDbg.totalMultiplier or 0
    local cloggingIsOnField = radiatorDbg.isOnField == true or airFilterDbg.isOnField == true
    local cloggingHasDust = radiatorDbg.hasDust == true or airFilterDbg.hasDust == true
    local cloggingHasDebris = radiatorDbg.hasDebris == true or airFilterDbg.hasDebris == true
    local cloggingWetnessFactor = airFilterDbg.baseWetnessFactor or radiatorDbg.baseWetnessFactor or 1
    local factorStatsOperatingHours = 0
    local currentOperatingSeconds = 0
    if vehicle.getOperatingTime ~= nil then
        currentOperatingSeconds = math.floor((tonumber(vehicle:getOperatingTime()) or 0) / 1000)
    end
    if type(factorStatsSource) == "table" then
        for _, stats in pairs(factorStatsSource) do
            if type(stats) == "table" and tonumber(stats.operatingHours) ~= nil then
                factorStatsOperatingHours = tonumber(stats.operatingHours) or 0
                break
            end
        end
    end
    addLine(overviewLines, string.format(
        "op.sec: %ds (real: %ds) | start.op.h: %.1fh | condition: %.2f%% | service: %.2f%% | service_wear: %.2f%% | rel: %.2f%% | mnt: %.2f%% | wf: %.3f | roof: %s | lube: %.2f%% | paint: %.2f%%",
        currentOperatingSeconds,
        math.floor((tonumber(spec.realOperatingTime) or 0) / 1000),
        factorStatsOperatingHours,
        asPercent(spec.conditionLevel or 0),
        asPercent(spec.serviceLevel or 0),
        asPercent(serviceWearRate),
        asPercent(spec.reliability or 0),
        asPercent(spec.maintainability or 0),
        weatherFactor,
        tostring(getDebugStateValue("isUnderRoof", spec.isUnderRoof == true) == true),
        asPercent(lubricationLevel),
        asPercent(paintState)
    ), {1, 1, 1, 1}, 0.95)

    addLine(overviewLines, string.format(
        "Clogging: Dirt %.2f%% | Radiator: %.2f%% (%s) | Filter: %.2f%%, residue: %.2f%% (%s) | field: %s, dust: %s, debris: %s, wetness: %.3f",
        asPercent(dirtLevel),
        asPercent(radiatorClogging),
        formatAppliedMultiplier(radiatorMultiplier),
        asPercent(airFilterClogging),
        asPercent(airFilterResidue),
        formatAppliedMultiplier(airFilterMultiplier),
        tostring(cloggingIsOnField),
        tostring(cloggingHasDust),
        tostring(cloggingHasDebris),
        cloggingWetnessFactor
    ), {1, 1, 1, 1}, 0.95)

    addLine(overviewLines, string.format(
        "Fluids: engine oil %.2f%% | coolant %.2f%% (leak %.3f/h) | transmission %.2f%% (leak %.3f/h) | hydraulic %.2f%% (leak %.3f/h)",
        asPercent(spec.engineOilLevel or 1),
        asPercent(spec.coolantLevel or 1),
        tonumber(spec.coolantLeakRate) or 0,
        asPercent(spec.transmissionOilLevel or 1),
        tonumber(spec.transmissionOilLeakRate) or 0,
        asPercent(spec.hydraulicFluidLevel or 1),
        tonumber(spec.hydraulicFluidLeakRate) or 0
    ), {1, 1, 1, 1}, 0.95)

    do
        local drivetrainModeNames = { [0] = "4x2", [1] = "4WD", [2] = "AUTO" }
        addLine(overviewLines, string.format(
            "Drivetrain: ctl: %s | mode: %s | autoEng: %s | lock: %s | park: %s | windup: %.1f%% (wf: %.2f) | ext: %s",
            tostring(drivetrainDbg.hasControl == true),
            drivetrainModeNames[tonumber(drivetrainDbg.driveMode) or -1] or "n/a",
            tostring(drivetrainDbg.autoEngaged == true),
            tostring(drivetrainDbg.diffLockEngaged == true),
            tostring(drivetrainDbg.parkBrake == true),
            asPercent(drivetrainDbg.windupStress or 0),
            tonumber(drivetrainDbg.windupWearFactor) or 0,
            tostring(drivetrainDbg.externallyManaged == true)
        ), {1, 1, 1, 1}, 0.95)
        local wheelSpeedValues = {}
        for wheelIndex, axleSpeed in ipairs(drivetrainDbg.wheelAxleSpeeds or {}) do
            table.insert(wheelSpeedValues, string.format("#%d=%.2f", wheelIndex, tonumber(axleSpeed) or 0))
        end
        if #wheelSpeedValues > 0 then
            addLine(
                overviewLines,
                "Wheel axle speeds (rad/s): " .. table.concat(wheelSpeedValues, " | "),
                {1, 1, 1, 1},
                0.95
            )
        end

        local axleRatioValues = {}
        for _, entry in ipairs(drivetrainDbg.axleRatios or {}) do
            local ratio = tonumber(entry.ratio)
            table.insert(axleRatioValues, string.format(
                "%s %s / cap %.2f",
                entry.label or "?",
                ratio ~= nil and string.format("%.2f", ratio) or "n/a",
                tonumber(entry.cap) or 0
            ))
        end
        if #axleRatioValues > 0 then
            addLine(
                overviewLines,
                "Axle ratio: " .. table.concat(axleRatioValues, " | "),
                {1, 1, 1, 1},
                0.95
            )
        end
    end

    do
        local smoke = spec.exhaustSmoke
        local exhaustEffectCount = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.exhaustEffects ~= nil
            and #vehicle.spec_motorized.exhaustEffects or 0
        addLine(overviewLines, string.format(
            "Exhaust: active: %s | nodes: %d | int: %.2f | era: %.2f | stageV: %s | def: %s | wet: %.2f%% | soot: %.2f%% | oil: %.2f%% | unburnt: %.2f%% | alpha: %.2f-%.2f | rgb: %.2f/%.2f/%.2f",
            tostring(smoke.isActive == true),
            exhaustEffectCount,
            RMS_Config.EXHAUST.INTENSITY,
            smoke.eraFactor,
            tostring(smoke.isStageV == true),
            tostring(smoke.hasDEF == true),
            asPercent(spec.fuelState ~= nil and spec.fuelState.wetStackingLevel or 0),
            asPercent(smoke.soot),
            asPercent(smoke.oil),
            asPercent(smoke.unburnt),
            smoke.alphaIdle,
            smoke.alphaFull,
            smoke.red,
            smoke.green,
            smoke.blue
        ), {1, 1, 1, 1}, 0.95)
    end

    local engineMaxFactor = math.max(
        engineDbg.motorLoadFactor or 0,
        engineDbg.airFilterCloggingFactor or 0,
        engineDbg.expiredServiceFactor or 0,
        engineDbg.coldMotorFactor or 0,
        engineDbg.hotMotorFactor or 0
    ) * bcw
    local transmissionMaxFactor = math.max(
        transmissionDbg.expiredServiceFactor or 0,
        transmissionDbg.pullOverloadFactor or 0,
        transmissionDbg.heavyTrailerFactor or 0,
        transmissionDbg.luggingFactor or 0,
        transmissionDbg.wheelSlipFactor or 0,
        transmissionDbg.drivetrainWindupFactor or 0,
        transmissionDbg.coldTransAbuse or 0,
        transmissionDbg.hotTransFactor or 0
    ) * bcw
    local hydraulicsMaxFactor = math.max(
        hydraulicsDbg.expiredServiceFactor or 0,
        hydraulicsDbg.heavyLiftFactor or 0,
        hydraulicsDbg.vibFactor or 0,
        hydraulicsDbg.operatingFactor or 0,
        hydraulicsDbg.coldOilFactor or 0,
        hydraulicsDbg.hotOilFactor or 0
    ) * bcw
    local coolingMaxFactor = math.max(
        coolingDbg.expiredServiceFactor or 0,
        coolingDbg.highCoolingFactor or 0,
        coolingDbg.overheatFactor or 0,
        coolingDbg.coldShockFactor or 0
    ) * bcw
    local electricalMaxFactor = math.max(
        electricalDbg.expiredServiceFactor or 0,
        electricalDbg.weatherExposureFactor or 0,
        electricalDbg.lightsFactor or 0,
        electricalDbg.crankingStressFactor or 0,
        electricalDbg.overheatFactor or 0,
        electricalDbg.vibFactor or 0
    ) * bcw
    local chassisMaxFactor = math.max(
        chassisDbg.expiredServiceFactor or 0,
        chassisDbg.lubricationFactor or 0,
        chassisDbg.vibFactor or 0,
        chassisDbg.steerLoadFactor or 0,
        chassisDbg.brakeMassFactor or 0
    ) * bcw
    local fuelMaxFactor = math.max(
        fuelDbg.expiredServiceFactor or 0,
        fuelDbg.lowFuelStarvationFactor or 0,
        fuelDbg.coldFuelFactor or 0,
        fuelDbg.idleDepositFactor or 0,
        fuelDbg.highPressureFactor or 0
    ) * bcw
    local ptoMaxFactor = math.max(
        ptoDbg.expiredServiceFactor or 0,
        ptoDbg.ptoLoadFactor or 0,
        ptoDbg.ptoEngagementFactor or 0
    ) * bcw
    local factorStats = {}
    for rawSystemKey, rawStats in pairs(factorStatsSource) do
        if type(rawStats) == "table" then
            factorStats[string.lower(tostring(rawSystemKey))] = rawStats
        end
    end

    ---Returns one accumulated wear statistic of a system
    -- @param string systemKey system key
    -- @param string statKey statistic key
    -- @return float value accumulated value
    local function getAccumulatedStat(systemKey, statKey)
        local stats = factorStats[string.lower(tostring(systemKey))]
        if type(stats) ~= "table" then
            return 0
        end
        return tonumber(stats[statKey]) or 0
    end

    ---Formats one wear factor line with its share and its accumulated total
    -- @param string systemKey system key
    -- @param string shortName factor name shown
    -- @param float? factorValue current factor value
    -- @param string statKey statistic key
    -- @param string? extraInfo text appended to the line
    -- @param float? systemStressMultiplier stress multiplier of the system
    -- @return string text formatted line
    local function formatFactorLine(systemKey, shortName, factorValue, statKey, extraInfo, systemStressMultiplier)
        local currentPct = asPercent((factorValue or 0) * bcw)
        local conditionSum = getAccumulatedStat(systemKey, statKey)
        local sumPct = asPercent(conditionSum)
        local stressPct = asPercent(conditionSum * (systemStressMultiplier or 1))
        local extraText = ""
        if extraInfo ~= nil and tostring(extraInfo) ~= "" then
            extraText = " (" .. tostring(extraInfo) .. ")"
        end
        return string.format("%s: %.2f | %.2f | %.2f%s", shortName, currentPct, sumPct, stressPct, extraText)
    end

    local avgTireGroundFrictionCoeff = tonumber(getDebugStateValue("avgTireGroundFrictionCoeff", spec.avgTireGroundFrictionCoeff)) or 0

    ---Builds every debug line of one system
    -- @param string systemKey system key
    -- @param table dbg debug data of the system
    -- @param float maxFactor largest factor value, used to scale the display
    -- @param table factorEntries factors to show
    -- @return table lines debug lines
    local function buildSystemLines(systemKey, dbg, maxFactor, factorEntries)
        local lines = {}
        local systemStressMultiplier = tonumber(RMS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS[systemKey]) or 1
        addLine(lines, string.format(
            "C: %.1f (-%.2f)",
            asPercent(getSystemCondition(systemKey)),
            asPercent((dbg.totalWearRate or 0) * bcw)
        ), getConditionFactorColor(maxFactor), 0.84)
        addLine(lines, string.format(
            "S: %.2f (+%.2f) t: %.2f | a: %.2f",
            asPercent(getSystemStress(systemKey)),
            asPercent(dbg.instantStressRate or 0),
            asPercent(getAccumulatedStat(systemKey, "stress")),
            asPercent(dbg._avgStress or 0)
        ), {1, 1, 1, 1}, 0.84)

        addLine(lines, string.format(
            "B: %.2f | %.2f",
            asPercent(dbg.breakdownProbability or 0),
            asPercent(dbg.critBreakdownProbability or 0)
        ), {1, 0.82, 0.82, 1}, 0.80)

        for _, entry in ipairs(factorEntries) do
            addLine(
                lines,
                formatFactorLine(systemKey, entry.shortName, entry.value, entry.statKey, nil, systemStressMultiplier),
                {0.92, 0.96, 1.0, 1},
                0.80
            )

            -- complements go on their own indented line
            local extraInfo = entry.extraInfo ~= nil and tostring(entry.extraInfo) or ""
            if extraInfo ~= "" then
                addLine(lines, "  (" .. extraInfo .. ")", {0.92, 0.96, 1.0, 1}, 0.80)
            end
        end

        return lines
    end

    local engineLines = buildSystemLines("engine", engineDbg, engineMaxFactor, {
        { shortName = "sf", statKey = "sf", value = engineDbg.expiredServiceFactor or 0 },
        { shortName = "mlf", statKey = "mlf", value = engineDbg.motorLoadFactor or 0, extraInfo = string.format("dml: %.2f", engineDbg.dynamicMotorLoad or 0) },
        { shortName = "lf", statKey = "lf", value = engineDbg.luggingFactor or 0 },
        { shortName = "aicf", statKey = "aicf", value = engineDbg.airFilterCloggingFactor or 0 },
        { shortName = "cmf", statKey = "cmf", value = engineDbg.coldMotorFactor or 0 },
        { shortName = "hmf", statKey = "hmf", value = engineDbg.hotMotorFactor or 0 },
        { shortName = "flf", statKey = "flf", value = engineDbg.lowFluidFactor or 0, extraInfo = string.format("lvl: %.1f%%", asPercent(spec.engineOilLevel or 1)) }
    })

    local transmissionLines = buildSystemLines("transmission", transmissionDbg, transmissionMaxFactor, {
        { shortName = "sf", statKey = "sf", value = transmissionDbg.expiredServiceFactor or 0 },
        { shortName = "pof", statKey = "pof", value = transmissionDbg.pullOverloadFactor or 0, extraInfo = string.format("%.1f->%.1f", transmissionDbg.pullOverloadTimer or 0, transmissionDbg.pullOverloadTimerMin or 0) },
        { shortName = "htf", statKey = "htf", value = transmissionDbg.heavyTrailerFactor or 0, extraInfo = string.format("hp/%s: %.1f", (transmissionDbg.heavyTrailerMassBasis == "gcw") and "gcw" or "trl", transmissionDbg.heavyTrailerMassRatio or 0) },
        { shortName = "lf", statKey = "lf", value = transmissionDbg.luggingFactor or 0 },
        { shortName = "wsf", statKey = "wsf", value = transmissionDbg.wheelSlipFactor or 0, extraInfo = string.format("c: %.2f", avgTireGroundFrictionCoeff) },
        { shortName = "dwf", statKey = "dwf", value = transmissionDbg.drivetrainWindupFactor or 0, extraInfo = string.format("w: %.1f%% lock: %s", asPercent(drivetrainDbg.windupStress or 0), (drivetrainDbg.diffLockEngaged == true) and "Y" or "N") },
        { shortName = "ctf", statKey = "ctf", value = transmissionDbg.coldTransAbuse or 0 },
        { shortName = "hotf", statKey = "hotf", value = transmissionDbg.hotTransFactor or 0 },
        { shortName = "flf", statKey = "flf", value = transmissionDbg.lowFluidFactor or 0, extraInfo = string.format("lvl: %.1f%%", asPercent(spec.transmissionOilLevel or 1)) }
    })

    local hydraulicsLines = buildSystemLines("hydraulics", hydraulicsDbg, hydraulicsMaxFactor, {
        { shortName = "sf", statKey = "sf", value = hydraulicsDbg.expiredServiceFactor or 0 },
        { shortName = "hlf", statKey = "hlf", value = hydraulicsDbg.heavyLiftFactor or 0, extraInfo = string.format("mr: %.2f", asPercent(hydraulicsDbg.heavyLiftMassRatio or 0)) },
        { shortName = "vf", statKey = "vf", value = hydraulicsDbg.vibFactor or 0, extraInfo = string.format("s: %.2f", asPercent(hydraulicsDbg.vibSignal or 0)) },
        { shortName = "of", statKey = "of", value = hydraulicsDbg.operatingFactor or 0, extraInfo = string.format("active: %s", tostring(hydraulicsDbg.isHydraulicActive == true)) },
        { shortName = "cof", statKey = "cof", value = hydraulicsDbg.coldOilFactor or 0 },
        { shortName = "hof", statKey = "hof", value = hydraulicsDbg.hotOilFactor or 0 },
        { shortName = "flf", statKey = "flf", value = hydraulicsDbg.lowFluidFactor or 0, extraInfo = string.format("lvl: %.1f%%", asPercent(spec.hydraulicFluidLevel or 1)) }
    })

    local coolingLines = buildSystemLines("cooling", coolingDbg, coolingMaxFactor, {
        { shortName = "sf", statKey = "sf", value = coolingDbg.expiredServiceFactor or 0 },
        { shortName = "hcf", statKey = "hcf", value = coolingDbg.highCoolingFactor or 0, extraInfo = string.format("ts: %.1f", asPercent(spec.thermostatState or 0)) },
        { shortName = "ohf", statKey = "ohf", value = coolingDbg.overheatFactor or 0 },
        { shortName = "csf", statKey = "csf", value = coolingDbg.coldShockFactor or 0 }
    })

    local electricalLines = buildSystemLines("electrical", electricalDbg, electricalMaxFactor, {
        { shortName = "sf", statKey = "sf", value = electricalDbg.expiredServiceFactor or 0 },
        { shortName = "wef", statKey = "wef", value = electricalDbg.weatherExposureFactor or 0 },
        { shortName = "ltf", statKey = "ltf", value = electricalDbg.lightsFactor or 0 },
        { shortName = "crf", statKey = "crf", value = electricalDbg.crankingStressFactor or 0, extraInfo = string.format("c: %s, t: %ds", tostring(getDebugStateValue("isCranking", spec.isCranking == true) == true), math.floor(((electricalDbg.crankingTimer or 0) / 1000) + 0.0001)) },
        { shortName = "ohf", statKey = "ohf", value = electricalDbg.overheatFactor or 0 },
        { shortName = "vf", statKey = "vf", value = electricalDbg.vibFactor or 0, extraInfo = string.format("r/s: %.2f / %.2f", asPercent(electricalDbg.vibRaw or 0), asPercent(electricalDbg.vibSignal or 0)) }
    })

    local chassisLines = buildSystemLines("chassis", chassisDbg, chassisMaxFactor, {
        { shortName = "sf", statKey = "sf", value = chassisDbg.expiredServiceFactor or 0 },
        { shortName = "lubf", statKey = "lubf", value = chassisDbg.lubricationFactor or 0, extraInfo = string.format("lvl: %.1f%%", asPercent(lubricationLevel)) },
        { shortName = "vf", statKey = "vf", value = chassisDbg.vibFactor or 0, extraInfo = string.format("r/s: %.2f / %.2f", asPercent(chassisDbg.vibRaw or 0), asPercent(chassisDbg.vibSignal or 0)) },
        { shortName = "slf", statKey = "slf", value = chassisDbg.steerLoadFactor or 0, extraInfo = string.format("ls: %.2f a: %.2f l: %.2f c: %.2f m: %s", chassisDbg.steerLowSpeedFactor or 0, chassisDbg.steerAngleRatio or 0, chassisDbg.steerAxleLoadRatio or 0, chassisDbg.steerGroundFrictionCoeff or 0, (chassisDbg.steerMoving == true) and "Y" or "N") },
        { shortName = "bmf", statKey = "bmf", value = chassisDbg.brakeMassFactor or 0, extraInfo = string.format("hp/%s: %.1f", (chassisDbg.brakeMassBasis == "gcw") and "gcw" or "trl", chassisDbg.brakeMassRatio or 0) }
    })

    local fuelLines = buildSystemLines("fuel", fuelDbg, fuelMaxFactor, {
        { shortName = "sf", statKey = "sf", value = fuelDbg.expiredServiceFactor or 0 },
        { shortName = "lff", statKey = "lff", value = fuelDbg.lowFuelStarvationFactor or 0, extraInfo = string.format("lvl: %.2f", asPercent(fuelDbg.fuelLevel or 0)) },
        { shortName = "cff", statKey = "cff", value = fuelDbg.coldFuelFactor or 0, extraInfo = string.format("ft: %.1f C", fuelDbg.fuelTemperature or 0) },
        { shortName = "idf", statKey = "idf", value = fuelDbg.idleDepositFactor or 0, extraInfo = string.format("t: %.0fs", fuelDbg.idleTimer or 0) },
        { shortName = "hpf", statKey = "hpf", value = fuelDbg.highPressureFactor or 0, extraInfo = string.format("r: %.3f", fuelDbg.currentFuelUsageRatio or 0) }
    })

    local ptoLines = buildSystemLines("pto", ptoDbg, ptoMaxFactor, {
        { shortName = "sf", statKey = "sf", value = ptoDbg.expiredServiceFactor or 0 },
        { shortName = "plf", statKey = "plf", value = ptoDbg.ptoLoadFactor or 0, extraInfo = string.format("active: %s rpm: %.0f kW: %.1f u: %.3f", tostring(ptoDbg.isPtoActive == true), ptoDbg.ptoRpm or 0, ptoDbg.ptoPower or 0, ptoDbg.ptoUtilization or 0) },
        { shortName = "pef", statKey = "pef", value = ptoDbg.ptoEngagementFactor or 0, extraInfo = string.format("cycles: %d pulse: %.0f", ptoDbg.ptoEngagementCount or 0, ptoDbg.ptoEngagementFactor or 0) }
    })


    local systemSections = {}
    if isSystemEnabled("engine") then
        table.insert(systemSections, {title = "Engine", lines = engineLines})
    end
    if isSystemEnabled("transmission") then
        table.insert(systemSections, {title = "Transmission", lines = transmissionLines})
    end
    if isSystemEnabled("hydraulics") then
        table.insert(systemSections, {title = "Hydraulics", lines = hydraulicsLines})
    end
    if isSystemEnabled("cooling") then
        table.insert(systemSections, {title = "Cooling", lines = coolingLines})
    end
    if isSystemEnabled("electrical") then
        table.insert(systemSections, {title = "Electrical", lines = electricalLines})
    end
    if isSystemEnabled("chassis") then
        table.insert(systemSections, {title = "Chassis", lines = chassisLines})
    end
    if isSystemEnabled("fuel") then
        table.insert(systemSections, {title = "Fuel", lines = fuelLines})
    end
    if isSystemEnabled("pto") then
        table.insert(systemSections, {title = "PTO", lines = ptoLines})
    end

    local engineTempLines = {}
    addLine(engineTempLines, string.format(
        "T: %.1fC (raw: %.1fC) | ts: %.3f | k/s/w: %.2f/%.3f/%.3f | h/c: %.3f/%.3f | r/s/c: %.3f/%.3f/%.3f",
        spec.engineTemperature,
        spec.rawEngineTemperature or spec.engineTemperature or -99,
        spec.thermostatState,
        (debugData.engineTemp or {}).kp or 0,
        (debugData.engineTemp or {}).stiction or 0,
        (debugData.engineTemp or {}).waxSpeed or 0,
        (debugData.engineTemp or {}).totalHeat or 0,
        (debugData.engineTemp or {}).totalCooling or 0,
        (debugData.engineTemp or {}).radiatorCooling or 0,
        (debugData.engineTemp or {}).speedCooling or 0,
        (debugData.engineTemp or {}).convectionCooling or 0
    ), getTempColor(spec.engineTemperature), 0.95)

    local hasActiveCVTAddon = hasCVTAddon(vehicle)
    local vehicleHasCVT = hasCVTTransmission(vehicle)

    local showTransmissionSection = vehicleHasCVT and spec.transmissionTemperature > -30
    local transmissionTempLines = {}
    if showTransmissionSection then
        addLine(transmissionTempLines, string.format(
            "T: %.1fC (raw: %.1fC) | ts: %.3f | h: %.3f(i/l/hs/a/ws: %.3f/%.2f/%.2f/%.2f/%.2f) | c: %.3f(cl/s/cv: %.3f/%.3f/%.3f) | cvt: a/l=%d/%d eh=%.3f ph=%.3f hh=%.3f",
            spec.transmissionTemperature,
            spec.rawTransmissionTemperature or spec.transmissionTemperature or -99,
            spec.transmissionThermostatState,
            (debugData.transmissionTemp or {}).totalHeat or 0,
            (debugData.transmissionTemp or {}).idleHeat or 0,
            (debugData.transmissionTemp or {}).loadFactor or 0,
            (debugData.transmissionTemp or {}).hydrostaticFactor or 0,
            (debugData.transmissionTemp or {}).accFactor or 0,
            (debugData.transmissionTemp or {}).wheelSlipFactor or 0,
            (debugData.transmissionTemp or {}).totalCooling or 0,
            (debugData.transmissionTemp or {}).coolerCooling or 0,
            (debugData.transmissionTemp or {}).speedCooling or 0,
            (debugData.transmissionTemp or {}).convectionCooling or 0,
            (debugData.transmissionTemp or {}).cvtSlipActive or 0,
            (debugData.transmissionTemp or {}).cvtSlipLocked or 0,
            (debugData.transmissionTemp or {}).extraTransmissionHeat or 0,
            (debugData.transmissionTemp or {}).ptoHeat or 0,
            (debugData.transmissionTemp or {}).hydraulicHeat or 0
        ), getTempColor(spec.transmissionTemperature), 0.95)
    end

    local availableTorque = motor:getMotorAvailableTorque() or 0
    local motorPower = motor:getMotorRotSpeed() * (availableTorque - motor:getMotorExternalTorque()) * 1000
    local peakPowerHp = (motor.peakMotorPower or 0) * 1.36
    local lastRpm = motor:getLastModulatedMotorRpm()
    local maxRpm = math.max(motor.maxRpm or 1, 1)
    local rpmLoad = lastRpm / maxRpm
    local motorLoad = vehicle:getMotorLoadPercentage() or 0
    local dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or motorLoad
    local avgDynamicMotorLoad = tonumber(getDebugStateValue("avgDynamicMotorLoad", spec.avgDynamicMotorLoad)) or 0
    local currentSpeed = tonumber(vehicle:getLastSpeed()) or 0
    local avgSpeed = tonumber(getDebugStateValue("avgSpeed", spec.avgSpeed)) or 0
    local avgAbsDiffAcc = tonumber(getDebugStateValue("avgAbsDiffAcc", spec.avgAbsDiffAcc)) or 0
    local acceleratorPedal = tonumber(getDebugStateValue("acceleratorPedal", motor.lastAcceleratorPedal)) or 0
    local brakePedal = tonumber(getDebugStateValue("chassisBrakePedal", spec.chassisBrakeState.pedal)) or 0
    local dynamicLoadDeltaPct = motorLoad > 0 and ((dynamicMotorLoad - motorLoad) / motorLoad) * 100 or 0
    local targetGear = (motor.targetGear or 0) * (motor.currentDirection or 1)
    local spec_CVTaddon = vehicle.spec_CVTaddon
    local draftMaxForce = tonumber(getDebugStateValue("activeDraftMaxForce", spec.activeDraftMaxForce)) or 0
    local draftEffectiveForceCap = tonumber(getDebugStateValue("activeDraftEffectiveForceCap", spec.activeDraftEffectiveForceCap)) or 0
    local effectiveCapPerHp = peakPowerHp > 0 and (draftEffectiveForceCap / peakPowerHp) or 0
    local motorTelemetryLines = {}
    addLine(motorTelemetryLines, string.format(
        "sp: %.1f (avg: %.1f) | ap: %.0f%% bp: %.0f%% | hp: %d/%d | ml/dml: %.0f/%.0f (+%.0f%%, ada: %.2f (avg: %.2f%%)) | rpm: %.0f%% | g: %d>%d(%d,%.2f) | max.f: %.2f, eff.c: %.2f | e/h: %.2f",
        currentSpeed,
        avgSpeed,
        math.max(acceleratorPedal * 100, 0),
        math.max(brakePedal * 100, 0),
        motorPower / 735.5,
        peakPowerHp,
        math.max(motorLoad * 100, 0),
        math.max(dynamicMotorLoad * 100, 0),
        dynamicLoadDeltaPct,
        avgAbsDiffAcc,
        math.max(avgDynamicMotorLoad * 100, 0),
        math.max(rpmLoad * 100, 0),
        motor.gear or 0,
        targetGear,
        motor.activeGearGroupIndex or 0,
        motor:getGearRatio() or 0,
        draftMaxForce,
        draftEffectiveForceCap,
        effectiveCapPerHp
    ), {1, 1, 1, 1}, 0.95)

    if hasActiveCVTAddon then
        addLine(motorTelemetryLines, string.format(
            "CA: damage: %.6f%% | wd: %s, cd: %s | wh: %s, ch: %s | hp: %s",
            tonumber(spec_CVTaddon.CVTdamage) or 0,
            tostring(spec_CVTaddon.forDBL_warndamage == 1),
            tostring(spec_CVTaddon.forDBL_critdamage == 1),
            tostring(spec_CVTaddon.forDBL_warnheat == 1),
            tostring(spec_CVTaddon.forDBL_critheat == 1),
            tostring(spec_CVTaddon.forDBL_highpressure == 1)
        ), {1, 0.92, 0.78, 1}, 0.95)
    end

    local batteryLines = {}
    local soc = spec.batterySoc or batteryDbg.soc or 0
    local ocvV = batteryDbg.ocvV or 0
    local termV = spec.batteryTerminalVoltageV or batteryDbg.batteryTerminalVoltageV or batteryDbg.batteryTerminalV or ocvV
    local systemV = spec.systemVoltageV or batteryDbg.systemVoltageVSmoothed or batteryDbg.systemVoltageV or termV
    local tempC = batteryDbg.batteryTempC or getDebugStateValue("batteryTempC", spec.batteryTempC) or 0
    local targetC = batteryDbg.battTempTargetC or 0
    local iAlt = batteryDbg.iAltAvail or 0
    local iLoads = batteryDbg.iLoads or 0
    local iNet = batteryDbg.iNet or batteryDbg.iNetRaw or (iAlt - iLoads)
    local chargeAh = batteryDbg.chargeAh or spec.batteryChargeAh or 0

    addLine(batteryLines, string.format(
        "Voltage: sys %.2fV | term: %.2fV | ocv: %.1fV - Battery: %.1fA | %.2f Ah (%.1f%%) | Temp %.1fC -> %.1fC | acc %.3f | rint %.5f",
        systemV,
        termV,
        ocvV,
        iNet,
        chargeAh,
        asPercent(soc),
        tempC,
        targetC,
        batteryDbg.acceptK or 1,
        batteryDbg.rIntOhm or 0
    ), {0.9, 1.0, 0.9, 1}, 0.95)

    addLine(batteryLines, string.format(
        "Alternator: %.1fA (raw: %.1fA | k %.2f) - Loads: %.1fA (base: %.1fA | lights: %.1fA | cabFan: %.1fA | winHeat: %.1fA | glowProxy: %.1fA | pulse: %.1fA | crank: %.1fA)",
        iAlt,
        batteryDbg.iAltRaw or iAlt,
        batteryDbg.altFactor or 0,
        iLoads,
        batteryDbg.baseLoadA or 0,
        batteryDbg.lightsLoadA or 0,
        batteryDbg.cabFanA or 0,
        batteryDbg.winterHeaterA or 0,
        batteryDbg.preheatLoadA or 0,
        batteryDbg.peakPulseA or 0,
        batteryDbg.crankingLoadA or 0
    ), {0.85, 0.95, 1.0, 1}, 0.95)

    local preheatState = tonumber(getDebugStateValue("preheatState", spec.preheatState)) or RMS_Preheat.STATE.IDLE
    local preheatStateName = tostring(getDebugStateValue("preheatStateName", RMS_Preheat.getStateName(preheatState)))
    local preheatIsDiesel = getDebugStateValue("preheatIsDiesel", RMS_Preheat.isDieselVehicle(vehicle)) == true
    local preheatEngineTemperatureC = tonumber(getDebugStateValue("preheatEngineTemperatureC", RMS_Preheat.getEngineTemperatureC(vehicle))) or 0
    local preheatLampTestActive = getDebugStateValue("preheatLampTestActive", spec.preheatLampTestActive == true) == true
    local preheatLampTestRemainingMs = tonumber(getDebugStateValue("preheatLampTestRemainingMs", spec.preheatLampTestRemainingMs)) or 0
    local preheatRemainingMs = tonumber(getDebugStateValue("preheatRemainingMs", spec.preheatRemainingMs)) or 0
    local preheatRequiredMs = tonumber(getDebugStateValue("preheatRequiredMs", spec.preheatRequiredMs)) or 0
    local preheatWasRequired = getDebugStateValue("preheatWasRequired", spec.preheatWasRequired == true) == true
    local preheatAutomaticCrank = getDebugStateValue("preheatAutomaticCrank", spec.preheatAutomaticCrank == true) == true
    local preheatAutomaticCrankElapsedMs = tonumber(getDebugStateValue("preheatAutomaticCrankElapsedMs", spec.preheatAutomaticCrankElapsedMs)) or 0
    local preheatGlowPlugFailureSeverity = tonumber(getDebugStateValue("preheatGlowPlugFailureSeverity", RMS_Preheat.getGlowPlugFailureSeverity(vehicle))) or 0
    local preheatColdStartFaultSeverity = tonumber(getDebugStateValue("preheatColdStartFaultSeverity", spec.preheatColdStartFaultSeverity)) or 0
    local glowHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER or nil
    local localGlowHardStartStatus = glowHardStartEffect ~= nil
        and glowHardStartEffect.extraData ~= nil
        and glowHardStartEffect.extraData.status
        or "NONE"
    local preheatGlowHardStartStatus = tostring(getDebugStateValue("preheatGlowHardStartStatus", localGlowHardStartStatus))
    local localGlowHardStartBlocked = glowHardStartEffect ~= nil
        and glowHardStartEffect.extraData ~= nil
        and glowHardStartEffect.extraData.blockStart == true
        and spec.preheatWasRequired == true
    local preheatGlowHardStartBlocked = getDebugStateValue("preheatGlowHardStartBlocked", localGlowHardStartBlocked) == true

    addLine(batteryLines, string.format(
        "Preheat: %s (%d) | diesel: %s | engine: %.1fC | required: %.1fs | remaining: %.1fs | requested cold: %s",
        preheatStateName,
        preheatState,
        tostring(preheatIsDiesel),
        preheatEngineTemperatureC,
        preheatRequiredMs / 1000,
        preheatRemainingMs / 1000,
        tostring(preheatWasRequired)
    ), {0.9, 1.0, 0.9, 1}, 0.95)

    addLine(batteryLines, string.format(
        "Preheat control: lamp test %s (%.1fs) | auto crank %s (%.1f/%.1fs) | glow fault %d | cold fault %d | glow starter %s | blocked %s",
        tostring(preheatLampTestActive),
        preheatLampTestRemainingMs / 1000,
        tostring(preheatAutomaticCrank),
        preheatAutomaticCrankElapsedMs / 1000,
        RMS_Config.PREHEAT.MAX_AUTOMATIC_CRANK_MS / 1000,
        preheatGlowPlugFailureSeverity,
        preheatColdStartFaultSeverity,
        preheatGlowHardStartStatus,
        tostring(preheatGlowHardStartBlocked)
    ), {0.85, 0.95, 1.0, 1}, 0.95)

    if (batteryDbg.externalConnected or 0) > 0 then
        addLine(batteryLines, string.format(
            "External: %s | bal %.1fA | com: %.1fA",
            tostring(batteryDbg.externalPartnerName or "-"),
            batteryDbg.externalBalanceCurrentA or 0,
            batteryDbg.externalCommonNetA or 0
        ), {0.85, 0.95, 1.0, 1}, 0.95)
    end

    local serviceDataLines = {}
    local states = RealisticMechanicalSystems.STATUS
    local isUnderService = spec.currentState ~= states.READY
    if isUnderService then
        local pendingInspectionQueue = getDebugStateValue("pendingInspectionQueue", spec.pendingInspectionQueue or {}) or {}
        local pendingRepairQueue = getDebugStateValue("pendingRepairQueue", spec.pendingRepairQueue or {}) or {}
        local pendingSelectedBreakdowns = getDebugStateValue("pendingSelectedBreakdowns", spec.pendingSelectedBreakdowns or {}) or {}
        local progressPercent = 0
        if (spec.pendingProgressTotalTime or 0) > 0 then
            local progressRatio = math.min(math.max((spec.pendingProgressElapsedTime or 0) / spec.pendingProgressTotalTime, 0), 1)
            progressPercent = math.floor(progressRatio * 100)
        end

        addLine(serviceDataLines, string.format(
            "cur/pl/ws: %s/%s/%s | o1/o2/o3/price: %s/%s/%s/%s",
            localizeDebugValue(spec.currentState),
            localizeDebugValue(spec.plannedState),
            localizeDebugValue(spec.workshopType),
            localizeDebugValue(spec.serviceOptionOne),
            localizeDebugValue(spec.serviceOptionTwo),
            localizeDebugValue(spec.serviceOptionThree),
            tostring(getDebugStateValue("pendingServicePrice", spec.pendingServicePrice))
        ), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, string.format(
            "tm/el/tt(ms): %.0f/%.0f/%.0f | prg: %d%% | step: %d | q(sel/insp/rep): %d/%d/%d",
            spec.maintenanceTimer or 0,
            spec.pendingProgressElapsedTime or 0,
            spec.pendingProgressTotalTime or 0,
            progressPercent,
            spec.pendingProgressStepIndex or 0,
            #pendingSelectedBreakdowns,
            #pendingInspectionQueue,
            #pendingRepairQueue
        ), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, string.format(
            "svc s->t: %s->%s | cur s/c: %.4f/%.4f",
            tostring(getDebugStateValue("pendingMaintenanceServiceStart", spec.pendingMaintenanceServiceStart)),
            tostring(getDebugStateValue("pendingMaintenanceServiceTarget", spec.pendingMaintenanceServiceTarget)),
            spec.serviceLevel or 0,
            spec.conditionLevel or 0
        ), {1, 0.95, 0.75, 1}, 0.95)

        if spec.currentState == states.OVERHAUL then
            local overhaulSystemStart = getDebugStateValue("pendingOverhaulSystemStart", spec.pendingOverhaulSystemStart or {}) or {}
            local overhaulSystemTarget = getDebugStateValue("pendingOverhaulSystemTarget", spec.pendingOverhaulSystemTarget or {}) or {}
            local overhaulStressStart = getDebugStateValue("pendingOverhaulSystemStressStart", spec.pendingOverhaulSystemStressStart or {}) or {}
            local overhaulStressTarget = getDebugStateValue("pendingOverhaulSystemStressTarget", spec.pendingOverhaulSystemStressTarget or {}) or {}
            local conditionEntries = buildPendingSystemTransitionEntries(
                overhaulSystemStart,
                overhaulSystemTarget,
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.condition) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )
            local stressEntries = buildPendingSystemTransitionEntries(
                overhaulStressStart,
                overhaulStressTarget,
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.stress) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )

            addLine(serviceDataLines, "ovh cond:", {1, 0.95, 0.75, 1}, 0.95)
            local conditionLines = packEntries(conditionEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
            for _, line in ipairs(conditionLines) do
                table.insert(serviceDataLines, line)
            end

            addLine(serviceDataLines, "ovh stress:", {1, 0.95, 0.75, 1}, 0.95)
            local stressLines = packEntries(stressEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
            for _, line in ipairs(stressLines) do
                table.insert(serviceDataLines, line)
            end
        elseif spec.currentState == states.REPAIR then
            local repairStressEntries = buildPendingSystemTransitionEntries(
                getDebugStateValue("pendingRepairSystemStressStart", spec.pendingRepairSystemStressStart or {}) or {},
                getDebugStateValue("pendingRepairSystemStressTarget", spec.pendingRepairSystemStressTarget or {}) or {},
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.stress) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )

            if #repairStressEntries > 0 then
                addLine(serviceDataLines, "rep stress:", {1, 0.95, 0.75, 1}, 0.95)
                local repairStressLines = packEntries(repairStressEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
                for _, line in ipairs(repairStressLines) do
                    table.insert(serviceDataLines, line)
                end
            end
        elseif spec.currentState == states.MAINTENANCE and spec.serviceOptionOne == RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE then
            local preventiveStressEntries = buildPendingSystemTransitionEntries(
                getDebugStateValue("pendingPreventiveSystemStressStart", spec.pendingPreventiveSystemStressStart or {}) or {},
                getDebugStateValue("pendingPreventiveSystemStressTarget", spec.pendingPreventiveSystemStressTarget or {}) or {},
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.stress) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )

            addLine(serviceDataLines, string.format(
                "prev sys: %d/%d | factor: %.3f",
                #preventiveStressEntries,
                tonumber(RMS_Config.MAINTENANCE.MAINTENANCE_PREVENTIVE_SYSTEMS_COUNT) or 0,
                tonumber(RMS_Config.MAINTENANCE.MAINTENANCE_PREVENTIVE_STRESS_REMOVE_MULTIPLIER) or 0
            ), {1, 0.95, 0.75, 1}, 0.95)

            local preventiveStressLines = packEntries(preventiveStressEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
            for _, line in ipairs(preventiveStressLines) do
                table.insert(serviceDataLines, line)
            end
        end

        addLine(serviceDataLines, "sel: " .. listToString(pendingSelectedBreakdowns), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, "insp: " .. listToString(pendingInspectionQueue), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, "rep: " .. listToString(pendingRepairQueue), {1, 0.95, 0.75, 1}, 0.95)
    end

    local overviewSection = {title = "Overall", lines = overviewLines}
    local sections = {
        {title = "Engine Temp", lines = engineTempLines}
    }
    local implementLines = {}
    addLine(implementLines, "", {1, 1, 1, 1}, 0.95)
    local debugImplements = getDebugStateValue("implements", spec.implements or {}) or {}
    addLine(implementLines, string.format(
        "Implements: lowered: %s | hydraulic: %s | lifted: %s | hydraulicTargets: %d | liftedMass: %.1f | debris: %s",
        tostring(getDebugStateValue("isImplementLowered", spec.isImplementLowered == true) == true),
        tostring(getDebugStateValue("isImplementOperating", spec.isImplementOperating == true) == true),
        tostring(getDebugStateValue("isImplementLifted", spec.isImplementLifted == true) == true),
        tonumber(getDebugStateValue("hydraulicActiveTargetCount", spec.hydraulicActiveTargetCount)) or 0,
        tonumber(getDebugStateValue("liftedMass", spec.liftedMass)) or 0,
        tostring(getDebugStateValue("hasDebris", spec.hasDebris == true) == true)
    ), {1, 1, 1, 1}, 0.95)

    for index, impl in ipairs(debugImplements) do
        addLine(implementLines, string.format(
            "#%d %s | mass: %.1f | jointType: %s | lowered: %s | supportWheels: %d | liftMoving: %s | cylinderMoving: %s | jointControl: %s | hammer: %s | head: %s",
            index,
            tostring(impl.name or "implement"),
            impl.mass,
            tostring(impl.jointTypeId),
            tostring(impl.isLowered == true),
            impl.supportWheelCount,
            tostring(impl.isMoving == true),
            tostring(impl.isCylinderedMoving == true),
            tostring(impl.isAttacherJointControlMoving == true),
            tostring(impl.isHydraulicHammerActive == true),
            tostring(impl.isHead == true)
        ), {0.92, 0.96, 1.0, 1}, 0.90)
    end

    if showTransmissionSection then
        table.insert(sections, {title = "CVT Temp", lines = transmissionTempLines})
    end

    table.insert(sections, {title = "Motor telemetry", lines = motorTelemetryLines})
    table.insert(sections, {title = "Battery", lines = batteryLines, showTitle = false})
    if isUnderService then
        table.insert(sections, {title = "Service Data", lines = serviceDataLines})
    end
    if #breakdownEntries > 0 then
        table.insert(sections, {title = "Active Breakdowns", lines = breakdownLines})
    end
    if #effectEntries > 0 then
        table.insert(sections, {title = "Active Effects", lines = effectLines})
    end

    if #aiCruiseLines > 0 then
        table.insert(sections, {title = "AI Cruise Control", lines = aiCruiseLines})
    end

    table.insert(sections, {title = "Implements", lines = implementLines, showTitle = false})

    local systemColumns = math.min(8, math.max(#systemSections, 1))
    local systemGapX = 0.002
    local systemGapY = sectionGap * 0.16
    local systemLineIndent = 0.003
    local systemCardWidth = ((panel.width - panel.padding * 2) - (systemColumns - 1) * systemGapX) / systemColumns

    setTextBold(false)
    for _, section in ipairs(systemSections) do
        local wrappedLines = {}
        for _, line in ipairs(section.lines) do
            local lineSize = activeNormalSize * (line.sizeScale or 1.0)
            for _, part in ipairs(wrapLineToWidth(line.text or "", lineSize, systemCardWidth - systemLineIndent)) do
                table.insert(wrappedLines, {text = part, color = line.color, sizeScale = line.sizeScale})
            end
        end
        section.lines = wrappedLines
    end

    local systemRows = (#systemSections > 0) and math.ceil(#systemSections / systemColumns) or 0
    local rowHeights = {}
    local totalSystemHeight = 0

    for row = 1, systemRows do
        local rowMaxLines = 0
        for col = 1, systemColumns do
            local index = (row - 1) * systemColumns + col
            local section = systemSections[index]
            if section ~= nil then
                rowMaxLines = math.max(rowMaxLines, #section.lines)
            end
        end
        local rowHeight = (rowMaxLines + 1) * activeLineHeight
        rowHeights[row] = rowHeight
        totalSystemHeight = totalSystemHeight + rowHeight
    end
    if systemRows > 1 then
        totalSystemHeight = totalSystemHeight + (systemRows - 1) * systemGapY
    end

    local totalSectionHeight = 0
    local allLinearSections = {}
    table.insert(allLinearSections, overviewSection)
    for _, section in ipairs(sections) do
        table.insert(allLinearSections, section)
    end

    for _, section in ipairs(allLinearSections) do
        totalSectionHeight = totalSectionHeight + (math.max(#section.lines, 1) * activeLineHeight)
    end
    if #systemSections > 0 then
        totalSectionHeight = totalSectionHeight + sectionGap + totalSystemHeight + sectionGap
    end

    local dynamicHeight = (panel.padding * 2) + activeHeaderSize + totalSectionHeight + 0.02

    local textStartX = panel.x + panel.padding
    local currentY = panel.y + dynamicHeight - panel.padding

    local vehicleTypeCategory = self:getVehicleTypeCategoryLabel(vehicle)
    local headerText = string.format("%s %s | Type/Category: %s", vehicle:getFullName(), tostring(spec.year), vehicleTypeCategory)
    queueText(textStartX, currentY, activeHeaderSize, headerText, {1, 1, 1, 1}, true)
    currentY = currentY - activeHeaderSize - activeLineHeight

    ---Draws one debug section and returns the height it took
    -- @param table section section lines
    -- @return float height height drawn
    local function drawSection(section)
        local sectionLines = section.lines or {}
        local showTitle = section.showTitle ~= false
        if #sectionLines == 0 then
            if showTitle then
                queueText(textStartX, currentY, activeNormalSize, section.title .. ":", {1, 1, 1, 1}, false)
            end
            currentY = currentY - activeLineHeight
            return
        end

        local firstLine = sectionLines[1]
        local firstColor = firstLine.color or {1, 1, 1, 1}
        local firstSize = activeNormalSize * (firstLine.sizeScale or 1.0)
        local firstText = firstLine.text or ""
        if showTitle then
            firstText = section.title .. ": " .. firstText
        end
        queueText(textStartX, currentY, firstSize, firstText, firstColor, false)
        currentY = currentY - activeLineHeight

        for index = 2, #sectionLines do
            local line = sectionLines[index]
            local lineText = line.text or ""
            local lineColor = line.color or {1, 1, 1, 1}
            local lineSize = activeNormalSize * (line.sizeScale or 1.0)
            queueText(textStartX, currentY, lineSize, lineText, lineColor, false)
            currentY = currentY - activeLineHeight
        end
    end

    drawSection(overviewSection)

    if #systemSections > 0 then
        currentY = currentY - sectionGap
        local gridStartX = textStartX
        local rowY = currentY

        for row = 1, systemRows do
            local rowHeight = rowHeights[row] or activeLineHeight
            for col = 1, systemColumns do
                local index = (row - 1) * systemColumns + col
                local section = systemSections[index]
                if section ~= nil then
                    local cardX = gridStartX + (col - 1) * (systemCardWidth + systemGapX)
                    local cardY = rowY
                    queueText(cardX, cardY, activeNormalSize, section.title .. ":", {1, 1, 1, 1}, false)

                    local cardLineY = cardY - activeLineHeight
                    for _, line in ipairs(section.lines) do
                        local lineText = line.text or ""
                        local lineColor = line.color or {1, 1, 1, 1}
                        local lineSize = activeNormalSize * (line.sizeScale or 1.0)
                        queueText(cardX + systemLineIndent, cardLineY, lineSize, lineText, lineColor, false)
                        cardLineY = cardLineY - activeLineHeight
                    end
                end
            end

            rowY = rowY - rowHeight
            if row < systemRows then
                rowY = rowY - systemGapY
            end
        end

        currentY = currentY - totalSystemHeight
        currentY = currentY - sectionGap
    end

    for _, section in ipairs(sections) do
        drawSection(section)
    end

    cache.lastUpdateTime = now
    cache.vehicle = vehicle
    cache.panel = {
        x = panel.x,
        y = panel.y,
        width = panel.width,
        height = dynamicHeight,
        color = {0, 0, 0, 0.7}
    }
    cache.commands = queuedCommands

    self:renderActiveVehicleDebugCache(cache)
end

---Draws the accumulated wear factor statistics, per system and per factor
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param table debugData debug data of the vehicle
-- @param table factorStatsRaw raw factor statistics
-- @param table panel panel geometry
-- @param float activeHeaderSize header text size
-- @param float activeNormalSize body text size
-- @param float activeLineHeight line height
-- @param float sectionGap gap between two sections
function RMS_Hud:drawFactorStatsVehicleHUD(vehicle, spec, debugData, factorStatsRaw, panel, activeHeaderSize, activeNormalSize, activeLineHeight, sectionGap)
    ---Appends one line to a debug section
    -- @param table target section lines
    -- @param string text line text
    -- @param table? color rgba channels
    -- @param float? sizeScale text size scale
    local function addLine(target, text, color, sizeScale)
        table.insert(target, {
            text = text,
            color = color or {1, 1, 1, 1},
            sizeScale = sizeScale or 1.0
        })
    end

    ---Packs several entries onto as few lines as the limit allows
    -- @param table entries entries to pack
    -- @param integer maxPerLine entries allowed on one line
    -- @param table? color rgba channels
    -- @param float? sizeScale text size scale
    -- @return table lines packed lines
    local function packEntries(entries, maxPerLine, color, sizeScale)
        local lines = {}
        if #entries == 0 then
            addLine(lines, "-", color, sizeScale)
            return lines
        end

        local lineEntries = {}
        for i, entry in ipairs(entries) do
            table.insert(lineEntries, entry)
            if #lineEntries >= maxPerLine or i == #entries then
                addLine(lines, table.concat(lineEntries, " | "), color, sizeScale)
                lineEntries = {}
            end
        end

        return lines
    end

    ---Formats a ratio as a percentage
    -- @param float? value ratio
    -- @return string text formatted percentage
    local function toPct(value)
        return (tonumber(value) or 0) * 100
    end

    ---Returns the localized title of a system
    -- @param string systemKey system key
    -- @return string title system title
    local function getSystemTitle(systemKey)
        local names = {
            engine = "Engine",
            transmission = "Transmission",
            hydraulics = "Hydraulics",
            cooling = "Cooling",
            electrical = "Electrical",
            chassis = "Chassis",
            fuel = "Fuel",
            pto = "PTO",
            materialFlow = "Material Flow"
        }
        return names[systemKey] or tostring(systemKey)
    end

    local aliasToDebugKey = {}
    for debugKey, alias in pairs(RealisticMechanicalSystems.FACTOR_STATS_ALIASES or {}) do
        aliasToDebugKey[tostring(alias)] = tostring(debugKey)
    end

    ---Builds the extra text shown next to a wear factor
    -- @param string debugKey factor debug key
    -- @param table dbg debug data of the system
    -- @return string? text extra information
    local function buildFactorExtraInfo(debugKey, dbg)
        if type(dbg) ~= "table" then
            return nil
        end

        if debugKey == "heavyLiftFactor" then
            local ratio = tonumber(dbg.heavyLiftMassRatio)
            if ratio ~= nil then
                return string.format("massRatio %.3f", ratio)
            end
        elseif debugKey == "steerLoadFactor" then
            local parts = {}
            if dbg.steerLowSpeedFactor ~= nil then
                table.insert(parts, string.format("lowSp %.3f", tonumber(dbg.steerLowSpeedFactor) or 0))
            end
            if dbg.steerGroundFrictionCoeff ~= nil then
                table.insert(parts, string.format("friction %.3f", tonumber(dbg.steerGroundFrictionCoeff) or 0))
            end
            if dbg.steerMoving ~= nil then
                table.insert(parts, string.format("moving %s", tostring(dbg.steerMoving == true)))
            end
            if #parts > 0 then
                return table.concat(parts, " | ")
            end
        elseif debugKey == "brakeMassFactor" then
            local parts = {}
            if dbg.brakeMassRatio ~= nil then
                table.insert(parts, string.format("massRatio %.3f", tonumber(dbg.brakeMassRatio) or 0))
            end
            if dbg.brakePedal ~= nil then
                table.insert(parts, string.format("brake %.3f", tonumber(dbg.brakePedal) or 0))
            end
            if #parts > 0 then
                return table.concat(parts, " | ")
            end
        elseif debugKey == "vibFactor" then
            local parts = {}
            if dbg.vibSignal ~= nil then
                table.insert(parts, string.format("signal %.3f", tonumber(dbg.vibSignal) or 0))
            end
            if dbg.vibFieldMultiplier ~= nil then
                table.insert(parts, string.format("field %.3f", tonumber(dbg.vibFieldMultiplier) or 0))
            end
            if #parts > 0 then
                return table.concat(parts, " | ")
            end
        elseif debugKey == "motorLoadFactor" then
            if dbg.dynamicMotorLoad ~= nil then
                return string.format("dml %.3f", tonumber(dbg.dynamicMotorLoad) or 0)
            end
        elseif debugKey == "highPressureFactor" then
            if dbg.currentFuelUsageRatio ~= nil then
                return string.format("ratio %.3f", tonumber(dbg.currentFuelUsageRatio) or 0)
            end
        elseif debugKey == "ptoLoadFactor" then
            return string.format("power %.1fkW | utilization %.3f | rpm %.0f", tonumber(dbg.ptoPower) or 0, tonumber(dbg.ptoUtilization) or 0, tonumber(dbg.ptoRpm) or 0)
        elseif debugKey == "ptoEngagementFactor" then
            return string.format("cycles %d | current pulse %.0f", tonumber(dbg.ptoEngagementCount) or 0, tonumber(dbg.ptoEngagementFactor) or 0)
        elseif debugKey == "airFilterCloggingFactor" then
            if dbg.airFilterClogging ~= nil then
                return string.format("clog %.1f%%", (tonumber(dbg.airFilterClogging) or 0) * 100)
            end
        elseif debugKey == "coldMotorFactor" then
            local parts = {}
            if dbg.engineTemperature ~= nil then
                table.insert(parts, string.format("temp %.1fC", tonumber(dbg.engineTemperature) or 0))
            end
            if dbg.rpmLoad ~= nil then
                table.insert(parts, string.format("rpm %.3f", tonumber(dbg.rpmLoad) or 0))
            end
            if #parts > 0 then
                return table.concat(parts, " | ")
            end
        elseif debugKey == "hotMotorFactor" or debugKey == "overheatFactor" then
            if dbg.engineTemperature ~= nil then
                return string.format("temp %.1fC", tonumber(dbg.engineTemperature) or 0)
            end
        elseif debugKey == "coldShockFactor" then
            local parts = {}
            if dbg.engineTemperature ~= nil then
                table.insert(parts, string.format("temp %.1fC", tonumber(dbg.engineTemperature) or 0))
            end
            if dbg.rpmLoad ~= nil then
                table.insert(parts, string.format("rpm %.3f", tonumber(dbg.rpmLoad) or 0))
            end
            if #parts > 0 then
                return table.concat(parts, " | ")
            end
        elseif debugKey == "highCoolingFactor" then
            if dbg.thermostatState ~= nil then
                return string.format("therm %.3f", tonumber(dbg.thermostatState) or 0)
            end
        end

        return nil
    end

    local sections = {}
    factorStatsRaw = factorStatsRaw or {}
    local factorStats = {}
    for rawSystemKey, rawStats in pairs(factorStatsRaw) do
        if type(rawStats) == "table" then
            local normalizedKey = tostring(rawSystemKey)
            local loweredKey = string.lower(normalizedKey)
            if loweredKey == "materialflow" then
                normalizedKey = "materialFlow"
            end

            if factorStats[normalizedKey] == nil then
                factorStats[normalizedKey] = {}
            end

            for statKey, statValue in pairs(rawStats) do
                local numericValue = tonumber(statValue)
                if numericValue ~= nil and string.sub(tostring(statKey), 1, 1) ~= "_" then
                    factorStats[normalizedKey][statKey] = (tonumber(factorStats[normalizedKey][statKey]) or 0) + numericValue
                end
            end
        end
    end

    local orderedSystems = {
        "engine", "transmission", "hydraulics", "cooling",
        "electrical", "chassis", "fuel", "pto", "materialFlow"
    }

    local usedSystems = {}
    for _, systemKey in ipairs(orderedSystems) do
        local stats = factorStats[systemKey]
        if type(stats) == "table" then
            usedSystems[systemKey] = true
            local lines = {}
            local dbg = type(debugData) == "table" and debugData[systemKey] or nil
            local systemStressMultiplier = tonumber(RMS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS[systemKey]) or 1
            addLine(lines, string.format(
                "total: %.3f%% | stress: %.3f%%",
                toPct(stats.total),
                toPct(stats.stress)
            ), {1, 1, 1, 1}, 0.95)

            if type(dbg) == "table" then
                addLine(lines, string.format(
                    "breakdown: %.3f%% | critical: %.3f%%",
                    toPct(dbg.breakdownProbability or 0),
                    toPct(dbg.critBreakdownProbability or 0)
                ), {1, 0.92, 0.78, 1}, 0.9)
            end

            local factorEntries = {}
            for key, value in pairs(stats) do
                if key ~= "total" and key ~= "stress" and key ~= "operatingHours" then
                    local numericValue = tonumber(value)
                    if numericValue ~= nil and math.abs(numericValue) > 0 then
                        table.insert(factorEntries, { key = key, value = numericValue })
                    end
                end
            end

            table.sort(factorEntries, function(a, b)
                return math.abs(a.value) > math.abs(b.value)
            end)

            if #factorEntries > 0 then
                addLine(lines, "", {1, 1, 1, 1}, 0.9)
            end

            for _, entry in ipairs(factorEntries) do
                local alias = tostring(entry.key)
                local accumulatedConditionDamage = tonumber(entry.value) or 0
                local accumulatedStressDamage = accumulatedConditionDamage * systemStressMultiplier
                local debugKey = aliasToDebugKey[alias]
                local currentValue = 0
                if debugKey ~= nil and type(dbg) == "table" then
                    currentValue = tonumber(dbg[debugKey]) or 0
                end

                local lineText = string.format(
                    "%s: %.3f%% | %.3f%% | %.3f%%",
                    alias,
                    toPct(currentValue),
                    toPct(accumulatedConditionDamage),
                    toPct(accumulatedStressDamage)
                )

                local extraInfo = buildFactorExtraInfo(debugKey, dbg)
                if extraInfo ~= nil and extraInfo ~= "" then
                    lineText = lineText .. " (" .. extraInfo .. ")"
                end

                addLine(lines, lineText, {0.92, 0.96, 1.0, 1}, 0.9)
            end

            table.insert(sections, { title = getSystemTitle(systemKey), lines = lines })
        end
    end

    for systemKey, stats in pairs(factorStats) do
        if type(stats) == "table" and not usedSystems[systemKey] then
            local lines = {}
            local dbg = type(debugData) == "table" and debugData[systemKey] or nil
            addLine(lines, string.format(
                "total: %.3f%% | stress: %.3f%%",
                toPct(stats.total),
                toPct(stats.stress)
            ), {1, 1, 1, 1}, 0.95)
            if type(dbg) == "table" then
                addLine(lines, string.format(
                    "breakdown: %.3f%% | critical: %.3f%%",
                    toPct(dbg.breakdownProbability or 0),
                    toPct(dbg.critBreakdownProbability or 0)
                ), {1, 0.92, 0.78, 1}, 0.9)
            end
            table.insert(sections, { title = getSystemTitle(systemKey), lines = lines })
        end
    end

    local totalSectionHeight = 0
    for _, section in ipairs(sections) do
        totalSectionHeight = totalSectionHeight + (math.max(#section.lines, 1) * activeLineHeight)
    end
    totalSectionHeight = totalSectionHeight + (math.max(#sections - 1, 0) * sectionGap)

    local dynamicHeight = (panel.padding * 2) + activeHeaderSize + totalSectionHeight + 0.02
    self:drawPanelBackground(
        panel.x,
        panel.y,
        panel.width,
        dynamicHeight,
        {0, 0, 0, 0.7}
    )

    local textStartX = panel.x + panel.padding
    local currentY = panel.y + dynamicHeight - panel.padding

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    local vehicleTypeCategory = self:getVehicleTypeCategoryLabel(vehicle)
    local headerText = string.format("%s %s | Type/Category: %s [Factor Stats]", vehicle:getFullName(), tostring(spec.year), vehicleTypeCategory)
    renderText(textStartX, currentY, activeHeaderSize, headerText)
    setTextBold(false)
    currentY = currentY - activeHeaderSize - activeLineHeight

    ---Draws one debug section and returns the height it took
    -- @param table section section lines
    -- @return float height height drawn
    local function drawSection(section)
        local sectionLines = section.lines or {}
        if #sectionLines == 0 then
            setTextColor(1, 1, 1, 1)
            renderText(textStartX, currentY, activeNormalSize, section.title .. ":")
            currentY = currentY - activeLineHeight
            return
        end

        local firstLine = sectionLines[1]
        local firstColor = firstLine.color or {1, 1, 1, 1}
        local firstSize = activeNormalSize * (firstLine.sizeScale or 1.0)
        setTextColor(firstColor[1], firstColor[2], firstColor[3], firstColor[4] or 1)
        renderText(textStartX, currentY, firstSize, section.title .. ": " .. (firstLine.text or ""))
        currentY = currentY - activeLineHeight

        for index = 2, #sectionLines do
            local line = sectionLines[index]
            local lineText = line.text or ""
            local lineColor = line.color or {1, 1, 1, 1}
            local lineSize = activeNormalSize * (line.sizeScale or 1.0)
            setTextColor(lineColor[1], lineColor[2], lineColor[3], lineColor[4] or 1)
            renderText(textStartX + 0.01, currentY, lineSize, lineText)
            currentY = currentY - activeLineHeight
        end
    end

    for index, section in ipairs(sections) do
        drawSection(section)
        if index < #sections then
            currentY = currentY - sectionGap
        end
    end

    setTextColor(1, 1, 1, 1)
end
