ADS_TutorialStateEvent = {}
local ADS_TutorialStateEvent_mt = Class(ADS_TutorialStateEvent, Event)

InitEventClass(ADS_TutorialStateEvent, "ADS_TutorialStateEvent")

function ADS_TutorialStateEvent.emptyNew()
    return Event.new(ADS_TutorialStateEvent_mt)
end

function ADS_TutorialStateEvent.new(state)
    local self = ADS_TutorialStateEvent.emptyNew()
    self.state = ADS_Config.createTutorialState(
        state ~= nil and state.tutorialMode,
        state ~= nil and state.welcomeVersionSeen,
        state ~= nil and state.messages
    )
    return self
end

function ADS_TutorialStateEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.state.tutorialMode)
    streamWriteString(streamId, self.state.welcomeVersionSeen)
    for _, messageId in ipairs(ADS_Config.TUTORIAL_MESSAGE_IDS) do
        streamWriteBool(streamId, self.state.messages[messageId])
    end
end

function ADS_TutorialStateEvent:readStream(streamId, connection)
    local messages = {}
    local tutorialMode = streamReadBool(streamId)
    local welcomeVersionSeen = streamReadString(streamId)
    for _, messageId in ipairs(ADS_Config.TUTORIAL_MESSAGE_IDS) do
        messages[messageId] = streamReadBool(streamId)
    end
    self.state = ADS_Config.createTutorialState(tutorialMode, welcomeVersionSeen, messages)
    self:run(connection)
end

local function getUniqueUserId(connection)
    local mission = g_currentMission
    if mission == nil or mission.userManager == nil or connection == nil then return nil end

    local userId = mission.userManager:getUserIdByConnection(connection)
    if userId == nil then return nil end
    return mission.userManager:getUniqueUserIdByUserId(userId)
end

function ADS_TutorialStateEvent:run(connection)
    if connection:getIsServer() then
        ADS_Config.applyTutorialState(self.state)
        return
    end

    ADS_Config.setTutorialPlayerState(getUniqueUserId(connection), self.state)
end

--- Pushed by the server to a newly connected client (see FSBaseMission.sendInitialClientState in ADS_Main.lua).
function ADS_TutorialStateEvent.sendToClient(connection)
    if g_server == nil then return end

    local state = ADS_Config.getTutorialPlayerState(getUniqueUserId(connection))
    if state ~= nil then
        connection:sendEvent(ADS_TutorialStateEvent.new(state))
    end
end

function ADS_TutorialStateEvent.sendToServer(state)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(ADS_TutorialStateEvent.new(state))
    end
end
