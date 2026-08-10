-- RMS_CancelServiceEvent
-- Client-to-server event. Cancels an in-progress service on the server.

RMS_CancelServiceEvent = {}
local RMS_CancelServiceEvent_mt = Class(RMS_CancelServiceEvent, Event)

InitEventClass(RMS_CancelServiceEvent, "RMS_CancelServiceEvent")


function RMS_CancelServiceEvent.emptyNew()
    return Event.new(RMS_CancelServiceEvent_mt)
end


function RMS_CancelServiceEvent.new(vehicle)
    local self = RMS_CancelServiceEvent.emptyNew()
    self.vehicle = vehicle
    return self
end


function RMS_CancelServiceEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end


function RMS_CancelServiceEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end


-- Server-side execution: validate vehicle, run cancelService.
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


-- Client convenience: send cancel request to the server.
function RMS_CancelServiceEvent.send(vehicle)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_CancelServiceEvent.new(vehicle))
    end
end
