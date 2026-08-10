-- RMS_VehicleChangeStatusEvent
-- Server-to-client broadcast. Notifies clients of RMS state changes
-- (service completion, cancellation, status transition).
-- Carries an optional HUD notification string; bulk state data is
-- synchronised via the update-stream dirty-flag pipeline.

RMS_VehicleChangeStatusEvent = {}
local RMS_VehicleChangeStatusEvent_mt = Class(RMS_VehicleChangeStatusEvent, Event)
MessageType.RMS_VEHICLE_CHANGE_STATUS = nextMessageTypeId()

InitEventClass(RMS_VehicleChangeStatusEvent, "RMS_VehicleChangeStatusEvent")


function RMS_VehicleChangeStatusEvent.emptyNew()
    return Event.new(RMS_VehicleChangeStatusEvent_mt)
end


function RMS_VehicleChangeStatusEvent.new(vehicle, notificationText)
    local self = RMS_VehicleChangeStatusEvent.emptyNew()
    self.vehicle = vehicle
    self.notificationText = notificationText or ""
    return self
end


function RMS_VehicleChangeStatusEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.notificationText or "")
end


function RMS_VehicleChangeStatusEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.notificationText = streamReadString(streamId)
    self:run(connection)
end


function RMS_VehicleChangeStatusEvent:run(connection)
    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        self.vehicle:recalculateAndApplyEffects()
        self.vehicle:recalculateAndApplyIndicators()

        -- Client-side: show HUD notification + play completion sound
        if connection:getIsServer() and self.notificationText ~= nil and self.notificationText ~= "" then
            if g_currentMission:getFarmId() == self.vehicle.ownerFarmId and g_currentMission ~= nil and g_currentMission.hud ~= nil then
                g_currentMission.hud:addSideNotification({1, 1, 1, 1}, self.notificationText)
            end
            if g_currentMission:getFarmId() == self.vehicle.ownerFarmId then
                RMS_SoundManager.playSample(RMS_Main.samples.maintenanceCompleted2D)
            end
        end

        g_messageCenter:publish(MessageType.RMS_VEHICLE_CHANGE_STATUS, self.vehicle)
    end

    -- Server relay: re-broadcast if received from a client (with ownership check)
    if not connection:getIsServer() then
        if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
            local userId = g_currentMission.userManager:getUserIdByConnection(connection)
            local farm = g_farmManager:getFarmByUserId(userId)
            if farm ~= nil and farm.farmId == self.vehicle:getOwnerFarmId() then
                g_server:broadcastEvent(RMS_VehicleChangeStatusEvent.new(self.vehicle, self.notificationText), nil, connection, self.vehicle)
            end
        end
    end
end


-- Server convenience: broadcast status change to all clients.
function RMS_VehicleChangeStatusEvent.send(vehicle, notificationText)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_VehicleChangeStatusEvent.new(vehicle, notificationText or ""), nil, nil, vehicle)
    end
end
