ADS_VehicleYears = {}

ADS_VehicleYears.DEFAULT_YEAR = 2000

local resolvedYears = {}

local function getStoreItemKey(storeItem)
    local prefix = ""

    if storeItem.customEnvironment ~= nil and string.find(storeItem.baseDir, "pdlc") == nil then
        prefix = storeItem.customEnvironment .. "/"
    end

    return string.lower(prefix .. string.gsub(storeItem.rawXMLFilename, "\\", "/"))
end

local function getDeclaredYear(xmlFilename)
    local xmlFile = XMLFile.load("ADS_VehicleYear", xmlFilename)
    local year = tonumber(xmlFile:getString("vehicle.storeData.year"))
    xmlFile:delete()

    return year
end

function ADS_VehicleYears.getYear(storeItem)
    local key = getStoreItemKey(storeItem)
    local year = resolvedYears[key]

    if year == nil then
        year = getDeclaredYear(storeItem.xmlFilename) or ADS_VehicleYearsData[key] or ADS_VehicleYears.DEFAULT_YEAR
        resolvedYears[key] = year
    end

    return year
end
