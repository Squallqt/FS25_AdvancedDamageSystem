-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Tutorial tips, each shown once when the player first meets the situation it teaches
RMS_Tutorial = {}
RMS_Tutorial.modDirectory = g_currentModDirectory
RMS_Tutorial.vehicle = nil
RMS_Tutorial.timer = 0
RMS_Tutorial.messageDowntime = 3000

local downtimeAfterMessage = 60000

---Shows one tutorial message, optionally pausing the game
-- @param string text message text
-- @param boolean? doPause true to pause the game
-- @param float? downtime delay before the next message can show
function RMS_Tutorial:showMessage(text, doPause, downtime)
    local mission = g_currentMission
    if mission == nil then
        return
    end

    if doPause then
        if mission.setManualPause ~= nil then
            mission:setManualPause(true)
        elseif mission.pauseGame ~= nil then
            mission:pauseGame()
        end
    end

    RMS_WelcomeDialog.show(text, function(_, disableTutorial)
        if g_currentMission == nil then
            return
        end

        if disableTutorial then
            RMS_Config.TUTORIAL_MODE = false
            RMS_Config.syncTutorialState()
        end

        if doPause then
            if g_currentMission.setManualPause ~= nil then
                g_currentMission:setManualPause(false)
            elseif g_currentMission.tryUnpauseGame ~= nil then
                g_currentMission:tryUnpauseGame()
            end
        end
    end, self)
    self.messageDowntime = downtime
end

---Returns the vehicle the player drives when RMS tracks it
-- @return table? vehicle tracked vehicle
function RMS_Tutorial:getRMSVehicle()
    self.vehicle = nil

    local player = g_localPlayer
    if player == nil or player.getCurrentVehicle == nil then
        return
    end

    local vehicle = player:getCurrentVehicle()
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        self.vehicle = vehicle
    end
end

---Checks the trigger of every unseen tip and shows the first one that fires
-- @param float dt time since last call in ms
function RMS_Tutorial:update(dt)
    local mission = g_currentMission

    if g_localPlayer == nil or not RMS_Config.ensureLocalTutorialState() or not RMS_Config.TUTORIAL_MODE then
        self.vehicle = nil
        self.timer = 0
        return
    end

    if g_gui:getIsGuiVisible() then
        self.vehicle = nil
        return
    end

    if RMS_Main ~= nil
        and RMS_Main.hud ~= nil
        and RMS_Main.hud:hasClosableNotification() then
        return
    end

    self.timer = self.timer + dt
    self.messageDowntime = math.max(self.messageDowntime - dt, 0)

    if self.timer < RMS_Config.TUTORIAL_UPDATE_DELAY then
        return
    end

    self.timer = self.timer % RMS_Config.TUTORIAL_UPDATE_DELAY

    self:getRMSVehicle()

    local spec = self.vehicle ~= nil and self.vehicle.spec_RealisticMechanicalSystems or nil


    local messagedData = RMS_Config.TUTORIAL_MESSAGES
    local prevDowntime = self.messageDowntime

    if self.messageDowntime <= 0 then

        -- gLOBAL MESSAGES
        if not RMS_Config.WELCOME_MESSAGE_SEEN then
            self:showMessage(g_i18n:getText("rms_tutorial_welcome_message"), false, 5000)
            RMS_Config.WELCOME_MESSAGE_SEEN = true
        end

        -- vEHICLE MESSAGES
        if self.vehicle ~= nil and spec ~= nil then
            local vehicle = self.vehicle
            local isMotorStarted = vehicle:getIsMotorStarted()
            local speed = vehicle:getLastSpeed()
            local systems = spec.systems or {}
            local function isSystemEnabled(systemKey)
                local systemData = systems[systemKey]
                return type(systemData) == "table" and systemData.enabled == true
            end
            local engineSystemEnabled = isSystemEnabled("engine")
            local transmissionSystemEnabled = isSystemEnabled("transmission")
            local hydraulicsSystemEnabled = isSystemEnabled("hydraulics")
            local coolingSystemEnabled = isSystemEnabled("cooling")
            local electricalSystemEnabled = isSystemEnabled("electrical")
            local chassisSystemEnabled = isSystemEnabled("chassis")
            local fuelSystemEnabled = isSystemEnabled("fuel")
            local ptoSystemEnabled = isSystemEnabled("pto")
            local ptoEngagementSequence = tonumber(spec.ptoEngagementSequence) or 0
            local hasNewPtoEngagement = ptoEngagementSequence > (tonumber(spec.ptoTutorialObservedSequence) or 0)
            if hasNewPtoEngagement then
                spec.ptoTutorialObservedSequence = ptoEngagementSequence
            end
            local transmissionConfig = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
            local hydraulicsConfig = RMS_Config.CORE.HYDRAULICS_FACTOR_DATA
            local chassisBrakeState = spec.chassisBrakeState
            local isTruck = spec.isTruck == true
            local heavyTrailerMass = math.max(chassisBrakeState.trailerMass, 0)
            local heavyTrailerRatio = isTruck
                and chassisBrakeState.hpGrossMassRatio
                or chassisBrakeState.hpTrailerMassRatio
            local heavyTrailerThreshold = RMS_Utils.getHeavyTrailerRatioLevels(isTruck) * transmissionConfig.HEAVY_TRAILER_TUTORIAL_MARGIN
            local hasHeavyTrailer = heavyTrailerMass > 0.1
                and heavyTrailerRatio <= heavyTrailerThreshold
            local preventiveRiskSystem = nil
            local hasPoorPartsBreakdown = false
            local localWeatherType = (g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.weather ~= nil)
                and g_currentMission.environment.weather:getCurrentWeatherType()
                or WeatherType.SUN

            if not messagedData.NEEDS_PREVENTIVE and spec.systems ~= nil then
                for _, systemData in pairs(spec.systems) do
                    if type(systemData) == "table"
                        and systemData.enabled == true
                        and systemData.condition ~= nil
                        and systemData.stress ~= nil then
                        local condition = math.max(systemData.condition, 0.001)
                        local stress = systemData.stress

                        if stress / condition > 0.7 then
                            preventiveRiskSystem = systemData
                            break
                        end
                    end
                end
            end

            if not messagedData.POOR_PARTS and spec.activeBreakdowns ~= nil then
                for breakdownId, breakdown in pairs(spec.activeBreakdowns) do
                    local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]

                    if breakdownDef ~= nil
                        and breakdownDef.isSelectable == true
                        and breakdown ~= nil
                        and breakdown.isActive == false
                        and breakdown.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
                        hasPoorPartsBreakdown = true
                        break
                    end
                end
            end

            local serviceInterval = vehicle:getHoursSinceLastMaintenance() / vehicle:getMaintenanceInterval()

            -- heavy trailer
            if not messagedData.HEAVY_TRAILER and transmissionSystemEnabled and isMotorStarted and speed > 5 and hasHeavyTrailer then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_heavy_trailer_message"),
                    0,
                    g_i18n:getText("rms_tutorial_heavy_trailer_title"),
                    true
                )
                messagedData.HEAVY_TRAILER = true
                self.messageDowntime = downtimeAfterMessage

            -- age degradation
            elseif not messagedData.AGE_DEGRADATION and vehicle:getConditionLevel() < 0.66 then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_age_degradation_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_age_degradation_title"),
                    true
                )
                messagedData.AGE_DEGRADATION = true
                self.messageDowntime = downtimeAfterMessage

            elseif not messagedData.IDLE_AND_DOWNTIME and isMotorStarted and spec.fuelState.idleTimer > 30 then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_idle_and_downtime_message"),
                    0,
                    g_i18n:getText("rms_tutorial_idle_and_downtime_title"),
                    true
                )
                messagedData.IDLE_AND_DOWNTIME = true
                self.messageDowntime = downtimeAfterMessage

            -- hot weather
            elseif not messagedData.HOT_WEATHER
                and (engineSystemEnabled or coolingSystemEnabled)
                and g_currentMission ~= nil
                and g_currentMission.environment ~= nil
                and g_currentMission.environment.weather ~= nil
                and g_currentMission.environment.weather.forecast ~= nil
                and g_currentMission.environment.weather.forecast:getCurrentWeather() ~= nil
                and g_currentMission.environment.weather.forecast:getCurrentWeather().temperature ~= nil
                and g_currentMission.environment.weather.forecast:getCurrentWeather().temperature > 30 then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_hot_weather_message"),
                    0,
                    g_i18n:getText("rms_tutorial_hot_weather_title"),
                    true
                )
                messagedData.HOT_WEATHER = true
                self.messageDowntime = downtimeAfterMessage

            -- wet weather
            elseif not messagedData.WET_WEATHER
                and electricalSystemEnabled
                and (
                    localWeatherType == WeatherType.RAIN
                    or localWeatherType == WeatherType.SNOW
                    or (WeatherType.HAIL ~= nil and localWeatherType == WeatherType.HAIL)
                ) then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_wet_weather_message"),
                    0,
                    g_i18n:getText("rms_tutorial_wet_weather_title"),
                    true
                )
                messagedData.WET_WEATHER = true
                self.messageDowntime = downtimeAfterMessage

            elseif not messagedData.RAD_OR_INTAKE_CLOGGED
                and (engineSystemEnabled or coolingSystemEnabled)
                and spec.isVehicleNeedBlowOut
                and (spec.radiatorClogging >= 0.75 or spec.airIntakeClogging >= 0.75) then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_rad_or_intake_clogged_message"),
                    0,
                    g_i18n:getText("rms_tutorial_rad_or_intake_clogged_title"),
                    true
                )
                messagedData.RAD_OR_INTAKE_CLOGGED = true
                self.messageDowntime = downtimeAfterMessage

            -- needs lubrication
            elseif not messagedData.NEEDS_LUBRICATION and spec.isVehicleNeedLubricate and spec.lubricationLevel <= RMS_Config.FIELD_CARE.LUBRICATION_WARNING_THRESHOLD then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_needs_lubrication_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_needs_lubrication_title"),
                    true
                )
                messagedData.NEEDS_LUBRICATION = true
                self.messageDowntime = downtimeAfterMessage
            
            -- engine overheat
            elseif not messagedData.ENGINE_OVERHEAT and engineSystemEnabled and isMotorStarted and spec.engineTemperature > 100 and not spec.isElectricVehicle then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_engine_overheat_message"),
                    0,
                    g_i18n:getText("rms_tutorial_engine_overheat_title"),
                    true
                )
                messagedData.ENGINE_OVERHEAT = true
                messagedData.CVT_OVERHEAT = true
                self.messageDowntime = downtimeAfterMessage

            -- cold engine
            elseif not messagedData.COLD_ENGINE and engineSystemEnabled and spec.engineTemperature < 40 and isMotorStarted and speed < 1 and not spec.isElectricVehicle then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_cold_engine_message"),
                    0,
                    g_i18n:getText("rms_tutorial_cold_engine_title"),
                    true
                )
                messagedData.COLD_ENGINE = true
                self.messageDowntime = downtimeAfterMessage

            -- overload indicator
            elseif not messagedData.OVERLOAD_INDICATOR and isMotorStarted and vehicle:hasBreakdown('STRESS_OVERLOAD') then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_overload_indicator_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_overload_indicator_title"),
                    true
                )
                messagedData.OVERLOAD_INDICATOR = true
                self.messageDowntime = downtimeAfterMessage

            -- engine overload
            elseif not messagedData.ENGINE_OVERLOAD and engineSystemEnabled and isMotorStarted and spec.dynamicMotorLoad >= 1.15 and not spec.isElectricVehicle then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_engine_overload_message"),
                    0,
                    g_i18n:getText("rms_tutorial_engine_overload_title"),
                    true
                )
                messagedData.ENGINE_OVERLOAD = true
                self.messageDowntime = downtimeAfterMessage

            -- lugging
            elseif not messagedData.LUGGING and transmissionSystemEnabled and spec.luggingTutorialTimer ~= nil and spec.luggingTutorialTimer >= 5000 and not spec.isElectricVehicle then
                RMS_Hud.showNotification(  
                    g_i18n:getText("rms_tutorial_lugging_message"),
                    0,
                    g_i18n:getText("rms_tutorial_lugging_title"),
                    true
                )
                messagedData.LUGGING = true
                self.messageDowntime = downtimeAfterMessage

            -- cvt overheat
            elseif not messagedData.CVT_OVERHEAT and transmissionSystemEnabled and isMotorStarted and spec.transmissionTemperature > 100 and not spec.isElectricVehicle and (RMS_Utils.hasCVTTransmission(vehicle) or RMS_Utils.hasCVTAddon(vehicle)) then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_cvt_overheat_message"),
                    0,
                    g_i18n:getText("rms_tutorial_cvt_overheat_title"),
                    true
                )
                messagedData.CVT_OVERHEAT = true
                messagedData.ENGINE_OVERHEAT = true
                self.messageDowntime = downtimeAfterMessage

            -- wheel slip
            elseif not messagedData.WHEEL_SLIP and transmissionSystemEnabled and isMotorStarted and spec.wheelSlipIntensity ~= nil and spec.wheelSlipIntensity > 0.9 and spec.wheelSlipTutorialTimer ~= nil and spec.wheelSlipTutorialTimer >= 3000 then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_wheel_slip_message"),
                    0,
                    g_i18n:getText("rms_tutorial_wheel_slip_title"),
                    true
                )
                messagedData.WHEEL_SLIP = true
                self.messageDowntime = downtimeAfterMessage

            -- driveline windup
            elseif not messagedData.DRIVETRAIN_WINDUP
                and transmissionSystemEnabled
                and isMotorStarted
                and spec.drivetrain ~= nil
                and spec.drivetrain.diffLockEngaged == true
                and (tonumber(spec.drivetrain.windupStress) or 0) > RMS_Config.DRIVETRAIN.WINDUP_TUTORIAL_THRESHOLD then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_drivetrain_windup_message"),
                    0,
                    g_i18n:getText("rms_tutorial_drivetrain_windup_title"),
                    true
                )
                messagedData.DRIVETRAIN_WINDUP = true
                self.messageDowntime = downtimeAfterMessage

            -- chassis vibration
            elseif not messagedData.CHASSIS_VIBRATION and chassisSystemEnabled and isMotorStarted and speed > 40 and vehicle:getIsOnField() then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_chassis_vibration_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_chassis_vibration_title"),
                    true
                )
                messagedData.CHASSIS_VIBRATION = true
                self.messageDowntime = downtimeAfterMessage

            -- steering
            elseif not messagedData.STEERING
                and chassisSystemEnabled
                and isMotorStarted
                and speed <= 0.1
                and spec.chassisSteerState.groundContact > 0
                and spec.chassisSteerState.isMoving == true then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_steering_message"),
                    0,
                    g_i18n:getText("rms_tutorial_steering_title"),
                    true
                )
                messagedData.STEERING = true
                self.messageDowntime = downtimeAfterMessage

            -- diesel preheating
            elseif not messagedData.PREHEAT
                and electricalSystemEnabled
                and RMS_Preheat.isHeating(vehicle) then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_preheat_message"),
                    0,
                    g_i18n:getText("rms_tutorial_preheat_title"),
                    true
                )
                messagedData.PREHEAT = true
                self.messageDowntime = downtimeAfterMessage

            -- cranking
            elseif not messagedData.CRANKING
                and electricalSystemEnabled
                and not spec.isElectricVehicle
                and spec.systems.electrical.crankingTimer ~= nil
                and spec.systems.electrical.crankingTimer >= 9000
                and not vehicle:hasEffect("ENGINE_HARD_START_MODIFIER")
                and not vehicle:hasEffect("GLOW_PLUG_HARD_START_MODIFIER") then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_cranking_message"),
                    0,
                    g_i18n:getText("rms_tutorial_cranking_title"),
                    true
                )
                messagedData.CRANKING = true
                self.messageDowntime = downtimeAfterMessage

            -- battery low
            elseif not messagedData.BATTERY_LOW
                and electricalSystemEnabled
                and not isMotorStarted
                and not spec.isCranking
                and vehicle:hasBreakdown('VOLTAGE_SAG') then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_battery_low_message"),
                    0,
                    g_i18n:getText("rms_tutorial_battery_low_title"),
                    true
                )
                messagedData.BATTERY_LOW = true
                messagedData.HARD_START = true
                self.messageDowntime = downtimeAfterMessage

            -- hard start
            elseif not messagedData.HARD_START
                and (engineSystemEnabled or electricalSystemEnabled or fuelSystemEnabled)
                and (vehicle:hasEffect("ENGINE_HARD_START_MODIFIER")
                    or (vehicle:hasEffect("GLOW_PLUG_HARD_START_MODIFIER")
                        and RMS_Preheat.shouldApplyGlowPlugHardStart(vehicle)))
                and not isMotorStarted then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_hard_start_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_hard_start_title"),
                    true
                )
                messagedData.HARD_START = true
                self.messageDowntime = downtimeAfterMessage

            -- critical failure
            elseif not messagedData.CRITICAL_FAILURE
                and (engineSystemEnabled or coolingSystemEnabled or electricalSystemEnabled or fuelSystemEnabled)
                and vehicle:hasEffect("ENGINE_FAILURE") then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_critical_failure_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_critical_failure_title"),
                    true
                )
                messagedData.CRITICAL_FAILURE = true
                self.messageDowntime = downtimeAfterMessage

            -- low fuel
            elseif not messagedData.LOW_FUEL
                and fuelSystemEnabled
                and isMotorStarted
                and not spec.isElectricVehicle
                and spec.fuelState.level < (RMS_Config.CORE.FUEL_FACTOR_DATA.LOW_FUEL_THRESHOLD or 0.20) then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_low_fuel_message"),
                    0,
                    g_i18n:getText("rms_tutorial_low_fuel_title"),
                    true
                )
                messagedData.LOW_FUEL = true
                self.messageDowntime = downtimeAfterMessage

            -- idle deposit
            elseif not messagedData.IDLE_DEPOSIT
                and fuelSystemEnabled
                and isMotorStarted
                and not spec.isElectricVehicle
                and spec.fuelState.idleTimer >= 120 then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_idle_deposit_message"),
                    0,
                    g_i18n:getText("rms_tutorial_idle_deposit_title"),
                    true
                )
                messagedData.IDLE_DEPOSIT = true
                self.messageDowntime = downtimeAfterMessage

            elseif not messagedData.PTO_ENGAGEMENT
                and ptoSystemEnabled
                and hasNewPtoEngagement then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_pto_engagement_message"),
                    0,
                    g_i18n:getText("rms_tutorial_pto_engagement_title"),
                    true
                )
                messagedData.PTO_ENGAGEMENT = true
                self.messageDowntime = downtimeAfterMessage

            elseif not messagedData.COLD_OIL
                and (transmissionSystemEnabled or (hydraulicsSystemEnabled and spec.isHydraulicActive))
                and isMotorStarted
                and spec.transmissionTemperature < hydraulicsConfig.COLD_OIL_THRESHOLD
                and spec.dynamicMotorLoad >= transmissionConfig.LUGGING_MOTORLOAD_THRESHOLD then
                RMS_Hud.showNotification(
                    g_i18n:getText("rms_tutorial_cold_oil_message"),
                    0,
                    g_i18n:getText("rms_tutorial_cold_oil_title"),
                    true
                )
                messagedData.COLD_OIL = true
                self.messageDowntime = downtimeAfterMessage

            -- service due soon
            elseif not messagedData.SERVICE_DUE_SOON and (serviceInterval >= 0.9 and serviceInterval < 1.0) then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_service_due_soon_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_service_due_soon_title"),
                    true
                )
                messagedData.SERVICE_DUE_SOON = true
                self.messageDowntime = downtimeAfterMessage

            -- service interval expired
            elseif not messagedData.SERVICE_INTERVAL_EXPIRED and serviceInterval >= 1.01 then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_service_interval_expired_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_service_interval_expired_title"),
                    true
                )
                messagedData.SERVICE_INTERVAL_EXPIRED = true
                self.messageDowntime = downtimeAfterMessage

            -- needs repair
            elseif not messagedData.NEEDS_REPAIR and isMotorStarted and vehicle:hasBreakdown() then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_needs_repair_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_needs_repair_title"),
                    true
                )
                messagedData.NEEDS_REPAIR = true
                self.messageDowntime = downtimeAfterMessage

            elseif not messagedData.NEEDS_OVERHAUL and vehicle:getConditionLevel() < 0.19 then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_needs_overhaul_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_needs_overhaul_title"),
                    true
                )
                messagedData.NEEDS_OVERHAUL = true
                self.messageDowntime = downtimeAfterMessage

            elseif not messagedData.NEEDS_PREVENTIVE
                and isMotorStarted
                and preventiveRiskSystem ~= nil then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_needs_preventive_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_needs_preventive_title"),
                    true
                )
                messagedData.NEEDS_PREVENTIVE = true
                self.messageDowntime = downtimeAfterMessage

            -- poor consumables
            elseif not messagedData.POOR_CONSUMABLES and vehicle:hasBreakdown("MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES") then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_poor_consumables_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_poor_consumables_title"),
                    true
                )
                messagedData.POOR_CONSUMABLES = true
                self.messageDowntime = downtimeAfterMessage

            -- poor parts
            elseif not messagedData.POOR_PARTS and hasPoorPartsBreakdown then
                RMS_Hud.showNotification(
                    string.format(g_i18n:getText("rms_tutorial_poor_parts_message"), vehicle:getFullName()),
                    0,
                    g_i18n:getText("rms_tutorial_poor_parts_title"),
                    true
                )
                messagedData.POOR_PARTS = true
                self.messageDowntime = downtimeAfterMessage

            end
        end
    end

    if prevDowntime <= 0 and self.messageDowntime > 0 then
        RMS_Config.syncTutorialState()
    end

end

addModEventListener(RMS_Tutorial)
