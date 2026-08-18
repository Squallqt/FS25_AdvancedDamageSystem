-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client-to-server event marking a player as running a field inspection on a vehicle
RMS_FieldInspectionEvent = {}
local RMS_FieldInspectionEvent_mt = Class(RMS_FieldInspectionEvent, Event)

InitEventClass(RMS_FieldInspectionEvent, "RMS_FieldInspectionEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_FieldInspectionEvent.emptyNew()
    return Event.new(RMS_FieldInspectionEvent_mt)
end

---Create new instance of event
-- @param table vehicle vehicle
-- @param boolean isActive true if the inspection is starting
-- @return table self instance of class event
function RMS_FieldInspectionEvent.new(vehicle, isActive)
    local self = RMS_FieldInspectionEvent.emptyNew()
    self.vehicle = vehicle
    self.isActive = isActive == true
    return self
end

---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_FieldInspectionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isActive)
end

---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_FieldInspectionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isActive = streamReadBool(streamId)
    self:run(connection)
end

---Applies the inspection state for the player behind the sending connection
-- @param Connection connection connection
function RMS_FieldInspectionEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    local player = g_currentMission.connectionsToPlayer[connection]
    if player ~= nil then
        vehicle:setFieldInspectionPlayerActive(player, self.isActive)
    end
end

---Applies the inspection state directly on the server, sends it to the server from a client
-- @param table vehicle vehicle
-- @param boolean isActive true if the inspection is starting
function RMS_FieldInspectionEvent.send(vehicle, isActive)
    if g_server ~= nil then
        vehicle:setFieldInspectionPlayerActive(g_localPlayer, isActive)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_FieldInspectionEvent.new(vehicle, isActive))
    end
end
