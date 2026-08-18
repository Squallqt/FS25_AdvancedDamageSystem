-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Charges applied when a leased vehicle is returned: overdue maintenance, repairs and washing
RMS_Leasing = {}

---Converts a value to a number, falling back when it cannot
-- @param any value value to convert
-- @param float? fallback value used when the conversion fails
-- @return float number converted number
local function getNumber(value, fallback)
    local numericValue = tonumber(value)
    if numericValue == nil then
        return fallback or 0
    end

    return numericValue
end

---Tells whether the extended leasing mod is loaded
-- @return boolean hasMod true when it is present
function RMS_Leasing.hasExtendedLeasing()
    return g_modIsLoaded ~= nil and g_modIsLoaded["FS25_ExtendedLeasing"] == true
end

---Wraps the vanilla vehicle sale so a leased RMS vehicle goes through the mod dialog
-- @param table _mission current mission
function RMS_Leasing.preLoad(_mission)
    SellVehicleEvent.run = Utils.overwrittenFunction(SellVehicleEvent.run, RMS_Leasing.onSellVehicleEventRun)
    ShopController.sell = Utils.overwrittenFunction(ShopController.sell, RMS_Leasing.onShopControllerSell)
end

---Hooks the mod into the mission load
function RMS_Leasing.init()
    Mission00.load = Utils.prependedFunction(Mission00.load, RMS_Leasing.preLoad)
end

---Tells whether RMS tracks the vehicle
-- @param table? vehicle vehicle
-- @return boolean isTracked true when RMS tracks it
function RMS_Leasing.isRMSVehicle(vehicle)
    return vehicle ~= nil
        and vehicle.spec_RealisticMechanicalSystems ~= nil
        and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
end

---Tells whether the vehicle is leased
-- @param table? vehicle vehicle
-- @return boolean isLeased true for a leased vehicle
function RMS_Leasing.isLeasedVehicle(vehicle)
    if vehicle == nil then
        return false
    end

    local leasedState = Vehicle ~= nil and Vehicle.PROPERTY_STATE_LEASED or 3
    return vehicle.propertyState == leasedState
end

---Tells whether the vehicle is both leased and tracked by RMS
-- @param table? vehicle vehicle
-- @return boolean isSupported true when the charges apply
function RMS_Leasing.isSupportedVehicle(vehicle)
    return RMS_Leasing.isRMSVehicle(vehicle) and RMS_Leasing.isLeasedVehicle(vehicle)
end

---Computes the return charges, the extended leasing mod taking the washing over
-- @param table? vehicle vehicle
-- @return table breakdown raw amounts, displayed amounts, charged amounts and rows
function RMS_Leasing.getReturnBreakdown(vehicle)
    local emptyResult = {
        vehicle = vehicle,
        hasExtendedLeasing = RMS_Leasing.hasExtendedLeasing(),
        raw = {
            overdueMaintenance = 0,
            repair = 0,
            washing = 0
        },
        display = {
            overdueMaintenance = 0,
            repair = 0,
            washing = 0,
            total = 0
        },
        charge = {
            overdueMaintenance = 0,
            repair = 0,
            washing = 0,
            total = 0
        },
        rows = {
            { label = "rms_sell_dialog_overdue_maintenance_penalty", key = "overdueMaintenance", value = 0 },
            { label = "rms_sell_dialog_repair_penalty", key = "repair", value = 0 },
            { label = "rms_sell_dialog_washing_penalty", key = "washing", value = 0 }
        }
    }

    if not RMS_Leasing.isRMSVehicle(vehicle) then
        return emptyResult
    end

    local rms = RealisticMechanicalSystems
    local hasExtendedLeasing = RMS_Leasing.hasExtendedLeasing()
    local vehiclePrice = getNumber(vehicle.getPrice ~= nil and vehicle:getPrice(), 0)
    local deposit = MathUtil.round(vehiclePrice * EconomyManager.DEFAULT_LEASING_DEPOSIT_FACTOR, 0)
    local dirtAmount = math.min(getNumber(vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount(), 0), 1)
    local washingCost = deposit * 0.3 * dirtAmount
    local serviceLevel = getNumber(vehicle.getServiceLevel ~= nil and vehicle:getServiceLevel(), RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD)
    local serviceExpiredThreshold = math.max(getNumber(RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD, 0), 0.0001)
    local overdueMaintenanceRatio = math.max(serviceExpiredThreshold - serviceLevel, 0) * (1 / serviceExpiredThreshold)
    local overdueMaintenanceCost = overdueMaintenanceRatio * getNumber(
        vehicle.getServicePrice ~= nil and vehicle:getServicePrice(
            rms.STATUS.MAINTENANCE,
            rms.MAINTENANCE_TYPES.STANDARD,
            rms.PART_TYPES.OEM,
            false,
            rms.WORKSHOP.DEALER
        ),
        0
    )
    local repairCost = getNumber(
        vehicle.getServicePrice ~= nil and vehicle:getServicePrice(
            rms.STATUS.REPAIR,
            rms.REPAIR_TYPES.MEDIUM,
            rms.PART_TYPES.OEM,
            false,
            rms.WORKSHOP.DEALER,
            true
        ),
        0
    )

    emptyResult.hasExtendedLeasing = hasExtendedLeasing
    emptyResult.raw.overdueMaintenance = overdueMaintenanceCost
    emptyResult.raw.repair = repairCost
    emptyResult.raw.washing = washingCost

    emptyResult.display.overdueMaintenance = -overdueMaintenanceCost
    emptyResult.display.repair = -repairCost
    emptyResult.display.washing = -washingCost
    emptyResult.display.total = emptyResult.display.overdueMaintenance
        + emptyResult.display.repair
        + emptyResult.display.washing

    if hasExtendedLeasing then
        emptyResult.charge.washing = 0
    else
        emptyResult.charge.washing = -washingCost
    end

    emptyResult.charge.overdueMaintenance = -overdueMaintenanceCost
    emptyResult.charge.repair = -repairCost
    emptyResult.charge.total = emptyResult.charge.overdueMaintenance
        + emptyResult.charge.repair
        + emptyResult.charge.washing

    emptyResult.rows[1].value = emptyResult.display.overdueMaintenance
    emptyResult.rows[2].value = emptyResult.display.repair
    emptyResult.rows[3].value = emptyResult.display.washing

    return emptyResult
end

---Routes the sale of a leased RMS vehicle through the mod dialog
-- @param table self shop controller
-- @param function overwrittenFunc overwritten function
-- @param table storeItem store item
-- @param table concreteItem vehicle being sold
function RMS_Leasing.onShopControllerSell(self, overwrittenFunc, storeItem, concreteItem)
    local vehicle = concreteItem
    local isConcreteVehicle = vehicle ~= nil and vehicle ~= ShopDisplayItem.NO_CONCRETE_ITEM

    if not isConcreteVehicle or not RMS_Leasing.isSupportedVehicle(vehicle) then
        overwrittenFunc(self, storeItem, concreteItem)
        return
    end

    self.isSelling = true
    self.currentSellStoreItem = storeItem
    self.currentSellItem = concreteItem

    RMS_SellItemDialog.show(vehicle, storeItem, RMS_Leasing.onShopControllerSellDialogCallback, self)
end

---Forwards the player answer to the shop controller
-- @param table? self shop controller
-- @param boolean yes true when the player confirmed
function RMS_Leasing.onShopControllerSellDialogCallback(self, yes)
    if self == nil then
        return
    end

    self:onSellCallback(yes)
end

---Debits the return charges on the server once the vehicle is sold
-- @param table self sell vehicle event
-- @param function overwrittenFunc overwritten function
-- @param Connection connection connection
function RMS_Leasing.onSellVehicleEventRun(self, overwrittenFunc, connection)
    local vehicle = self.vehicle
    local ownerFarmId = vehicle ~= nil and vehicle:getOwnerFarmId() or FarmManager.SPECTATOR_FARM_ID
    local hasPermission = vehicle ~= nil
        and g_currentMission:getHasPlayerPermission(Farm.PERMISSION.SELL_VEHICLE, connection, ownerFarmId)
    local isVehicleInUse = vehicle ~= nil and vehicle:getIsInUse(connection)
    local shouldApplyCharges = RMS_Leasing.isSupportedVehicle(vehicle)
        and hasPermission
        and not isVehicleInUse

    overwrittenFunc(self, connection)

    if connection:getIsServer() or not shouldApplyCharges or vehicle == nil then
        return
    end

    local farm = g_farmManager:getFarmById(ownerFarmId)
    if ownerFarmId == nil or ownerFarmId == FarmManager.SPECTATOR_FARM_ID or farm == nil then
        return
    end

    local breakdown = RMS_Leasing.getReturnBreakdown(vehicle)
    if breakdown == nil or breakdown.charge == nil then
        return
    end

    local changes = {
        { value = breakdown.charge.overdueMaintenance, moneyType = MoneyType.VEHICLE_RUNNING_COSTS },
        { value = breakdown.charge.repair, moneyType = MoneyType.VEHICLE_RUNNING_COSTS },
        { value = breakdown.charge.washing, moneyType = MoneyType.VEHICLE_RUNNING_COSTS }
    }

    for _, change in ipairs(changes) do
        local value = getNumber(change.value, 0)
        if value ~= 0 and change.moneyType ~= nil then
            farm:changeBalance(value, change.moneyType)
            g_currentMission:addMoneyChange(value, ownerFarmId, change.moneyType, true)
        end
    end
end

RMS_Leasing.init()
