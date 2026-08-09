ADS_DrivetrainEvent = {}
local ADS_DrivetrainEvent_mt = Class(ADS_DrivetrainEvent, Event)

InitEventClass(ADS_DrivetrainEvent, "ADS_DrivetrainEvent")

function ADS_DrivetrainEvent.emptyNew()
    return Event.new(ADS_DrivetrainEvent_mt)
end

function ADS_DrivetrainEvent.new(vehicle)
    local self = ADS_DrivetrainEvent.emptyNew()
    local state = ADS_Drivetrain.getState(vehicle)

    self.vehicle = vehicle
    self.driveMode = math.clamp(math.floor(tonumber(state.driveMode) or ADS_Drivetrain.MODE.FOUR_WD), 0, 2)
    self.diffLockRequested = state.diffLockRequested == true
    self.parkBrake = state.parkBrake == true
    return self
end

function ADS_DrivetrainEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUIntN(streamId, self.driveMode, 2)
    streamWriteBool(streamId, self.diffLockRequested)
    streamWriteBool(streamId, self.parkBrake)
end

function ADS_DrivetrainEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.driveMode = streamReadUIntN(streamId, 2)
    self.diffLockRequested = streamReadBool(streamId)
    self.parkBrake = streamReadBool(streamId)
    self:run(connection)
end

function ADS_DrivetrainEvent:run(connection)
    if self.vehicle == nil or not self.vehicle:getIsSynchronized() then
        return
    end

    if connection:getIsServer() then
        return
    end

    if self.vehicle:getOwnerConnection() ~= connection then
        return
    end

    ADS_Drivetrain.setDrivetrainState(self.vehicle, self.driveMode, self.diffLockRequested, self.parkBrake, true)
end

function ADS_DrivetrainEvent.sendEvent(vehicle, noEventSend)
    if noEventSend or g_client == nil then
        return
    end

    g_client:getServerConnection():sendEvent(ADS_DrivetrainEvent.new(vehicle))
end
