-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---HUD of the mod: dashboard indicators, telemetry cards, notifications and the damage bar
RMS_Hud = {}
RMS_Hud.modDirectory = g_currentModDirectory
RMS_Hud.debugViewMode = RMS_Hud.debugViewMode or "default"
local RMS_Hud_mt = Class(RMS_Hud, HUDDisplay)

RMS_Hud.COLOR_GAME_GREEN = HUD.COLOR.ACTIVE
RMS_Hud.INSPECTION_RING_SIZE = 138
RMS_Hud.CONSUMPTION_REFRESH_INTERVAL = 500
RMS_Hud.CONSUMPTION_PER_HOUR_BUCKETS = 2
RMS_Hud.CONSUMPTION_PER_AREA_BUCKETS = 10
RMS_Hud.MOTOR_LOAD_BUCKETS = 2

---Formats a number, dropping its decimals when it rounds to zero
-- @param float value value to format
-- @param string numberFormat format applied to a non zero value
-- @return string text formatted value
local function formatValue(value, numberFormat)
    local amount = tonumber(value) or 0
    local text = string.format(numberFormat, amount)

    if text == string.format(numberFormat, 0) then
        return "0"
    end

    return text
end

---Formats a consumption readout, one decimal below a hundred
-- @param float value consumption value
-- @return string text formatted value
local function formatConsumptionValue(value)
    local amount = math.max(tonumber(value) or 0, 0)
    return formatValue(amount, amount < 100 and "%.1f" or "%.0f")
end

---Create instance of RMS_Hud, loading its overlays and its sounds
-- @return table self instance of class RMS_Hud
function RMS_Hud:new()
	local self = RMS_Hud:superClass().new(RMS_Hud_mt)
	self.vehicle = nil
    self.telemetryDisplayValues = {
        motorLoad = 0
    }
    self.motorLoadAverage = { buckets = {}, current = { value = 0, time = 0 }, timer = 0 }
    self.consumption = {
        buckets = {},
        current = { fuel = 0, time = 0, litres = 0, hectares = 0 },
        timer = 0,
        perHour = 0,
        perArea = nil
    }

    g_overlayManager:addTextureConfigFile(RMS_Hud.modDirectory .. "hud/rms_dashboardHud.xml", "rms_DashboardHud")
    self.wheelSlipHud = {
        icon = g_overlayManager:createOverlay("rms_DashboardHud.wheelSlip", 0, 0, 0, 0)
    }
    self.fuelConsumptionHud = {
        icon = g_overlayManager:createOverlay("rms_DashboardHud.fuelConsumption", 0, 0, 0, 0)
    }

    self.dashExtension = {
        leftHalf = g_overlayManager:createOverlay("gui.speedBg", 0, 0, 0, 0),
        rightHalf = g_overlayManager:createOverlay("gui.speedBg", 0, 0, 0, 0),
        strip = g_overlayManager:createOverlay("gui.speedBg", 0, 0, 0, 0)
    }
    local bgUvs = self.dashExtension.leftHalf.uvs
    local uMidBottom = (bgUvs[1] + bgUvs[5]) * 0.5
    local uMidTop = (bgUvs[3] + bgUvs[7]) * 0.5
    local uHalfPx = (bgUvs[5] - bgUvs[1]) / 232 * 0.5
    self.dashExtension.leftHalf:setUVs({bgUvs[1], bgUvs[2], bgUvs[3], bgUvs[4], uMidBottom, bgUvs[6], uMidTop, bgUvs[8]})
    self.dashExtension.rightHalf:setUVs({uMidBottom, bgUvs[2], uMidTop, bgUvs[4], bgUvs[5], bgUvs[6], bgUvs[7], bgUvs[8]})
    self.dashExtension.strip:setUVs({uMidBottom - uHalfPx, bgUvs[2], uMidTop - uHalfPx, bgUvs[4], uMidBottom + uHalfPx, bgUvs[6], uMidTop + uHalfPx, bgUvs[8]})

    self.drivetrainHud = {
        icons = {
            drivelineOpen    = { overlay = g_overlayManager:createOverlay("rms_DashboardHud.drivelineOpen", 0, 0, 0, 0),    aspect = 45 / 59, height = 21 },
            drivelineEngaged = { overlay = g_overlayManager:createOverlay("rms_DashboardHud.drivelineEngaged", 0, 0, 0, 0), aspect = 45 / 59, height = 21 },
            diffLockCenter   = { overlay = g_overlayManager:createOverlay("rms_DashboardHud.diffLockCenter", 0, 0, 0, 0),   aspect = 44 / 59, height = 21 },
            diffLockRear     = { overlay = g_overlayManager:createOverlay("rms_DashboardHud.diffLockRear", 0, 0, 0, 0),     aspect = 44 / 59, height = 21 }
        }
    }

    self.parkBrakeHud = {
        icon = g_overlayManager:createOverlay("rms_DashboardHud.parkBrake", 0, 0, 0, 0)
    }

    self.indicators = {
        engine = {
            name = 'engine',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.engine", 0, 0, 0, 0),
            year = 1990
        },
        transmission = {
            name = 'transmission',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.transmission", 0, 0, 0, 0),
            year = 1990,
        },
        brakes = {
            name = 'brakes',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.brakes", 0, 0, 0, 0),
            year = 1980
        },
        battery = {
            name = 'battery',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.battery", 0, 0, 0, 0),
            year = 1950
        },
        coolant = {
            name = 'coolant',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.coolant", 0, 0, 0, 0),
            year = 1950
        },
        warning = {
            name = 'warning',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.warning", 0, 0, 0, 0),
            year = 1990
        },
        preheat = {
            name = 'preheat',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.preheat", 0, 0, 0, 0)
        },
        service = {
            name = 'service',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.service", 0, 0, 0, 0),
            year = 1970
        },
        oil = {
            name = 'oil',
            icon = g_overlayManager:createOverlay("rms_DashboardHud.oil", 0, 0, 0, 0),
            year = 1950
        }
    }

    self.indicatorRuntime = {}
    self.indicatorSoundConfig = {
        engine =        { cooldownMs = 1800, sampleName = "warning" },
        transmission =  { cooldownMs = 1800, sampleName = "warning" },
        brakes =        { cooldownMs = 1800, sampleName = "warning" },
        battery =       { cooldownMs = 1800, sampleName = "warning" },
        coolant =       { cooldownMs = 1800, sampleName = "warning" },
        warning =       { cooldownMs = 1400, sampleName = "warning" },
        preheat =       { cooldownMs = 1800, sampleName = "warning" },
        service =       { cooldownMs = 2500, sampleName = "warning" },
        oil =           { cooldownMs = 1800, sampleName = "warning" }
    }

    self.indicatorValueText = {}

    self.loadMassText = {}

    self.notificationPanel = {
        title = nil,
        text = nil,
        endTime = nil,
        isVisible = false,
        isPersistent = false,
        closeGlyphSize = 26,
        closeGlyphTextSpacing = 6
    }

    self.inspectionProgress = {
        ratio = nil,
        messageText = nil,
        messageEndTime = 0
    }

    self.notificationCloseGlyph = nil
    self.notificationCloseGlyphInputMode = nil
    self.notificationInputContextName = nil
    self.notificationCloseActionEventId = nil

    self.activeVehicleDebugPanel = {
        x = 0.20,
        y = 0.0269,
        width = 0.60,
        padding = 0.01,
        lineHeight = 0.012,
        isVisible = false
    }

    self.activeVehicleDebugCache = {
        refreshIntervalMs = 100,
        lastUpdateTime = -math.huge,
        vehicle = nil,
        panel = nil,
        commands = nil
    }

    self.text = {
        headerSize = 0.014,
        normalSize = 0.010,
        color = {1, 1, 1, 1}
    }


    return self
end

---Deletes the overlays of the HUD
function RMS_Hud:delete()
    self:setNotificationInputActive(false)
    self.wheelSlipHud.icon:delete()
    self.wheelSlipHud.icon = nil
    self.fuelConsumptionHud.icon:delete()
    self.fuelConsumptionHud.icon = nil
    self.parkBrakeHud.icon:delete()
    self.parkBrakeHud.icon = nil

    if self.dashExtension ~= nil then
        self.dashExtension.leftHalf:delete()
        self.dashExtension.rightHalf:delete()
        self.dashExtension.strip:delete()
        self.dashExtension = nil
    end

    for _, icon in pairs(self.drivetrainHud.icons) do
        icon.overlay:delete()
        icon.overlay = nil
    end

    for _, indicator in pairs(self.indicators) do
        indicator.icon:delete()
        indicator.icon = nil
    end

    if self.notificationCloseGlyph ~= nil then
        self.notificationCloseGlyph:delete()
        self.notificationCloseGlyph = nil
    end

    RMS_Hud:superClass().delete(self)
end

---Shows or hides the HUD
-- @param boolean isVisible true to show it
function RMS_Hud:setVisible(isVisible)
    self.activeVehicleDebugPanel.isVisible = isVisible
end

---Binds the HUD to a vehicle and resets its per vehicle state
-- @param table? vehicle vehicle
function RMS_Hud:setVehicle(vehicle)
    if self.vehicle ~= vehicle then
        self.indicatorRuntime = {}
        self.activeVehicleDebugCache.lastUpdateTime = -math.huge
        self.activeVehicleDebugCache.vehicle = nil
        self.activeVehicleDebugCache.panel = nil
        self.activeVehicleDebugCache.commands = nil
        self.telemetryDisplayValues.motorLoad = 0
        self.motorLoadAverage = { buckets = {}, current = { value = 0, time = 0 }, timer = 0 }
        self:resetConsumptionAverages()
    end

    self.vehicle = vehicle
end

---Returns the blink and sound state of an indicator, creating it on first use
-- @param string indicatorId dashboard indicator id
-- @return table state indicator runtime state
function RMS_Hud:getIndicatorRuntimeState(indicatorId)
    if self.indicatorRuntime == nil then
        self.indicatorRuntime = {}
    end

    if self.indicatorRuntime[indicatorId] == nil then
        self.indicatorRuntime[indicatorId] = {
            isLit = false,
            soundPlayedForCurrentActivation = false,
            lastSoundTime = 0,
            severity = 0,
            lastSoundSeverity = 0,
            blinkStartTime = 0,
            blinkActive = false
        }
    end

    return self.indicatorRuntime[indicatorId]
end

---Starts the blink cycle of an indicator
-- @param string indicatorId dashboard indicator id
function RMS_Hud:startIndicatorBlink(indicatorId)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.getMotorState == nil or vehicle:getMotorState() ~= MotorState.ON then
        runtimeState.blinkActive = false
        runtimeState.blinkStartTime = 0
        return
    end

    local now = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0

    runtimeState.blinkActive = true
    runtimeState.blinkStartTime = now
end

---Applies the blink colour of an indicator for this frame
-- @param string indicatorId dashboard indicator id
-- @param table targetColor colour the indicator lights in
-- @param boolean blinkWhileActive true to keep blinking while it stays lit
function RMS_Hud:applyIndicatorBlink(indicatorId, targetColor, blinkWhileActive)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local colors = RMS_Breakdowns ~= nil and RMS_Breakdowns.COLORS or nil
    local vehicle = self.vehicle
    if runtimeState == nil or colors == nil or runtimeState.blinkActive ~= true then
        return targetColor
    end

    if vehicle == nil or vehicle.getMotorState == nil or vehicle:getMotorState() ~= MotorState.ON then
        runtimeState.blinkActive = false
        runtimeState.blinkStartTime = 0
        return targetColor
    end

    local now = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
    local blinkIntervalMs = 600
    local totalPhases = 4
    local elapsed = math.max(now - (runtimeState.blinkStartTime or 0), 0)
    local phaseIndex = math.floor(elapsed / blinkIntervalMs)

    if not blinkWhileActive and phaseIndex >= totalPhases then
        runtimeState.blinkActive = false
        return targetColor
    end

    if phaseIndex % 2 == 1 then
        return colors.DEFAULT
    end

    return targetColor
end

---Plays the warning or alarm sound once when an indicator lights up
-- @param string indicatorId dashboard indicator id
-- @param table runtimeState indicator runtime state
-- @param integer severity indicator severity
function RMS_Hud:tryPlayIndicatorActivationSound(indicatorId, runtimeState, severity)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return false
    end

    local config = self.indicatorSoundConfig ~= nil and self.indicatorSoundConfig[indicatorId] or nil
    if config == nil then
        return false
    end

    if vehicle.getMotorState == nil or vehicle:getMotorState() ~= MotorState.ON then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local samples = spec.samples
    if samples == nil then
        return false
    end

    local sampleName = config.sampleName
    local sample = sampleName ~= nil and samples[sampleName] or nil
    if sample == nil then
        return false
    end

    local now = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
    local cooldownMs = math.max(tonumber(config.cooldownMs) or 0, 0)
    local elapsed = now - (runtimeState.lastSoundTime or 0)

    if runtimeState.soundPlayedForCurrentActivation and severity <= (runtimeState.lastSoundSeverity or 0) then
        return false
    end

    if elapsed < cooldownMs then
        return false
    end

    RMS_SoundManager.playSample(sample)
    runtimeState.lastSoundTime = now
    runtimeState.soundPlayedForCurrentActivation = true
    runtimeState.lastSoundSeverity = severity or 0
    return true
end

---Lights or clears an indicator, starting its blink and its sound on the transition
-- @param string indicatorId dashboard indicator id
-- @param boolean shouldLight true when the indicator must be lit
-- @param table targetColor colour the indicator lights in
function RMS_Hud:syncIndicatorActivation(indicatorId, shouldLight, targetColor)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local colors = RMS_Breakdowns ~= nil and RMS_Breakdowns.COLORS or nil
    local severity = 0

    if shouldLight and colors ~= nil then
        if targetColor == colors.CRITICAL then
            severity = 2
        elseif targetColor == colors.WARNING then
            severity = 1
        end
    end

    local wasLit = runtimeState.isLit == true
    local previousSeverity = runtimeState.severity or 0
    local turnedOn = shouldLight and not wasLit
    local turnedOff = not shouldLight and wasLit
    local escalatedToCritical = shouldLight and previousSeverity == 1 and severity == 2

    if turnedOn then
        runtimeState.isLit = true
        runtimeState.severity = severity
        if severity > 0 then
            self:startIndicatorBlink(indicatorId)
        end
        self:tryPlayIndicatorActivationSound(indicatorId, runtimeState, severity)
    elseif escalatedToCritical then
        runtimeState.isLit = true
        runtimeState.severity = severity
        if severity > 0 then
            self:startIndicatorBlink(indicatorId)
        end
        self:tryPlayIndicatorActivationSound(indicatorId, runtimeState, severity)
    elseif turnedOff then
        runtimeState.isLit = false
        runtimeState.severity = 0
        runtimeState.soundPlayedForCurrentActivation = false
        runtimeState.lastSoundSeverity = 0
        runtimeState.blinkActive = false
        runtimeState.blinkStartTime = 0
    else
        runtimeState.isLit = shouldLight
        runtimeState.severity = severity
    end
end

---Returns the store category label of a vehicle
-- @param table? vehicle vehicle
-- @return string label category label
function RMS_Hud:getVehicleTypeCategoryLabel(vehicle)
    local vehicleTypeName = "-"
    local categoryName = "-"

    if vehicle ~= nil and vehicle.type ~= nil and vehicle.type.name ~= nil then
        vehicleTypeName = tostring(vehicle.type.name)
    end

    if vehicle ~= nil and g_storeManager ~= nil and g_storeManager.getItemByXMLFilename ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
        if storeItem ~= nil and storeItem.categoryName ~= nil then
            categoryName = tostring(storeItem.categoryName)
        end
    end

    return string.format("%s/%s", vehicleTypeName, categoryName)
end

local hasCVTTransmission = RMS_Utils.hasCVTTransmission
local hasCVTAddon = RMS_Utils.hasCVTAddon


---Draws the whole HUD for the current frame
function RMS_Hud:draw()
    if g_currentMission == nil then
        return
    end

    local isHudVisible = g_currentMission.hud.isVisible
    local isGuiVisible = g_gui ~= nil and g_gui:getIsGuiVisible()
    self:setNotificationInputActive(isHudVisible and not isGuiVisible and self:hasClosableNotification())

    if not isHudVisible then
        return
    end

    self:drawNotificationPanel()
    self:drawInspectionProgress()

    if RMS_Config.DEBUG and g_currentMission.isMasterUser and self.vehicle ~= nil and self.activeVehicleDebugPanel.isVisible then
        self:drawActiveVehicleHUD()
    end

    if self.vehicle ~= nil then
        self:drawDashboard()
        self:drawTelemetryCards()
    end
end


---Shows a notification on the shared HUD instance
-- @param string text notification text
-- @param float? durationMs display duration in ms, absent for a persistent one
-- @param string? title notification title
-- @param boolean? playSound true to play the notification sound
function RMS_Hud.showNotification(text, durationMs, title, playSound)
    if RMS_Main ~= nil and RMS_Main.hud ~= nil then
        RMS_Main.hud:setNotification(text, durationMs, title, playSound)
    end
end

---Sets the inspection progress on the shared HUD instance
-- @param float? ratio progress between 0 and 1
function RMS_Hud.showInspectionProgress(ratio)
    if RMS_Main ~= nil and RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionProgress(ratio)
    end
end

---Shows a message where the inspection ring stood on the shared HUD instance
-- @param string text message shown
-- @param float durationMs time the message stays on screen
function RMS_Hud.showInspectionMessage(text, durationMs)
    if RMS_Main ~= nil and RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionMessage(text, durationMs)
    end
end

---Stores the notification to draw and starts its timer
-- @param string text notification text
-- @param float? durationMs display duration in ms, absent for a persistent one
-- @param string? title notification title
-- @param boolean? playSound true to play the notification sound
function RMS_Hud:setNotification(text, durationMs, title, playSound)
    local panel = self.notificationPanel
    local normalizedText = tostring(text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local normalizedTitle = tostring(title or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local parsedDurationMs = tonumber(durationMs)

    if normalizedText == "" then
        self:clearNotification()
        return
    end

    if normalizedTitle == "" then
        normalizedTitle = nil
    else
        normalizedTitle = utf8ToUpper(normalizedTitle)
    end

    panel.title = normalizedTitle
    panel.text = normalizedText
    panel.isPersistent = parsedDurationMs ~= nil and parsedDurationMs <= 0
    if panel.isPersistent then
        panel.endTime = nil
    else
        panel.endTime = g_time + math.max(parsedDurationMs or 3000, 0)
    end
    panel.isVisible = true

    if playSound then
        RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
    end
end

---Clears the notification and its input binding
function RMS_Hud:clearNotification()
    local panel = self.notificationPanel
    panel.title = nil
    panel.text = nil
    panel.endTime = nil
    panel.isVisible = false
    panel.isPersistent = false
end

---Registers or drops the action closing a persistent notification
-- @param boolean isActive true to register it
function RMS_Hud:setNotificationInputActive(isActive)
    local inputBinding = g_inputBinding
    local contextName = isActive and inputBinding.currentContextName or nil

    if self.notificationCloseActionEventId ~= nil
        and (not isActive or self.notificationInputContextName ~= contextName) then
        inputBinding:beginActionEventsModification(self.notificationInputContextName)
        inputBinding:removeActionEvent(self.notificationCloseActionEventId)
        inputBinding:endActionEventsModification()

        self.notificationInputContextName = nil
        self.notificationCloseActionEventId = nil
    end

    if isActive and contextName ~= nil and self.notificationCloseActionEventId == nil then
        inputBinding:beginActionEventsModification(contextName)
        local _, eventId = inputBinding:registerActionEvent(
            InputAction.RMS_CLOSE_NOTIFICATION,
            self,
            self.onCloseNotificationInput,
            false,
            true,
            false,
            true,
            nil,
            false
        )
        inputBinding:setActionEventTextVisibility(eventId, false)
        inputBinding:endActionEventsModification()

        self.notificationInputContextName = contextName
        self.notificationCloseActionEventId = eventId
    end
end

---Closes the persistent notification on player input
function RMS_Hud:onCloseNotificationInput()
    self:closePersistentNotification()
end

---Tells whether a notification the player can close is shown
-- @return boolean hasClosable true when one is shown
function RMS_Hud:hasClosableNotification()
    local panel = self.notificationPanel

    return panel ~= nil and panel.isVisible and panel.isPersistent
end

---Closes the persistent notification
function RMS_Hud:closePersistentNotification()
    if not self:hasClosableNotification() then
        return false
    end

    self:clearNotification()

    return true
end

---Draws the divider line of the notification panel
-- @param float x x position
-- @param float y y position
-- @param float width divider width
-- @param float height divider height
-- @param table color rgba channels
function RMS_Hud:drawNotificationDivider(x, y, width, height, color)
    local snappedX, snappedY, snappedWidth, snappedHeight = self:snapScreenRect(x, y, width, height)
    drawFilledRect(
        snappedX,
        snappedY,
        snappedWidth,
        snappedHeight,
        color[1],
        color[2],
        color[3],
        color[4] or 1
    )
end

---Returns the input glyph closing the notification
-- @param float glyphWidth glyph width
-- @param float glyphHeight glyph height
-- @return table? glyph input glyph element
function RMS_Hud:getNotificationCloseGlyph(glyphWidth, glyphHeight)
    if self.notificationCloseGlyph == nil then
        self.notificationCloseGlyph = InputGlyphElement.new(g_inputDisplayManager, glyphWidth, glyphHeight)
        self.notificationCloseGlyph:setKeyboardGlyphColor(RMS_Hud.COLOR_GAME_GREEN, {0, 0, 0, 0.8})
        self.notificationCloseGlyph:setButtonGlyphColor(RMS_Hud.COLOR_GAME_GREEN)
    elseif self.notificationCloseGlyph.baseWidth ~= glyphWidth or self.notificationCloseGlyph.baseHeight ~= glyphHeight then
        self.notificationCloseGlyph:delete()
        self.notificationCloseGlyph = InputGlyphElement.new(g_inputDisplayManager, glyphWidth, glyphHeight)
        self.notificationCloseGlyph:setKeyboardGlyphColor(RMS_Hud.COLOR_GAME_GREEN, {0, 0, 0, 0.8})
        self.notificationCloseGlyph:setButtonGlyphColor(RMS_Hud.COLOR_GAME_GREEN)
        self.notificationCloseGlyphInputMode = nil
    end

    local inputMode = g_inputBinding:getInputHelpMode()
    if self.notificationCloseGlyphInputMode ~= inputMode then
        self.notificationCloseGlyph:setAction(InputAction.RMS_CLOSE_NOTIFICATION, nil, nil, true)
        self.notificationCloseGlyphInputMode = inputMode
    end

    return self.notificationCloseGlyph
end

---Snaps a rectangle to whole pixels
-- @param float x x position
-- @param float y y position
-- @param float width rectangle width
-- @param float height rectangle height
-- @return float x, float y, float width, float height snapped rectangle
function RMS_Hud:snapScreenRect(x, y, width, height)
    local snappedX = math.floor(x * g_screenWidth + 0.5) / g_screenWidth
    local snappedY = math.floor(y * g_screenHeight + 0.5) / g_screenHeight
    local snappedWidth = math.max(math.floor(width * g_screenWidth + 0.5) / g_screenWidth, 1 / g_screenWidth)
    local snappedHeight = math.max(math.floor(height * g_screenHeight + 0.5) / g_screenHeight, 1 / g_screenHeight)

    return snappedX, snappedY, snappedWidth, snappedHeight
end

---Draws the rounded background of a panel
-- @param float x x position
-- @param float y y position
-- @param float width panel width
-- @param float height panel height
-- @param table color rgba channels
function RMS_Hud:drawPanelBackground(x, y, width, height, color)
    if width <= 0 or height <= 0 then
        return
    end

    local panelColor = color or {0, 0, 0, 0.7}
    local panelX, panelY, panelWidth, panelHeight = self:snapScreenRect(x, y, width, height)
    drawFilledRectRound(
        panelX,
        panelY,
        panelWidth,
        panelHeight,
        0.25,
        panelColor[1],
        panelColor[2],
        panelColor[3],
        panelColor[4] or 1
    )
end

---Stores the progress the inspection ring draws, absent to hide it
-- @param float? ratio progress between 0 and 1
function RMS_Hud:setInspectionProgress(ratio)
    local progress = self.inspectionProgress
    progress.ratio = ratio ~= nil and math.clamp(ratio, 0, 1) or nil

    if progress.ratio ~= nil then
        progress.messageText = nil
    end
end

---Stores the message shown where the inspection ring stood
-- @param string text message shown
-- @param float durationMs time the message stays on screen
function RMS_Hud:setInspectionMessage(text, durationMs)
    local progress = self.inspectionProgress
    progress.messageText = text
    progress.messageEndTime = g_time + durationMs
end

---Draws the inspection progress as a ring filling up around its percentage
function RMS_Hud:drawInspectionProgress()
    local progress = self.inspectionProgress
    local ratio = progress.ratio
    local centerX, centerY = 0.5, 0.46

    if ratio == nil then
        if progress.messageText ~= nil and g_time < progress.messageEndTime then
            local messageSize = self:scalePixelToScreenHeight(20)

            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextColor(1, 1, 1, 0.55)
            renderText(centerX, centerY, messageSize, progress.messageText)
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextColor(1, 1, 1, 1)
        end

        return
    end

    local ringWidth, ringHeight = self:scalePixelValuesToScreenVector(RMS_Hud.INSPECTION_RING_SIZE, RMS_Hud.INSPECTION_RING_SIZE)
    RMS_ProgressRing.render(centerX, centerY, ringWidth, ringHeight, ratio)

    local labelSize = self:scalePixelToScreenHeight(17)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(1, 1, 1, 0.55)
    renderText(centerX, centerY + ringHeight * 0.5 + labelSize * 0.6, labelSize, g_i18n:getText("rms_field_inspection_progress"))

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

---Draws the notification panel and its text
function RMS_Hud:drawNotificationPanel()
    local panel = self.notificationPanel
    if panel == nil or not panel.isVisible or panel.text == nil then
        return
    end

    if panel.endTime ~= nil and g_time >= panel.endTime then
        self:clearNotification()
        return
    end

    local panelWidth = self:scalePixelToScreenWidth(640)
    local panelX = 0.5 - panelWidth * 0.5
    local panelY = g_hudAnchorBottom
    local paddingX = self:scalePixelToScreenWidth(20)
    local paddingY = self:scalePixelToScreenHeight(20)
    local maxTextWidth = panelWidth - paddingX * 2
    local titleTextSize = self:scalePixelToScreenHeight(19)
    local textSize = self:scalePixelToScreenHeight(17)
    local titleSpacing = self:scalePixelToScreenHeight(10)
    local sectionSpacing = self:scalePixelToScreenHeight(15)
    local dividerHeight = self:scalePixelToScreenHeight(1)
    local closeRowHeight = self:scalePixelToScreenHeight(30)
    local hasTitle = panel.title ~= nil
    local closeGlyphVisible = panel.isPersistent and hasTitle
    local closeGlyphWidth = closeGlyphVisible and self:scalePixelToScreenWidth(panel.closeGlyphSize or 18) or 0
    local closeGlyphHeight = closeGlyphVisible and self:scalePixelToScreenHeight(panel.closeGlyphSize or 18) or 0

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
    setTextWrapWidth(maxTextWidth)

    local titleHeight = 0
    if hasTitle then
        setTextBold(true)
        titleHeight = getTextHeight(titleTextSize, panel.title)
    end

    setTextBold(false)
    local textHeight = getTextHeight(textSize, panel.text)
    local titleSectionHeight = hasTitle and (titleHeight + titleSpacing * 2 + dividerHeight) or 0
    local closeSectionHeight = hasTitle and (sectionSpacing + dividerHeight + (closeGlyphVisible and closeRowHeight or 0)) or 0
    local dynamicHeight = paddingY * 2 + titleSectionHeight + textHeight + closeSectionHeight

    self:drawPanelBackground(
        panelX,
        panelY,
        panelWidth,
        dynamicHeight,
        HUD.COLOR.BACKGROUND_DARK
    )

    local centerX = 0.5
    local dividerWidth = panelWidth - paddingX * 2
    local currentY = panelY + dynamicHeight - paddingY

    if hasTitle then
        setTextBold(true)
        setTextColor(unpack(RMS_Hud.COLOR_GAME_GREEN))
        renderText(centerX, currentY, titleTextSize, panel.title)
        currentY = currentY - titleHeight - titleSpacing

        self:drawNotificationDivider(panelX + paddingX, currentY - dividerHeight, dividerWidth, dividerHeight, RMS_Hud.COLOR_GAME_GREEN)
        currentY = currentY - dividerHeight - titleSpacing
    end

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    renderText(centerX, currentY, textSize, panel.text)
    currentY = currentY - textHeight
    setTextWrapWidth(0)

    if hasTitle then
        currentY = currentY - sectionSpacing
        self:drawNotificationDivider(panelX + paddingX, currentY - dividerHeight, dividerWidth, dividerHeight, RMS_Hud.COLOR_GAME_GREEN)

        if closeGlyphVisible then
            local glyph = self:getNotificationCloseGlyph(closeGlyphWidth, closeGlyphHeight)
            if glyph ~= nil then
                local glyphWidth = glyph:getGlyphWidth()
                local okText = "OK"
                local okTextSize = textSize
                local textSpacing = self:scalePixelToScreenWidth(panel.closeGlyphTextSpacing or 6)
                local okTextWidth = getTextWidth(okTextSize, okText)
                local glyphX = centerX - (glyphWidth + textSpacing + okTextWidth) * 0.5
                local glyphY = panelY + paddingY + (closeRowHeight - closeGlyphHeight) * 0.5
                glyph:setPosition(glyphX, glyphY)
                glyph:draw()

                setTextAlignment(RenderText.ALIGN_LEFT)
                setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
                setTextBold(true)
                setTextColor(1, 1, 1, 0.95)
                renderText(glyphX + glyphWidth + textSpacing - self:scalePixelToScreenWidth(4), glyphY + closeGlyphHeight * 0.5 + self:scalePixelToScreenHeight(2), okTextSize, okText)
            end
        end
    end

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
end


---Recomputes every HUD size and position for the current screen resolution
function RMS_Hud:storeScaledValues()

    self.dashExtension.stretchWidth = self:scalePixelToScreenWidth(25)

    local indicatorSize = 19
    local indicatorValueSize = 9
    local indicatorWidth, indicatorHeight = self:scalePixelValuesToScreenVector(indicatorSize, indicatorSize)
    local indicatorLayout = {
    {indicator = self.indicators.brakes,       offsetX = -91.125,  offsetY =  55.000},
        {indicator = self.indicators.engine,       offsetX = -106.445, offsetY =  35.250, valueOffsetX = -5.875, valueOffsetY = -3.847, maxTextWidth = 27.232},
        {indicator = self.indicators.coolant,      offsetX = -116.136, offsetY =   4.488, valueOffsetX = -1.125, valueOffsetY = -4.507, maxTextWidth = 29.528},
        {indicator = self.indicators.transmission, offsetX = -114.629, offsetY = -27.732, valueOffsetX = 2.632,  valueOffsetY = -4.417, maxTextWidth = 27.858},
        {indicator = self.indicators.battery,      offsetX = -102.186, offsetY = -58.003, valueOffsetX = -0.625, valueOffsetY = -1.826, maxTextWidth = 25.975}
    }

    for _, layout in ipairs(indicatorLayout) do
        local indicator = layout.indicator
        indicator.offsetX, indicator.offsetY = self:scalePixelValuesToScreenVector(layout.offsetX, layout.offsetY)
        indicator.icon:setDimension(indicatorWidth, indicatorHeight)

        if layout.valueOffsetY ~= nil then
            indicator.valueOffsetX, indicator.valueOffsetY = self:scalePixelValuesToScreenVector(
                layout.valueOffsetX,
                layout.valueOffsetY
            )
            indicator.valueMaxWidth = self:scalePixelToScreenWidth(layout.maxTextWidth)
        end
    end

    local oilWidth, oilHeight = self:scalePixelValuesToScreenVector(22, 22)
    local speedMeter = g_currentMission.hud.speedMeter
    local serviceAnchorY = (
        speedMeter.gaugeTextOffsets[4].offsetY
        + speedMeter.gaugeTextOffsets[7].offsetY
    ) * 0.5
    local warningRowCenterY = serviceAnchorY - self:scalePixelToScreenHeight(10)
    self.indicators.oil.offsetX = self:scalePixelToScreenWidth(28) - oilWidth * (37 / 72)
    self.indicators.oil.offsetY = warningRowCenterY - oilHeight * (35 / 72)
    self.indicators.oil.icon:setDimension(oilWidth, oilHeight)

    local warningWidth, warningHeight = self:scalePixelValuesToScreenVector(18, 18)
    self.indicators.warning.offsetX = -warningWidth * (37 / 72)
    self.indicators.warning.offsetY = warningRowCenterY - warningHeight * (35.5 / 72)
    self.indicators.warning.icon:setDimension(warningWidth, warningHeight)

    local preheatWidth = oilWidth * (64 / 69)
    local preheatHeight = oilHeight * (40 / 43)
    self.indicators.preheat.offsetX = self:scalePixelToScreenWidth(-28) - preheatWidth * (35.5 / 72)
    self.indicators.preheat.offsetY = warningRowCenterY - preheatHeight * (35.5 / 72)
    self.indicators.preheat.icon:setDimension(preheatWidth, preheatHeight)

    local serviceWidth, serviceHeight = self:scalePixelValuesToScreenVector(42, 10)
    self.indicators.service.offsetX = -serviceWidth * 0.5
    self.indicators.service.offsetY = serviceAnchorY
    self.indicators.service.icon:setDimension(serviceWidth, serviceHeight)

    self.wheelSlipHud.offsetX, self.wheelSlipHud.offsetY = self:scalePixelValuesToScreenVector(47, -76)
    local wheelSlipWidth, wheelSlipHeight = self:scalePixelValuesToScreenVector(24, 24)
    self.wheelSlipHud.icon:setDimension(wheelSlipWidth, wheelSlipHeight)

    self.drivetrainHud.centerX, self.drivetrainHud.centerY = self:scalePixelValuesToScreenVector(-59, -67)
    self.drivetrainHud.autoBadgeOffsetX, self.drivetrainHud.autoBadgeOffsetY = self:scalePixelValuesToScreenVector(-59, -82)
    self.drivetrainHud.autoBadgeSize = self:scalePixelToScreenHeight(7)
    for _, iconData in pairs(self.drivetrainHud.icons) do
        local iconWidth, iconHeight = self:scalePixelValuesToScreenVector(iconData.height * iconData.aspect, iconData.height)
        iconData.overlay:setDimension(iconWidth, iconHeight)
        iconData.width2, iconData.height2 = iconWidth * 0.5, iconHeight * 0.5
    end

    if self.parkBrakeHud ~= nil and self.parkBrakeHud.icon ~= nil then
        local parkWidth, parkHeight = self:scalePixelValuesToScreenVector(23, 19)
        self.parkBrakeHud.icon:setDimension(parkWidth, parkHeight)
        self.parkBrakeHud.width = parkWidth
        self.parkBrakeHud.height = parkHeight
        self.parkBrakeHud.gapX = self:scalePixelToScreenWidth(8)
        self.parkBrakeHud.offsetY = self:scalePixelToScreenHeight(0)
    end

    self.indicatorValueText.size = self:scalePixelToScreenHeight(indicatorValueSize)

    self.wheelSlipHud.textOffsetX, self.wheelSlipHud.textOffsetY = self:scalePixelValuesToScreenVector(59, -78)
    self.wheelSlipHud.textSize = self:scalePixelToScreenHeight(9)

    self.loadMassText.size = self:scalePixelToScreenHeight(13)
    self.loadMassText.paddingH, self.loadMassText.paddingV = self:scalePixelValuesToScreenVector(10, 4)
    self.telemetryCardGap = self:scalePixelToScreenWidth(4)

    local fuelIconWidth, fuelIconHeight = self:scalePixelValuesToScreenVector(14, 15)
    self.fuelConsumptionHud.icon:setDimension(fuelIconWidth, fuelIconHeight)
    self.fuelConsumptionHud.width = fuelIconWidth
    self.fuelConsumptionHud.height = fuelIconHeight
    self.fuelConsumptionHud.iconGap = self:scalePixelToScreenWidth(6)
end

---Draws the dashboard indicators, the gauges and the vehicle condition
function RMS_Hud:drawDashboard()
    if self.vehicle == nil or self.vehicle.spec_RealisticMechanicalSystems == nil or self.vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        return
    end

    local vehicle = self.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems
    local colors = RMS_Breakdowns.COLORS
    local activeIndicators = spec.activeIndicators
    local serviceInterval = (self.vehicle:getHoursSinceLastMaintenance() or 0) / (self.vehicle:getMaintenanceInterval() or 5)
    local isServiceOverdue = serviceInterval > 1.0
    local motorState = vehicle:getMotorState()
    local preheatState = spec.preheatState or RMS_Preheat.STATE.IDLE
    local isLampTestActive = RMS_Preheat.isLampTestActive(vehicle)

    ---Returns the colour an indicator must light in, the highest priority breakdown winning
    -- @param string hudIndicatorId dashboard indicator id
    -- @param boolean mutateActiveState true to update the stored active state as well
    -- @return table? color rgba channels, nil when the indicator stays off
    -- @return boolean isRoutineIgnitionIndicator true for an indicator that lights on every ignition
    local function calculateIndicatorTargetColor(hudIndicatorId, mutateActiveState)
        local targetColor = colors.DEFAULT
        local isRoutineIgnitionIndicator = false

        if motorState ~= MotorState.OFF then
            local activeData = activeIndicators[hudIndicatorId]
            if activeData then
                local isActive = activeData.isActive
                local shouldBeOn = activeData.switchOn(vehicle)
                local shouldBeOff = activeData.switchOff(vehicle)

                if isActive and not shouldBeOff then
                    targetColor = activeData.color
                elseif shouldBeOn and not shouldBeOff then
                    if mutateActiveState then
                        activeData.isActive = true
                    end
                    targetColor = activeData.color
                elseif shouldBeOff and mutateActiveState then
                    activeData.isActive = false
                end
            end

            if hasCVTAddon(vehicle) then
                local spec_CVTaddon = vehicle.spec_CVTaddon

                if hudIndicatorId == self.indicators.warning.name and targetColor == colors.DEFAULT and (spec_CVTaddon.forDBL_warndamage == 1 or spec_CVTaddon.forDBL_warnheat == 1 or spec_CVTaddon.forDBL_highpressure == 1) then
                    targetColor = colors.WARNING
                end
                if hudIndicatorId == self.indicators.warning.name and targetColor == colors.WARNING and (spec_CVTaddon.forDBL_critdamage == 1 or spec_CVTaddon.forDBL_critheat == 1) then
                    targetColor = colors.CRITICAL
                end
            end

            local isEngineNotHeated = spec.engineTemperature < RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD

            if hudIndicatorId == self.indicators.coolant.name and targetColor == colors.DEFAULT and isEngineNotHeated then targetColor = colors.COOL
            elseif hudIndicatorId == self.indicators.coolant.name and targetColor == colors.DEFAULT and spec.engineTemperature > 99 and spec.engineTemperature < 110 then targetColor = colors.WARNING
            elseif hudIndicatorId == self.indicators.coolant.name and spec.engineTemperature > 110 then targetColor = colors.CRITICAL end
            if hudIndicatorId == self.indicators.transmission.name and targetColor == colors.DEFAULT and spec.transmissionTemperature > 99 and spec.transmissionTemperature < 110 then targetColor = colors.WARNING
            elseif hudIndicatorId == self.indicators.transmission.name and spec.transmissionTemperature > 110 then targetColor = colors.CRITICAL end

            if hudIndicatorId == self.indicators.service.name and isServiceOverdue then targetColor = colors.WARNING end
            if hudIndicatorId == self.indicators.oil.name
                    and (tonumber(spec.engineOilLevel) or 1) < RMS_Config.FLUIDS.LEVEL_MIN_MARK then
                targetColor = colors.CRITICAL
            end

            if isLampTestActive then
                targetColor = colors.WARNING
                isRoutineIgnitionIndicator = true
            elseif hudIndicatorId == self.indicators.preheat.name
                    and preheatState == RMS_Preheat.STATE.PREHEATING
                    and targetColor == colors.DEFAULT then
                targetColor = colors.WARNING
                isRoutineIgnitionIndicator = true
            elseif (motorState == MotorState.IGNITION or motorState == MotorState.STARTING)
                    and (hudIndicatorId == self.indicators.battery.name or hudIndicatorId == self.indicators.oil.name)
                    and targetColor == colors.DEFAULT then
                targetColor = colors.WARNING
                isRoutineIgnitionIndicator = true
            end
        else
            local activeData = activeIndicators[hudIndicatorId]
            if activeData and mutateActiveState then
                activeData.isActive = false
            end
        end

        return targetColor, isRoutineIgnitionIndicator
    end

    g_currentMission.hud.speedMeter.speedTextSize = self:scalePixelToScreenHeight(43)
    local speedBgX, speedBgY = g_currentMission.hud.speedMeter.speedBg:getPosition()
    local posX = speedBgX + g_currentMission.hud.speedMeter.speedGaugeCenterOffsetX
    local posY = speedBgY + g_currentMission.hud.speedMeter.speedGaugeCenterOffsetY

    for hudIndicatorId, hudIndicatorData in pairs(self.indicators) do
        local icon = hudIndicatorData.icon
        local targetColor, isRoutineIgnitionIndicator = calculateIndicatorTargetColor(hudIndicatorId, true)
        local activeIndicatorData = activeIndicators[hudIndicatorId]
        local isIndicatorVisible = true

        icon:setPosition(posX + hudIndicatorData.offsetX, posY + hudIndicatorData.offsetY)
        if hudIndicatorId == self.indicators.preheat.name and not spec.isDieselVehicle then
            isIndicatorVisible = false
        elseif hudIndicatorId == self.indicators.coolant.name and spec.isElectricVehicle then
            isIndicatorVisible = false
        elseif hudIndicatorId ~= self.indicators.preheat.name then
            isIndicatorVisible = hudIndicatorData.year < spec.year
        end

        icon:setVisible(isIndicatorVisible)

        local isAudibleIndicator = targetColor ~= colors.DEFAULT and targetColor ~= colors.COOL
        local shouldActivateIndicator = isIndicatorVisible and isAudibleIndicator and not isRoutineIgnitionIndicator
        self:syncIndicatorActivation(hudIndicatorId, shouldActivateIndicator, targetColor)

        local blinkWhileActive = activeIndicatorData ~= nil and activeIndicatorData.blinkWhileActive == true
        local displayColor = isRoutineIgnitionIndicator and targetColor or self:applyIndicatorBlink(hudIndicatorId, targetColor, blinkWhileActive)
        icon:setColor(unpack(displayColor))
        icon:render()
    end

    local engineTemp, transTemp, systemVoltageV = spec.engineTemperature, spec.transmissionTemperature, spec.systemVoltageV
    local motorLoad = 0
    if vehicle:getIsMotorStarted() then
        motorLoad = self:updateMotorLoadAverage(math.clamp(tonumber(spec.dynamicMotorLoad) or 0, 0, 1))
    end
    self.telemetryDisplayValues.motorLoad = motorLoad

    local tempSign = "°C"
    local voltageSing = "V"

    if g_gameSettings:getValue(GameSettings.SETTING.USE_FAHRENHEIT) then
        engineTemp = engineTemp * 1.8 + 32
        transTemp = transTemp * 1.8 + 32
        tempSign = "°F"
    end

    local tempText = string.format("%.0f%s", engineTemp, tempSign)
    local transTempText = nil
    if hasCVTTransmission(vehicle) or hasCVTAddon(vehicle) then
        transTempText = string.format("%.0f%s", transTemp, tempSign)
    end

    local batteryVoltageText = formatValue(systemVoltageV, "%.1f") .. voltageSing
    local motorText = string.format("%.0f%%", math.max(motorLoad * 100, 0))

    local batteryVoltageTextColor = {1, 1, 1, 1}
    if systemVoltageV < 12 then
        batteryVoltageTextColor = colors.WARNING
    end

    local motorLoadTextColor = {1, 1, 1, 1}
    if motorLoad > RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD then
        motorLoadTextColor = colors.WARNING
    end

    if not spec.isElectricVehicle then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
        setTextBold(true)

        ---Draws one gauge value in its colour
    -- @param table indicator gauge element
    -- @param any value value to draw
    -- @param table color rgba channels
    local function renderIndicatorValue(indicator, value, color)
            if value == nil or not indicator.icon.visible then
                return
            end

            local iconX, iconY = indicator.icon:getPosition()
            local valueSize = self.indicatorValueText.size
            local valueWidth = getTextWidth(valueSize, value)
            if indicator.valueMaxWidth ~= nil and valueWidth > indicator.valueMaxWidth then
                valueSize = valueSize * indicator.valueMaxWidth / valueWidth
            end
            local valueCenterX = iconX + indicator.icon.width * 0.5 + indicator.valueOffsetX
            local valueY = iconY + indicator.valueOffsetY

            setTextColor(color[1], color[2], color[3], color[4])
            renderText(
                valueCenterX,
                valueY,
                valueSize,
                value
            )
        end

        local defaultTextColor = {1, 1, 1, 1}
        renderIndicatorValue(self.indicators.coolant, tempText, defaultTextColor)
        renderIndicatorValue(self.indicators.transmission, transTempText, defaultTextColor)
        renderIndicatorValue(self.indicators.engine, motorText, motorLoadTextColor)
        renderIndicatorValue(self.indicators.battery, batteryVoltageText, batteryVoltageTextColor)
        setTextColor(1, 1, 1, 1)
    end

    if RMS_Drivetrain == nil or not RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        self:drawWheelSlipDisplay(spec, posX, posY)
    end
    self:drawDrivetrainDisplay(vehicle, spec, posX, posY)
    self:drawParkBrakeDisplay(vehicle)

    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
    setTextBold(false)
end

---Draws the wheel slip readout
-- @param table spec vehicle spec
-- @param float posX x position
-- @param float posY y position
function RMS_Hud:drawWheelSlipDisplay(spec, posX, posY)
    if self.wheelSlipHud == nil or self.wheelSlipHud.icon == nil then
        return
    end

    local wheelSlip = math.clamp(tonumber(spec.wheelSlipIntensity) or 0, 0, 1)

    local icon = self.wheelSlipHud.icon
    icon:setPosition(posX + self.wheelSlipHud.offsetX, posY + self.wheelSlipHud.offsetY)
    icon:setVisible(true)
    icon:setColor(1, 1, 1, 1)
    icon:render()

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(posX + self.wheelSlipHud.textOffsetX, posY + self.wheelSlipHud.textOffsetY, self.wheelSlipHud.textSize, string.format("%.0f%%", wheelSlip * 100))
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

---Draws the drive mode, the differential lock and the park brake
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param float posX x position
-- @param float posY y position
function RMS_Hud:drawDrivetrainDisplay(vehicle, spec, posX, posY)
    if self.drivetrainHud == nil or RMS_Drivetrain == nil then
        return
    end

    if not RMS_Drivetrain.getIsAvailable(vehicle) then
        return
    end

    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then
        return
    end

    local colors = RMS_Breakdowns.COLORS
    local iconId, color
    local showAutoBadge = false
    local windupStress = tonumber(state.windupStress) or 0
    local windupWarningActive = state.windupActive == true and windupStress > RMS_Config.DRIVETRAIN.WINDUP_4WD_WARNING_THRESHOLD

    if state.diffLockEngaged then
        local fourWheelDrive = state.driveMode == RMS_Drivetrain.MODE.FOUR_WD
            or (state.driveMode == RMS_Drivetrain.MODE.AUTO and state.autoEngaged)
        iconId = (fourWheelDrive and RMS_Drivetrain.getHasCenterDifferential(vehicle)) and "diffLockCenter" or "diffLockRear"
        color = colors.WARNING

        if windupStress > RMS_Config.DRIVETRAIN.WINDUP_CRITICAL_THRESHOLD then
            local blinkOn = math.floor((g_time or 0) / 250) % 2 == 0
            color = blinkOn and colors.CRITICAL or colors.WARNING
        end
    else
        if not RMS_Drivetrain.getHasCenterDifferential(vehicle) then
            iconId = "diffLockRear"
            color = colors.DEFAULT
        elseif state.driveMode == RMS_Drivetrain.MODE.TWO_WD then
            iconId = "drivelineOpen"
            color = {1, 1, 1, 0.85}
        elseif state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
            iconId = "drivelineEngaged"
            color = windupWarningActive and colors.WARNING or RMS_Hud.COLOR_GAME_GREEN
        else
            iconId = state.autoEngaged and "drivelineEngaged" or "drivelineOpen"
            color = state.autoEngaged and (windupWarningActive and colors.WARNING or RMS_Hud.COLOR_GAME_GREEN) or {1, 1, 1, 0.85}
            showAutoBadge = true
        end
    end

    local iconData = self.drivetrainHud.icons[iconId]
    if iconData == nil then
        return
    end

    local overlay = iconData.overlay
    overlay:setPosition(posX + self.drivetrainHud.centerX - iconData.width2, posY + self.drivetrainHud.centerY - iconData.height2)
    overlay:setVisible(true)
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:render()

    if showAutoBadge then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
        setTextBold(true)
        setTextColor(color[1], color[2], color[3], color[4])
        renderText(posX + self.drivetrainHud.autoBadgeOffsetX, posY + self.drivetrainHud.autoBadgeOffsetY, self.drivetrainHud.autoBadgeSize, "AUTO")
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
        setTextBold(false)
        setTextColor(1, 1, 1, 1)
    end
end

---Draws the park brake indicator
-- @param table vehicle vehicle
function RMS_Hud:drawParkBrakeDisplay(vehicle)
    if self.parkBrakeHud == nil or self.parkBrakeHud.icon == nil then
        return
    end
    if not RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED or RMS_Drivetrain == nil then
        return
    end

    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil or state.parkExternallyManaged then
        return -- EV's own parking brake (and HUD) takes over
    end

    local sm = g_currentMission.hud.speedMeter
    if sm == nil or sm.gearIcon == nil then
        return
    end

    local gearIconX, gearIconY = sm.gearIcon:getPosition()
    local gearIconHeight = sm.gearIcon.height or 0
    local icon = self.parkBrakeHud.icon
    icon:setPosition(gearIconX - self.parkBrakeHud.width - self.parkBrakeHud.gapX,
        gearIconY + (gearIconHeight - (self.parkBrakeHud.height or 0)) * 0.5 + (self.parkBrakeHud.offsetY or 0))
    icon:setVisible(true)

    local colors = RMS_Breakdowns.COLORS
    local color = state.parkBrake and colors.CRITICAL or colors.DEFAULT
    icon:setColor(color[1], color[2], color[3], color[4])
    icon:render()
end


---Draws the fuel consumption and load mass cards
function RMS_Hud:drawTelemetryCards()
    local speedMeter = g_currentMission.hud.speedMeter
    if speedMeter == nil or speedMeter.speedBg == nil then
        return
    end

    local cardRightX = speedMeter:getPosition()
    cardRightX = self:drawLoadMass(cardRightX) or cardRightX
    self:drawFuelConsumption(cardRightX)
end

---Returns the widest steering assist work area of the whole combination
-- @param table vehicle controlled vehicle
-- @return float width working width in metres
local function getSteeringAssistWidth(vehicle)
    local width = 0
    local root = vehicle.rootVehicle or vehicle

    for _, child in pairs(root.childVehicles or {}) do
        local workAreaSpec = child.spec_workArea
        if workAreaSpec ~= nil and workAreaSpec.workAreas ~= nil then
            for _, workArea in pairs(workAreaSpec.workAreas) do
                if g_workAreaTypeManager:getWorkAreaTypeIsSteeringAssistArea(workArea.type) then
                    width = math.max(width, tonumber(workArea.workWidth) or 0)
                end
            end
        end
    end

    return width
end

---Returns the fuel consumption per worked area
-- @return float? rate consumption per hectare
function RMS_Hud:getConsumptionAreaRate()
    local vehicle = self.vehicle
    if vehicle == nil then
        return 0, 0
    end

    local speed = vehicle.getLastSpeed ~= nil and (tonumber(vehicle:getLastSpeed()) or 0) or 0
    local width = vehicle.getAttacherToolWorkingWidth ~= nil and (tonumber(vehicle:getAttacherToolWorkingWidth()) or 0) or 0

    -- steering assist width fallback
    if width <= 0 then
        width = getSteeringAssistWidth(vehicle)
    end

    local guidanceSpec = vehicle.spec_globalPositioningSystem
    if guidanceSpec ~= nil and guidanceSpec.guidanceData ~= nil and guidanceSpec.guidanceData.width ~= nil then
        width = tonumber(guidanceSpec.guidanceData.width) or width
    end

    return speed, (speed * width) / 10
end

---Clears the consumption samples and their averages
function RMS_Hud:resetConsumptionAverages()
    local state = self.consumption
    state.buckets = {}
    state.current = { fuel = 0, time = 0, litres = 0, hectares = 0 }
    state.timer = 0
    state.perHour = 0
    state.perArea = nil
end

---Samples the consumption and refreshes both averages once a second
-- @param float consumptionPerHour consumption in units per hour
-- @param float areaRate worked area rate in hectares per hour
function RMS_Hud:updateConsumptionAverages(consumptionPerHour, areaRate)
    local state = self.consumption
    local dt = tonumber(g_currentDt) or 0
    local current = state.current

    current.fuel = current.fuel + consumptionPerHour * dt
    current.time = current.time + dt

    if areaRate > 0 then
        current.litres = current.litres + consumptionPerHour * dt / (60 * 60 * 1000)
        current.hectares = current.hectares + areaRate * dt / (60 * 60 * 1000)
    end

    state.timer = state.timer + dt
    if state.timer < RMS_Hud.CONSUMPTION_REFRESH_INTERVAL then
        return
    end
    state.timer = 0

    table.insert(state.buckets, 1, current)
    while #state.buckets > RMS_Hud.CONSUMPTION_PER_AREA_BUCKETS do
        table.remove(state.buckets)
    end
    state.current = { fuel = 0, time = 0, litres = 0, hectares = 0 }

    local fuelSum, timeSum, litresSum, hectaresSum = 0, 0, 0, 0
    for index, bucket in ipairs(state.buckets) do
        if index <= RMS_Hud.CONSUMPTION_PER_HOUR_BUCKETS then
            fuelSum = fuelSum + bucket.fuel
            timeSum = timeSum + bucket.time
        end
        litresSum = litresSum + bucket.litres
        hectaresSum = hectaresSum + bucket.hectares
    end

    state.perHour = timeSum > 0 and fuelSum / timeSum or 0
    state.perArea = hectaresSum > 0.0001 and litresSum / hectaresSum or nil
end

---Samples the engine load and refreshes its average once a second
-- @param float motorLoad current engine load between 0 and 1
-- @return float average averaged engine load
function RMS_Hud:updateMotorLoadAverage(motorLoad)
    local state = self.motorLoadAverage
    local dt = tonumber(g_currentDt) or 0

    state.current.value = state.current.value + motorLoad * dt
    state.current.time = state.current.time + dt
    state.timer = state.timer + dt

    if state.timer >= RMS_Hud.CONSUMPTION_REFRESH_INTERVAL then
        state.timer = 0
        table.insert(state.buckets, 1, state.current)
        while #state.buckets > RMS_Hud.MOTOR_LOAD_BUCKETS do
            table.remove(state.buckets)
        end
        state.current = { value = 0, time = 0 }
    end

    local valueSum, timeSum = 0, 0
    for _, bucket in ipairs(state.buckets) do
        valueSum = valueSum + bucket.value
        timeSum = timeSum + bucket.time
    end

    return timeSum > 0 and valueSum / timeSum or motorLoad
end

---Draws the fuel consumption card
-- @param float cardRightX right edge of the card
function RMS_Hud:drawFuelConsumption(cardRightX)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or vehicle.spec_motorized == nil then
        return
    end

    local _, fuelCapacity, fuelType = SpeedMeterDisplay.getVehicleFuelLevelAndCapacity(vehicle)
    if fuelCapacity == nil or fuelCapacity <= 0 then
        return
    end

    local motorizedSpec = vehicle.spec_motorized
    local consumptionPerHour = 0
    if vehicle:getIsMotorStarted() then
        consumptionPerHour = math.max(tonumber(motorizedSpec.lastFuelUsageDisplay or motorizedSpec.lastFuelUsage) or 0, 0)
    end

    local speed, areaRate = self:getConsumptionAreaRate()
    self:updateConsumptionAverages(consumptionPerHour, speed > 0.9 and areaRate or 0)

    local isElectric = fuelType == FillType.ELECTRICCHARGE
    local isMethane = fuelType == FillType.METHANE
    local perHourUnit = isElectric and "kW" or (isMethane and "kg/h" or "L/h")
    local perAreaUnit = isElectric and "kWh/ha" or (isMethane and "kg/ha" or "L/ha")
    local perHourStr = formatConsumptionValue(self.consumption.perHour)
    local perAreaStr = self.consumption.perArea ~= nil and formatConsumptionValue(self.consumption.perArea) or "-"

    local speedMeter = g_currentMission.hud.speedMeter
    local size = self.loadMassText.size or 0.01
    local padH = self.loadMassText.paddingH or 0
    local padV = self.loadMassText.paddingV or 0
    local iconWidth = self.fuelConsumptionHud.width or 0
    local iconHeight = self.fuelConsumptionHud.height or 0
    local iconGap = self.fuelConsumptionHud.iconGap or 0
    local unitGap = self:scalePixelToScreenWidth(4)
    local separatorGap = self:scalePixelToScreenWidth(20)
    local perHourValueWidth = getTextWidth(size, perHourStr)
    local perHourUnitWidth = getTextWidth(size, perHourUnit)
    local perAreaValueWidth = getTextWidth(size, perAreaStr)
    local perAreaUnitWidth = getTextWidth(size, perAreaUnit)
    local perHourWidth = perHourValueWidth + unitGap + perHourUnitWidth
    local perAreaWidth = perAreaValueWidth + unitGap + perAreaUnitWidth
    local fullWidth = iconWidth + iconGap + perHourWidth + separatorGap + perAreaWidth
    local textHeight = getTextHeight(size, perHourStr)
    local panelH = textHeight + padV * 2
    local panelW = fullWidth + padH * 2
    local _, smBottomY = speedMeter:getPosition()
    local panelX = cardRightX - panelW
    local panelY = (smBottomY - panelH) * 0.5
    local startX = panelX + padH
    local textX = startX + iconWidth + iconGap
    local textY = panelY + panelH * 0.5 + self:scalePixelToScreenHeight(2)

    local bg = HUD.COLOR.BACKGROUND
    drawFilledRectRound(panelX, panelY, panelW, panelH, 0.35, bg[1], bg[2], bg[3], bg[4])

    local icon = self.fuelConsumptionHud.icon
    local green = HUD.COLOR.ACTIVE
    icon:setPosition(startX, panelY + (panelH - iconHeight) * 0.5)
    icon:setColor(green[1], green[2], green[3], green[4])
    icon:setVisible(true)
    icon:render()

    local separatorLineW = 1 / g_screenWidth
    local separatorLineH = panelH * 0.55
    local separatorLineX = textX + perHourWidth + separatorGap * 0.5 - separatorLineW * 0.5
    local separatorLineY = panelY + (panelH - separatorLineH) * 0.5
    self:drawNotificationDivider(separatorLineX, separatorLineY, separatorLineW, separatorLineH, green)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(textX, textY, size, perHourStr)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.55)
    renderText(textX + perHourValueWidth + unitGap, textY, size, perHourUnit)

    textX = textX + perHourWidth + separatorGap
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(textX, textY, size, perAreaStr)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.55)
    renderText(textX + perAreaValueWidth + unitGap, textY, size, perAreaUnit)

    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
end


---Returns the colour of a load severity
-- @param integer severity load severity
-- @return table color rgba channels
function RMS_Hud:getLoadSeverityColor(severity)
    local colors = RMS_Breakdowns.COLORS
    local s = math.clamp(tonumber(severity) or 0, 0, 1)

    if s <= 0 then
        return HUD.COLOR.ACTIVE
    end

    return {
        colors.WARNING[1] + (colors.CRITICAL[1] - colors.WARNING[1]) * s,
        colors.WARNING[2] + (colors.CRITICAL[2] - colors.WARNING[2]) * s,
        colors.WARNING[3] + (colors.CRITICAL[3] - colors.WARNING[3]) * s,
        1
    }
end

---Formats a mass in tons
-- @param float massTons mass in tons
-- @return string text formatted mass
function RMS_Hud:formatMass(massTons)
    return formatValue(math.max(tonumber(massTons) or 0, 0), "%.1f") .. " t"
end

---Returns a mass that only changes past a threshold, so the readout stops flickering
-- @param string cacheKey key the mass is cached under
-- @param float massTons mass in tons
-- @return float mass stable mass
function RMS_Hud:getStableDisplayMass(cacheKey, massTons)
    local mass = math.max(tonumber(massTons) or 0, 0)
    local displayStep = 0.1
    local roundedMass = math.floor(mass / displayStep + 0.5) * displayStep
    local cachedMass = tonumber(self.loadMassText[cacheKey])

    if cachedMass == nil or math.abs(mass - cachedMass) >= displayStep then
        cachedMass = roundedMass
        self.loadMassText[cacheKey] = cachedMass
    end

    return cachedMass
end

---Draws the load mass card
-- @param float cardRightX right edge of the card
function RMS_Hud:drawLoadMass(cardRightX)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.getTotalMass == nil then
        return cardRightX
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return cardRightX
    end

    local speedMeter = g_currentMission.hud.speedMeter
    if speedMeter == nil or speedMeter.speedBg == nil then
        return cardRightX
    end

    local selfMass  = tonumber(vehicle:getTotalMass(true)) or 0
    local totalMass = tonumber(vehicle:getTotalMass())     or 0
    local lockedHookLiftContainer = RMS_Utils.getLockedHookLiftContainer(vehicle)
    local carriedMass = lockedHookLiftContainer ~= nil and (tonumber(lockedHookLiftContainer:getTotalMass()) or 0) or 0
    local vehicleMass = math.min(selfMass + carriedMass, totalMass)
    local towedMass = math.max(totalMass - vehicleMass, 0)

    local loadColor = HUD.COLOR.ACTIVE

    if spec.isExcludedVehicle ~= true and towedMass > 0.1 then
        local motor      = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
        local horsepower = math.max(((motor ~= nil and motor.peakMotorPower) or 0) * 1.36, 0.001)
        local isTruck    = spec.isTruck == true
        local ratioBasis = isTruck and totalMass or towedMass
        local powerToWeight = horsepower / math.max(ratioBasis, 0.01)

        local threshold, fullEffect = RMS_Utils.getHeavyTrailerRatioLevels(isTruck)

        local trailerSeverity = RMS_Utils.calculateQuadraticMultiplier(powerToWeight, threshold, true, fullEffect)

        loadColor = self:getLoadSeverityColor(trailerSeverity)
    end

    local _, smBottomY = g_currentMission.hud.speedMeter:getPosition()
    local padH = self.loadMassText.paddingH or 0
    local padV = self.loadMassText.paddingV or 0
    local size = self.loadMassText.size or 0.01
    local sep  = "     "

    local displaySelfMass = self:getStableDisplayMass("displaySelfMass", vehicleMass)
    local displayTowedMass = self:getStableDisplayMass("displayTowedMass", towedMass)
    local displayTotalMass = displaySelfMass + displayTowedMass

    local tractorLabel = g_i18n:getText("rms_hud_mass_tractor") .. "  "
    local tractorValue = self:formatMass(displaySelfMass)
    local chargeLabel  = g_i18n:getText("rms_hud_mass_towed")   .. "  "
    local chargeValue  = self:formatMass(displayTowedMass)
    local totalLabel   = g_i18n:getText("rms_hud_mass_total")    .. "  "
    local totalValue   = self:formatMass(displayTotalMass)

    local wTL  = getTextWidth(size, tractorLabel)
    local wTV  = getTextWidth(size, tractorValue)
    local wCL  = getTextWidth(size, chargeLabel)
    local wCV  = getTextWidth(size, chargeValue)
    local wOL  = getTextWidth(size, totalLabel)
    local wOV  = getTextWidth(size, totalValue)
    local wsep = getTextWidth(size, sep)
    local w1   = wTL + wTV
    local w2   = wCL + wCV
    local w3   = wOL + wOV
    local fullW = w1 + wsep + w2 + wsep + w3

    local textHeight = getTextHeight(size, totalValue)
    local panelH = textHeight + padV * 2
    local panelW = fullW + padH * 2
    local panelX = cardRightX - panelW
    local panelY = (smBottomY - panelH) * 0.5
    local startX = panelX + padH
    local textY  = panelY + panelH * 0.5 + self:scalePixelToScreenHeight(2)

    local bg = HUD.COLOR.BACKGROUND
    drawFilledRectRound(panelX, panelY, panelW, panelH, 0.35, bg[1], bg[2], bg[3], bg[4])

    local sepLineW = 1 / g_screenWidth
    local sepLineH = panelH * 0.55
    local sepLineY = panelY + (panelH - sepLineH) * 0.5
    local green    = HUD.COLOR.ACTIVE
    self:drawNotificationDivider(startX + w1 + wsep * 0.5 - sepLineW * 0.5,             sepLineY, sepLineW, sepLineH, green)
    self:drawNotificationDivider(startX + w1 + wsep + w2 + wsep * 0.5 - sepLineW * 0.5, sepLineY, sepLineW, sepLineH, green)

    local cx = startX
    local dimLabel = {1, 1, 1, 0.55}

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)

    setTextBold(false)
    setTextColor(unpack(dimLabel))
    renderText(cx, textY, size, tractorLabel)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(cx + wTL, textY, size, tractorValue)

    cx = cx + w1 + wsep

    setTextBold(false)
    setTextColor(unpack(dimLabel))
    renderText(cx, textY, size, chargeLabel)
    setTextBold(true)
    setTextColor(loadColor[1], loadColor[2], loadColor[3], 1)
    renderText(cx + wCL, textY, size, chargeValue)

    cx = cx + w2 + wsep

    setTextBold(false)
    setTextColor(unpack(dimLabel))
    renderText(cx, textY, size, totalLabel)
    setTextBold(true)
    setTextColor(loadColor[1], loadColor[2], loadColor[3], 1)
    renderText(cx + wOL, textY, size, totalValue)

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)

    return panelX - (self.telemetryCardGap or 0)
end


local INSPECTED_DAMAGE_CEILING = 0.9

-- damage bar filling of each condition tier
local TIER_DAMAGE_AMOUNTS = {0.0, 0.25, 0.5, 0.75, INSPECTED_DAMAGE_CEILING}

local originalSpeedMeterDisplayDraw = SpeedMeterDisplay.draw
SpeedMeterDisplay.draw = function(self, ...)
    local vehicle = self.vehicle
    if vehicle == nil or not self.isVehicleDrawSafe or vehicle.rootVehicle == nil then
        return originalSpeedMeterDisplayDraw(self, ...)
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and spec.isExcludedVehicle then
        return originalSpeedMeterDisplayDraw(self, ...)
    end

    local rmsHud = RMS_Main ~= nil and RMS_Main.hud or nil
    local dashExt = nil
    if spec ~= nil and rmsHud ~= nil and rmsHud.dashExtension ~= nil and rmsHud.dashExtension.stretchWidth ~= nil then
        dashExt = rmsHud.dashExtension

        local extScaleWidth = self.gearBarScaleWidth
        if vehicle.spec_motorized ~= nil then
            extScaleWidth = extScaleWidth + self.fuelBarScaleWidth
        end
        if vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount() ~= nil then
            extScaleWidth = extScaleWidth + self.repairBarScaleWidth
        end

        local basePosX, basePosY = self:getPosition()
        local speedBgX = basePosX - self.speedBgRight.width - extScaleWidth - self.speedBg.width

        local halfWidth = self.speedBg.width * 0.5
        local fullHeight = self.speedBg.height
        dashExt.leftHalf:setDimension(halfWidth, fullHeight)
        dashExt.rightHalf:setDimension(halfWidth, fullHeight)
        dashExt.strip:setDimension(dashExt.stretchWidth, fullHeight)

        dashExt.leftHalf:setPosition(speedBgX - dashExt.stretchWidth, basePosY)
        dashExt.strip:setPosition(speedBgX + halfWidth - dashExt.stretchWidth, basePosY)
        dashExt.rightHalf:setPosition(speedBgX + halfWidth, basePosY)

        dashExt.leftHalf:render()
        dashExt.strip:render()
        dashExt.rightHalf:render()

        self.speedBg:setVisible(false)
    end

    local selectedTool = nil
    local useCustomValue = false
    local customDamageAmount = 0

    for _, implement in ipairs(vehicle.rootVehicle.childVehicles) do
        if implement:getIsSelected() and implement.getDamageShowOnHud ~= nil and implement:getDamageShowOnHud() then
            selectedTool = implement
            break
        end
    end

    if selectedTool ~= nil then
        useCustomValue = true
        if selectedTool.getServiceLevel ~= nil then
            local condition, isCompleteInspection = vehicle:getLastInspectedCondition()
            condition = math.clamp(condition or 0, 0, 1)
            if isCompleteInspection == nil then
                customDamageAmount = 1.0
            elseif isCompleteInspection then
                customDamageAmount = math.min(1 - condition, INSPECTED_DAMAGE_CEILING)
            else
                customDamageAmount = TIER_DAMAGE_AMOUNTS[RMS_Utils.getConditionTier(condition)]
            end
        else
            customDamageAmount = selectedTool:getDamageAmount()
        end
    end

    local originalGetDamageMethods = {}
    if useCustomValue then
        local allVehicles = vehicle.rootVehicle.childVehicles
        
        for _, v in ipairs(allVehicles) do
            if v.getDamageAmount ~= nil then
                originalGetDamageMethods[v] = v.getDamageAmount
                v.getDamageAmount = function()
                    return customDamageAmount
                end
            end
        end
    end

    local ok, result = pcall(originalSpeedMeterDisplayDraw, self, ...)

    if dashExt ~= nil then
        self.speedBg:setVisible(true)
    end

    if useCustomValue then
        for vehicleInstance, originalMethod in pairs(originalGetDamageMethods) do
            vehicleInstance.getDamageAmount = originalMethod
        end
    end

    if not ok then
        error(result, 0)
    end

    return result
end


---Adds the RMS lines to the vanilla vehicle info box
-- @param table box info box
function RMS_Hud:showInfoVehicle(box)
    if self.spec_RealisticMechanicalSystems ~= nil and not self.spec_RealisticMechanicalSystems.isExcludedVehicle then
        local spec = self.spec_RealisticMechanicalSystems
        
        local remaining = self:getMaintenanceInterval() - self:getHoursSinceLastMaintenance()
        local hoursText = string.format("%.0f %s", math.abs(remaining), g_i18n:getText("rms_spec_op_hours_short"))
        local serviceText = remaining >= 0 and hoursText
            or string.format(g_i18n:getText("rms_ws_value_service_overdue"), hoursText)

        box:addLine(g_i18n:getText('rms_ws_label_condition'), RMS_Utils.formatCondition(self:getLastInspectedCondition()))
        box:addLine(g_i18n:getText("rms_ws_label_next_service"), serviceText)

        
        if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY and spec.currentState ~= RealisticMechanicalSystems.STATUS.BROKEN then
            local maintenanceStatusText = string.format(g_i18n:getText("rms_spec_last_maintenance_until_format"), g_i18n:getText(spec.currentState), RMS_Utils.formatFinishTime(self:getServiceFinishTime()))
            box:addLine(maintenanceStatusText)
        end
    end
end

Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, RMS_Hud.showInfoVehicle)


source(g_currentModDirectory .. "scripts/RMS_HudDebug.lua")
