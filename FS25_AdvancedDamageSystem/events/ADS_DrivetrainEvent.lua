-- ADS_DrivetrainEvent
-- Replicates a drivetrain command (drive mode + differential lock request) for one
-- vehicle. Client input -> server (farm ownership validated) -> broadcast to all.
-- The resulting physical state (autoEngaged, diffLockEngaged, windup stress) is
-- replicated separately through the adsDirtyFlag_drivetrain update-stream group.

ADS_DrivetrainEvent = {}
local ADS_DrivetrainEvent_mt = Class(ADS_DrivetrainEvent, Event)

InitEventClass(ADS_DrivetrainEvent, "ADS_DrivetrainEvent")

function ADS_DrivetrainEvent.emptyNew()
    return Event.new(ADS_DrivetrainEvent_mt)
end

function ADS_DrivetrainEvent.new(vehicle, driveMode, diffLockRequested, parkBrake)
    local self = ADS_DrivetrainEvent.emptyNew()
    self.vehicle = vehicle
    self.driveMode = math.clamp(math.floor(tonumber(driveMode) or ADS_Drivetrain.MODE.FOUR_WD), 0, 2)
    self.diffLockRequested = diffLockRequested == true
    self.parkBrake = parkBrake == true
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

    if not connection:getIsServer() then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local farm = g_farmManager:getFarmByUserId(userId)
        if farm == nil or farm.farmId ~= self.vehicle:getOwnerFarmId() then
            return
        end

        ADS_Drivetrain.setDrivetrainState(self.vehicle, self.driveMode, self.diffLockRequested, self.parkBrake, true)
        g_server:broadcastEvent(ADS_DrivetrainEvent.new(self.vehicle, self.driveMode, self.diffLockRequested, self.parkBrake), nil, connection, self.vehicle)
    else
        ADS_Drivetrain.setDrivetrainState(self.vehicle, self.driveMode, self.diffLockRequested, self.parkBrake, true)
    end
end

--- sendEvent helper used by the ADS_Drivetrain setter.
function ADS_DrivetrainEvent.sendEvent(vehicle, driveMode, diffLockRequested, parkBrake, noEventSend)
    if noEventSend then return end

    if g_server ~= nil then
        g_server:broadcastEvent(ADS_DrivetrainEvent.new(vehicle, driveMode, diffLockRequested, parkBrake), nil, nil, vehicle)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(ADS_DrivetrainEvent.new(vehicle, driveMode, diffLockRequested, parkBrake))
    end
end
