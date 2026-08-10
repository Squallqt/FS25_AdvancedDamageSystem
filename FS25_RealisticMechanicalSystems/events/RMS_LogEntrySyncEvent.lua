RMS_LogEntrySyncEvent = {}
local RMS_LogEntrySyncEvent_mt = Class(RMS_LogEntrySyncEvent, Event)

InitEventClass(RMS_LogEntrySyncEvent, "RMS_LogEntrySyncEvent")


function RMS_LogEntrySyncEvent.emptyNew()
    return Event.new(RMS_LogEntrySyncEvent_mt)
end


function RMS_LogEntrySyncEvent.new(vehicle, serializedEntry)
    local self = RMS_LogEntrySyncEvent.emptyNew()
    self.vehicle = vehicle
    self.serializedEntry = serializedEntry or ""
    return self
end


function RMS_LogEntrySyncEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.serializedEntry)
end


function RMS_LogEntrySyncEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.serializedEntry = streamReadString(streamId)
    self:run(connection)
end


function RMS_LogEntrySyncEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local entry = RMS_Utils.deserializeMaintenanceLogEntry(self.serializedEntry)
    if entry ~= nil then
        for i, existingEntry in ipairs(spec.maintenanceLog) do
            if existingEntry.id == entry.id then
                spec.maintenanceLog[i] = entry
                return
            end
        end

        table.insert(spec.maintenanceLog, entry)
    end
end


function RMS_LogEntrySyncEvent.sendToClients(vehicle, entry)
    if g_server ~= nil and entry ~= nil then
        local serialized = RMS_Utils.serializeMaintenanceLogEntry(entry)
        g_server:broadcastEvent(RMS_LogEntrySyncEvent.new(vehicle, serialized), nil, nil, vehicle)
    end
end
