RMS_SellItemDialog = {}
RMS_SellItemDialog.INSTANCE = nil

local RMS_SellItemDialog_mt = Class(RMS_SellItemDialog, MessageDialog)
local modDirectory = g_currentModDirectory

local function ensureTrailingColon(text)
    local normalized = tostring(text or ""):gsub("%s*:%s*$", "")
    return normalized .. ":"
end

local function formatSignedMoney(value)
    local amount = tonumber(value) or 0
    local sign = amount > 0 and "+" or amount < 0 and "-" or ""
    return string.format("%s%s", sign, g_i18n:formatMoney(math.abs(amount), 0, true, false))
end

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

function RMS_SellItemDialog.register()
    local dialog = RMS_SellItemDialog.new()
    g_gui:loadGui(modDirectory .. "gui/ADS_SellItemDialog.xml", "RMS_SellItemDialog", dialog)
    RMS_SellItemDialog.INSTANCE = dialog
end

function RMS_SellItemDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_SellItemDialog_mt)
    dialog.vehicle = nil
    dialog.callback = nil
    dialog.callbackTarget = nil
    dialog.callbackArgs = nil
    dialog.costRows = {}
    return dialog
end

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

function RMS_SellItemDialog:getNumberOfItemsInSection(list, section)
    if list == self.costList then
        return #self.costRows
    end

    return 0
end

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

function RMS_SellItemDialog:sendCallback(value)
    if self.callback ~= nil then
        if self.callbackArgs ~= nil then
            self.callback(self.callbackTarget, value, unpack(self.callbackArgs))
        else
            self.callback(self.callbackTarget, value)
        end
    end
end

function RMS_SellItemDialog:onClickYes()
    self:sendCallback(true)
    self:close()
end

function RMS_SellItemDialog:onClickNo()
    self:sendCallback(false)
    self:close()
end

function RMS_SellItemDialog:onOpen()
    RMS_SellItemDialog:superClass().onOpen(self)
end

function RMS_SellItemDialog:onClose()
    self.vehicle = nil
    self.storeItem = nil
    self.returnBreakdown = nil
    self.callback = nil
    self.callbackTarget = nil
    self.callbackArgs = nil
    RMS_SellItemDialog:superClass().onClose(self)
end
