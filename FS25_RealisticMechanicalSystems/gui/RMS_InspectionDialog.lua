-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Field inspection dialog listing fluid, cooling, air and lubrication findings
RMS_InspectionDialog = {}
RMS_InspectionDialog.INSTANCE = nil

local RMS_InspectionDialog_mt = Class(RMS_InspectionDialog, MessageDialog)
local modDirectory = g_currentModDirectory
local TEXT_COLOR = {1, 1, 1, 1}

-- share of the gauge kept for everything under the minimum mark
local GAUGE_MARK_RATIO = 0.25

-- inspection target to the dialog section holding its row
local TARGET_TO_SECTION = {
    engineOil = "technicalFluidsData",
    coolant = "technicalFluidsData",
    hydraulicFluid = "technicalFluidsData",
    transmissionOil = "technicalFluidsData",
    radiator = "coolingAndAirData",
    airFilter = "coolingAndAirData",
    lubrication = "lubricationData"
}

-- fluid rows of the dialog, with the system carrying them and the level they read
local FLUID_ROWS = {
    { titleKey = "rms_inspection_engine_oil", systemKey = "engine", levelKey = "engineOilLevel" },
    { titleKey = "rms_inspection_coolant", systemKey = "cooling", levelKey = "coolantLevel" },
    { titleKey = "rms_inspection_hydraulic_fluid", systemKey = "hydraulics", levelKey = "hydraulicFluidLevel" },
    { titleKey = "rms_inspection_transmission_oil", systemKey = "transmission", levelKey = "transmissionOilLevel" }
}

-- severity rank of each status, 0 for fine up to 4 for critical, the highest wins on a row
local STATUS_PRIORITY = {
    rms_inspection_ok = 0,
    rms_inspection_status_slightly_low = 1,
    rms_inspection_status_slightly_darkened = 1,
    rms_inspection_status_slight_moisture = 1,
    rms_inspection_status_slightly_dirty = 1,
    rms_inspection_status_slightly_dry = 1,
    rms_inspection_status_low = 2,
    rms_inspection_status_darkened = 2,
    rms_inspection_status_seepage = 2,
    rms_inspection_status_dirty = 2,
    rms_inspection_status_dry = 2,
    rms_inspection_status_very_low = 3,
    rms_inspection_status_contaminated = 3,
    rms_inspection_status_active_leak = 3,
    rms_inspection_status_heavily_clogged = 3,
    rms_inspection_status_very_dry = 3,
    rms_inspection_status_critically_low = 4,
    rms_inspection_status_critical_condition = 4,
    rms_inspection_status_severe_leak = 4,
    rms_inspection_status_critically_clogged = 4,
    rms_inspection_status_critically_dry = 4,
    rms_inspection_status_not_required = 0
}

---Localizes a value when it is an rms_ key, returns it as text otherwise
-- @param any value l10n key or plain value
-- @return string text localized or converted text
local function getLocalizedText(value)
    if value == nil then
        return ""
    end

    if type(value) == "string" and string.sub(value, 1, 4) == "rms_" then
        return g_i18n:getText(value)
    end

    return tostring(value)
end

---Returns the colour a severity shows in, the one the dashboard telltales use
-- @param integer priority severity rank, 0 for fine up to 4 for critical
-- @return table color rgba channels
local function getSeverityColor(priority)
    if priority >= 4 then
        return RMS_Breakdowns.COLORS.CRITICAL
    elseif priority >= 1 then
        return RMS_Breakdowns.COLORS.WARNING
    end

    return HUD.COLOR.ACTIVE
end

---Returns the row colour from its status severity
-- @param table? row inspection row
-- @return table color rgba channels
local function getRowColor(row)
    if row ~= nil and row.statusKey == "rms_inspection_status_not_required" then
        return RMS_Breakdowns.COLORS.DEFAULT
    end

    return getSeverityColor(row ~= nil and STATUS_PRIORITY[row.statusKey or ""] or 0)
end

---Returns the accent colour of a row, quiet while the row is fine
-- @param table? row inspection row
-- @return table color rgba channels
local function getRowAccentColor(row)
    local priority = row ~= nil and STATUS_PRIORITY[row.statusKey or ""] or 0
    if priority == 0 then
        return RMS_Breakdowns.COLORS.DEFAULT
    end

    return getRowColor(row)
end

---Returns the bar fill a fluid level draws, the mark sitting low on the gauge
-- @param float level fluid level
-- @return float ratio fill ratio between 0 and 1
local function getGaugeRatio(level)
    local mark = math.clamp(RMS_Config.FLUIDS.LEVEL_MIN_MARK, 0.001, 0.999)
    if level >= mark then
        return GAUGE_MARK_RATIO + (1 - GAUGE_MARK_RATIO) * ((level - mark) / (1 - mark))
    end

    return GAUGE_MARK_RATIO * (level / mark)
end

---Returns the worst status severity of the whole report
-- @param table dialog dialog instance
-- @return integer priority 0 when every row is fine, up to 4
local function getWorstPriority(dialog)
    local worst = 0
    for _, rows in ipairs({dialog.technicalFluidsData, dialog.coolingAndAirData, dialog.lubricationData}) do
        for _, row in ipairs(rows or {}) do
            if row.statusKey ~= "rms_inspection_status_not_required" then
                worst = math.max(worst, STATUS_PRIORITY[row.statusKey or ""] or 0)
            end
        end
    end

    return worst
end

---Sets the status of a row, keeping the one already there when it is more severe
-- @param table? rows section rows
-- @param string? titleKey l10n key identifying the row
-- @param string? statusKey status l10n key
local function setRowValue(rows, titleKey, statusKey)
    if rows == nil or titleKey == nil or statusKey == nil then
        return
    end

    for _, row in ipairs(rows) do
        if row.titleKey == titleKey then
            local newPriority = STATUS_PRIORITY[statusKey] or 0
            local currentPriority = STATUS_PRIORITY[row.statusKey or "rms_inspection_ok"] or 0

            if newPriority >= currentPriority then
                row.statusKey = statusKey
                row.value = getLocalizedText(statusKey)
            end

            return
        end
    end
end

---Stores the fill ratio of a row gauge
-- @param table? rows section rows
-- @param string? titleKey l10n key identifying the row
-- @param float level fill ratio between 0 and 1
local function setRowLevel(rows, titleKey, level)
    if rows == nil or titleKey == nil then
        return
    end

    for _, row in ipairs(rows) do
        if row.titleKey == titleKey then
            row.level = math.clamp(tonumber(level) or 1, 0, 1)
            return
        end
    end
end

---Appends a localized line to the findings list, skipping empties and duplicates
-- @param table? lines findings lines
-- @param string? textKey l10n key of the line
local function appendAdditionalLine(lines, textKey)
    if lines == nil or textKey == nil or textKey == "" then
        return
    end

    local text = getLocalizedText(textKey)
    if text == "" then
        return
    end

    for _, existing in ipairs(lines) do
        if existing == text then
            return
        end
    end

    table.insert(lines, text)
end

---Joins the findings into a bullet list, or returns the no symptom text
-- @param table? lines findings lines
-- @return string text findings block
local function buildAdditionalText(lines)
    if lines == nil or #lines == 0 then
        return g_i18n:getText("rms_inspection_no_suspicious_symptoms")
    end

    local formattedLines = {}
    for _, line in ipairs(lines) do
        table.insert(formattedLines, "- " .. line)
    end

    return table.concat(formattedLines, "\n")
end

---Applies the inspection findings declared by the active breakdown stages
-- @param table dialog dialog instance
-- @param table additionalLines findings lines, modified in place
local function applyBreakdownInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    if vehicle == nil or vehicle.getActiveBreakdowns == nil or RMS_Breakdowns == nil then
        return
    end

    local activeBreakdowns = vehicle:getActiveBreakdowns() or {}
    local registry = RMS_Breakdowns.BreakdownRegistry or {}
    local targetMap = {
        engineOil = "rms_inspection_engine_oil",
        coolant = "rms_inspection_coolant",
        hydraulicFluid = "rms_inspection_hydraulic_fluid",
        transmissionOil = "rms_inspection_transmission_oil",
        radiator = "rms_inspection_radiator",
        airFilter = "rms_inspection_air_filter",
        lubrication = "rms_inspection_lubrication_level"
    }

    for breakdownId, breakdown in pairs(activeBreakdowns) do
        local registryEntry = registry[breakdownId]
        if registryEntry ~= nil and registryEntry.stages ~= nil then
            local stageData = registryEntry.stages[breakdown.stage]
            local findings = stageData ~= nil and stageData.inspection or nil

            if findings ~= nil then
                for _, finding in ipairs(findings) do
                    -- a finding without target and status only contributes a findings line
                    if finding.target ~= nil and finding.status ~= nil then
                        local titleKey = targetMap[finding.target]
                        local sectionKey = TARGET_TO_SECTION[finding.target]
                        if titleKey ~= nil and sectionKey ~= nil then
                            setRowValue(dialog[sectionKey], titleKey, finding.status)
                        end
                    end

                    appendAdditionalLine(additionalLines, finding.additional)
                end
            end
        end
    end
end

---Rates the radiator and air intake clogging above 0.15 into four severity steps
-- @param table dialog dialog instance
-- @param table additionalLines findings lines, modified in place
local function applyCloggingInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    if spec.isVehicleNeedBlowOut == false then
        return
    end

    local radiatorClogging = math.clamp(tonumber(spec.radiatorClogging) or 0, 0, 1)
    if radiatorClogging > 0.15 then
        local statusKey
        if radiatorClogging >= 0.85 then
            statusKey = "rms_inspection_status_critically_clogged"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage4")
        elseif radiatorClogging >= 0.60 then
            statusKey = "rms_inspection_status_heavily_clogged"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage3")
        elseif radiatorClogging >= 0.35 then
            statusKey = "rms_inspection_status_dirty"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage2")
        else
            statusKey = "rms_inspection_status_slightly_dirty"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage1")
        end

        setRowValue(dialog.coolingAndAirData, "rms_inspection_radiator", statusKey)
    end

    local airFilterClogging = math.clamp(tonumber(spec.airFilterClogging) or 0, 0, 1)
    if airFilterClogging > 0.15 then
        local statusKey
        if airFilterClogging >= 0.85 then
            statusKey = "rms_inspection_status_critically_clogged"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_air_filter_clogging_stage4")
        elseif airFilterClogging >= 0.60 then
            statusKey = "rms_inspection_status_heavily_clogged"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_air_filter_clogging_stage3")
        elseif airFilterClogging >= 0.35 then
            statusKey = "rms_inspection_status_dirty"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_air_filter_clogging_stage2")
        else
            statusKey = "rms_inspection_status_slightly_dirty"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_air_filter_clogging_stage1")
        end

        setRowValue(dialog.coolingAndAirData, "rms_inspection_air_filter", statusKey)
    end
end

---Rates the lubrication level against the configured dryness thresholds
-- @param table dialog dialog instance
-- @param table additionalLines findings lines, modified in place
local function applyLubricationInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isVehicleNeedLubricate == false then
        return
    end

    local lubricationLevel = math.clamp(tonumber(spec.lubricationLevel) or 0, 0, 1)
    local statusKey = nil

    local C = RMS_Config.FIELD_CARE

    if lubricationLevel <= C.LUBRICATION_CRITICALLY_DRY_THRESHOLD then
        statusKey = "rms_inspection_status_critically_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage4")
    elseif lubricationLevel <= C.LUBRICATION_VERY_DRY_THRESHOLD then
        statusKey = "rms_inspection_status_very_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage3")
    elseif lubricationLevel <= C.LUBRICATION_DRY_THRESHOLD then
        statusKey = "rms_inspection_status_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage2")
    elseif lubricationLevel <= C.LUBRICATION_WARNING_THRESHOLD then
        statusKey = "rms_inspection_status_slightly_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage1")
    end

    if statusKey ~= nil then
        setRowValue(dialog.lubricationData, "rms_inspection_lubrication_level", statusKey)
    end
end

---Reads the level of every fluid the machine carries
-- @param table dialog dialog instance
-- @param table additionalLines findings lines, modified in place
local function applyFluidLevelInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    local C = RMS_Config.FLUIDS

    for _, row in ipairs(FLUID_ROWS) do
        local systemData = spec.systems ~= nil and spec.systems[row.systemKey] or nil
        -- fluid read only on a system the machine has
        if systemData == nil or systemData.enabled == false then
            setRowValue(dialog.technicalFluidsData, row.titleKey, "rms_inspection_status_not_required")
        else
            local level = math.clamp(tonumber(spec[row.levelKey]) or 1, 0, 1)
            local statusKey = nil

            if level <= C.LEVEL_CRITICALLY_LOW then
                statusKey = "rms_inspection_status_critically_low"
            elseif level <= C.LEVEL_VERY_LOW then
                statusKey = "rms_inspection_status_very_low"
            elseif level <= C.LEVEL_LOW then
                statusKey = "rms_inspection_status_low"
            elseif level < C.LEVEL_MIN_MARK then
                statusKey = "rms_inspection_status_slightly_low"
            end

            setRowLevel(dialog.technicalFluidsData, row.titleKey, level)

            if statusKey ~= nil then
                setRowValue(dialog.technicalFluidsData, row.titleKey, statusKey)
                appendAdditionalLine(additionalLines, "rms_inspection_hint_fluid_level_low")
            end
        end
    end
end

---Writes the machine name, its hours and its service due date
-- @param table dialog dialog instance
local function updateIdentity(dialog)
    local vehicle = dialog.vehicle
    local hoursText = string.format("%.0f %s", vehicle:getFormattedOperatingTime(), g_i18n:getText("rms_spec_op_hours_short"))
    local remaining = vehicle:getMaintenanceInterval() - vehicle:getHoursSinceLastMaintenance()
    local serviceKey = remaining >= 0 and "rms_inspection_service_due_in" or "rms_inspection_service_overdue"
    local serviceText = string.format(g_i18n:getText(serviceKey),
        string.format("%.0f %s", math.abs(remaining), g_i18n:getText("rms_spec_op_hours_short")))

    dialog.identityElement:setText(string.format("%s  \194\183  %s  \194\183  %s", vehicle:getFullName(), hoursText, serviceText))

    local textWidth = math.max(dialog.dialogTitleElement.size[1], dialog.identityElement.size[1])
    dialog.headerTextLayout:setSize(textWidth, nil)
    dialog.headerTextLayout:invalidateLayout()
    dialog.headerLayout:invalidateLayout()
end

---Writes the go or no go the whole report comes down to
-- @param table dialog dialog instance
local function updateVerdict(dialog)
    local worst = getWorstPriority(dialog)
    local name, color

    if worst >= 4 then
        name = "stop"
    elseif worst >= 1 then
        name = "watch"
    else
        name = "ok"
    end

    color = getSeverityColor(worst)

    dialog.verdictTitle:setText(g_i18n:getText("rms_inspection_verdict_" .. name .. "_title"))
    dialog.verdictMessage:setText(g_i18n:getText("rms_inspection_verdict_" .. name .. "_message"))
    dialog.verdictBadgeText:setText(worst == 0 and "OK" or "!")
    dialog.verdictTitle:setTextColor(unpack(color))
    dialog.verdictAccent:setImageColor(nil, unpack(color))
    dialog.verdictBadge.color = {color[1], color[2], color[3], color[4]}
end

---Loads the dialog layout and stores the shared instance
function RMS_InspectionDialog.register()
    local dialog = RMS_InspectionDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_InspectionDialog.xml", "RMS_InspectionDialog", dialog)
    RMS_InspectionDialog.INSTANCE = dialog
end

---Create instance of RMS_InspectionDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_InspectionDialog
function RMS_InspectionDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_InspectionDialog_mt)
    dialog.vehicle = nil
    dialog.technicalFluidsData = {}
    dialog.coolingAndAirData = {}
    dialog.lubricationData = {}
    return dialog
end

---Opens the dialog on a vehicle
-- @param table vehicle vehicle
function RMS_InspectionDialog.show(vehicle)
    if RMS_InspectionDialog.INSTANCE == nil then RMS_InspectionDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then return end
    
    local dialog = RMS_InspectionDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog:updateScreen()
    g_gui:showDialog("RMS_InspectionDialog")
end

---Resets every section to fine, then applies the breakdown, clogging and lubrication findings
function RMS_InspectionDialog:updateScreen()
    if self.vehicle == nil then return end
    
    self.dialogTitleElement:setText(g_i18n:getText("rms_inspection_dialog_title"))

    self.technicalFluidsData = {
        {titleKey = "rms_inspection_engine_oil", title = g_i18n:getText("rms_inspection_engine_oil"), statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")},
        {titleKey = "rms_inspection_coolant", title = g_i18n:getText("rms_inspection_coolant"), statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")},
        {titleKey = "rms_inspection_hydraulic_fluid", title = g_i18n:getText("rms_inspection_hydraulic_fluid"), statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")},
        {titleKey = "rms_inspection_transmission_oil", title = g_i18n:getText("rms_inspection_transmission_oil"), statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")}
    }

    self.coolingAndAirData = {
        {titleKey = "rms_inspection_radiator", title = g_i18n:getText("rms_inspection_radiator"), statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")},
        {titleKey = "rms_inspection_air_filter", title = g_i18n:getText("rms_inspection_air_filter"), statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")}
    }

    self.lubricationData = {
        {titleKey = "rms_inspection_lubrication_level", title = g_i18n:getText("rms_inspection_lubrication_level"), statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")}
    }

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and spec.isVehicleNeedBlowOut == false then
        setRowValue(self.coolingAndAirData, "rms_inspection_radiator", "rms_inspection_status_not_required")
        setRowValue(self.coolingAndAirData, "rms_inspection_air_filter", "rms_inspection_status_not_required")
    end

    if spec ~= nil and spec.isVehicleNeedLubricate == false then
        setRowValue(self.lubricationData, "rms_inspection_lubrication_level", "rms_inspection_status_not_required")
    end

    local additionalLines = {}

    applyFluidLevelInspectionFindings(self, additionalLines)
    applyBreakdownInspectionFindings(self, additionalLines)
    applyCloggingInspectionFindings(self, additionalLines)
    applyLubricationInspectionFindings(self, additionalLines)

    self.additionalText:setText(buildAdditionalText(additionalLines))

    self.technicalFluidsList:setDataSource(self)
    self.technicalFluidsList:setDelegate(self)
    self.technicalFluidsList:reloadData()

    self.coolingAndAirList:setDataSource(self)
    self.coolingAndAirList:setDelegate(self)
    self.coolingAndAirList:reloadData()

    self.lubricationList:setDataSource(self)
    self.lubricationList:setDelegate(self)
    self.lubricationList:reloadData()

    updateIdentity(self)
    updateVerdict(self)
end

---Returns the row table backing a list element
-- @param table self dialog instance
-- @param table list list element
-- @return table? data section rows, nil for an unknown list
local function getListData(self, list)
    if list == self.technicalFluidsList then
        return self.technicalFluidsData
    elseif list == self.coolingAndAirList then
        return self.coolingAndAirData
    elseif list == self.lubricationList then
        return self.lubricationData
    end

    return nil
end

---Returns the row count of the requested section
-- @param table list list element
-- @param integer section section index
-- @return integer count number of rows
function RMS_InspectionDialog:getNumberOfItemsInSection(list, section)
    local data = getListData(self, list)
    return data ~= nil and #data or 0
end

---Fits a row status pill to its rendered text and gives the remaining width to the title
-- @param table cell row cell
-- @param table titleElement row title element
-- @param table valuePill status pill element
-- @param table valueElement row value element
-- @param string titleText localized row title
-- @param string valueText localized row value
local function updateRowTextLayout(cell, titleElement, valuePill, valueElement, titleText, valueText)
    if cell.rmsInspectionTextLayout == nil then
        cell.rmsInspectionTextLayout = {
            titleX = titleElement.position[1],
            titleMaxWidth = titleElement.size[1],
            pillMaxWidth = valuePill.size[1],
            pillRight = valuePill.position[1] + valuePill.size[1],
            valuePadding = valueElement.position[1] - valuePill.position[1],
            titlePillGap = valuePill.position[1] - titleElement.position[1] - titleElement.size[1]
        }
    end

    local layout = cell.rmsInspectionTextLayout
    local pillX = layout.pillRight - layout.pillMaxWidth
    valuePill:setPosition(pillX, nil)
    valuePill:setSize(layout.pillMaxWidth, nil)
    valueElement:setPosition(pillX + layout.valuePadding, nil)
    valueElement:setSize(layout.pillMaxWidth - layout.valuePadding * 2, nil)
    titleElement:setSize(layout.titleMaxWidth, nil)

    titleElement:setText(titleText)
    valueElement:setText(valueText)

    local pillWidth = math.min(layout.pillMaxWidth, valueElement:getTextWidth(true) + layout.valuePadding * 2)
    pillX = layout.pillRight - pillWidth
    valuePill:setPosition(pillX, nil)
    valuePill:setSize(pillWidth, nil)
    valueElement:setPosition(pillX + layout.valuePadding, nil)
    valueElement:setSize(pillWidth - layout.valuePadding * 2, nil)
    titleElement:setSize(math.max(pillX - layout.titlePillGap - layout.titleX, 0), nil)
end

---Fills one inspection row, colouring the value by status severity
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_InspectionDialog:populateCellForItemInSection(list, section, index, cell)
    local data = getListData(self, list)
    local row = data ~= nil and data[index] or nil
    if row == nil then
        return
    end

    local titleElement = cell:getAttribute("inspectionTitle")
    local valueElement = cell:getAttribute("inspectionValue")
    local valuePill = cell:getAttribute("inspectionValuePill")

    updateRowTextLayout(cell, titleElement, valuePill, valueElement, row.title or "", row.value or "")
    titleElement:setTextColor(unpack(TEXT_COLOR))
    valueElement:setTextColor(unpack(getRowColor(row)))

    local accent = cell:getAttribute("inspectionAccent")
    if accent ~= nil then
        accent:setImageColor(nil, unpack(getRowAccentColor(row)))
    end

    local gaugeTrack = cell:getAttribute("inspectionGaugeTrack")
    local gaugeFill = cell:getAttribute("inspectionGaugeFill")
    local gaugeMark = cell:getAttribute("inspectionGaugeMark")
    if gaugeTrack == nil or gaugeFill == nil or gaugeMark == nil then
        return
    end

    -- gauge shown only on a row carrying a level
    local level = tonumber(row.level)
    gaugeTrack:setVisible(level ~= nil)
    gaugeMark:setVisible(level ~= nil)

    if level == nil then
        gaugeFill:setVisible(false)
        return
    end

    local ratio = getGaugeRatio(level)
    local trackWidth, trackHeight = gaugeTrack.size[1], gaugeTrack.size[2]
    local fillWidth = GuiUtils.alignValueToScreenPixels(trackWidth * ratio, true)
    gaugeFill:setSize(fillWidth, trackHeight)
    gaugeFill:setImageColor(nil, unpack(getRowColor(row)))
    gaugeFill:setVisible(ratio > 0)
end

---
function RMS_InspectionDialog:onOpen()
    RMS_InspectionDialog:superClass().onOpen(self)
end

---Clears the inspected vehicle
function RMS_InspectionDialog:onClose()
    self.vehicle = nil
    RMS_InspectionDialog:superClass().onClose(self)
end

---Closes the dialog
function RMS_InspectionDialog:onClickBack()
    self:close()
end
