RMS_WorkshopDialog = {}
RMS_WorkshopDialog.INSTANCE = nil

local RMS_WorkshopDialog_mt = Class(RMS_WorkshopDialog, MessageDialog)
local modDirectory = g_currentModDirectory

local log_dbg = RMS_Utils.createLogger("[RMS_WORKSHOP_DIALOG]")


function RMS_WorkshopDialog.register()
    local dialog = RMS_WorkshopDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_WorkshopDialog.xml", "RMS_WorkshopDialog", dialog)
    RMS_WorkshopDialog.INSTANCE = dialog
end

function RMS_WorkshopDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_WorkshopDialog_mt)
    dialog.vehicle = nil
    dialog.isDialogOpen = false
    dialog.lastObservedStatus = nil
    return dialog
end


function RMS_WorkshopDialog.show(vehicle)
    if RMS_WorkshopDialog.INSTANCE.updateScreen == nil then RMS_WorkshopDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        log_dbg("Tried to show RMS_WorkshopDialog without a valid vehicle.")
        return
    end
    local dialog = RMS_WorkshopDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.activeBreakdowns = vehicle:getActiveBreakdowns()
    dialog.visibleBreakdowns = {}
    dialog.breakdownRegistry = RMS_Breakdowns.BreakdownRegistry
    dialog.workshopType = RealisticMechanicalSystems.WORKSHOP.DEALER
    dialog.lastObservedStatus = vehicle:getCurrentStatus()

    if g_workshopScreen.isOwnWorkshop then  dialog.workshopType = RealisticMechanicalSystems.WORKSHOP.OWN end
    if g_workshopScreen.isMobileWorkshop then  dialog.workshopType = RealisticMechanicalSystems.WORKSHOP.MOBILE end

    dialog:updateScreen()
    g_gui:showDialog("RMS_WorkshopDialog")
end

function RMS_WorkshopDialog:updateScreen()
    if self.vehicle == nil then return end
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local vehicle = self.vehicle
    local STATUS = RealisticMechanicalSystems.STATUS
    self.lastObservedStatus = self.vehicle:getCurrentStatus()

    -- ====================================================================
    -- 1: Vehicle Info Panel
    -- ====================================================================

    local balanceText = g_i18n:formatMoney(math.floor(g_currentMission:getMoney()), 2, true, false)
    self.balanceElement:setText(balanceText)
    RMS_Utils.updateMoneyBoxLayout(
        self.balanceTitleElement,
        self.balanceElement,
        self.moneyBox,
        self.moneyBoxBg,
        g_i18n:getText("ui_balance"),
        balanceText
    )
    self.vehicleImage:setImageFilename(vehicle:getImageFilename())
    self.vehicleNameValue:setText(vehicle:getFullName())
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local currentValue = g_i18n:formatMoney(math.min(math.floor(vehicle:getSellPrice() * EconomyManager.DIRECT_SELL_MULTIPLIER), vehicle:getPrice()), 0, true, false)
    local newPrice = nil
    if storeItem ~= nil then
        newPrice = StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations)
        if newPrice == nil or newPrice <= 0 then
            newPrice = storeItem.price
        end
    end
    if newPrice ~= nil and newPrice > 0 then
        self.valueValue:setText(string.format("%s / %s", currentValue, g_i18n:formatMoney(newPrice, 0, true, false)))
    else
        self.valueValue:setText(currentValue)
    end
    
    self.ageValue:setText(string.format("%d %s", vehicle.age, g_i18n:getText("rms_ws_age_unit")))
    self.operatingHoursValue:setText(string.format("%s %s", vehicle:getFormattedOperatingTime(), g_i18n:getText("rms_ws_hours_unit")))
    
    self.lastServiceValue:setText(RMS_Utils.formatTimeAgo(vehicle:getLastMaintenanceDate()))
    self.maintainabilityValue:setText(RMS_Utils.formatMaintainability(spec.maintainability))
    self.maintainabilityValue:setTextColor(RMS_Utils.getValueColor(spec.maintainability, 1.2, 1.1, 1.0, 0.9, false))

    local monthsSinceInspectionText = RMS_Utils.formatTimeAgo(self.vehicle:getLastInspectionDate())
    local inspectedService, isCompleteServiceInspection = self.vehicle:getLastInspectedService()
    local inspectedCondition, isCompleteInspection = self.vehicle:getLastInspectedCondition()

    self.serviceValue:setText(RMS_Utils.formatService(inspectedService, isCompleteServiceInspection))
    self.serviceValue:setTextColor(RMS_Utils.getServiceColor(inspectedService, isCompleteServiceInspection))
    self.conditionValue:setText(RMS_Utils.formatCondition(inspectedCondition, isCompleteInspection))
    self.conditionValue:setTextColor(RMS_Utils.getConditionColor(inspectedCondition, isCompleteInspection))
    self.serviceLastInspectionDeltaValue:setTextColor(0.5, 0.5, 0.5, 1.0)
    self.conditionLastInspectionDeltaValue:setTextColor(0.5, 0.5, 0.5, 1.0)
    self.serviceLastInspectionDeltaValue:setText(monthsSinceInspectionText)
    self.conditionLastInspectionDeltaValue:setText(monthsSinceInspectionText)

    self.relAndMainValue:setText(RMS_Utils.formatOperatingHours(self.vehicle:getHoursSinceLastMaintenance(), self.vehicle:getMaintenanceInterval()))

    -- ====================================================================
    -- 2: Breakdowns Table
    -- ====================================================================

    self.visibleBreakdowns = {}
    for id, breakdown in pairs(self.activeBreakdowns) do
        if breakdown.isVisible then
            table.insert(self.visibleBreakdowns, id)
        end
    end

    self.breakdownTable:setDataSource(self)
    self.breakdownTable:setDelegate(self)
    self.breakdownTable:reloadData()

    -- ====================================================================
    -- 3: Status Text
    -- ====================================================================
    
    local buttonsDisabled = false
    local statusText = ""
    local statusColor = {1, 1, 1, 1}
    
    self.maintanceInProgressSpinner:setVisible(false)
    local isWorkshopTypeOpen = RMS_Main == nil
        or RMS_Main.isWorkshopTypeOpen == nil
        or RMS_Main:isWorkshopTypeOpen(self.workshopType)

    if not isWorkshopTypeOpen then
        buttonsDisabled = true
        statusText = g_i18n:getText("rms_ws_status_closed")
        statusColor = {0.6, 0.6, 0.6, 1}
    else
        statusText = g_i18n:getText("rms_ws_status_open")
        buttonsDisabled = false
    end

    if spec.currentState ~= STATUS.READY then
        self.maintanceInProgressSpinner:setVisible(true)
        buttonsDisabled = true
        local finishTimeText = RMS_Utils.formatFinishTime(self.vehicle:getServiceFinishTime(nil, nil, nil, nil))
        local localizedStatus = g_i18n:getText(spec.currentState)
        statusText = string.format(g_i18n:getText("rms_ws_status_in_progress_format"), localizedStatus, finishTimeText)
        if spec.currentState ~= STATUS.REPAIR then
            local inspectingText = g_i18n:getText("rms_ws_inspecting_status")
            self.serviceValue:setText(inspectingText)
            self.serviceValue:setTextColor(0.5, 0.5, 0.5, 1.0)
            self.conditionValue:setText(inspectingText)
            self.conditionValue:setTextColor(0.5, 0.5, 0.5, 1.0)
        end
    end

    self.statusText:setText(statusText)
    self.statusText:setTextColor(statusColor[1], statusColor[2], statusColor[3], statusColor[4])

    -- ====================================================================
    -- 4: Action Buttons
    -- ====================================================================

    local hasSystemEligibleForOverhaul = false
    if spec.systems ~= nil then
        for _, systemData in pairs(spec.systems) do
            if type(systemData) == "table" and systemData.enabled ~= false and (tonumber(systemData.condition) or 1.0) < 0.5 then
                hasSystemEligibleForOverhaul = true
                break
            end
        end
    end

    if g_workshopScreen.isDealer or g_workshopScreen.isOwnWorkshop then
        self.inspectionButton.disabled = buttonsDisabled 
        self.maintenanceButton.disabled = buttonsDisabled
        self.repairButton.disabled = buttonsDisabled
        self.overhaulButton.disabled = buttonsDisabled or not hasSystemEligibleForOverhaul
    else
        self.inspectionButton.disabled = buttonsDisabled or spec.currentState ~= STATUS.READY
        self.maintenanceButton.disabled = buttonsDisabled or spec.currentState ~= STATUS.READY
        self.repairButton.disabled = buttonsDisabled or spec.currentState ~= STATUS.READY
        self.overhaulButton.disabled = true
    end

    local isUnderService = spec.currentState ~= STATUS.READY
    self.cancelServiceButton:setVisible(isUnderService)
    self.cancelServiceButton.disabled = not isUnderService
    self.inspectionButton:setVisible(not isUnderService)
    self.maintenanceButton:setVisible(not isUnderService)
    self.repairButton:setVisible(not isUnderService)
    self.overhaulButton:setVisible(not isUnderService)

    local inspectionPrice = self.vehicle:getServicePrice(RealisticMechanicalSystems.STATUS.INSPECTION, RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD, "NONE", false, self.workshopType)
    local maintenancePrice = self.vehicle:getServicePrice(RealisticMechanicalSystems.STATUS.MAINTENANCE, RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD, RealisticMechanicalSystems.PART_TYPES.OEM, false, self.workshopType)
    local repairPrice = self.vehicle:getServicePrice(RealisticMechanicalSystems.STATUS.REPAIR, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, RealisticMechanicalSystems.PART_TYPES.OEM, false, self.workshopType)
    local overhaulPrice = self.vehicle:getServicePrice(RealisticMechanicalSystems.STATUS.OVERHAUL, RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD, "NONE", false, self.workshopType)

    local selectedRepairCount = 0
    for _, breakdown in pairs(self.activeBreakdowns) do
        if breakdown ~= nil and breakdown.isVisible and breakdown.isSelectedForRepair then
            selectedRepairCount = selectedRepairCount + 1
        end
    end

    if selectedRepairCount == 0 then
        self.repairButton.disabled = true
    end
    
    local buttonFormat = g_i18n:getText("rms_ws_button_price_format")
    self.inspectionButton:setText(string.format(buttonFormat, g_i18n:getText("rms_ws_action_inspection"), g_i18n:formatMoney(inspectionPrice, 0, true, false)))
    self.maintenanceButton:setText(string.format(buttonFormat, g_i18n:getText("rms_ws_action_maintenance"), g_i18n:formatMoney(maintenancePrice, 0, true, false)))
    if self.vehicle:isWarrantyRepairCovered(RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, RealisticMechanicalSystems.PART_TYPES.OEM) and selectedRepairCount > 0 then
        self.repairButton:setText(string.format(buttonFormat, g_i18n:getText("rms_ws_action_repair"), g_i18n:getText("rms_option_menu_warranty_repair_text")))
    else
        self.repairButton:setText(string.format(buttonFormat, g_i18n:getText("rms_ws_action_repair"), g_i18n:formatMoney(repairPrice, 0, true, false)))
    end
    self.overhaulButton:setText(string.format(buttonFormat, g_i18n:getText("rms_ws_action_overhaul"), g_i18n:formatMoney(overhaulPrice, 0, true, false)))

    -- ====================================================================
    -- 5: Table Visibility
    -- ====================================================================
    
    local isListEmpty = #self.visibleBreakdowns == 0

    if self.vehicle:getCurrentStatus() == STATUS.READY then
        self.breakdownTable:setVisible(not isListEmpty)
        self.tableSlider:setVisible(not isListEmpty)
        self.emptyTableText:setVisible(isListEmpty)
        self.emptyTableText:setText(g_i18n:getText("rms_ws_info_no_breakdowns"))
        self.emptyTableText:setTextColor(0.5, 0.5, 0.5, 1)
    else
        self:updateServiceProgressText()
    end
    --self.statusText:setPosition(0, 0.015)
end

function RMS_WorkshopDialog:getServiceProgressPercent()
    if self.vehicle == nil or self.vehicle.spec_RealisticMechanicalSystems == nil then
        return nil
    end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local totalTime = spec.pendingProgressTotalTime or 0
    local elapsedTime = spec.pendingProgressElapsedTime or 0

    if totalTime <= 0 then
        return nil
    end

    local ratio = math.max(0, math.min(elapsedTime / totalTime, 1))
    return math.floor(ratio * 100)
end

function RMS_WorkshopDialog:updateServiceProgressText()
    if self.vehicle == nil or self.vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end

    if self.vehicle:getCurrentStatus() == RealisticMechanicalSystems.STATUS.READY then
        return
    end

    local progressPercent = self:getServiceProgressPercent()

    local progressText = ""
    if progressPercent ~= nil then
        progressText = string.format("%d%%", progressPercent)
    end

    self.emptyTableText:setVisible(true)
    self.breakdownTable:setVisible(false)
    self.tableSlider:setVisible(false)
    self.emptyTableText:setText(progressText)
    self.emptyTableText:setTextColor(0.455, 0.565, 0.115, 1)
end

function RMS_WorkshopDialog:getNumberOfItemsInSection(list, section)
    return #self.visibleBreakdowns
end


function RMS_WorkshopDialog:populateCellForItemInSection(list, section, index, cell)
    local breakdownId = self.visibleBreakdowns[index]
    local data = self.activeBreakdowns[breakdownId]
    if data == nil then return end

    local part_key = self.breakdownRegistry[breakdownId].part or self.breakdownRegistry[breakdownId].system
    local stage_key = self.breakdownRegistry[breakdownId].stages[data.stage].severity
    local description_key = self.breakdownRegistry[breakdownId].stages[data.stage].description
    local price = self.vehicle:getBreakdownRepairPrice(breakdownId, data.stage, RealisticMechanicalSystems.PART_TYPES.OEM)
    local selected = data.isSelectedForRepair

    local stageText = ""
    local descriptionText = ""

    if data.isActive == false and data.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX then
        stageText = g_i18n:getText("rms_breakdowns_quick_fix_stage")
        descriptionText = g_i18n:getText("rms_breakdowns_temporarily_repaired_description")
    elseif data.isActive == false and data.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
        stageText = g_i18n:getText("rms_breakdowns_defected_parts_stage")
        descriptionText = g_i18n:getText("rms_breakdowns_defected_parts_detected_description")
    else
        stageText = g_i18n:getText(stage_key)
        descriptionText = g_i18n:getText(description_key)
    end

    if data.stage == 1 then
        cell:getAttribute("rms_tableBreakdownStage"):setTextColor(1, 1, 1, 1)
    elseif data.stage == 2 then
        cell:getAttribute("rms_tableBreakdownStage"):setTextColor( 0.5, 0.5, 0, 1)
    elseif data.stage == 3 then
        cell:getAttribute("rms_tableBreakdownStage"):setTextColor( 0.7, 0.3, 0, 1)
    else
        cell:getAttribute("rms_tableBreakdownStage"):setTextColor(0.88, 0.12, 0, 1)
    end

    cell:getAttribute("rms_tableBreakdownName"):setText(g_i18n:getText(part_key))
    cell:getAttribute("rms_tableBreakdownDisc"):setText(descriptionText)
    cell:getAttribute("rms_tableBreakdownStage"):setText(stageText)
    cell:getAttribute("rms_tableBreakdownPrice"):setText(g_i18n:formatMoney(price, 0, true, false))
    
    
    local selectedText = g_i18n:getText("rms_ws_option_no")
    if selected then 
        selectedText = g_i18n:getText("rms_ws_option_yes")
        cell:getAttribute("rms_tableBreakdownName"):setDisabled(false)
        cell:getAttribute("rms_tableBreakdownDisc"):setDisabled(false)
        cell:getAttribute("rms_tableBreakdownStage"):setDisabled(false)
        cell:getAttribute("rms_tableBreakdownPrice"):setDisabled(false)
        cell:getAttribute("rms_tableBreakdownSelect"):setTextColor(0.3, 0.7, 0.0, 1.0)
    else
        cell:getAttribute("rms_tableBreakdownName"):setDisabled(true)
        cell:getAttribute("rms_tableBreakdownDisc"):setDisabled(true)
        cell:getAttribute("rms_tableBreakdownStage"):setDisabled(true)
        cell:getAttribute("rms_tableBreakdownPrice"):setDisabled(true)
        cell:getAttribute("rms_tableBreakdownSelect"):setTextColor(0.2, 0.2, 0.2, 1)
    end
    cell:getAttribute("rms_tableBreakdownSelect"):setText(selectedText)
end


function RMS_WorkshopDialog:onRowClick(button)
    if self.vehicle:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY then return end
    if button == nil or self.visibleBreakdowns[button.parent.indexInSection] == nil then return end
    
    local id = self.visibleBreakdowns[button.parent.indexInSection]
    local breakdown = self.activeBreakdowns[id]
    if breakdown then
        breakdown.isSelectedForRepair = not breakdown.isSelectedForRepair
        self:updateScreen()
    end
end

function RMS_WorkshopDialog:onClickShowLog()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    if #spec.maintenanceLog > 1 then
        RMS_MaintenanceLogDialog.show(self.vehicle)
    else
        InfoDialog.show(g_i18n:getText("rms_ws_no_log_empty_message"))
    end
end

function RMS_WorkshopDialog:onClickShowReport()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
            RMS_ReportDialog.show(self.vehicle, entry)
            return
        end
    end
    InfoDialog.show(g_i18n:getText("rms_ws_no_last_report_message"))
end

function RMS_WorkshopDialog:onClickInspection()
    RMS_MaintenanceTwoOptionsDialog.show(self.vehicle, RealisticMechanicalSystems.STATUS.INSPECTION)
end

function RMS_WorkshopDialog:onClickService()
    RMS_MaintenanceThreeOptionsDialog.show(self.vehicle, RealisticMechanicalSystems.STATUS.MAINTENANCE)
end

function RMS_WorkshopDialog:onClickRepair()
    RMS_MaintenanceThreeOptionsDialog.show(self.vehicle, RealisticMechanicalSystems.STATUS.REPAIR)
end

function RMS_WorkshopDialog:onClickOverhaul()
    RMS_MaintenanceThreeOptionsDialog.show(self.vehicle, RealisticMechanicalSystems.STATUS.OVERHAUL)
end

function RMS_WorkshopDialog:onClickCancelService()
    if self.vehicle == nil then return end
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.currentState == RealisticMechanicalSystems.STATUS.READY then return end

    local title = string.format(g_i18n:getText("rms_ws_cancel_confirm_title"), g_i18n:getText(spec.currentState))
    local text = g_i18n:getText("rms_ws_cancel_confirm_text")

    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(self.onCancelServiceConfirm, self, text, title, nil, nil)
    end
end

function RMS_WorkshopDialog:onCancelServiceConfirm(yes)
    if yes and self.vehicle ~= nil then
        if g_server ~= nil then
            -- Server: execute locally
            self.vehicle:cancelService()
        else
            -- Client: send request to server
            RMS_CancelServiceEvent.send(self.vehicle)
        end
        self:updateScreen()
    end
end


function RMS_WorkshopDialog:onCreate(superFunc)
    --
end

function RMS_WorkshopDialog:onOpen(superFunc)
    self.isDialogOpen = true

    local function onVehicleChangeStatusEvent(vehicle)
        if self.vehicle.node == vehicle.node then
            self:updateScreen()
        end
    end

    local function onWorkshopChangeStatusEvent(vehicle)
        self:updateScreen()
    end

    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)
    g_messageCenter:subscribe(MessageType.RMS_VEHICLE_CHANGE_STATUS, onVehicleChangeStatusEvent, self)
    g_messageCenter:subscribe(MessageType.RMS_WORKSHOP_CHANGE_STATUS, onWorkshopChangeStatusEvent, self)
end

function RMS_WorkshopDialog:onClose(superFunc)
    self.isDialogOpen = false
    self.lastObservedStatus = nil
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)
    g_currentMission:showMoneyChange(MoneyType.VEHICLE_RUNNING_COSTS)
    g_currentMission:showMoneyChange(MoneyType.SHOP_VEHICLE_BUY)
	g_currentMission:showMoneyChange(MoneyType.SHOP_VEHICLE_SELL)
end

function RMS_WorkshopDialog:onClickBack()
    self:close()
end
