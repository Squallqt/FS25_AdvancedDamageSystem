ADS_Hud = {}
ADS_Hud.modDirectory = g_currentModDirectory
ADS_Hud.debugViewMode = ADS_Hud.debugViewMode or "default"
local ADS_Hud_mt = Class(ADS_Hud, HUDDisplay)

ADS_Hud.ROUNDED_PANEL_TEXTURE_SIZE = 64
ADS_Hud.ROUNDED_PANEL_CORNER_SIZE = 5
ADS_Hud.ROUNDED_PANEL_UV = {
    topLeft     = {  0,  0,  5,  5 },
    top         = {  5,  0, 54,  5 },
    topRight    = { 59,  0,  5,  5 },
    left        = {  0,  5,  5, 54 },
    center      = {  5,  5, 54, 54 },
    right       = { 59,  5,  5, 54 },
    bottomLeft  = {  0, 59,  5,  5 },
    bottom      = {  5, 59, 54,  5 },
    bottomRight = { 59, 59,  5,  5 }
}
ADS_Hud.COLOR_GAME_GREEN = HUD.COLOR.ACTIVE
ADS_Hud.NOTIFICATION_INPUT_CONTEXT_NAME = "ADS_NOTIFICATION"
ADS_Hud.CONSUMPTION_PER_AREA_INTERPOLATION_SPEED = 0.009
ADS_Hud.MOTOR_LOAD_DISPLAY_INTERPOLATION_SPEED = 0.0035
ADS_Hud.MOTOR_LOAD_HIGH_DISPLAY_INTERPOLATION_SPEED = 0.0015

function ADS_Hud:new()
	local self = ADS_Hud:superClass().new(ADS_Hud_mt)
	self.vehicle = nil
    self.telemetryDisplayValues = {
        consumptionPerArea = 0,
        motorLoad = 0
    }

    self.roundedPanelOverlay = Overlay.new(self.modDirectory .. "hud/panelRounded.dds", 0, 0, 0, 0)

    g_overlayManager:addTextureConfigFile(ADS_Hud.modDirectory .. "hud/ads_dashboardHud.xml", "ads_DashboardHud")
    self.wheelSlipHud = {
        icon = g_overlayManager:createOverlay("ads_DashboardHud.wheelSlip", 0, 0, 0, 0)
    }
    self.fuelConsumptionHud = {
        icon = g_overlayManager:createOverlay("ads_DashboardHud.fuelConsumption", 0, 0, 0, 0)
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
            drivelineOpen    = { overlay = g_overlayManager:createOverlay("ads_DashboardHud.drivelineOpen", 0, 0, 0, 0),    aspect = 45 / 59, height = 21 },
            drivelineEngaged = { overlay = g_overlayManager:createOverlay("ads_DashboardHud.drivelineEngaged", 0, 0, 0, 0), aspect = 45 / 59, height = 21 },
            diffLockCenter   = { overlay = g_overlayManager:createOverlay("ads_DashboardHud.diffLockCenter", 0, 0, 0, 0),   aspect = 44 / 59, height = 21 },
            diffLockRear     = { overlay = g_overlayManager:createOverlay("ads_DashboardHud.diffLockRear", 0, 0, 0, 0),     aspect = 44 / 59, height = 21 }
        }
    }

    self.parkBrakeHud = {
        icon = g_overlayManager:createOverlay("ads_DashboardHud.parkBrake", 0, 0, 0, 0)
    }

    self.indicators = {
        engine = {
            name = 'engine',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.engine", 0, 0, 0, 0),
            year = 1990
        },
        transmission = {
            name = 'transmission',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.transmission", 0, 0, 0, 0),
            year = 1990,
        },
        brakes = {
            name = 'brakes',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.brakes", 0, 0, 0, 0),
            year = 1980
        },
        battery = {
            name = 'battery',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.battery", 0, 0, 0, 0),
            year = 1950
        },
        coolant = {
            name = 'coolant',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.coolant", 0, 0, 0, 0),
            year = 1950
        },
        warning = {
            name = 'warning',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.warning", 0, 0, 0, 0),
            year = 1990
        },
        preheat = {
            name = 'preheat',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.preheat", 0, 0, 0, 0)
        },
        service = {
            name = 'service',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.service", 0, 0, 0, 0),
            year = 1970
        },
        oil = {
            name = 'oil',
            icon = g_overlayManager:createOverlay("ads_DashboardHud.oil", 0, 0, 0, 0),
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
        x = 0.40,
        y = 0.14,   
        width = 0.20,
        padding = 0.01,
        lineHeight = 0.016,
        titleLineHeight = 0.018,
        titleSpacing = 0.006,
        titleDividerHeight = 0.001,
        dividerSpacing = 0.003,
        bottomDividerSpacing = 2,
        persistentDurationMs = 60000,
        dividerBackground = "dataS/menu/base/graph_pixel.dds",
        title = nil,
        text = nil,
        endTime = 0,
        isVisible = false,
        isPersistent = false,
        closeGlyphSize = 26,
        closeGlyphTextSpacing = 6
    }

    self.notificationDividerOverlay = Overlay.new(self.notificationPanel.dividerBackground, 0, 0, 0, 0)
    self.notificationCloseGlyph = nil
    self.notificationCloseGlyphInputMode = nil
    self.isNotificationInputActive = false

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

function ADS_Hud:delete()
    self.roundedPanelOverlay:delete()
    self.roundedPanelOverlay = nil
    self.notificationDividerOverlay:delete()
    self.notificationDividerOverlay = nil
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

    ADS_Hud:superClass().delete(self)
end

function ADS_Hud:setVisible(isVisible)
    self.activeVehicleDebugPanel.isVisible = isVisible
end

function ADS_Hud:setVehicle(vehicle)
    if self.vehicle ~= vehicle then
        self.indicatorRuntime = {}
        self.activeVehicleDebugCache.lastUpdateTime = -math.huge
        self.activeVehicleDebugCache.vehicle = nil
        self.activeVehicleDebugCache.panel = nil
        self.activeVehicleDebugCache.commands = nil
        self.telemetryDisplayValues.consumptionPerArea = 0
        self.telemetryDisplayValues.motorLoad = 0
    end

    self.vehicle = vehicle
end

function ADS_Hud:getIndicatorRuntimeState(indicatorId)
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

function ADS_Hud:startIndicatorBlink(indicatorId)
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

function ADS_Hud:applyIndicatorBlink(indicatorId, targetColor, blinkWhileActive)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local colors = ADS_Breakdowns ~= nil and ADS_Breakdowns.COLORS or nil
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

function ADS_Hud:tryPlayIndicatorActivationSound(indicatorId, runtimeState, severity)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_AdvancedDamageSystem == nil then
        return false
    end

    local config = self.indicatorSoundConfig ~= nil and self.indicatorSoundConfig[indicatorId] or nil
    if config == nil then
        return false
    end

    if vehicle.getMotorState == nil or vehicle:getMotorState() ~= MotorState.ON then
        return false
    end

    local spec = vehicle.spec_AdvancedDamageSystem
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

    ADS_SoundManager.playSample(sample)
    runtimeState.lastSoundTime = now
    runtimeState.soundPlayedForCurrentActivation = true
    runtimeState.lastSoundSeverity = severity or 0
    return true
end

function ADS_Hud:syncIndicatorActivation(indicatorId, shouldLight, targetColor)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local colors = ADS_Breakdowns ~= nil and ADS_Breakdowns.COLORS or nil
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

function ADS_Hud:getVehicleTypeCategoryLabel(vehicle)
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

local hasCVTTransmission = ADS_Utils.hasCVTTransmission
local hasCVTAddon = ADS_Utils.hasCVTAddon

-- =====================================================================================
--                              DRAW
-- =====================================================================================

function ADS_Hud:draw()
    if g_currentMission == nil then
        return
    end

    local isHudVisible = g_currentMission.hud.isVisible
    self:setNotificationInputActive(isHudVisible and self:hasClosableNotification())

    if not isHudVisible then
        return
    end

    self:drawNotificationPanel()

    if ADS_Config.DEBUG and g_currentMission.isMasterUser and self.vehicle ~= nil and self.activeVehicleDebugPanel.isVisible then
        self:drawActiveVehicleHUD()
    end

    if self.vehicle ~= nil then
        self:drawDashboard()
        self:drawTelemetryCards()
    end
end

-- =====================================================================================
--                              NOTIFICATION PANEL
-- =====================================================================================

function ADS_Hud.showNotification(text, durationMs, title, playSound)
    if ADS_Main ~= nil and ADS_Main.hud ~= nil then
        ADS_Main.hud:setNotification(text, durationMs, title, playSound)
    end
end

function ADS_Hud.hideNotification()
    if ADS_Main ~= nil and ADS_Main.hud ~= nil then
        ADS_Main.hud:clearNotification()
    end
end

function ADS_Hud:setNotification(text, durationMs, title, playSound)
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
    panel.endTime = panel.isPersistent
        and (g_time + math.max(panel.persistentDurationMs or 25000, 0))
        or (g_time + math.max(parsedDurationMs or 3000, 0))
    panel.isVisible = true

    if playSound then
        ADS_SoundManager.playSample(ADS_Main.samples.notification2D)
    end
end

function ADS_Hud:clearNotification()
    local panel = self.notificationPanel
    panel.title = nil
    panel.text = nil
    panel.endTime = 0
    panel.isVisible = false
    panel.isPersistent = false
end

function ADS_Hud:setNotificationInputActive(isActive)
    local inputBinding = g_inputBinding

    if isActive and not self.isNotificationInputActive then
        inputBinding:setContext(ADS_Hud.NOTIFICATION_INPUT_CONTEXT_NAME, true, false)

        local _, eventId = inputBinding:registerActionEvent(InputAction.ADS_CLOSE_NOTIFICATION, self, self.onCloseNotificationInput, false, true, false, true)
        inputBinding:setActionEventTextVisibility(eventId, false)

        self.isNotificationInputActive = true
    elseif not isActive and self.isNotificationInputActive then
        inputBinding:removeActionEventsByTarget(self)
        inputBinding:revertContext(true)

        self.isNotificationInputActive = false
    end
end

function ADS_Hud:onCloseNotificationInput()
    self:closePersistentNotification()
end

function ADS_Hud:hasClosableNotification()
    local panel = self.notificationPanel

    return panel ~= nil and panel.isVisible and panel.isPersistent
end

function ADS_Hud:closePersistentNotification()
    if not self:hasClosableNotification() then
        return false
    end

    self:clearNotification()

    return true
end

function ADS_Hud:wrapNotificationText(text, maxWidth, textSize)
    local words = {}
    for word in tostring(text or ""):gmatch("%S+") do
        table.insert(words, word)
    end

    local lines = {}
    local currentLine = ""

    for _, word in ipairs(words) do
        local candidate = currentLine == "" and word or (currentLine .. " " .. word)

        if currentLine == "" or getTextWidth(textSize, candidate) <= maxWidth then
            currentLine = candidate
        else
            table.insert(lines, currentLine)
            currentLine = word
        end
    end

    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end

    if #lines == 0 then
        table.insert(lines, "")
    end

    return lines
end

function ADS_Hud:drawNotificationDivider(x, y, width, height, color)
    local snappedX = math.floor(x * g_screenWidth + 0.5) / g_screenWidth
    local snappedY = math.floor(y * g_screenHeight + 0.5) / g_screenHeight
    local snappedWidth = math.max(math.floor(width * g_screenWidth + 0.5) / g_screenWidth, 1 / g_screenWidth)
    local snappedHeight = math.max(math.floor(height * g_screenHeight + 0.5) / g_screenHeight, 1 / g_screenHeight)

    local overlay = self.notificationDividerOverlay
    overlay:setPosition(snappedX, snappedY)
    overlay:setDimension(snappedWidth, snappedHeight)
    overlay:setColor(unpack(color))
    overlay:render()
end

function ADS_Hud:getNotificationCloseGlyph(glyphWidth, glyphHeight)
    if self.notificationCloseGlyph == nil then
        self.notificationCloseGlyph = InputGlyphElement.new(g_inputDisplayManager, glyphWidth, glyphHeight)
        self.notificationCloseGlyph:setKeyboardGlyphColor(ADS_Hud.COLOR_GAME_GREEN, {0, 0, 0, 0.8})
        self.notificationCloseGlyph:setButtonGlyphColor(ADS_Hud.COLOR_GAME_GREEN)
    elseif self.notificationCloseGlyph.baseWidth ~= glyphWidth or self.notificationCloseGlyph.baseHeight ~= glyphHeight then
        self.notificationCloseGlyph:delete()
        self.notificationCloseGlyph = InputGlyphElement.new(g_inputDisplayManager, glyphWidth, glyphHeight)
        self.notificationCloseGlyph:setKeyboardGlyphColor(ADS_Hud.COLOR_GAME_GREEN, {0, 0, 0, 0.8})
        self.notificationCloseGlyph:setButtonGlyphColor(ADS_Hud.COLOR_GAME_GREEN)
        self.notificationCloseGlyphInputMode = nil
    end

    local inputMode = g_inputBinding:getInputHelpMode()
    if self.notificationCloseGlyphInputMode ~= inputMode then
        self.notificationCloseGlyph:setAction(InputAction.ADS_CLOSE_NOTIFICATION, nil, nil, true)
        self.notificationCloseGlyphInputMode = inputMode
    end

    return self.notificationCloseGlyph
end

function ADS_Hud:snapScreenRect(x, y, width, height)
    local snappedX = math.floor(x * g_screenWidth + 0.5) / g_screenWidth
    local snappedY = math.floor(y * g_screenHeight + 0.5) / g_screenHeight
    local snappedWidth = math.max(math.floor(width * g_screenWidth + 0.5) / g_screenWidth, 1 / g_screenWidth)
    local snappedHeight = math.max(math.floor(height * g_screenHeight + 0.5) / g_screenHeight, 1 / g_screenHeight)

    return snappedX, snappedY, snappedWidth, snappedHeight
end

function ADS_Hud:renderPanelQuad(x, y, width, height, color, uvs)
    if self.roundedPanelOverlay == nil or width <= 0 or height <= 0 then
        return
    end

    local overlay = self.roundedPanelOverlay
    overlay:setPosition(x, y)
    overlay:setDimension(width, height)
    overlay:setUVs(GuiUtils.getUVs(uvs, {ADS_Hud.ROUNDED_PANEL_TEXTURE_SIZE, ADS_Hud.ROUNDED_PANEL_TEXTURE_SIZE}))
    overlay:setColor(color[1], color[2], color[3], color[4] or 1)
    overlay:render()
end

function ADS_Hud:drawPanelBackground(x, y, width, height, color)
    local panelColor = color or {0, 0, 0, 0.7}

    local panelX, panelY, panelWidth, panelHeight = self:snapScreenRect(x, y, width, height)
    local cornerWidth = math.min(
        math.floor(self:scalePixelToScreenWidth(ADS_Hud.ROUNDED_PANEL_CORNER_SIZE) * g_screenWidth + 0.5) / g_screenWidth,
        panelWidth * 0.5
    )
    local cornerHeight = math.min(
        math.floor(self:scalePixelToScreenHeight(ADS_Hud.ROUNDED_PANEL_CORNER_SIZE) * g_screenHeight + 0.5) / g_screenHeight,
        panelHeight * 0.5
    )
    local leftX = panelX
    local centerX = panelX + cornerWidth
    local rightX = panelX + panelWidth - cornerWidth
    local bottomY = panelY
    local centerY = panelY + cornerHeight
    local topY = panelY + panelHeight - cornerHeight
    local centerWidth = math.max(rightX - centerX, 0)
    local centerHeight = math.max(topY - centerY, 0)
    local uv = ADS_Hud.ROUNDED_PANEL_UV

    self:renderPanelQuad(leftX, bottomY, cornerWidth, cornerHeight, panelColor, uv.bottomLeft)
    self:renderPanelQuad(centerX, bottomY, centerWidth, cornerHeight, panelColor, uv.bottom)
    self:renderPanelQuad(rightX, bottomY, cornerWidth, cornerHeight, panelColor, uv.bottomRight)

    self:renderPanelQuad(leftX, centerY, cornerWidth, centerHeight, panelColor, uv.left)
    self:renderPanelQuad(centerX, centerY, centerWidth, centerHeight, panelColor, uv.center)
    self:renderPanelQuad(rightX, centerY, cornerWidth, centerHeight, panelColor, uv.right)

    self:renderPanelQuad(leftX, topY, cornerWidth, cornerHeight, panelColor, uv.topLeft)
    self:renderPanelQuad(centerX, topY, centerWidth, cornerHeight, panelColor, uv.top)
    self:renderPanelQuad(rightX, topY, cornerWidth, cornerHeight, panelColor, uv.topRight)
end

function ADS_Hud:drawNotificationPanel()
    local panel = self.notificationPanel
    if panel == nil or not panel.isVisible or panel.text == nil then
        return
    end

    if g_time >= panel.endTime then
        self:clearNotification()
        return
    end

    local titleTextSize = self.text.headerSize
    local textSize = self.text.normalSize + 0.003
    local fullTextWidth = panel.width - panel.padding * 2
    local titleTextWidth = fullTextWidth
    local titleLines = {}

    if panel.title ~= nil then
        titleLines = self:wrapNotificationText(panel.title, titleTextWidth, titleTextSize)
    end

    local lines = self:wrapNotificationText(panel.text, fullTextWidth, textSize)
    local baseHeight = panel.padding * 2 + panel.lineHeight
    local hasTitle = #titleLines > 0
    local titleSpacing = hasTitle and panel.titleSpacing or 0
    local titleDividerHeight = hasTitle and panel.titleDividerHeight or 0
    local titleTextExtraSpacing = hasTitle and self:scalePixelToScreenHeight(10) or 0
    local dividerSpacing = hasTitle and (panel.dividerSpacing + self:scalePixelToScreenHeight(5)) or 0
    local bottomDividerTextSpacing = hasTitle and self:scalePixelToScreenHeight((panel.bottomDividerSpacing or 2) + 2) or 0
    local closeGlyphVisible = panel.isPersistent and hasTitle
    local closeGlyphWidth = closeGlyphVisible and self:scalePixelToScreenWidth(panel.closeGlyphSize or 18) or 0
    local closeGlyphHeight = closeGlyphVisible and self:scalePixelToScreenHeight(panel.closeGlyphSize or 18) or 0
    local topSectionHeight = hasTitle and (panel.padding + (#titleLines * panel.titleLineHeight) + dividerSpacing + titleDividerHeight) or 0
    local bottomSectionHeight = hasTitle and (topSectionHeight + dividerSpacing + bottomDividerTextSpacing) or 0
    local dynamicHeight = hasTitle
        and (panel.padding + (#titleLines * panel.titleLineHeight) + titleSpacing + titleTextExtraSpacing + (#lines * panel.lineHeight) + bottomSectionHeight)
        or (panel.padding * 2 + (#lines * panel.lineHeight))
    local anchorCenterY = panel.y + baseHeight * 0.5
    local panelY = anchorCenterY - dynamicHeight * 0.5

    self:drawPanelBackground(
        panel.x,
        panelY,
        panel.width,
        dynamicHeight,
        {0, 0, 0, 0.72}
    )

    local centerX = panel.x + panel.width * 0.5
    local currentY = panelY + dynamicHeight - panel.padding

    if hasTitle then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
        setTextBold(true)
        setTextColor(unpack(ADS_Hud.COLOR_GAME_GREEN))

        for _, line in ipairs(titleLines) do
            renderText(centerX, currentY, titleTextSize, line)
            currentY = currentY - panel.titleLineHeight
        end

        local dividerWidth = panel.width - panel.padding * 2
        local dividerY = currentY - dividerSpacing - titleDividerHeight * 0.5
        self:drawNotificationDivider(panel.x + panel.padding, dividerY, dividerWidth, titleDividerHeight, ADS_Hud.COLOR_GAME_GREEN)

        currentY = currentY - panel.titleSpacing - titleTextExtraSpacing
    end

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)

    for _, line in ipairs(lines) do
        renderText(centerX, currentY, textSize, line)
        currentY = currentY - panel.lineHeight
    end

    if hasTitle then
        local dividerWidth = panel.width - panel.padding * 2
        local bottomDividerY = currentY - dividerSpacing - bottomDividerTextSpacing - titleDividerHeight * 0.5
        self:drawNotificationDivider(panel.x + panel.padding, bottomDividerY, dividerWidth, titleDividerHeight, ADS_Hud.COLOR_GAME_GREEN)

        if closeGlyphVisible then
            local glyph = self:getNotificationCloseGlyph(closeGlyphWidth, closeGlyphHeight)
            if glyph ~= nil then
                local glyphWidth = glyph:getGlyphWidth()
                local okText = "OK"
                local okTextSize = textSize
                local textSpacing = self:scalePixelToScreenWidth(panel.closeGlyphTextSpacing or 6)
                local okTextWidth = getTextWidth(okTextSize, okText)
                local glyphX = centerX - (glyphWidth + textSpacing + okTextWidth) * 0.5
                local glyphY = panelY + math.max((topSectionHeight - titleDividerHeight - closeGlyphHeight) * 0.5, 0)
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

-- =====================================================================================
--                              DASHBOARD
-- =====================================================================================

function ADS_Hud:storeScaledValues()

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

function ADS_Hud:drawDashboard()
    if self.vehicle == nil or self.vehicle.spec_AdvancedDamageSystem == nil or self.vehicle.spec_AdvancedDamageSystem.isExcludedVehicle then
        return
    end

    local vehicle = self.vehicle
    local spec = vehicle.spec_AdvancedDamageSystem
    local colors = ADS_Breakdowns.COLORS
    local activeIndicators = spec.activeIndicators
    local serviceInterval = (self.vehicle:getHoursSinceLastMaintenance() or 0) / (self.vehicle:getMaintenanceInterval() or 5)
    local isServiceOverdue = serviceInterval > 1.0
    local motorState = vehicle:getMotorState()
    local preheatState = spec.preheatState or ADS_Preheat.STATE.IDLE
    local isLampTestActive = ADS_Preheat.isLampTestActive(vehicle)

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

            local isEngineNotHeated = spec.engineTemperature < ADS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
            local isTransmissionNotHeated =
                (hasCVTTransmission(vehicle) and not hasCVTAddon(vehicle) and spec.transmissionTemperature < ADS_Config.CORE.TRANSMISSION_FACTOR_DATA.COLD_TRANSMISSION_THRESHOLD) or
                (hasCVTAddon(vehicle) and spec.transmissionTemperature < 55)

            if hudIndicatorId == self.indicators.coolant.name and targetColor == colors.DEFAULT and isEngineNotHeated then targetColor = colors.COOL
            elseif hudIndicatorId == self.indicators.coolant.name and targetColor == colors.DEFAULT and spec.engineTemperature > 99 and spec.engineTemperature < 110 then targetColor = colors.WARNING
            elseif hudIndicatorId == self.indicators.coolant.name and spec.engineTemperature > 110 then targetColor = colors.CRITICAL end
            if hudIndicatorId == self.indicators.transmission.name and targetColor == colors.DEFAULT and isTransmissionNotHeated then targetColor = colors.COOL
            elseif hudIndicatorId == self.indicators.transmission.name and targetColor == colors.DEFAULT and spec.transmissionTemperature > 99 and spec.transmissionTemperature < 110 then targetColor = colors.WARNING
            elseif hudIndicatorId == self.indicators.transmission.name and spec.transmissionTemperature > 110 then targetColor = colors.CRITICAL end

            if hudIndicatorId == self.indicators.service.name and isServiceOverdue then targetColor = colors.WARNING end
            if hudIndicatorId == self.indicators.oil.name and spec.serviceLevel < 0.2 then targetColor = colors.WARNING end

            if isLampTestActive then
                targetColor = colors.WARNING
                isRoutineIgnitionIndicator = true
            elseif hudIndicatorId == self.indicators.preheat.name
                    and preheatState == ADS_Preheat.STATE.PREHEATING
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
        local targetMotorLoad = math.clamp(tonumber(spec.dynamicMotorLoad) or 0, 0, 1)
        local currentMotorLoad = math.clamp(tonumber(self.telemetryDisplayValues.motorLoad) or 0, 0, 1)
        local interpolationSpeed = targetMotorLoad < 0.8
            and ADS_Hud.MOTOR_LOAD_DISPLAY_INTERPOLATION_SPEED
            or ADS_Hud.MOTOR_LOAD_HIGH_DISPLAY_INTERPOLATION_SPEED
        motorLoad = self:interpolateTelemetryValue(currentMotorLoad, targetMotorLoad, interpolationSpeed)
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

    local batteryVoltageText = string.format("%.1f%s", systemVoltageV, voltageSing)
    local motorText = string.format("%.0f%%", math.max(motorLoad * 100, 0))

    local batteryVoltageTextColor = {1, 1, 1, 1}
    if systemVoltageV < 12 then
        batteryVoltageTextColor = colors.WARNING
    end

    local motorLoadTextColor = {1, 1, 1, 1}
    if motorLoad > ADS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD then
        motorLoadTextColor = colors.WARNING
    end

    if not spec.isElectricVehicle then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
        setTextBold(true)

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

    if ADS_Drivetrain == nil or not ADS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        self:drawWheelSlipDisplay(spec, posX, posY)
    end
    self:drawDrivetrainDisplay(vehicle, spec, posX, posY)
    self:drawParkBrakeDisplay(vehicle)

    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
    setTextBold(false)
end

function ADS_Hud:drawWheelSlipDisplay(spec, posX, posY)
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

function ADS_Hud:drawDrivetrainDisplay(vehicle, spec, posX, posY)
    if self.drivetrainHud == nil or ADS_Drivetrain == nil then
        return
    end

    if not ADS_Drivetrain.getIsAvailable(vehicle) then
        return
    end

    local state = ADS_Drivetrain.getState(vehicle)
    if state == nil then
        return
    end

    local colors = ADS_Breakdowns.COLORS
    local iconId, color
    local showAutoBadge = false
    local windupStress = tonumber(state.windupStress) or 0
    local windupWarningActive = state.windupActive == true and windupStress > ADS_Config.DRIVETRAIN.WINDUP_4WD_WARNING_THRESHOLD

    if state.diffLockEngaged then
        local fourWheelDrive = state.driveMode == ADS_Drivetrain.MODE.FOUR_WD
            or (state.driveMode == ADS_Drivetrain.MODE.AUTO and state.autoEngaged)
        iconId = (fourWheelDrive and ADS_Drivetrain.getHasCenterDifferential(vehicle)) and "diffLockCenter" or "diffLockRear"
        color = colors.WARNING

        if windupStress > ADS_Config.DRIVETRAIN.WINDUP_CRITICAL_THRESHOLD then
            local blinkOn = math.floor((g_time or 0) / 250) % 2 == 0
            color = blinkOn and colors.CRITICAL or colors.WARNING
        end
    else
        if not ADS_Drivetrain.getHasCenterDifferential(vehicle) then
            iconId = "diffLockRear"
            color = colors.DEFAULT
        elseif state.driveMode == ADS_Drivetrain.MODE.TWO_WD then
            iconId = "drivelineOpen"
            color = {1, 1, 1, 0.85}
        elseif state.driveMode == ADS_Drivetrain.MODE.FOUR_WD then
            iconId = "drivelineEngaged"
            color = windupWarningActive and colors.WARNING or ADS_Hud.COLOR_GAME_GREEN
        else
            iconId = state.autoEngaged and "drivelineEngaged" or "drivelineOpen"
            color = state.autoEngaged and (windupWarningActive and colors.WARNING or ADS_Hud.COLOR_GAME_GREEN) or {1, 1, 1, 0.85}
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

function ADS_Hud:drawParkBrakeDisplay(vehicle)
    if self.parkBrakeHud == nil or self.parkBrakeHud.icon == nil then
        return
    end
    if not ADS_Config.DRIVETRAIN.PARKBRAKE_ENABLED or ADS_Drivetrain == nil then
        return
    end

    local state = ADS_Drivetrain.getState(vehicle)
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

    local colors = ADS_Breakdowns.COLORS
    local color = state.parkBrake and colors.CRITICAL or colors.DEFAULT
    icon:setColor(color[1], color[2], color[3], color[4])
    icon:render()
end

-- =====================================================================================
--                          TELEMETRY CARDS HUD
-- =====================================================================================

function ADS_Hud:drawTelemetryCards()
    local speedMeter = g_currentMission.hud.speedMeter
    if speedMeter == nil or speedMeter.speedBg == nil then
        return
    end

    local cardRightX = speedMeter:getPosition()
    cardRightX = self:drawLoadMass(cardRightX) or cardRightX
    self:drawFuelConsumption(cardRightX)
end

function ADS_Hud:getConsumptionAreaRate()
    local vehicle = self.vehicle
    if vehicle == nil then
        return 0, 0
    end

    local speed = vehicle.getLastSpeed ~= nil and (tonumber(vehicle:getLastSpeed()) or 0) or 0
    local width = vehicle.getAttacherToolWorkingWidth ~= nil and (tonumber(vehicle:getAttacherToolWorkingWidth()) or 0) or 0
    local guidanceSpec = vehicle.spec_globalPositioningSystem
    if guidanceSpec ~= nil and guidanceSpec.guidanceData ~= nil and guidanceSpec.guidanceData.width ~= nil then
        width = tonumber(guidanceSpec.guidanceData.width) or width
    end

    return speed, (speed * width) / 10
end

function ADS_Hud:interpolateTelemetryValue(currentValue, targetValue, interpolationSpeed)
    if currentValue == targetValue then
        return targetValue
    end

    local direction = math.sign(targetValue - currentValue)
    local limitFunc = direction < 0 and math.max or math.min
    return limitFunc(currentValue + interpolationSpeed * direction * (tonumber(g_currentDt) or 0), targetValue)
end

function ADS_Hud:drawFuelConsumption(cardRightX)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_AdvancedDamageSystem == nil or vehicle.spec_motorized == nil then
        return
    end

    local _, fuelCapacity, fuelType = SpeedMeterDisplay.getVehicleFuelLevelAndCapacity(vehicle)
    if fuelCapacity == nil or fuelCapacity <= 0 then
        return
    end

    local motorizedSpec = vehicle.spec_motorized
    local consumptionPerHour = 0
    local rawConsumptionPerHour = 0
    if vehicle:getIsMotorStarted() then
        consumptionPerHour = math.max(tonumber(motorizedSpec.lastFuelUsageDisplay or motorizedSpec.lastFuelUsage) or 0, 0)
        rawConsumptionPerHour = math.max(tonumber(motorizedSpec.lastFuelUsage) or 0, 0)
    end

    local speed, areaRate = self:getConsumptionAreaRate()
    local consumptionPerArea = 0
    if speed > 0.9 and areaRate > 0 then
        consumptionPerArea = rawConsumptionPerHour / areaRate
    end
    consumptionPerArea = self:interpolateTelemetryValue(
        self.telemetryDisplayValues.consumptionPerArea,
        consumptionPerArea,
        ADS_Hud.CONSUMPTION_PER_AREA_INTERPOLATION_SPEED
    )
    self.telemetryDisplayValues.consumptionPerArea = consumptionPerArea

    local isElectric = fuelType == FillType.ELECTRICCHARGE
    local isMethane = fuelType == FillType.METHANE
    local perHourUnit = isElectric and "kW" or (isMethane and "kg/h" or "L/h")
    local perAreaUnit = isElectric and "kWh/ha" or (isMethane and "kg/ha" or "L/ha")
    local perHourStr = string.format("%.1f", consumptionPerHour)
    local perAreaStr = string.format("%.1f", consumptionPerArea)

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

-- =====================================================================================
--                              LOAD / MASS HUD
-- =====================================================================================

function ADS_Hud:getLoadSeverityColor(severity)
    local colors = ADS_Breakdowns.COLORS
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

function ADS_Hud:formatMass(massTons)
    return string.format("%.1f t", math.max(tonumber(massTons) or 0, 0))
end

function ADS_Hud:getStableDisplayMass(cacheKey, massTons)
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

function ADS_Hud:drawLoadMass(cardRightX)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.getTotalMass == nil then
        return cardRightX
    end

    local spec = vehicle.spec_AdvancedDamageSystem
    if spec == nil then
        return cardRightX
    end

    local speedMeter = g_currentMission.hud.speedMeter
    if speedMeter == nil or speedMeter.speedBg == nil then
        return cardRightX
    end

    local selfMass  = tonumber(vehicle:getTotalMass(true)) or 0
    local totalMass = tonumber(vehicle:getTotalMass())     or 0
    local lockedHookLiftContainer = ADS_Utils.getLockedHookLiftContainer(vehicle)
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

        local threshold, fullEffect = ADS_Utils.getHeavyTrailerRatioLevels(isTruck)

        local trailerSeverity = ADS_Utils.calculateQuadraticMultiplier(powerToWeight, threshold, true, fullEffect)

        local hydraulicsConfig = ADS_Config.CORE.HYDRAULICS_FACTOR_DATA
        local liftThreshold = tonumber(hydraulicsConfig.HEAVY_LIFT_FACTOR_THRESHOLD) or 0.6
        local liftedMass = math.max(tonumber(spec.liftedMass) or 0, 0)
        local liftMassRatio = selfMass > 0 and (liftedMass / selfMass) or 0
        local liftSeverity = ADS_Utils.calculateQuadraticMultiplier(liftMassRatio, liftThreshold, false)

        loadColor = self:getLoadSeverityColor(math.max(trailerSeverity, liftSeverity))
    end

    local _, smBottomY = g_currentMission.hud.speedMeter:getPosition()
    local padH = self.loadMassText.paddingH or 0
    local padV = self.loadMassText.paddingV or 0
    local size = self.loadMassText.size or 0.01
    local sep  = "     "

    local displaySelfMass = self:getStableDisplayMass("displaySelfMass", vehicleMass)
    local displayTowedMass = self:getStableDisplayMass("displayTowedMass", towedMass)
    local displayTotalMass = displaySelfMass + displayTowedMass

    local tractorLabel = g_i18n:getText("ads_hud_mass_tractor") .. "  "
    local tractorValue = self:formatMass(displaySelfMass)
    local chargeLabel  = g_i18n:getText("ads_hud_mass_towed")   .. "  "
    local chargeValue  = self:formatMass(displayTowedMass)
    local totalLabel   = g_i18n:getText("ads_hud_mass_total")    .. "  "
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

-- =====================================================================================
--                              DEBUG HUD ACTIVE
-- =====================================================================================

function ADS_Hud:renderActiveVehicleDebugCache(cache)
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

function ADS_Hud:drawActiveVehicleHUD()
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_AdvancedDamageSystem == nil then
        return
    end
    local spec = vehicle.spec_AdvancedDamageSystem
    local motor = vehicle:getMotor()
    if motor == nil then
        return
    end

    local panel = self.activeVehicleDebugPanel
    local debugSnapshot = nil
    if not vehicle.isServer then
        ADS_DebugSnapshot.request(vehicle)
        debugSnapshot = ADS_DebugSnapshot.get(vehicle)
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

    if ADS_Hud.debugViewMode == "factorStats" then
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

    local function addLine(target, text, color, sizeScale)
        table.insert(target, {
            text = text,
            color = color or {1, 1, 1, 1},
            sizeScale = sizeScale or 1.0
        })
    end

    local function getTempColor(temp)
        if temp > 105 then
            return {1, 0.6, 0.6, 1}
        elseif temp > 95 then
            return {1, 1, 0.6, 1}
        end

        return {0.6, 0.8, 1, 1}
    end

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

    local function listToString(list)
        if list == nil or #list == 0 then
            return "-"
        end

        return table.concat(list, ",")
    end

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

    local function localizeDebugValue(value)
        if value == nil then
            return "-"
        end

        if type(value) == "boolean" then
            local key = value and "ads_ws_option_yes" or "ads_ws_option_no"
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

    local function getBreakdownSourceLabel(source)
        if source == AdvancedDamageSystem.BREAKDOWN_SOURCES.POOR_PARTS then
            return "PARTS"
        elseif source == AdvancedDamageSystem.BREAKDOWN_SOURCES.QUICK_FIX then
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

    local bcw = ADS_Config.CORE.BASE_SYSTEMS_WEAR

    local function asPercent(value)
        return (value or 0) * 100
    end

    local function formatAppliedMultiplier(value)
        local formatted = string.format("%.2f", tonumber(value) or 0)
        formatted = formatted:gsub("(%..-)0+$", "%1")
        formatted = formatted:gsub("%.$", "")
        return "x" .. formatted
    end

    local function getSystemCondition(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.condition or 0
        end
        return systemData or 0
    end

    local function getSystemStress(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.stress or 0
        end
        return 0
    end

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
    local serviceDbg = debugData.service or {}
    local batteryDbg = debugData.battery or {}
    local drivetrainDbg = debugData.drivetrain or {}

    local overviewLines = {}
    local serviceWearRate = serviceDbg.totalWearRate or ADS_Config.CORE.BASE_SERVICE_WEAR or 0
    local weatherFactor = ADS_Main.currentWeatherFactor
    local dirtLevel = vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount() or 0
    local radiatorClogging = spec.radiatorClogging
    local airIntakeClogging = spec.airIntakeClogging
    local lubricationLevel = spec.lubricationLevel
    local paintState = math.max(1 - (vehicle.getWearTotalAmount ~= nil and vehicle:getWearTotalAmount() or 0), 0)
    local radiatorDbg = debugData.radiator or {}
    local airIntakeDbg = debugData.airIntake or {}
    local radiatorMultiplier = radiatorDbg.totalMultiplier or 0
    local airIntakeMultiplier = airIntakeDbg.totalMultiplier or 0
    local cloggingIsOnField = radiatorDbg.isOnField == true or airIntakeDbg.isOnField == true
    local cloggingHasDust = radiatorDbg.hasDust == true or airIntakeDbg.hasDust == true
    local cloggingHasDebris = radiatorDbg.hasDebris == true or airIntakeDbg.hasDebris == true
    local cloggingWetnessFactor = airIntakeDbg.baseWetnessFactor or radiatorDbg.baseWetnessFactor or 1
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
        "Clogging: Dirt %.2f%% | Rad: %.2f%% (%s) | AI: %.2f%% (%s) | field: %s, dust: %s, derbis: %s, wtf: %.3f",
        asPercent(dirtLevel),
        asPercent(radiatorClogging),
        formatAppliedMultiplier(radiatorMultiplier),
        asPercent(airIntakeClogging),
        formatAppliedMultiplier(airIntakeMultiplier),
        tostring(cloggingIsOnField),
        tostring(cloggingHasDust),
        tostring(cloggingHasDebris),
        cloggingWetnessFactor
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

    local engineMaxFactor = math.max(
        engineDbg.motorLoadFactor or 0,
        engineDbg.airIntakeCloggingFactor or 0,
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
        transmissionDbg.coldTransFactor or 0,
        transmissionDbg.hotTransFactor or 0
    ) * bcw
    local hydraulicsMaxFactor = math.max(
        hydraulicsDbg.expiredServiceFactor or 0,
        hydraulicsDbg.heavyLiftFactor or 0,
        hydraulicsDbg.operatingFactor or 0,
        hydraulicsDbg.vibFactor or 0,
        hydraulicsDbg.coldOilFactor or 0,
        hydraulicsDbg.sharpAngleFactor or 0
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
    local factorStats = {}
    for rawSystemKey, rawStats in pairs(factorStatsSource) do
        if type(rawStats) == "table" then
            factorStats[string.lower(tostring(rawSystemKey))] = rawStats
        end
    end

    local function getAccumulatedStat(systemKey, statKey)
        local stats = factorStats[string.lower(tostring(systemKey))]
        if type(stats) ~= "table" then
            return 0
        end
        return tonumber(stats[statKey]) or 0
    end

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

    local function buildSystemLines(systemKey, dbg, maxFactor, factorEntries)
        local lines = {}
        local systemStressMultiplier = tonumber(ADS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS[systemKey]) or 1
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
                formatFactorLine(systemKey, entry.shortName, entry.value, entry.statKey, entry.extraInfo, systemStressMultiplier),
                {0.92, 0.96, 1.0, 1},
                0.80
            )
        end

        return lines
    end

    local engineLines = buildSystemLines("engine", engineDbg, engineMaxFactor, {
        { shortName = "sf", statKey = "sf", value = engineDbg.expiredServiceFactor or 0 },
        { shortName = "mlf", statKey = "mlf", value = engineDbg.motorLoadFactor or 0, extraInfo = string.format("dml: %.2f", engineDbg.dynamicMotorLoad or 0) },
        { shortName = "lf", statKey = "lf", value = engineDbg.luggingFactor or 0 },
        { shortName = "aicf", statKey = "aicf", value = engineDbg.airIntakeCloggingFactor or 0 },
        { shortName = "cmf", statKey = "cmf", value = engineDbg.coldMotorFactor or 0 },
        { shortName = "hmf", statKey = "hmf", value = engineDbg.hotMotorFactor or 0 }
    })

    local transmissionLines = buildSystemLines("transmission", transmissionDbg, transmissionMaxFactor, {
        { shortName = "sf", statKey = "sf", value = transmissionDbg.expiredServiceFactor or 0 },
        { shortName = "pof", statKey = "pof", value = transmissionDbg.pullOverloadFactor or 0, extraInfo = string.format("%.1f->%.1f", transmissionDbg.pullOverloadTimer or 0, transmissionDbg.pullOverloadTimerMin or 0) },
        { shortName = "htf", statKey = "htf", value = transmissionDbg.heavyTrailerFactor or 0, extraInfo = string.format("hp/%s: %.1f", (transmissionDbg.heavyTrailerMassBasis == "gcw") and "gcw" or "trl", transmissionDbg.heavyTrailerMassRatio or 0) },
        { shortName = "lf", statKey = "lf", value = transmissionDbg.luggingFactor or 0 },
        { shortName = "wsf", statKey = "wsf", value = transmissionDbg.wheelSlipFactor or 0, extraInfo = string.format("c: %.2f", avgTireGroundFrictionCoeff) },
        { shortName = "dwf", statKey = "dwf", value = transmissionDbg.drivetrainWindupFactor or 0, extraInfo = string.format("w: %.1f%% lock: %s", asPercent(drivetrainDbg.windupStress or 0), (drivetrainDbg.diffLockEngaged == true) and "Y" or "N") },
        { shortName = "ctf", statKey = "ctf", value = transmissionDbg.coldTransFactor or 0 },
        { shortName = "hotf", statKey = "hotf", value = transmissionDbg.hotTransFactor or 0 }
    })

    local hydraulicsLines = buildSystemLines("hydraulics", hydraulicsDbg, hydraulicsMaxFactor, {
        { shortName = "sf", statKey = "sf", value = hydraulicsDbg.expiredServiceFactor or 0 },
        { shortName = "hlf", statKey = "hlf", value = hydraulicsDbg.heavyLiftFactor or 0, extraInfo = string.format("mr: %.2f", asPercent(hydraulicsDbg.heavyLiftMassRatio or 0)) },
        { shortName = "of", statKey = "of", value = hydraulicsDbg.operatingFactor or 0, extraInfo = string.format("om: %.2f t: %ds", hydraulicsDbg.operatingMassRatio or 0, math.floor(((hydraulicsDbg.operatingTimer or 0) / 1000) + 0.0001)) },
        { shortName = "vf", statKey = "vf", value = hydraulicsDbg.vibFactor or 0, extraInfo = string.format("r/s: %.2f / %.2f", asPercent(hydraulicsDbg.vibRaw or 0), asPercent(hydraulicsDbg.vibSignal or 0)) },
        { shortName = "cof", statKey = "cof", value = hydraulicsDbg.coldOilFactor or 0 },
        { shortName = "saf", statKey = "saf", value = hydraulicsDbg.sharpAngleFactor or 0, extraInfo = string.format("%.1f deg", hydraulicsDbg.ptoSharpAngleDeg or 0) }
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
        { shortName = "slf", statKey = "slf", value = chassisDbg.steerLoadFactor or 0, extraInfo = string.format("ls: %.2f c: %.2f m: %s", chassisDbg.steerLowSpeedFactor or 0, chassisDbg.steerGroundFrictionCoeff or 0, (chassisDbg.steerMoving == true) and "Y" or "N") },
        { shortName = "bmf", statKey = "bmf", value = chassisDbg.brakeMassFactor or 0, extraInfo = string.format("hp/%s: %.1f", (chassisDbg.brakeMassBasis == "gcw") and "gcw" or "trl", chassisDbg.brakeMassRatio or 0) }
    })

    local fuelLines = buildSystemLines("fuel", fuelDbg, fuelMaxFactor, {
        { shortName = "sf", statKey = "sf", value = fuelDbg.expiredServiceFactor or 0 },
        { shortName = "lff", statKey = "lff", value = fuelDbg.lowFuelStarvationFactor or 0, extraInfo = string.format("lvl: %.2f", asPercent(fuelDbg.fuelLevel or 0)) },
        { shortName = "cff", statKey = "cff", value = fuelDbg.coldFuelFactor or 0, extraInfo = string.format("ft: %.1f C", fuelDbg.fuelTemperature or 0) },
        { shortName = "idf", statKey = "idf", value = fuelDbg.idleDepositFactor or 0, extraInfo = string.format("t: %.0fs", fuelDbg.idleTimer or 0) },
        { shortName = "hpf", statKey = "hpf", value = fuelDbg.highPressureFactor or 0, extraInfo = string.format("r: %.3f", fuelDbg.currentFuelUsageRatio or 0) }
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
            "T: %.1fC (raw: %.1fC) | ts: %.3f | k/s/w: %.2f/%.3f/%.3f | h: %.3f(l/s/a/ws: %.2f/%.2f/%.2f/%.2f) | c: %.3f(r/s/c: %.3f/%.3f/%.3f) | cvt: a/l=%d/%d eh=%.3f",
            spec.transmissionTemperature,
            spec.rawTransmissionTemperature or spec.transmissionTemperature or -99,
            spec.transmissionThermostatState,
            (debugData.transmissionTemp or {}).kp or 0,
            (debugData.transmissionTemp or {}).stiction or 0,
            (debugData.transmissionTemp or {}).waxSpeed or 0,
            (debugData.transmissionTemp or {}).totalHeat or 0,
            (debugData.transmissionTemp or {}).loadFactor or 0,
            (debugData.transmissionTemp or {}).slipFactor or 0,
            (debugData.transmissionTemp or {}).accFactor or 0,
            (debugData.transmissionTemp or {}).wheelSlipFactor or 0,
            (debugData.transmissionTemp or {}).totalCooling or 0,
            (debugData.transmissionTemp or {}).radiatorCooling or 0,
            (debugData.transmissionTemp or {}).speedCooling or 0,
            (debugData.transmissionTemp or {}).convectionCooling or 0,
            (debugData.transmissionTemp or {}).cvtSlipActive or 0,
            (debugData.transmissionTemp or {}).cvtSlipLocked or 0,
            (debugData.transmissionTemp or {}).extraTransmissionHeat or 0
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

    local preheatState = tonumber(getDebugStateValue("preheatState", spec.preheatState)) or ADS_Preheat.STATE.IDLE
    local preheatStateName = tostring(getDebugStateValue("preheatStateName", ADS_Preheat.getStateName(preheatState)))
    local preheatIsDiesel = getDebugStateValue("preheatIsDiesel", ADS_Preheat.isDieselVehicle(vehicle)) == true
    local preheatEngineTemperatureC = tonumber(getDebugStateValue("preheatEngineTemperatureC", ADS_Preheat.getEngineTemperatureC(vehicle))) or 0
    local preheatLampTestActive = getDebugStateValue("preheatLampTestActive", spec.preheatLampTestActive == true) == true
    local preheatLampTestRemainingMs = tonumber(getDebugStateValue("preheatLampTestRemainingMs", spec.preheatLampTestRemainingMs)) or 0
    local preheatRemainingMs = tonumber(getDebugStateValue("preheatRemainingMs", spec.preheatRemainingMs)) or 0
    local preheatRequiredMs = tonumber(getDebugStateValue("preheatRequiredMs", spec.preheatRequiredMs)) or 0
    local preheatWasRequired = getDebugStateValue("preheatWasRequired", spec.preheatWasRequired == true) == true
    local preheatAutomaticCrank = getDebugStateValue("preheatAutomaticCrank", spec.preheatAutomaticCrank == true) == true
    local preheatAutomaticCrankElapsedMs = tonumber(getDebugStateValue("preheatAutomaticCrankElapsedMs", spec.preheatAutomaticCrankElapsedMs)) or 0
    local preheatGlowPlugFailureSeverity = tonumber(getDebugStateValue("preheatGlowPlugFailureSeverity", ADS_Preheat.getGlowPlugFailureSeverity(vehicle))) or 0
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
        ADS_Config.PREHEAT.MAX_AUTOMATIC_CRANK_MS / 1000,
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
    local states = AdvancedDamageSystem.STATUS
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
        elseif spec.currentState == states.MAINTENANCE and spec.serviceOptionOne == AdvancedDamageSystem.MAINTENANCE_TYPES.PREVENTIVE then
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
                tonumber(ADS_Config.MAINTENANCE.MAINTENANCE_PREVENTIVE_SYSTEMS_COUNT) or 0,
                tonumber(ADS_Config.MAINTENANCE.MAINTENANCE_PREVENTIVE_STRESS_REMOVE_MULTIPLIER) or 0
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
        "Implements: lowered: %s | operating: %s | lifted: %s | operatingMass: %.1f | liftedMass: %.1f | connectedPto: %s | ptoActive: %s | harvesting: %s",
        tostring(getDebugStateValue("isImplementLowered", spec.isImplementLowered == true) == true),
        tostring(getDebugStateValue("isImplementOperating", spec.isImplementOperating == true) == true),
        tostring(getDebugStateValue("isImplementLifted", spec.isImplementLifted == true) == true),
        tonumber(getDebugStateValue("operatingMass", spec.operatingMass)) or 0,
        tonumber(getDebugStateValue("liftedMass", spec.liftedMass)) or 0,
        tostring(getDebugStateValue("hasConnectedPto", spec.hasConnectedPto == true) == true),
        tostring(getDebugStateValue("isPtoActive", spec.isPtoActive == true) == true),
        tostring(getDebugStateValue("isHarvesting", spec.isHarvesting == true) == true)
    ), {1, 1, 1, 1}, 0.95)

    for index, impl in ipairs(debugImplements) do
        addLine(implementLines, string.format(
            "#%d %s | mass: %.1f | jointType: %s | lowered: %s | supportWheels: %d | moving: %s | foldMoving: %s | plowRotating: %s | cylinderMoving: %s | head: %s",
            index,
            tostring(impl.name or "implement"),
            impl.mass,
            tostring(impl.jointTypeId),
            tostring(impl.isLowered == true),
            impl.supportWheelCount,
            tostring(impl.isMoving == true),
            tostring(impl.isFoldMoving == true),
            tostring(impl.isPlowRotationMoving == true),
            tostring(impl.isCylinderedMoving == true),
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
    local systemGapX = 0.00012
    local systemGapY = sectionGap * 0.16
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
        local gridAvailableWidth = panel.width - panel.padding * 2
        local cardWidth = (gridAvailableWidth - (systemColumns - 1) * systemGapX) / systemColumns
        local rowY = currentY

        for row = 1, systemRows do
            local rowHeight = rowHeights[row] or activeLineHeight
            for col = 1, systemColumns do
                local index = (row - 1) * systemColumns + col
                local section = systemSections[index]
                if section ~= nil then
                    local cardX = gridStartX + (col - 1) * (cardWidth + systemGapX)
                    local cardY = rowY
                    queueText(cardX, cardY, activeNormalSize, section.title .. ":", {1, 1, 1, 1}, false)

                    local cardLineY = cardY - activeLineHeight
                    for _, line in ipairs(section.lines) do
                        local lineText = line.text or ""
                        local lineColor = line.color or {1, 1, 1, 1}
                        local lineSize = activeNormalSize * (line.sizeScale or 1.0)
                        queueText(cardX + 0.003, cardLineY, lineSize, lineText, lineColor, false)
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

function ADS_Hud:drawFactorStatsVehicleHUD(vehicle, spec, debugData, factorStatsRaw, panel, activeHeaderSize, activeNormalSize, activeLineHeight, sectionGap)
    local function addLine(target, text, color, sizeScale)
        table.insert(target, {
            text = text,
            color = color or {1, 1, 1, 1},
            sizeScale = sizeScale or 1.0
        })
    end

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

    local function toPct(value)
        return (tonumber(value) or 0) * 100
    end

    local function getSystemTitle(systemKey)
        local names = {
            engine = "Engine",
            transmission = "Transmission",
            hydraulics = "Hydraulics",
            cooling = "Cooling",
            electrical = "Electrical",
            chassis = "Chassis",
            fuel = "Fuel",
            materialFlow = "Material Flow"
        }
        return names[systemKey] or tostring(systemKey)
    end

    local aliasToDebugKey = {}
    for debugKey, alias in pairs(AdvancedDamageSystem.FACTOR_STATS_ALIASES or {}) do
        aliasToDebugKey[tostring(alias)] = tostring(debugKey)
    end

    local function buildFactorExtraInfo(debugKey, dbg)
        if type(dbg) ~= "table" then
            return nil
        end

        if debugKey == "heavyLiftFactor" then
            local ratio = tonumber(dbg.heavyLiftMassRatio)
            if ratio ~= nil then
                return string.format("massRatio %.3f", ratio)
            end
        elseif debugKey == "sharpAngleFactor" then
            local angle = tonumber(dbg.ptoSharpAngleDeg)
            if angle ~= nil then
                return string.format("angle %.1fdeg", angle)
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
        elseif debugKey == "airIntakeCloggingFactor" then
            if dbg.airIntakeClogging ~= nil then
                return string.format("clog %.1f%%", (tonumber(dbg.airIntakeClogging) or 0) * 100)
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
        "electrical", "chassis", "fuel", "materialFlow"
    }

    local usedSystems = {}
    for _, systemKey in ipairs(orderedSystems) do
        local stats = factorStats[systemKey]
        if type(stats) == "table" then
            usedSystems[systemKey] = true
            local lines = {}
            local dbg = type(debugData) == "table" and debugData[systemKey] or nil
            local systemStressMultiplier = tonumber(ADS_Config.CORE.SYSTEM_STRESS_ACCUMULATION_MULTIPLIERS[systemKey]) or 1
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

-- =====================================================================================
--                             DAMAGE BAR CONTROL
-- =====================================================================================

local INSPECTED_DAMAGE_CEILING = 0.9

-- Damage bar filling of each condition tier.
local TIER_DAMAGE_AMOUNTS = {0.0, 0.25, 0.5, 0.75, INSPECTED_DAMAGE_CEILING}

local originalSpeedMeterDisplayDraw = SpeedMeterDisplay.draw
SpeedMeterDisplay.draw = function(self, ...)
    local vehicle = self.vehicle
    if vehicle == nil or not self.isVehicleDrawSafe or vehicle.rootVehicle == nil then
        return originalSpeedMeterDisplayDraw(self, ...)
    end

    local spec = vehicle.spec_AdvancedDamageSystem
    if spec ~= nil and spec.isExcludedVehicle then
        return originalSpeedMeterDisplayDraw(self, ...)
    end

    local adsHud = ADS_Main ~= nil and ADS_Main.hud or nil
    local dashExt = nil
    if spec ~= nil and adsHud ~= nil and adsHud.dashExtension ~= nil and adsHud.dashExtension.stretchWidth ~= nil then
        dashExt = adsHud.dashExtension

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
                customDamageAmount = TIER_DAMAGE_AMOUNTS[ADS_Utils.getConditionTier(condition)]
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

-- =====================================================================================
--                         VEHICLE INFO PANEL
-- =====================================================================================

function ADS_Hud:showInfoVehicle(box)
    if self.spec_AdvancedDamageSystem ~= nil and not self.spec_AdvancedDamageSystem.isExcludedVehicle then
        local spec = self.spec_AdvancedDamageSystem
        
        box:addLine(g_i18n:getText('ads_ws_label_condition'), ADS_Utils.formatCondition(self:getLastInspectedCondition()))
        box:addLine(g_i18n:getText("ads_ws_label_last_inspection"), ADS_Utils.formatTimeAgo(self:getLastInspectionDate()))
        box:addLine(g_i18n:getText("ads_ws_label_last_maintenance"), ADS_Utils.formatTimeAgo(self:getLastMaintenanceDate()))
        box:addLine(g_i18n:getText("ads_ws_label_service_interval"), ADS_Utils.formatOperatingHours(self:getHoursSinceLastMaintenance(), self:getMaintenanceInterval()))

        
        if spec.currentState ~= AdvancedDamageSystem.STATUS.READY and spec.currentState ~= AdvancedDamageSystem.STATUS.BROKEN then
            local maintenanceStatusText = string.format(g_i18n:getText("ads_spec_last_maintenance_until_format"), g_i18n:getText(spec.currentState), ADS_Utils.formatFinishTime(self:getServiceFinishTime()))
            box:addLine(maintenanceStatusText)
        end
    end
end

Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, ADS_Hud.showInfoVehicle)
