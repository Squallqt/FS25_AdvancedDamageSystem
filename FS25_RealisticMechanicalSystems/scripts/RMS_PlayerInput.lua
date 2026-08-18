-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---On foot field inspection: hold the action while looking at a tracked vehicle

local rmsInspectionVehicle = nil
local rmsInspectionActionId = nil
local rmsInspectionHoldVehicle = nil
local rmsInspectionHoldTime = 0
local rmsInspectionHoldThreshold = 600
local rmsInspectionHoldTriggered = false

local rmsActiveInspectionVehicle = nil
local rmsInspectionProgressPercent = -1
local rmsInspectionMaxDistance = 6.0


---Clears the hold timer of the inspection action
local function rmsResetInspectionHoldState()
    rmsInspectionHoldVehicle = nil
    rmsInspectionHoldTime = 0
    rmsInspectionHoldTriggered = false
end

---Returns the vehicle the player looks at, if RMS tracks it and the player may access it
-- @param table player player
-- @return table? vehicle vehicle that can be inspected
local function rmsGetInspectionVehicleFromTargeter(player)
    local object = nil

    if player.targeter ~= nil then
        local node = player.targeter:getClosestTargetedNodeFromType(PlayerInputComponent)

        if node ~= nil then
            object = g_currentMission:getNodeObject(node)
        end
    end

    if object == nil then
        return nil
    end

    local spec = object.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return nil
    end

    if g_currentMission ~= nil and g_currentMission.accessHandler ~= nil and not g_currentMission.accessHandler:canPlayerAccess(object, player) then
        return nil
    end

    return object
end

---Stops the running inspection and tells the player why
-- @param string? reasonText message shown, none to just hide the notification
local function rmsCancelActiveInspection(reasonText)
    local vehicle = rmsActiveInspectionVehicle
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil then
        local spec = vehicle.spec_RealisticMechanicalSystems
        local inspection = spec.fieldInspection
        RMS_FieldInspectionEvent.send(vehicle, false)

        if inspection ~= nil then
            inspection.isActive = false
            inspection.elapsedTime = 0
            inspection.startTime = 0
            inspection.targetNode = nil
            inspection.targetVehicle = nil
        end
    end

    rmsActiveInspectionVehicle = nil
    rmsInspectionProgressPercent = -1

    if reasonText ~= nil and reasonText ~= "" then
        RMS_Hud.showNotification(reasonText, 1500)
    else
        RMS_Hud.hideNotification()
    end
end

---Ends the inspection and opens the inspection dialog
local function rmsCompleteActiveInspection()
    local vehicle = rmsActiveInspectionVehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        rmsCancelActiveInspection()
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local inspection = spec.fieldInspection
    RMS_FieldInspectionEvent.send(vehicle, false)

    if inspection ~= nil then
        inspection.isActive = false
        inspection.elapsedTime = inspection.duration
        inspection.startTime = 0
        inspection.targetNode = nil
        inspection.targetVehicle = nil
    end

    rmsActiveInspectionVehicle = nil
    rmsInspectionProgressPercent = -1
    RMS_Hud.hideNotification()

    if RMS_InspectionDialog ~= nil then
        RMS_InspectionDialog.show(vehicle)
    end
end

---Advances the inspection, cancelling it when the player looks away, moves off or gets busy
-- @param table inputComponent player input component
-- @param float dt time since last call in ms
local function rmsUpdateActiveInspection(inputComponent, dt)
    local vehicle = rmsActiveInspectionVehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local inspection = spec.fieldInspection
    local player = inputComponent.player

    if inspection == nil or not inspection.isActive then
        rmsCancelActiveInspection()
        return
    end

    if player == nil or not player.isControlled then
        rmsCancelActiveInspection()
        return
    end

    if player:getIsInVehicle() or player:getAreHandsHoldingObject() or player:getIsHoldingHandTool() then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    local currentTargetVehicle = rmsGetInspectionVehicleFromTargeter(player)
    if currentTargetVehicle ~= vehicle then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    if player.rootNode == nil then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    local distance = vehicle:getDistanceToNode(player.rootNode)
    if distance == nil or distance > rmsInspectionMaxDistance then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    inspection.elapsedTime = math.min(inspection.elapsedTime + dt, inspection.duration)

    local percent = math.floor((inspection.elapsedTime / math.max(inspection.duration, 1)) * 100)
    if percent ~= rmsInspectionProgressPercent then
        rmsInspectionProgressPercent = percent
        RMS_Hud.showNotification(string.format(g_i18n:getText("rms_field_inspection_progress"), percent), 250)
    end

    if inspection.elapsedTime >= inspection.duration then
        rmsCompleteActiveInspection()
    end
end

---Starts the inspection once the action has been held long enough
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
local function rmsOnInputFieldInspection(actionName, inputValue, callbackState, isAnalog)
    if rmsActiveInspectionVehicle ~= nil then
        return
    end

    if rmsInspectionVehicle == nil then
        rmsResetInspectionHoldState()
        return
    end

    if inputValue == 0 then
        rmsResetInspectionHoldState()
        return
    end

    if rmsInspectionHoldVehicle ~= rmsInspectionVehicle then
        rmsInspectionHoldVehicle = rmsInspectionVehicle
        rmsInspectionHoldTime = 0
        rmsInspectionHoldTriggered = false
    end

    if rmsInspectionHoldTriggered then
        return
    end

    rmsInspectionHoldTime = rmsInspectionHoldTime + g_currentDt

    if rmsInspectionHoldTime >= rmsInspectionHoldThreshold then
        rmsInspectionHoldTriggered = true

        if rmsInspectionHoldVehicle ~= nil and rmsInspectionHoldVehicle.startFieldVisualInspectionProcess ~= nil then
            local started = rmsInspectionHoldVehicle:startFieldVisualInspectionProcess()

            if started then
                rmsActiveInspectionVehicle = rmsInspectionHoldVehicle
                rmsInspectionProgressPercent = -1
            end
        end

        rmsResetInspectionHoldState()
    end
end

---Offers the inspection action while the player looks at a tracked vehicle on foot
-- @param table inputComponent player input component
-- @param function superFunc super function
-- @param float dt time since last call in ms
local function rmsOnPlayerInputComponentUpdate(inputComponent, superFunc, dt)
    superFunc(inputComponent, dt)

    if not inputComponent.player.isOwner
        or g_inputBinding:getContextName() ~= PlayerInputComponent.INPUT_CONTEXT_NAME
        or rmsInspectionActionId == nil then
        return
    end

    if rmsActiveInspectionVehicle ~= nil then
        g_inputBinding:setActionEventActive(rmsInspectionActionId, false)
        rmsUpdateActiveInspection(inputComponent, dt)
        return
    end

    local previousVehicle = rmsInspectionVehicle
    rmsInspectionVehicle = nil

    local player = inputComponent.player
    if player.isControlled
        and not player:getIsInVehicle()
        and not player:getAreHandsHoldingObject()
        and not player:getIsHoldingHandTool() then
        rmsInspectionVehicle = rmsGetInspectionVehicleFromTargeter(player)
    end

    if rmsInspectionVehicle ~= previousVehicle then
        rmsResetInspectionHoldState()
    end

    local isActive = rmsInspectionVehicle ~= nil
    g_inputBinding:setActionEventActive(rmsInspectionActionId, isActive)

    if isActive then
        g_inputBinding:setActionEventText(rmsInspectionActionId, g_i18n:getText("rms_field_inspection_hold_to_start"))
    else
        rmsResetInspectionHoldState()
    end
end

---Registers the field inspection action on the player
-- @param table inputComponent player input component
local function rmsOnPlayerInputComponentRegisterActionEvents(inputComponent)
    if not inputComponent.player.isOwner then
        return
    end

    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

    local _, eventId = g_inputBinding:registerActionEvent(
        InputAction.RMS_FIELD_INSPECTION,
        inputComponent,
        rmsOnInputFieldInspection,
        true,
        true,
        true,
        true,
        nil,
        true
    )

    rmsInspectionActionId = eventId

    if rmsInspectionActionId ~= nil then
        g_inputBinding:setActionEventActive(rmsInspectionActionId, false)
        g_inputBinding:setActionEventTextPriority(rmsInspectionActionId, GS_PRIO_NORMAL)
    end

    g_inputBinding:endActionEventsModification()
end

PlayerInputComponent.update = Utils.overwrittenFunction(PlayerInputComponent.update, rmsOnPlayerInputComponentUpdate)
PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, rmsOnPlayerInputComponentRegisterActionEvents)
