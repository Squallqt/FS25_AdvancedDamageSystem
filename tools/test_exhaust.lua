MotorState = { OFF = 0, STARTING = 1, ON = 2 }
RMS_VehicleYears = { DEFAULT_YEAR = 2000 }

dofile("FS25_RealisticMechanicalSystems/scripts/RMS_Config.lua")
dofile("FS25_RealisticMechanicalSystems/scripts/core/RMS_Exhaust.lua")

local tests = {}
local assertionCount = 0
local shaderWrites = {}

function setShaderParameter(node, name, a, b, c, d)
    shaderWrites[#shaderWrites + 1] = { node = node, name = name, values = { a, b, c, d } }
end

local function assertTrue(value, message)
    assertionCount = assertionCount + 1
    if not value then
        error(message or "expected true", 2)
    end
end

local function assertFalse(value, message)
    assertTrue(not value, message or "expected false")
end

local function assertEqual(actual, expected, message)
    assertionCount = assertionCount + 1
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

local function assertNear(actual, expected, tolerance, message)
    assertionCount = assertionCount + 1
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.8f, got %.8f", message or "values differ", expected, actual), 2)
    end
end

local function addTest(name, callback)
    tests[#tests + 1] = { name = name, callback = callback }
end

local function readFile(filename)
    local file = assert(io.open(filename, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function calculate(overrides)
    local input = {
        year = 1993,
        peakPowerKw = 150,
        hasDEF = false,
        isMethane = false,
        load = 0,
        lastLoad = 0,
        dt = 100,
        airIntakeClogging = 0,
        serviceLevel = 1,
        engineTemperature = 90,
        isStarting = false,
        preheatSeverity = 0,
        wetStackingLevel = 0,
        sootEffect = 0,
        oilEffect = 0,
        unburntEffect = 0
    }
    for key, value in pairs(overrides or {}) do
        input[key] = value
    end

    return RMS_Exhaust.calculateTargets(input)
end

local function newEffect(node, minScale, maxScale)
    return {
        effectNode = node,
        minRpmColor = { 0.1, 0.2, 0.3, 0.4 },
        maxRpmColor = { 0.5, 0.6, 0.7, 0.8 },
        minRpmScale = minScale,
        maxRpmScale = maxScale,
        xRot = 0.1,
        zRot = 0.2
    }
end

local function newVehicle(options)
    options = options or {}
    local motor = {
        peakMotorPower = options.peakPowerKw or 150,
        getMaxRpm = function()
            return 2000
        end
    }
    local vehicle = {
        motorState = options.motorState or MotorState.ON,
        motorRpm = options.motorRpm or 1000,
        spec_motorized = {
            consumersByFillTypeName = options.consumers or { DIESEL = {} },
            exhaustEffects = options.effects or { newEffect(101, 0.25, 0.95) }
        },
        spec_RealisticMechanicalSystems = {
            year = options.year or 1993,
            dynamicMotorLoad = options.load or 0,
            airIntakeClogging = options.airIntakeClogging or 0,
            serviceLevel = options.serviceLevel or 1,
            rawEngineTemperature = options.engineTemperature or 90,
            preheatColdStartFaultSeverity = options.preheatSeverity or 0,
            isDieselVehicle = options.isDiesel ~= false,
            fuelState = { wetStackingLevel = options.wetStackingLevel or 0 },
            activeEffects = options.activeEffects or {}
        }
    }
    function vehicle:getMotor()
        return motor
    end
    function vehicle:getMotorState()
        return self.motorState
    end
    function vehicle:getMotorRpmReal()
        return self.motorRpm
    end
    RMS_Exhaust.initSpec(vehicle)

    return vehicle
end

addTest("emission era boundaries", function()
    local cases = {
        { 1900, 1.00 }, { 2000, 1.00 },
        { 2001, 0.75 }, { 2005, 0.75 },
        { 2006, 0.55 }, { 2010, 0.55 },
        { 2011, 0.40 }, { 2013, 0.40 },
        { 2014, 0.30 }, { 2026, 0.30 }
    }
    for _, case in ipairs(cases) do
        assertNear(RMS_Exhaust.getEraFactor(case[1]), case[2], 0.000001, "era " .. case[1])
    end
    assertNear(RMS_Exhaust.getEraFactor(nil), 1.00, 0.000001, "default year")
end)

addTest("Stage V year and power boundaries", function()
    assertFalse(RMS_Exhaust.getIsStageV(2026, 18.9), "below particulate-number power range")
    assertFalse(RMS_Exhaust.getIsStageV(2018, 19), "outer range before 2019")
    assertTrue(RMS_Exhaust.getIsStageV(2019, 19), "outer range in 2019")
    assertTrue(RMS_Exhaust.getIsStageV(2019, 55.9), "low outer range")
    assertFalse(RMS_Exhaust.getIsStageV(2019, 56), "middle range before 2020")
    assertTrue(RMS_Exhaust.getIsStageV(2020, 56), "middle range in 2020")
    assertTrue(RMS_Exhaust.getIsStageV(2020, 129.9), "upper middle range")
    assertTrue(RMS_Exhaust.getIsStageV(2019, 130), "high outer range")
    assertTrue(RMS_Exhaust.getIsStageV(2019, 560), "maximum regulated power")
    assertFalse(RMS_Exhaust.getIsStageV(2026, 560.1), "above regulated power range")
end)

addTest("same fault is denser on an older vehicle", function()
    local old = calculate({ year = 1993, sootEffect = 0.65, oilEffect = 0.50, unburntEffect = 0.60 })
    local recent = calculate({ year = 2015, sootEffect = 0.65, oilEffect = 0.50, unburntEffect = 0.60 })
    assertTrue(old.soot > recent.soot, "old soot")
    assertTrue(old.oil > recent.oil, "old oil")
    assertTrue(old.unburnt > recent.unburnt, "old unburnt")
    local floor = RMS_Config.EXHAUST.ERA_BREAKDOWN_FLOOR
    assertNear(recent.soot / old.soot, floor, 0.000001, "recent soot fault floor")
    assertNear(recent.oil / old.oil, floor, 0.000001, "recent oil fault floor")
    assertNear(recent.unburnt / old.unburnt, floor, 0.000001, "recent unburnt fault floor")
end)

addTest("a declared fault reaches the shader alpha range that was visible before", function()
    local config = RMS_Config.EXHAUST
    local targets = calculate({ year = 2015, peakPowerKw = 291, hasDEF = true, sootEffect = 0.80 })
    local saturation = math.min(targets.soot + targets.oil + targets.unburnt, 1)
    local visible = saturation * targets.loadDensityFactor
    local healthyFull = config.HEALTHY_ALPHA_FULL * targets.healthyAlphaFactor
    local alphaFull = healthyFull + (config.SATURATED_ALPHA_FULL - healthyFull) * visible

    assertTrue(alphaFull > 2.0, "fault alpha stays in the range that rendered before")
    assertTrue(targets.soot > 0.40, "a declared fault keeps most of its registry value")
end)

addTest("a healthy recent machine stays invisible", function()
    local config = RMS_Config.EXHAUST
    local targets = calculate({ year = 2015, peakPowerKw = 291, hasDEF = true })
    local saturation = math.min(targets.soot + targets.oil + targets.unburnt, 1)
    local alphaFull = config.HEALTHY_ALPHA_FULL * targets.healthyAlphaFactor
        + (config.SATURATED_ALPHA_FULL - config.HEALTHY_ALPHA_FULL * targets.healthyAlphaFactor)
        * saturation * targets.loadDensityFactor

    assertTrue(alphaFull < 0.05, "healthy modern plume stays invisible")
end)

addTest("DEF affects healthy visibility but not fault channels", function()
    local diesel = calculate({ year = 2015, sootEffect = 0.65, hasDEF = false })
    local def = calculate({ year = 2015, sootEffect = 0.65, hasDEF = true })
    assertNear(def.soot, diesel.soot, 0.000001, "SCR does not filter soot")
    assertNear(def.oil, diesel.oil, 0.000001, "SCR does not filter oil")
    assertNear(def.unburnt, diesel.unburnt, 0.000001, "SCR does not filter unburnt smoke")
    assertNear(def.healthyAlphaFactor, diesel.healthyAlphaFactor * RMS_Config.EXHAUST.DEF_HEALTHY_ALPHA_FACTOR, 0.000001, "DEF healthy plume")
end)

addTest("Stage V particulate control targets soot", function()
    local stageIV = calculate({ year = 2018, peakPowerKw = 150, sootEffect = 0.80, oilEffect = 0.65 })
    local stageV = calculate({ year = 2019, peakPowerKw = 150, sootEffect = 0.80, oilEffect = 0.65 })
    assertFalse(stageIV.isStageV, "2018 profile")
    assertTrue(stageV.isStageV, "2019 profile")
    assertNear(stageV.soot, stageIV.soot * RMS_Config.EXHAUST.STAGE_V.SOOT_FACTOR, 0.000001, "Stage V soot")
    assertNear(stageV.oil, stageIV.oil, 0.000001, "Stage V does not rewrite oil source")
end)

addTest("methane profile suppresses soot without hiding oil or unburnt fuel", function()
    local diesel = calculate({ year = 2015, sootEffect = 0.8, oilEffect = 0.65, unburntEffect = 0.6 })
    local methane = calculate({ year = 2015, sootEffect = 0.8, oilEffect = 0.65, unburntEffect = 0.6, isMethane = true })
    assertNear(methane.soot, diesel.soot * RMS_Config.EXHAUST.METHANE_SOOT_FACTOR, 0.000001, "methane soot")
    assertNear(methane.oil, diesel.oil, 0.000001, "methane oil")
    assertNear(methane.unburnt, diesel.unburnt, 0.000001, "methane unburnt-fuel smoke")
end)

addTest("stable engine load controls soot", function()
    local low = calculate({ load = 0.79, lastLoad = 0.79 })
    local threshold = calculate({ load = 0.80, lastLoad = 0.80 })
    local high = calculate({ load = 1.05, lastLoad = 1.05 })
    assertNear(low.soot, 0, 0.000001, "below load threshold")
    assertNear(threshold.soot, 0, 0.000001, "at load threshold")
    assertNear(high.soot, RMS_Config.EXHAUST.SOOT.LOAD_MAX, 0.000001, "full load smoke")
    assertTrue(high.loadDensityFactor > low.loadDensityFactor, "load density")
end)

addTest("positive load transient creates a short soot target", function()
    local stable = calculate({ load = 0.70, lastLoad = 0.70, dt = 100 })
    local rising = calculate({ load = 0.70, lastLoad = 0.10, dt = 100 })
    local falling = calculate({ load = 0.10, lastLoad = 0.70, dt = 100 })
    assertNear(stable.soot, 0, 0.000001, "stable load")
    assertTrue(rising.soot > 0, "rising load")
    assertNear(falling.soot, 0, 0.000001, "falling load")
end)

addTest("wet stacking uses the existing RMS idle thresholds", function()
    local fuelConfig = RMS_Config.CORE.FUEL_FACTOR_DATA
    local belowThreshold = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0,
        idleTimer = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD - 1,
        load = 0,
        dt = 1000,
        engineTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP,
        isIdle = true,
        isDiesel = true,
        isMotorStarted = true
    })
    local atThreshold = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0,
        idleTimer = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD,
        load = 0,
        dt = 1000,
        engineTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP,
        isIdle = true,
        isDiesel = true,
        isMotorStarted = true
    })
    local warmThreshold = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0,
        idleTimer = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD + 1,
        load = fuelConfig.IDLE_DEPOSIT_LOAD_THRESHOLD,
        dt = 1000,
        engineTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP,
        isIdle = true,
        isDiesel = true,
        isMotorStarted = true
    })
    local coldThreshold = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0,
        idleTimer = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD + 1,
        load = 0,
        dt = 1000,
        engineTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD,
        isIdle = true,
        isDiesel = true,
        isMotorStarted = true
    })
    local repeatedIdle = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0.20,
        idleTimer = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD + 1,
        load = 0,
        dt = 1000,
        engineTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP,
        isIdle = true,
        isDiesel = true,
        isMotorStarted = true
    })
    local fullWarmBuildup = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0,
        idleTimer = fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER,
        load = 0,
        dt = (fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD) * 1000,
        engineTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP,
        isIdle = true,
        isDiesel = true,
        isMotorStarted = true
    })

    assertNear(belowThreshold, 0, 0.000001, "no wet stacking before prolonged idle")
    assertNear(atThreshold, 0, 0.000001, "no threshold jump")
    local oneSecondBuildup = 1 / (fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD)
    assertNear(warmThreshold, oneSecondBuildup, 0.000001, "warm buildup starts progressively after threshold")
    assertNear(coldThreshold, warmThreshold * 2, 0.000001, "cold engine accelerates deposits")
    assertNear(repeatedIdle, 0.20 + oneSecondBuildup, 0.000001, "separate idle periods resume without a threshold jump")
    assertNear(fullWarmBuildup, 1, 0.000001, "continuous warm idle reaches maximum at the existing RMS timer limit")
end)

addTest("wet stacking persists stopped and burns off only warm under load", function()
    local preserved = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0.8,
        isDiesel = true,
        isMotorStarted = false
    })
    local coldLoaded = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0.8,
        idleTimer = 0,
        load = 1,
        dt = 300000,
        engineTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD,
        isIdle = false,
        isDiesel = true,
        isMotorStarted = true
    })
    local warmLoaded = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0.8,
        idleTimer = 0,
        load = 1,
        dt = 300000,
        engineTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP,
        isIdle = false,
        isDiesel = true,
        isMotorStarted = true
    })
    local methane = RMS_Exhaust.calculateWetStackingLevel({
        currentLevel = 0.8,
        isDiesel = false,
        isMotorStarted = true
    })

    assertNear(preserved, 0.8, 0.000001, "engine stop preserves deposits")
    assertNear(coldLoaded, 0.8, 0.000001, "cold load cannot burn deposits")
    assertNear(warmLoaded, 0, 0.000001, "warm rated load clears deposits")
    assertNear(methane, 0, 0.000001, "wet stacking is diesel-only")
end)

addTest("wet stacking adds black smoke and still follows the emission era", function()
    local clean = calculate({ year = 1993, wetStackingLevel = 0 })
    local old = calculate({ year = 1993, wetStackingLevel = 1 })
    local recent = calculate({ year = 2015, wetStackingLevel = 1 })

    assertNear(clean.soot, 0, 0.000001, "clean idle")
    assertNear(old.soot, RMS_Config.EXHAUST.SOOT.WET_STACKING_MAX, 0.000001, "old wet stacking soot")
    assertNear(recent.soot, old.soot * 0.30, 0.000001, "recent wet stacking era factor")
    assertNear(old.oil, 0, 0.000001, "wet stacking is not blue oil smoke")
    assertNear(old.unburnt, 0, 0.000001, "wet stacking renders its observed black carbon")
end)

addTest("air intake and overdue service increase soot independently", function()
    local clean = calculate()
    local clogged = calculate({ airIntakeClogging = 1 })
    local overdue = calculate({ serviceLevel = 0 })
    assertNear(clean.soot, 0, 0.000001, "clean engine")
    assertNear(clogged.soot, RMS_Config.EXHAUST.SOOT.AIR_INTAKE_MAX, 0.000001, "clogged intake")
    assertNear(overdue.soot, RMS_Config.EXHAUST.SOOT.SERVICE_MAX, 0.000001, "overdue service")
end)

addTest("oil fault remains visible at idle and grows under load", function()
    local idle = calculate({ oilEffect = 0.5, load = 0, lastLoad = 0 })
    local loaded = calculate({ oilEffect = 0.5, load = 1, lastLoad = 1 })
    assertNear(idle.oil, 0.5 * RMS_Config.EXHAUST.OIL.BREAKDOWN_MAX * RMS_Config.EXHAUST.OIL.IDLE_BOOST, 0.000001, "idle oil")
    assertNear(loaded.oil, 0.5 * RMS_Config.EXHAUST.OIL.BREAKDOWN_MAX, 0.000001, "loaded oil")
    assertTrue(loaded.loadDensityFactor > idle.loadDensityFactor, "loaded plume density")
end)

addTest("cold start and preheat fault control unburnt fuel", function()
    local warm = calculate({ engineTemperature = 50 })
    local cold = calculate({ engineTemperature = -10 })
    local starting = calculate({ engineTemperature = -10, isStarting = true })
    local preheat = calculate({ engineTemperature = -10, preheatSeverity = 4 })
    assertNear(warm.unburnt, 0, 0.000001, "warm engine")
    assertNear(cold.unburnt, RMS_Config.EXHAUST.UNBURNT.COLD_MAX, 0.000001, "cold engine")
    assertNear(starting.unburnt, 1, 0.000001, "cold cranking clamp")
    assertTrue(preheat.unburnt > cold.unburnt, "preheat failure")
end)

addTest("target values are clamped for combined causes", function()
    local target = calculate({ load = 1.5, lastLoad = 0, airIntakeClogging = 1, serviceLevel = 0, sootEffect = 1, oilEffect = 1, unburntEffect = 1, engineTemperature = -80, isStarting = true, preheatSeverity = 4 })
    assertTrue(target.soot >= 0 and target.soot <= 1, "soot clamp")
    assertTrue(target.oil >= 0 and target.oil <= 1, "oil clamp")
    assertTrue(target.unburnt >= 0 and target.unburnt <= 1, "unburnt clamp")
end)

addTest("runtime smoothing rises quickly and falls progressively", function()
    local vehicle = newVehicle({ activeEffects = { EXHAUST_SOOT = { value = 0.8 } } })
    local target = calculate({ sootEffect = 0.8 }).soot
    RMS_Exhaust.update(vehicle, 100)
    local smoke = vehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    local rising = smoke.soot
    assertTrue(rising > 0, "smoke starts rising")
    assertTrue(rising < target, "rise is smoothed")
    vehicle.spec_RealisticMechanicalSystems.activeEffects = {}
    RMS_Exhaust.update(vehicle, 100)
    assertTrue(smoke.soot < rising, "smoke starts falling")
    assertTrue(smoke.soot > 0, "fall is not abrupt")
end)

addTest("runtime keeps native effects and writes every exhaust node", function()
    local effects = { newEffect(101, 0.20, 0.80), newEffect(102, 0.35, 1.10), newEffect(103, 0.50, 1.30) }
    local vehicle = newVehicle({ effects = effects, activeEffects = { EXHAUST_SOOT = { value = 0.8 } } })
    RMS_Exhaust.update(vehicle, 1000)
    local smoke = vehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertTrue(smoke.isActive, "runtime active")
    assertEqual(#effects, 3, "effect count")
    assertNear(effects[1].minRpmScale, 0.20, 0.000001, "first native minimum scale")
    assertNear(effects[2].maxRpmScale, 1.10, 0.000001, "second native maximum scale")
    assertNear(effects[3].maxRpmScale, 1.30, 0.000001, "third native maximum scale")
    assertNear(effects[1].minRpmColor[1], effects[2].minRpmColor[1], 0.000001, "same red on every node")
    assertNear(effects[2].maxRpmColor[4], effects[3].maxRpmColor[4], 0.000001, "same alpha on every node")
    shaderWrites = {}
    RMS_Exhaust.applyShader(vehicle)
    assertEqual(#shaderWrites, 6, "two shader writes per node")
    for index = 1, #shaderWrites, 2 do
        assertEqual(shaderWrites[index].name, "exhaustColor", "native colour parameter")
        assertEqual(shaderWrites[index + 1].name, "param", "native shape parameter")
    end
end)

addTest("runtime smoke colours match their diagnostic channels", function()
    local sootVehicle = newVehicle({ activeEffects = { EXHAUST_SOOT = { value = 1 } } })
    RMS_Exhaust.update(sootVehicle, 10000)
    local soot = sootVehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertTrue(soot.red < 0.20 and soot.green < 0.20 and soot.blue < 0.20, "soot is dark")

    local oilVehicle = newVehicle({ activeEffects = { EXHAUST_OIL = { value = 1 } } })
    RMS_Exhaust.update(oilVehicle, 10000)
    local oil = oilVehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertTrue(oil.blue > oil.red * 2 and oil.blue > oil.green * 2, "oil is blue")

    local unburntVehicle = newVehicle({ activeEffects = { EXHAUST_UNBURNT = { value = 1 } } })
    RMS_Exhaust.update(unburntVehicle, 10000)
    local unburnt = unburntVehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertTrue(unburnt.red > 0.90 and unburnt.green > 0.90 and unburnt.blue > 0.90, "unburnt is white")
end)

addTest("engine speed interpolates opacity without erasing smoke", function()
    local vehicle = newVehicle({ motorRpm = 0, activeEffects = { EXHAUST_SOOT = { value = 0.8 } } })
    RMS_Exhaust.update(vehicle, 1000)
    local smoke = vehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertTrue(smoke.alphaIdle > 0, "idle smoke remains visible")
    assertTrue(smoke.alphaFull > smoke.alphaIdle, "full-rpm smoke is denser")
    shaderWrites = {}
    RMS_Exhaust.applyShader(vehicle)
    assertNear(shaderWrites[1].values[4], smoke.alphaIdle, 0.000001, "zero-rpm opacity")
    vehicle.motorRpm = 2000
    shaderWrites = {}
    RMS_Exhaust.applyShader(vehicle)
    assertNear(shaderWrites[1].values[4], smoke.alphaFull, 0.000001, "maximum-rpm opacity")
end)

addTest("healthy recent DEF vehicle is almost invisible", function()
    local vehicle = newVehicle({ year = 2015, consumers = { DIESEL = {}, DEF = {} } })
    RMS_Exhaust.update(vehicle, 1000)
    local smoke = vehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertTrue(smoke.hasDEF, "DEF profile detected")
    assertNear(smoke.soot, 0, 0.000001, "healthy soot")
    assertNear(smoke.oil, 0, 0.000001, "healthy oil")
    assertNear(smoke.unburnt, 0, 0.000001, "healthy unburnt")
    assertNear(smoke.alphaIdle, 0.003, 0.000001, "healthy DEF idle alpha")
    assertNear(smoke.alphaFull, 0.012, 0.000001, "healthy DEF full alpha")
end)

addTest("intensity changes opacity without changing causes", function()
    local vehicle = newVehicle({ activeEffects = { EXHAUST_SOOT = { value = 0.8 } } })
    RMS_Config.EXHAUST.INTENSITY = 1
    RMS_Exhaust.update(vehicle, 1000)
    local smoke = vehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    local soot = smoke.soot
    local alpha = smoke.alphaIdle
    local doubleVehicle = newVehicle({ activeEffects = { EXHAUST_SOOT = { value = 0.8 } } })
    RMS_Config.EXHAUST.INTENSITY = 2
    RMS_Exhaust.update(doubleVehicle, 1000)
    local doubleSmoke = doubleVehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertNear(doubleSmoke.soot, soot, 0.000001, "intensity keeps cause")
    assertNear(doubleSmoke.alphaIdle, alpha * 2, 0.000001, "intensity doubles opacity")
    local floorVehicle = newVehicle({ activeEffects = { EXHAUST_SOOT = { value = 0.8 } } })
    RMS_Config.EXHAUST.INTENSITY = 0
    RMS_Exhaust.update(floorVehicle, 1000)
    local floorSmoke = floorVehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    assertNear(floorSmoke.soot, soot, 0.000001, "intensity never changes the cause")
    assertNear(floorSmoke.alphaIdle, alpha, 0.000001, "intensity below the range cannot hide the plume")
    RMS_Config.EXHAUST.INTENSITY = 1
end)

addTest("engine stop restores all native values", function()
    local effect = newEffect(101, 0.25, 0.95)
    local originalMinColour = effect.minRpmColor
    local originalMaxColour = effect.maxRpmColor
    local vehicle = newVehicle({ effects = { effect }, activeEffects = { EXHAUST_OIL = { value = 0.65 } } })
    RMS_Exhaust.update(vehicle, 1000)
    assertTrue(effect.minRpmColor ~= originalMinColour, "RMS owns active colour")
    vehicle.motorState = MotorState.OFF
    RMS_Exhaust.update(vehicle, 100)
    assertFalse(vehicle.spec_RealisticMechanicalSystems.exhaustSmoke.isActive, "inactive with engine stopped")
    assertEqual(effect.minRpmColor, originalMinColour, "native minimum colour restored")
    assertEqual(effect.maxRpmColor, originalMaxColour, "native maximum colour restored")
    assertNear(effect.minRpmScale, 0.25, 0.000001, "native minimum scale restored")
    assertNear(effect.maxRpmScale, 0.95, 0.000001, "native maximum scale restored")
end)

addTest("disabled model restores native effects", function()
    local effect = newEffect(101, 0.25, 0.95)
    local originalMinColour = effect.minRpmColor
    local vehicle = newVehicle({ effects = { effect }, activeEffects = { EXHAUST_OIL = { value = 0.65 } } })
    RMS_Exhaust.update(vehicle, 1000)
    RMS_Config.EXHAUST.ENABLED = false
    RMS_Exhaust.update(vehicle, 100)
    assertEqual(effect.minRpmColor, originalMinColour, "native colour restored when disabled")
    assertFalse(vehicle.spec_RealisticMechanicalSystems.exhaustSmoke.isActive, "disabled state")
    RMS_Config.EXHAUST.ENABLED = true
end)

addTest("vehicle without exhaust effects is ignored safely", function()
    local vehicle = newVehicle({ effects = {} })
    RMS_Exhaust.update(vehicle, 100)
    assertFalse(vehicle.spec_RealisticMechanicalSystems.exhaustSmoke.isActive, "no exhaust effect")
end)

addTest("identical synchronized inputs are deterministic", function()
    local input = { year = 2015, peakPowerKw = 280, hasDEF = true, load = 0.93, lastLoad = 0.40, dt = 100, airIntakeClogging = 0.35, serviceLevel = 0.72, engineTemperature = 35, sootEffect = 0.65, oilEffect = 0.5, unburntEffect = 0.3 }
    local host = RMS_Exhaust.calculateTargets(input)
    local client = RMS_Exhaust.calculateTargets(input)
    assertNear(host.soot, client.soot, 0, "soot determinism")
    assertNear(host.oil, client.oil, 0, "oil determinism")
    assertNear(host.unburnt, client.unburnt, 0, "unburnt determinism")
    assertNear(host.healthyAlphaFactor, client.healthyAlphaFactor, 0, "profile determinism")
end)

addTest("breakdown registry smoke mappings are complete", function()
    local registry = readFile("FS25_RealisticMechanicalSystems/scripts/core/RMS_BreakdownRegistry.lua")
    local rawCount = select(2, registry:gsub('id%s*=%s*"EXHAUST_[A-Z]+"', ""))
    local parsedCount = 0
    for channel, value in registry:gmatch('{%s*id%s*=%s*"(EXHAUST_[A-Z]+)"%s*,%s*value%s*=%s*([%d%.]+)%s*,%s*aggregation%s*=%s*"max"%s*}') do
        parsedCount = parsedCount + 1
        if channel ~= "EXHAUST_SOOT" and channel ~= "EXHAUST_OIL" and channel ~= "EXHAUST_UNBURNT" then
            error("unknown exhaust channel: " .. channel)
        end
        local number = tonumber(value)
        if number == nil or number <= 0 or number > 1 then
            error("invalid exhaust effect value: " .. tostring(value))
        end
    end
    assertEqual(rawCount, 27, "registry mapping count")
    assertEqual(parsedCount, rawCount, "all registry mappings use max aggregation and numeric values")
    assertFalse(registry:find("DARK_EXHAUST_EFFECT", 1, true) ~= nil, "legacy dark-smoke effect removed")
    local coolantStart = assert(registry:find("COOLANT_LEAK =", 1, true), "coolant breakdown")
    local coolantEnd = assert(registry:find("FUEL_PUMP_MALFUNCTION =", coolantStart, true), "next breakdown")
    assertFalse(registry:sub(coolantStart, coolantEnd):find("EXHAUST_", 1, true) ~= nil, "external coolant leak does not imply combustion smoke")

    local breakdowns = readFile("FS25_RealisticMechanicalSystems/scripts/core/RMS_SpecBreakdowns.lua")
    assertTrue(breakdowns:find('id = "EXHAUST_OIL"', 1, true) ~= nil, "engine wear creates oil smoke")
    assertTrue(breakdowns:find("(1 - condition) ^ 2", 1, true) ~= nil, "engine-wear smoke follows condition")
end)

addTest("runtime and multiplayer wiring expose every model input", function()
    local specialization = readFile("FS25_RealisticMechanicalSystems/scripts/core/RMS_Specialization.lua")
    local saveLoad = readFile("FS25_RealisticMechanicalSystems/scripts/core/RMS_SpecSaveLoad.lua")
    local streams = readFile("FS25_RealisticMechanicalSystems/scripts/core/RMS_SpecStreams.lua")
    local vehicleState = readFile("FS25_RealisticMechanicalSystems/scripts/core/RMS_SpecVehicleState.lua")
    local settingsSync = readFile("FS25_RealisticMechanicalSystems/events/RMS_SettingsSyncEvent.lua")

    assertTrue(specialization:find('source(g_currentModDirectory .. "scripts/core/RMS_Exhaust.lua")', 1, true) ~= nil, "model source order")
    assertTrue(saveLoad:find("RMS_Exhaust.initSpec(self)", 1, true) ~= nil, "model initialization")
    assertTrue(specialization:find("RMS_Exhaust.update(self, updateDt)", 1, true) ~= nil, "client model update")
    assertTrue(specialization:find("RMS_Exhaust.applyShader(self)", 1, true) ~= nil, "post-update shader authority")
    assertTrue(specialization:find("spec.year = RMS_VehicleYears.getYear(storeItem)", 1, true) ~= nil, "production-year resolution")
    assertTrue(streams:find("spec.dynamicMotorLoad", 1, true) ~= nil, "load synchronization")
    assertTrue(streams:find("spec.rawEngineTemperature", 1, true) ~= nil, "temperature synchronization")
    assertTrue(streams:find("spec.airIntakeClogging", 1, true) ~= nil, "air-intake synchronization")
    assertTrue(streams:find("spec.serviceLevel", 1, true) ~= nil, "service synchronization")
    assertTrue(streams:find("spec.preheatColdStartFaultSeverity", 1, true) ~= nil, "preheat synchronization")
    assertTrue(streams:find("spec.activeBreakdowns", 1, true) ~= nil, "breakdown synchronization")
    assertTrue(streams:find("fuelState.wetStackingLevel", 1, true) ~= nil, "wet-stacking synchronization")
    assertTrue(saveLoad:find("#wetStackingLevel", 1, true) ~= nil, "wet-stacking persistence")
    assertTrue(specialization:find('baseKey .. "#wetStackingLevel"', 1, true) ~= nil, "wet-stacking savegame schema")
    assertTrue(vehicleState:find("RMS_Exhaust.calculateWetStackingLevel", 1, true) ~= nil, "existing fuel-state update owns wet stacking")
    assertTrue(vehicleState:find("fuelState.idleTimer = 0", 1, true) ~= nil, "engine stop resets only the consecutive-idle timer")
    assertTrue(streams:find("self:recalculateAndApplyEffects()", 1, true) ~= nil, "client effect recalculation")
    assertTrue(settingsSync:find("self.exhaustSmokeEnabled", 1, true) ~= nil, "enabled-setting synchronization")
    assertTrue(settingsSync:find("self.exhaustSmokeIntensity", 1, true) ~= nil, "intensity-setting synchronization")
end)

local failures = {}
for _, test in ipairs(tests) do
    local ok, message = pcall(test.callback)
    if not ok then
        failures[#failures + 1] = test.name .. ": " .. tostring(message)
    end
end

if #failures > 0 then
    io.stderr:write(string.format("Exhaust tests failed: %d/%d\n", #failures, #tests))
    for _, failure in ipairs(failures) do
        io.stderr:write("- " .. failure .. "\n")
    end
    os.exit(1)
end

print(string.format("Exhaust tests passed: %d cases, %d assertions", #tests, assertionCount))
