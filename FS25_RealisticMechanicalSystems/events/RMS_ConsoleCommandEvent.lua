-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client-to-server request running a whitelisted console command on the server
RMS_ConsoleCommandEvent = {}
local RMS_ConsoleCommandEvent_mt = Class(RMS_ConsoleCommandEvent, Event)

InitEventClass(RMS_ConsoleCommandEvent, "RMS_ConsoleCommandEvent")

-- console command names accepted from a client
RMS_ConsoleCommandEvent.ALLOWED_COMMANDS = {
    setService = true,
    setCondition = true,
    setSystemCondition = true,
    setSystemStress = true,
    setSystemStressMultiplier = true,
    resetVehicle = true,
    addBreakdown = true,
    removeBreakdown = true,
    changeBreakdownStage = true,
    startMaintance = true,
    finishMaintance = true,
    setDirtAmount = true,
    setFuelLevel = true,
    setHorsePower = true,
    setOperatingTime = true,
    setPlowMaxForce = true,
    resetFactorStats = true,
    reinitializeVehicle = true,
    printSpecVar = true,
    setSpecVar = true,
    setConfigVar = true,
    setExcluded = true,
    debug = true
}

---Create instance of Event class
-- @return table self instance of class event
function RMS_ConsoleCommandEvent.emptyNew()
    return Event.new(RMS_ConsoleCommandEvent_mt)
end


---Create new instance of event
-- @param string commandName console command name
-- @param string? argsOne first command argument
-- @param string? argsTwo second command argument
-- @param table? vehicle vehicle the command is applied to
-- @return table self instance of class event
function RMS_ConsoleCommandEvent.new(commandName, argsOne, argsTwo, vehicle)
    local self = RMS_ConsoleCommandEvent.emptyNew()
    self.commandName = commandName
    self.argsOne = argsOne
    self.argsTwo = argsTwo
    self.vehicle = vehicle
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_ConsoleCommandEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.commandName or "")
    streamWriteString(streamId, self.argsOne or "")
    streamWriteString(streamId, self.argsTwo or "")
    local hasVehicle = self.vehicle ~= nil
    streamWriteBool(streamId, hasVehicle)
    if hasVehicle then
        NetworkUtil.writeNodeObject(streamId, self.vehicle)
    end
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_ConsoleCommandEvent:readStream(streamId, connection)
    self.commandName = streamReadString(streamId)
    self.argsOne = streamReadString(streamId)
    self.argsTwo = streamReadString(streamId)
    local hasVehicle = streamReadBool(streamId)
    if hasVehicle then
        self.vehicle = NetworkUtil.readNodeObject(streamId)
    end

    -- empty strings map back to missing arguments
    if self.argsOne == "" then self.argsOne = nil end
    if self.argsTwo == "" then self.argsTwo = nil end

    self:run(connection)
end


---Runs the requested console command on the server against the carried vehicle
-- @param Connection connection connection
function RMS_ConsoleCommandEvent:run(connection)
    if connection:getIsServer() then
        return
    end

    -- only a master user may run a command
    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local user = g_currentMission.userManager:getUserByUserId(userId)
    if user == nil or not user:getIsMasterUser() then
        return
    end

    if not RMS_ConsoleCommandEvent.ALLOWED_COMMANDS[self.commandName] then
        return
    end

    local func = RealisticMechanicalSystems.ConsoleCommands[self.commandName]
    if func == nil then
        return
    end

    -- the carried vehicle replaces the console target for the duration of the call
    RealisticMechanicalSystems.ConsoleCommands._overrideVehicle = self.vehicle
    func(RealisticMechanicalSystems.ConsoleCommands, self.argsOne, self.argsTwo)
    RealisticMechanicalSystems.ConsoleCommands._overrideVehicle = nil

    -- replicate every sync group of the modified vehicle
    if self.vehicle ~= nil and self.vehicle.spec_RealisticMechanicalSystems ~= nil then
        local spec = self.vehicle.spec_RealisticMechanicalSystems
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.STATE)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.TELEMETRY)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.THERMAL)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.WEAR)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
        RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS)
    end

    if self.commandName == "setConfigVar" then
        g_server:broadcastEvent(RMS_SettingsSyncEvent.new())
    end
end


---Send the console command from a client to the server
-- @param string commandName console command name
-- @param string? argsOne first command argument
-- @param string? argsTwo second command argument
-- @param table? vehicle vehicle the command is applied to
function RMS_ConsoleCommandEvent.sendToServer(commandName, argsOne, argsTwo, vehicle)
    if g_client ~= nil then
        if not g_currentMission.isMasterUser then
            print("RMS: Admin access required.")
            return
        end
        g_client:getServerConnection():sendEvent(RMS_ConsoleCommandEvent.new(commandName, argsOne, argsTwo, vehicle))
    end
end
