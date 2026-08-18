-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Synchronises the air blower and grease gun hand tool actions between server and clients
RMS_HandToolSyncEvent = {}
local RMS_HandToolSyncEvent_mt = Class(RMS_HandToolSyncEvent, Event)

InitEventClass(RMS_HandToolSyncEvent, "RMS_HandToolSyncEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_HandToolSyncEvent.emptyNew()
    return Event.new(RMS_HandToolSyncEvent_mt)
end


---Create new instance of event
-- @param table tool hand tool
-- @param string? state tool state
-- @param table? targetVehicle vehicle the tool is aimed at
-- @param float? targetDistance distance to the target vehicle
-- @return table self instance of class event
function RMS_HandToolSyncEvent.new(tool, state, targetVehicle, targetDistance)
    local self = RMS_HandToolSyncEvent.emptyNew()
    self.tool = tool
    self.state = state or ""
    self.targetVehicle = targetVehicle
    self.targetDistance = targetDistance or 0
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_HandToolSyncEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.tool)
    streamWriteString(streamId, self.state)
    NetworkUtil.writeNodeObject(streamId, self.targetVehicle)
    streamWriteFloat32(streamId, self.targetDistance)
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_HandToolSyncEvent:readStream(streamId, connection)
    self.tool = NetworkUtil.readNodeObject(streamId)
    self.state = streamReadString(streamId)
    self.targetVehicle = NetworkUtil.readNodeObject(streamId)
    self.targetDistance = streamReadFloat32(streamId)
    self:run(connection)
end


---Validates and rebroadcasts the tool action on the server, applies its effect on a client
-- @param Connection connection connection
function RMS_HandToolSyncEvent:run(connection)
    local tool = self.tool
    if tool == nil or not tool:getIsSynchronized() then
        return
    end

    local spec = rmsHandTools.getSpec(tool)
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
                g_server:broadcastEvent(RMS_HandToolSyncEvent.new(tool, self.state, self.targetVehicle, self.targetDistance), nil, connection, tool)
            end
        elseif spec.toolKind == "greaseGun"
            and self.state == "use"
            and tool:tryUseGreaseGunServer(self.targetVehicle, connection) then
            RMS_SoundManager.playSample(spec.samples.greaseGun)
            g_server:broadcastEvent(RMS_HandToolSyncEvent.new(tool, "greaseUsed", self.targetVehicle, 0), nil, nil, tool)
        end

        return
    end

    if spec.toolKind == "airBlower" then
        tool:applyAirBlowerNetworkState(self.state, self.targetVehicle, self.targetDistance)
    elseif spec.toolKind == "greaseGun" and self.state == "greaseUsed" then
        RMS_SoundManager.playSample(spec.samples.greaseGun)
    end
end


---Applies and broadcasts the action on the server, sends it to the server from a client
-- @param table tool hand tool
-- @param string state tool state
-- @param table? targetVehicle vehicle the tool is aimed at
-- @param float? targetDistance distance to the target vehicle
function RMS_HandToolSyncEvent.send(tool, state, targetVehicle, targetDistance)
    if g_server ~= nil then
        local spec = rmsHandTools.getSpec(tool)
        if spec.toolKind == "airBlower" then
            if tool:applyAirBlowerNetworkState(state, targetVehicle, targetDistance) then
                g_server:broadcastEvent(RMS_HandToolSyncEvent.new(tool, state, targetVehicle, targetDistance), nil, nil, tool)
            end
        elseif spec.toolKind == "greaseGun"
            and state == "use"
            and tool:tryUseGreaseGunServer(targetVehicle) then
            RMS_SoundManager.playSample(spec.samples.greaseGun)
            g_server:broadcastEvent(RMS_HandToolSyncEvent.new(tool, "greaseUsed", targetVehicle, 0), nil, nil, tool)
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_HandToolSyncEvent.new(tool, state, targetVehicle, targetDistance))
    end
end
