RMS_WelcomeDialog = {}
RMS_WelcomeDialog.INSTANCE = nil

local RMS_WelcomeDialog_mt = Class(RMS_WelcomeDialog, MessageDialog)
local modDirectory = g_currentModDirectory

function RMS_WelcomeDialog.register()
    local dialog = RMS_WelcomeDialog.new()
    g_gui:loadGui(modDirectory .. "gui/ADS_WelcomeDialog.xml", "RMS_WelcomeDialog", dialog)
    RMS_WelcomeDialog.INSTANCE = dialog
end

function RMS_WelcomeDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_WelcomeDialog_mt)
    dialog.callback = nil
    dialog.callbackTarget = nil
    dialog.disableTutorial = false
    return dialog
end

function RMS_WelcomeDialog.show(text, callback, callbackTarget)
    if RMS_WelcomeDialog.INSTANCE == nil then
        RMS_WelcomeDialog.register()
    end

    local dialog = RMS_WelcomeDialog.INSTANCE
    dialog.callback = callback
    dialog.callbackTarget = callbackTarget
    dialog.disableTutorial = false

    dialog.dialogTitleElement:setText(g_i18n:getText("ads_tutorial_welcome_dialog_title"))
    dialog.messageTextElement:setText(text or "")

    g_gui:showDialog("RMS_WelcomeDialog")
end

function RMS_WelcomeDialog:onClickDisableTips()
    self.disableTutorial = true
    self:close()
end

function RMS_WelcomeDialog:onClickEnableTips()
    self.disableTutorial = false
    self:close()
end

function RMS_WelcomeDialog:onClose()
    RMS_WelcomeDialog:superClass().onClose(self)

    if self.callback ~= nil then
        if self.callbackTarget ~= nil then
            self.callback(self.callbackTarget, self.disableTutorial)
        else
            self.callback(self.disableTutorial)
        end
    end

    self.callback = nil
    self.callbackTarget = nil
    self.disableTutorial = false
end
