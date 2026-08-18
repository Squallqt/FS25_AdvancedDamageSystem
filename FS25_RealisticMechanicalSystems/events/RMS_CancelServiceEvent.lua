-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client-to-server request cancelling an in-progress service on the server
RMS_CancelServiceEvent = {}
local RMS_CancelServiceEvent_mt = Class(RMS_CancelServiceEvent, Event)

InitEventClass(RMS_CancelServiceEvent, "RMS_CancelServiceEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_CancelServiceEvent.emptyNew()
    return Event.new(RMS_CancelServiceEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @return table self instance of class event
function RMS_CancelServiceEvent.new(vehicle)
    local self = RMS_CancelServiceEvent.emptyNew()
    self.vehicle = vehicle
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_CancelServiceEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_CancelServiceEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end


---Cancels the service on the server if the requesting farm owns the vehicle and a service is running
-- @param Connection connection connection
function RMS_CancelServiceEvent:run(connection)
    if not connection:getIsServer() then
        if self.vehicle ~= nil and self.vehicle:getIsSynchronized() and self.vehicle.spec_RealisticMechanicalSystems ~= nil then
            local userId = g_currentMission.userManager:getUserIdByConnection(connection)
            local farm = g_farmManager:getFarmByUserId(userId)
            if farm == nil or farm.farmId ~= self.vehicle:getOwnerFarmId() then
                return
            end

            local spec = self.vehicle.spec_RealisticMechanicalSystems
            if spec.currentState == RealisticMechanicalSystems.STATUS.READY then
                return
            end

            self.vehicle:cancelService()
        end
    end
end


---Send the cancel request from a client to the server
-- @param table vehicle vehicle
function RMS_CancelServiceEvent.send(vehicle)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_CancelServiceEvent.new(vehicle))
    end
end
