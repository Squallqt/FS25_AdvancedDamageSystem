ADS_LogEntrySyncEvent = {}
local ADS_LogEntrySyncEvent_mt = Class(ADS_LogEntrySyncEvent, Event)

InitEventClass(ADS_LogEntrySyncEvent, "ADS_LogEntrySyncEvent")


function ADS_LogEntrySyncEvent.emptyNew()
    return Event.new(ADS_LogEntrySyncEvent_mt)
end


function ADS_LogEntrySyncEvent.new(vehicle, serializedEntry)
    local self = ADS_LogEntrySyncEvent.emptyNew()
    self.vehicle = vehicle
    self.serializedEntry = serializedEntry or ""
    return self
end


function ADS_LogEntrySyncEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.serializedEntry)
end


function ADS_LogEntrySyncEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.serializedEntry = streamReadString(streamId)
    self:run(connection)
end


function ADS_LogEntrySyncEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    local spec = vehicle.spec_AdvancedDamageSystem
    if spec == nil then
        return
    end

    local entry = ADS_Utils.deserializeMaintenanceLogEntry(self.serializedEntry)
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


function ADS_LogEntrySyncEvent.sendToClients(vehicle, entry)
    if g_server ~= nil and entry ~= nil then
        local serialized = ADS_Utils.serializeMaintenanceLogEntry(entry)
        g_server:broadcastEvent(ADS_LogEntrySyncEvent.new(vehicle, serialized), nil, nil, vehicle)
    end
end
