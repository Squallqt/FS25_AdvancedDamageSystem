RMS_DebugSnapshotRequestEvent = {}
local RMS_DebugSnapshotRequestEvent_mt = Class(RMS_DebugSnapshotRequestEvent, Event)

InitEventClass(RMS_DebugSnapshotRequestEvent, "RMS_DebugSnapshotRequestEvent")

function RMS_DebugSnapshotRequestEvent.emptyNew()
    return Event.new(RMS_DebugSnapshotRequestEvent_mt)
end

function RMS_DebugSnapshotRequestEvent.new(vehicle)
    local self = RMS_DebugSnapshotRequestEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

function RMS_DebugSnapshotRequestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

function RMS_DebugSnapshotRequestEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

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

function RMS_DebugSnapshotRequestEvent.send(vehicle)
    if g_client ~= nil and vehicle ~= nil then
        g_client:getServerConnection():sendEvent(RMS_DebugSnapshotRequestEvent.new(vehicle))
    end
end

