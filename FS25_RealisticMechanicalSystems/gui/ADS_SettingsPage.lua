RMS_SettingsPage = {}
RMS_SettingsPage.name = g_currentModName
RMS_SettingsPage.modDirectory = g_currentModDirectory

RMS_SettingsPage.steps = {}

local function formatAh(val)
    local text = string.format("%.2f", val)
    text = text:gsub("(%..-)0+$", "%1")
    text = text:gsub("%.$", "")
    return text .. " Ah"
end

local function valuesDiffer(a, b)
    if type(a) == "number" or type(b) == "number" then
        return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) > 0.0001
    end

    return a ~= b
end

local function buildPendingConfigFromAdsConfig()
    return {
        tutorialMode = RMS_Config.TUTORIAL_MODE,

        baseServiceWear = RMS_Config.CORE.BASE_SERVICE_WEAR,
        baseSystemsWear = RMS_Config.CORE.BASE_SYSTEMS_WEAR,
        downtimeMultiplier = RMS_Config.CORE.DOWNTIME_MULTIPLIER,
        generalWearEnabled = RMS_Config.CORE.GENERAL_WEAR_ENABLED,
        enableWarningMessages = RMS_Config.CORE.ENABLE_WARNING_MESSAGES,
        systemStressGlobalMultiplier = RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER,
        aiOverloadControl = RMS_Config.CORE.AI_OVERLOAD_AND_OVERHEAT_CONTROL,
        aiDisableOnCriticalOverload = RMS_Config.CORE.AI_DISABLE_ON_CRITICAL_OVERLOAD,
        contractVehicleProtection = RMS_Config.CORE.CONTRACT_VEHICLE_PROTECTION,
        aiWorkerTargetStress = RMS_Config.CORE.AI_WORKER_PID.TARGET_STRESS,
        aiWorkerMinSpeed = RMS_Config.CORE.AI_WORKER_PID.MIN_SPEED,

        instantInspection = RMS_Config.MAINTENANCE.INSTANT_INSPECTION,
        parkVehicle = RMS_Config.MAINTENANCE.PARK_VEHICLE,
        warrantyEnabled = RMS_Config.MAINTENANCE.WARRANTY_ENABLED,
        globalPriceMultiplier = RMS_Config.MAINTENANCE.GLOBAL_SERVICE_PRICE_MULTIPLIER,
        globalTimeMultiplier = RMS_Config.MAINTENANCE.GLOBAL_SERVICE_TIME_MULTIPLIER,

        dealerAlwaysAvailable = RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE,
        mobileAlwaysAvailable = RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE,
        ownAlwaysAvailable = RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE,
        mobileWorkshopRestrictionsEnabled = RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED,
        openHour = RMS_Config.WORKSHOP.OPEN_HOUR,
        closeHour = RMS_Config.WORKSHOP.CLOSE_HOUR,

        engineMaxHeat = RMS_Config.THERMAL.ENGINE_MAX_HEAT,
        transMaxHeat = RMS_Config.THERMAL.TRANS_MAX_HEAT,
        temperatureChangeSpeed = RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED,
        maxDirtInfluence = RMS_Config.THERMAL.MAX_DIRT_INFLUENCE,
        warmingBoostPower = RMS_Config.THERMAL.WARMING_BOOST_POWER,
        coolingSlowdownPower = RMS_Config.THERMAL.COOLING_SLOWDOWN_POWER,

        batteryUsableCapacityFactor = RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR,
        alternatorMaxOutput = RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT,
        idleCurrentA = RMS_Config.ELECTRICAL.IDLE_CURRENT_A,

        cloggingSpeed = RMS_Config.FIELD_CARE.CLOGGING_SPEED,
        fieldInspectionDuration = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION,
        lubricationReducePerOperatingHour = RMS_Config.FIELD_CARE.LUBRICATION_REDUCE_PER_OPERATING_HOUR,

        drivetrainEnabled = RMS_Config.DRIVETRAIN.ENABLED,
        drivetrainAllowAutoMode = RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE,
        drivetrainWindupDamage = RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED,
        drivetrainDiffLockReleaseSpeed = RMS_Config.DRIVETRAIN.DIFFLOCK_AUTO_RELEASE_SPEED,
        drivetrainParkBrakeEnabled = RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED,
        drivetrainParkBrakeAuto = RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE,

        debugMode = RMS_Config.DEBUG
    }
end

local function getPendingConfig()
    if RMS_SettingsPage.pendingConfig == nil then
        RMS_SettingsPage.pendingConfig = buildPendingConfigFromAdsConfig()
    end

    return RMS_SettingsPage.pendingConfig
end

local function getSettingsProfile(defaultProfileName)
    return g_gui:getProfile(defaultProfileName)
end

local function applyButtonBackgroundProfile(button)
    if button == nil or button.elements == nil then
        return
    end

    for _, child in pairs(button.elements) do
        if child ~= nil and child.applyProfile ~= nil and child.profile == "fs25_settingsButtonBg" then
            child:applyProfile("ads_settingsButtonBg")
            return
        end
    end
end

local function applyMultiTextOptionBackgroundProfile(option)
    if option == nil or option.elements == nil then
        return
    end

    for _, child in pairs(option.elements) do
        if child ~= nil and child.applyProfile ~= nil and child.profile == "fs25_multiTextOptionBg" then
            child:applyProfile("ads_settingsMultiTextOptionBg")
            return
        end
    end
end

local function addDisabledLockToSettingsRow(rowElement, optionElement, tooltip)
    if rowElement == nil or optionElement == nil then
        return nil
    end

    local lockButton = ButtonElement.new()
    lockButton.name = "iconDisabled"
    lockButton:loadProfile(getSettingsProfile("fs25_settingsMultiTextOptionLocked"), true)
    lockButton.target = RMS_SettingsPage
    lockButton:setCallback("onClickCallback", "onClickSettingsLockedIcon")
    lockButton:setCallback("onFocusCallback", "onFocusSettingsLockedIcon")

    local lockTooltip = TextElement.new()
    lockTooltip:loadProfile(getSettingsProfile("fs25_multiTextOptionTooltip"), true)
    lockTooltip:setText(tooltip)
    lockTooltip:setPosition(unpack(GuiUtils.getNormalizedScreenValues("940px 0px", lockTooltip.position)))
    lockButton:addElement(lockTooltip)

    rowElement:addElement(lockButton)
    lockButton:onGuiSetupFinished()
    lockTooltip:onGuiSetupFinished()
    lockButton:setDisabled(true)

    local oldSetDisabled = optionElement.setDisabled
    optionElement.setDisabled = function(element, disabled, ...)
        oldSetDisabled(element, disabled, ...)
        lockButton:setDisabled(not disabled)
    end


    return lockButton
end

local function applySettingsRowColor(page, rowElement)
    if page == nil or not page.ads_useFleetMenuStyle or rowElement == nil or rowElement.setImageColor == nil then
        return
    end

    if InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.COLOR_ALTERNATING ~= nil then
        rowElement:setImageColor(nil, table.unpack(InGameMenuSettingsFrame.COLOR_ALTERNATING[page.ads_settingsRowIsEven]))
    end

    page.ads_settingsRowIsEven = not page.ads_settingsRowIsEven
end

local function getVanillaSettingsButtonTemplate()
    local settingsPage = g_inGameMenu ~= nil and g_inGameMenu.pageSettings or nil
    local scrollPanel = settingsPage ~= nil and settingsPage.gameSettingsLayout or nil

    if scrollPanel == nil or scrollPanel.elements == nil then
        return nil
    end

    for _, element in pairs(scrollPanel.elements) do
        if element.typeName == "Bitmap"
            and element.elements ~= nil
            and element.elements[1] ~= nil
            and element.elements[1].typeName == "Button" then
            return element
        end
    end

    return nil
end

function RMS_SettingsPage:onClickSettingsLockedIcon()
end

function RMS_SettingsPage:onFocusSettingsLockedIcon(icon)
    local page = RMS_SettingsPage.embeddedPage
    if page ~= nil and page.settingsLayout ~= nil and page.settingsLayout.scrollToMakeElementVisible ~= nil then
        page.settingsLayout:scrollToMakeElementVisible(icon)
    end
end

local function getCurrentSettingsPage()
    local embeddedPage = RMS_SettingsPage.embeddedPage
    if embeddedPage ~= nil
        and embeddedPage.getCurrentSubCategory ~= nil
        and RMS_InGameMenuFrame ~= nil
        and RMS_InGameMenuFrame.SUB_CATEGORY ~= nil
        and embeddedPage:getCurrentSubCategory() == RMS_InGameMenuFrame.SUB_CATEGORY.SETTINGS then
        return embeddedPage
    end

    return nil
end

local function isCurrentMissionMultiplayer()
    return g_currentMission ~= nil
        and g_currentMission.missionDynamicInfo ~= nil
        and g_currentMission.missionDynamicInfo.isMultiplayer == true
end

local function canChangeRMSSettings()
    return g_currentMission ~= nil
        and g_currentMission.getIsClient ~= nil
        and g_currentMission:getIsClient()
        and (not isCurrentMissionMultiplayer() or g_currentMission:getIsServer() or g_currentMission.isMasterUser)
end

local function refreshCurrentSettingsPage()
    local currentPage = getCurrentSettingsPage()
    if currentPage ~= nil then
        RMS_SettingsPage:updateRMSSettings(currentPage)
    end
end

function RMS_SettingsPage.applyPendingConfigSideEffects(oldConfig, newConfig)
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end

    if oldConfig == nil or newConfig == nil or RMS_Main == nil or RMS_Main.vehicles == nil then
        return
    end

    local parkVehicleChanged = valuesDiffer(oldConfig.parkVehicle, newConfig.parkVehicle)
    local instantInspectionEnabled = (oldConfig.instantInspection ~= true and newConfig.instantInspection == true)

    if not parkVehicleChanged and not instantInspectionEnabled then
        return
    end

    local states = RealisticMechanicalSystems.STATUS

    for _, vehicle in pairs(RMS_Main.vehicles) do
        if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
            local spec = vehicle.spec_RealisticMechanicalSystems
            local currentState = spec.currentState

            if parkVehicleChanged
                and currentState ~= states.READY
                and currentState ~= states.BROKEN
                and vehicle.spec_enterable ~= nil
                and vehicle.spec_enterable.setIsTabbable ~= nil then
                vehicle.spec_enterable:setIsTabbable(not newConfig.parkVehicle)
            end

            if instantInspectionEnabled and currentState == states.INSPECTION then
                if RealisticMechanicalSystems.forceFinishService(vehicle) then
                    RealisticMechanicalSystems.raiseServiceLifecycleDirtyFlags(vehicle)
                end
            end
        end
    end
end

function RMS_SettingsPage.commitPendingConfig(current, pending)
    if pending == nil or current == nil then
        return
    end

    RMS_SettingsPage.applyPendingConfigSideEffects(current, pending)

    local batteryFactorChanged = valuesDiffer(pending.batteryUsableCapacityFactor, current.batteryUsableCapacityFactor)
    local workshopChanged =
        valuesDiffer(pending.dealerAlwaysAvailable, current.dealerAlwaysAvailable) or
        valuesDiffer(pending.mobileAlwaysAvailable, current.mobileAlwaysAvailable) or
        valuesDiffer(pending.ownAlwaysAvailable, current.ownAlwaysAvailable) or
        valuesDiffer(pending.mobileWorkshopRestrictionsEnabled, current.mobileWorkshopRestrictionsEnabled) or
        valuesDiffer(pending.openHour, current.openHour) or
        valuesDiffer(pending.closeHour, current.closeHour)

    local tutorialModeChanged = valuesDiffer(pending.tutorialMode, current.tutorialMode)
    RMS_Config.TUTORIAL_MODE = pending.tutorialMode
    if tutorialModeChanged then
        RMS_Config.syncTutorialState()
    end

    RMS_Config.CORE.BASE_SERVICE_WEAR = pending.baseServiceWear
    RMS_Config.CORE.BASE_SYSTEMS_WEAR = pending.baseSystemsWear
    RMS_Config.CORE.DOWNTIME_MULTIPLIER = pending.downtimeMultiplier
    RMS_Config.CORE.GENERAL_WEAR_ENABLED = pending.generalWearEnabled
    RMS_Config.CORE.ENABLE_WARNING_MESSAGES = pending.enableWarningMessages
    RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER = pending.systemStressGlobalMultiplier
    RMS_Config.CORE.AI_OVERLOAD_AND_OVERHEAT_CONTROL = pending.aiOverloadControl
    RMS_Config.CORE.AI_DISABLE_ON_CRITICAL_OVERLOAD = pending.aiDisableOnCriticalOverload
    RMS_Config.CORE.CONTRACT_VEHICLE_PROTECTION = pending.contractVehicleProtection
    RMS_Config.CORE.AI_WORKER_PID.TARGET_STRESS = pending.aiWorkerTargetStress
    RMS_Config.CORE.AI_WORKER_PID.MIN_SPEED = pending.aiWorkerMinSpeed

    RMS_Config.MAINTENANCE.INSTANT_INSPECTION = pending.instantInspection
    RMS_Config.MAINTENANCE.PARK_VEHICLE = pending.parkVehicle
    RMS_Config.MAINTENANCE.WARRANTY_ENABLED = pending.warrantyEnabled
    RMS_Config.MAINTENANCE.GLOBAL_SERVICE_PRICE_MULTIPLIER = pending.globalPriceMultiplier
    RMS_Config.MAINTENANCE.GLOBAL_SERVICE_TIME_MULTIPLIER = pending.globalTimeMultiplier

    RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE = pending.dealerAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE = pending.mobileAlwaysAvailable
    RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE = pending.ownAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED = pending.mobileWorkshopRestrictionsEnabled
    RMS_Config.WORKSHOP.OPEN_HOUR = pending.openHour
    RMS_Config.WORKSHOP.CLOSE_HOUR = pending.closeHour

    RMS_Config.THERMAL.ENGINE_MAX_HEAT = pending.engineMaxHeat
    RMS_Config.THERMAL.TRANS_MAX_HEAT = pending.transMaxHeat
    RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED = pending.temperatureChangeSpeed
    RMS_Config.THERMAL.MAX_DIRT_INFLUENCE = pending.maxDirtInfluence
    RMS_Config.THERMAL.WARMING_BOOST_POWER = pending.warmingBoostPower
    RMS_Config.THERMAL.COOLING_SLOWDOWN_POWER = pending.coolingSlowdownPower

    RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR = pending.batteryUsableCapacityFactor
    RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT = pending.alternatorMaxOutput
    RMS_Config.ELECTRICAL.IDLE_CURRENT_A = pending.idleCurrentA

    RMS_Config.FIELD_CARE.CLOGGING_SPEED = pending.cloggingSpeed
    RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION = pending.fieldInspectionDuration
    RMS_Config.FIELD_CARE.LUBRICATION_REDUCE_PER_OPERATING_HOUR = pending.lubricationReducePerOperatingHour

    RMS_Config.DRIVETRAIN.ENABLED = pending.drivetrainEnabled
    RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE = pending.drivetrainAllowAutoMode
    RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED = pending.drivetrainWindupDamage
    RMS_Config.DRIVETRAIN.DIFFLOCK_AUTO_RELEASE_SPEED = pending.drivetrainDiffLockReleaseSpeed
    RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED = pending.drivetrainParkBrakeEnabled
    RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE = pending.drivetrainParkBrakeAuto

    RMS_Config.DEBUG = pending.debugMode

    if batteryFactorChanged and RMS_Main ~= nil and RMS_Main.vehicles ~= nil then
        for _, vehicle in pairs(RMS_Main.vehicles) do
            if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
                RMS_Electrical.rescaleBatteryChargeFromSoc(vehicle)

                local spec = vehicle.spec_RealisticMechanicalSystems
                RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
            end
        end
    end

    if workshopChanged and RMS_Main ~= nil and RMS_Main.forceWorkshopUpdate ~= nil then
        RMS_Main:forceWorkshopUpdate(true)
    end

    if g_currentMission ~= nil then
        if g_currentMission:getIsServer() and g_server ~= nil then
            g_server:broadcastEvent(RMS_SettingsSyncEvent.new())
        elseif g_client ~= nil then
            RMS_SettingsSyncEvent.send()
        end
    end
end

function RMS_SettingsPage.beginSettingsSession()
    RMS_SettingsPage.pendingConfig = buildPendingConfigFromAdsConfig()
    RMS_SettingsPage.ads_hasPendingSettingsChange = false
end

function RMS_SettingsPage:initializeSettingsPageControls(targetPage)
    local page = targetPage
    if page == nil or page.ads_initSettingsMenuDone then
        return
    end

    local function deleteElementById(elementId)
        local root = page.settingsPage or page.settingsLayout or page
        local element = root ~= nil and root:getDescendantById(elementId) or nil
        if element ~= nil then
            element:delete()
        end
    end

    RMS_SettingsPage:generateAllSteps()
    page.ads_settingsRowIsEven = false

    -- General
    page.ads_tutorialMode = RMS_SettingsPage:addBinaryOption(
        page,
        "onTutorialModeChanged",
        g_i18n:getText("ads_tutorialMode_label"),
        g_i18n:getText("ads_tutorialMode_tooltip")
    )
    page.ads_tutorialResetTips = RMS_SettingsPage:addButtonOption(
        page,
        "onResetTutorialTipsClicked",
        g_i18n:getText("ads_tutorialResetTips_label"),
        g_i18n:getText("ads_tutorialResetTips_text"),
        g_i18n:getText("ads_tutorialResetTips_tooltip")
    )
    page.ads_warningMessages = RMS_SettingsPage:addBinaryOption(
        page,
        "onWarningMessagesChanged",
        g_i18n:getText("ads_warningMessages_label"),
        g_i18n:getText("ads_warningMessages_tooltip")
    )
    page.ads_debugMode = RMS_SettingsPage:addBinaryOption(
        page,
        "onDebugModeChanged",
        g_i18n:getText("ads_debugMode_label"),
        g_i18n:getText("ads_debugMode_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("ads_settings_section_service_wear"))

    page.ads_serviceWear = RMS_SettingsPage:addMultiTextOption(
        page, "onServiceWearChanged",
        RMS_SettingsPage.steps.serviceWear.texts,
        g_i18n:getText("ads_serviceInterval_label"),
        g_i18n:getText("ads_serviceInterval_tooltip")
    )
    page.ads_conditionWear = RMS_SettingsPage:addMultiTextOption(
        page, "onConditionWearChanged",
        RMS_SettingsPage.steps.conditionWear.texts,
        g_i18n:getText("ads_vehicleLifespan_label"),
        g_i18n:getText("ads_vehicleLifespan_tooltip")
    )
    page.ads_systemStressRate = RMS_SettingsPage:addMultiTextOption(
        page, "onSystemStressRateChanged",
        RMS_SettingsPage.steps.systemStressRate.texts,
        g_i18n:getText("ads_systemStressRate_label"),
        g_i18n:getText("ads_systemStressRate_tooltip")
    )
    page.ads_downtimeWear = RMS_SettingsPage:addMultiTextOption(
        page, "onDowntimeWearChanged",
        RMS_SettingsPage.steps.downtimeWear.texts,
        g_i18n:getText("ads_downtimeWear_label"),
        g_i18n:getText("ads_downtimeWear_tooltip")
    )
    page.ads_generalWearEnabled = RMS_SettingsPage:addBinaryOption(
        page,
        "onGeneralWearEnabledChanged",
        g_i18n:getText("ads_generalWearEnabled_label"),
        g_i18n:getText("ads_generalWearEnabled_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("ads_ws_header_title"))

    -- Instant Inspection (Binary)
    page.ads_instantInspection = RMS_SettingsPage:addBinaryOption(
        page,
        "onInstantInspectionChanged",
        g_i18n:getText("ads_instantInspection_label"),
        g_i18n:getText("ads_instantInspection_tooltip")
    )

    -- Park Vehicle (Binary)
    page.ads_parkVehicle = RMS_SettingsPage:addBinaryOption(
        page,
        "onParkVehicleChanged",
        g_i18n:getText("ads_parkVehicle_label"),
        g_i18n:getText("ads_parkVehicle_tooltip")
    )

    -- Warranty Coverage (Binary)
    page.ads_warrantyEnabled = RMS_SettingsPage:addBinaryOption(
        page,
        "onWarrantyEnabledChanged",
        g_i18n:getText("ads_warrantyEnabled_label"),
        g_i18n:getText("ads_warrantyEnabled_tooltip")
    )

    -- Maintenance Price
    page.ads_maintenancePrice = RMS_SettingsPage:addMultiTextOption(
        page,
        "onMaintenancePriceChanged",
        RMS_SettingsPage.steps.maintPrice.texts,
        g_i18n:getText("ads_maintenancePrice_label"),
        g_i18n:getText("ads_maintenancePrice_tooltip")
    )

    -- Maintenance Duration
    page.ads_maintenanceDuration = RMS_SettingsPage:addMultiTextOption(
        page,
        "onMaintenanceDurationChanged",
        RMS_SettingsPage.steps.maintDuration.texts,
        g_i18n:getText("ads_maintenanceDuration_label"),
        g_i18n:getText("ads_maintenanceDuration_tooltip")
    )

    -- Mobile Workshop Restrictions (Binary)
    page.ads_mobileWorkshopRestrictions = RMS_SettingsPage:addBinaryOption(
        page,
        "onMobileWorkshopRestrictionsChanged",
        g_i18n:getText("ads_mobileWorkshopRestrictions_label"),
        g_i18n:getText("ads_mobileWorkshopRestrictions_tooltip")
    )

    -- Dealer Workshop Available (Binary)
    page.ads_dealerWorkshopAvailable = RMS_SettingsPage:addBinaryOption(
        page,
        "onDealerWorkshopAvailableChanged",
        g_i18n:getText("ads_dealerWorkshopAvailable_label"),
        g_i18n:getText("ads_dealerWorkshopAvailable_tooltip")
    )

    -- Mobile Workshop Available (Binary)
    page.ads_mobileWorkshopAvailable = RMS_SettingsPage:addBinaryOption(
        page,
        "onMobileWorkshopAvailableChanged",
        g_i18n:getText("ads_mobileWorkshopAvailable_label"),
        g_i18n:getText("ads_mobileWorkshopAvailable_tooltip")
    )

    -- Own Workshop Available (Binary)
    page.ads_ownWorkshopAvailable = RMS_SettingsPage:addBinaryOption(
        page,
        "onOwnWorkshopAvailableChanged",
        g_i18n:getText("ads_ownWorkshopAvailable_label"),
        g_i18n:getText("ads_ownWorkshopAvailable_tooltip")
    )

    -- Workshop Open Hour
    page.ads_workshopOpenHour = RMS_SettingsPage:addMultiTextOption(
        page,
        "onWorkshopOpenHourChanged",
        RMS_SettingsPage.steps.hours.texts,
        g_i18n:getText("ads_workshopOpenHour_label"),
        g_i18n:getText("ads_workshopOpenHour_tooltip")
    )

    -- Workshop Close Hour
    page.ads_workshopCloseHour = RMS_SettingsPage:addMultiTextOption(
        page,
        "onWorkshopCloseHourChanged",
        RMS_SettingsPage.steps.hours.texts,
        g_i18n:getText("ads_workshopCloseHour_label"),
        g_i18n:getText("ads_workshopCloseHour_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("ads_settings_section_thermal_model"))

    page.ads_thermalSensitivity = RMS_SettingsPage:addMultiTextOption(
        page, "onThermalSensitivityChanged",
        RMS_SettingsPage.steps.thermalSensitivity.texts,
        g_i18n:getText("ads_thermalSensitivity_label"),
        g_i18n:getText("ads_thermalSensitivity_tooltip")
    )
    page.ads_temperatureChangeSpeed = RMS_SettingsPage:addMultiTextOption(
        page,
        "onTemperatureChangeSpeedChanged",
        RMS_SettingsPage.steps.temperatureChangeSpeed.texts,
        g_i18n:getText("ads_temperatureChangeSpeed_label"),
        g_i18n:getText("ads_temperatureChangeSpeed_tooltip")
    )
    page.ads_radiatorDirtInfluence = RMS_SettingsPage:addMultiTextOption(
        page,
        "onRadiatorDirtInfluenceChanged",
        RMS_SettingsPage.steps.radiatorDirtInfluence.texts,
        g_i18n:getText("ads_radiatorDirtInfluence_label"),
        g_i18n:getText("ads_radiatorDirtInfluence_tooltip")
    )
    page.ads_warmingBoostPower = RMS_SettingsPage:addMultiTextOption(
        page,
        "onWarmingBoostPowerChanged",
        RMS_SettingsPage.steps.thermalPower.texts,
        g_i18n:getText("ads_warmingBoostPower_label"),
        g_i18n:getText("ads_warmingBoostPower_tooltip")
    )
    page.ads_coolingSlowdownPower = RMS_SettingsPage:addMultiTextOption(
        page,
        "onCoolingSlowdownPowerChanged",
        RMS_SettingsPage.steps.thermalPower.texts,
        g_i18n:getText("ads_coolingSlowdownPower_label"),
        g_i18n:getText("ads_coolingSlowdownPower_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("ads_settings_section_battery_alternator"))

    page.ads_batteryCapacity = RMS_SettingsPage:addMultiTextOption(
        page, "onBatteryCapacityChanged",
        RMS_SettingsPage.steps.batteryCapacity.texts,
        g_i18n:getText("ads_batteryCapacity_label"),
        g_i18n:getText("ads_batteryCapacity_tooltip")
    )
    page.ads_alternatorMaxOutput = RMS_SettingsPage:addMultiTextOption(
        page,
        "onAlternatorMaxOutputChanged",
        RMS_SettingsPage.steps.alternatorMaxOutput.texts,
        g_i18n:getText("ads_alternatorMaxOutput_label"),
        g_i18n:getText("ads_alternatorMaxOutput_tooltip")
    )
    page.ads_idleCurrent = RMS_SettingsPage:addMultiTextOption(
        page,
        "onIdleCurrentChanged",
        RMS_SettingsPage.steps.idleCurrent.texts,
        g_i18n:getText("ads_idleCurrent_label"),
        g_i18n:getText("ads_idleCurrent_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("ads_settings_section_preshift_maintenance"))

    page.ads_cloggingSpeed = RMS_SettingsPage:addMultiTextOption(
        page,
        "onCloggingSpeedChanged",
        RMS_SettingsPage.steps.cloggingSpeed.texts,
        g_i18n:getText("ads_cloggingSpeed_label"),
        g_i18n:getText("ads_cloggingSpeed_tooltip")
    )
    page.ads_fieldInspectionDuration = RMS_SettingsPage:addMultiTextOption(
        page,
        "onFieldInspectionDurationChanged",
        RMS_SettingsPage.steps.fieldInspectionDuration.texts,
        g_i18n:getText("ads_fieldInspectionDuration_label"),
        g_i18n:getText("ads_fieldInspectionDuration_tooltip")
    )
    page.ads_lubricationReducePerOperatingHour = RMS_SettingsPage:addMultiTextOption(
        page,
        "onLubricationReducePerOperatingHourChanged",
        RMS_SettingsPage.steps.lubricationReducePerOperatingHour.texts,
        g_i18n:getText("ads_lubricationReducePerOperatingHour_label"),
        g_i18n:getText("ads_lubricationReducePerOperatingHour_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("ads_settings_section_drivetrain"))

    page.ads_drivetrainEnabled = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainEnabledChanged",
        g_i18n:getText("ads_drivetrainEnabled_label"),
        g_i18n:getText("ads_drivetrainEnabled_tooltip")
    )
    page.ads_drivetrainAllowAutoMode = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainAllowAutoModeChanged",
        g_i18n:getText("ads_drivetrainAllowAutoMode_label"),
        g_i18n:getText("ads_drivetrainAllowAutoMode_tooltip")
    )
    page.ads_drivetrainWindupDamage = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainWindupDamageChanged",
        g_i18n:getText("ads_drivetrainWindupDamage_label"),
        g_i18n:getText("ads_drivetrainWindupDamage_tooltip")
    )
    page.ads_drivetrainDiffLockReleaseSpeed = RMS_SettingsPage:addMultiTextOption(
        page,
        "onDrivetrainDiffLockReleaseSpeedChanged",
        RMS_SettingsPage.steps.diffLockReleaseSpeed.texts,
        g_i18n:getText("ads_drivetrainDiffLockReleaseSpeed_label"),
        g_i18n:getText("ads_drivetrainDiffLockReleaseSpeed_tooltip")
    )
    page.ads_drivetrainParkBrakeEnabled = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainParkBrakeEnabledChanged",
        g_i18n:getText("ads_drivetrainParkBrakeEnabled_label"),
        g_i18n:getText("ads_drivetrainParkBrakeEnabled_tooltip")
    )
    page.ads_drivetrainParkBrakeAuto = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainParkBrakeAutoChanged",
        g_i18n:getText("ads_drivetrainParkBrakeAuto_label"),
        g_i18n:getText("ads_drivetrainParkBrakeAuto_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("ads_settings_section_other"))

    page.ads_aiOverloadAndOverheatControl = RMS_SettingsPage:addBinaryOption(
        page,
        "onAiOverloadAndOverheatControlChanged",
        g_i18n:getText("ads_aiOverloadAndOverheatControl_label"),
        g_i18n:getText("ads_aiOverloadAndOverheatControl_tooltip")
    )
    page.ads_aiDisableOnCriticalOverload = RMS_SettingsPage:addBinaryOption(
        page,
        "onAiDisableOnCriticalOverloadChanged",
        g_i18n:getText("ads_aiDisableOnCriticalOverload_label"),
        g_i18n:getText("ads_aiDisableOnCriticalOverload_tooltip")
    )
    page.ads_contractVehicleProtection = RMS_SettingsPage:addBinaryOption(
        page,
        "onContractVehicleProtectionChanged",
        g_i18n:getText("ads_contractVehicleProtection_label"),
        g_i18n:getText("ads_contractVehicleProtection_tooltip")
    )
    page.ads_aiWorkerTargetStress = RMS_SettingsPage:addMultiTextOption(
        page,
        "onAiWorkerTargetStressChanged",
        RMS_SettingsPage.steps.aiWorkerTargetStress.texts,
        g_i18n:getText("ads_aiWorkerTargetStress_label"),
        g_i18n:getText("ads_aiWorkerTargetStress_tooltip")
    )
    page.ads_aiWorkerMinSpeed = RMS_SettingsPage:addMultiTextOption(
        page,
        "onAiWorkerMinSpeedChanged",
        RMS_SettingsPage.steps.aiWorkerMinSpeed.texts,
        g_i18n:getText("ads_aiWorkerMinSpeed_label"),
        g_i18n:getText("ads_aiWorkerMinSpeed_tooltip")
    )

    deleteElementById("subTitlePrefab")
    deleteElementById("binaryPrefab")
    deleteElementById("multiPrefab")

    page.settingsLayout:invalidateLayout()
    page.ads_initSettingsMenuDone = true
end

function RMS_SettingsPage:activateEmbeddedSettingsPage(page)
    if page == nil then
        return
    end

    self.embeddedPage = page
    page.ads_useFleetMenuStyle = true

    if self.pendingConfig == nil then
        RMS_SettingsPage.beginSettingsSession()
    end

    self:updateRMSPageVisibility(page)

    self:initializeSettingsPageControls(page)
    if page.settingsSlider ~= nil and page.settingsSlider.setDataElement ~= nil then
        page.settingsSlider:setDataElement(page.settingsLayout)
    end
    RMS_SettingsPage.registerEmbeddedFocus(page)
    self:updateRMSPageVisibility(page)
    self:updateRMSSettings(page)
end

function RMS_SettingsPage.registerEmbeddedFocus(page)
    if page == nil
        or page.ads_settingsFocusLoaded
        or page.settingsLayout == nil
        or FocusManager == nil
        or FocusManager.loadElementFromCustomValues == nil then
        return
    end

    local currentGui = FocusManager.currentGui
    if page.name ~= nil and FocusManager.setGui ~= nil then
        FocusManager:setGui(page.name)
    end

    if FocusManager.removeElement ~= nil then
        FocusManager:removeElement(page.settingsLayout)
    end
    FocusManager:loadElementFromCustomValues(page.settingsLayout)

    if currentGui ~= nil and FocusManager.setGui ~= nil then
        FocusManager:setGui(currentGui)
    end

    page.ads_settingsFocusLoaded = true
end

function RMS_SettingsPage:updateRMSPageVisibility(targetPage)
    local page = targetPage
    if page == nil then
        return
    end

    if page.noPermissionText ~= nil then
        page.noPermissionText:setVisible(false)
    end
    if page.settingsLayout ~= nil then
        page.settingsLayout:setVisible(page.ads_initSettingsMenuDone == true)
    end
    if page.settingsSliderBox ~= nil then
        page.settingsSliderBox:setVisible(page.ads_initSettingsMenuDone == true)
    end
    if page.settingsTooltipSeparator ~= nil then
        page.settingsTooltipSeparator:setVisible(page.ads_initSettingsMenuDone == true)
    end
end

function RMS_SettingsPage:onFrameClose()
    if not RMS_SettingsPage.ads_hasPendingSettingsChange then
        RMS_SettingsPage.pendingConfig = nil
        return
    end

    local pending = RMS_SettingsPage.pendingConfig
    local current = buildPendingConfigFromAdsConfig()

    RMS_SettingsPage.pendingConfig = nil
    RMS_SettingsPage.ads_hasPendingSettingsChange = false

    if pending == nil then
        return
    end

    local anyChanged = false
    for key, oldValue in pairs(current) do
        if valuesDiffer(pending[key], oldValue) then
            anyChanged = true
            break
        end
    end

    if not anyChanged then
        return
    end

    RMS_SettingsPage.commitPendingConfig(current, pending)
end


function RMS_SettingsPage:updateRMSSettings(currentPage)
    if currentPage == nil or not currentPage.ads_initSettingsMenuDone then return end

    local steps = RMS_SettingsPage.steps
    local pending = RMS_SettingsPage.pendingConfig or buildPendingConfigFromAdsConfig()
    local tutorialOption = currentPage.ads_tutorialMode

    local function setIndex(element, valueList, targetValue)
        local bestIndex = 1
        local bestDiff = math.huge

        for i, v in ipairs(valueList) do
            local diff = math.abs((tonumber(v) or 0) - (tonumber(targetValue) or 0))
            if diff < bestDiff then
                bestDiff = diff
                bestIndex = i
            end
        end

        element:setState(bestIndex)
    end

    setIndex(currentPage.ads_systemStressRate, steps.systemStressRate.values, pending.systemStressGlobalMultiplier)
    setIndex(currentPage.ads_batteryCapacity, steps.batteryCapacity.values, pending.batteryUsableCapacityFactor)
    setIndex(currentPage.ads_alternatorMaxOutput, steps.alternatorMaxOutput.values, pending.alternatorMaxOutput)
    setIndex(currentPage.ads_idleCurrent, steps.idleCurrent.values, pending.idleCurrentA)
    setIndex(currentPage.ads_serviceWear, steps.serviceWear.values, pending.baseServiceWear)
    setIndex(currentPage.ads_conditionWear, steps.conditionWear.values, pending.baseSystemsWear)
    setIndex(currentPage.ads_downtimeWear, steps.downtimeWear.values, pending.downtimeMultiplier)
    setIndex(currentPage.ads_maintenancePrice, steps.maintPrice.values, pending.globalPriceMultiplier * 100)
    setIndex(currentPage.ads_maintenanceDuration, steps.maintDuration.values, pending.globalTimeMultiplier * 100)
    setIndex(currentPage.ads_thermalSensitivity, steps.thermalSensitivity.values, pending.engineMaxHeat)
    setIndex(currentPage.ads_temperatureChangeSpeed, steps.temperatureChangeSpeed.values, pending.temperatureChangeSpeed)
    setIndex(currentPage.ads_radiatorDirtInfluence, steps.radiatorDirtInfluence.values, pending.maxDirtInfluence)
    setIndex(currentPage.ads_warmingBoostPower, steps.thermalPower.values, pending.warmingBoostPower)
    setIndex(currentPage.ads_coolingSlowdownPower, steps.thermalPower.values, pending.coolingSlowdownPower)
    setIndex(currentPage.ads_cloggingSpeed, steps.cloggingSpeed.values, pending.cloggingSpeed)
    setIndex(currentPage.ads_fieldInspectionDuration, steps.fieldInspectionDuration.values, pending.fieldInspectionDuration)
    setIndex(currentPage.ads_lubricationReducePerOperatingHour, steps.lubricationReducePerOperatingHour.values, pending.lubricationReducePerOperatingHour)
    setIndex(currentPage.ads_aiWorkerTargetStress, steps.aiWorkerTargetStress.values, pending.aiWorkerTargetStress)
    setIndex(currentPage.ads_aiWorkerMinSpeed, steps.aiWorkerMinSpeed.values, pending.aiWorkerMinSpeed)
    setIndex(currentPage.ads_drivetrainDiffLockReleaseSpeed, steps.diffLockReleaseSpeed.values, pending.drivetrainDiffLockReleaseSpeed)
    
    if tutorialOption ~= nil then
        tutorialOption:setIsChecked(pending.tutorialMode, false, false)
    end
    currentPage.ads_instantInspection:setIsChecked(pending.instantInspection, false, false)
    currentPage.ads_parkVehicle:setIsChecked(pending.parkVehicle, false, false)
    currentPage.ads_warrantyEnabled:setIsChecked(pending.warrantyEnabled, false, false)
    currentPage.ads_generalWearEnabled:setIsChecked(pending.generalWearEnabled, false, false)
    currentPage.ads_warningMessages:setIsChecked(pending.enableWarningMessages, false, false)
    currentPage.ads_aiOverloadAndOverheatControl:setIsChecked(pending.aiOverloadControl, false, false)
    currentPage.ads_aiDisableOnCriticalOverload:setIsChecked(pending.aiDisableOnCriticalOverload, false, false)
    currentPage.ads_contractVehicleProtection:setIsChecked(pending.contractVehicleProtection, false, false)
    currentPage.ads_dealerWorkshopAvailable:setIsChecked(pending.dealerAlwaysAvailable, false, false)
    currentPage.ads_mobileWorkshopAvailable:setIsChecked(pending.mobileAlwaysAvailable, false, false)
    currentPage.ads_ownWorkshopAvailable:setIsChecked(pending.ownAlwaysAvailable, false, false)
    currentPage.ads_mobileWorkshopRestrictions:setIsChecked(pending.mobileWorkshopRestrictionsEnabled, false, false)
    currentPage.ads_drivetrainEnabled:setIsChecked(pending.drivetrainEnabled, false, false)
    currentPage.ads_drivetrainAllowAutoMode:setIsChecked(pending.drivetrainAllowAutoMode, false, false)
    currentPage.ads_drivetrainWindupDamage:setIsChecked(pending.drivetrainWindupDamage, false, false)
    currentPage.ads_drivetrainParkBrakeEnabled:setIsChecked(pending.drivetrainParkBrakeEnabled, false, false)
    currentPage.ads_drivetrainParkBrakeAuto:setIsChecked(pending.drivetrainParkBrakeAuto, false, false)
    currentPage.ads_debugMode:setIsChecked(pending.debugMode, false, false)
    
    setIndex(currentPage.ads_workshopOpenHour, steps.hours.values, pending.openHour)
    setIndex(currentPage.ads_workshopCloseHour, steps.hours.values, pending.closeHour)

    local areAllWorkshopsAlwaysAvailable = pending.dealerAlwaysAvailable
        and pending.mobileAlwaysAvailable
        and pending.ownAlwaysAvailable
    currentPage.ads_workshopOpenHour:setDisabled(areAllWorkshopsAlwaysAvailable)
    currentPage.ads_workshopCloseHour:setDisabled(areAllWorkshopsAlwaysAvailable)

    -- MP permission: only server host or dedicated-server admin can change settings.
    local canChangeSettings = canChangeRMSSettings()
    local disableAll = not canChangeSettings

    currentPage.ads_serviceWear:setDisabled(disableAll)
    currentPage.ads_conditionWear:setDisabled(disableAll)
    currentPage.ads_downtimeWear:setDisabled(disableAll)
    currentPage.ads_generalWearEnabled:setDisabled(disableAll)

    currentPage.ads_systemStressRate:setDisabled(disableAll)
    currentPage.ads_batteryCapacity:setDisabled(disableAll)
    currentPage.ads_alternatorMaxOutput:setDisabled(disableAll)
    currentPage.ads_idleCurrent:setDisabled(disableAll)
    currentPage.ads_instantInspection:setDisabled(disableAll)
    currentPage.ads_parkVehicle:setDisabled(disableAll)
    currentPage.ads_warrantyEnabled:setDisabled(disableAll)
    currentPage.ads_maintenancePrice:setDisabled(disableAll)
    currentPage.ads_maintenanceDuration:setDisabled(disableAll)
    currentPage.ads_dealerWorkshopAvailable:setDisabled(disableAll)
    currentPage.ads_mobileWorkshopAvailable:setDisabled(disableAll)
    currentPage.ads_ownWorkshopAvailable:setDisabled(disableAll)
    currentPage.ads_mobileWorkshopRestrictions:setDisabled(disableAll)
    currentPage.ads_drivetrainEnabled:setDisabled(disableAll)
    currentPage.ads_drivetrainAllowAutoMode:setDisabled(disableAll or not pending.drivetrainEnabled)
    currentPage.ads_drivetrainWindupDamage:setDisabled(disableAll or not pending.drivetrainEnabled)
    currentPage.ads_drivetrainDiffLockReleaseSpeed:setDisabled(disableAll or not pending.drivetrainEnabled)
    currentPage.ads_drivetrainParkBrakeEnabled:setDisabled(disableAll)
    currentPage.ads_drivetrainParkBrakeAuto:setDisabled(disableAll or not pending.drivetrainParkBrakeEnabled)
    currentPage.ads_thermalSensitivity:setDisabled(disableAll)
    currentPage.ads_temperatureChangeSpeed:setDisabled(disableAll)
    currentPage.ads_radiatorDirtInfluence:setDisabled(disableAll)
    currentPage.ads_warmingBoostPower:setDisabled(disableAll)
    currentPage.ads_coolingSlowdownPower:setDisabled(disableAll)
    currentPage.ads_cloggingSpeed:setDisabled(disableAll)
    currentPage.ads_fieldInspectionDuration:setDisabled(disableAll)
    currentPage.ads_lubricationReducePerOperatingHour:setDisabled(disableAll)
    currentPage.ads_aiOverloadAndOverheatControl:setDisabled(disableAll)
    currentPage.ads_aiDisableOnCriticalOverload:setDisabled(disableAll)
    currentPage.ads_contractVehicleProtection:setDisabled(disableAll)
    currentPage.ads_aiWorkerTargetStress:setDisabled(disableAll or not pending.aiOverloadControl)
    currentPage.ads_aiWorkerMinSpeed:setDisabled(disableAll or not pending.aiOverloadControl)
    currentPage.ads_warningMessages:setDisabled(disableAll)
    currentPage.ads_debugMode:setDisabled(disableAll)

    -- Workshop hour controls are disabled while every workshop type is available 24/7.
    if disableAll or areAllWorkshopsAlwaysAvailable then
        currentPage.ads_workshopOpenHour:setDisabled(true)
        currentPage.ads_workshopCloseHour:setDisabled(true)
    end

end

-- --- Callback Handlers --- --
function RMS_SettingsPage:onServiceWearChanged(state)
    getPendingConfig().baseServiceWear = RMS_SettingsPage.steps.serviceWear.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onTutorialModeChanged(state, optionElement)
    local pending = getPendingConfig()
    local newValue = false

    if optionElement ~= nil and optionElement.getIsChecked ~= nil then
        newValue = optionElement:getIsChecked()
    elseif RMS_SettingsPage.embeddedPage ~= nil
        and RMS_SettingsPage.embeddedPage.ads_tutorialMode ~= nil
        and RMS_SettingsPage.embeddedPage.ads_tutorialMode.getIsChecked ~= nil then
        newValue = RMS_SettingsPage.embeddedPage.ads_tutorialMode:getIsChecked()
    elseif BinaryOptionElement ~= nil and state == BinaryOptionElement.STATE_RIGHT then
        newValue = true
    elseif type(state) == "boolean" then
        newValue = not state
    end

    pending.tutorialMode = newValue
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onResetTutorialTipsClicked()
    YesNoDialog.show(function(shouldReset)
        if shouldReset then
            RMS_Config.resetTutorialMessages()
            RMS_Config.syncTutorialState()
        end
    end, nil, g_i18n:getText("ads_tutorialResetConfirm_message"), g_i18n:getText("ads_tutorialResetConfirm_title"))
end

function RMS_SettingsPage:onConditionWearChanged(state)
    getPendingConfig().baseSystemsWear = RMS_SettingsPage.steps.conditionWear.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDowntimeWearChanged(state)
    getPendingConfig().downtimeMultiplier = RMS_SettingsPage.steps.downtimeWear.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onGeneralWearEnabledChanged(state)
    getPendingConfig().generalWearEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onInstantInspectionChanged(state)
    getPendingConfig().instantInspection = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onParkVehicleChanged(state)
    getPendingConfig().parkVehicle = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onWarrantyEnabledChanged(state)
    getPendingConfig().warrantyEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onMaintenancePriceChanged(state)
    getPendingConfig().globalPriceMultiplier = RMS_SettingsPage.steps.maintPrice.values[state] / 100
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onMaintenanceDurationChanged(state)
    getPendingConfig().globalTimeMultiplier = RMS_SettingsPage.steps.maintDuration.values[state] / 100
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDealerWorkshopAvailableChanged(state)
    getPendingConfig().dealerAlwaysAvailable = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onMobileWorkshopAvailableChanged(state)
    getPendingConfig().mobileAlwaysAvailable = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onOwnWorkshopAvailableChanged(state)
    getPendingConfig().ownAlwaysAvailable = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onMobileWorkshopRestrictionsChanged(state)
    getPendingConfig().mobileWorkshopRestrictionsEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onWorkshopOpenHourChanged(state)
    local pending = getPendingConfig()
    local newOpen = RMS_SettingsPage.steps.hours.values[state]
    local currentClose = pending.closeHour

    -- Keep open/close hours from overlapping.
    if newOpen >= currentClose then
        currentClose = newOpen + 1
        if currentClose > 23 then
            currentClose = 23
            newOpen = 22
        end
        pending.closeHour = currentClose
    end

    pending.openHour = newOpen
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onWorkshopCloseHourChanged(state)
    local pending = getPendingConfig()
    local newClose = RMS_SettingsPage.steps.hours.values[state]
    local currentOpen = pending.openHour

    -- Keep open/close hours from overlapping.
    if currentOpen >= newClose then
        currentOpen = newClose - 1
        if currentOpen < 0 then
            currentOpen = 0
            newClose = 1
        end
        pending.openHour = currentOpen
    end

    pending.closeHour = newClose
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end


function RMS_SettingsPage:onSystemStressRateChanged(state)
    getPendingConfig().systemStressGlobalMultiplier = RMS_SettingsPage.steps.systemStressRate.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onBatteryCapacityChanged(state)
    getPendingConfig().batteryUsableCapacityFactor = RMS_SettingsPage.steps.batteryCapacity.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onAlternatorMaxOutputChanged(state)
    getPendingConfig().alternatorMaxOutput = RMS_SettingsPage.steps.alternatorMaxOutput.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onIdleCurrentChanged(state)
    getPendingConfig().idleCurrentA = RMS_SettingsPage.steps.idleCurrent.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end


function RMS_SettingsPage:onThermalSensitivityChanged(state)
    local val = RMS_SettingsPage.steps.thermalSensitivity.values[state]
    local pending = getPendingConfig()
    pending.engineMaxHeat = val
    pending.transMaxHeat = val
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onTemperatureChangeSpeedChanged(state)
    getPendingConfig().temperatureChangeSpeed = RMS_SettingsPage.steps.temperatureChangeSpeed.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onRadiatorDirtInfluenceChanged(state)
    getPendingConfig().maxDirtInfluence = RMS_SettingsPage.steps.radiatorDirtInfluence.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onWarmingBoostPowerChanged(state)
    getPendingConfig().warmingBoostPower = RMS_SettingsPage.steps.thermalPower.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onCoolingSlowdownPowerChanged(state)
    getPendingConfig().coolingSlowdownPower = RMS_SettingsPage.steps.thermalPower.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onCloggingSpeedChanged(state)
    getPendingConfig().cloggingSpeed = RMS_SettingsPage.steps.cloggingSpeed.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onFieldInspectionDurationChanged(state)
    getPendingConfig().fieldInspectionDuration = RMS_SettingsPage.steps.fieldInspectionDuration.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onLubricationReducePerOperatingHourChanged(state)
    getPendingConfig().lubricationReducePerOperatingHour = RMS_SettingsPage.steps.lubricationReducePerOperatingHour.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onAiOverloadAndOverheatControlChanged(state)
    getPendingConfig().aiOverloadControl = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onAiDisableOnCriticalOverloadChanged(state)
    getPendingConfig().aiDisableOnCriticalOverload = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onContractVehicleProtectionChanged(state)
    getPendingConfig().contractVehicleProtection = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onAiWorkerTargetStressChanged(state)
    getPendingConfig().aiWorkerTargetStress = RMS_SettingsPage.steps.aiWorkerTargetStress.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onAiWorkerMinSpeedChanged(state)
    getPendingConfig().aiWorkerMinSpeed = RMS_SettingsPage.steps.aiWorkerMinSpeed.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDrivetrainEnabledChanged(state)
    getPendingConfig().drivetrainEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDrivetrainAllowAutoModeChanged(state)
    getPendingConfig().drivetrainAllowAutoMode = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDrivetrainWindupDamageChanged(state)
    getPendingConfig().drivetrainWindupDamage = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDrivetrainDiffLockReleaseSpeedChanged(state)
    getPendingConfig().drivetrainDiffLockReleaseSpeed = RMS_SettingsPage.steps.diffLockReleaseSpeed.values[state]
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDrivetrainParkBrakeEnabledChanged(state)
    getPendingConfig().drivetrainParkBrakeEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDrivetrainParkBrakeAutoChanged(state)
    getPendingConfig().drivetrainParkBrakeAuto = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onWarningMessagesChanged(state)
    getPendingConfig().enableWarningMessages = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

function RMS_SettingsPage:onDebugModeChanged(state)
    getPendingConfig().debugMode = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.ads_hasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end


-- --- UI Helper Methods --- --
function RMS_SettingsPage:addSectionHeader(inGameMenuSettingsFrame, titleText)
    local textElement = TextElement.new()
    local textElementProfile = getSettingsProfile("fs25_settingsSectionHeader")
    textElement.name = "sectionHeader"
    textElement:loadProfile(textElementProfile, true)
    textElement:setText(titleText)
    inGameMenuSettingsFrame.settingsLayout:addElement(textElement)
    textElement:onGuiSetupFinished()
end

function RMS_SettingsPage:addMultiTextOption(inGameMenuSettingsFrame, onClickCallback, texts, title, tooltip)
    local bitMap = BitmapElement.new()
    local bitMapProfile = getSettingsProfile("fs25_multiTextOptionContainer")
    bitMap:loadProfile(bitMapProfile, true)
    applySettingsRowColor(inGameMenuSettingsFrame, bitMap)

    local multiTextOption = MultiTextOptionElement.new()
    local multiTextOptionProfile = getSettingsProfile("fs25_settingsMultiTextOption")
    multiTextOption:loadProfile(multiTextOptionProfile, true)
    multiTextOption.updateChildrenState = true
    multiTextOption.target = RMS_SettingsPage
    multiTextOption:setCallback("onClickCallback", onClickCallback)
    multiTextOption:setTexts(texts)

    local multiTextOptionTitle = TextElement.new()
    local multiTextOptionTitleProfile = getSettingsProfile("fs25_settingsMultiTextOptionTitle")
    multiTextOptionTitle:loadProfile(multiTextOptionTitleProfile, true)
    multiTextOptionTitle:setText(title)

    local multiTextOptionTooltip = TextElement.new()
    local multiTextOptionTooltipProfile = getSettingsProfile("fs25_multiTextOptionTooltip")
    multiTextOptionTooltip.name = "ignore"
    multiTextOptionTooltip:loadProfile(multiTextOptionTooltipProfile, true)
    multiTextOptionTooltip:setText(tooltip)

    multiTextOption:addElement(multiTextOptionTooltip)
    bitMap:addElement(multiTextOption)
    addDisabledLockToSettingsRow(bitMap, multiTextOption, tooltip)
    bitMap:addElement(multiTextOptionTitle)

    multiTextOption:onGuiSetupFinished()
    applyMultiTextOptionBackgroundProfile(multiTextOption)
    multiTextOptionTitle:onGuiSetupFinished()
    multiTextOptionTooltip:onGuiSetupFinished()

    inGameMenuSettingsFrame.settingsLayout:addElement(bitMap)
    bitMap:onGuiSetupFinished()
    
    return multiTextOption
end

function RMS_SettingsPage:addBinaryOption(inGameMenuSettingsFrame, onClickCallback, title, tooltip)
    local bitMap = BitmapElement.new()
    local bitMapProfile = getSettingsProfile("fs25_multiTextOptionContainer")
    bitMap:loadProfile(bitMapProfile, true)
    applySettingsRowColor(inGameMenuSettingsFrame, bitMap)

    local binaryOption = BinaryOptionElement.new()
    binaryOption.useYesNoTexts = true
    local binaryOptionProfile = getSettingsProfile("fs25_settingsBinaryOption")
    binaryOption:loadProfile(binaryOptionProfile, true)
    binaryOption.target = RMS_SettingsPage
    binaryOption:setCallback("onClickCallback", onClickCallback)

    local binaryOptionTitle = TextElement.new()
    local binaryOptionTitleProfile = getSettingsProfile("fs25_settingsMultiTextOptionTitle")
    binaryOptionTitle:loadProfile(binaryOptionTitleProfile, true)
    binaryOptionTitle:setText(title)

    local binaryOptionTooltip = TextElement.new()
    local binaryOptionTooltipProfile = getSettingsProfile("fs25_multiTextOptionTooltip")
    binaryOptionTooltip.name = "ignore"
    binaryOptionTooltip:loadProfile(binaryOptionTooltipProfile, true)
    binaryOptionTooltip:setText(tooltip)

    binaryOption:addElement(binaryOptionTooltip)
    bitMap:addElement(binaryOption)
    addDisabledLockToSettingsRow(bitMap, binaryOption, tooltip)
    bitMap:addElement(binaryOptionTitle)

    binaryOption:onGuiSetupFinished()
    binaryOptionTitle:onGuiSetupFinished()
    binaryOptionTooltip:onGuiSetupFinished()

    inGameMenuSettingsFrame.settingsLayout:addElement(bitMap)
    bitMap:onGuiSetupFinished()
    
    return binaryOption
end

function RMS_SettingsPage:addButtonOption(inGameMenuSettingsFrame, onClickCallback, title, text, tooltip)
    local template = getVanillaSettingsButtonTemplate()
    local bitMap
    local clonedTemplate = template ~= nil and template.clone ~= nil

    if clonedTemplate then
        bitMap = template:clone(inGameMenuSettingsFrame.settingsLayout)
        bitMap.id = nil
    else
        bitMap = BitmapElement.new()
        local bitMapProfile = getSettingsProfile("fs25_multiTextOptionContainer")
        bitMap:loadProfile(bitMapProfile, true)
        inGameMenuSettingsFrame.settingsLayout:addElement(bitMap)
    end

    applySettingsRowColor(inGameMenuSettingsFrame, bitMap)

    local button
    local buttonTitle

    for _, element in pairs(bitMap.elements) do
        if element.typeName == "Button" then
            button = element
        elseif element.typeName == "Text" and element.name ~= "ignore" then
            buttonTitle = element
        end
    end

    if button == nil then
        button = ButtonElement.new()
        bitMap:addElement(button)
    end

    button:applyProfile("ads_settingsButton")
    applyButtonBackgroundProfile(button)
    button.target = RMS_SettingsPage
    button:setCallback("onClickCallback", onClickCallback)
    button:setText(text)
    button.id = nil
    button.isAlwaysFocusedOnOpen = false
    button.focused = false

    if buttonTitle == nil then
        buttonTitle = TextElement.new()
        local buttonTitleProfile = getSettingsProfile("fs25_settingsMultiTextOptionTitle")
        buttonTitle:loadProfile(buttonTitleProfile, true)
        bitMap:addElement(buttonTitle)
    elseif buttonTitle.applyProfile ~= nil then
        buttonTitle:applyProfile("fs25_settingsMultiTextOptionTitle")
    end

    buttonTitle:setText(title)
    buttonTitle.id = nil
    if buttonTitle.setDisabled ~= nil then
        buttonTitle:setDisabled(false)
    end

    local buttonTooltip = button:getDescendantByName("ignore")
    if buttonTooltip == nil then
        buttonTooltip = TextElement.new()
        local buttonTooltipProfile = getSettingsProfile("fs25_multiTextOptionTooltip")
        buttonTooltip.name = "ignore"
        buttonTooltip:loadProfile(buttonTooltipProfile, true)
        button:addElement(buttonTooltip)
    end

    buttonTooltip:setText(tooltip)
    buttonTooltip.id = nil

    button:onGuiSetupFinished()
    buttonTitle:onGuiSetupFinished()
    buttonTooltip:onGuiSetupFinished()

    bitMap:onGuiSetupFinished()

    return button
end


-- --- Data Generation --- --
function RMS_SettingsPage:generateAllSteps()
    if self.steps.generated then return end

    local function createSteps(startVal, count, stepSize, formatter)
        local data = { values = {}, texts = {} }
        for i = 0, count - 1 do
            local val = startVal + (i * stepSize)
            table.insert(data.values, val)
            table.insert(data.texts, formatter and formatter(val) or tostring(val))
        end
        return data
    end

    -- Service Interval
    do
        local data = { values = {}, texts = {} }

        local function addHourRange(startHour, endHour, stepHour)
            local hours = startHour
            while hours <= endHour + 0.0001 do
                table.insert(data.values, 0.5 / hours)
                table.insert(data.texts, string.format("%.1f h", hours))
                hours = hours + stepHour
            end
        end

        addHourRange(1.0, 20.0, 1.0)
        addHourRange(22.0, 50.0, 2.0)
        addHourRange(55.0, 100.0, 5.0)
        addHourRange(200.0, 1000.0, 100.0)

        self.steps.serviceWear = data
    end

    -- Vehicle Lifespan:
    -- 0.001 = 1000h, 0.030 = ~33h
    do
        local data = { values = {}, texts = {} }

        local function addHourRange(startHour, endHour, stepHour)
            local hours = startHour
            while hours <= endHour + 0.0001 do
                table.insert(data.values, 1.0 / hours)
                table.insert(data.texts, string.format("%d h", hours))
                hours = hours + stepHour
            end
        end

        addHourRange(40, 200, 10)
        addHourRange(220, 500, 20)
        addHourRange(550, 1000, 50)
        addHourRange(2000, 10000, 1000)
        addHourRange(20000, 50000, 10000)

        self.steps.conditionWear = data
    end

    -- Downtime Wear: Off, then 1% to 10%
    do
        local data = { values = {0.0}, texts = {g_i18n:getText("ads_option_off")} }
        for percent = 1, 10 do
            local value = percent / 100
            table.insert(data.values, value)
            table.insert(data.texts, string.format("%d%%", percent))
        end
        self.steps.downtimeWear = data
    end

    -- System Stress Rate: 10% to 300%, then 350% to 1000% by 50%
    do
        local data = createSteps(0.1, 30, 0.1, function(v)
            return string.format("%.0f%%", v * 100)
        end)

        for percent = 350, 1000, 50 do
            table.insert(data.values, percent / 100)
            table.insert(data.texts, string.format("%d%%", percent))
        end

        self.steps.systemStressRate = data
    end

    -- Battery Capacity in Ah (stored as usable capacity factor)
    do
        local nominalCapacity = tonumber(RMS_Config.ELECTRICAL.BATTERY_NOMINAL_CAPACITY) or 150
        local data = { values = {}, texts = {} }
        local factors = {0.025, 0.05, 0.075, 0.1}

        for factor = 0.2, 1.0, 0.1 do
            table.insert(factors, factor)
        end

        for _, factor in ipairs(factors) do
            table.insert(data.values, factor)
            table.insert(data.texts, formatAh(nominalCapacity * factor))
        end

        self.steps.batteryCapacity = data
    end

    -- Alternator Max Output: 100 A to 300 A.
    self.steps.alternatorMaxOutput = createSteps(100, 5, 50, function(v)
        return string.format("%d A", v)
    end)

    -- Idle Current: none, then 0.1 A to 2.0 A.
    do
        local data = { values = {0.0}, texts = {g_i18n:getText("ads_option_none")} }
        for tenths = 1, 20 do
            local value = tenths / 10
            table.insert(data.values, value)
            table.insert(data.texts, string.format("%.1f A", value))
        end
        self.steps.idleCurrent = data
    end

    -- Maint Price: 10% to 300%
    self.steps.maintPrice = createSteps(10, 30, 10, function(v)
        return string.format("%.0f%%", v)
    end)

    -- Maint Duration: 10% to 300%
    self.steps.maintDuration = createSteps(10, 30, 10, function(v)
        return string.format("%.0f%%", v)
    end)

    -- Hours: 00:00 to 23:00
    self.steps.hours = createSteps(0, 24, 1, function(v)
        return string.format("%02d:00", v)
    end)

    -- Thermal Sensitivity:
    self.steps.thermalSensitivity = {
        values = {0.9, 1.0, 1.05, 1.1},
        texts  = {
            g_i18n:getText("ads_thermal_none"),
            g_i18n:getText("ads_thermal_mild"),
            g_i18n:getText("ads_thermal_default"),
            g_i18n:getText("ads_thermal_aggressive"),
        }
    }

    -- Overall thermal model speed: 0.5x to 2.0x.
    self.steps.temperatureChangeSpeed = createSteps(0.5, 16, 0.1, function(v)
        return string.format("%.1fx", v)
    end)

    -- Radiator Dirt Influence: Off, then 10% to 50%.
    do
        local data = { values = {0.0}, texts = {g_i18n:getText("ads_option_off")} }
        for percent = 10, 50, 10 do
            table.insert(data.values, percent / 100)
            table.insert(data.texts, string.format("%d%%", percent))
        end
        self.steps.radiatorDirtInfluence = data
    end

    -- Thermal artificial scaling: Off, then 2x to 20x.
    do
        local data = { values = {1.0}, texts = {g_i18n:getText("ads_option_off")} }
        for multiplier = 2, 20 do
            table.insert(data.values, multiplier)
            table.insert(data.texts, string.format("%dx", multiplier))
        end
        self.steps.thermalPower = data
    end

    -- Clogging Speed: 10% to 300%
    self.steps.cloggingSpeed = createSteps(0.1, 30, 0.1, function(v)
        return string.format("%.0f%%", v * 100)
    end)

    -- Field Inspection Duration: 1 s to 30 s.
    self.steps.fieldInspectionDuration = createSteps(1000, 30, 1000, function(v)
        return string.format("%d s", v / 1000)
    end)

    -- Lubrication wear: Off, then 1% to 5% per operating hour.
    do
        local data = { values = {0.0}, texts = {g_i18n:getText("ads_option_off")} }
        for percent = 1, 5 do
            table.insert(data.values, percent / 100)
            table.insert(data.texts, string.format("%d%%", percent))
        end
        self.steps.lubricationReducePerOperatingHour = data
    end

    -- AI speed response target stress. Lower values react earlier and more aggressively.
    self.steps.aiWorkerTargetStress = {
        values = {0.4, 0.3, 0.2, 0.1},
        texts = {
            g_i18n:getText("ads_aiWorkerTargetStress_relaxed"),
            g_i18n:getText("ads_aiWorkerTargetStress_balanced"),
            g_i18n:getText("ads_aiWorkerTargetStress_sensitive"),
            g_i18n:getText("ads_aiWorkerTargetStress_verySensitive"),
        }
    }

    -- AI minimum cruise speed: 3 km/h to 10 km/h.
    self.steps.aiWorkerMinSpeed = createSteps(3, 8, 1, function(v)
        return string.format("%d km/h", v)
    end)

    -- Diff lock auto-release speed: 10 km/h to 40 km/h.
    self.steps.diffLockReleaseSpeed = createSteps(10, 7, 5, function(v)
        return string.format("%d km/h", v)
    end)

    self.steps.generated = true
end


function RMS_SettingsPage.reset()
    RMS_SettingsPage.steps = {}
    RMS_SettingsPage.pendingConfig = nil
    RMS_SettingsPage.ads_hasPendingSettingsChange = false
    RMS_SettingsPage.embeddedPage = nil
end
