# FS25_RealisticMechanicalSystems

In-depth vehicle wear, failure, diagnostics, maintenance, and repair system for Farming Simulator 25.

[![Version](https://img.shields.io/badge/version-0.9.3.0%20%5BWIP%5D-blue.svg)](#)
[![FS25](https://img.shields.io/badge/FS25-compatible-green.svg)](https://farming-simulator.com/)
![Multiplayer](https://img.shields.io/badge/multiplayer-supported-success.svg)
![Languages](https://img.shields.io/badge/languages-15-blue.svg)
[![License](https://img.shields.io/badge/license-GPL--3.0-yellow.svg)](LICENSE)

Every machine is built from up to 7 individual systems, each with its own condition, its own wear factors, and its own way of failing. Service on schedule, work the machine within its limits, and watch for the early symptoms: the cheapest repair is always the one you catch first.

Singleplayer, multiplayer, and dedicated server.

> **Note:** This repository is an independently maintained fork of Advanced Damage System by id577, developed by Squallqt since 30 June 2026. The gameplay model and the documentation have been substantially reworked since then; the original credits and provenance are preserved unchanged in [NOTICE.md](NOTICE.md).

## Quick Start

Three rules are enough to play without constant breakdowns:

1. **Follow the service interval.** Around `5 operating hours` on average by default. Check it in the workshop, in the vehicle info panel, or in the fleet menu (`P` key), then run `Maintenance`.
2. **Prepare your machines daily.** Hold `R` near a vehicle for a pre-shift inspection, clean it with the `Air Blower`, and grease what needs greasing with the `Grease Gun`.
3. **Do not abuse your equipment.** If it would damage a real machine, it damages this one: overloading, overheating, cold-engine work, wheel slip in mud, oversized implements, speed over rough ground.

## Core Mechanics

Every system tracks three values.

- **Condition**: health and remaining service life. It sets how much abuse a system tolerates before failures become likely. It drops about `1%` per operating hour under normal use, faster under harsh use, and very slowly on a vehicle stored outdoors. Restored by `Overhaul`.
- **Stress**: accumulated misuse. It does not build during normal operation, only through overload, overheating, cold running, wheel slip, and system-specific mistakes. Breakdown probability rises as Stress approaches that system's current Condition. Reduced by preventive maintenance, by repairs, and automatically once a breakdown occurs.
- **Service**: the state of oils, filters, and fluids. It falls with operating hours, and a low level accelerates Condition loss across every system, the engine most of all. Restored by `Maintenance`.

Inspection reports give an approximate status (`OPTIMAL`, `REQUIRED`, `OVERDUE`). Exact percentages require a full defectoscopy, which is slow and expensive, and rarely worth it: following the recommended interval works better than measuring.

## Wear Factors

Four factors apply to every system: **overdue service**, **an active breakdown in that system**, **idleness** (an unused system barely wears), and **downtime** (slow passive wear outdoors). Each system then has its own.

| System | Wear factors |
| --- | --- |
| **Engine** | Load above `90%`; air intake clogged past `50%`; cold running below `50C` at high RPM load; overheating above `95C` under load |
| **Transmission** | Sustained pull above `85%` load, building over `90` seconds; lugging (high load, low RPM); wheel slip above `5%` under `20 km/h`; heavy trailer below `10 hp/t` (`6 hp/t` for trucks); on CVT, cold oil below `45C` and overheating above `100C` |
| **Hydraulics** | Active work under load; lifted mass above `60%` of vehicle mass; cold oil below `30C`; PTO angle beyond `30` degrees |
| **Cooling** | Thermostat effort above `85%`; engine above `95C`; cold shock below `50C` at high RPM load |
| **Electrical** | Lights on; rain, snow, or hail on an outdoor vehicle; starter cranking; engine above `95C` |
| **Chassis** | Vibration over rough ground at speed; steering load under `4 km/h`; braking above `2 km/h` while towing |
| **Fuel** | Fuel below `20%` under load; fuel colder than `20C` above `50%` load; idling past `60` seconds; injection pressure above `90%` load |

Cold-engine and cold-shock factors do not apply to AI workers.

## Breakdowns

Breakdown probability depends entirely on how close a system's Stress is to its Condition. Condition also sets the chance of a **critical** failure, one that appears straight at stage 4 and skips the rest. The type is not random: the mod tracks which wear factors have been active most and picks the failure that history makes most likely.

Most breakdowns run through four stages, **Minor**, **Moderate**, **Major**, and **Critical**, each costing more to repair than the last. Progression is context-dependent; some faults only worsen while the machine performs the work that causes them. Modern vehicles get dashboard indicators from stage 2, but stage 1 is silent and only shows itself through symptoms: fluctuating RPM, dark smoke, knocking, squealing. Catching one there costs almost nothing.

Beyond individual failures, low Condition triggers a permanent **General Wear and Tear** effect: an old machine loses engine power, transmission bite, battery performance, and cooling efficiency even with nothing formally broken.

<details>
<summary><strong>Full breakdown list</strong></summary>

| Breakdown | Applies to | Critical effect |
| --- | --- | --- |
| ECU Malfunction | Non-electric, `2000+` | Engine cannot be controlled and will not start |
| Corroded Wiring | `2000+` with lights | Lights dead, engine start impossible |
| Battery Sulfation | All | Cranking too weak to start reliably |
| Glow Plug Failure | Diesel | No start when preheating is required |
| Alternator Regulator Failure | All | No charging, battery reserve only |
| Turbocharger Wear | Engines from `56 kW` (`75 hp`) | Most engine power lost, further damage likely |
| Oil Pump Malfunction | All non-electric | Oil circulation lost, running and starting unsafe |
| Valve Train Malfunction | All non-electric | Engine cannot run correctly, may not start |
| Manual Clutch Wear | Manual transmissions | Clutch burnout, vehicle cannot move |
| Synchronizer Malfunction | Manual and synchro-shift | Shifting impossible |
| Powershift Pump Malfunction | Powershift | Transmission stuck in neutral |
| CVT Chain Wear | CVT | Movement no longer reliable |
| CVT Control Valve Malfunction | CVT | Severely restricted emergency mode |
| Transmission Thermostat Malfunction | CVT | Oil never reaches correct temperature |
| Hydraulic Pump Malfunction | Hydraulic vehicles from `1960+` | Hydraulic system inoperable |
| Hydraulic Cylinder Internal Leak | Hydraulic vehicles from `1960+` | Movement almost lost, no load holding |
| PTO Clutch Slip | PTO-capable | PTO operation impossible |
| Brake Malfunction | Wheeled | Braking impossible |
| Bearing Wear | Wheeled | Wheel rotation blocked |
| Steering Linkage Wear | Wheeled without tracks | Directional control unsafe |
| Track Tensioner Malfunction | Tracked | Running gear can seize |
| Thermostat Malfunction | All non-electric | Coolant circulation disrupted, overheating unavoidable |
| Coolant Leak | All non-electric | Safe engine temperature unreachable |
| Fan Clutch Failure | All non-electric | Cooling airflow insufficient |
| Fuel Pump Malfunction | All non-electric | No fuel delivered to the engine |
| Fuel Injector Malfunction | All non-electric | Engine will not run correctly, may not start |
| Fuel Filter Clogging | All non-electric | Fuel flow insufficient to run |
| Fuel Line Air Leak | All non-electric | Fuel supply cannot be maintained |

</details>

## Workshop

Four procedures, each with options that change duration, cost, and quality. All of them take real time, and the workshop closes overnight: work in progress resumes the next opening. Planning when a machine goes in matters as much as paying for it.

- **Inspection**: `Visual` is quick but can miss things, `Standard` detects faults and reports condition, `Complete Defectoscopy` finds hidden faults and defective parts and gives exact values.
- **Maintenance**: replaces oils, filters, and fluids, and restores Service. `Minimal` is cheap and partial, `Standard` follows manufacturer spec, `Extended` restores above normal, `Preventive` also strips Stress from the worst systems. The cost is **fixed**, so servicing at `90%` costs the same as at `10%`.
- **Repair**: `Quick Fix` suppresses the symptoms without fixing the fault, which returns. `Standard` replaces the failed part and cuts Stress. `Advanced` replaces everything around it and zeroes Stress.
- **Overhaul**: restores Condition on one system or all of them, clears breakdowns, and includes maintenance unless partial. `Partial`, `Standard`, and `Full` differ in scope and price. Paintwork can be renewed for a fee. It never restores a flat `100%`: the result depends on maintainability, on how many overhauls the machine already had, and on chance.

Maintenance and repair let you pick part quality between `Used`, `Aftermarket`, `OEM`, and `Premium`. Cheaper parts are more often defective: on maintenance they shorten the interval and accelerate wear, on repair they bring the same fault back. Complete Defectoscopy detects them.

## Pre-Shift Care

- **Inspection**: hold `R` near a vehicle to check fluid levels, radiator and air intake fouling, and reveal faults a real visual check would catch. Takes seconds, works anywhere.
- **Air Blower**: clears dust from the cooling pack and air intake. A clean radiator will not overheat and a clean intake lets the engine breathe under load.
- **Grease Gun**: restores lubrication on machines that need it, harvesters above all. Lubrication drops `10%` per period only if the machine was neither operated, greased, nor serviced during it; inspection alone does not count.

## Reliability and Maintainability

Every brand carries two ratings based on its real-world reputation, both shown in the shop.

- **Reliability** slows Condition loss, lowers base breakdown probability, and lengthens service intervals. Premium European and American brands generally rate higher than budget or older Eastern European ones.
- **Maintainability** cuts the money and time of every workshop operation and improves how much an overhaul recovers. Simple older machines usually beat modern electronics-heavy ones.

Vehicles also age: production year drives thermostat behaviour, overheat protection, and which breakdowns can occur at all.

## Thermal Model

Engine temperature is computed from load, ambient temperature, dirt on the radiator, airflow from speed, and thermostat state, and it feeds directly into wear and failure risk.

- **Thermostat behaviour follows production year.** Older machines have inert mechanical thermostats with real stiction; modern ones use fast PID control that adapts quickly to load.
- **Overheat protection is staged from `2000` onwards**: power is progressively limited, then the engine can shut down. Older vehicles have no such protection and can suffer a hard failure instead.
- **Warm-up is mandatory.** Cold operation under load is heavily penalised.
- **CVT machines run a separate transmission model** driven by transmission load, slip, and acceleration dynamics. Slow high-stress work and jerky driving can cook a CVT while the engine still reads normal.

## Electrical System

The battery is a real model, not a switch: capacity falls in the cold, internal resistance rises with cold and age, and charge acceptance drops with low temperature, high state of charge, and poor health. A weak battery does not merely hold less; it also charges worse, sags harder, and cranks poorly.

The alternator output follows engine RPM, current load, and its own health. When consumers demand more than it delivers, voltage sags and the battery drains. Battery temperature is simulated on its own, driven by ambient air, engine bay heat, and self-heating from current.

If a battery is too flat to start, jumper cables link both vehicles into a shared circuit so the donor can support cranking or charge the receiver.

## Installation

1. Place the mod ZIP file into your FS25 `mods/` directory (do not extract).
2. Activate the mod in mod selection.
3. Access RMS from the fleet menu (`P` key), the in-game settings, and workshop interactions.

## Usage

### Running a service

1. Drive the vehicle to a workshop, or use a mobile workshop.
2. Pick `Inspection` first if you are unsure what is wrong, then `Maintenance`, `Repair`, or `Overhaul`.
3. Choose the scope and part quality; both change price and duration.
4. Read the report afterwards. The maintenance log keeps every past procedure.

### Reading the warning signs

1. Watch the dashboard indicators, which light from stage 2 on modern vehicles.
2. Listen for knocking, whistling, and grinding, and look for smoke or unstable RPM; stage 1 is otherwise silent.
3. Run a pre-shift inspection when something feels off, then a workshop inspection if it does not clear.
4. Repair early. A stage 1 fault costs a fraction of a critical one.

## Console Commands

For testing and debugging. Most require you to be inside a vehicle that supports the mod. Typed on a client, they are relayed to the server.

| Command | Description |
| --- | --- |
| `rms_debug` | Toggles debug mode |
| `rms_listBreakdowns` | Lists every breakdown ID in the registry |
| `rms_addBreakdown [id] [stage]` | Adds a breakdown to the current vehicle |
| `rms_removeBreakdown [id]` | Removes one breakdown, or all of them without an ID |
| `rms_advanceBreakdown [id]` | Advances one breakdown a stage, or all where possible |
| `rms_setCondition <0.0-1.0>` | Sets Condition on every enabled system |
| `rms_setSystemCondition <system> <0.0-1.0>` | Sets Condition on one system |
| `rms_setSystemStress <system> <value>` | Sets Stress on one system |
| `rms_setSystemStressMultiplier <value> [system]` | Sets the stress accumulation multiplier |
| `rms_setService <0.0-1.0>` | Sets the Service level |
| `rms_resetVehicle` | Resets condition, service, and active breakdowns |
| `rms_reinitializeVehicle` | Recomputes condition from vanilla resale price, as on first load |
| `rms_setExcluded <true\|false>` | Excludes the vehicle or brings it back in; prints the exclusion state without an argument |
| `rms_startService <type> [count]` | Starts `inspection`, `maintenance`, `repair`, or `overhaul` |
| `rms_finishService` | Finishes the active service instantly |
| `rms_getServiceState` | Prints workshop and service state |
| `rms_showServiceLog [index]` | Prints the service log, or one entry in detail |
| `rms_getDebugVehicleInfo [1]` | Prints vehicle debug info, with specializations when given `1` |
| `rms_setDirtAmount <0.0-1.0>` | Sets the dirt level |
| `rms_setFuelLevel <value>` | Sets fuel, as `0.0-1.0` or `0-100` percent |
| `rms_setOperatingTime <hours>` | Sets operating hours |
| `rms_setHorsePower <hp>` | Sets engine power, rescaling the torque curve |
| `rms_setPlowMaxForce <kN>` | Sets max force on the selected or attached plow |
| `rms_resetFactorStats` | Resets accumulated factor statistics |
| `rms_toggleHudDebugView` | Switches the HUD debug view between normal and factor stats |
| `rms_setConfigVar <path> <value>` | Changes a value inside `RMS_Config` at runtime |
| `rms_printSpecVar <path>` | Prints a value from `spec_RealisticMechanicalSystems` |
| `rms_setSpecVar <path> <value>` | Changes a value inside `spec_RealisticMechanicalSystems` |
| `rms_telemetryStart [scenario] [intervalMs]` | Starts CSV telemetry (`default` or `transmission`) |
| `rms_telemetryStop` | Stops telemetry and closes the file |

## Changelog

### v0.9.3.0 [WIP]

- Fixed and improved translations
- Added drivetrain management for tractors: 4x2 / 4WD / AUTO drive modes and differential locks, with key bindings, a HUD indicator, and settings
- Turning on hard ground with locked differentials now damages the transmission
- Added a parking brake with HUD indicator and optional automatic engagement
- Hands the drivetrain and parking brake over to Enhanced Vehicle when its matching functions are enabled
- Added a HUD readout of tractor, towed, and combined mass
- Fixed locked hook-lift containers being classified as towed and continuously lifted loads
- Extended lubrication to all non-road machines
- Removed the work process system entirely, with the harvest processing wear and the unloading auger malfunction
- Reworked cold-engine wear to start only at the dashboard's high-load threshold, with RPM as a secondary factor
- Fixed the debug HUD showing missing or incorrect values on dedicated servers
- Integrated dashboard indicators into an extended native speedometer layout
- Separated engine and transmission thermal alerts and routed transmission breakdowns to their own indicator
- Dashboard indicators no longer disappear at high speed, and the inactive service indicator stays visible in gray
- Turbocharger wear now applies to every engine of `56 kW` (`75 hp`) or more
- Added a transmission thermostat breakdown on CVT gearboxes
- Recalibrated CVT temperatures against real transmission oil data: regulation at `85C`, overheating wear from `100C`
- Added automatic temperature-based diesel preheating, with battery load, a dashboard indicator, tutorial guidance, and a four-stage glow-plug breakdown
- Vehicle exclusions now follow what a machine can do instead of its type name, and any automatic exclusion can be reverted with `rms_setExcluded false`, except on electric vehicles
- Vehicle production years are now resolved by the mod itself; Vehicle Years is no longer required

## Support

- [GitHub Issues](https://github.com/Squallqt/FS25_RealisticMechanicalSystems/issues)
- [GitHub Discussions](https://github.com/Squallqt/FS25_RealisticMechanicalSystems/discussions)

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) for the complete terms and [NOTICE.md](NOTICE.md) for provenance and attribution.
