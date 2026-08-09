ADS_FieldInspectionEvent = {}
local ADS_FieldInspectionEvent_mt = Class(ADS_FieldInspectionEvent, Event)

InitEventClass(ADS_FieldInspectionEvent, "ADS_FieldInspectionEvent")

function ADS_FieldInspectionEvent.emptyNew()
    return Event.new(ADS_FieldInspectionEvent_mt)
end

function ADS_FieldInspectionEvent.new(vehicle, isActive)
    local self = ADS_FieldInspectionEvent.emptyNew()
    self.vehicle = vehicle
    self.isActive = isActive == true
    return self
end

function ADS_FieldInspectionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isActive)
end

function ADS_FieldInspectionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isActive = streamReadBool(streamId)
    self:run(connection)
end

function ADS_FieldInspectionEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    local player = g_currentMission.connectionsToPlayer[connection]
    if player ~= nil then
        vehicle:setFieldInspectionPlayerActive(player, self.isActive)
    end
end

function ADS_FieldInspectionEvent.send(vehicle, isActive)
    if g_server ~= nil then
        vehicle:setFieldInspectionPlayerActive(g_localPlayer, isActive)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(ADS_FieldInspectionEvent.new(vehicle, isActive))
    end
end
