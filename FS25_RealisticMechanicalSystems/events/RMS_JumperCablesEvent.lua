-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Carries jumper cable requests to the server and the resulting state back to the clients
RMS_JumperCablesEvent = {}
local RMS_JumperCablesEvent_mt = Class(RMS_JumperCablesEvent, Event)

InitEventClass(RMS_JumperCablesEvent, "RMS_JumperCablesEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_JumperCablesEvent.emptyNew()
    return Event.new(RMS_JumperCablesEvent_mt)
end


---Create new instance of event
-- @param table tool jumper cables hand tool
-- @param string? state requested or resulting cable state
-- @param table? targetVehicle vehicle aimed at by the request
-- @param table? connectedVehicleA vehicle on the first clamp
-- @param table? connectedVehicleB vehicle on the second clamp
-- @return table self instance of class event
function RMS_JumperCablesEvent.new(tool, state, targetVehicle, connectedVehicleA, connectedVehicleB)
    local self = RMS_JumperCablesEvent.emptyNew()
    self.tool = tool
    self.state = state or ""
    self.targetVehicle = targetVehicle
    self.connectedVehicleA = connectedVehicleA
    self.connectedVehicleB = connectedVehicleB
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_JumperCablesEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.tool)
    streamWriteString(streamId, self.state)
    NetworkUtil.writeNodeObject(streamId, self.targetVehicle)
    NetworkUtil.writeNodeObject(streamId, self.connectedVehicleA)
    NetworkUtil.writeNodeObject(streamId, self.connectedVehicleB)
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_JumperCablesEvent:readStream(streamId, connection)
    self.tool = NetworkUtil.readNodeObject(streamId)
    self.state = streamReadString(streamId)
    self.targetVehicle = NetworkUtil.readNodeObject(streamId)
    self.connectedVehicleA = NetworkUtil.readNodeObject(streamId)
    self.connectedVehicleB = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end


---Handles the request on the server for the carrying player, applies the state on a client
-- @param Connection connection connection
function RMS_JumperCablesEvent:run(connection)
    local tool = self.tool
    if tool == nil or not tool:getIsSynchronized() then
        return
    end

    local spec = rmsHandTools.getSpec(tool)
    if spec == nil or spec.toolKind ~= "jumperCables" then
        return
    end

    if connection ~= nil and not connection:getIsServer() then
        local player = g_currentMission ~= nil and g_currentMission.connectionsToPlayer ~= nil and g_currentMission.connectionsToPlayer[connection] or nil
        if player == nil or tool.getCarryingPlayer == nil or tool:getCarryingPlayer() ~= player then
            return
        end

        tool:handleJumperCablesActionServer(self.state, self.targetVehicle, connection)
        return
    end

    tool:applyJumperCablesState(self.state, self.targetVehicle, self.connectedVehicleA, self.connectedVehicleB)
end


---Send a cable request from a client to the server
-- @param table tool jumper cables hand tool
-- @param string state requested cable state
-- @param table? targetVehicle vehicle aimed at by the request
function RMS_JumperCablesEvent.sendRequest(tool, state, targetVehicle)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_JumperCablesEvent.new(tool, state, targetVehicle, nil, nil))
    end
end


---Broadcast the resulting cable state from the server to the clients of the tool
-- @param table tool jumper cables hand tool
-- @param string state resulting cable state
-- @param table? targetVehicle vehicle aimed at by the request
-- @param table? connectedVehicleA vehicle on the first clamp
-- @param table? connectedVehicleB vehicle on the second clamp
function RMS_JumperCablesEvent.broadcastState(tool, state, targetVehicle, connectedVehicleA, connectedVehicleB)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_JumperCablesEvent.new(tool, state, targetVehicle, connectedVehicleA, connectedVehicleB), nil, nil, tool)
    end
end
