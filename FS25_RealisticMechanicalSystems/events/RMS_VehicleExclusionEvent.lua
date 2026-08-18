-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Server-to-client broadcast of the user controlled exclusion flag of a vehicle
RMS_VehicleExclusionEvent = {}
local RMS_VehicleExclusionEvent_mt = Class(RMS_VehicleExclusionEvent, Event)

InitEventClass(RMS_VehicleExclusionEvent, "RMS_VehicleExclusionEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_VehicleExclusionEvent.emptyNew()
    return Event.new(RMS_VehicleExclusionEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param boolean isExcludedByUser true if the user excluded the vehicle
-- @return table self instance of class event
function RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser)
    local self = RMS_VehicleExclusionEvent.emptyNew()
    self.vehicle = vehicle
    self.isExcludedByUser = isExcludedByUser == true
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleExclusionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isExcludedByUser)
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleExclusionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isExcludedByUser = streamReadBool(streamId)
    self:run(connection)
end


---Applies the received exclusion flag on the client vehicle
-- @param Connection connection connection
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


---Broadcast the exclusion flag from the server to the clients of the vehicle
-- @param table vehicle vehicle
-- @param boolean isExcludedByUser true if the user excluded the vehicle
function RMS_VehicleExclusionEvent.sendToClients(vehicle, isExcludedByUser)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser), nil, nil, vehicle)
    end
end
