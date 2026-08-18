-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Signals a status change of a vehicle and carries an optional notification text
RMS_VehicleChangeStatusEvent = {}
local RMS_VehicleChangeStatusEvent_mt = Class(RMS_VehicleChangeStatusEvent, Event)
MessageType.RMS_VEHICLE_CHANGE_STATUS = nextMessageTypeId()

InitEventClass(RMS_VehicleChangeStatusEvent, "RMS_VehicleChangeStatusEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_VehicleChangeStatusEvent.emptyNew()
    return Event.new(RMS_VehicleChangeStatusEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param string? notificationText text shown as a side notification
-- @return table self instance of class event
function RMS_VehicleChangeStatusEvent.new(vehicle, notificationText)
    local self = RMS_VehicleChangeStatusEvent.emptyNew()
    self.vehicle = vehicle
    self.notificationText = notificationText or ""
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleChangeStatusEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.notificationText or "")
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleChangeStatusEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.notificationText = streamReadString(streamId)
    self:run(connection)
end


---Reapplies effects and indicators, notifies the owning farm, and relays the event on the server
-- @param Connection connection connection
function RMS_VehicleChangeStatusEvent:run(connection)
    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        self.vehicle:recalculateAndApplyEffects()
        self.vehicle:recalculateAndApplyIndicators()

        -- notification and sound for the owning farm only
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

    -- relay to the other clients, only for the farm owning the vehicle
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


---Broadcast the status change from the server to the clients of the vehicle
-- @param table vehicle vehicle
-- @param string? notificationText text shown as a side notification
function RMS_VehicleChangeStatusEvent.send(vehicle, notificationText)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_VehicleChangeStatusEvent.new(vehicle, notificationText or ""), nil, nil, vehicle)
    end
end
