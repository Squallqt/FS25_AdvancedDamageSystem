-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Synchronises the per player tutorial state between server and client
RMS_TutorialStateEvent = {}
local RMS_TutorialStateEvent_mt = Class(RMS_TutorialStateEvent, Event)

InitEventClass(RMS_TutorialStateEvent, "RMS_TutorialStateEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_TutorialStateEvent.emptyNew()
    return Event.new(RMS_TutorialStateEvent_mt)
end

---Create new instance of event from a normalized copy of the tutorial state
-- @param table? state tutorial state
-- @return table self instance of class event
function RMS_TutorialStateEvent.new(state)
    local self = RMS_TutorialStateEvent.emptyNew()
    self.state = RMS_Config.createTutorialState(
        state ~= nil and state.tutorialMode,
        state ~= nil and state.welcomeMessageSeen,
        state ~= nil and state.messages
    )
    return self
end

---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_TutorialStateEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.state.tutorialMode)
    streamWriteBool(streamId, self.state.welcomeMessageSeen)
    for _, messageId in ipairs(RMS_Config.TUTORIAL_MESSAGE_IDS) do
        streamWriteBool(streamId, self.state.messages[messageId])
    end
end

---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_TutorialStateEvent:readStream(streamId, connection)
    local messages = {}
    local tutorialMode = streamReadBool(streamId)
    local welcomeMessageSeen = streamReadBool(streamId)
    for _, messageId in ipairs(RMS_Config.TUTORIAL_MESSAGE_IDS) do
        messages[messageId] = streamReadBool(streamId)
    end
    self.state = RMS_Config.createTutorialState(tutorialMode, welcomeMessageSeen, messages)
    self:run(connection)
end

---Applies the state locally on a client, stores it against the sending player on the server
-- @param Connection connection connection
function RMS_TutorialStateEvent:run(connection)
    if connection:getIsServer() then
        RMS_Config.applyTutorialState(self.state)
        return
    end

    RMS_Config.setTutorialPlayerState(RMS_Utils.getUniqueUserIdByConnection(connection), self.state)
end

---Send the stored tutorial state of a player to its newly connected client
-- @param Connection connection connection
function RMS_TutorialStateEvent.sendToClient(connection)
    if g_server == nil then return end

    local state = RMS_Config.getTutorialPlayerState(RMS_Utils.getUniqueUserIdByConnection(connection))
    if state ~= nil then
        connection:sendEvent(RMS_TutorialStateEvent.new(state))
    end
end

---Send the tutorial state from a client to the server
-- @param table state tutorial state
function RMS_TutorialStateEvent.sendToServer(state)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_TutorialStateEvent.new(state))
    end
end
