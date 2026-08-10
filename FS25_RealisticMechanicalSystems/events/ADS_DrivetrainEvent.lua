RMS_DrivetrainEvent = {}
local RMS_DrivetrainEvent_mt = Class(RMS_DrivetrainEvent, Event)

InitEventClass(RMS_DrivetrainEvent, "RMS_DrivetrainEvent")

function RMS_DrivetrainEvent.emptyNew()
    return Event.new(RMS_DrivetrainEvent_mt)
end

function RMS_DrivetrainEvent.new(vehicle)
    local self = RMS_DrivetrainEvent.emptyNew()
    local state = RMS_Drivetrain.getState(vehicle)

    self.vehicle = vehicle
    self.driveMode = math.clamp(math.floor(tonumber(state.driveMode) or RMS_Drivetrain.MODE.FOUR_WD), 0, 2)
    self.diffLockRequested = state.diffLockRequested == true
    self.parkBrake = state.parkBrake == true
    return self
end

function RMS_DrivetrainEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUIntN(streamId, self.driveMode, 2)
    streamWriteBool(streamId, self.diffLockRequested)
    streamWriteBool(streamId, self.parkBrake)
end

function RMS_DrivetrainEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.driveMode = streamReadUIntN(streamId, 2)
    self.diffLockRequested = streamReadBool(streamId)
    self.parkBrake = streamReadBool(streamId)
    self:run(connection)
end

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

function RMS_DrivetrainEvent.sendEvent(vehicle, noEventSend)
    if noEventSend or g_client == nil then
        return
    end

    g_client:getServerConnection():sendEvent(RMS_DrivetrainEvent.new(vehicle))
end
