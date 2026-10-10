local SLOT_ORDER = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19
}

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt",
    [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [11] = "Finger 1",
    [12] = "Finger 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main hand", [17] = "Off hand",
    [18] = "Ranged", [19] = "Tabard"
}

local BAG_FIRST = 0
local BAG_LAST = 4
local nextEquip = nil
local nativeVerification = nil
local updateElapsed = 0
local frame

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffbfwEquip:|r " .. message)
end

local function EnsureDatabase()
    if type(bfwEquipDB) ~= "table" then
        bfwEquipDB = {}
    end
    if type(bfwEquipDB.sets) ~= "table" then
        bfwEquipDB.sets = {}
    end
end

local function Trim(value)
    return string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
end

local function GetItemKey(link)
    if type(link) ~= "string" then
        return nil
    end
    local _, _, itemKey = string.find(link, "(item:[^|]+)")
    if itemKey then
        return itemKey
    end
    return nil
end

local function FindSet(name)
    local wanted = string.lower(name)
    for savedName, slots in pairs(bfwEquipDB.sets) do
        if type(savedName) == "string" and string.lower(savedName) == wanted then
            return savedName, slots
        end
    end
    return nil, nil
end

local function SaveSet(name)
    local _, existing = FindSet(name)
    local savedName = name
    if existing then
        for key in pairs(bfwEquipDB.sets) do
            if type(key) == "string" and string.lower(key) == string.lower(name) then
                savedName = key
                break
            end
        end
    end

    local slots = {}
    local count = 0
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        local slot = SLOT_ORDER[index]
        local link = GetInventoryItemLink("player", slot)
        if link then
            slots[slot] = link
            count = count + 1
        end
    end

    bfwEquipDB.sets[savedName] = slots
    Print("Saved \"" .. savedName .. "\" with " .. count .. " equipped items.")

    local equipmentAPI = C_EquipmentSet
    if type(equipmentAPI) == "table"
        and type(equipmentAPI.GetEquipmentSetID) == "function"
        and type(equipmentAPI.CreateEquipmentSet) == "function"
        and type(equipmentAPI.SaveEquipmentSet) == "function" then
        local setID
        local ok, errorMessage = pcall(function()
            setID = equipmentAPI.GetEquipmentSetID(savedName)
            if not setID then
                equipmentAPI.CreateEquipmentSet(savedName)
                setID = equipmentAPI.GetEquipmentSetID(savedName)
            end
            if not setID then
                error("the client did not return an equipment set ID")
            end
            equipmentAPI.SaveEquipmentSet(setID)
        end)
        if ok then
            Print("Also saved as a native client equipment set.")
        else
            Print("The SavedVariables copy is safe, but native set sync failed: " ..
                tostring(errorMessage))
        end
    end
end

local function ListSets()
    local names = {}
    local name
    for name in pairs(bfwEquipDB.sets) do
        if type(name) == "string" then
            table.insert(names, name)
        end
    end
    table.sort(names, function(left, right)
        return string.lower(left) < string.lower(right)
    end)

    if table.getn(names) == 0 then
        Print("No saved gear sets. Use /bfwequip save <name>.")
        return
    end

    local index
    for index = 1, table.getn(names) do
        Print(names[index])
    end
end

local function FindBagItem(itemKey)
    local bag
    local slot
    for bag = BAG_FIRST, BAG_LAST do
        local itemCount = GetContainerNumSlots(bag) or 0
        for slot = 1, itemCount do
            local link = GetContainerItemLink(bag, slot)
            if GetItemKey(link) == itemKey then
                local _, _, locked = GetContainerItemInfo(bag, slot)
                if not locked then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

local function IsInCombat()
    return UnitAffectingCombat and UnitAffectingCombat("player")
end

local function FinishEquip()
    local result = nextEquip
    nextEquip = nil
    nativeVerification = nil
    frame:SetScript("OnUpdate", nil)
    if result.missing > 0 then
        Print("PARTIAL: \"" .. result.name .. "\" equipped " ..
            result.equipped .. " item(s); " .. result.already ..
            " already equipped; " .. result.missing ..
            " unavailable or incompatible. Missing: " ..
            table.concat(result.missingNames, ", ") .. ".")
    else
        Print("Equipped \"" .. result.name .. "\": " ..
            result.equipped .. " item(s) changed, " .. result.already ..
            " already equipped.")
    end
end

local function StopForCombat()
    local result = nextEquip
    nextEquip = nil
    nativeVerification = nil
    frame:SetScript("OnUpdate", nil)
    Print("Stopped \"" .. result.name .. "\": " .. result.equipped ..
        " item(s) changed, " .. result.already ..
        " already equipped. Remaining pieces were not attempted because combat began.")
end

local function VerifyNativeEquip()
    local result = nativeVerification
    nativeVerification = nil
    frame:SetScript("OnUpdate", nil)

    local expected = 0
    local equipped = 0
    local missingNames = {}
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        local inventorySlot = SLOT_ORDER[index]
        local expectedKey = GetItemKey(result.slots[inventorySlot])
        if expectedKey then
            expected = expected + 1
            if GetItemKey(GetInventoryItemLink("player", inventorySlot)) == expectedKey then
                equipped = equipped + 1
            else
                table.insert(missingNames, SLOT_NAMES[inventorySlot])
            end
        end
    end

    if table.getn(missingNames) > 0 then
        Print("PARTIAL: native equip of \"" .. result.name .. "\" verified " ..
            equipped .. "/" .. expected .. " items. Not equipped: " ..
            table.concat(missingNames, ", ") .. ".")
    else
        Print("Native equip of \"" .. result.name .. "\" verified: " ..
            equipped .. "/" .. expected .. " saved items present.")
    end
end

local function BeginNativeVerification(name, slots)
    nativeVerification = {
        name = name,
        slots = slots,
        remaining = 1.5
    }
    updateElapsed = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        if not nativeVerification then
            frame:SetScript("OnUpdate", nil)
            return
        end
        nativeVerification.remaining = nativeVerification.remaining - elapsed
        if nativeVerification.remaining <= 0 then
            VerifyNativeEquip()
        end
    end)
    Print("Requested native equip of \"" .. name .. "\"; checking equipped items shortly.")
end

local function ProcessNextItem()
    if not nextEquip then
        return
    end
    if IsInCombat() then
        StopForCombat()
        return
    end

    local result = nextEquip
    if result.index > table.getn(SLOT_ORDER) then
        FinishEquip()
        return
    end

    local inventorySlot = SLOT_ORDER[result.index]
    result.index = result.index + 1

    local link = result.slots[inventorySlot]
    if not link then
        return
    end

    local itemKey = GetItemKey(link)
    if not itemKey then
        result.missing = result.missing + 1
        table.insert(result.missingNames, SLOT_NAMES[inventorySlot] .. " (invalid saved item)")
        return
    end

    if GetItemKey(GetInventoryItemLink("player", inventorySlot)) == itemKey then
        result.already = result.already + 1
        return
    end

    if CursorHasItem() then
        result.missing = result.missing + 1
        table.insert(result.missingNames, SLOT_NAMES[inventorySlot] .. " (cursor is occupied)")
        result.index = table.getn(SLOT_ORDER) + 1
        return
    end

    local bag, bagSlot = FindBagItem(itemKey)
    if not bag then
        result.missing = result.missing + 1
        table.insert(result.missingNames, SLOT_NAMES[inventorySlot])
        return
    end

    PickupContainerItem(bag, bagSlot)
    if not CursorHasItem() then
        result.missing = result.missing + 1
        table.insert(result.missingNames, SLOT_NAMES[inventorySlot] .. " (bag item could not be picked up)")
        return
    end

    PickupInventoryItem(inventorySlot)
    if CursorHasItem() then
        PickupContainerItem(bag, bagSlot)
    end

    if CursorHasItem() then
        result.missing = result.missing + 1
        table.insert(result.missingNames, SLOT_NAMES[inventorySlot] .. " (could not safely finish swap)")
        result.index = table.getn(SLOT_ORDER) + 1
    elseif GetItemKey(GetInventoryItemLink("player", inventorySlot)) == itemKey then
        result.equipped = result.equipped + 1
    else
        result.missing = result.missing + 1
        table.insert(result.missingNames, SLOT_NAMES[inventorySlot] .. " (item was not accepted)")
    end
end

local function BeginEquip(name)
    local savedName, slots = FindSet(name)
    if not savedName or type(slots) ~= "table" then
        Print("No saved set named \"" .. name .. "\".")
        return
    end
    if IsInCombat() then
        Print("Cannot equip a set during combat.")
        return
    end
    if CursorHasItem() then
        Print("Cannot equip a set while your cursor is holding an item.")
        return
    end
    if nextEquip or nativeVerification then
        Print("Another set is still being equipped; wait for it to finish.")
        return
    end

    local equipmentAPI = C_EquipmentSet
    if type(equipmentAPI) == "table"
        and type(equipmentAPI.GetEquipmentSetID) == "function"
        and type(equipmentAPI.UseEquipmentSet) == "function" then
        local setID = equipmentAPI.GetEquipmentSetID(savedName)
        if setID then
            local ok, errorMessage = pcall(equipmentAPI.UseEquipmentSet, setID)
            if ok then
                BeginNativeVerification(savedName, slots)
                return
            end
            Print("Native equip failed; falling back to bags: " .. tostring(errorMessage))
        end
    end

    nextEquip = {
        name = savedName,
        slots = slots,
        index = 1,
        equipped = 0,
        already = 0,
        missing = 0,
        missingNames = {}
    }
    updateElapsed = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= 0.1 then
            updateElapsed = 0
            ProcessNextItem()
        end
    end)
end

local function DeleteSet(name)
    local savedName = FindSet(name)
    if not savedName then
        Print("No saved set named \"" .. name .. "\".")
        return
    end
    bfwEquipDB.sets[savedName] = nil
    Print("Deleted \"" .. savedName .. "\".")

    local equipmentAPI = C_EquipmentSet
    if type(equipmentAPI) == "table"
        and type(equipmentAPI.GetEquipmentSetID) == "function"
        and type(equipmentAPI.DeleteEquipmentSet) == "function" then
        local setID = equipmentAPI.GetEquipmentSetID(savedName)
        if setID then
            local ok, errorMessage = pcall(equipmentAPI.DeleteEquipmentSet, setID)
            if ok then
                Print("Also deleted the matching native client equipment set.")
            else
                Print("The SavedVariables copy was deleted, but native set deletion failed: " ..
                    tostring(errorMessage))
            end
        end
    end
end

local function HandleSlashCommand(message)
    EnsureDatabase()
    local matchStart, matchEnd, command, argument =
        string.find(message, "^%s*(%S+)%s*(.-)%s*$")
    if not command or command == "" or string.lower(command) == "help" then
        Print("Commands: /bfwequip save <name>, list, equip <name>, delete <name>.")
        return
    end

    command = string.lower(command)
    argument = Trim(argument or "")
    if command == "save" then
        if argument == "" then
            Print("Usage: /bfwequip save <name>")
        else
            SaveSet(argument)
        end
    elseif command == "list" then
        ListSets()
    elseif command == "equip" then
        if argument == "" then
            Print("Usage: /bfwequip equip <name>")
        else
            BeginEquip(argument)
        end
    elseif command == "delete" then
        if argument == "" then
            Print("Usage: /bfwequip delete <name>")
        else
            DeleteSet(argument)
        end
    else
        Print("Unknown command. Use /bfwequip help.")
    end
end

frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    EnsureDatabase()
end)

SLASH_BFWEQUIP1 = "/bfwequip"
SLASH_BFWEQUIP2 = "/bfwe"
SlashCmdList["BFWEQUIP"] = HandleSlashCommand
