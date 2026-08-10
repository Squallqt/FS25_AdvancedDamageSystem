-- RMS_WorkshopChangeStatusEvent
-- Server-to-client broadcast. Synchronises workshop open/close state
-- (driven by time-of-day) to all clients.

RMS_WorkshopChangeStatusEvent = {}
local RMS_WorkshopChangeStatusEvent_mt = Class(RMS_WorkshopChangeStatusEvent, Event)
MessageType.RMS_WORKSHOP_CHANGE_STATUS = nextMessageTypeId()

InitEventClass(RMS_WorkshopChangeStatusEvent, "RMS_WorkshopChangeStatusEvent")


function RMS_WorkshopChangeStatusEvent.emptyNew()
    return Event.new(RMS_WorkshopChangeStatusEvent_mt)
end


function RMS_WorkshopChangeStatusEvent.new(isOpen)
    local self = RMS_WorkshopChangeStatusEvent.emptyNew()
    self.isOpen = isOpen
    return self
end


function RMS_WorkshopChangeStatusEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isOpen)
end


function RMS_WorkshopChangeStatusEvent:readStream(streamId, connection)
    self.isOpen = streamReadBool(streamId)
    self:run(connection)
end


function RMS_WorkshopChangeStatusEvent:run(connection)
    if not connection:getIsServer() then
        return
    end

    RMS_Main.isWorkshopOpen = self.isOpen
    g_messageCenter:publish(MessageType.RMS_WORKSHOP_CHANGE_STATUS, self.isOpen)
end


-- Server convenience: broadcast workshop state to all clients.
function RMS_WorkshopChangeStatusEvent.send(isOpen)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_WorkshopChangeStatusEvent.new(isOpen))
    end
end
