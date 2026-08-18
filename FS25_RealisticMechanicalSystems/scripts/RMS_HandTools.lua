-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Hand tool specialization: air blower, grease gun and jumper cables
rmsHandTools = {}

local specName = "spec_" .. g_currentModName .. ".rmsHandTools"

---Returns the reach of the hand tool raycast
-- @return float distance raycast distance in metres
local function getRaycastDistance()
    local fieldCare = RMS_Config ~= nil and RMS_Config.FIELD_CARE or nil
    return (fieldCare ~= nil and fieldCare.RAYCAST_DISTANCE) or 1.5
end


local log_dbg = RMS_Utils.createLogger("[RMS_HAND_TOOLS]")

---Returns the hand tool spec of an object, creating it on first use
-- @param table? object hand tool
-- @return table? spec hand tool spec
local function ensureSpec(object)
    local spec = object[specName]
    if spec == nil then
        spec = {}
        object[specName] = spec
    end

    return spec
end

---Returns the hand tool spec of an object without creating it
-- @param table? tool hand tool
-- @return table? spec hand tool spec, nil when the object carries none
function rmsHandTools.getSpec(tool)
    if tool == nil then
        return nil
    end

    if g_currentModName ~= nil then
        local spec = tool["spec_" .. g_currentModName .. ".rmsHandTools"]
        if spec ~= nil then
            return spec
        end
    end

    for key, value in pairs(tool) do
        if type(key) == "string"
            and string.sub(key, 1, 5) == "spec_"
            and string.sub(key, -13) == ".rmsHandTools" then
            return value
        end
    end

    return nil
end

---Returns which of the three tools this is, read from its xml
-- @param table? handTool hand tool
-- @return string? kind tool kind
local function getToolKind(handTool)
    local configFileName = string.lower(handTool ~= nil and handTool.configFileName or "")

    if string.find(configFileName, "airblower", 1, true) then
        return "airBlower"
    end

    if string.find(configFileName, "greasegun", 1, true) then
        return "greaseGun"
    end

    if string.find(configFileName, "jumpercables", 1, true) then
        return "jumperCables"
    end

    return "unknown"
end

---Resolves an i3d node declared under a mapping key
-- @param table? object hand tool
-- @param string mappingKey i3d mapping key
-- @return entityId? node resolved node
local function resolveMappedNode(object, mappingKey)
    if object == nil or object.components == nil or object.i3dMappings == nil then
        return nil
    end

    return I3DUtil.indexToObject(object.components, mappingKey, object.i3dMappings)
end

---Raycasts forward from the tool and returns the vehicle it hits
-- @param table? handTool hand tool
-- @param float maxDistance reach of the raycast
-- @return table? vehicle vehicle hit
-- @return float distance distance to it
local function getRaycastVehicle(handTool, maxDistance)
    local spec = ensureSpec(handTool)
    spec.raycastVehicle = nil
    spec.raycastVehicleDistance = math.huge
    spec.raycastHitX = nil
    spec.raycastHitY = nil
    spec.raycastHitZ = nil
    spec.raycastHitNX = nil
    spec.raycastHitNY = nil
    spec.raycastHitNZ = nil

    if spec.raycastNode == nil or spec.raycastNode == 0 then
        log_dbg("Raycast aborted: raycastNode is missing")
        return nil
    end

    local x, y, z = getWorldTranslation(spec.raycastNode)
    local dx, dy, dz = localDirectionToWorld(spec.raycastNode, 0, 0, -1)

    raycastAll(x, y, z, dx, dy, dz, maxDistance or getRaycastDistance(), "handToolRaycastCallback", handTool, nil, false, true)

    return spec.raycastVehicle
end

---Sets the text shown on the tool action
-- @param table? handTool hand tool
-- @param string text action text
local function setActionText(handTool, text)
    local spec = ensureSpec(handTool)
    if spec.activateActionEventId ~= nil then
        g_inputBinding:setActionEventText(spec.activateActionEventId, text)
    end
end

---Returns the action text of the tool when it points at nothing
-- @param table? handTool hand tool
-- @return string text action text
local function getDefaultActionText(handTool)
    local toolKind = getToolKind(handTool)

    if toolKind == "airBlower" then
        return g_i18n:getText("rms_air_blower_action")
    elseif toolKind == "greaseGun" then
        return g_i18n:getText("rms_grease_gun_action")
    elseif toolKind == "jumperCables" then
        if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText("rms_jumper_cables_action") then
            return g_i18n:getText("rms_jumper_cables_action")
        end

        return "Connect jumper cables"
    end

    return ""
end

---Starts or stops the working sound of the tool
-- @param table? handTool hand tool
-- @param boolean shouldPlay true to play it
local function setToolSoundState(handTool, shouldPlay)
    local spec = ensureSpec(handTool)
    if spec == nil or spec.samples == nil then
        return
    end

    local sample = nil
    if spec.toolKind == "airBlower" then
        sample = spec.samples.airBlower
    end

    if sample == nil then
        return
    end

    RMS_SoundManager.setSamplePlaying(sample, shouldPlay)
end

---Starts or stops the air resistance sound of the blower
-- @param table? handTool hand tool
-- @param boolean shouldPlay true to play it
local function setAirResistanceSoundState(handTool, shouldPlay)
    local spec = ensureSpec(handTool)
    if spec == nil or spec.samples == nil then
        return
    end

    local sample = nil
    if spec.toolKind == "airBlower" then
        sample = spec.samples.airBlowerAirResistance
    end

    if sample == nil then
        return
    end

    RMS_SoundManager.setSamplePlaying(sample, shouldPlay)
end

---Puts the dust emitter of the blower back at its rest position
-- @param table? handTool hand tool
local function resetDustEmitterPosition(handTool)
    local spec = ensureSpec(handTool)
    if spec.dustEmitterRootNode ~= nil and spec.dustEmitterRootNode ~= 0 then
        setTranslation(
            spec.dustEmitterRootNode,
            spec.dustEmitterBaseX or 0,
            spec.dustEmitterBaseY or 0,
            spec.dustEmitterBaseZ or 0
        )
    end
end

---Moves the dust emitter of the blower to the distance being blown at
-- @param table? handTool hand tool
-- @param float distance distance to the target
local function setDustEmitterDistance(handTool, distance)
    local spec = ensureSpec(handTool)
    if spec.dustEmitterRootNode == nil or spec.dustEmitterRootNode == 0 then
        return
    end

    local clampedDistance = math.max(tonumber(distance) or 0, 0.1)

    setTranslation(
        spec.dustEmitterRootNode,
        spec.dustEmitterBaseX or 0,
        spec.dustEmitterBaseY or 0,
        -clampedDistance
    )
end

---Replicates the tool state, skipping an unchanged one unless forced
-- @param table? handTool hand tool
-- @param string state tool state
-- @param boolean? force true to send an unchanged state
-- @param table? targetVehicle vehicle the tool points at
-- @param float? targetDistance distance to it
local function sendHandToolState(handTool, state, force, targetVehicle, targetDistance)
    if g_server == nil and g_client == nil then
        return
    end

    local spec = ensureSpec(handTool)
    if state == "use" then
        local distance = tonumber(targetDistance) or 0
        if not force
            and spec.lastSentUseTargetVehicle == targetVehicle
            and math.abs((spec.lastSentUseTargetDistance or 0) - distance) < 0.05 then
            return
        end

        RMS_HandToolSyncEvent.send(handTool, state, targetVehicle, distance)
        spec.lastSentUseTargetVehicle = targetVehicle
        spec.lastSentUseTargetDistance = distance
        return
    end

    if not force and spec.lastSentNetworkState == state then
        return
    end

    RMS_HandToolSyncEvent.send(handTool, state, targetVehicle, targetDistance)

    if state == "stop" then
        spec.lastSentUseTargetVehicle = nil
        spec.lastSentUseTargetDistance = nil
    end

    spec.lastSentNetworkState = state
end

---Broadcasts the jumper cable state from the server
-- @param table? handTool hand tool
-- @param string state cable state
-- @param table? targetVehicle vehicle at the other end
local function broadcastJumperCablesState(handTool, state, targetVehicle)
    local spec = ensureSpec(handTool)

    if g_server ~= nil then
        RMS_JumperCablesEvent.broadcastState(handTool, state, targetVehicle, spec.connectedVehicleA, spec.connectedVehicleB)
    end

    if handTool.isClient then
        handTool:applyJumperCablesState(state, targetVehicle, spec.connectedVehicleA, spec.connectedVehicleB)
    end
end

---Shows the cable clamps matching the current connection
-- @param table? handTool hand tool
local function updateJumperCablesVisibility(handTool)
    local spec = ensureSpec(handTool)
    if spec.toolKind ~= "jumperCables" then
        return
    end

    if spec.leftPairNode ~= nil and spec.leftPairNode ~= 0 then
        setVisibility(spec.leftPairNode, spec.connectedVehicleA == nil)
    end

    if spec.rightPairNode ~= nil and spec.rightPairNode ~= 0 then
        setVisibility(spec.rightPairNode, spec.connectedVehicleB == nil)
    end
end

---Resolves a connected object to the vehicle carrying the battery
-- @param table? vehicle vehicle or implement
-- @return table? vehicle vehicle carrying the battery
local function normalizeConnectedVehicle(vehicle)
    if vehicle == nil then
        return nil
    end

    if vehicle.getRootVehicle ~= nil then
        return vehicle:getRootVehicle()
    end

    return vehicle
end

---Tells whether two vehicles are already linked by jumper cables
-- @param table? vehicleA first vehicle
-- @param table? vehicleB second vehicle
-- @return boolean areConnected true when the cables link them
local function areVehiclesExternallyConnected(vehicleA, vehicleB)
    vehicleA = normalizeConnectedVehicle(vehicleA)
    vehicleB = normalizeConnectedVehicle(vehicleB)

    if vehicleA == nil or vehicleB == nil or vehicleA == vehicleB then
        return false
    end

    local specA = vehicleA.spec_RealisticMechanicalSystems
    local specB = vehicleB.spec_RealisticMechanicalSystems
    if specA == nil or specB == nil then
        return false
    end

    local connectionA = specA.externalPowerConnection
    if type(connectionA) == "table" and connectionA.object ~= nil then
        connectionA = connectionA.object
    end

    local connectionB = specB.externalPowerConnection
    if type(connectionB) == "table" and connectionB.object ~= nil then
        connectionB = connectionB.object
    end

    return connectionA == vehicleB and connectionB == vehicleA
end


---
-- @param table specializations specializations of the hand tool type
-- @return boolean hasPrerequisite true when the specialization applies
function rmsHandTools.prerequisitesPresent(specializations)
    return true
end

---
-- @param table handTool hand tool type
function rmsHandTools.registerFunctions(handTool)
    SpecializationUtil.registerFunction(handTool, "handToolRaycastCallback", rmsHandTools.handToolRaycastCallback)
    SpecializationUtil.registerFunction(handTool, "applyAirBlowerNetworkState", rmsHandTools.applyAirBlowerNetworkState)
    SpecializationUtil.registerFunction(handTool, "tryUseGreaseGunServer", rmsHandTools.tryUseGreaseGunServer)
    SpecializationUtil.registerFunction(handTool, "handleJumperCablesActionServer", rmsHandTools.handleJumperCablesActionServer)
    SpecializationUtil.registerFunction(handTool, "applyJumperCablesState", rmsHandTools.applyJumperCablesState)
end

---
-- @param table handTool hand tool type
function rmsHandTools.registerEventListeners(handTool)
    SpecializationUtil.registerEventListener(handTool, "onLoad", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onPostLoad", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onDelete", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onUpdate", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onWriteStream", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onReadStream", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onHeldStart", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onHeldEnd", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onRegisterActionEvents", rmsHandTools)
end

---
-- @param table savegame savegame
function rmsHandTools:onLoad(savegame)
    ensureSpec(self)
end

---
-- @param table savegame savegame
function rmsHandTools:onPostLoad(savegame)
    local spec = ensureSpec(self)
    spec.toolKind = getToolKind(self)
    spec.activateText = getDefaultActionText(self)
    spec.isActive = false
    spec.activatePressed = false
    spec.raycastVehicle = nil
    spec.raycastVehicleDistance = math.huge
    spec.raycastHitX = nil
    spec.raycastHitY = nil
    spec.raycastHitZ = nil
    spec.raycastHitNX = nil
    spec.raycastHitNY = nil
    spec.raycastHitNZ = nil
    spec.raycastNode = resolveMappedNode(self, "raycastNode")
    spec.leftPairNode = nil
    spec.rightPairNode = nil
    spec.dustEmitterNode = nil
    spec.dustEmitterRootNode = nil
    spec.dustEmitterBaseX = nil
    spec.dustEmitterBaseY = nil
    spec.dustEmitterBaseZ = nil
    spec.dustParticleSystem = nil
    spec.lastAirBlowerHintKey = nil
    spec.networkUseActive = false
    spec.networkTargetVehicle = nil
    spec.networkTargetDistance = 0
    spec.lastSentNetworkState = nil
    spec.lastSentUseTargetVehicle = nil
    spec.lastSentUseTargetDistance = nil
    spec.samples = spec.samples or {}

    if self.isClient then
        local xmlSoundFile = loadXMLFile("rmsHandToolSounds", self.baseDirectory .. "sounds/rms_sounds.xml")
        if xmlSoundFile ~= nil then
            if spec.toolKind == "airBlower" then
                spec.samples.airBlower = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "airBlowerTool", self.baseDirectory, self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
                spec.samples.airBlowerAirResistance = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "airBlowerAirResistanceTool", self.baseDirectory, self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
            elseif spec.toolKind == "greaseGun" then
                spec.samples.greaseGun = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "greaseGunTool", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
            elseif spec.toolKind == "jumperCables" then
                spec.samples.jumperCablesConnect = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "jumperCablesConnectTool", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
                spec.samples.jumperCablesDisconnect = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "jumperCablesDisconnectTool", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
                spec.samples.jumperCablesSparks = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "jumperCablesSparksTool", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
            end

            delete(xmlSoundFile)
        end
    end

    if spec.toolKind == "airBlower" then
        spec.dustEmitterNode = resolveMappedNode(self, "dustEmitterNode")
    end

    if spec.toolKind == "airBlower" and spec.dustEmitterNode ~= nil and spec.dustEmitterNode ~= 0 then
        local emitterParent = getParent(spec.dustEmitterNode)
        if emitterParent ~= nil and emitterParent ~= 0 then
            spec.dustEmitterRootNode = emitterParent
        else
            spec.dustEmitterRootNode = spec.dustEmitterNode
        end

        if spec.dustEmitterRootNode ~= nil and spec.dustEmitterRootNode ~= 0 then
            spec.dustEmitterBaseX, spec.dustEmitterBaseY, spec.dustEmitterBaseZ = getTranslation(spec.dustEmitterRootNode)
        end

        local sourceParticleSystem = g_particleSystemManager:getParticleSystem("wheel_dust")

        if sourceParticleSystem ~= nil then
            spec.dustParticleSystem = ParticleUtil.copyParticleSystem(nil, nil, sourceParticleSystem, spec.dustEmitterNode)

            if spec.dustParticleSystem ~= nil then
                ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
            end
        end
    end

    if spec.toolKind == "jumperCables" then
        spec.leftPairNode = resolveMappedNode(self, "leftPair")
        spec.rightPairNode = resolveMappedNode(self, "rightPair")
        spec.connectedVehicleA = nil
        spec.connectedVehicleB = nil
        updateJumperCablesVisibility(self)
    end
end

---
-- @param integer streamId streamId
-- @param Connection connection connection
function rmsHandTools:onWriteStream(streamId, connection)
    local spec = ensureSpec(self)
    if spec.toolKind == "airBlower" and not connection:getIsServer() then
        streamWriteBool(streamId, spec.networkUseActive)
        NetworkUtil.writeNodeObject(streamId, spec.networkTargetVehicle)
        streamWriteFloat32(streamId, spec.networkTargetDistance)
    end
end

---
-- @param integer streamId streamId
-- @param Connection connection connection
function rmsHandTools:onReadStream(streamId, connection)
    local spec = ensureSpec(self)
    if spec.toolKind == "airBlower" and connection:getIsServer() then
        local isActive = streamReadBool(streamId)
        local targetVehicle = NetworkUtil.readNodeObject(streamId)
        local targetDistance = streamReadFloat32(streamId)
        self:applyAirBlowerNetworkState(isActive and "use" or "stop", targetVehicle, targetDistance)
    end
end

---
function rmsHandTools:onDelete()
    local spec = ensureSpec(self)

    setToolSoundState(self, false)
    setAirResistanceSoundState(self, false)

    if spec.samples ~= nil then
        if spec.samples.airBlower ~= nil then
            g_soundManager:deleteSample(spec.samples.airBlower)
        end

        if spec.samples.airBlowerAirResistance ~= nil then
            g_soundManager:deleteSample(spec.samples.airBlowerAirResistance)
        end

        if spec.samples.greaseGun ~= nil then
            g_soundManager:deleteSample(spec.samples.greaseGun)
        end

        if spec.samples.jumperCablesConnect ~= nil then
            g_soundManager:deleteSample(spec.samples.jumperCablesConnect)
        end

        if spec.samples.jumperCablesDisconnect ~= nil then
            g_soundManager:deleteSample(spec.samples.jumperCablesDisconnect)
        end

        if spec.samples.jumperCablesSparks ~= nil then
            g_soundManager:deleteSample(spec.samples.jumperCablesSparks)
        end
    end

    if spec.dustParticleSystem ~= nil then
        ParticleUtil.deleteParticleSystem(spec.dustParticleSystem)
        spec.dustParticleSystem = nil
    end
end


---Registers the tool actions and starts its idle sounds when the player picks it up
function rmsHandTools:onHeldStart()
    if g_localPlayer == nil or self:getCarryingPlayer() ~= g_localPlayer then
        return
    end

    local spec = ensureSpec(self)
    spec.isActive = true
    spec.activatePressed = false
    spec.networkUseActive = false
    spec.networkTargetVehicle = nil
    spec.networkTargetDistance = 0
    spec.lastAirBlowerHintKey = nil
    spec.lastSentNetworkState = nil
    spec.lastSentUseTargetVehicle = nil
    spec.lastSentUseTargetDistance = nil

    if spec.toolKind == 'jumperCables' and self.isClient and spec.connectedVehicleA ~= nil and spec.connectedVehicleB ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_both_already_connected"), spec.connectedVehicleA:getFullName(), spec.connectedVehicleB:getFullName()), 2200)
    end

end

---Stops the sounds and the effects when the player puts the tool away
function rmsHandTools:onHeldEnd()
    local spec = ensureSpec(self)

    if spec.toolKind == "airBlower" and spec.lastSentNetworkState == "start" then
        sendHandToolState(self, "stop", true)
    end

    spec.isActive = false
    spec.activatePressed = false
    spec.networkUseActive = false
    spec.networkTargetVehicle = nil
    spec.networkTargetDistance = 0
    spec.lastAirBlowerHintKey = nil
    spec.lastSentUseTargetVehicle = nil
    spec.lastSentUseTargetDistance = nil
    setActionText(self, spec.activateText)
    setToolSoundState(self, false)
    setAirResistanceSoundState(self, false)
    resetDustEmitterPosition(self)

end

---Applies the blower state, aiming its dust emitter and cleaning the target vehicle
-- @param string state tool state
-- @param table? targetVehicle vehicle being blown out
-- @param float? targetDistance distance to it
-- @return boolean changed true when the state changed
function rmsHandTools:applyAirBlowerNetworkState(state, targetVehicle, targetDistance)
    local spec = ensureSpec(self)
    if spec.toolKind ~= "airBlower" then
        return false
    end

    if state == "start" then
        spec.networkUseActive = true
        spec.networkTargetVehicle = nil
        spec.networkTargetDistance = 0
    elseif state == "stop" then
        spec.networkUseActive = false
        spec.networkTargetVehicle = nil
        spec.networkTargetDistance = 0
    elseif state == "use" then
        spec.networkUseActive = true
        spec.networkTargetVehicle = normalizeConnectedVehicle(targetVehicle)
        spec.networkTargetDistance = tonumber(targetDistance) or 0
    else
        return false
    end

    return true
end

---Greases the target vehicle on the server when it needs it
-- @param table? targetVehicle vehicle being greased
-- @param Connection? connection connection of the requesting player
-- @return boolean used true when grease was applied
function rmsHandTools:tryUseGreaseGunServer(targetVehicle, connection)
    if not self.isServer then
        return false
    end

    local spec = ensureSpec(self)
    if spec.toolKind ~= "greaseGun" then
        return false
    end

    if connection ~= nil then
        local player = g_currentMission ~= nil and g_currentMission.connectionsToPlayer ~= nil and g_currentMission.connectionsToPlayer[connection] or nil
        if player == nil or self.getCarryingPlayer == nil or self:getCarryingPlayer() ~= player then
            return false
        end
    end

    local vehicle = normalizeConnectedVehicle(targetVehicle)
    if vehicle == nil then
        vehicle = getRaycastVehicle(self, getRaycastDistance())
    end

    if vehicle == nil then
        return false
    end

    local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
    if vehicleSpec == nil or not vehicleSpec.isVehicleNeedLubricate then
        return false
    end

    if (tonumber(vehicleSpec.lubricationLevel) or 0) >= 1.0 then
        return false
    end

    vehicle:lubricateVehicle()
    return true
end

---Runs one jumper cable action on the server: clamp, unclamp or link the two batteries
-- @param string state requested cable state
-- @param table? targetVehicle vehicle aimed at
-- @param Connection? connection connection of the requesting player
function rmsHandTools:handleJumperCablesActionServer(state, targetVehicle, connection)
    if not self.isServer then
        return false
    end

    local spec = ensureSpec(self)
    if spec.toolKind ~= "jumperCables" then
        return false
    end

    if connection ~= nil then
        local player = g_currentMission ~= nil and g_currentMission.connectionsToPlayer ~= nil and g_currentMission.connectionsToPlayer[connection] or nil
        if player == nil or self.getCarryingPlayer == nil or self:getCarryingPlayer() ~= player then
            return false
        end
    end

    local resultState = "jumperInvalid"
    local vehicle = targetVehicle

    if state ~= "jumperInteract" then
        return false
    end

    -- no rms
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        resultState = "jumperInvalid"

    -- disconnect
    elseif vehicle == spec.connectedVehicleA or vehicle == spec.connectedVehicleB then
        if spec.connectedVehicleA ~= nil and spec.connectedVehicleA.clearExternalPowerConnection ~= nil then
            spec.connectedVehicleA:clearExternalPowerConnection(spec.connectedVehicleB)
        elseif spec.connectedVehicleB ~= nil and spec.connectedVehicleB.clearExternalPowerConnection ~= nil then
            spec.connectedVehicleB:clearExternalPowerConnection(spec.connectedVehicleA)
        end

        if vehicle == spec.connectedVehicleA then
            spec.connectedVehicleA = nil
        else
            spec.connectedVehicleB = nil
        end

        resultState = "jumperDisconnected"

    -- connect first
    elseif spec.connectedVehicleA == nil and spec.connectedVehicleB == nil then
        spec.connectedVehicleA = vehicle
        resultState = "jumperSelected"

    -- connect second
    elseif spec.connectedVehicleA == nil or spec.connectedVehicleB == nil then
        local firstVehicle = spec.connectedVehicleA or spec.connectedVehicleB
        local isValid, reason = RMS_Electrical.isValidPowerPair(firstVehicle, vehicle)

        if not isValid then
            if reason == "TOO_FAR" then
                resultState = "jumperTooFar"
            else
                resultState = "jumperInvalid"
            end
        else
            if spec.connectedVehicleB == nil then
                spec.connectedVehicleB = vehicle
            else
                spec.connectedVehicleA = vehicle
            end

            if firstVehicle:establishExternalPowerConnection(vehicle) then
                resultState = "jumperConnected"
            else
                if spec.connectedVehicleA == vehicle then
                    spec.connectedVehicleA = nil
                elseif spec.connectedVehicleB == vehicle then
                    spec.connectedVehicleB = nil
                end

                resultState = "jumperInvalid"
            end
        end
    else
        resultState = "jumperFull"
    end

    broadcastJumperCablesState(self, resultState, vehicle)
    return resultState == "jumperSelected" or resultState == "jumperConnected" or resultState == "jumperDisconnected"
end

---Applies the cable state locally, moving the clamps and the sounds
-- @param string state cable state
-- @param table? targetVehicle vehicle aimed at
-- @param table? connectedVehicleA vehicle on the first clamp
-- @param table? connectedVehicleB vehicle on the second clamp
function rmsHandTools:applyJumperCablesState(state, targetVehicle, connectedVehicleA, connectedVehicleB)
    local spec = ensureSpec(self)
    spec.connectedVehicleA = connectedVehicleA
    spec.connectedVehicleB = connectedVehicleB
    updateJumperCablesVisibility(self)

    if self.isClient then
        if state == "jumperSelected" or state == "jumperConnected" then
            RMS_SoundManager.playSample(spec.samples.jumperCablesConnect)
        elseif state == "jumperDisconnected" or state == "jumperAutoDisconnected" then
            RMS_SoundManager.playSample(spec.samples.jumperCablesDisconnect)
        end
        if state == "jumperConnected" then
            RMS_SoundManager.playSample(spec.samples.jumperCablesSparks)
        end
    end

    if not self.isClient or g_localPlayer == nil or self.getCarryingPlayer == nil or self:getCarryingPlayer() ~= g_localPlayer then
        return
    end

    local targetName = targetVehicle ~= nil and targetVehicle.getFullName ~= nil and targetVehicle:getFullName() or nil
    local firstVehicle = spec.connectedVehicleA or spec.connectedVehicleB
    local firstVehicleName = firstVehicle ~= nil and firstVehicle.getFullName ~= nil and firstVehicle:getFullName() or nil

    if state == "jumperSelected" and targetName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_connected"), targetName), 2200)
    elseif state == "jumperConnected" and targetName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_connected"), targetName), 2200)
    elseif state == "jumperDisconnected" and targetName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_disconnected"), targetName), 2200)
    elseif state == "jumperAutoDisconnected" then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_auto_disconnected"), 2200)
    elseif state == "jumperTooFar" and targetName ~= nil and firstVehicleName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_is_too_far"), targetName, firstVehicleName), 2200)
    elseif state == "jumperFull" and spec.connectedVehicleA ~= nil and spec.connectedVehicleB ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_both_already_connected"), spec.connectedVehicleA:getFullName(), spec.connectedVehicleB:getFullName()), 2200)
    elseif state == "jumperInvalid" then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_impossible_to_connect"), 2200)
    end
end


---
function rmsHandTools:onRegisterActionEvents()
    local spec = ensureSpec(self)
    if not self:getIsActiveForInput(true) then
        return
    end

    if spec.activateText == nil or spec.activateText == "" then
        return
    end

    local _, eventId = self:addActionEvent(
        InputAction.ACTIVATE_HANDTOOL,
        self,
        rmsHandTools.onActionCallback,
        true,
        true,
        false,
        true,
        nil
    )

    spec.activateActionEventId = eventId

    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(eventId, spec.activateText)
        g_inputBinding:setActionEventActive(eventId, true)
    end
end

---Runs the tool action on the vehicle the player points at
-- @param string actionName input action name
-- @param float inputValue input value
function rmsHandTools:onActionCallback(actionName, inputValue)
    local spec = ensureSpec(self)
    local isPressed = inputValue > 0

    if not spec.isActive then
        return
    end

    spec.activatePressed = isPressed

    -- airBlower
    if not isPressed then
        if spec.toolKind == "airBlower" then
            sendHandToolState(self, "stop")
        end

        spec.lastAirBlowerHintKey = nil
        setActionText(self, spec.activateText)
        setToolSoundState(self, false)
        setAirResistanceSoundState(self, false)
        resetDustEmitterPosition(self)
        return
    end

    if spec.toolKind == "airBlower" then
        sendHandToolState(self, "start")
    end

    local vehicle = getRaycastVehicle(self, getRaycastDistance())

    -- greaseGun
    if vehicle ~= nil and spec.toolKind == "greaseGun" then
        local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
        if vehicleSpec ~= nil and vehicleSpec.isVehicleNeedLubricate and (tonumber(vehicleSpec.lubricationLevel) or 0) < 1.0 then
            sendHandToolState(self, "use", true, vehicle)
        elseif vehicleSpec ~= nil and not vehicleSpec.isVehicleNeedLubricate then
            if self.isClient then
                g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_grease_gun_lubrication_not_require"), vehicle:getFullName()), 2200)
            end
        else
            if self.isClient then
                g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_grease_gun_already_lubricated"), vehicle:getFullName()), 2200)
            end
        end
    end

    -- jumperCables
    if vehicle ~= nil and spec.toolKind == "jumperCables" then
        local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
        if vehicleSpec ~= nil then
            if self.isServer then
                self:handleJumperCablesActionServer("jumperInteract", vehicle)
            else
                RMS_JumperCablesEvent.sendRequest(self, "jumperInteract", vehicle)
            end
        else
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_impossible_to_connect"), 2200)
        end
    end

    -- airBlower
    if vehicle ~= nil and spec.toolKind == "airBlower" then
        local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
        local needsBlowOut = vehicleSpec ~= nil and vehicleSpec.isVehicleNeedBlowOut == true
        local isAlreadyClean = vehicleSpec ~= nil
            and (tonumber(vehicleSpec.radiatorClogging) or 0) <= 0
            and (tonumber(vehicleSpec.airIntakeClogging) or 0) <= 0

        if not needsBlowOut and self.isClient then
            g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_air_blower_cleaning_not_require"), vehicle:getFullName()), 2200)
        elseif isAlreadyClean and self.isClient then
            g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_air_blower_already_clean"), vehicle:getFullName()), 2200)
        end
    end

    if vehicle == nil then
        if spec.toolKind == "airBlower" and self.isClient then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_air_blower_no_vehicle"), 2200)
        elseif spec.toolKind == "greaseGun" and self.isClient then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_grease_gun_no_vehicle"), 2200)
        end
    end
end

---Raycast callback keeping the first vehicle hit
-- @param entityId hitActorId actor hit
-- @param float x hit x position
-- @param float y hit y position
-- @param float z hit z position
-- @param float distance hit distance
-- @param float nx hit normal x
-- @param float ny hit normal y
-- @param float nz hit normal z
-- @param integer subShapeIndex sub shape index
-- @param entityId hitShapeId shape hit
-- @return boolean continueRaycast false to stop the raycast
function rmsHandTools:handToolRaycastCallback(hitActorId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId)
    local spec = ensureSpec(self)
    local vehicle = g_currentMission.nodeToObject[hitActorId] or g_currentMission:getNodeObject(hitActorId)

    if vehicle == nil and hitShapeId ~= nil and hitShapeId ~= 0 then
        local parentId = hitShapeId
        while parentId ~= 0 do
            vehicle = g_currentMission.nodeToObject[parentId] or g_currentMission:getNodeObject(parentId)
            if vehicle ~= nil then
                break
            end
            parentId = getParent(parentId)
        end
    end

    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and distance < (spec.raycastVehicleDistance or math.huge) then
        spec.raycastVehicle = vehicle
        spec.raycastVehicleDistance = distance
        spec.raycastHitX = x
        spec.raycastHitY = y
        spec.raycastHitZ = z
        spec.raycastHitNX = nx
        spec.raycastHitNY = ny
        spec.raycastHitNZ = nz
    end
end


---
-- @param float dt time since last call in ms
function rmsHandTools:onUpdate(dt)
    local spec = ensureSpec(self)
    local carryingPlayer = self:getCarryingPlayer()
    local isLocalOwner = carryingPlayer ~= nil and carryingPlayer.isOwner
    local isUsing = (isLocalOwner and spec.activatePressed) or spec.networkUseActive
    local isOperational = (isLocalOwner and spec.isActive) or spec.networkUseActive

    if spec.toolKind == "jumperCables"
        and self.isServer
        and spec.connectedVehicleA ~= nil
        and spec.connectedVehicleB ~= nil
        and not areVehiclesExternallyConnected(spec.connectedVehicleA, spec.connectedVehicleB) then

        spec.connectedVehicleA = nil
        spec.connectedVehicleB = nil
        updateJumperCablesVisibility(self)
        broadcastJumperCablesState(self, "jumperAutoDisconnected", nil)
    end

    if not isOperational then
        spec.lastAirBlowerHintKey = nil
        setToolSoundState(self, false)
        setAirResistanceSoundState(self, false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end

    if not isUsing then
        spec.lastAirBlowerHintKey = nil
        setToolSoundState(self, false)
        setAirResistanceSoundState(self, false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end

    setToolSoundState(self, spec.toolKind == "airBlower")

    local vehicle = nil
    local targetDistance = 0
    if spec.toolKind == "airBlower" and not isLocalOwner then
        vehicle = normalizeConnectedVehicle(spec.networkTargetVehicle)
        targetDistance = spec.networkTargetDistance
    else
        vehicle = getRaycastVehicle(self, getRaycastDistance())
        targetDistance = spec.raycastVehicleDistance
    end

    if vehicle == nil then
        if spec.toolKind == "airBlower" and isLocalOwner then
            sendHandToolState(self, "use", false, nil, 0)
        end

        spec.lastAirBlowerHintKey = nil
        setActionText(self, spec.activateText)
        setAirResistanceSoundState(self, false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end

    if spec.toolKind == "airBlower" then
        local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
        local needsBlowOut = vehicleSpec ~= nil and vehicleSpec.isVehicleNeedBlowOut == true
        local isAlreadyClean = vehicleSpec ~= nil
            and (tonumber(vehicleSpec.radiatorClogging) or 0) <= 0
            and (tonumber(vehicleSpec.airIntakeClogging) or 0) <= 0
        local vehicleId = tostring(vehicle.uniqueId or vehicle.id or vehicle.rootNode or vehicle:getFullName())
        local hintKey = nil

        if not needsBlowOut then
            hintKey = vehicleId .. ":not_require"
            if spec.lastAirBlowerHintKey ~= hintKey then
                if isLocalOwner then
                    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_air_blower_cleaning_not_require"), vehicle:getFullName()), 2200)
                end
            end
        elseif isAlreadyClean then
            hintKey = vehicleId .. ":already_clean"
            if spec.lastAirBlowerHintKey ~= hintKey then
                if isLocalOwner then
                    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_air_blower_already_clean"), vehicle:getFullName()), 2200)
                end
            end
        end

        spec.lastAirBlowerHintKey = hintKey
        setAirResistanceSoundState(self, true)

        if isLocalOwner then
            sendHandToolState(self, "use", false, vehicle, targetDistance)
        end

        if self.isServer and needsBlowOut then
            vehicle:cleanRadiatorAndAirIntake(dt)
        end

        if self.isClient then
            local currentAirIntakeClogging = vehicleSpec ~= nil and vehicleSpec.airIntakeClogging or 0
            local currentRadiatorClogging = vehicleSpec ~= nil and vehicleSpec.radiatorClogging or 0
            local hasCleaningDust = currentAirIntakeClogging > 0 or currentRadiatorClogging > 0
            local dustScale = math.max((currentAirIntakeClogging + currentRadiatorClogging) / 20, 0.01)
            local dustLifespan = math.clamp((currentAirIntakeClogging + currentRadiatorClogging) * 1200, 600, 1200)

            if spec.dustParticleSystem ~= nil and hasCleaningDust then
                setDustEmitterDistance(self, targetDistance)
                ParticleUtil.setEmitCountScale(spec.dustParticleSystem, dustScale)
                ParticleUtil.setParticleLifespan(spec.dustParticleSystem, dustLifespan)
                ParticleUtil.setEmittingState(spec.dustParticleSystem, true)
            elseif spec.dustParticleSystem ~= nil then
                ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
                resetDustEmitterPosition(self)
            end
        end
    else
        setAirResistanceSoundState(self, false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end
end
