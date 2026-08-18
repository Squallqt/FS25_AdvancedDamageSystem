-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Service dialog for maintenance, repair and overhaul, with a type, a part or system, and a yes or no option
RMS_MaintenanceThreeOptionsDialog = {}
RMS_MaintenanceThreeOptionsDialog.INSTANCE = nil

local RMS_MaintenanceThreeOptionsDialog_mt = Class(RMS_MaintenanceThreeOptionsDialog, MessageDialog)
local modDirectory = g_currentModDirectory

---Loads the dialog layout and stores the shared instance
function RMS_MaintenanceThreeOptionsDialog.register()
    local dialog = RMS_MaintenanceThreeOptionsDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_MaintenanceThreeOptionsDialog.xml", "RMS_MaintenanceThreeOptionsDialog", dialog)
    RMS_MaintenanceThreeOptionsDialog.INSTANCE = dialog
end

---Create instance of RMS_MaintenanceThreeOptionsDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_MaintenanceThreeOptionsDialog
function RMS_MaintenanceThreeOptionsDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_MaintenanceThreeOptionsDialog_mt)
    dialog.vehicle = nil
    dialog.overhaulSystemValues = nil
    dialog.optionOneValues = nil
    dialog.optionTwoValues = nil
    dialog.serviceInfoData = {}
    return dialog
end

---Returns the text with exactly one trailing colon
-- @param string? text label text
-- @return string text label ending with a colon
local function ensureTrailingColon(text)
    local normalized = tostring(text or ""):gsub("%s*:%s*$", "")
    return normalized .. ":"
end

---Returns the systems a partial overhaul may target, every system when the spec is unreadable
-- @param table? vehicle vehicle
-- @return table values system l10n keys in declared order
local function getEnabledOverhaulSystemValues(vehicle)
    local values = {}
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local allSystems = RealisticMechanicalSystems.SYSTEMS_ORDER

    if spec == nil or type(spec.systems) ~= "table" then
        return allSystems
    end

    for _, systemL10nKey in ipairs(allSystems) do
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemL10nKey)
        local systemData = spec.systems[systemKey]
        if type(systemData) == "table" and systemData.enabled ~= false then
            table.insert(values, systemL10nKey)
        end
    end

    return values
end

---Returns the second option actually sent, an overhaul only carries one outside the partial type
-- @param table? dialog dialog instance
-- @return string optionTwo second option value
local function getEffectiveOptionTwo(dialog)
    if dialog == nil then
        return "NONE"
    end

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL
        and dialog.selectedOptionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
        return "NONE"
    end

    return dialog.selectedOptionTwo
end

---Tells whether the mobile workshop accepts the selected procedure at the vehicle maintainability
-- @param table dialog dialog instance
-- @return boolean isAllowed true outside the mobile workshop or when restrictions are off
local function getMobileWorkshopAvailability(dialog)
    local vehicle = dialog ~= nil and dialog.vehicle or nil
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or (spec ~= nil and spec.workshopType or nil)

    if vehicle == nil or spec == nil or workshopType ~= RealisticMechanicalSystems.WORKSHOP.MOBILE then
        return true
    end

    if not RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED then
        return true
    end

    local serviceKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.STATUS, dialog.maintenanceType)
    local optionKey

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, dialog.selectedOptionOne)
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, dialog.selectedOptionOne)
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, dialog.selectedOptionOne)
    end

    local limits = RMS_Config.WORKSHOP.MOBILE_WORKSHOP_SERVICES_BY_MAINTAINABILITY
    local requiredMaintainability = limits ~= nil and serviceKey ~= nil and optionKey ~= nil and limits[serviceKey] ~= nil and limits[serviceKey][optionKey] or 0
    local currentMaintainability = spec.maintainability or 0

    return currentMaintainability >= requiredMaintainability
end

---Tells whether the selected workshop is currently open
-- @param table dialog dialog instance
-- @return boolean isOpen true when the workshop accepts a service now
local function getSelectedWorkshopAvailability(dialog)
    local vehicle = dialog ~= nil and dialog.vehicle or nil
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or (spec ~= nil and spec.workshopType or nil)

    if RMS_Main ~= nil and RMS_Main.isWorkshopTypeOpen ~= nil then
        return RMS_Main:isWorkshopTypeOpen(workshopType)
    end

    return true
end

---Returns the localized name of the selected procedure, option then service type
-- @param table? dialog dialog instance
-- @return string name procedure name
local function getSelectedProcedureDisplayName(dialog)
    if dialog == nil then
        return ""
    end

    local optionOneText = dialog.selectedOptionOne ~= nil and g_i18n:getText(dialog.selectedOptionOne) or ""
    local typeText = dialog.maintenanceType ~= nil and g_i18n:getText(dialog.maintenanceType) or ""

    if optionOneText == "" then
        return typeText
    end

    if typeText == "" then
        return optionOneText
    end

    return string.format("%s %s", optionOneText, typeText)
end

---Opens the dialog on a vehicle for a maintenance, a repair or an overhaul
-- @param table vehicle vehicle
-- @param string maintenanceType service status constant
function RMS_MaintenanceThreeOptionsDialog.show(vehicle, maintenanceType)
    if RMS_MaintenanceThreeOptionsDialog.INSTANCE == nil then RMS_MaintenanceThreeOptionsDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or maintenanceType == nil then return end
    
    local dialog = RMS_MaintenanceThreeOptionsDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.maintenanceType = maintenanceType
    dialog.optionThree.useYesNoTexts = true
    dialog.optionOne:setState(1)
    dialog.optionTwo:setState(1)
    if dialog.optionThree.setIsChecked ~= nil then
        dialog.optionThree:setIsChecked(false, false, false)
    else
        dialog.optionThree:setState(BinaryOptionElement.STATE_LEFT)
    end

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        dialog.selectedOptionOne = RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        dialog.selectedOptionOne = RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        dialog.selectedOptionOne = RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD
    end
    dialog.overhaulSystemValues = getEnabledOverhaulSystemValues(vehicle)
    dialog.selectedOptionTwo = dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL
        and dialog.overhaulSystemValues[1]
        or RealisticMechanicalSystems.PART_TYPES.OEM
    dialog.selectedOptionThree = false
    
    dialog:updateScreen()
    g_gui:showDialog("RMS_MaintenanceThreeOptionsDialog")
end

---Rebuilds the three options, the price, duration and finish time rows, and the disclaimers
function RMS_MaintenanceThreeOptionsDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or spec.workshopType

    -- title
    self.dialogTitleElement:setText(g_i18n:getText(self.maintenanceType))

    -- option one
    local optionOneText = ""
    local optionOneOptions = {}
    local optionOneValues = {}
    local choosenPartsForQuickFix = {}
    local choosenPartsForRepair = {}

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_maintenance")
        optionOneValues = {
            RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD,
            RealisticMechanicalSystems.MAINTENANCE_TYPES.MINIMAL,
            RealisticMechanicalSystems.MAINTENANCE_TYPES.EXTENDED,
            RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE
        }
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_repair")

        -- an active breakdown can be quick fixed, an inactive one can only be replaced
        local isHaveBreakdownToBeQuickFixed = false
        local isHaveBreakdownToBeReplaced = false
        local activeBreakdowns = self.vehicle:getActiveBreakdowns()
        local breakdownRegistry = RMS_Breakdowns.BreakdownRegistry
        for breakdownId, breakdownData in pairs(activeBreakdowns) do
            if breakdownData.isSelectedForRepair and breakdownData.isVisible then
                if breakdownData.isActive then
                    isHaveBreakdownToBeQuickFixed = true
                    isHaveBreakdownToBeReplaced = true
                    table.insert(choosenPartsForQuickFix, breakdownRegistry[breakdownId].part)
                    table.insert(choosenPartsForRepair, breakdownRegistry[breakdownId].part)
                else 
                    isHaveBreakdownToBeReplaced = true
                    table.insert(choosenPartsForRepair, breakdownRegistry[breakdownId].part)
                end
            end
        end

        if isHaveBreakdownToBeReplaced then
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM)
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.HIGH)
        end
        if isHaveBreakdownToBeQuickFixed then
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.LOW)
        end

    else
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_overhaul")
        optionOneValues = {
            RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD,
            RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL,
            RealisticMechanicalSystems.OVERHAUL_TYPES.FULL
        }
    end

    for _, optionValue in ipairs(optionOneValues) do
        table.insert(optionOneOptions, g_i18n:getText(optionValue))
    end

    self.optionOneValues = optionOneValues
    if self.optionOneValues[1] == nil then
        self.selectedOptionOne = nil
    elseif RMS_Utils.getKeyByValue(self.optionOneValues, self.selectedOptionOne) == nil then
        self.selectedOptionOne = self.optionOneValues[1]
        if self.optionOne.setState ~= nil then
            self.optionOne:setState(1)
        end
    end

    self.optionOneText:setText(optionOneText)
    self.optionOne:setTexts(optionOneOptions)

    -- option two
    local optionTwoText = ""
    local optionTwoOptions = {}
    local optionTwoValues = {}

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_maintenance")
        optionTwoValues = RealisticMechanicalSystems.PART_TYPES_ORDER
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_repair")
        optionTwoValues = RealisticMechanicalSystems.PART_TYPES_ORDER
    else
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_overhaul")
        self.overhaulSystemValues = self.overhaulSystemValues or getEnabledOverhaulSystemValues(self.vehicle)
        optionTwoValues = self.overhaulSystemValues
    end

    for _, optionValue in ipairs(optionTwoValues) do
        table.insert(optionTwoOptions, g_i18n:getText(optionValue))
    end

    self.optionTwoValues = optionTwoValues
    self.optionTwoText:setText(optionTwoText)
    self.optionTwo:setTexts(optionTwoOptions)

    -- selected options read back from the element states
    if self.optionOne ~= nil and self.optionOne.getState ~= nil then
        local optionOneState = tonumber(self.optionOne:getState())
        if optionOneState ~= nil then
            if self.optionOneValues ~= nil and self.optionOneValues[optionOneState] ~= nil then
                self.selectedOptionOne = self.optionOneValues[optionOneState]
            end
        end
    end

    if self.optionTwo ~= nil and self.optionTwo.getState ~= nil then
        local optionTwoState = tonumber(self.optionTwo:getState())
        if optionTwoState ~= nil and self.optionTwoValues[optionTwoState] ~= nil then
            self.selectedOptionTwo = self.optionTwoValues[optionTwoState]
        end
    end

    local disableOptionTwo = false
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        disableOptionTwo = self.selectedOptionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        disableOptionTwo = self.selectedOptionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
    end
    self.optionTwo:setDisabled(disableOptionTwo)

    local isAllowedInMobileWorkshop = getMobileWorkshopAvailability(self)
    local isWorkshopOpen = getSelectedWorkshopAvailability(self)

    -- price, duration, finishtime
    local isWarrantyRepair = self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR
        and self.vehicle:isWarrantyRepairCovered(self.selectedOptionOne, self.selectedOptionTwo)
    local effectiveOptionTwo = getEffectiveOptionTwo(self)
    local servicePrice = self.vehicle:getServicePrice(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType)
    local priceValue = ""

    if isWarrantyRepair then
        priceValue = g_i18n:getText("rms_option_menu_warranty_repair_text")
    else
        priceValue = g_i18n:formatMoney(servicePrice, 0, true, false)
    end
    local durationValue = RMS_Utils.formatDuration(self.vehicle:getServiceDuration(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType))
    local finishTimeValue = RMS_Utils.formatFinishTime(self.vehicle:getServiceFinishTime(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType))

    self.serviceInfoData = {
        {title = ensureTrailingColon(g_i18n:getText("rms_option_menu_price_text")), value = priceValue},
        {title = ensureTrailingColon(g_i18n:getText("rms_option_menu_duration_text")), value = durationValue},
        {title = ensureTrailingColon(g_i18n:getText("rms_option_menu_finish_time_text")), value = finishTimeValue}
    }

    self.serviceInfoTable:setDataSource(self)
    self.serviceInfoTable:setDelegate(self)
    self.serviceInfoTable:reloadData()

    -- disclaimers
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        local optionOneDisclaimers = {
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD]   = g_i18n:getText("rms_option_menu_maintenance_standard_description"),
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.MINIMAL]    = g_i18n:getText("rms_option_menu_maintenance_minimal_description"),
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.EXTENDED]   = g_i18n:getText("rms_option_menu_maintenance_extended_description"),
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE] = g_i18n:getText("rms_option_menu_maintenance_preventive_description")
        }
        self.optionOneDisclaimer:setText(optionOneDisclaimers[self.selectedOptionOne] or "")
        self.choosenPartsText:setVisible(false)
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        local choosenPartsText = g_i18n:getText("rms_option_menu_chosen_parts_text")
        local choosenPartsLabels = {}
        if self.selectedOptionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW then
            for _, part in ipairs(choosenPartsForQuickFix) do
                table.insert(choosenPartsLabels, g_i18n:getText(part))
            end
            self.optionOneDisclaimer:setText(g_i18n:getText("rms_option_menu_repair_type_fix_description"))
        else
            for _, part in ipairs(choosenPartsForRepair) do
                table.insert(choosenPartsLabels, g_i18n:getText(part))
            end
            if self.selectedOptionOne == RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM then
                self.optionOneDisclaimer:setText(g_i18n:getText("rms_option_menu_repair_type_replacement_description"))
            else
                self.optionOneDisclaimer:setText(g_i18n:getText("rms_option_menu_repair_type_advanced_description"))
            end
        end
        if #choosenPartsLabels > 0 then
            choosenPartsText = choosenPartsText .. " " .. table.concat(choosenPartsLabels, ", ")
        end
        self.choosenPartsText:setTextColor(0.88, 0.45, 0.10, 1)
        self.choosenPartsText:setText(choosenPartsText)
        self.choosenPartsText:setVisible(true)
    else
        local optionOneDisclaimers = {
            [RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD] = g_i18n:getText("rms_option_menu_overhaul_standard_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL]  = g_i18n:getText("rms_option_menu_overhaul_partial_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.FULL]     = g_i18n:getText("rms_option_menu_overhaul_full_description")
        }
        self.optionOneDisclaimer:setText(optionOneDisclaimers[self.selectedOptionOne] or "")
        self.choosenPartsText:setVisible(false)
    end

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        self.optionTwoDisclaimer:setText("")
    else
        local optionTwoDisclaimers = {
            [RealisticMechanicalSystems.PART_TYPES.OEM]         = g_i18n:getText("rms_option_menu_part_oem_description"),
            [RealisticMechanicalSystems.PART_TYPES.USED]        = g_i18n:getText("rms_option_menu_part_used_description"),
            [RealisticMechanicalSystems.PART_TYPES.AFTERMARKET] = g_i18n:getText("rms_option_menu_part_aftermarket_description"),
            [RealisticMechanicalSystems.PART_TYPES.PREMIUM]     = g_i18n:getText("rms_option_menu_part_premium_description")
        }
        self.optionTwoDisclaimer:setText(optionTwoDisclaimers[self.selectedOptionTwo] or "")
    end

    if not isAllowedInMobileWorkshop then
        local procedureName = getSelectedProcedureDisplayName(self)
        local vehicleName = self.vehicle.getFullName ~= nil and self.vehicle:getFullName() or g_i18n:getText("ui_vehicle")
        self.optionOneDisclaimer:setText(string.format(g_i18n:getText("rms_mobile_workshop_low_maintainability"), procedureName, vehicleName))
        self.optionOneDisclaimer:setTextColor(0.88, 0.18, 0.18, 1)
        self.optionTwoDisclaimer:setVisible(false)
    else
        self.optionOneDisclaimer:setTextColor(1, 1, 1, 1)
        self.optionTwoDisclaimer:setVisible(self.maintenanceType ~= RealisticMechanicalSystems.STATUS.OVERHAUL)
    end

    -- option three
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        self.optionThreeText:setText(g_i18n:getText("rms_option_menu_perform_repair"))
        self.optionThreeDisclaimer:setText(g_i18n:getText("rms_option_menu_option_three_disclaimer_repair_after_detection"))
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        self.optionThreeText:setText(g_i18n:getText("rms_option_menu_perform_maintenance"))
        self.optionThreeDisclaimer:setText(g_i18n:getText("rms_option_menu_option_three_disclaimer_maintenance_after_repair"))
    else
        self.optionThreeText:setText(g_i18n:getText("rms_option_menu_perform_renew_paint"))
        self.optionThreeDisclaimer:setText(g_i18n:getText("rms_option_menu_option_three_disclaimer_overhaul_repaint"))
    end

    if self.startServiceButton ~= nil then
        self.startServiceButton:setDisabled(not isAllowedInMobileWorkshop or not isWorkshopOpen)
    end

end


---Selects the service type option and refreshes the screen
-- @param integer index selected option index
function RMS_MaintenanceThreeOptionsDialog:onClickOptionOne(index)
    if self.optionOneValues ~= nil and self.optionOneValues[index] ~= nil then
        self.selectedOptionOne = self.optionOneValues[index]
    end
    self:updateScreen()
end

---Selects the part type or the overhaul system and refreshes the screen
-- @param integer index selected option index
function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwo(index)
    self.selectedOptionTwo = self.optionTwoValues[index] or self.selectedOptionTwo
    self:updateScreen()
end

---Toggles the yes or no option and refreshes the screen
-- @param integer state binary option state
-- @param table binaryOptionElement binary option element
function RMS_MaintenanceThreeOptionsDialog:onClickOptionThree(state, binaryOptionElement)
    self.selectedOptionThree = (state == BinaryOptionElement.STATE_RIGHT)
    self:updateScreen()
end

---Starts the service directly on the server, sends a request from a client, after a money check
function RMS_MaintenanceThreeOptionsDialog:onClickStartService()
    if not getMobileWorkshopAvailability(self) or not getSelectedWorkshopAvailability(self) then
        return
    end

    local vehicle = self.vehicle
    local workshopType = RMS_WorkshopDialog.INSTANCE.workshopType
    local effectiveOptionTwo = getEffectiveOptionTwo(self)
    
    local price = vehicle:getServicePrice(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType)
    if g_currentMission:getMoney() < price then
        InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
        return
    end

    if g_server ~= nil then
        vehicle:initService(self.maintenanceType, workshopType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree)
        g_currentMission:addMoney(-1 * price, vehicle:getOwnerFarmId(), MoneyType.VEHICLE_RUNNING_COSTS, true, true)
        RMS_VehicleChangeStatusEvent.send(vehicle)
    else
        RMS_ServiceRequestEvent.send(vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree)
    end

    self:close()
end

---Closes the dialog
function RMS_MaintenanceThreeOptionsDialog:onClickBack()
    self:close()
end

---Returns the number of service info rows
-- @param table list list element
-- @param integer section section index
-- @return integer count number of rows
function RMS_MaintenanceThreeOptionsDialog:getNumberOfItemsInSection(list, section)
    if list == self.serviceInfoTable then
        return #self.serviceInfoData
    end

    return 0
end

---Fills one service info row with its title and value
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_MaintenanceThreeOptionsDialog:populateCellForItemInSection(list, section, index, cell)
    if list ~= self.serviceInfoTable then
        return
    end

    local data = self.serviceInfoData[index]
    if data == nil then
        return
    end

    local titleElement = cell:getAttribute("serviceInfoTitle")
    local valueElement = cell:getAttribute("serviceInfoValue")
    titleElement:setText(data.title or "")
    valueElement:setText(data.value or "")
    titleElement:setTextColor(1, 1, 1, 1)
    valueElement:setTextColor(1, 1, 1, 1)
end

---
-- @param function superFunc super function
function RMS_MaintenanceThreeOptionsDialog:onOpen(superFunc)
    if self.optionThree ~= nil then
        self.optionThree.useYesNoTexts = true
        if self.optionThree.setIsChecked ~= nil then
            self.optionThree:setIsChecked(self.selectedOptionThree == true, false, false)
        elseif self.optionThree.getState ~= nil then
            self.optionThree:setState(self.optionThree:getState())
        end
    end

    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)
end

---
-- @param function superFunc super function
function RMS_MaintenanceThreeOptionsDialog:onClose(superFunc)
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)
end
