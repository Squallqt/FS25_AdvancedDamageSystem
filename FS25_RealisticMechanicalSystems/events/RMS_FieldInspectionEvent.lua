RMS_FieldInspectionEvent = {}
local RMS_FieldInspectionEvent_mt = Class(RMS_FieldInspectionEvent, Event)

InitEventClass(RMS_FieldInspectionEvent, "RMS_FieldInspectionEvent")

function RMS_FieldInspectionEvent.emptyNew()
    return Event.new(RMS_FieldInspectionEvent_mt)
end

function RMS_FieldInspectionEvent.new(vehicle, isActive)
    local self = RMS_FieldInspectionEvent.emptyNew()
    self.vehicle = vehicle
    self.isActive = isActive == true
    return self
end

function RMS_FieldInspectionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isActive)
end

function RMS_FieldInspectionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isActive = streamReadBool(streamId)
    self:run(connection)
end

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

function RMS_FieldInspectionEvent.send(vehicle, isActive)
    if g_server ~= nil then
        vehicle:setFieldInspectionPlayerActive(g_localPlayer, isActive)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_FieldInspectionEvent.new(vehicle, isActive))
    end
end
