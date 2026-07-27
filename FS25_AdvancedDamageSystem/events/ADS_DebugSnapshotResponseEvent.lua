ADS_DebugSnapshotResponseEvent = {}
local ADS_DebugSnapshotResponseEvent_mt = Class(ADS_DebugSnapshotResponseEvent, Event)

InitEventClass(ADS_DebugSnapshotResponseEvent, "ADS_DebugSnapshotResponseEvent")

function ADS_DebugSnapshotResponseEvent.emptyNew()
    return Event.new(ADS_DebugSnapshotResponseEvent_mt)
end

function ADS_DebugSnapshotResponseEvent.new(vehicle)
    local self = ADS_DebugSnapshotResponseEvent.emptyNew()
    self.vehicle = vehicle
    self.snapshot = ADS_DebugSnapshot.build(vehicle)
    return self
end

function ADS_DebugSnapshotResponseEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    ADS_DebugSnapshot.write(streamId, self.snapshot)
end

function ADS_DebugSnapshotResponseEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.snapshot = ADS_DebugSnapshot.read(streamId)

    self:run(connection)
end

function ADS_DebugSnapshotResponseEvent:run(connection)
    if connection == nil or not connection:getIsServer() or not ADS_Config.DEBUG then
        return
    end
    if self.vehicle == nil or self.vehicle.spec_AdvancedDamageSystem == nil then
        return
    end

    ADS_DebugSnapshot.apply(self.vehicle, self.snapshot)
end

