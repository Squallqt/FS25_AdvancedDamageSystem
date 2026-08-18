-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Server-to-client answer carrying the debug snapshot of a vehicle
RMS_DebugSnapshotResponseEvent = {}
local RMS_DebugSnapshotResponseEvent_mt = Class(RMS_DebugSnapshotResponseEvent, Event)

InitEventClass(RMS_DebugSnapshotResponseEvent, "RMS_DebugSnapshotResponseEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_DebugSnapshotResponseEvent.emptyNew()
    return Event.new(RMS_DebugSnapshotResponseEvent_mt)
end

---Create new instance of event carrying a snapshot built from the current vehicle state
-- @param table vehicle vehicle
-- @return table self instance of class event
function RMS_DebugSnapshotResponseEvent.new(vehicle)
    local self = RMS_DebugSnapshotResponseEvent.emptyNew()
    self.vehicle = vehicle
    self.snapshot = RMS_DebugSnapshot.build(vehicle)
    return self
end

---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DebugSnapshotResponseEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    RMS_DebugSnapshot.write(streamId, self.snapshot)
end

---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DebugSnapshotResponseEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.snapshot = RMS_DebugSnapshot.read(streamId)

    self:run(connection)
end

---Stores the received snapshot on the client vehicle
-- @param Connection connection connection
function RMS_DebugSnapshotResponseEvent:run(connection)
    if connection == nil or not connection:getIsServer() or not RMS_Config.DEBUG then
        return
    end
    if self.vehicle == nil or self.vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end

    RMS_DebugSnapshot.apply(self.vehicle, self.snapshot)
end

