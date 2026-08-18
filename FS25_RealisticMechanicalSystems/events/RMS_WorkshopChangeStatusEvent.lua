-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Server-to-client broadcast of the workshop open state
RMS_WorkshopChangeStatusEvent = {}
local RMS_WorkshopChangeStatusEvent_mt = Class(RMS_WorkshopChangeStatusEvent, Event)
MessageType.RMS_WORKSHOP_CHANGE_STATUS = nextMessageTypeId()

InitEventClass(RMS_WorkshopChangeStatusEvent, "RMS_WorkshopChangeStatusEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_WorkshopChangeStatusEvent.emptyNew()
    return Event.new(RMS_WorkshopChangeStatusEvent_mt)
end


---Create new instance of event
-- @param boolean isOpen true if the workshop is open
-- @return table self instance of class event
function RMS_WorkshopChangeStatusEvent.new(isOpen)
    local self = RMS_WorkshopChangeStatusEvent.emptyNew()
    self.isOpen = isOpen
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_WorkshopChangeStatusEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isOpen)
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_WorkshopChangeStatusEvent:readStream(streamId, connection)
    self.isOpen = streamReadBool(streamId)
    self:run(connection)
end


---Stores the received workshop state on the client and publishes it on the message center
-- @param Connection connection connection
function RMS_WorkshopChangeStatusEvent:run(connection)
    if not connection:getIsServer() then
        return
    end

    RMS_Main.isWorkshopOpen = self.isOpen
    g_messageCenter:publish(MessageType.RMS_WORKSHOP_CHANGE_STATUS, self.isOpen)
end


---Broadcast the workshop state from the server to all clients
-- @param boolean isOpen true if the workshop is open
function RMS_WorkshopChangeStatusEvent.send(isOpen)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_WorkshopChangeStatusEvent.new(isOpen))
    end
end
