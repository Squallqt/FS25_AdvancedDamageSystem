RMS_MaintenanceTwoOptionsDialog = {}
RMS_MaintenanceTwoOptionsDialog.INSTANCE = nil

local RMS_MaintenanceTwoOptionsDialog_mt = Class(RMS_MaintenanceTwoOptionsDialog, MessageDialog)
local modDirectory = g_currentModDirectory

function RMS_MaintenanceTwoOptionsDialog.register()
    local dialog = RMS_MaintenanceTwoOptionsDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_MaintenanceTwoOptionsDialog.xml", "RMS_MaintenanceTwoOptionsDialog", dialog)
    RMS_MaintenanceTwoOptionsDialog.INSTANCE = dialog
end

function RMS_MaintenanceTwoOptionsDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_MaintenanceTwoOptionsDialog_mt)
    dialog.vehicle = nil
    dialog.optionOneValues = nil
    dialog.serviceInfoData = {}
    return dialog
end

local function ensureTrailingColon(text)
    local normalized = tostring(text or ""):gsub("%s*:%s*$", "")
    return normalized .. ":"
end

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

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        optionKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, dialog.selectedOptionOne)
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, dialog.selectedOptionOne)
    end

    local limits = RMS_Config.WORKSHOP.MOBILE_WORKSHOP_SERVICES_BY_MAINTAINABILITY
    local requiredMaintainability = limits ~= nil and serviceKey ~= nil and optionKey ~= nil and limits[serviceKey] ~= nil and limits[serviceKey][optionKey] or 0
    local currentMaintainability = spec.maintainability or 0

    return currentMaintainability >= requiredMaintainability
end

local function getSelectedWorkshopAvailability(dialog)
    local vehicle = dialog ~= nil and dialog.vehicle or nil
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or (spec ~= nil and spec.workshopType or nil)

    if RMS_Main ~= nil and RMS_Main.isWorkshopTypeOpen ~= nil then
        return RMS_Main:isWorkshopTypeOpen(workshopType)
    end

    return true
end

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

function RMS_MaintenanceTwoOptionsDialog.show(vehicle, maintenanceType)
    if RMS_MaintenanceTwoOptionsDialog.INSTANCE == nil then RMS_MaintenanceTwoOptionsDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or maintenanceType == nil then return end
    
    local dialog = RMS_MaintenanceTwoOptionsDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.maintenanceType = maintenanceType

    dialog.optionThree.useYesNoTexts = true
    dialog.optionOne:setState(1)
    if dialog.optionThree.setIsChecked ~= nil then
        dialog.optionThree:setIsChecked(false, false, false)
    else
        dialog.optionThree:setState(BinaryOptionElement.STATE_LEFT)
    end

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        dialog.selectedOptionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        dialog.selectedOptionOne = RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD
    end
    dialog.selectedOptionThree = false
    
    dialog:updateScreen()
    g_gui:showDialog("RMS_MaintenanceTwoOptionsDialog")
end

function RMS_MaintenanceTwoOptionsDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems

    -- title
    self.dialogTitleElement:setText(g_i18n:getText(self.maintenanceType))

    -- option one
    local optionOneText = ""
    local optionOneOptions = {}

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_inspection")
        local instantInspection = RMS_Config.MAINTENANCE.INSTANT_INSPECTION
        if instantInspection then
            self.optionOneValues = {
                RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD,
                RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE
            }
            if self.selectedOptionOne == RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL then
                self.selectedOptionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
            end
        else
            self.optionOneValues = {
                RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD,
                RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL,
                RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE
            }
        end
    else
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_overhaul")
        self.optionOneValues = {
            RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD,
            RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL,
            RealisticMechanicalSystems.OVERHAUL_TYPES.FULL
        }
    end

    for _, optionValue in ipairs(self.optionOneValues) do
        table.insert(optionOneOptions, g_i18n:getText(optionValue))
    end

    self.optionOneText:setText(optionOneText)
    self.optionOne:setTexts(optionOneOptions)

    if self.optionOne ~= nil and self.optionOne.getState ~= nil then
        local optionOneState = tonumber(self.optionOne:getState())
        if optionOneState ~= nil and self.optionOneValues[optionOneState] ~= nil then
            self.selectedOptionOne = self.optionOneValues[optionOneState]
        end
    end

    local isAllowedInMobileWorkshop = getMobileWorkshopAvailability(self)
    local isWorkshopOpen = getSelectedWorkshopAvailability(self)

    -- price, duration, finishtime
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or spec.workshopType
    local priceValue = g_i18n:formatMoney(self.vehicle:getServicePrice(self.maintenanceType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree, workshopType), 0, true, false)
    local durationValue = ""
    if RMS_Config.MAINTENANCE.INSTANT_INSPECTION and  self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        durationValue = g_i18n:getText("rms_option_menu_duration_instant")
    else
        durationValue = RMS_Utils.formatDuration(self.vehicle:getServiceDuration(self.maintenanceType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree, workshopType))
    end
    local finishTimeValue = RMS_Utils.formatFinishTime(self.vehicle:getServiceFinishTime(self.maintenanceType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree, workshopType))

    self.serviceInfoData = {
        {title = ensureTrailingColon(g_i18n:getText("rms_option_menu_price_text")), value = priceValue},
        {title = ensureTrailingColon(g_i18n:getText("rms_option_menu_duration_text")), value = durationValue},
        {title = ensureTrailingColon(g_i18n:getText("rms_option_menu_finish_time_text")), value = finishTimeValue}
    }

    self.serviceInfoTable:setDataSource(self)
    self.serviceInfoTable:setDelegate(self)
    self.serviceInfoTable:reloadData()


    -- disclaimers
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        local disclaimerByType = {
            [RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD] = g_i18n:getText("rms_option_menu_inspection_standard_description"),
            [RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL] = g_i18n:getText("rms_option_menu_inspection_visual_description"),
            [RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE] = g_i18n:getText("rms_option_menu_inspection_complete_description")
        }
        self.optionOneDisclaimer:setText(disclaimerByType[self.selectedOptionOne] or "")
    else
        local disclaimerByType = {
            [RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD] = g_i18n:getText("rms_option_menu_overhaul_standard_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL]  = g_i18n:getText("rms_option_menu_overhaul_partial_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.FULL]     = g_i18n:getText("rms_option_menu_overhaul_full_description")
        }
        self.optionOneDisclaimer:setText(disclaimerByType[self.selectedOptionOne] or "")
    end

    if not isAllowedInMobileWorkshop then
        local procedureName = getSelectedProcedureDisplayName(self)
        local vehicleName = self.vehicle.getFullName ~= nil and self.vehicle:getFullName() or g_i18n:getText("ui_vehicle")
        self.optionOneDisclaimer:setText(string.format(g_i18n:getText("rms_mobile_workshop_low_maintainability"), procedureName, vehicleName))
        self.optionOneDisclaimer:setTextColor(0.88, 0.18, 0.18, 1)
    else
        self.optionOneDisclaimer:setTextColor(1, 1, 1, 1)
    end

    

    -- option three
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        self.optionThreeText:setText(g_i18n:getText("rms_option_menu_perform_repair"))
        self.optionThreeDisclaimer:setText(g_i18n:getText("rms_option_menu_option_three_disclaimer_repair_after_detection"))
    else
        self.optionThreeText:setText(g_i18n:getText("rms_option_menu_perform_renew_paint"))
        self.optionThreeDisclaimer:setText(g_i18n:getText("rms_option_menu_option_three_disclaimer_overhaul_repaint"))
    end

    if self.startServiceButton ~= nil then
        self.startServiceButton:setDisabled(not isAllowedInMobileWorkshop or not isWorkshopOpen)
    end
end

-- ====================================================================
-- CALLBACKS & EVENTS
-- ====================================================================

function RMS_MaintenanceTwoOptionsDialog:onClickOptionOne(index)
    self.selectedOptionOne = self.optionOneValues[index] or self.selectedOptionOne
    self:updateScreen()
end

function RMS_MaintenanceTwoOptionsDialog:onClickOptionThree(state, binaryOptionElement)
    self.selectedOptionThree = (state == BinaryOptionElement.STATE_RIGHT)
    self:updateScreen()
end

function RMS_MaintenanceTwoOptionsDialog:onClickStartService()
    if not getMobileWorkshopAvailability(self) or not getSelectedWorkshopAvailability(self) then
        return
    end

    local vehicle = self.vehicle
    local workshopType = RMS_WorkshopDialog.INSTANCE.workshopType
    local spec = vehicle.spec_RealisticMechanicalSystems
    
    local price = vehicle:getServicePrice(self.maintenanceType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree, workshopType)
    
    if g_currentMission:getMoney() < price then
        InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
        return
    end
    
    if g_server ~= nil then
        -- Server: execute locally and broadcast
        spec.serviceOptionOne = self.selectedOptionOne
        spec.serviceOptionTwo = self.selectedOptionTwo
        spec.serviceOptionThree = self.selectedOptionThree
        vehicle:initService(self.maintenanceType, workshopType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree)
        g_currentMission:addMoney(-1 * price, vehicle:getOwnerFarmId(), MoneyType.VEHICLE_RUNNING_COSTS, true, true)
        RMS_VehicleChangeStatusEvent.send(vehicle)
    else
        -- Client: only send request to server
        RMS_ServiceRequestEvent.send(vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree, price)
    end
    
    self:close()
end

function RMS_MaintenanceTwoOptionsDialog:onClickBack()
    self:close()
end

function RMS_MaintenanceTwoOptionsDialog:getNumberOfItemsInSection(list, section)
    if list == self.serviceInfoTable then
        return #self.serviceInfoData
    end

    return 0
end

function RMS_MaintenanceTwoOptionsDialog:populateCellForItemInSection(list, section, index, cell)
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

function RMS_MaintenanceTwoOptionsDialog:onOpen(superFunc)
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

function RMS_MaintenanceTwoOptionsDialog:onClose(superFunc)
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)
end
