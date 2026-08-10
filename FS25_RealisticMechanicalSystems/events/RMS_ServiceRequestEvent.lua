-- RMS_ServiceRequestEvent
-- Client-to-server event. Sends a service request (inspection/maintenance/repair/overhaul)
-- to the server for authoritative execution.

RMS_ServiceRequestEvent = {}
local RMS_ServiceRequestEvent_mt = Class(RMS_ServiceRequestEvent, Event)

InitEventClass(RMS_ServiceRequestEvent, "RMS_ServiceRequestEvent")


function RMS_ServiceRequestEvent.emptyNew()
    return Event.new(RMS_ServiceRequestEvent_mt)
end


function RMS_ServiceRequestEvent.new(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree, price)
    local self = RMS_ServiceRequestEvent.emptyNew()
    self.vehicle = vehicle
    self.serviceType = serviceType
    self.workshopType = workshopType
    self.optionOne = optionOne
    self.optionTwo = optionTwo
    self.optionThree = optionThree
    self.price = price
    return self
end


function RMS_ServiceRequestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.serviceType or "")
    streamWriteString(streamId, self.workshopType or "")
    streamWriteString(streamId, self.optionOne or "")
    streamWriteString(streamId, self.optionTwo or "")
    streamWriteBool(streamId, self.optionThree or false)
    streamWriteFloat32(streamId, self.price or 0)
end


function RMS_ServiceRequestEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.serviceType = streamReadString(streamId)
    self.workshopType = streamReadString(streamId)
    self.optionOne = streamReadString(streamId)
    self.optionTwo = streamReadString(streamId)
    self.optionThree = streamReadBool(streamId)
    self.price = streamReadFloat32(streamId)

    if self.optionOne == "" then self.optionOne = nil end
    if self.optionTwo == "" then self.optionTwo = nil end
    if self.workshopType == "" then self.workshopType = nil end

    self:run(connection)
end


-- Server-side execution: validate vehicle, run initService, debit money.
-- Price is recalculated server-side to prevent client tampering.
function RMS_ServiceRequestEvent:run(connection)
    if not connection:getIsServer() then
        if self.vehicle ~= nil and self.vehicle:getIsSynchronized() and self.vehicle.spec_RealisticMechanicalSystems ~= nil then
            local userId = g_currentMission.userManager:getUserIdByConnection(connection)
            local farm = g_farmManager:getFarmByUserId(userId)
            if farm == nil or farm.farmId ~= self.vehicle:getOwnerFarmId() then
                return
            end

            local spec = self.vehicle.spec_RealisticMechanicalSystems
            if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY then
                return
            end

            local validTypes = {
                [RealisticMechanicalSystems.STATUS.INSPECTION] = true,
                [RealisticMechanicalSystems.STATUS.MAINTENANCE] = true,
                [RealisticMechanicalSystems.STATUS.REPAIR] = true,
                [RealisticMechanicalSystems.STATUS.OVERHAUL] = true
            }
            if not validTypes[self.serviceType] then
                return
            end

            if RMS_Main ~= nil
                and RMS_Main.isWorkshopTypeOpen ~= nil
                and not RMS_Main:isWorkshopTypeOpen(self.workshopType) then
                return
            end

            local serverPrice = self.vehicle:getServicePrice(self.serviceType, self.optionOne, self.optionTwo, self.optionThree, self.workshopType) or 0

            self.vehicle:initService(self.serviceType, self.workshopType, self.optionOne, self.optionTwo, self.optionThree)

            if serverPrice > 0 then
                g_currentMission:addMoney(-1 * serverPrice, self.vehicle:getOwnerFarmId(), MoneyType.VEHICLE_RUNNING_COSTS, true, true)
            end

            RMS_VehicleChangeStatusEvent.send(self.vehicle)
        end
    end
end


-- Client convenience: send service request to the server.
function RMS_ServiceRequestEvent.send(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree, price)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_ServiceRequestEvent.new(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree, price))
    end
end
