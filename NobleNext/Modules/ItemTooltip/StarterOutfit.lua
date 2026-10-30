local _, ns = ...
local R = ns.RPSClient

local processor = TooltipDataProcessor
local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
local lineTypes = Enum and Enum.TooltipDataLineType
if not processor or not processor.AddLinePreCall or not lineTypes or itemType == nil then
    return
end

local function secret(value) return issecretvalue and issecretvalue(value) end

-- Native weapon/armor numbers are not RP rules: every weapon (2) and armor (4) shows only RP properties.
local EQUIPMENT = { [2] = true, [4] = true }
local function isEquipmentData(data)
    if secret(data) or type(data) ~= "table" or secret(data.type) or secret(data.id) or secret(data.guid)
        or data.type ~= itemType or type(data.id) ~= "number" then
        return false
    end
    local getInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local classID = getInfo and select(6, getInfo(data.id))
    if not secret(classID) and EQUIPMENT[classID] then return true end
    return (R and R.IsNativeRoleplayItem and R.IsNativeRoleplayItem(data.guid, data.id)) == true
end

local function getData(tooltip)
    if not tooltip then return end
    local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
    if info then return info.tooltipData end
    return tooltip.GetTooltipData and tooltip:GetTooltipData()
end

-- Binding is hidden: the server keeps RP equipment tradable (RPS.Items.TradableEquipment).
local visibleLines = {}
for _, key in ipairs({ "ItemName", "EquipSlot", "FlavorText", "ErrorLine", "DisabledLine",
    "UsageRequirement", "SellPrice", "ItemQuality", "TradeTimeRemaining" }) do
    local lineType = lineTypes[key]
    if lineType ~= nil then visibleLines[lineType] = true end
end

-- Per processing pass: RP properties go right after the equip slot line, where native stats were.
local passes = setmetatable({}, { __mode = "k" })
if R then R.itemTooltipInjected = R.itemTooltipInjected or setmetatable({}, { __mode = "k" }) end

local function inject(tooltip, pass)
    pass.done = true
    local lines = R and R.NativeItemPropertyLines and R.NativeItemPropertyLines(pass.data.guid, pass.data.id)
    if not lines then return end
    for _, line in ipairs(lines) do tooltip:AddLine(line[1], line[2], line[3], line[4], line[5]) end
    R.itemTooltipInjected[tooltip] = true
end

local function resetPass(tooltip)
    passes[tooltip] = nil
    if R and R.itemTooltipInjected then R.itemTooltipInjected[tooltip] = nil end
end

processor.AddLinePreCall(processor.AllTypes, function(tooltip, lineData)
    local data = getData(tooltip)
    if not isEquipmentData(data) then
        resetPass(tooltip)
        return
    end
    if secret(lineData.type) then return end
    local kind = lineData.type
    if kind == lineTypes.SellPrice and R and R.NativeItemHasNoVendorValue
        and R.NativeItemHasNoVendorValue(data.guid, data.id) then return true end
    if kind == lineTypes.ItemName then
        resetPass(tooltip)
        passes[tooltip] = { data = data }
    end
    local pass = passes[tooltip]
    if pass and pass.data ~= data then resetPass(tooltip); pass = nil end
    if pass and pass.equip and not pass.done then inject(tooltip, pass) end
    if pass and kind == lineTypes.EquipSlot then pass.equip = true end
    return not visibleLines[kind]
end)

local comparison = TooltipComparisonManager
if comparison and comparison.SetItemTooltip and hooksecurefunc then
    -- Rebuild the shopping tooltip the way Blizzard does (ClearLines + append) without native deltas,
    -- then add the RP replacement summary.
    hooksecurefunc(comparison, "SetItemTooltip", function(manager, isPrimary)
        local main = manager.tooltip
        local shopping = main and main.shoppingTooltips
        local tooltip = shopping and shopping[isPrimary and 1 or 2]
        local displayed
        if isPrimary then
            displayed = manager.compareInfo and manager.compareInfo.item
        elseif manager.GetSecondaryItem then
            displayed = manager:GetSecondaryItem()
        end
        local data = displayed and manager.GetComparisonItemData and manager:GetComparisonItemData(displayed)
        local hovered = getData(main)
        if not tooltip or not data or not (isEquipmentData(data) or isEquipmentData(hovered)) then return end
        tooltip:ClearLines()
        if tooltip.CompareHeader then tooltip.CompareHeader:Show() end
        tooltip:ProcessInfo({ tooltipData = data, append = true })
        local lines = R and R.NativeItemComparisonLines and R.NativeItemComparisonLines(hovered, data)
        if lines then
            tooltip:AddLine(" ")
            for _, line in ipairs(lines) do tooltip:AddLine(line[1], line[2], line[3], line[4], line[5]) end
        end
    end)
end
