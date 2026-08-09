ADS_HandToolSyncEvent = {}
local ADS_HandToolSyncEvent_mt = Class(ADS_HandToolSyncEvent, Event)

InitEventClass(ADS_HandToolSyncEvent, "ADS_HandToolSyncEvent")


local function getHandToolSpec(tool)
    if tool == nil then
        return nil
    end

    if g_currentModName ~= nil then
        local spec = tool["spec_" .. g_currentModName .. ".adsHandTools"]
        if spec ~= nil then
            return spec
        end
    end

    for key, value in pairs(tool) do
        if type(key) == "string"
            and string.sub(key, 1, 5) == "spec_"
            and string.sub(key, -13) == ".adsHandTools" then
            return value
        end
    end

    return nil
end


function ADS_HandToolSyncEvent.emptyNew()
    return Event.new(ADS_HandToolSyncEvent_mt)
end


function ADS_HandToolSyncEvent.new(tool, state, targetVehicle, targetDistance)
    local self = ADS_HandToolSyncEvent.emptyNew()
    self.tool = tool
    self.state = state or ""
    self.targetVehicle = targetVehicle
    self.targetDistance = targetDistance or 0
    return self
end


function ADS_HandToolSyncEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.tool)
    streamWriteString(streamId, self.state)
    NetworkUtil.writeNodeObject(streamId, self.targetVehicle)
    streamWriteFloat32(streamId, self.targetDistance)
end


function ADS_HandToolSyncEvent:readStream(streamId, connection)
    self.tool = NetworkUtil.readNodeObject(streamId)
    self.state = streamReadString(streamId)
    self.targetVehicle = NetworkUtil.readNodeObject(streamId)
    self.targetDistance = streamReadFloat32(streamId)
    self:run(connection)
end


function ADS_HandToolSyncEvent:run(connection)
    local tool = self.tool
    if tool == nil or not tool:getIsSynchronized() then
        return
    end

    local spec = getHandToolSpec(tool)
    if spec == nil then
        return
    end

    if not connection:getIsServer() then
        local player = g_currentMission ~= nil and g_currentMission.connectionsToPlayer ~= nil and g_currentMission.connectionsToPlayer[connection] or nil
        if player == nil or tool.getCarryingPlayer == nil or tool:getCarryingPlayer() ~= player then
            return
        end

        if spec.toolKind == "airBlower" then
            if tool:applyAirBlowerNetworkState(self.state, self.targetVehicle, self.targetDistance) then
                g_server:broadcastEvent(ADS_HandToolSyncEvent.new(tool, self.state, self.targetVehicle, self.targetDistance), nil, connection, tool)
            end
        elseif spec.toolKind == "greaseGun"
            and self.state == "use"
            and tool:tryUseGreaseGunServer(self.targetVehicle, connection) then
            ADS_SoundManager.playSample(spec.samples.greaseGun)
            g_server:broadcastEvent(ADS_HandToolSyncEvent.new(tool, "greaseUsed", self.targetVehicle, 0), nil, nil, tool)
        end

        return
    end

    if spec.toolKind == "airBlower" then
        tool:applyAirBlowerNetworkState(self.state, self.targetVehicle, self.targetDistance)
    elseif spec.toolKind == "greaseGun" and self.state == "greaseUsed" then
        ADS_SoundManager.playSample(spec.samples.greaseGun)
    end
end


function ADS_HandToolSyncEvent.send(tool, state, targetVehicle, targetDistance)
    if g_server ~= nil then
        local spec = getHandToolSpec(tool)
        if spec.toolKind == "airBlower" then
            if tool:applyAirBlowerNetworkState(state, targetVehicle, targetDistance) then
                g_server:broadcastEvent(ADS_HandToolSyncEvent.new(tool, state, targetVehicle, targetDistance), nil, nil, tool)
            end
        elseif spec.toolKind == "greaseGun"
            and state == "use"
            and tool:tryUseGreaseGunServer(targetVehicle) then
            ADS_SoundManager.playSample(spec.samples.greaseGun)
            g_server:broadcastEvent(ADS_HandToolSyncEvent.new(tool, "greaseUsed", targetVehicle, 0), nil, nil, tool)
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(ADS_HandToolSyncEvent.new(tool, state, targetVehicle, targetDistance))
    end
end
