-- Replicates authoritative drivetrain state and forwards client commands to the server.

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
    self.hasControl = state.hasControl == true
    self.hasCenterDiff = state.hasCenterDiff == true
    self.externallyManaged = state.externallyManaged == true
    self.parkExternallyManaged = state.parkExternallyManaged == true
    self.driveMode = math.clamp(math.floor(tonumber(state.driveMode) or ADS_Drivetrain.MODE.FOUR_WD), 0, 2)
    self.autoEngaged = state.autoEngaged == true
    self.diffLockRequested = state.diffLockRequested == true
    self.diffLockEngaged = state.diffLockEngaged == true
    self.parkBrake = state.parkBrake == true
    self.windupActive = state.windupActive == true
    self.windupStress = math.clamp(tonumber(state.windupStress) or 0, 0, 1)
    return self
end

function ADS_DrivetrainEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.hasControl)
    streamWriteBool(streamId, self.hasCenterDiff)
    streamWriteBool(streamId, self.externallyManaged)
    streamWriteBool(streamId, self.parkExternallyManaged)
    streamWriteUIntN(streamId, self.driveMode, 2)
    streamWriteBool(streamId, self.autoEngaged)
    streamWriteBool(streamId, self.diffLockRequested)
    streamWriteBool(streamId, self.diffLockEngaged)
    streamWriteBool(streamId, self.parkBrake)
    streamWriteBool(streamId, self.windupActive)
    streamWriteUInt8(streamId, math.floor(self.windupStress * 255 + 0.5))
end

function ADS_DrivetrainEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.hasControl = streamReadBool(streamId)
    self.hasCenterDiff = streamReadBool(streamId)
    self.externallyManaged = streamReadBool(streamId)
    self.parkExternallyManaged = streamReadBool(streamId)
    self.driveMode = streamReadUIntN(streamId, 2)
    self.autoEngaged = streamReadBool(streamId)
    self.diffLockRequested = streamReadBool(streamId)
    self.diffLockEngaged = streamReadBool(streamId)
    self.parkBrake = streamReadBool(streamId)
    self.windupActive = streamReadBool(streamId)
    self.windupStress = streamReadUInt8(streamId) / 255
    self:run(connection)
end

function ADS_DrivetrainEvent:run(connection)
    if self.vehicle == nil or not self.vehicle:getIsSynchronized() then
        return
    end

    if not connection:getIsServer() then
        if self.vehicle:getOwnerConnection() ~= connection then
            return
        end

        ADS_Drivetrain.setDrivetrainState(self.vehicle, self.driveMode, self.diffLockRequested, self.parkBrake, true)
        ADS_DrivetrainEvent.sendState(self.vehicle)
    else
        local state = ADS_Drivetrain.getState(self.vehicle)
        state.hasControl = self.hasControl
        state.hasCenterDiff = self.hasCenterDiff
        state.externallyManaged = self.externallyManaged
        state.parkExternallyManaged = self.parkExternallyManaged
        state.driveMode = self.driveMode
        state.autoEngaged = self.autoEngaged
        state.diffLockRequested = self.diffLockRequested
        state.diffLockEngaged = self.diffLockEngaged
        state.parkBrake = self.parkBrake
        state.windupActive = self.windupActive
        state.windupStress = self.windupStress
    end
end

function ADS_DrivetrainEvent.sendState(vehicle, connection)
    local event = ADS_DrivetrainEvent.new(vehicle)

    if connection ~= nil then
        connection:sendEvent(event)
    else
        g_server:broadcastEvent(event, nil, nil, vehicle)
    end
end

--- Sends a drivetrain command or authoritative server state.
function ADS_DrivetrainEvent.sendEvent(vehicle, noEventSend)
    if noEventSend then return end

    if g_server ~= nil then
        ADS_DrivetrainEvent.sendState(vehicle)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(ADS_DrivetrainEvent.new(vehicle))
    end
end
