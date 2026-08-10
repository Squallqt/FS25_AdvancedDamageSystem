RMS_StartButtonEvent = {}
local RMS_StartButtonEvent_mt = Class(RMS_StartButtonEvent, Event)

InitEventClass(RMS_StartButtonEvent, "RMS_StartButtonEvent")


function RMS_StartButtonEvent.emptyNew()
    return Event.new(RMS_StartButtonEvent_mt)
end


function RMS_StartButtonEvent.new(vehicle, isDown, isHeld, isUp)
    local self = RMS_StartButtonEvent.emptyNew()
    self.vehicle = vehicle
    self.isDown = isDown == true
    self.isHeld = isHeld == true
    self.isUp = isUp == true
    return self
end


function RMS_StartButtonEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isDown)
    streamWriteBool(streamId, self.isHeld)
    streamWriteBool(streamId, self.isUp)
end


function RMS_StartButtonEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isDown = streamReadBool(streamId)
    self.isHeld = streamReadBool(streamId)
    self.isUp = streamReadBool(streamId)
    self:run(connection)
end


function RMS_StartButtonEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    spec.startButtonDown = self.isDown
    spec.startButtonHeld = self.isHeld
    spec.startButtonUp = self.isUp

    if not connection:getIsServer() then
        if self.isDown and vehicle.isServer then
            RMS_Preheat.requestStart(vehicle)
        end
        g_server:broadcastEvent(RMS_StartButtonEvent.new(vehicle, self.isDown, self.isHeld, self.isUp), nil, connection, vehicle)
    end
end


function RMS_StartButtonEvent.send(vehicle, isDown, isHeld, isUp)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_StartButtonEvent.new(vehicle, isDown, isHeld, isUp), nil, nil, vehicle)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_StartButtonEvent.new(vehicle, isDown, isHeld, isUp))
    end
end

