-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Maintenance log dialog listing the service history of a vehicle and its ownership statistics
RMS_MaintenanceLogDialog = {}
RMS_MaintenanceLogDialog.INSTANCE = nil

local RMS_MaintenanceLogDialog_mt = Class(RMS_MaintenanceLogDialog, MessageDialog)
local modDirectory = g_currentModDirectory

---Tells whether a repaired breakdown is worth listing, general wear is not
-- @param string? breakdownId breakdown id
-- @return boolean isLoggable true when the breakdown is listed
local function isLoggableRepairBreakdownId(breakdownId)
    return breakdownId ~= nil and breakdownId ~= "GENERAL_WEAR"
end

---Tells whether a log entry is shown, treating a missing flag as visible and accepting string flags
-- @param table? entry maintenance log entry
-- @return boolean isVisible true when the entry is listed
local function isLogEntryVisible(entry)
    if entry == nil then
        return false
    end

    local value = entry.isVisible
    if value == nil then
        return true
    end

    if type(value) == "string" then
        local v = string.lower(value)
        if v == "false" or v == "0" or v == "off" or v == "no" then
            return false
        end
        return true
    end

    return value ~= false
end

---Counts the breakdowns resolved by the completed repair and overhaul entries
-- @param table logEntries maintenance log entries
-- @return integer count number of resolved breakdowns
local function getResolvedBreakdownsCount(logEntries)
    if type(logEntries) ~= "table" then
        return 0
    end

    local total = 0
    local S = RealisticMechanicalSystems.STATUS

    for _, entry in ipairs(logEntries) do
        if entry ~= nil and entry.isCompleted ~= false then
            local entryType = entry.type

            if entryType == S.REPAIR or entryType == S.OVERHAUL then
                local conditionData = entry.conditionData
                local selectedBreakdowns = conditionData ~= nil and conditionData.selectedBreakdowns or nil

                if type(selectedBreakdowns) == "table" then
                    for _, breakdownId in ipairs(selectedBreakdowns) do
                        if breakdownId ~= nil and breakdownId ~= "GENERAL_WEAR" then
                            total = total + 1
                        end
                    end
                end
            end
        end
    end

    return total
end

---Loads the dialog layout and stores the shared instance
function RMS_MaintenanceLogDialog.register()
    local dialog = RMS_MaintenanceLogDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_MaintenanceLogDialog.xml", "RMS_MaintenanceLogDialog", dialog)
    RMS_MaintenanceLogDialog.INSTANCE = dialog
end

---Create instance of RMS_MaintenanceLogDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_MaintenanceLogDialog
function RMS_MaintenanceLogDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_MaintenanceLogDialog_mt)
    dialog.vehicle = nil
    dialog.logDataAll = nil
    dialog.selectedLogIndex = nil
    return dialog
end

---Returns the selected log entry, the list being displayed newest first
-- @return table? entry selected maintenance log entry
function RMS_MaintenanceLogDialog:getSelectedLogEntry()
    if self.logData == nil or self.selectedLogIndex == nil then
        return nil
    end

    local entryIndex = #self.logData - self.selectedLogIndex + 1
    return self.logData[entryIndex]
end

---Enables the report button only when the selected entry carries a report
function RMS_MaintenanceLogDialog:updateShowReportButtonState()
    if self.showReportButton == nil then
        return
    end

    local entry = self:getSelectedLogEntry()
    self.showReportButton.disabled = not (entry ~= nil and RealisticMechanicalSystems.getIsLogEntryHasReport(entry))
end

---Rebuilds the displayed list from the full log, keeping the visible entries
function RMS_MaintenanceLogDialog:rebuildVisibleLogData()
    self.logData = {}
    if self.logDataAll == nil then
        return
    end

    for _, entry in ipairs(self.logDataAll) do
        if isLogEntryVisible(entry) then
            table.insert(self.logData, entry)
        end
    end
end

---Opens the dialog on a vehicle with its newest entry selected
-- @param table vehicle vehicle
function RMS_MaintenanceLogDialog.show(vehicle)
    if RMS_MaintenanceLogDialog.INSTANCE == nil then RMS_MaintenanceLogDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then return end
    
    local dialog = RMS_MaintenanceLogDialog.INSTANCE
    dialog.vehicle = vehicle
    
    dialog.logDataAll = vehicle.spec_RealisticMechanicalSystems.maintenanceLog or {}
    dialog:rebuildVisibleLogData()
    dialog.selectedLogIndex = #dialog.logData > 0 and 1 or nil
    
    dialog:updateScreen()
    g_gui:showDialog("RMS_MaintenanceLogDialog")
end

---Rebuilds the log list and the ownership statistics header
function RMS_MaintenanceLogDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    self.logDataAll = spec.maintenanceLog or {}
    self:rebuildVisibleLogData()

    local balanceText = g_i18n:formatMoney(g_currentMission:getMoney(), 0, true, false)
    self.balanceElement:setText(balanceText)
    RMS_Utils.updateMoneyBoxLayout(
        self.balanceTitleElement,
        self.balanceElement,
        self.moneyBox,
        self.moneyBoxBg,
        g_i18n:getText("ui_balance"),
        balanceText
    )
    self.vehicleNameValue:setText(g_i18n:getText('rms_log_title') .. " " .. self.vehicle:getFullName())

    local totalCost = 0
    local totalBreakdowns = getResolvedBreakdownsCount(self.logDataAll)
    local purchaseDate = {}
    local purchaseHours = 0

    for _, entry in pairs(self.logDataAll) do
        totalCost = totalCost + (entry.price or 0)
        if entry.id == 1 then
            purchaseDate = entry.date or {}
            purchaseHours = entry.conditionData and entry.conditionData.operatingHours or 0
        end
    end

    self.totalCostValue:setText(g_i18n:formatMoney(totalCost, 0, true, false))

    -- ownership age in months, counted from the first log entry
    local currentYear = g_currentMission.environment.currentYear
    local currentMonth = g_currentMission.environment.currentPeriod
    
    local pMonth = (purchaseDate and purchaseDate.month) or currentMonth
    local pYear = (purchaseDate and purchaseDate.year) or currentYear
    local age = math.max(1, (currentMonth + (currentYear - 1) * 12) - (pMonth + (pYear - 1) * 12))
    
    local costPerMonth = totalCost / age
    local currentLoggedHours = (tonumber(spec.realOperatingTime) or 0) / (60 * 60 * 1000)
    local avgBreakdownInterval = totalBreakdowns > 0 and math.max(((currentLoggedHours - (purchaseHours or 0)) / totalBreakdowns), 0) or 0
    local averageMaintenanceInterval = 0

    self.costPerMonthValue:setText(g_i18n:formatMoney(costPerMonth, 0, true, false) .. " / " .. g_i18n:getText("rms_ws_age_unit"))
    self.ownershipMonthsValue:setText(tostring(age) .. " " .. g_i18n:getText("rms_ws_age_unit"))
    self.totalBreakdownsCountValue:setText(string.format("%d", totalBreakdowns))
    if totalBreakdowns > 0 then
        self.averageBreakdownsIntervalValue:setText(string.format("%.1f", avgBreakdownInterval) .. " " .. g_i18n:getText("rms_spec_hour_s"))
    else
        self.averageBreakdownsIntervalValue:setText("-")
    end

    local maintenanceCount = 0
    for _, entry in pairs(self.logDataAll) do
        if entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE then
            maintenanceCount = maintenanceCount + 1
        end
    end

    if maintenanceCount > 0 then
        local sumMaintenanceInterval = 0
        local lastServiceHours = purchaseHours or 0
        for i = 1, #self.logDataAll do
            local nextEntry = self.logDataAll[i]
            if nextEntry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE then
                if nextEntry.conditionData and nextEntry.conditionData.operatingHours then
                    sumMaintenanceInterval = sumMaintenanceInterval + (nextEntry.conditionData.operatingHours - lastServiceHours)
                    lastServiceHours = nextEntry.conditionData.operatingHours
                end
            end
        end
        averageMaintenanceInterval = math.max(sumMaintenanceInterval / maintenanceCount, 0)
        self.averageMaintenanceIntervalValue:setText(string.format("%.1f", averageMaintenanceInterval) .. " " .. g_i18n:getText("rms_spec_hour_s"))
    else
        self.averageMaintenanceIntervalValue:setText("-")
    end

    self.logTable:setDataSource(self)
    self.logTable:setDelegate(self)
    self.logTable:reloadData()

    if #self.logData > 0 then
        if self.selectedLogIndex == nil or self.selectedLogIndex > #self.logData then
            self.selectedLogIndex = 1
        end
        self.logTable:setSelectedItem(1, self.selectedLogIndex, false, false)
    else
        self.selectedLogIndex = nil
    end

    self:updateShowReportButtonState()

    local isEmpty = #self.logData == 0
    self.logTable:setVisible(not isEmpty)
    self.emptylogText:setVisible(isEmpty)
end

---Returns the number of visible log entries
-- @param table list list element
-- @param integer section section index
-- @return integer count number of rows
function RMS_MaintenanceLogDialog:getNumberOfItemsInSection(list, section)
    return #self.logData
end

---Fills one log row with its date, hours, colour coded type, description and price
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_MaintenanceLogDialog:populateCellForItemInSection(list, section, index, cell)
    local entryIndex = #self.logData - index + 1
    local entry = self.logData[entryIndex]
    local spec = self.vehicle.spec_RealisticMechanicalSystems

    if entry == nil then return end

    -- date
    local yearStr = "00"
    if entry.date and entry.date.year then
        if entry.date.year >= 10 then
            yearStr = tostring(entry.date.year)
        else
            yearStr = "0" .. tostring(entry.date.year)
        end
    end
    local dDay = (entry.date and entry.date.day) or 1
    local dMonth = (entry.date and entry.date.month) or 1
    local dateStr = string.format("%s %s. '%s", dDay, g_i18n:formatPeriod(dMonth, true), yearStr)
    cell:getAttribute("logDate"):setText(dateStr)
    
    -- operating hours
    local opHours = (entry.conditionData and entry.conditionData.operatingHours) or 0
    cell:getAttribute("logHours"):setText(string.format("%.1f", opHours) .. " " .. g_i18n:getText("rms_spec_hour_s"))

    -- maintenance type
    local typeText = "UNKNOWN"
    local color = {1, 1, 1, 1}
    
    local S = RealisticMechanicalSystems.STATUS
    if entry.type == S.REPAIR then
        typeText = g_i18n:getText("rms_ws_action_repair")
        color = {0.88, 0.12, 0.12, 1}
    elseif entry.type == S.MAINTENANCE then
        typeText = g_i18n:getText("rms_ws_action_maintenance")
        color = {0.2, 0.6, 1.0, 1}
    elseif entry.type == S.INSPECTION then
        typeText = g_i18n:getText("rms_ws_action_inspection")
        color = {1, 1, 1, 1}
    elseif entry.type == S.OVERHAUL then
        typeText = g_i18n:getText("rms_ws_action_overhaul")
        color = {1.0, 0.5, 0.0, 1}
    elseif entry.type == S.REFILL then
        typeText = g_i18n:getText("rms_ws_action_refill")
        color = HUD.COLOR.ACTIVE
    end
    
    cell:getAttribute("logType"):setText(typeText)
    cell:getAttribute("logType"):setTextColor(unpack(color))

    -- description
    local descText = ""
    local repairedParts = {}
    local seenParts = {}

    if entry.conditionData and entry.conditionData.selectedBreakdowns then
        for _, breakdownId in ipairs(entry.conditionData.selectedBreakdowns) do
            if isLoggableRepairBreakdownId(breakdownId) then
                local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
                 
                local partKey = breakdownDef ~= nil and (breakdownDef.part or breakdownDef.system) or nil
                if partKey ~= nil then
                    if not seenParts[partKey] then
                        table.insert(repairedParts, partKey)
                        seenParts[partKey] = true
                    end
                end
            end
        end
    end

    local partsNames = {}
    if repairedParts and #repairedParts > 0 then
        for _, partKey in ipairs(repairedParts) do
            table.insert(partsNames, g_i18n:getText(partKey))
        end
    end
   
    if entry.isCompleted == false then
        descText = g_i18n:getText("rms_log_cancelled_desc")
    else
        local partTypeSuffix = ""
        if entry.optionTwo ~= nil and entry.optionTwo ~= "NONE" then
            partTypeSuffix = " (" .. g_i18n:getText(entry.optionTwo) .. ")"
        end

        -- repair
        if entry.type == S.REPAIR then
            local repairedPartsText = table.concat(partsNames, ", ")
            if repairedPartsText == "" then
                repairedPartsText = g_i18n:getText("rms_log_repair_desc_generic")
            end
            descText = repairedPartsText .. partTypeSuffix

        -- maintenance
        elseif entry.type == S.MAINTENANCE then
            descText = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText(entry.optionOne) .. " " .. g_i18n:getText("rms_ws_task_maintenance"))
            descText = descText .. partTypeSuffix
            if #repairedParts > 0 then
                descText = descText .. ". " .. string.format(g_i18n:getText("rms_log_inspection_desc_with_breakdowns"), table.concat(partsNames, ", "))
            end

        -- inspection
        elseif entry.type == S.INSPECTION then
            descText = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText(entry.optionOne) .. " " .. g_i18n:getText("rms_ws_task_inspection"))
            if #repairedParts > 0 then
                descText = descText .. ". " .. string.format(g_i18n:getText("rms_log_inspection_desc_with_breakdowns"), table.concat(partsNames, ", "))
            else
                descText = descText .. ". " .. g_i18n:getText("rms_log_inspection_desc_no_breakdowns")
            end
        

        -- overhaul
        elseif entry.type == S.OVERHAUL then
            descText = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText(entry.optionOne) .. " " .. g_i18n:getText("rms_ws_task_overhaul"))
            if entry.optionThree then
                descText = descText .. ". " .. g_i18n:getText("rms_log_overhaul_desc_with_painting")
            end
        end
    end

    cell:getAttribute("logDescription"):setText(descText)
    
    cell:getAttribute("logPrice"):setText(g_i18n:formatMoney(entry.price or 0, 0, true, false))
    color = {0.88, 0.12, 0.12, 1}
    cell:getAttribute("logPrice"):setTextColor(unpack(color))
end

---Closes the dialog
function RMS_MaintenanceLogDialog:onClickBack()
    self:close()
end

---Selects a log row and refreshes the report button
-- @param table row clicked row
function RMS_MaintenanceLogDialog:onRowClick(row)
    if row == nil or row.indexInSection == nil then return end

    self.selectedLogIndex = row.indexInSection
    if self.logTable ~= nil then
        self.logTable:setSelectedItem(1, row.indexInSection, false, false)
    end
    self:updateShowReportButtonState()
end

---Opens the report of the selected entry, or tells the player there is none
function RMS_MaintenanceLogDialog:onClickShowReport()
    local entry = self:getSelectedLogEntry()
    if entry ~= nil and RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
        RMS_ReportDialog.show(self.vehicle, entry)
        return
    end

    InfoDialog.show(g_i18n:getText("rms_ws_no_report_message"))
end

---
-- @param function superFunc super function
function RMS_MaintenanceLogDialog:onOpen(superFunc)
    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)
end

---
-- @param function superFunc super function
function RMS_MaintenanceLogDialog:onClose(superFunc)
    self.vehicle = nil
    self.logData = nil
    self.logDataAll = nil
    self.selectedLogIndex = nil
    g_messageCenter:unsubscribeAll(self)
end
