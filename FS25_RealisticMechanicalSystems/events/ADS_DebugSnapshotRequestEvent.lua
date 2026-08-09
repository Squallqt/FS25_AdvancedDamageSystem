ADS_DebugSnapshotRequestEvent = {}
local ADS_DebugSnapshotRequestEvent_mt = Class(ADS_DebugSnapshotRequestEvent, Event)

InitEventClass(ADS_DebugSnapshotRequestEvent, "ADS_DebugSnapshotRequestEvent")

function ADS_DebugSnapshotRequestEvent.emptyNew()
    return Event.new(ADS_DebugSnapshotRequestEvent_mt)
end

function ADS_DebugSnapshotRequestEvent.new(vehicle)
    local self = ADS_DebugSnapshotRequestEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

function ADS_DebugSnapshotRequestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

function ADS_DebugSnapshotRequestEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

function ADS_DebugSnapshotRequestEvent:run(connection)
    if connection == nil or connection:getIsServer() or not ADS_Config.DEBUG then
        return
    end

    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local user = g_currentMission.userManager:getUserByUserId(userId)
    if user == nil or not user:getIsMasterUser() then
        return
    end

    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_AdvancedDamageSystem == nil or vehicle.spec_AdvancedDamageSystem.isExcludedVehicle then
        return
    end

    connection:sendEvent(ADS_DebugSnapshotResponseEvent.new(vehicle))
end

function ADS_DebugSnapshotRequestEvent.send(vehicle)
    if g_client ~= nil and vehicle ~= nil then
        g_client:getServerConnection():sendEvent(ADS_DebugSnapshotRequestEvent.new(vehicle))
    end
end

