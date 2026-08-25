-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client request to recompute the whole fleet, answered by the server with its counts
RMS_ReinitializeVehiclesEvent = {}
local RMS_ReinitializeVehiclesEvent_mt = Class(RMS_ReinitializeVehiclesEvent, Event)

InitEventClass(RMS_ReinitializeVehiclesEvent, "RMS_ReinitializeVehiclesEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_ReinitializeVehiclesEvent.emptyNew()
    return Event.new(RMS_ReinitializeVehiclesEvent_mt)
end


---Create new instance of event
-- @param boolean isResult true for the answer sent back by the server
-- @param integer? recalculated number of vehicles recomputed
-- @param integer? busy number of vehicles left untouched
-- @return table self instance of class event
function RMS_ReinitializeVehiclesEvent.new(isResult, recalculated, busy)
    local self = RMS_ReinitializeVehiclesEvent.emptyNew()
    self.isResult = isResult == true
    self.recalculated = math.max(math.floor(tonumber(recalculated) or 0), 0)
    self.busy = math.max(math.floor(tonumber(busy) or 0), 0)
    return self
end


---Writes the event
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_ReinitializeVehiclesEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isResult)
    if self.isResult then
        streamWriteUInt16(streamId, math.min(self.recalculated, 65535))
        streamWriteUInt16(streamId, math.min(self.busy, 65535))
    end
end


---Reads the event
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_ReinitializeVehiclesEvent:readStream(streamId, connection)
    self.isResult = streamReadBool(streamId)
    if self.isResult then
        self.recalculated = streamReadUInt16(streamId)
        self.busy = streamReadUInt16(streamId)
    end
    self:run(connection)
end


---Runs the recomputation on the server, or shows its result on the requesting client
-- @param Connection connection connection
function RMS_ReinitializeVehiclesEvent:run(connection)
    if self.isResult then
        if connection:getIsServer() then
            RMS_SettingsPage.showReinitializeVehiclesResult(self.recalculated, self.busy)
        end
        return
    end

    if connection:getIsServer() then
        return
    end

    local recalculated, busy = RealisticMechanicalSystems.reinitializeAllVehicles()
    connection:sendEvent(RMS_ReinitializeVehiclesEvent.new(true, recalculated, busy))
end


---Asks the server to recompute the whole fleet
function RMS_ReinitializeVehiclesEvent.sendToServer()
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_ReinitializeVehiclesEvent.new(false))
    end
end
