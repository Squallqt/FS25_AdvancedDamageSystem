-- RMS_VehicleExclusionEvent
-- Server-to-client event for synchronising the user-controlled RMS exclusion flag.

RMS_VehicleExclusionEvent = {}
local RMS_VehicleExclusionEvent_mt = Class(RMS_VehicleExclusionEvent, Event)

InitEventClass(RMS_VehicleExclusionEvent, "RMS_VehicleExclusionEvent")


function RMS_VehicleExclusionEvent.emptyNew()
    return Event.new(RMS_VehicleExclusionEvent_mt)
end


function RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser)
    local self = RMS_VehicleExclusionEvent.emptyNew()
    self.vehicle = vehicle
    self.isExcludedByUser = isExcludedByUser == true
    return self
end


function RMS_VehicleExclusionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isExcludedByUser)
end


function RMS_VehicleExclusionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isExcludedByUser = streamReadBool(streamId)
    self:run(connection)
end


function RMS_VehicleExclusionEvent:run(connection)
    if not connection:getIsServer() then
        return
    end

    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() or vehicle.setRMSUserExcluded == nil then
        return
    end

    vehicle:setRMSUserExcluded(self.isExcludedByUser, true)
end


function RMS_VehicleExclusionEvent.sendToClients(vehicle, isExcludedByUser)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser), nil, nil, vehicle)
    end
end
