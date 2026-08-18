-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Synchronises the pressed, held and released state of the start button of a vehicle
RMS_StartButtonEvent = {}
local RMS_StartButtonEvent_mt = Class(RMS_StartButtonEvent, Event)

InitEventClass(RMS_StartButtonEvent, "RMS_StartButtonEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_StartButtonEvent.emptyNew()
    return Event.new(RMS_StartButtonEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param boolean isDown true on the frame the button is pressed
-- @param boolean isHeld true while the button stays pressed
-- @param boolean isUp true on the frame the button is released
-- @return table self instance of class event
function RMS_StartButtonEvent.new(vehicle, isDown, isHeld, isUp)
    local self = RMS_StartButtonEvent.emptyNew()
    self.vehicle = vehicle
    self.isDown = isDown == true
    self.isHeld = isHeld == true
    self.isUp = isUp == true
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_StartButtonEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isDown)
    streamWriteBool(streamId, self.isHeld)
    streamWriteBool(streamId, self.isUp)
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_StartButtonEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isDown = streamReadBool(streamId)
    self.isHeld = streamReadBool(streamId)
    self.isUp = streamReadBool(streamId)
    self:run(connection)
end


---Stores the button state on the vehicle, then requests the start and rebroadcasts it on the server
-- @param Connection connection connection
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


---Broadcast the button state from the server, send it to the server from a client
-- @param table vehicle vehicle
-- @param boolean isDown true on the frame the button is pressed
-- @param boolean isHeld true while the button stays pressed
-- @param boolean isUp true on the frame the button is released
function RMS_StartButtonEvent.send(vehicle, isDown, isHeld, isUp)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_StartButtonEvent.new(vehicle, isDown, isHeld, isUp), nil, nil, vehicle)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_StartButtonEvent.new(vehicle, isDown, isHeld, isUp))
    end
end

