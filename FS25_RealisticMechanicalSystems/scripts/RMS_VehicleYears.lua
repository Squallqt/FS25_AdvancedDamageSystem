-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Production year of a vehicle, read from its xml and falling back to the generated table
RMS_VehicleYears = {}

RMS_VehicleYears.DEFAULT_YEAR = 2000

local resolvedYears = {}

---Builds the lookup key of a store item, mod name then raw xml path in lower case
-- @param table storeItem store item
-- @return string key lookup key
local function getStoreItemKey(storeItem)
    local prefix = ""

    if storeItem.customEnvironment ~= nil and string.find(storeItem.baseDir, "pdlc") == nil then
        prefix = storeItem.customEnvironment .. "/"
    end

    return string.lower(prefix .. string.gsub(storeItem.rawXMLFilename, "\\", "/"))
end

---Reads the production year declared in a vehicle xml
-- @param string xmlFilename vehicle xml path
-- @return integer? year declared year
local function getDeclaredYear(xmlFilename)
    local xmlFile = XMLFile.load("RMS_VehicleYear", xmlFilename)
    local year = tonumber(xmlFile:getString("vehicle.storeData.year"))
    xmlFile:delete()

    return year
end

---Returns the production year of a store item, caching the result
-- @param table storeItem store item
-- @return integer year production year
function RMS_VehicleYears.getYear(storeItem)
    local key = getStoreItemKey(storeItem)
    local year = resolvedYears[key]

    if year == nil then
        year = getDeclaredYear(storeItem.xmlFilename) or RMS_VehicleYearsData[key] or RMS_VehicleYears.DEFAULT_YEAR
        resolvedYears[key] = year
    end

    return year
end
