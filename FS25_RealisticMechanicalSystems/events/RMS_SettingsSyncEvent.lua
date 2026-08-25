-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Replicates every adjustable RMS_Config value between the admin client, the server and the other clients
RMS_SettingsSyncEvent = {}
local RMS_SettingsSyncEvent_mt = Class(RMS_SettingsSyncEvent, Event)

InitEventClass(RMS_SettingsSyncEvent, "RMS_SettingsSyncEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_SettingsSyncEvent.emptyNew()
    return Event.new(RMS_SettingsSyncEvent_mt)
end


---Create new instance of event holding a snapshot of the local configuration
-- @return table self instance of class event
function RMS_SettingsSyncEvent.new()
    local self = RMS_SettingsSyncEvent.emptyNew()

    self.baseServiceWear           = RMS_Config.CORE.BASE_SERVICE_WEAR
    self.baseSystemsWear           = RMS_Config.CORE.BASE_SYSTEMS_WEAR
    self.downtimeMultiplier        = RMS_Config.CORE.DOWNTIME_MULTIPLIER
    self.generalWearEnabled        = RMS_Config.CORE.GENERAL_WEAR_ENABLED
    self.enableWarningMessages     = RMS_Config.CORE.ENABLE_WARNING_MESSAGES
    self.systemStressGlobalMultiplier = RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER
    self.aiOverloadControl         = RMS_Config.CORE.AI_OVERLOAD_AND_OVERHEAT_CONTROL
    self.aiDisableOnCriticalOverload = RMS_Config.CORE.AI_DISABLE_ON_CRITICAL_OVERLOAD
    self.contractVehicleProtection = RMS_Config.CORE.CONTRACT_VEHICLE_PROTECTION
    self.aiWorkerTargetStress      = RMS_Config.CORE.AI_WORKER_PID.TARGET_STRESS
    self.aiWorkerMinSpeed          = RMS_Config.CORE.AI_WORKER_PID.MIN_SPEED
    self.instantInspection         = RMS_Config.MAINTENANCE.INSTANT_INSPECTION
    self.parkVehicle               = RMS_Config.MAINTENANCE.PARK_VEHICLE
    self.warrantyEnabled           = RMS_Config.MAINTENANCE.WARRANTY_ENABLED
    self.globalPriceMultiplier     = RMS_Config.MAINTENANCE.GLOBAL_SERVICE_PRICE_MULTIPLIER
    self.globalTimeMultiplier      = RMS_Config.MAINTENANCE.GLOBAL_SERVICE_TIME_MULTIPLIER
    self.dealerAlwaysAvailable     = RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE
    self.mobileAlwaysAvailable     = RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE
    self.ownAlwaysAvailable        = RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE
    self.mobileWorkshopRestrictionsEnabled = RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED
    self.openHour                  = RMS_Config.WORKSHOP.OPEN_HOUR
    self.closeHour                 = RMS_Config.WORKSHOP.CLOSE_HOUR
    self.temperatureChangeSpeed    = RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED
    self.transTemperatureChangeMultiplier = RMS_Config.THERMAL.TRANS_TEMPERATURE_CHANGE_MULTIPLIER
    self.maxDirtInfluence          = RMS_Config.THERMAL.MAX_DIRT_INFLUENCE
    self.batteryUsableCapacityFactor = RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR
    self.alternatorMaxOutput       = RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT
    self.idleCurrentA              = RMS_Config.ELECTRICAL.IDLE_CURRENT_A
    self.cloggingSpeed             = RMS_Config.FIELD_CARE.CLOGGING_SPEED
    self.fieldInspectionDuration   = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    self.lubricationReducePerOperatingHour = RMS_Config.FIELD_CARE.LUBRICATION_REDUCE_PER_OPERATING_HOUR
    self.debugMode                 = RMS_Config.DEBUG
    self.drivetrainEnabled         = RMS_Config.DRIVETRAIN.ENABLED
    self.drivetrainAllowAutoMode   = RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE
    self.drivetrainWindupDamage    = RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED
    self.drivetrainDiffLockReleaseSpeed = RMS_Config.DRIVETRAIN.DIFFLOCK_AUTO_RELEASE_SPEED
    self.drivetrainParkBrakeEnabled = RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED
    self.drivetrainParkBrakeAuto   = RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE
    self.exhaustSmokeEnabled       = RMS_Config.EXHAUST.ENABLED
    self.exhaustSmokeIntensity     = RMS_Config.EXHAUST.INTENSITY

    return self
end


---Called on server side on join, values are written in the order readStream expects them
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_SettingsSyncEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.baseServiceWear       or 0)
    streamWriteFloat32(streamId, self.baseSystemsWear       or 0)
    streamWriteFloat32(streamId, self.downtimeMultiplier    or 0)
    streamWriteBool(streamId,    self.generalWearEnabled    or false)
    streamWriteBool(streamId,    self.enableWarningMessages or false)
    streamWriteFloat32(streamId, self.systemStressGlobalMultiplier or 1.0)
    streamWriteBool(streamId,    self.aiOverloadControl      or false)
    streamWriteBool(streamId,    self.aiDisableOnCriticalOverload or false)
    streamWriteBool(streamId,    self.contractVehicleProtection or false)
    streamWriteFloat32(streamId, self.aiWorkerTargetStress   or 0.3)
    streamWriteFloat32(streamId, self.aiWorkerMinSpeed       or 3.0)
    streamWriteBool(streamId,    self.instantInspection      or false)
    streamWriteBool(streamId,    self.parkVehicle            or false)
    streamWriteBool(streamId,    self.warrantyEnabled        or false)
    streamWriteFloat32(streamId, self.globalPriceMultiplier  or 1)
    streamWriteFloat32(streamId, self.globalTimeMultiplier   or 1)
    streamWriteBool(streamId,    self.dealerAlwaysAvailable  or false)
    streamWriteBool(streamId,    self.mobileAlwaysAvailable  or false)
    streamWriteBool(streamId,    self.ownAlwaysAvailable     or false)
    streamWriteBool(streamId,    self.mobileWorkshopRestrictionsEnabled or false)
    streamWriteFloat32(streamId, self.openHour               or 8)
    streamWriteFloat32(streamId, self.closeHour              or 19)
    streamWriteFloat32(streamId, self.temperatureChangeSpeed or 1.4)
    streamWriteFloat32(streamId, self.transTemperatureChangeMultiplier or 1.0)
    streamWriteFloat32(streamId, self.maxDirtInfluence       or 1.0)
    streamWriteFloat32(streamId, self.batteryUsableCapacityFactor or 0.1)
    streamWriteFloat32(streamId, self.alternatorMaxOutput    or 100)
    streamWriteFloat32(streamId, self.idleCurrentA           or 0.5)
    streamWriteFloat32(streamId, self.cloggingSpeed          or 1.0)
    streamWriteFloat32(streamId, self.fieldInspectionDuration or 6000)
    streamWriteFloat32(streamId, self.lubricationReducePerOperatingHour)
    streamWriteBool(streamId,    self.debugMode              or false)
    streamWriteBool(streamId,    self.drivetrainEnabled ~= false)
    streamWriteBool(streamId,    self.drivetrainAllowAutoMode ~= false)
    streamWriteBool(streamId,    self.drivetrainWindupDamage ~= false)
    streamWriteFloat32(streamId, self.drivetrainDiffLockReleaseSpeed or 10)
    streamWriteBool(streamId,    self.drivetrainParkBrakeEnabled ~= false)
    streamWriteBool(streamId,    self.drivetrainParkBrakeAuto ~= false)
    streamWriteBool(streamId,    self.exhaustSmokeEnabled ~= false)
    streamWriteFloat32(streamId, self.exhaustSmokeIntensity or 1.0)
end


---Called on client side on join, values are read in the order writeStream sends them
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_SettingsSyncEvent:readStream(streamId, connection)
    self.baseServiceWear           = streamReadFloat32(streamId)
    self.baseSystemsWear           = streamReadFloat32(streamId)
    self.downtimeMultiplier        = streamReadFloat32(streamId)
    self.generalWearEnabled        = streamReadBool(streamId)
    self.enableWarningMessages     = streamReadBool(streamId)
    self.systemStressGlobalMultiplier = streamReadFloat32(streamId)
    self.aiOverloadControl         = streamReadBool(streamId)
    self.aiDisableOnCriticalOverload = streamReadBool(streamId)
    self.contractVehicleProtection = streamReadBool(streamId)
    self.aiWorkerTargetStress      = streamReadFloat32(streamId)
    self.aiWorkerMinSpeed          = streamReadFloat32(streamId)
    self.instantInspection         = streamReadBool(streamId)
    self.parkVehicle               = streamReadBool(streamId)
    self.warrantyEnabled           = streamReadBool(streamId)
    self.globalPriceMultiplier     = streamReadFloat32(streamId)
    self.globalTimeMultiplier      = streamReadFloat32(streamId)
    self.dealerAlwaysAvailable     = streamReadBool(streamId)
    self.mobileAlwaysAvailable     = streamReadBool(streamId)
    self.ownAlwaysAvailable        = streamReadBool(streamId)
    self.mobileWorkshopRestrictionsEnabled = streamReadBool(streamId)
    self.openHour                  = streamReadFloat32(streamId)
    self.closeHour                 = streamReadFloat32(streamId)
    self.temperatureChangeSpeed    = streamReadFloat32(streamId)
    self.transTemperatureChangeMultiplier = streamReadFloat32(streamId)
    self.maxDirtInfluence          = streamReadFloat32(streamId)
    self.batteryUsableCapacityFactor = streamReadFloat32(streamId)
    self.alternatorMaxOutput       = streamReadFloat32(streamId)
    self.idleCurrentA              = streamReadFloat32(streamId)
    self.cloggingSpeed             = streamReadFloat32(streamId)
    self.fieldInspectionDuration   = streamReadFloat32(streamId)
    self.lubricationReducePerOperatingHour = streamReadFloat32(streamId)
    self.debugMode                 = streamReadBool(streamId)
    self.drivetrainEnabled         = streamReadBool(streamId)
    self.drivetrainAllowAutoMode   = streamReadBool(streamId)
    self.drivetrainWindupDamage    = streamReadBool(streamId)
    self.drivetrainDiffLockReleaseSpeed = streamReadFloat32(streamId)
    self.drivetrainParkBrakeEnabled = streamReadBool(streamId)
    self.drivetrainParkBrakeAuto   = streamReadBool(streamId)
    self.exhaustSmokeEnabled       = streamReadBool(streamId)
    self.exhaustSmokeIntensity     = streamReadFloat32(streamId)

    self:run(connection)
end


---Writes the received values into RMS_Config, clamping those with a bounded range
-- @param table event event carrying the configuration snapshot
local function applyConfig(event)
    local oldBatteryCapacityFactor = RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR
    local oldConfig = {
        parkVehicle = RMS_Config.MAINTENANCE.PARK_VEHICLE,
        instantInspection = RMS_Config.MAINTENANCE.INSTANT_INSPECTION
    }

    RMS_Config.CORE.BASE_SERVICE_WEAR                      = event.baseServiceWear
    RMS_Config.CORE.BASE_SYSTEMS_WEAR                      = event.baseSystemsWear
    RMS_Config.CORE.DOWNTIME_MULTIPLIER                    = event.downtimeMultiplier
    RMS_Config.CORE.GENERAL_WEAR_ENABLED                   = event.generalWearEnabled
    RMS_Config.CORE.ENABLE_WARNING_MESSAGES                = event.enableWarningMessages
    RMS_Config.CORE.SYSTEM_STRESS_GLOBAL_MULTIPLIER        = event.systemStressGlobalMultiplier
    RMS_Config.CORE.AI_OVERLOAD_AND_OVERHEAT_CONTROL       = event.aiOverloadControl
    RMS_Config.CORE.AI_DISABLE_ON_CRITICAL_OVERLOAD        = event.aiDisableOnCriticalOverload
    RMS_Config.CORE.CONTRACT_VEHICLE_PROTECTION            = event.contractVehicleProtection
    RMS_Config.CORE.AI_WORKER_PID.TARGET_STRESS            = event.aiWorkerTargetStress
    RMS_Config.CORE.AI_WORKER_PID.MIN_SPEED                = event.aiWorkerMinSpeed
    RMS_Config.MAINTENANCE.INSTANT_INSPECTION               = event.instantInspection
    RMS_Config.MAINTENANCE.PARK_VEHICLE                     = event.parkVehicle
    RMS_Config.MAINTENANCE.WARRANTY_ENABLED                 = event.warrantyEnabled
    RMS_Config.MAINTENANCE.GLOBAL_SERVICE_PRICE_MULTIPLIER  = event.globalPriceMultiplier
    RMS_Config.MAINTENANCE.GLOBAL_SERVICE_TIME_MULTIPLIER   = event.globalTimeMultiplier
    RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE             = event.dealerAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE             = event.mobileAlwaysAvailable
    RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE                = event.ownAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED = event.mobileWorkshopRestrictionsEnabled
    RMS_Config.WORKSHOP.OPEN_HOUR                           = event.openHour
    RMS_Config.WORKSHOP.CLOSE_HOUR                          = event.closeHour
    RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED             = math.clamp(event.temperatureChangeSpeed, 0.5, 2.0)
    RMS_Config.THERMAL.TRANS_TEMPERATURE_CHANGE_MULTIPLIER  = math.clamp(event.transTemperatureChangeMultiplier, 0.5, 2.0)
    RMS_Config.THERMAL.MAX_DIRT_INFLUENCE                   = math.clamp(event.maxDirtInfluence, 0.0, 1.0)
    RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR    = event.batteryUsableCapacityFactor
    RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT                    = event.alternatorMaxOutput
    RMS_Config.ELECTRICAL.IDLE_CURRENT_A                    = event.idleCurrentA
    RMS_Config.FIELD_CARE.CLOGGING_SPEED                    = event.cloggingSpeed
    RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION         = event.fieldInspectionDuration
    RMS_Config.FIELD_CARE.LUBRICATION_REDUCE_PER_OPERATING_HOUR = event.lubricationReducePerOperatingHour
    RMS_Config.DEBUG                                        = event.debugMode
    RMS_Config.DRIVETRAIN.ENABLED                           = event.drivetrainEnabled ~= false
    RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE                   = event.drivetrainAllowAutoMode ~= false
    RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED             = event.drivetrainWindupDamage ~= false
    RMS_Config.DRIVETRAIN.DIFFLOCK_AUTO_RELEASE_SPEED       = math.clamp(tonumber(event.drivetrainDiffLockReleaseSpeed) or 10, 10, 40)
    RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED                 = event.drivetrainParkBrakeEnabled ~= false
    RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE               = event.drivetrainParkBrakeAuto ~= false
    RMS_Config.EXHAUST.ENABLED                              = event.exhaustSmokeEnabled ~= false
    RMS_Config.EXHAUST.INTENSITY                            = math.clamp(tonumber(event.exhaustSmokeIntensity) or 1.0, 1, 3)

    local newConfig = {
        parkVehicle = event.parkVehicle,
        instantInspection = event.instantInspection
    }

    RMS_SettingsPage.applyPendingConfigSideEffects(oldConfig, newConfig)

    -- a changed battery capacity factor rescales the charge of every tracked vehicle
    if math.abs((oldBatteryCapacityFactor or 0) - (event.batteryUsableCapacityFactor or 0)) > 0.0001
        and RMS_Main ~= nil and RMS_Main.vehicles ~= nil then
        for _, vehicle in pairs(RMS_Main.vehicles) do
            if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
                RMS_Electrical.rescaleBatteryChargeFromSoc(vehicle)

                RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
            end
        end
    end

    RMS_Main:forceWorkshopUpdate(true)
end


---Applies the configuration, and on the server relays it to the other clients for a master user only
-- @param Connection connection connection
function RMS_SettingsSyncEvent:run(connection)
    if not connection:getIsServer() then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local user = g_currentMission.userManager:getUserByUserId(userId)
        if user == nil or not user:getIsMasterUser() then
            return
        end

        applyConfig(self)
        g_server:broadcastEvent(RMS_SettingsSyncEvent.new(), nil, connection)
    else
        applyConfig(self)
    end
end


---Send the local configuration from a client to the server
function RMS_SettingsSyncEvent.send()
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_SettingsSyncEvent.new())
    end
end
