ADS_ConsoleCommandEvent = {}
local ADS_ConsoleCommandEvent_mt = Class(ADS_ConsoleCommandEvent, Event)

InitEventClass(ADS_ConsoleCommandEvent, "ADS_ConsoleCommandEvent")

ADS_ConsoleCommandEvent.ALLOWED_COMMANDS = {
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

function ADS_ConsoleCommandEvent.emptyNew()
    return Event.new(ADS_ConsoleCommandEvent_mt)
end


function ADS_ConsoleCommandEvent.new(commandName, argsOne, argsTwo, vehicle)
    local self = ADS_ConsoleCommandEvent.emptyNew()
    self.commandName = commandName
    self.argsOne = argsOne
    self.argsTwo = argsTwo
    self.vehicle = vehicle
    return self
end


function ADS_ConsoleCommandEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.commandName or "")
    streamWriteString(streamId, self.argsOne or "")
    streamWriteString(streamId, self.argsTwo or "")
    local hasVehicle = self.vehicle ~= nil
    streamWriteBool(streamId, hasVehicle)
    if hasVehicle then
        NetworkUtil.writeNodeObject(streamId, self.vehicle)
    end
end


function ADS_ConsoleCommandEvent:readStream(streamId, connection)
    self.commandName = streamReadString(streamId)
    self.argsOne = streamReadString(streamId)
    self.argsTwo = streamReadString(streamId)
    local hasVehicle = streamReadBool(streamId)
    if hasVehicle then
        self.vehicle = NetworkUtil.readNodeObject(streamId)
    end

    if self.argsOne == "" then self.argsOne = nil end
    if self.argsTwo == "" then self.argsTwo = nil end

    self:run(connection)
end


function ADS_ConsoleCommandEvent:run(connection)
    if connection:getIsServer() then
        return
    end

    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local user = g_currentMission.userManager:getUserByUserId(userId)
    if user == nil or not user:getIsMasterUser() then
        return
    end

    if not ADS_ConsoleCommandEvent.ALLOWED_COMMANDS[self.commandName] then
        return
    end

    local func = AdvancedDamageSystem.ConsoleCommands[self.commandName]
    if func == nil then
        return
    end

    AdvancedDamageSystem.ConsoleCommands._overrideVehicle = self.vehicle
    func(AdvancedDamageSystem.ConsoleCommands, self.argsOne, self.argsTwo)
    AdvancedDamageSystem.ConsoleCommands._overrideVehicle = nil

    if self.vehicle ~= nil and self.vehicle.spec_AdvancedDamageSystem ~= nil then
        local spec = self.vehicle.spec_AdvancedDamageSystem
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.STATE)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.SERVICE_CONTEXT)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.TELEMETRY)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.THERMAL)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.ELECTRICAL)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.FIELDCARE)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.WEAR)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.BREAKDOWNS)
        AdvancedDamageSystem.raiseADSDirty(self.vehicle, AdvancedDamageSystem.SYNC_GROUP.SERVICE_PROGRESS)
    end

    if self.commandName == "setConfigVar" then
        g_server:broadcastEvent(ADS_SettingsSyncEvent.new())
    end
end


function ADS_ConsoleCommandEvent.sendToServer(commandName, argsOne, argsTwo, vehicle)
    if g_client ~= nil then
        if not g_currentMission.isMasterUser then
            print("ADS: Admin access required.")
            return
        end
        g_client:getServerConnection():sendEvent(ADS_ConsoleCommandEvent.new(commandName, argsOne, argsTwo, vehicle))
    end
end
