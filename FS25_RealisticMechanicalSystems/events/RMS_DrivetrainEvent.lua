-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client-to-server request applying the drive mode, differential lock and park brake of a vehicle
RMS_DrivetrainEvent = {}
local RMS_DrivetrainEvent_mt = Class(RMS_DrivetrainEvent, Event)

InitEventClass(RMS_DrivetrainEvent, "RMS_DrivetrainEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_DrivetrainEvent.emptyNew()
    return Event.new(RMS_DrivetrainEvent_mt)
end

---Create new instance of event from the current drivetrain state of the vehicle
-- @param table vehicle vehicle
-- @return table self instance of class event
function RMS_DrivetrainEvent.new(vehicle)
    local self = RMS_DrivetrainEvent.emptyNew()
    local state = RMS_Drivetrain.getState(vehicle)

    self.vehicle = vehicle
    self.driveMode = math.clamp(math.floor(tonumber(state.driveMode) or RMS_Drivetrain.MODE.FOUR_WD), 0, 2)
    self.diffLockRequested = state.diffLockRequested == true
    self.parkBrake = state.parkBrake == true
    return self
end

---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DrivetrainEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUIntN(streamId, self.driveMode, 2)
    streamWriteBool(streamId, self.diffLockRequested)
    streamWriteBool(streamId, self.parkBrake)
end

---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DrivetrainEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.driveMode = streamReadUIntN(streamId, 2)
    self.diffLockRequested = streamReadBool(streamId)
    self.parkBrake = streamReadBool(streamId)
    self:run(connection)
end

---Applies the received drivetrain state on the server if the sending connection owns the vehicle
-- @param Connection connection connection
function RMS_DrivetrainEvent:run(connection)
    if self.vehicle == nil or not self.vehicle:getIsSynchronized() then
        return
    end

    if connection:getIsServer() then
        return
    end

    if self.vehicle:getOwnerConnection() ~= connection then
        return
    end

    RMS_Drivetrain.setDrivetrainState(self.vehicle, self.driveMode, self.diffLockRequested, self.parkBrake, true)
end

---Send the drivetrain state from a client to the server
-- @param table vehicle vehicle
-- @param boolean noEventSend no event send
function RMS_DrivetrainEvent.sendEvent(vehicle, noEventSend)
    if noEventSend or g_client == nil then
        return
    end

    g_client:getServerConnection():sendEvent(RMS_DrivetrainEvent.new(vehicle))
end
