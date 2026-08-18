-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Confirmation dialog listing the cost breakdown of returning a leased vehicle
RMS_SellItemDialog = {}
RMS_SellItemDialog.INSTANCE = nil

local RMS_SellItemDialog_mt = Class(RMS_SellItemDialog, MessageDialog)
local modDirectory = g_currentModDirectory

---Returns the text with exactly one trailing colon
-- @param string? text label text
-- @return string text label ending with a colon
local function ensureTrailingColon(text)
    local normalized = tostring(text or ""):gsub("%s*:%s*$", "")
    return normalized .. ":"
end

---Formats an amount as money with an explicit sign, and no sign at zero
-- @param any value amount
-- @return string text formatted amount
local function formatSignedMoney(value)
    local amount = tonumber(value) or 0
    local sign = amount > 0 and "+" or amount < 0 and "-" or ""
    return string.format("%s%s", sign, g_i18n:formatMoney(math.abs(amount), 0, true, false))
end

---Colours a text element green for a credit, red for a debit, dimmed at zero
-- @param table? element text element
-- @param any value amount
local function applyMoneyColor(element, value)
    if element == nil then
        return
    end

    local amount = tonumber(value) or 0
    if amount > 0 then
        element:setTextColor(0.455, 0.565, 0.115, 1)
    elseif amount < 0 then
        element:setTextColor(0.88, 0.12, 0, 1)
    else
        element:setTextColor(1, 1, 1, 0.5)
    end
end

---Loads the dialog layout and stores the shared instance
function RMS_SellItemDialog.register()
    local dialog = RMS_SellItemDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_SellItemDialog.xml", "RMS_SellItemDialog", dialog)
    RMS_SellItemDialog.INSTANCE = dialog
end

---Create instance of RMS_SellItemDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_SellItemDialog
function RMS_SellItemDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_SellItemDialog_mt)
    dialog.vehicle = nil
    dialog.callback = nil
    dialog.callbackTarget = nil
    dialog.callbackArgs = nil
    dialog.costRows = {}
    return dialog
end

---Opens the dialog on a vehicle, falling back to the store item of its config file
-- @param table vehicle vehicle
-- @param table? storeItem store item
-- @param function? callback called with the player answer
-- @param table? target callback target
-- @param table? args extra callback arguments
function RMS_SellItemDialog.show(vehicle, storeItem, callback, target, args)
    if RMS_SellItemDialog.INSTANCE == nil then
        RMS_SellItemDialog.register()
    end

    if vehicle == nil then
        return
    end

    local dialog = RMS_SellItemDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.storeItem = storeItem or g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    dialog.callback = callback
    dialog.callbackTarget = target
    dialog.callbackArgs = args

    dialog:updateScreen()
    g_gui:showDialog("RMS_SellItemDialog")
end

---Fills the vehicle image, name and the return cost rows
function RMS_SellItemDialog:updateScreen()
    if self.vehicle == nil then
        return
    end

    local storeItem = self.storeItem
    local imageFilename = "dataS/menu/blank.png"
    local name = "unknown"

    if storeItem ~= nil then
        imageFilename = storeItem.imageFilename
        name = storeItem.name
    end

    if self.vehicle.getFullName ~= nil then
        name = self.vehicle:getFullName()
    elseif self.vehicle.getName ~= nil then
        name = self.vehicle:getName()
    end

    if self.vehicle.getImageFilename ~= nil then
        local vehicleImageFilename = self.vehicle:getImageFilename()
        if vehicleImageFilename ~= nil and vehicleImageFilename ~= "" then
            imageFilename = vehicleImageFilename
        end
    end

    if self.dialogTitleElement ~= nil then
        self.dialogTitleElement:setText(g_i18n:getText("button_return"))
    end

    if self.vehicleImageElement ~= nil then
        self.vehicleImageElement:setImageFilename(imageFilename)
    end

    if self.vehicleNameElement ~= nil then
        self.vehicleNameElement:setText(name)
    end


    local returnBreakdown = RMS_Leasing.getReturnBreakdown(self.vehicle)
    self.returnBreakdown = returnBreakdown

    self.costRows = {
    }

    for _, row in ipairs(returnBreakdown.rows or {}) do
        table.insert(self.costRows, {
            label = ensureTrailingColon(g_i18n:getText(row.label)),
            key = row.key,
            value = row.value
        })
    end

    if self.totalAmountElement ~= nil then
        self.totalAmountElement:setText(formatSignedMoney(returnBreakdown.display.total))
        applyMoneyColor(self.totalAmountElement, returnBreakdown.display.total)
    end

    if self.costList ~= nil then
        self.costList:setDataSource(self)
        self.costList:setDelegate(self)
        self.costList:reloadData()
    end
end

---Returns the number of cost rows
-- @param table list list element
-- @param integer section section index
-- @return integer count number of rows
function RMS_SellItemDialog:getNumberOfItemsInSection(list, section)
    if list == self.costList then
        return #self.costRows
    end

    return 0
end

---Fills one cost row with its label and its coloured amount
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_SellItemDialog:populateCellForItemInSection(list, section, index, cell)
    if list ~= self.costList then
        return
    end

    local row = self.costRows[index]
    if row == nil then
        return
    end

    local labelElement = cell:getAttribute("costLabel")
    local valueElement = cell:getAttribute("costValue")

    if labelElement ~= nil then
        labelElement:setText(row.label or "")
    end

    if valueElement ~= nil then
        valueElement:setText(formatSignedMoney(row.value))
        applyMoneyColor(valueElement, row.value)
    end
end

---Fires the stored callback with the player answer
-- @param boolean value true when the return is confirmed
function RMS_SellItemDialog:sendCallback(value)
    if self.callback ~= nil then
        if self.callbackArgs ~= nil then
            self.callback(self.callbackTarget, value, unpack(self.callbackArgs))
        else
            self.callback(self.callbackTarget, value)
        end
    end
end

---Confirms the return and closes the dialog
function RMS_SellItemDialog:onClickYes()
    self:sendCallback(true)
    self:close()
end

---Declines the return and closes the dialog
function RMS_SellItemDialog:onClickNo()
    self:sendCallback(false)
    self:close()
end

---
function RMS_SellItemDialog:onOpen()
    RMS_SellItemDialog:superClass().onOpen(self)
end

---Clears the dialog state
function RMS_SellItemDialog:onClose()
    self.vehicle = nil
    self.storeItem = nil
    self.returnBreakdown = nil
    self.callback = nil
    self.callbackTarget = nil
    self.callbackArgs = nil
    RMS_SellItemDialog:superClass().onClose(self)
end
