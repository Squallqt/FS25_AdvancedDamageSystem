RMS_DebugSnapshotResponseEvent = {}
local RMS_DebugSnapshotResponseEvent_mt = Class(RMS_DebugSnapshotResponseEvent, Event)

InitEventClass(RMS_DebugSnapshotResponseEvent, "RMS_DebugSnapshotResponseEvent")

function RMS_DebugSnapshotResponseEvent.emptyNew()
    return Event.new(RMS_DebugSnapshotResponseEvent_mt)
end

function RMS_DebugSnapshotResponseEvent.new(vehicle)
    local self = RMS_DebugSnapshotResponseEvent.emptyNew()
    self.vehicle = vehicle
    self.snapshot = RMS_DebugSnapshot.build(vehicle)
    return self
end

function RMS_DebugSnapshotResponseEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    RMS_DebugSnapshot.write(streamId, self.snapshot)
end

function RMS_DebugSnapshotResponseEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.snapshot = RMS_DebugSnapshot.read(streamId)

    self:run(connection)
end

function RMS_DebugSnapshotResponseEvent:run(connection)
    if connection == nil or not connection:getIsServer() or not RMS_Config.DEBUG then
        return
    end
    if self.vehicle == nil or self.vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end

    RMS_DebugSnapshot.apply(self.vehicle, self.snapshot)
end

