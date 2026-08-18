-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client-to-server request asking for a debug snapshot of a vehicle
RMS_DebugSnapshotRequestEvent = {}
local RMS_DebugSnapshotRequestEvent_mt = Class(RMS_DebugSnapshotRequestEvent, Event)

InitEventClass(RMS_DebugSnapshotRequestEvent, "RMS_DebugSnapshotRequestEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_DebugSnapshotRequestEvent.emptyNew()
    return Event.new(RMS_DebugSnapshotRequestEvent_mt)
end

---Create new instance of event
-- @param table vehicle vehicle
-- @return table self instance of class event
function RMS_DebugSnapshotRequestEvent.new(vehicle)
    local self = RMS_DebugSnapshotRequestEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DebugSnapshotRequestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DebugSnapshotRequestEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

---Answers the request with a snapshot of the vehicle sent back to the requesting connection
-- @param Connection connection connection
function RMS_DebugSnapshotRequestEvent:run(connection)
    if connection == nil or connection:getIsServer() or not RMS_Config.DEBUG then
        return
    end

    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local user = g_currentMission.userManager:getUserByUserId(userId)
    if user == nil or not user:getIsMasterUser() then
        return
    end

    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        return
    end

    connection:sendEvent(RMS_DebugSnapshotResponseEvent.new(vehicle))
end

---Send the snapshot request from a client to the server
-- @param table vehicle vehicle
function RMS_DebugSnapshotRequestEvent.send(vehicle)
    if g_client ~= nil and vehicle ~= nil then
        g_client:getServerConnection():sendEvent(RMS_DebugSnapshotRequestEvent.new(vehicle))
    end
end

