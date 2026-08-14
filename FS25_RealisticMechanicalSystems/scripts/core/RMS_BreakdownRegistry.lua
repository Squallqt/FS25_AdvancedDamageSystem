-- ==========================================================
--                    REGISTRY VOCABULARY
-- ==========================================================

RMS_Breakdowns.DASHBOARD = {
    ENGINE = "engine",
    WARNING = "warning",
    TRANSMISSION = "transmission",
    BRAKES = "brakes",
    BATTERY = "battery",
    COOLANT = "coolant",
    SERVICE = "service",
    OIL = "oil",
    PREHEAT = "preheat"
}

RMS_Breakdowns.COLORS = {
    DEFAULT = Dashboard.COLORS.GREY,
    COOL = { 0.0097, 0.4287, 0.6445, 1 },
    WARNING  = { 1, 0.4287, 0.0006, 1 },
    CRITICAL = {0.8069, 0.0097, 0.0097, 1}
}

local color = RMS_Breakdowns.COLORS
local db = RMS_Breakdowns.DASHBOARD

local glowPlugFailureIndicator = {
    id = db.PREHEAT,
    color = color.WARNING,
    switchOn = function(vehicle)
        return vehicle ~= nil and vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()
    end,
    switchOff = function(vehicle)
        return vehicle == nil or vehicle.getIsMotorStarted == nil or not vehicle:getIsMotorStarted()
    end,
    blinkWhileActive = true
}

RMS_Breakdowns.COLOR_PRIORITY = {
    [color.CRITICAL] = 3,
    [color.WARNING]  = 2,
    [color.COOL]     = 1,
    [color.DEFAULT]  = 0
}

-- ==========================================================
--                    BREAKDOWN REGISTRY
-- ==========================================================

local getIsElectricVehicle = RMS_Utils.getIsElectricVehicle
local hasCVTAddon = RMS_Utils.hasCVTAddon

local systems = RealisticMechanicalSystems.SYSTEMS

RMS_Breakdowns.PARTS = {
    VEHICLE = "rms_breakdowns_part_vehicle",
    CONSUMABLES = "rms_breakdowns_part_consumables",
    ENGINE = "rms_breakdowns_part_engine",
    BATTERY = "rms_breakdowns_part_battery",
    GLOW_PLUGS = "rms_breakdowns_part_glow_plugs",
    ECU = "rms_breakdowns_part_ecu",
    WIRING = "rms_breakdowns_part_wiring",
    ALTERNATOR_REGULATOR = "rms_breakdowns_part_alternator_regulator",
    TURBOCHARGER = "rms_breakdowns_part_turbocharger",
    OIL_PUMP = "rms_breakdowns_part_oil_pump",
    VALVE_TRAIN = "rms_breakdowns_part_valve_train",
    CLUTCH = "rms_breakdowns_part_clutch",
    SYNCHRONIZER = "rms_breakdowns_part_synchronizer",
    POWERSHIFT_HYDRAULIC_PUMP = "rms_breakdowns_part_powershift_hydraulic_pump",
    CVT_CHAIN = "rms_breakdowns_part_cvt_chain",
    CVT_HYDRAULIC_CONTROL_VALVE = "rms_breakdowns_part_cvt_hydraulic_control_valve",
    CVT = "rms_breakdowns_part_cvt",
    TRANSMISSION_THERMOSTAT = "rms_breakdowns_part_transmission_thermostat",
    HYDRAULIC_PUMP = "rms_breakdowns_part_hydraulic_pump",
    HYDRAULIC_CYLINDER = "rms_breakdowns_part_hydraulic_cylinder",
    HYDRAULIC_HOSE = "rms_breakdowns_part_hydraulic_hose",
    HYDRAULIC_FILTER = "rms_breakdowns_part_hydraulic_filter",
    HYDRAULIC_OIL_COOLER = "rms_breakdowns_part_hydraulic_oil_cooler",
    HYDRAULIC_SPOOL_VALVE = "rms_breakdowns_part_hydraulic_spool_valve",
    BRAKE_SYSTEM = "rms_breakdowns_part_brake_system",
    WHEEL_BEARING = "rms_breakdowns_part_wheel_bearing",
    STEERING_LINKAGE = "rms_breakdowns_part_steering_linkage",
    TRACK_TENSIONER = "rms_breakdowns_part_track_tensioner",
    THERMOSTAT = "rms_breakdowns_part_thermostat",
    COOLING_SYSTEM = "rms_breakdowns_part_cooling_system",
    FAN_CLUTCH = "rms_breakdowns_part_fan_clutch",
    FUEL_PUMP = "rms_breakdowns_part_fuel_pump",
    FUEL_INJECTORS = "rms_breakdowns_part_fuel_injectors",
    FUEL_FILTER = "rms_breakdowns_part_fuel_filter",
    FUEL_LINE = "rms_breakdowns_part_fuel_line",
    PTO_CLUTCH = "rms_breakdowns_part_pto_clutch",
    PTO_OUTPUT_SHAFT = "rms_breakdowns_part_pto_output_shaft"
}

local parts = RMS_Breakdowns.PARTS

local breakdownPriceMultipliers = {
    ECU_MALFUNCTION = 0.60,
    CORRODED_WIRING = 0.45,
    BATTERY_SULFATION = 0.50,
    GLOW_PLUG_FAILURE = 0.45,
    ALTERNATOR_REGULATOR_FAILURE = 0.75,
    TURBOCHARGER_MALFUNCTION = 1.00, -- 1% price
    OIL_PUMP_MALFUNCTION = 1.50,
    VALVE_TRAIN_MALFUNCTION = 1.60,
    MANUAL_TRANSMISSION_CLUTCH_WEAR = 1.30,
    MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = 1.10,
    POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION = 2.40,
    CVT_CHAIN_WEAR = 2.60,
    CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = 2.80,
    CVT_ADDON_MALFUNCTION = 3.0,
    TRANSMISSION_THERMOSTAT_MALFUNCTION = 1.20,
    HYDRAULIC_PUMP_MALFUNCTION = 0.90,
    HYDRAULIC_CYLINDER_INTERNAL_LEAK = 1.0,
    HYDRAULIC_HOSE_EXTERNAL_LEAK = 0.45,
    HYDRAULIC_FILTER_CLOGGING = 0.35,
    HYDRAULIC_OIL_COOLER_MALFUNCTION = 0.65,
    HYDRAULIC_SPOOL_VALVE_MALFUNCTION = 0.75,
    BRAKE_MALFUNCTION = 0.35,
    BEARING_WEAR = 0.55,
    STEERING_LINKAGE_WEAR = 0.45,
    TRACK_TENSIONER_MALFUNCTION = 0.80,
    THERMOSTAT_MALFUNCTION = 0.50,
    COOLANT_LEAK = 0.80,
    FAN_CLUTCH_FAILURE = 0.65,
    FUEL_PUMP_MALFUNCTION = 0.55,
    FUEL_INJECTOR_MALFUNCTION = 0.80,
    FUEL_FILTER_CLOGGING = 0.35,
    FUEL_LINE_AIR_LEAK = 0.45,
    PTO_CLUTCH_WEAR = 1.30,
    PTO_OUTPUT_BEARING_WEAR = 0.60,
    PTO_ENGAGEMENT_VALVE_MALFUNCTION = 0.75,
}

local breakdownProgressMultipliers = {
    ECU_MALFUNCTION = 1.00, -- 3.5 hours
    CORRODED_WIRING = 0.9,
    BATTERY_SULFATION = 1.4,
    GLOW_PLUG_FAILURE = 1.0,
    ALTERNATOR_REGULATOR_FAILURE = 1.1,
    TURBOCHARGER_MALFUNCTION = 1.1,
    OIL_PUMP_MALFUNCTION = 1.3,
    VALVE_TRAIN_MALFUNCTION = 1.4,
    MANUAL_TRANSMISSION_CLUTCH_WEAR = 1.00,
    MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = 1.3,
    POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION = 1.1,
    CVT_CHAIN_WEAR = 1.2,
    CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = 1.1,
    CVT_ADDON_MALFUNCTION = 1.4,
    TRANSMISSION_THERMOSTAT_MALFUNCTION = 1.3,
    HYDRAULIC_PUMP_MALFUNCTION = 1.1,
    HYDRAULIC_CYLINDER_INTERNAL_LEAK = 0.6,
    HYDRAULIC_HOSE_EXTERNAL_LEAK = 0.8,
    HYDRAULIC_FILTER_CLOGGING = 1.2,
    HYDRAULIC_OIL_COOLER_MALFUNCTION = 0.9,
    HYDRAULIC_SPOOL_VALVE_MALFUNCTION = 1.1,
    BRAKE_MALFUNCTION = 0.9,
    BEARING_WEAR = 1.2,
    STEERING_LINKAGE_WEAR = 1.2,
    TRACK_TENSIONER_MALFUNCTION = 1.3,
    THERMOSTAT_MALFUNCTION = 1.4,
    COOLANT_LEAK = 0.6,
    FAN_CLUTCH_FAILURE = 0.9,
    FUEL_PUMP_MALFUNCTION = 1.1,
    FUEL_INJECTOR_MALFUNCTION = 1.1,
    FUEL_FILTER_CLOGGING = 1.2,
    FUEL_LINE_AIR_LEAK = 0.8,
    PTO_CLUTCH_WEAR = 1.00,
    PTO_OUTPUT_BEARING_WEAR = 1.20,
    PTO_ENGAGEMENT_VALVE_MALFUNCTION = 1.10,
}

local function getBreakdownFactorWeightPercent(vehicle, systemName, ...)
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return 0
    end

    local factorStats = vehicle.spec_RealisticMechanicalSystems.factorStats
    if type(factorStats) ~= "table" then
        return 0
    end

    local targetSystem = systemName
    if type(targetSystem) == "string" and systems[targetSystem] ~= nil then
        targetSystem = systems[targetSystem]
    end

    local systemKey = RMS_Utils ~= nil and RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, targetSystem) or nil
    if systemKey == nil or systemKey == "" then
        systemKey = string.lower(tostring(targetSystem or ""))
    end

    local systemStats = factorStats[systemKey]
    if type(systemStats) ~= "table" then
        return 0
    end

    local requestedAliases = {}
    local rawArgs = {...}
    for _, arg in ipairs(rawArgs) do
        if type(arg) == "table" then
            for _, alias in ipairs(arg) do
                if alias ~= nil then
                    table.insert(requestedAliases, tostring(alias))
                end
            end
        elseif arg ~= nil then
            table.insert(requestedAliases, tostring(arg))
        end
    end

    if #requestedAliases == 0 then
        return 0
    end

    local factorKeys = RealisticMechanicalSystems.FACTOR_STATS_KEYS
    local numerator = 0
    local denominator = 0
    for statKey, statValue in pairs(systemStats) do
        if factorKeys[statKey] then
            local numericValue = math.max(tonumber(statValue) or 0, 0)
            denominator = denominator + numericValue
            for _, alias in ipairs(requestedAliases) do
                if statKey == alias then
                    numerator = numerator + numericValue
                    break
                end
            end
        end
    end

    if denominator <= 0 or numerator <= 0 then
        return 0
    end

    return math.max((numerator / denominator) * 100, 0)
end

local BREAKDOWN_SECONDARY_FACTOR_WEIGHT = 0.35
local BREAKDOWN_FALLBACK_WEIGHT = 1.0

local function getBreakdownProbabilityWeightPercent(vehicle, systemName, primaryAliases, secondaryAliases, fallbackWeight, secondaryWeight)
    local resolvedFallbackWeight = math.max(tonumber(fallbackWeight) or BREAKDOWN_FALLBACK_WEIGHT, 0)
    local resolvedSecondaryWeight = math.max(tonumber(secondaryWeight) or BREAKDOWN_SECONDARY_FACTOR_WEIGHT, 0)

    local primaryWeight = getBreakdownFactorWeightPercent(vehicle, systemName, primaryAliases)
    local secondaryWeightPercent = getBreakdownFactorWeightPercent(vehicle, systemName, secondaryAliases)
    local weightedPercent = primaryWeight + secondaryWeightPercent * resolvedSecondaryWeight

    if weightedPercent <= 0 then
        return resolvedFallbackWeight
    end

    return math.max(weightedPercent, resolvedFallbackWeight)
end

local function isHydraulicBreakdownApplicable(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem.categoryName == "TRUCKS" then return false end
    local vtype = vehicle.type.name
    local spec = vehicle.spec_RealisticMechanicalSystems
    return vtype ~= "car" and vtype ~= "carFillable" and vtype ~= "motorbike" and spec.year >= 1960
end

local function isPtoBreakdownApplicable(vehicle)
    return RMS_Utils.hasPtoOutputCapability(vehicle)
end

RMS_Breakdowns.BreakdownRegistry = {

--------------------- NOT SELECTEBLE BREAKDOWNS (does not happen by chance, but is the result of various conditions) ---------------------

    GENERAL_WEAR = {
        isSelectable = false,
        part = parts.VEHICLE,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 0.0
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_permanent",
                description = "rms_breakdowns_general_wear_stage1_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {},
                indicators = {}
            }
        }
    },

    COLD_ENGINE = {
        system = systems.ENGINE,
        part = parts.ENGINE,
        isSelectable = false,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 0.0
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_permanent",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    {
                        id = "ENGINE_HARD_START_MODIFIER",
                        value = 0,
                        aggregation = "max",
                        extraData = {timer = 0, status = 'IDLE'}
                    }
                },
                indicators = {}
            }
        }
    },

    DEAD_BATTERY = {
        system = systems.ELECTRICAL,
        part = parts.BATTERY,
        isSelectable = false,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 0.0
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_permanent",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_FAILURE", value = 1.0, extraData = {starter = false, message = "rms_breakdowns_dead_battery_message", reason = "BREAKDOWN", disableAi = true}, aggregation = "boolean_or"},
                    { id = "LIGHTS_FAILURE", value = 1.0, aggregation = "boolean_or" }
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    VOLTAGE_SAG = {
        system = systems.ELECTRICAL,
        part = parts.VEHICLE,
        isSelectable = false,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 0.0
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_permanent",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "LIGHTS_FLICKER_CHANCE", value = 0.1, extraData = {timer = 0, status = 'IDLE', duration = 200, maskBackup = 0}, aggregation = "min"},
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 1, aggregation = "min", extraData = {status = 'IDLE'} },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, extraData = { timer = 0, status = 'IDLE', message = "rms_breakdowns_voltage_sag_message"}},
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    AIRINTAKE_CLOGGING = {
        system = systems.ENGINE,
        part = parts.VEHICLE,
        isSelectable = false,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            if spec == nil then return end
            if spec.isVehicleNeedBlowOut then
                return true
            end
            return false
        end,
        probability = function(vehicle)
            return 0.0
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum"},
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.06, aggregation = "sum" },

                },
                indicators = {
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.06, aggregation = "sum"},
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.12, aggregation = "sum" },

                },
                indicators = {
                }
            },
                        {
                severity = "rms_breakdowns_severity_major",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum"},
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.18, aggregation = "sum" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.05, aggregation = "sum" }
                },
                indicators = {
                }
            }
        }
    },

    STRESS_OVERLOAD = {
        part = parts.VEHICLE,
        isSelectable = false,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 0.0
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {},
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "EMPTY_EFFECT", value = 1.0, aggregation = "boolean_or",  extraData = {message = "rms_breakdowns_overload_breakdown_stage2_message", reason = "BREAKDOWN", disableAi = true, criticalOverload = true}}
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
        }
    },

    MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES = {
        isSelectable = false,
        part = parts.CONSUMABLES,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 1.0   
        end,
        isCanProgress = function(vehicle)
            return true
        end,
        stages = {
            {
                severity = "",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 5.0,
                repairPrice = 0.0,
                effects = {
                    { id = "CONDITION_WEAR_MODIFIER", value = 0.33, aggregation = 'sum' },
                    { id = "SERVICE_WEAR_MODIFIER", value = 0.33, aggregation = 'sum' }
                }
            },
            {
                severity = "",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "SELF_DISAPPEARING_BREAKDOWN_EFFECT", value = 1.0, aggregation = 'boolean_or', extraData = {breakdownId = "MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES"} }
                }
            },   
        },
    },

    OVERHEAT_PROTECTION = {
        isSelectable = false,
        system = systems.ENGINE,
        part = parts.VEHICLE,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 1.0   
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage1_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_LIMP_EFFECT", value = -0.2, aggregation = "min", extraData = {reason = "OVERHEAT", message = "rms_breakdowns_overheat_protection_stage1_message", disableAi = true } },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    }
                }
            },            
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage2_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_LIMP_EFFECT", value = -0.5, aggregation = "min", extraData = {reason = "OVERHEAT", message = "rms_breakdowns_overheat_protection_stage2_message", disableAi = true }  },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    }
                }
            },
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage3_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_LIMP_EFFECT", value = -0.8, aggregation = "min", extraData = {reason = "OVERHEAT", message = "rms_breakdowns_overheat_protection_stage3_message", disableAi = true } },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    }
                }
            },
            {
                severity = "rms_breakdowns_severity_shutdown",
                description = "rms_breakdowns_overheat_protection_stage4_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                     { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = false, message = "rms_breakdowns_overheat_protection_stage4_message", reason = "OVERHEAT", disableAi = true } },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    }
                }
            }
        }
    },

    ENGINE_JAM = {
        isSelectable = false,
        system = systems.ENGINE,
        part = parts.ENGINE,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return 1.0   
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_engine_jam_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0.0,
                repairPrice = 20.0,
                effects = {
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = false, message = "rms_breakdowns_engine_jam_stage1_message", reason = "OVERHEAT", disableAi = true} },
                },
                indicators = {
                    {  
                        id = db.ENGINE,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    }
                }
            }
        }
    },
    

-------------------------------------------- SELECTABLE -----------------------------------------

    -- electrical
    ECU_MALFUNCTION = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.ECU,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            if spec.year >= 2000 and not getIsElectricVehicle(vehicle) then
                return true
            end
            return false
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ELECTRICAL, {"ohf"}, {"crf", "idfg", "sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_ecu_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ECU_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.ECU_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum"},
                    { id = "EXHAUST_SOOT", value = 0.25, aggregation = "max" },
                },
                indicators = {
                    {  
                        id = db.ENGINE,
                        color = color.WARNING,
                        switchOn = function(vehicle)
                            if vehicle.spec_motorized and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() > 0.95 then
                                return true
                            end
                            return false
                        end,
                        switchOff = function(vehicle)
                            if vehicle.spec_motorized and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() <= 0.50 then
                                return true
                            end
                            return false
                        end,
                    }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_ecu_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ECU_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.ECU_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.20, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum" },
                    { id = "EXHAUST_SOOT", value = 0.45, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_ecu_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ECU_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.ECU_MALFUNCTION,
                effects = { 
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.5, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_SOOT", value = 0.80, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_ecu_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.ECU_MALFUNCTION,
                effects = { 
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or",  extraData = {starter = true, message = "rms_breakdowns_ecu_malfunction_stage4_message", reason = "BREAKDOWN", disableAi = true}} 
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CORRODED_WIRING = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.WIRING,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return spec.year >= 2000 and vehicle.spec_lights ~= nil
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ELECTRICAL, {"wef"}, {"sf", "ltf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_corroded_wiring_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CORRODED_WIRING,
                repairPrice = 1.0 * breakdownPriceMultipliers.CORRODED_WIRING,
                effects = {
                    { id = "LIGHTS_FLICKER_CHANCE", value = 1.0, extraData = {timer = 0, status = 'IDLE', duration = 200, maskBackup = 0}, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 1.0, extraData = { timer = 0, status = 'IDLE'}, aggregation = "min"}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate", 
                description = "rms_breakdowns_corroded_wiring_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CORRODED_WIRING,
                repairPrice = 2.0 * breakdownPriceMultipliers.CORRODED_WIRING,
                effects = {
                    { id = "LIGHTS_FLICKER_CHANCE", value = 0.33, extraData = {timer = 0, status = 'IDLE', duration = 300, maskBackup = 0}, aggregation = "min" },
                    { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 5, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 0.33, extraData = { timer = 0, status = 'IDLE'}, aggregation = "min"}
                },
                inspection = {
                    { additional = "rms_inspection_hint_corroded_wiring_stage2" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_corroded_wiring_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CORRODED_WIRING,
                repairPrice = 4.0 * breakdownPriceMultipliers.CORRODED_WIRING,
                effects = { 
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum"},
                    { id = "LIGHTS_FAILURE", value = 1.0, aggregation = "boolean_or" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 8, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 0.1, extraData = { timer = 0, status = 'IDLE'}, aggregation = "min"}
                },
                inspection = {
                    { additional = "rms_inspection_hint_corroded_wiring_stage3" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_corroded_wiring_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.CORRODED_WIRING,
                effects = { 
                    { id = "LIGHTS_FAILURE", value = 1.0, aggregation = "boolean_or" },
                    { id = "ENGINE_FAILURE", value = 1.0, extraData = {starter = false, message = "rms_breakdowns_corroded_wiring_stage4_message", reason = "BREAKDOWN", disableAi = true}, aggregation = "boolean_or"} 
                },
                inspection = {
                    { additional = "rms_inspection_hint_corroded_wiring_stage4" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    BATTERY_SULFATION = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.BATTERY,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ELECTRICAL, {"crf", "idfg"}, {"sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_battery_sulfation_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.BATTERY_SULFATION,
                repairPrice = 1.0 * breakdownPriceMultipliers.BATTERY_SULFATION,
                effects = {
                    { id = "BATTERY_HEALTH_MODIFIER", value = -0.3, aggregation = "min"},

                },
                inspection = {
                    { additional = "rms_inspection_hint_battery_sulfation_stage1" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate", 
                description = "rms_breakdowns_battery_sulfation_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.BATTERY_SULFATION,
                repairPrice = 2.0 * breakdownPriceMultipliers.BATTERY_SULFATION,
                effects = {
                    { id = "BATTERY_HEALTH_MODIFIER", value = -0.6, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                },
                inspection = {
                    { additional = "rms_inspection_hint_battery_sulfation_stage2" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_battery_sulfation_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.BATTERY_SULFATION,
                repairPrice = 4.0 * breakdownPriceMultipliers.BATTERY_SULFATION,
                effects = { 
                    { id = "BATTERY_HEALTH_MODIFIER", value = -0.9, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                },
                inspection = {
                    { additional = "rms_inspection_hint_battery_sulfation_stage3" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_battery_sulfation_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.BATTERY_SULFATION,
                effects = { 
                    { id = "BATTERY_HEALTH_MODIFIER", value = -1.0, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 9, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                },
                inspection = {
                    { additional = "rms_inspection_hint_battery_sulfation_stage4" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    GLOW_PLUG_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.GLOW_PLUGS,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ELECTRICAL, {"crf", "idfg"}, {"sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_glow_plug_failure_stage1_description",
                detectionChance = 0.5,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GLOW_PLUG_FAILURE,
                repairPrice = 1.0 * breakdownPriceMultipliers.GLOW_PLUG_FAILURE,
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 1, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = "IDLE" } }
                },
                inspection = {
                    { additional = "rms_inspection_hint_glow_plug_failure_stage1" }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_glow_plug_failure_stage2_description",
                detectionChance = 0.75,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GLOW_PLUG_FAILURE,
                repairPrice = 2.0 * breakdownPriceMultipliers.GLOW_PLUG_FAILURE,
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 2, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = "IDLE" } },
                    { id = "GLOW_PLUG_COLD_IDLE_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, period = 1800 } }
                },
                inspection = {
                    { additional = "rms_inspection_hint_glow_plug_failure_stage2" }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_glow_plug_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GLOW_PLUG_FAILURE,
                repairPrice = 4.0 * breakdownPriceMultipliers.GLOW_PLUG_FAILURE,
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 3, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 8, aggregation = "max", extraData = { timer = 0, status = "IDLE" } },
                    { id = "GLOW_PLUG_COLD_IDLE_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1500 } }
                },
                inspection = {
                    { additional = "rms_inspection_hint_glow_plug_failure_stage3" }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_glow_plug_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.GLOW_PLUG_FAILURE,
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 4, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 8, aggregation = "max", extraData = { timer = 0, status = "IDLE", blockStart = true } },
                    { id = "GLOW_PLUG_COLD_IDLE_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1500 } }
                },
                inspection = {
                    { additional = "rms_inspection_hint_glow_plug_failure_stage4" }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            }
        }
    },

    ALTERNATOR_REGULATOR_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.ALTERNATOR_REGULATOR,
        isApplicable = function(vehicle)
            return true
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ELECTRICAL, {"ohf", "crf", "idfg"}, {"ltf", "sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_alternator_regulator_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ALTERNATOR_REGULATOR_FAILURE,
                repairPrice = 1.0 * breakdownPriceMultipliers.ALTERNATOR_REGULATOR_FAILURE,
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_alternator_regulator_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ALTERNATOR_REGULATOR_FAILURE,
                repairPrice = 2.0 * breakdownPriceMultipliers.ALTERNATOR_REGULATOR_FAILURE,
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.5, aggregation = "min" },
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 2.0, extraData = { timer = 0, status = 'IDLE'}, aggregation = "min"}
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_alternator_regulator_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ALTERNATOR_REGULATOR_FAILURE,
                repairPrice = 4.0 * breakdownPriceMultipliers.ALTERNATOR_REGULATOR_FAILURE,
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.7, aggregation = "min" },
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 1.0, extraData = { timer = 0, status = 'IDLE'}, aggregation = "min"}
                },
                inspection = {
                    { additional = "rms_inspection_hint_alternator_regulator_failure_stage3" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_alternator_regulator_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.ALTERNATOR_REGULATOR_FAILURE,
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -1.0, aggregation = "min" },
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 0.3, extraData = { timer = 0, status = 'IDLE'}, aggregation = "min"}
                },
                inspection = {
                    { additional = "rms_inspection_hint_alternator_regulator_failure_stage4" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    -- engine
    TURBOCHARGER_MALFUNCTION = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.TURBOCHARGER,
        isApplicable = function(vehicle)
            local motor = vehicle:getMotor()
            return (motor.peakMotorPower or 0) >= RMS_Config.CORE.TURBO_MIN_POWER_KW
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ENGINE, {"hmf", "mlf"}, {"aicf", "sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_turbocharger_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TURBOCHARGER_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.TURBOCHARGER_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum" },
                    { id = "TURBO_WHISTLE_NOISE_EFFECT", value = 0.25, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.20, aggregation = "max" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_turbocharger_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TURBOCHARGER_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.TURBOCHARGER_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.20, aggregation = "sum" },
                    { id = "TURBO_WHISTLE_NOISE_EFFECT", value = 0.35, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.40, aggregation = "max" },
                    { id = "EXHAUST_OIL", value = 0.25, aggregation = "max" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_turbocharger_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TURBOCHARGER_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.TURBOCHARGER_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.40, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "TURBO_WHISTLE_NOISE_EFFECT", value = 0.6, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.65, aggregation = "max" },
                    { id = "EXHAUST_OIL", value = 0.50, aggregation = "max" },
                },
                inspection = {
                    { additional = "rms_inspection_hint_turbocharger_malfunction_stage3" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_turbocharger_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.TURBOCHARGER_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.50, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.60, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "EXHAUST_SOOT", value = 0.90, aggregation = "max" },
                    { id = "EXHAUST_OIL", value = 0.70, aggregation = "max" },
                },
                inspection = {
                    { additional = "rms_inspection_hint_turbocharger_malfunction_stage4" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    OIL_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.OIL_PUMP,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ENGINE, {"sf"}, {"hmf", "cmf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_oil_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.OIL_PUMP_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.OIL_PUMP_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.30, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.05, aggregation = "sum" },
                    
                },
                inspection = {
                    { target = "engineOil", status = "rms_inspection_status_slightly_darkened", additional = "rms_inspection_hint_oil_pump_malfunction_stage1" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_oil_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.OIL_PUMP_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.OIL_PUMP_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.15, aggregation = "sum" },
                },
                inspection = {
                    { target = "engineOil", status = "rms_inspection_status_darkened", additional = "rms_inspection_hint_oil_pump_malfunction_stage2" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_oil_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.OIL_PUMP_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.OIL_PUMP_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.45, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.8, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.35, aggregation = "sum" },
                },
                inspection = {
                    { target = "engineOil", status = "rms_inspection_status_contaminated", additional = "rms_inspection_hint_oil_pump_malfunction_stage3" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_oil_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.OIL_PUMP_MALFUNCTION,
                effects = {
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = true, message = "rms_breakdowns_oil_pump_malfunction_stage4_message", reason = "BREAKDOWN", disableAi = true} },
                },
                inspection = {
                    { target = "engineOil", status = "rms_inspection_status_critical_condition", additional = "rms_inspection_hint_oil_pump_malfunction_stage4" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                
                }
            }
        }
    },

    VALVE_TRAIN_MALFUNCTION = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.VALVE_TRAIN,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.ENGINE, {"sf", "cmf"}, {"hmf", "mlf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_valve_train_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.VALVE_TRAIN_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.VALVE_TRAIN_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum" },
                    { id = "VALVE_TRAIN_NOISE_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.05, aggregation = "sum" },
                    { id = "EXHAUST_OIL", value = 0.20, aggregation = "max" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_valve_train_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.VALVE_TRAIN_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.VALVE_TRAIN_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "VALVE_TRAIN_NOISE_EFFECT", value = 0.7, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.10, aggregation = "sum" },
                    { id = "EXHAUST_OIL", value = 0.40, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "max", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_valve_train_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.VALVE_TRAIN_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.VALVE_TRAIN_MALFUNCTION,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.20, aggregation = "sum" },
                    { id = "VALVE_TRAIN_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "EXHAUST_OIL", value = 0.65, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 1.0, motorLoad = 0.5, cruiseState = 0}, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_valve_train_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.VALVE_TRAIN_MALFUNCTION,
                effects = {
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = true, message = "rms_breakdowns_valve_train_malfunction_stage4_message", reason = "BREAKDOWN", disableAi = true} },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }         
                }
            }
        }
    },

    -- transmission system
    MANUAL_TRANSMISSION_CLUTCH_WEAR = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.CLUTCH,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            return motor.minForwardGearRatio == nil
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.TRANSMISSION, {"wsf", "lf"}, {"pof", "sf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,

        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_slip_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                repairPrice = 1.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.20, aggregation = "max" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_slip_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                repairPrice = 2.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                effects = {
                     { id = "TRANSMISSION_SLIP_EFFECT", value = 0.40, aggregation = "max" },
                     { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.20, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_slip_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                repairPrice = 4.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                effects = { 
                     { id = "TRANSMISSION_SLIP_EFFECT", value = 0.60, aggregation = "max"},
                     { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.50, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_slip_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                effects = { 
                     { id = "TRANSMISSION_SLIP_EFFECT", value = 1.0, extraData = {message = "rms_breakdowns_transmission_slip_stage4_message", disableAi = true}, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.SYNCHRONIZER,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            return motor.minForwardGearRatio == nil and motor.gearType ~= VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.TRANSMISSION, {"lf", "pof"}, {"sf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                effects = {
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.10, extraData = {timer = 0, status = 'IDLE', duration = 1500}, aggregation = "max"},
                    { id = "GEAR_REJECTION_CHANCE", value = 20.0, extraData = {timer = 0, status = 'IDLE', duration = 2000 }, aggregation = "min"}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                effects = {
                     { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.20, extraData = {timer = 0, status = 'IDLE', duration = 1800}, aggregation = "max"},
                     { id = "GEAR_REJECTION_CHANCE", value = 10.0, extraData = {timer = 0, status = 'IDLE', duration = 2000 }, aggregation = "min"}
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                effects = { 
                     { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.50, extraData = {timer = 0, status = 'IDLE', duration = 2200}, aggregation = "max"},
                     { id = "GEAR_REJECTION_CHANCE", value = 3.0, extraData = {timer = 0, status = 'IDLE', duration = 2000 }, aggregation = "min"}
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                effects = { 
                     { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 1.00, extraData = {timer = 0, status = 'IDLE', duration = 2200, message = "rms_breakdowns_transmission_synchronizer_malfunction_stage4_message", disableAi = true}, aggregation = "max"}
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.POWERSHIFT_HYDRAULIC_PUMP,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            return motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.TRANSMISSION, {"hotf"}, {"pof", "sf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_powershift_hydraulic_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION,
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.2, extraData = {timer = 0, status = "IDLE", duration = 700, backup = 0}, aggregation = "max"}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_powershift_hydraulic_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION,
                effects = {
                     { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.5, extraData = {timer = 0, status = "IDLE", duration = 1000, backup = 0}, aggregation = "max"}
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_powershift_hydraulic_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION,
                effects = { 
                     { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.99, extraData = {timer = 0, status = "IDLE", duration = 1500, backup = 0}, aggregation = "max"}
                },
                inspection = {
                    { additional = "rms_inspection_hint_powershift_hydraulic_pump_malfunction_stage3" },
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_powershift_hydraulic_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION,
                effects = { 
                     { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 1.0, extraData = {timer = 0, status = "IDLE", duration = 0, disableAi = true}, aggregation = "max"}
                },
                inspection = {
                    { additional = "rms_inspection_hint_powershift_hydraulic_pump_malfunction_stage4" },
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CVT_CHAIN_WEAR = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.CVT_CHAIN,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            if motor.minForwardGearRatio == nil then return false end
            return true
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.TRANSMISSION, {"wsf", "lf"}, {"hotf", "pof"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_cvt_chain_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CVT_CHAIN_WEAR,
                repairPrice = 1.0 * breakdownPriceMultipliers.CVT_CHAIN_WEAR,
                effects = {
                    { id = "CVT_SLIP_EFFECT", value = 0.1, aggregation = "max" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.05, aggregation = "sum" }  
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cvt_chain_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CVT_CHAIN_WEAR,
                repairPrice = 2.0 * breakdownPriceMultipliers.CVT_CHAIN_WEAR,
                effects = {
                     { id = "CVT_SLIP_EFFECT", value = 0.2, aggregation = "max" },
                     { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.20, aggregation = "sum" },
                     { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.1, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_cvt_chain_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CVT_CHAIN_WEAR,
                repairPrice = 4.0 * breakdownPriceMultipliers.CVT_CHAIN_WEAR,
                effects = { 
                     { id = "CVT_SLIP_EFFECT", value = 0.5, aggregation = "max" },
                     { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.25, aggregation = "sum" },
                     { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.15, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cvt_chain_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.CVT_CHAIN_WEAR,
                effects = { 
                     { id = "CVT_SLIP_EFFECT", value = 1.0, extraData = {message = "rms_breakdowns_cvt_chain_wear_stage4_message", disableAi = true}, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.CVT_HYDRAULIC_CONTROL_VALVE,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            if motor.minForwardGearRatio == nil then return false end
            return true
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.TRANSMISSION, {"hotf"}, {"ctf", "sf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                effects = {
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 2.0, aggregation = "max", extraData = {timer = 0, duration = 200, status = 'IDLE'}},
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.3, aggregation = "max" },
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                effects = {
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 1.0, aggregation = "max", extraData = {timer = 0, duration = 250, status = 'IDLE'}},
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.05, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.4, aggregation = "max" },
                    
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                effects = { 
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 0.5, aggregation = "max", extraData = {timer = 0, duration = 300, status = 'IDLE'}},
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.2, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.1, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.5, aggregation = "max" },
                },
                inspection = {
                    { additional = "rms_inspection_hint_cvt_hydraulic_control_valve_malfunction_stage3" },
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                effects = { 
                     { id = "CVT_MAX_RATIO_MODIFIER", value = 0.8, aggregation = "max" },
                     { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.15, aggregation = "sum" },
                     { id = "ENGINE_TORQUE_MODIFIER", value = -0.3, aggregation = "sum" },
                     { id = "CVT_PRESSURE_DROP_CHANCE", value = 0.1, aggregation = "max", extraData = {timer = 0, duration = 300, status = 'IDLE'}},
                     { id = "ENGINE_LIMP_EFFECT", value = -0.2, aggregation = "min", extraData = {reason = "BREAKDOWN", message = "rms_breakdowns_hydraulic_control_valve_malfunction_stage4_message", disableAi = true } },
                },
                inspection = {
                    { additional = "rms_inspection_hint_cvt_hydraulic_control_valve_malfunction_stage4" },
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRANSMISSION_THERMOSTAT_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_THERMOSTAT,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            if motor.minForwardGearRatio == nil then return false end
            return true
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.TRANSMISSION, {"hotf", "ctf"}, {"pof", "lf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_thermostat_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRANSMISSION_THERMOSTAT_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.TRANSMISSION_THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER", value = -0.3, aggregation = "min"}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_thermostat_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRANSMISSION_THERMOSTAT_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.TRANSMISSION_THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER", value = -0.6, aggregation = "min"}
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_thermostat_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRANSMISSION_THERMOSTAT_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.TRANSMISSION_THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER", value = -0.8, aggregation = "min"}
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_thermostat_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.TRANSMISSION_THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_THERMOSTAT_STUCK_EFFECT", value = -1.0, aggregation = "min"}
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CVT_ADDON_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.CVT,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return true end
            return false
        end,
        probability = function(vehicle)
            return 1.0
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            { 
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_cvt_addon_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 3.0 * breakdownProgressMultipliers.CVT_ADDON_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.CVT_ADDON_MALFUNCTION,
                effects = { 
                },
                indicators = {
            
                }
            },
            { 
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cvt_addon_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.5 * breakdownProgressMultipliers.CVT_ADDON_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.CVT_ADDON_MALFUNCTION,
                effects = { 
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_cvt_addon_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CVT_ADDON_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.CVT_ADDON_MALFUNCTION,
                effects = { 
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cvt_addon_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.CVT_ADDON_MALFUNCTION,
                effects = { 
                    { id = "CVT_SLIP_EFFECT", value = 1.0, extraData = {message = "rms_breakdowns_cvt_addon_malfunction_stage4_message", disableAi = true}, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    -- hydraulic system
    HYDRAULIC_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_PUMP,
        isApplicable = isHydraulicBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.HYDRAULICS, {"cof", "hof", "sf"}, {})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.20, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.40, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                effects = { 
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.75, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                effects = { 
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -1.0, extraData = {message = 'rms_breakdowns_hydraulic_pump_malfunction_stage4_message', disableAi = true}, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    
    HYDRAULIC_CYLINDER_INTERNAL_LEAK  = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_CYLINDER,
        isApplicable = isHydraulicBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.HYDRAULICS, {"hlf", "of", "vf"}, {})
        end,
        isCanProgress = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return spec.isImplementLifted or spec.operatingMass > 0
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                repairPrice = 1.0 * breakdownPriceMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.01, aggregation = "max", extraData = {status = 'IDLE', timer = 0, massRatio = 0.5} }
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_cylinder_internal_leak_stage1" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                repairPrice = 2.0 * breakdownPriceMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.03, aggregation = "max", extraData = {status = 'IDLE', timer = 0, massRatio = 0.4}}
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_cylinder_internal_leak_stage2" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                repairPrice = 4.0 * breakdownPriceMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                effects = { 
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.05, aggregation = "max", extraData = {status = 'IDLE', timer = 0, massRatio = 0.2} }
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_cylinder_internal_leak_stage3" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                effects = { 
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 1.0, aggregation = "max", extraData = {status = 'IDLE', timer = 0, massRatio = 0.0} }
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_cylinder_internal_leak_stage4" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDRAULIC_HOSE_EXTERNAL_LEAK = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_HOSE,
        isApplicable = isHydraulicBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.HYDRAULICS, {"hlf", "vf"}, {})
        end,
        isCanProgress = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return vehicle:getIsMotorStarted() and (spec.isImplementLifted or spec.isImplementOperating)
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                repairPrice = 1.0 * breakdownPriceMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.05, aggregation = "min" }
                },
                inspection = {
                    { target = "hydraulicFluid", status = "rms_inspection_status_slight_moisture", additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage1" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                repairPrice = 2.0 * breakdownPriceMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.10, aggregation = "min" }
                },
                inspection = {
                    { target = "hydraulicFluid", status = "rms_inspection_status_seepage", additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage2" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                repairPrice = 4.0 * breakdownPriceMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.20, aggregation = "min" }
                },
                inspection = {
                    { target = "hydraulicFluid", status = "rms_inspection_status_active_leak", additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage3" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.35, aggregation = "min" }
                },
                inspection = {
                    { target = "hydraulicFluid", status = "rms_inspection_status_severe_leak", additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage4" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDRAULIC_FILTER_CLOGGING = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_FILTER,
        isApplicable = isHydraulicBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.HYDRAULICS, {"sf", "cof"}, {})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_FILTER_CLOGGING,
                repairPrice = 1.0 * breakdownPriceMultipliers.HYDRAULIC_FILTER_CLOGGING,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.10, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_FILTER_CLOGGING,
                repairPrice = 2.0 * breakdownPriceMultipliers.HYDRAULIC_FILTER_CLOGGING,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.25, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_FILTER_CLOGGING,
                repairPrice = 4.0 * breakdownPriceMultipliers.HYDRAULIC_FILTER_CLOGGING,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.45, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.HYDRAULIC_FILTER_CLOGGING,
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.70, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDRAULIC_OIL_COOLER_MALFUNCTION = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_OIL_COOLER,
        isApplicable = isHydraulicBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.HYDRAULICS, {"sf", "hof"}, {})
        end,
        isCanProgress = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.isImplementOperating
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.05, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.10, aggregation = "sum" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.15, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.20, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDRAULIC_SPOOL_VALVE_MALFUNCTION = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_SPOOL_VALVE,
        isApplicable = isHydraulicBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.HYDRAULICS, {"of", "sf"}, {})
        end,
        isCanProgress = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.isImplementOperating
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_spool_valve_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.10, aggregation = "min", extraData = {childVehicleHash = ""} },
                    { id = "HYDRAULIC_LOAD_PRESSURE_LOSS_EFFECT", value = -0.15, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_spool_valve_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.20, aggregation = "min", extraData = {childVehicleHash = ""} },
                    { id = "HYDRAULIC_LOAD_PRESSURE_LOSS_EFFECT", value = -0.30, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_spool_valve_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.35, aggregation = "min", extraData = {childVehicleHash = ""} },
                    { id = "HYDRAULIC_LOAD_PRESSURE_LOSS_EFFECT", value = -0.55, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_spool_valve_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.50, aggregation = "min", extraData = {childVehicleHash = ""} },
                    { id = "HYDRAULIC_LOAD_PRESSURE_LOSS_EFFECT", value = -0.80, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PTO_CLUTCH_WEAR = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_CLUTCH,
        isApplicable = isPtoBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.PTO, {"plf", "pef"}, {})
        end,
        isCanProgress = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.isPtoActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_clutch_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_CLUTCH_WEAR,
                repairPrice = 1.0 * breakdownPriceMultipliers.PTO_CLUTCH_WEAR,
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 40, aggregation = "min", extraData = {status = "IDLE"} }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_clutch_wear_stage1" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_clutch_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_CLUTCH_WEAR,
                repairPrice = 2.0 * breakdownPriceMultipliers.PTO_CLUTCH_WEAR,
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 20, aggregation = "min", extraData = {status = "IDLE"} }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_clutch_wear_stage2" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_clutch_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_CLUTCH_WEAR,
                repairPrice = 4.0 * breakdownPriceMultipliers.PTO_CLUTCH_WEAR,
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 10, aggregation = "min", extraData = {status = "IDLE"} }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_clutch_wear_stage3" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_clutch_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.PTO_CLUTCH_WEAR,
                effects = {
                    { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {message = "rms_breakdowns_pto_clutch_wear_stage4_message", disableAi = true} }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_clutch_wear_stage4" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PTO_OUTPUT_BEARING_WEAR = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_OUTPUT_SHAFT,
        isApplicable = isPtoBreakdownApplicable,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.PTO, {"plf", "sf"}, {})
        end,
        isCanProgress = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.isPtoActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_output_bearing_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_OUTPUT_BEARING_WEAR,
                repairPrice = 1.0 * breakdownPriceMultipliers.PTO_OUTPUT_BEARING_WEAR,
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 0.35, aggregation = "max" }
                },
                inspection = {
                    { target = "ptoShaft", additional = "rms_inspection_hint_pto_output_bearing_wear_stage1" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_output_bearing_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_OUTPUT_BEARING_WEAR,
                repairPrice = 2.0 * breakdownPriceMultipliers.PTO_OUTPUT_BEARING_WEAR,
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 0.60, aggregation = "max" }
                },
                inspection = {
                    { target = "ptoShaft", additional = "rms_inspection_hint_pto_output_bearing_wear_stage2" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_output_bearing_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_OUTPUT_BEARING_WEAR,
                repairPrice = 4.0 * breakdownPriceMultipliers.PTO_OUTPUT_BEARING_WEAR,
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 0.85, aggregation = "max" },
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 30, aggregation = "min", extraData = {status = "IDLE"} }
                },
                inspection = {
                    { target = "ptoShaft", additional = "rms_inspection_hint_pto_output_bearing_wear_stage3" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_output_bearing_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.PTO_OUTPUT_BEARING_WEAR,
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {message = "rms_breakdowns_pto_output_bearing_wear_stage4_message", disableAi = true} }
                },
                inspection = {
                    { target = "ptoShaft", additional = "rms_inspection_hint_pto_output_bearing_wear_stage4" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PTO_ENGAGEMENT_VALVE_MALFUNCTION = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_CLUTCH,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return isPtoBreakdownApplicable(vehicle) and spec.year >= 1990
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.PTO, {"pef", "sf"}, {})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_engagement_valve_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_ENGAGEMENT_VALVE_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.PTO_ENGAGEMENT_VALVE_MALFUNCTION,
                effects = {
                    { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.10, aggregation = "max" }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_engagement_valve_malfunction_stage1" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_engagement_valve_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_ENGAGEMENT_VALVE_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.PTO_ENGAGEMENT_VALVE_MALFUNCTION,
                effects = {
                    { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.30, aggregation = "max" }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_engagement_valve_malfunction_stage2" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_engagement_valve_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_ENGAGEMENT_VALVE_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.PTO_ENGAGEMENT_VALVE_MALFUNCTION,
                effects = {
                    { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.60, aggregation = "max" }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_engagement_valve_malfunction_stage3" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_engagement_valve_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.PTO_ENGAGEMENT_VALVE_MALFUNCTION,
                effects = {
                    { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 1.0, aggregation = "max", extraData = {message = "rms_breakdowns_pto_engagement_valve_malfunction_stage4_message", disableAi = true} }
                },
                inspection = {
                    { target = "ptoClutch", additional = "rms_inspection_hint_pto_engagement_valve_malfunction_stage4" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    -- chassis system
    BRAKE_MALFUNCTION = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.BRAKE_SYSTEM,
        isApplicable = function(vehicle)
            if vehicle.spec_crawlers ~= nil then
                return #vehicle.spec_crawlers.crawlers == 0
            else
                return true
            end
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.CHASSIS, {"bmf"}, {"sf"})
        end,
        isCanProgress = function(vehicle)
            return true
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_brake_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.BRAKE_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.BRAKE_MALFUNCTION,
                effects = {
                    { id = "BRAKE_FORCE_MODIFIER", value = -0.30, aggregation = "min",  extraData = {} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_brake_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.BRAKE_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.BRAKE_MALFUNCTION,
                effects = {
                    { id = "BRAKE_FORCE_MODIFIER", value = -0.45, aggregation = "min",  extraData = {} }
                },
                indicators = {
                    { id = db.BRAKES, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_brake_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.BRAKE_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.BRAKE_MALFUNCTION,
                effects = { 
                    { id = "BRAKE_FORCE_MODIFIER", value = -0.70, aggregation = "min",  extraData = {} }
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_brake_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.BRAKE_MALFUNCTION,
                effects = { 
                    { id = "BRAKE_FORCE_MODIFIER", value = -1.0, aggregation = "min", extraData = {message = "rms_breakdowns_brake_malfunction_stage4_message", disableAi = true} }
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    BEARING_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.WHEEL_BEARING,
        isApplicable = function(vehicle)
            if vehicle.spec_crawlers ~= nil then
                return #vehicle.spec_crawlers.crawlers == 0
            else
                return true
            end
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.CHASSIS, {"vf"}, {"bmf", "sf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_bearing_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.BEARING_WEAR,
                repairPrice = 1.0 * breakdownPriceMultipliers.BEARING_WEAR,
                effects = {
                    { id = "WHEEL_HUB_BEARING_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "VIBRATION_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.05, aggregation = "max" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_bearing_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.BEARING_WEAR,
                repairPrice = 2.0 * breakdownPriceMultipliers.BEARING_WEAR,
                effects = {
                    { id = "WHEEL_HUB_BEARING_NOISE_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "VIBRATION_NOISE_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.10, aggregation = "max" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                },
                indicators = {

                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_bearing_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.BEARING_WEAR,
                repairPrice = 4.0 * breakdownPriceMultipliers.BEARING_WEAR,
                effects = { 
                    { id = "WHEEL_HUB_BEARING_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "VIBRATION_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.20, aggregation = "max" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.07, aggregation = "sum" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                },
                indicators = {

                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_bearing_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.BEARING_WEAR,
                effects = { 
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 2.5, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_EFFECT", value = 1.0, aggregation = "max", extraData = {message = "rms_breakdowns_bearing_wear_stage4_message", disableAi = true}},
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    STEERING_LINKAGE_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.STEERING_LINKAGE,
        isApplicable = function(vehicle)
            if vehicle.spec_wheels == nil or vehicle.spec_wheels.wheels == nil or #vehicle.spec_wheels.wheels == 0 then
                return false
            end
            if vehicle.spec_crawlers ~= nil and #vehicle.spec_crawlers.crawlers > 0 then
                return false
            end
            return true
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.CHASSIS, {"slf"}, {"vf", "sf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_steering_linkage_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.STEERING_LINKAGE_WEAR,
                repairPrice = 1.0 * breakdownPriceMultipliers.STEERING_LINKAGE_WEAR,
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.003, aggregation = "max" },
                    { id = "STEERING_SENSITIVITY_MODIFIER", value = 0.10, aggregation = "max" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_steering_linkage_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.STEERING_LINKAGE_WEAR,
                repairPrice = 2.0 * breakdownPriceMultipliers.STEERING_LINKAGE_WEAR,
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.01, aggregation = "max" },
                    { id = "STEERING_SENSITIVITY_MODIFIER", value = 0.25, aggregation = "max" },
                },
                indicators = {
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_steering_linkage_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.STEERING_LINKAGE_WEAR,
                repairPrice = 4.0 * breakdownPriceMultipliers.STEERING_LINKAGE_WEAR,
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.03, aggregation = "max" },
                    { id = "STEERING_SENSITIVITY_MODIFIER", value = 0.45, aggregation = "max" },
                },
                indicators = {
                    { id = db.BRAKES, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_steering_linkage_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.STEERING_LINKAGE_WEAR,
                effects = {
                    { id = "STEERING_SENSITIVITY_MODIFIER", value = 0.99, aggregation = "max", extraData = {message="rms_breakdowns_steering_linkage_wear_stage4_message", disableAi=true} },
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRACK_TENSIONER_MALFUNCTION = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.TRACK_TENSIONER,
        isApplicable = function(vehicle)
            if vehicle.spec_crawlers ~= nil and #vehicle.spec_crawlers.crawlers > 0 then
                return true
            end
            return false
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.CHASSIS, {"vf"}, {"slf"})
        end,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_track_tensioner_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRACK_TENSIONER_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.TRACK_TENSIONER_MALFUNCTION,
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.003, aggregation = "max" },
                    { id = "VIBRATION_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.03, aggregation = "max" },

                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_track_tensioner_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRACK_TENSIONER_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.TRACK_TENSIONER_MALFUNCTION,
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.01, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "max", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 0.6, motorLoad = 0.2, cruiseState = 0}},
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "VIBRATION_NOISE_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.06, aggregation = "max" },

                },
                inspection = {
                    { additional = "rms_inspection_hint_track_tensioner_malfunction_stage2" },
                },
                indicators = {
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_track_tensioner_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRACK_TENSIONER_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.TRACK_TENSIONER_MALFUNCTION,
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.05, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.1, aggregation = "max", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.6, motorLoad = 0.2, cruiseState = 0}},
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "VIBRATION_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.15, aggregation = "max" },

                },
                inspection = {
                    { additional = "rms_inspection_hint_track_tensioner_malfunction_stage3" },
                },
                indicators = {
                    { id = db.BRAKES, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_track_tensioner_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.TRACK_TENSIONER_MALFUNCTION,
                effects = {
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 2.5, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_EFFECT", value = 1.0, aggregation = "max", extraData = {message = "rms_breakdowns_track_tensioner_malfunction_stage4_message", disableAi = true}},
                },
                inspection = {
                    { additional = "rms_inspection_hint_track_tensioner_malfunction_stage4" },
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    -- cooling system
    THERMOSTAT_MALFUNCTION = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.THERMOSTAT,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.COOLING, {"hcf"}, {"csf", "sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_thermostat_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.THERMOSTAT_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "THERMOSTAT_HEALTH_MODIFIER", value = -0.3, aggregation = "min"}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_thermostat_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.THERMOSTAT_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "THERMOSTAT_HEALTH_MODIFIER", value = -0.6, aggregation = "min"}
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_thermostat_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.THERMOSTAT_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "THERMOSTAT_HEALTH_MODIFIER", value = -0.8, aggregation = "min"}
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_thermostat_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.THERMOSTAT_MALFUNCTION,
                effects = {
                    { id = "THERMOSTAT_STUCK_EFFECT", value = -1.0, aggregation = "min"}
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    COOLANT_LEAK = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.COOLING_SYSTEM,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.COOLING, {"ohf"}, {"csf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_coolant_leak_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.COOLANT_LEAK,
                repairPrice = 1.0 * breakdownPriceMultipliers.COOLANT_LEAK,
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.1, aggregation = "min"}
                },
                inspection = {
                    { target = "coolant", status = "rms_inspection_status_slightly_low", additional = "rms_inspection_hint_coolant_leak_stage1" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_coolant_leak_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.COOLANT_LEAK,
                repairPrice = 2.0 * breakdownPriceMultipliers.COOLANT_LEAK,
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min"}
                },
                inspection = {
                    { target = "coolant", status = "rms_inspection_status_low", additional = "rms_inspection_hint_coolant_leak_stage2" },
                },
                indicators = {

                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_coolant_leak_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.COOLANT_LEAK,
                repairPrice = 4.0 * breakdownPriceMultipliers.COOLANT_LEAK,
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.4, aggregation = "min"}
                },
                inspection = {
                    { target = "coolant", status = "rms_inspection_status_very_low", additional = "rms_inspection_hint_coolant_leak_stage3" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_coolant_leak_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.COOLANT_LEAK,
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.6, aggregation = "min"}
                },
                inspection = {
                    { target = "coolant", status = "rms_inspection_status_critically_low", additional = "rms_inspection_hint_coolant_leak_stage4" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false },
                }
            }
        }
    },

    FAN_CLUTCH_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.FAN_CLUTCH,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.COOLING, {"hcf"}, {"ohf", "sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fan_clutch_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FAN_CLUTCH_FAILURE,
                repairPrice = 1.0 * breakdownPriceMultipliers.FAN_CLUTCH_FAILURE,
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.1, aggregation = "min"},
                    { id = "FAN_CLUTCH_NOISE_EFFECT", value = 0.6, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fan_clutch_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FAN_CLUTCH_FAILURE,
                repairPrice = 2.0 * breakdownPriceMultipliers.FAN_CLUTCH_FAILURE,
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.2, aggregation = "min"},
                    { id = "FAN_CLUTCH_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fan_clutch_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FAN_CLUTCH_FAILURE,
                repairPrice = 4.0 * breakdownPriceMultipliers.FAN_CLUTCH_FAILURE,
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.3, aggregation = "min"},
                    { id = "FAN_CLUTCH_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fan_clutch_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.FAN_CLUTCH_FAILURE,
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.5, aggregation = "min"},
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false },
                }
            }
        }
    },

    -- fuel system
    FUEL_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_PUMP,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.FUEL, {"lff"}, {"hpf", "idf", "sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_PUMP_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.FUEL_PUMP_MALFUNCTION,
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, period = 1800, rpmBackup = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "max", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_PUMP_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.FUEL_PUMP_MALFUNCTION,
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.08, aggregation = "max", extraData = { timer = 0, period = 1600, rpmBackup = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.4, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_UNBURNT", value = 0.20, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "max", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    {  
                        id = db.ENGINE,
                        color = color.WARNING,
                        switchOn = function(vehicle)
                            if vehicle.spec_motorized and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() > 0.95 then
                                return true
                            end
                            return false
                        end,
                        switchOff = false
                    }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_PUMP_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.FUEL_PUMP_MALFUNCTION,
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1500, rpmBackup = 0} }, 
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 1.0, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_UNBURNT", value = 0.30, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.15, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, aggregation = "max", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 1.0, motorLoad = 0.5, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.FUEL_PUMP_MALFUNCTION,
                effects = { 
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = true, message = "rms_breakdowns_fuel_pump_malfunction_stage4_message", reason = "BREAKDOWN", disableAi = true} } 
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    FUEL_INJECTOR_MALFUNCTION = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_INJECTORS,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.FUEL, {"idf", "hpf"}, {"cff"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_injector_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_INJECTOR_MALFUNCTION,
                repairPrice = 1.0 * breakdownPriceMultipliers.FUEL_INJECTOR_MALFUNCTION,
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, period = 1800, rpmBackup = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.08, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.10, aggregation = "sum" },
                    { id = "EXHAUST_SOOT", value = 0.20, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.15, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.4, aggregation = "max", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.9, cruiseState = 0} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_injector_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_INJECTOR_MALFUNCTION,
                repairPrice = 2.0 * breakdownPriceMultipliers.FUEL_INJECTOR_MALFUNCTION,
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.08, aggregation = "max", extraData = { timer = 0, period = 1500, rpmBackup = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.20, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.25, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                    { id = "EXHAUST_SOOT", value = 0.40, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.30, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "max", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 0.8, motorLoad = 0.8, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_injector_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_INJECTOR_MALFUNCTION,
                repairPrice = 4.0 * breakdownPriceMultipliers.FUEL_INJECTOR_MALFUNCTION,
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1800, rpmBackup = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.50, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_SOOT", value = 0.70, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.50, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "max", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_injector_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.FUEL_INJECTOR_MALFUNCTION,
                effects = {
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = true, message = "rms_breakdowns_fuel_injector_malfunction_stage4_message", reason = "BREAKDOWN", disableAi = true} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    FUEL_FILTER_CLOGGING = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_FILTER,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.FUEL, {"idf"}, {"cff", "sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_filter_clogging_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_FILTER_CLOGGING,
                repairPrice = 1.0 * breakdownPriceMultipliers.FUEL_FILTER_CLOGGING,
                effects = {
                     { id = "ENGINE_HESITATION_CHANCE", value = 0.4, aggregation = "max", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.9, cruiseState = 0} },
                     { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_filter_clogging_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_FILTER_CLOGGING,
                repairPrice = 2.0 * breakdownPriceMultipliers.FUEL_FILTER_CLOGGING,
                effects = {
                     { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "max", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 0.7, motorLoad = 0.9, cruiseState = 0} },
                     { id = "ENGINE_TORQUE_MODIFIER", value = -0.06, aggregation = "sum" },
                     { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                     { id = "EXHAUST_UNBURNT", value = 0.15, aggregation = "max" },
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_filter_clogging_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_FILTER_CLOGGING,
                repairPrice = 4.0 * breakdownPriceMultipliers.FUEL_FILTER_CLOGGING,
                effects = { 
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "max", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.7, motorLoad = 0.9, cruiseState = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "EXHAUST_UNBURNT", value = 0.25, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.15, aggregation = "max" },
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_filter_clogging_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.FUEL_FILTER_CLOGGING,
                effects = {
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = true, message = "rms_breakdowns_fuel_filter_clogging_stage4_message", reason = "BREAKDOWN", disableAi = true} }
                }
            }
        }
    },

    FUEL_LINE_AIR_LEAK = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_LINE,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        probability = function(vehicle)
            return getBreakdownProbabilityWeightPercent(vehicle, systems.FUEL, {"lff"}, {"sf"})
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_line_air_leak_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_LINE_AIR_LEAK,
                repairPrice = 1.0 * breakdownPriceMultipliers.FUEL_LINE_AIR_LEAK,
                effects = {
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", extraData = { timer = 0, status = 'IDLE', count = 0}}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_line_air_leak_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_LINE_AIR_LEAK,
                repairPrice = 2.0 * breakdownPriceMultipliers.FUEL_LINE_AIR_LEAK,
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "max", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.5, cruiseState = 0} },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE', count = 0}},
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "EXHAUST_UNBURNT", value = 0.20, aggregation = "max" },
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_line_air_leak_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_LINE_AIR_LEAK,
                repairPrice = 4.0 * breakdownPriceMultipliers.FUEL_LINE_AIR_LEAK,
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "max", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.7, motorLoad = 0.5, cruiseState = 0} },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = {timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "EXHAUST_UNBURNT", value = 0.35, aggregation = "max" },
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_line_air_leak_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = 8.0 * breakdownPriceMultipliers.FUEL_LINE_AIR_LEAK,
                effects = {
                    { id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {starter = true, message = "rms_breakdowns_fuel_line_air_leak_stage4_message", reason = "BREAKDOWN", disableAi = true}}
                }
            }
        }
    }
}

local function wrapBreakdownApplicabilityByEnabledSystem()
    for _, entry in pairs(RMS_Breakdowns.BreakdownRegistry or {}) do
        if type(entry) == "table" and entry.system ~= nil and type(entry.isApplicable) == "function" then
            local originalIsApplicable = entry.isApplicable

            entry.isApplicable = function(vehicle)
                if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
                    return false
                end

                local spec = vehicle.spec_RealisticMechanicalSystems
                local systemKey = nil

                if RMS_Utils ~= nil and RealisticMechanicalSystems ~= nil and RealisticMechanicalSystems.SYSTEMS ~= nil then
                    systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, entry.system)
                end

                if (systemKey == nil or systemKey == "") and type(entry.system) == "string" then
                    systemKey = string.lower(entry.system)
                end

                if systemKey ~= nil and systemKey ~= "" then
                    local systemData = spec.systems ~= nil and spec.systems[systemKey] or nil
                    if type(systemData) == "table" and systemData.enabled == false then
                        return false
                    end
                end

                return originalIsApplicable(vehicle) == true
            end
        end
    end
end

wrapBreakdownApplicabilityByEnabledSystem()
