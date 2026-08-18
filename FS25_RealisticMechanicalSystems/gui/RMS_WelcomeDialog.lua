-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Welcome dialog offering to keep or disable the tutorial tips
RMS_WelcomeDialog = {}
RMS_WelcomeDialog.INSTANCE = nil

local RMS_WelcomeDialog_mt = Class(RMS_WelcomeDialog, MessageDialog)
local modDirectory = g_currentModDirectory

---Loads the dialog layout and stores the shared instance
function RMS_WelcomeDialog.register()
    local dialog = RMS_WelcomeDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_WelcomeDialog.xml", "RMS_WelcomeDialog", dialog)
    RMS_WelcomeDialog.INSTANCE = dialog
end

---Create instance of RMS_WelcomeDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_WelcomeDialog
function RMS_WelcomeDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_WelcomeDialog_mt)
    dialog.callback = nil
    dialog.callbackTarget = nil
    dialog.disableTutorial = false
    return dialog
end

---Opens the dialog on a message text
-- @param string? text message shown in the dialog
-- @param function? callback called on close with the tutorial choice
-- @param table? callbackTarget callback target
function RMS_WelcomeDialog.show(text, callback, callbackTarget)
    if RMS_WelcomeDialog.INSTANCE == nil then
        RMS_WelcomeDialog.register()
    end

    local dialog = RMS_WelcomeDialog.INSTANCE
    dialog.callback = callback
    dialog.callbackTarget = callbackTarget
    dialog.disableTutorial = false

    dialog.dialogTitleElement:setText(g_i18n:getText("rms_tutorial_welcome_dialog_title"))
    dialog.messageTextElement:setText(text or "")

    g_gui:showDialog("RMS_WelcomeDialog")
end

---Closes the dialog asking for the tips to be disabled
function RMS_WelcomeDialog:onClickDisableTips()
    self.disableTutorial = true
    self:close()
end

---Closes the dialog keeping the tips enabled
function RMS_WelcomeDialog:onClickEnableTips()
    self.disableTutorial = false
    self:close()
end

---Fires the callback with the tutorial choice, then clears the dialog state
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
