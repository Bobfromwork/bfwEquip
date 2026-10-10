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

local TRINKET_SLOTS = { 13, 14 }
local WEAPON_SLOTS = { 16, 17 }

local BAG_FIRST = 0
local BAG_LAST = 4
local EQUIP_OPERATION_SETTLE_TIME = 0.005
local EQUIP_OPERATION_TIMEOUT = 1.5
local WEAPON_RETRY_PASSES = 1
local nextEquip = nil
local nativeVerification = nil
local frame
local mainWindow
local RefreshUI
local SetUIStatus
local ToggleMainWindow
local MIN_WINDOW_WIDTH = 380
local MIN_WINDOW_HEIGHT = 370
local MAX_WINDOW_WIDTH = 900
local MAX_WINDOW_HEIGHT = 760
local INITIAL_WINDOW_WIDTH = 400
local INITIAL_WINDOW_HEIGHT = 400
local MAX_HOTKEY_SLOTS = 10

BINDING_HEADER_BFWEQUIP = "bfwEquip"
local hotkeySlot
for hotkeySlot = 1, MAX_HOTKEY_SLOTS do
    _G["BINDING_NAME_BFWEQUIP_SET_" .. hotkeySlot] =
        "Equip Gear Set Hotkey Slot " .. hotkeySlot
end
BINDING_NAME_BFWEQUIP_TOGGLE_WINDOW = "Toggle bfwEquip Window"

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
    if type(bfwEquipDB.hotkeys) ~= "table" then
        bfwEquipDB.hotkeys = {}
    end
    if type(bfwEquipDB.partialSets) ~= "table" then
        bfwEquipDB.partialSets = {}
    end
end

local function ClampWindowSize(width, height)
    width = math.max(MIN_WINDOW_WIDTH, math.min(MAX_WINDOW_WIDTH, width))
    height = math.max(MIN_WINDOW_HEIGHT, math.min(MAX_WINDOW_HEIGHT, height))
    return width, height
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

local function GetHotkeySlot(name)
    for slot = 1, MAX_HOTKEY_SLOTS do
        if bfwEquipDB.hotkeys[slot] == name then
            return slot
        end
    end
    return nil
end

local function BindSetHotkey(name, slot)
    local savedName = FindSet(name)
    if not savedName then
        Print("No saved set named \"" .. name .. "\".")
        return false
    end

    local oldSlot = GetHotkeySlot(savedName)
    if oldSlot then
        bfwEquipDB.hotkeys[oldSlot] = nil
    end

    if slot then
        if slot < 1 or slot > MAX_HOTKEY_SLOTS or slot ~= math.floor(slot) then
            Print("Hotkey slot must be from 1 to " .. MAX_HOTKEY_SLOTS .. ".")
            if oldSlot then
                bfwEquipDB.hotkeys[oldSlot] = savedName
            end
            return false
        end

        local previousName = bfwEquipDB.hotkeys[slot]
        if previousName and previousName ~= savedName then
            Print("Hotkey slot " .. slot .. " was unassigned from \"" ..
                previousName .. "\".")
        end
        bfwEquipDB.hotkeys[slot] = savedName
        Print("Bound \"" .. savedName .. "\" to bfwEquip hotkey slot " .. slot ..
            ". Set its key in Escape > Key Bindings > bfwEquip.")
    else
        Print("Removed the hotkey assignment for \"" .. savedName .. "\".")
    end

    if RefreshUI then
        RefreshUI(savedName)
    end
    return true, bag, bagSlot
end

local function IsFullSlotSelection(slotSelection)
    if not slotSelection then
        return true
    end

    local index
    for index = 1, table.getn(SLOT_ORDER) do
        if not slotSelection[SLOT_ORDER[index]] then
            return false
        end
    end
    return true
end

local function CountSelectedSlots(slotSelection)
    if not slotSelection then
        return table.getn(SLOT_ORDER)
    end

    local count = 0
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        if slotSelection[SLOT_ORDER[index]] then
            count = count + 1
        end
    end
    return count
end

local function SaveSet(name, preserveName, slotSelection)
    if CountSelectedSlots(slotSelection) == 0 then
        if SetUIStatus then
            SetUIStatus("Select at least one gear slot to save.")
        end
        return false
    end

    local _, existing = FindSet(name)
    local savedName = name
    if existing and not preserveName then
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
        if link and (not slotSelection or slotSelection[slot]) then
            slots[slot] = link
            count = count + 1
        end
    end

    bfwEquipDB.sets[savedName] = slots
    local fullSelection = IsFullSlotSelection(slotSelection)
    if fullSelection then
        bfwEquipDB.partialSets[savedName] = nil
    else
        bfwEquipDB.partialSets[savedName] = true
    end
    Print("Saved \"" .. savedName .. "\" with " .. count .. " equipped items.")
    if not fullSelection then
        Print("This is a partial set; only its selected gear slots will be equipped.")
    end
    if RefreshUI then
        RefreshUI(savedName)
    end
    if SetUIStatus then
        SetUIStatus("Saved " .. savedName .. ".")
    end

    local equipmentAPI = C_EquipmentSet
    if fullSelection
        and type(equipmentAPI) == "table"
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
    return true
end

local function OverwriteSet(selectedName, requestedName, slotSelection)
    local savedName = FindSet(selectedName)
    if not savedName then
        SetUIStatus("The selected set no longer exists.")
        RefreshUI()
        return false
    end

    local targetName = requestedName
    if targetName == "" then
        targetName = savedName
    end

    local conflictingName = FindSet(targetName)
    if conflictingName and conflictingName ~= savedName then
        SetUIStatus("\"" .. conflictingName ..
            "\" already exists. Choose another name or select that set.")
        return false
    end

    if not SaveSet(targetName, true, slotSelection) then
        return false
    end

    if targetName ~= savedName then
        bfwEquipDB.sets[savedName] = nil
        bfwEquipDB.partialSets[savedName] = nil
        local slot
        for slot = 1, MAX_HOTKEY_SLOTS do
            if bfwEquipDB.hotkeys[slot] == savedName then
                bfwEquipDB.hotkeys[slot] = targetName
            end
        end

        local equipmentAPI = C_EquipmentSet
        if type(equipmentAPI) == "table"
            and type(equipmentAPI.GetEquipmentSetID) == "function"
            and type(equipmentAPI.DeleteEquipmentSet) == "function" then
            local ok, errorMessage = pcall(function()
                local setID = equipmentAPI.GetEquipmentSetID(savedName)
                if setID then
                    equipmentAPI.DeleteEquipmentSet(setID)
                end
            end)
            if not ok then
                Print("The addon set was renamed, but the old native set could not be removed: " ..
                    tostring(errorMessage))
            end
        end

        Print("Renamed \"" .. savedName .. "\" to \"" .. targetName .. "\".")
        if RefreshUI then
            RefreshUI(targetName)
        end
    end

    return true
end

local function SaveNewSet(name, slotSelection)
    if name == "" then
        if SetUIStatus then
            SetUIStatus("Enter a name before saving.")
        end
        return false
    end

    local existingName = FindSet(name)
    if existingName then
        if SetUIStatus then
            SetUIStatus("\"" .. existingName ..
                "\" already exists. Select it to overwrite that set.")
        end
        return false
    end

    return SaveSet(name, false, slotSelection)
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

local function FindEmptyBagSlot()
    local bag
    local slot
    for bag = BAG_FIRST, BAG_LAST do
        local itemCount = GetContainerNumSlots(bag) or 0
        for slot = 1, itemCount do
            if not GetContainerItemLink(bag, slot) then
                return bag, slot
            end
        end
    end
    return nil, nil
end

local function FindEquippedSourceSlot(itemKey, slots, targetSlot)
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        local sourceSlot = SLOT_ORDER[index]
        if sourceSlot ~= targetSlot
            and slots[sourceSlot]
            and GetItemKey(GetInventoryItemLink("player", sourceSlot)) == itemKey then
            return sourceSlot
        end
    end
    return nil
end

local function StowEquippedItem(sourceSlot)
    if CursorHasItem() then
        return false, false, "cursor is occupied"
    end

    local bag, bagSlot = FindEmptyBagSlot()
    if not bag then
        return false, true, "no empty bag slot to move the equipped item"
    end

    PickupInventoryItem(sourceSlot)
    if not CursorHasItem() then
        return false, true, "equipped item could not be picked up"
    end

    PickupContainerItem(bag, bagSlot)
    if CursorHasItem() then
        PickupInventoryItem(sourceSlot)
        return false, not CursorHasItem(),
            "could not safely stow the equipped item in bags"
    end
    return true, nil, nil, bag, bagSlot
end

local function IsInCombat()
    return UnitAffectingCombat and UnitAffectingCombat("player")
end

local function RecordSlotError(result, slot, message)
    result.slotErrors[slot] = message
end

local function BuildEquipOrder(slots)
    local order = {}
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        table.insert(order, SLOT_ORDER[index])
    end
    local pass
    for pass = 1, WEAPON_RETRY_PASSES do
        for index = 1, table.getn(WEAPON_SLOTS) do
            local slot = WEAPON_SLOTS[index]
            if slots[slot] then
                table.insert(order, slot)
            end
        end
    end
    return order
end

local function HasCrossHandWeaponSwap(slots)
    return (GetItemKey(slots[16]) ~= nil
            and GetItemKey(slots[16]) ==
                GetItemKey(GetInventoryItemLink("player", 17)))
        or (GetItemKey(slots[17]) ~= nil
            and GetItemKey(slots[17]) ==
                GetItemKey(GetInventoryItemLink("player", 16)))
end

local function ReportEquipResult()
    local result = nextEquip
    nextEquip = nil
    nativeVerification = nil
    frame:SetScript("OnUpdate", nil)
    if result.missing > 0 then
        if SetUIStatus then
            SetUIStatus("Partial: " .. result.equipped .. " equipped; " ..
                result.missing .. " unavailable.")
        end
        Print("PARTIAL: \"" .. result.name .. "\" equipped " ..
            result.equipped .. " item(s); " .. result.already ..
            " already equipped; " .. result.missing ..
            " unavailable or incompatible. Missing: " ..
            table.concat(result.missingNames, ", ") .. ".")
    else
        if SetUIStatus then
            SetUIStatus("Equipped " .. result.name .. ".")
        end
        Print("Equipped \"" .. result.name .. "\": " ..
            result.equipped .. " item(s) changed, " .. result.already ..
            " already equipped.")
    end
end

local function VerifyBagEquip()
    local result = nextEquip
    if not result then
        frame:SetScript("OnUpdate", nil)
        return
    end

    result.equipped = 0
    result.already = 0
    result.missing = 0
    result.missingNames = {}
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        local inventorySlot = SLOT_ORDER[index]
        local expectedKey = GetItemKey(result.slots[inventorySlot])
        if expectedKey then
            if GetItemKey(GetInventoryItemLink("player", inventorySlot)) == expectedKey then
                result.slotErrors[inventorySlot] = nil
                if result.initialMatches[inventorySlot] then
                    result.already = result.already + 1
                else
                    result.equipped = result.equipped + 1
                end
            else
                result.missing = result.missing + 1
                table.insert(result.missingNames,
                    SLOT_NAMES[inventorySlot] .. " (" ..
                    (result.slotErrors[inventorySlot] or "item was not accepted") .. ")")
            end
        elseif result.slotErrors[inventorySlot] then
            result.missing = result.missing + 1
            table.insert(result.missingNames, SLOT_NAMES[inventorySlot] ..
                " (" .. result.slotErrors[inventorySlot] .. ")")
        end
    end

    ReportEquipResult()
end

local function FinishEquip()
    if not nextEquip then
        return
    end
    nextEquip.verifying = true
    nextEquip.verificationRemaining = 0.1
    frame:SetScript("OnUpdate", function(_, elapsed)
        if not nextEquip then
            frame:SetScript("OnUpdate", nil)
            return
        end
        nextEquip.verificationRemaining = nextEquip.verificationRemaining - elapsed
        if nextEquip.verificationRemaining <= 0 then
            VerifyBagEquip()
        end
    end)
end

local function StopForCombat()
    local result = nextEquip
    nextEquip = nil
    nativeVerification = nil
    frame:SetScript("OnUpdate", nil)
    if SetUIStatus then
        SetUIStatus("Equip stopped: combat began.")
    end
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
        if SetUIStatus then
            SetUIStatus("Partial: " .. equipped .. "/" .. expected .. " items equipped.")
        end
        Print("PARTIAL: native equip of \"" .. result.name .. "\" verified " ..
            equipped .. "/" .. expected .. " items. Not equipped: " ..
            table.concat(missingNames, ", ") .. ".")
    else
        if SetUIStatus then
            SetUIStatus("Equipped " .. result.name .. " (" .. equipped .. " items).")
        end
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
    if SetUIStatus then
        SetUIStatus("Equipping " .. name .. "...")
    end
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

local function CancelPendingEquip()
    if nextEquip then
        local result = nextEquip
        nextEquip = nil
        frame:SetScript("OnUpdate", nil)
        if result.verifying then
            Print("Replaced the pending result check for \"" .. result.name .. "\".")
        else
            Print("Replaced the in-progress equip of \"" .. result.name ..
                "\" after " .. result.equipped ..
                " item(s) changed; its remaining items will not be attempted.")
        end
        return
    end

    if nativeVerification then
        local result = nativeVerification
        nativeVerification = nil
        frame:SetScript("OnUpdate", nil)
        Print("Replaced the pending result check for native equip of \"" ..
            result.name .. "\" with a new equip request.")
    end
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
    if result.index > table.getn(result.order) then
        FinishEquip()
        return
    end

    local inventorySlot = result.order[result.index]
    result.index = result.index + 1

    local link = result.slots[inventorySlot]
    if not link then
        return
    end

    local itemKey = GetItemKey(link)
    if not itemKey then
        RecordSlotError(result, inventorySlot, "invalid saved item")
        return
    end

    if GetItemKey(GetInventoryItemLink("player", inventorySlot)) == itemKey then
        result.already = result.already + 1
        return
    end

    if CursorHasItem() then
        RecordSlotError(result, inventorySlot, "cursor is occupied")
        result.index = table.getn(result.order) + 1
        return
    end

    local bag, bagSlot = FindBagItem(itemKey)
    if not bag then
        local sourceSlot = FindEquippedSourceSlot(itemKey, result.slots, inventorySlot)
        if sourceSlot then
            local stowed, safe, reason, stowBag, stowBagSlot =
                StowEquippedItem(sourceSlot)
            if stowed then
                result.pendingOperation = {
                    kind = "stow",
                    itemKey = itemKey,
                    sourceSlot = sourceSlot,
                    bag = stowBag,
                    bagSlot = stowBagSlot,
                    slot = inventorySlot,
                    elapsed = 0,
                    stableElapsed = 0
                }
                result.index = 1
                return true
            end

            RecordSlotError(result, inventorySlot, reason)
            if not safe then
                result.index = table.getn(result.order) + 1
            end
            return true
        end

        RecordSlotError(result, inventorySlot, "item unavailable in bags")
        return false
    end

    PickupContainerItem(bag, bagSlot)
    if not CursorHasItem() then
        RecordSlotError(result, inventorySlot, "bag item could not be picked up")
        return true
    end

    PickupInventoryItem(inventorySlot)
    if CursorHasItem() then
        PickupContainerItem(bag, bagSlot)
    end

    if CursorHasItem() then
        RecordSlotError(result, inventorySlot, "could not safely finish swap")
        result.index = table.getn(result.order) + 1
        return true
    else
        result.verifySlots[inventorySlot] = true
        result.pendingOperation = {
            kind = "equip",
            itemKey = itemKey,
            inventorySlot = inventorySlot,
            slot = inventorySlot,
            elapsed = 0,
            stableElapsed = 0
        }
        return true
    end
end

local ProcessEquipImmediately
local WaitForEquipOperation

ProcessEquipImmediately = function()
    while nextEquip and not nextEquip.verifying do
        if IsInCombat() then
            StopForCombat()
            return
        end

        if nextEquip.index > table.getn(nextEquip.order) then
            FinishEquip()
            return
        end

        local itemOperationStarted = ProcessNextItem()
        if itemOperationStarted then
            frame:SetScript("OnUpdate", WaitForEquipOperation)
            return
        end
    end
end

WaitForEquipOperation = function(_, elapsed)
    if not nextEquip or nextEquip.verifying then
        frame:SetScript("OnUpdate", nil)
        return
    end
    if IsInCombat() then
        StopForCombat()
        return
    end

    local result = nextEquip
    local operation = result.pendingOperation
    if not operation then
        ProcessEquipImmediately()
        return
    end

    operation.elapsed = operation.elapsed + elapsed
    local settled
    if operation.kind == "stow" then
        settled = GetItemKey(GetInventoryItemLink("player", operation.sourceSlot)) ~=
                operation.itemKey
            and GetItemKey(GetContainerItemLink(operation.bag, operation.bagSlot)) ==
                operation.itemKey
    else
        settled = GetItemKey(GetInventoryItemLink("player", operation.inventorySlot)) ==
            operation.itemKey
    end

    if settled then
        operation.stableElapsed = operation.stableElapsed + elapsed
        if operation.stableElapsed >= EQUIP_OPERATION_SETTLE_TIME then
            result.pendingOperation = nil
            ProcessEquipImmediately()
            return
        end
    else
        operation.stableElapsed = 0
    end

    if operation.elapsed >= EQUIP_OPERATION_TIMEOUT then
        RecordSlotError(result, operation.slot,
            "inventory did not settle after item transfer")
        result.index = table.getn(result.order) + 1
        result.pendingOperation = nil
        FinishEquip()
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
        CancelPendingEquip()
    end

    local equipmentAPI = C_EquipmentSet
    if not bfwEquipDB.partialSets[savedName]
        and not HasCrossHandWeaponSwap(slots)
        and type(equipmentAPI) == "table"
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
        order = BuildEquipOrder(slots),
        verifySlots = {},
        initialMatches = {},
        slotErrors = {},
        index = 1,
        equipped = 0,
        already = 0,
        missing = 0,
        missingNames = {}
    }
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        local slot = SLOT_ORDER[index]
        local expectedKey = GetItemKey(slots[slot])
        nextEquip.initialMatches[slot] = expectedKey ~= nil
            and GetItemKey(GetInventoryItemLink("player", slot)) == expectedKey
    end
    if SetUIStatus then
        SetUIStatus("Equipping " .. savedName .. "...")
    end
    ProcessEquipImmediately()
end

function BFWEQUIP_EquipHotkey(slot)
    EnsureDatabase()
    local name = bfwEquipDB.hotkeys[slot]
    if not name then
        Print("No gear set is assigned to hotkey slot " .. tostring(slot) .. ".")
        return
    end
    if not bfwEquipDB.sets[name] then
        bfwEquipDB.hotkeys[slot] = nil
        Print("The saved set for hotkey slot " .. slot .. " no longer exists.")
        if RefreshUI then
            RefreshUI()
        end
        return
    end
    BeginEquip(name)
end

local function DeleteSet(name)
    local savedName = FindSet(name)
    if not savedName then
        Print("No saved set named \"" .. name .. "\".")
        return
    end
    bfwEquipDB.sets[savedName] = nil
    bfwEquipDB.partialSets[savedName] = nil
    local slot
    for slot = 1, MAX_HOTKEY_SLOTS do
        if bfwEquipDB.hotkeys[slot] == savedName then
            bfwEquipDB.hotkeys[slot] = nil
        end
    end
    Print("Deleted \"" .. savedName .. "\".")
    if RefreshUI then
        RefreshUI()
    end
    if SetUIStatus then
        SetUIStatus("Deleted " .. savedName .. ".")
    end

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
    if not command or command == "" then
        ToggleMainWindow()
        return
    end

    if string.lower(command) == "help" then
        Print("Commands: /bfwequip (open UI), save <name>, list, equip <name>, delete <name>, bind <name> <slot|off>, close.")
        return
    end

    command = string.lower(command)
    argument = Trim(argument or "")
    if command == "ui" or command == "open" or command == "toggle" then
        ToggleMainWindow()
    elseif command == "close" then
        mainWindow:Hide()
    elseif command == "save" then
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
    elseif command == "bind" then
        local _, _, setName, slotName = string.find(argument, "^(.-)%s+(%S+)$")
        if not setName or setName == "" then
            Print("Usage: /bfwequip bind <name> <1-" .. MAX_HOTKEY_SLOTS .. "|off>")
        elseif string.lower(slotName) == "off" or string.lower(slotName) == "none" then
            BindSetHotkey(setName, nil)
        else
            local slot = tonumber(slotName)
            if not slot then
                Print("Hotkey slot must be from 1 to " .. MAX_HOTKEY_SLOTS .. " or off.")
            else
                BindSetHotkey(setName, slot)
            end
        end
    else
        Print("Unknown command. Use /bfwequip help.")
    end
end

local selectedSet
local statusText
local nameInput
local dropdownButton
local saveScopeDropdown
local saveDropdown
local hotkeyButton
local selectedSaveSlots = {}
local AddDropdownMenuItem
local RefreshSaveSlotSelectionLabel
local SetSaveSlotSelection
local InitializeSaveSlotDropdown
local selectedSlotIndex
for selectedSlotIndex = 1, table.getn(SLOT_ORDER) do
    selectedSaveSlots[SLOT_ORDER[selectedSlotIndex]] = true
end

SetSaveSlotSelection = function(slots)
    local index
    for index = 1, table.getn(SLOT_ORDER) do
        selectedSaveSlots[SLOT_ORDER[index]] = false
    end
    for index = 1, table.getn(slots) do
        selectedSaveSlots[slots[index]] = true
    end
    RefreshSaveSlotSelectionLabel()
end

RefreshSaveSlotSelectionLabel = function()
    local count = CountSelectedSlots(selectedSaveSlots)
    local label
    if count == table.getn(SLOT_ORDER) then
        label = "Save slots: All"
    elseif selectedSaveSlots[13] and selectedSaveSlots[14] and count == 2 then
        label = "Save slots: Trinkets"
    elseif selectedSaveSlots[16] and selectedSaveSlots[17] and count == 2 then
        label = "Save slots: Main + Off Hand"
    else
        label = "Save slots: " .. count .. "/" .. table.getn(SLOT_ORDER)
    end
    UIDropDownMenu_SetText(label, saveScopeDropdown)
end

InitializeSaveSlotDropdown = function()
    local presets = {
        { text = "All Slots", slots = SLOT_ORDER },
        { text = "Trinkets Only", slots = TRINKET_SLOTS },
        { text = "Main + Off Hand", slots = WEAPON_SLOTS }
    }

    local index
    for index = 1, table.getn(presets) do
        local preset = presets[index]
        local info = {}
        info.text = preset.text
        info.notCheckable = 1
        info.func = function()
            SetSaveSlotSelection(preset.slots)
        end
        AddDropdownMenuItem(info)
    end

    local title = {}
    title.text = "Individual Slots"
    title.isTitle = 1
    title.notCheckable = 1
    AddDropdownMenuItem(title)

    for index = 1, table.getn(SLOT_ORDER) do
        local slot = SLOT_ORDER[index]
        local info = {}
        info.text = SLOT_NAMES[slot]
        info.value = slot
        info.checked = selectedSaveSlots[slot]
        info.keepShownOnClick = 1
        info.func = function()
            selectedSaveSlots[slot] = not selectedSaveSlots[slot]
            local menuButton = this
            if menuButton and menuButton.GetName then
                local check = _G[menuButton:GetName() .. "Check"]
                if check then
                    if selectedSaveSlots[slot] then
                        check:Show()
                    else
                        check:Hide()
                    end
                end
            end
            RefreshSaveSlotSelectionLabel()
        end
        AddDropdownMenuItem(info)
    end
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(height)
    button:SetText(text)
    return button
end

AddDropdownMenuItem = function(info, level)
    UIDropDownMenu_AddButton(info, level)

    local menuLevel = level or UIDROPDOWNMENU_MENU_LEVEL or 1
    local list = _G["DropDownList" .. menuLevel]
    if not list then
        return
    end

    local index
    for index = 1, list.numButtons or 0 do
        local button = _G["DropDownList" .. menuLevel .. "Button" .. index]
        if button and button:GetName() then
            local check = _G[button:GetName() .. "Check"]
            if check then
                check:ClearAllPoints()
                check:SetPoint("RIGHT", button, "RIGHT", -4, 0)
            end

            local text = _G[button:GetName() .. "NormalText"]
            if text then
                text:ClearAllPoints()
                text:SetPoint("LEFT", button, "LEFT",
                    button.notCheckable and 1 or 24, 0)
                text:SetPoint("RIGHT", button, "RIGHT",
                    button.notCheckable and -8 or -24, 0)
            end
        end
    end
end

SetUIStatus = function(message)
    if statusText then
        statusText:SetText(message or "")
    end
end

RefreshUI = function(preferredSelection)
    if not dropdownButton then
        return
    end

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

    if preferredSelection then
        selectedSet = preferredSelection
    elseif selectedSet and not bfwEquipDB.sets[selectedSet] then
        selectedSet = nil
    end
    if not selectedSet and table.getn(names) > 0 then
        selectedSet = names[1]
    end

    UIDropDownMenu_SetSelectedValue(dropdownButton, selectedSet)
    UIDropDownMenu_SetText(selectedSet or "Select a saved set", dropdownButton)
    if hotkeyButton then
        local assignedSlot = selectedSet and GetHotkeySlot(selectedSet)
        if assignedSlot then
            hotkeyButton:SetText("Clear Hotkey (Slot " .. assignedSlot .. ")")
        else
            hotkeyButton:SetText("Bind Hotkey")
        end
    end
end

local function InitializeSetDropdown()
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

    local index
    for index = 1, table.getn(names) do
        local info = {}
        info.text = names[index]
        info.value = names[index]
        info.checked = names[index] == selectedSet
        info.func = function()
            selectedSet = this.value
            RefreshUI()
        end
        AddDropdownMenuItem(info)
    end
end

ToggleMainWindow = function()
    if mainWindow:IsShown() then
        mainWindow:Hide()
    else
        EnsureDatabase()
        RefreshUI()
        mainWindow:Show()
    end
end

function BFWEQUIP_ToggleWindow()
    if ToggleMainWindow then
        ToggleMainWindow()
    end
end

local function CreateMainWindow()
    mainWindow = CreateFrame("Frame", "bfwEquipMainWindow", UIParent)
    local initialWidth = bfwEquipDB.windowWidth
    local initialHeight = bfwEquipDB.windowHeight
    if type(initialWidth) ~= "number" then
        initialWidth = INITIAL_WINDOW_WIDTH
    end
    if type(initialHeight) ~= "number" then
        initialHeight = INITIAL_WINDOW_HEIGHT
    end
    initialWidth, initialHeight = ClampWindowSize(initialWidth, initialHeight)
    mainWindow:SetWidth(initialWidth)
    mainWindow:SetHeight(initialHeight)
    mainWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainWindow:SetFrameStrata("DIALOG")
    mainWindow:SetMovable(true)
    mainWindow:EnableMouse(true)
    mainWindow:SetResizable(true)
    if mainWindow.SetMinResize then
        mainWindow:SetMinResize(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)
    end
    if mainWindow.SetMaxResize then
        mainWindow:SetMaxResize(MAX_WINDOW_WIDTH, MAX_WINDOW_HEIGHT)
    end
    mainWindow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    mainWindow:SetBackdropColor(0.04, 0.04, 0.04, 0.96)
    mainWindow:SetBackdropBorderColor(0.55, 0.45, 0.22, 1)

    local titleBar = CreateFrame("Frame", nil, mainWindow)
    titleBar:SetPoint("TOPLEFT", mainWindow, "TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", mainWindow, "TOPRIGHT", -42, -8)
    titleBar:SetHeight(30)
    titleBar:SetFrameLevel(mainWindow:GetFrameLevel() + 1)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    titleBar:SetBackdropColor(0.16, 0.13, 0.08, 1)
    titleBar:SetBackdropBorderColor(0.55, 0.45, 0.22, 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        mainWindow:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        mainWindow:StopMovingOrSizing()
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText("bfwEquip")

    local closeButton = CreateFrame("Button", nil, mainWindow, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", mainWindow, "TOPRIGHT", -4, -4)
    closeButton:SetFrameLevel(titleBar:GetFrameLevel() + 1)
    closeButton:SetScript("OnClick", function()
        mainWindow:Hide()
    end)

    local listTitle = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", mainWindow, "TOPLEFT", 18, -50)
    listTitle:SetText("Saved gear set")

    dropdownButton = CreateFrame("Frame", "bfwEquipSetDropdown", mainWindow, "UIDropDownMenuTemplate")
    dropdownButton:SetPoint("TOPLEFT", mainWindow, "TOPLEFT", 8, -68)
    UIDropDownMenu_SetWidth(324, dropdownButton)
    UIDropDownMenu_Initialize(dropdownButton, InitializeSetDropdown)

    saveScopeDropdown = CreateFrame("Frame", "bfwEquipSaveSlotsDropdown", mainWindow, "UIDropDownMenuTemplate")
    saveScopeDropdown:SetPoint("TOPLEFT", dropdownButton, "BOTTOMLEFT", -10, -4)
    UIDropDownMenu_SetWidth(250, saveScopeDropdown)
    RefreshSaveSlotSelectionLabel()
    UIDropDownMenu_Initialize(saveScopeDropdown, InitializeSaveSlotDropdown)

    local nameLabel = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", saveScopeDropdown, "BOTTOMLEFT", 18, -8)
    nameLabel:SetText("Set name:")

    nameInput = CreateFrame("EditBox", "bfwEquipNameInput", mainWindow)
    nameInput:SetWidth(215)
    nameInput:SetHeight(24)
    nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
    nameInput:SetAutoFocus(false)
    nameInput:SetFontObject(GameFontHighlight)
    nameInput:SetTextInsets(6, 6, 2, 2)
    nameInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    nameInput:SetBackdropColor(0.08, 0.08, 0.08, 1)
    nameInput:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    nameInput:SetScript("OnEnterPressed", function(self)
        local name = Trim(self:GetText() or "")
        if SaveNewSet(name, selectedSaveSlots) then
            self:SetText("")
            self:ClearFocus()
        end
    end)
    nameInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    saveDropdown = CreateFrame("Frame", "bfwEquipSaveDropdown", mainWindow, "UIDropDownMenuTemplate")
    saveDropdown:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", -10, -4)
    UIDropDownMenu_SetWidth(112, saveDropdown)
    UIDropDownMenu_SetText("Save Current", saveDropdown)
    UIDropDownMenu_Initialize(saveDropdown, function()
        local saveInfo = {}
        saveInfo.text = "Save as New Set"
        saveInfo.notCheckable = 1
        saveInfo.func = function()
            local name = Trim(nameInput:GetText() or "")
            if SaveNewSet(name, selectedSaveSlots) then
                nameInput:SetText("")
                nameInput:ClearFocus()
            elseif name == "" then
                nameInput:SetFocus()
            end
        end
        AddDropdownMenuItem(saveInfo)

        local overwriteInfo = {}
        overwriteInfo.text = "Overwrite Selected Set"
        overwriteInfo.notCheckable = 1
        overwriteInfo.func = function()
            if not selectedSet then
                SetUIStatus("Select a saved set to overwrite.")
                return
            end

            local name = Trim(nameInput:GetText() or "")
            if OverwriteSet(selectedSet, name, selectedSaveSlots) then
                nameInput:SetText("")
                nameInput:ClearFocus()
            end
        end
        AddDropdownMenuItem(overwriteInfo)
    end)

    local deleteButton = CreateButton(mainWindow, "Delete", 76, 26)
    deleteButton:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 122, -4)
    deleteButton:SetScript("OnClick", function()
        if not selectedSet then
            SetUIStatus("Select a saved set first.")
            return
        end
        StaticPopup_Show("BFWEQUIP_CONFIRM_DELETE", selectedSet)
    end)

    hotkeyButton = CreateButton(mainWindow, "Bind Hotkey", 130, 26)
    hotkeyButton:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -44)
    hotkeyButton:SetScript("OnClick", function()
        if not selectedSet then
            SetUIStatus("Select a saved set first.")
            return
        end

        local assignedSlot = GetHotkeySlot(selectedSet)
        if assignedSlot then
            BindSetHotkey(selectedSet, nil)
            return
        end

        local slot
        for slot = 1, MAX_HOTKEY_SLOTS do
            if not bfwEquipDB.hotkeys[slot] then
                BindSetHotkey(selectedSet, slot)
                return
            end
        end
        SetUIStatus("All hotkey slots are used. Clear one or use /bfwequip bind.")
    end)

    statusText = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", mainWindow, "BOTTOMLEFT", 18, 12)
    statusText:SetWidth(324)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Choose a set or enter a name to save your gear.")

    local resizeGrip = CreateFrame("Button", nil, mainWindow)
    resizeGrip:SetWidth(16)
    resizeGrip:SetHeight(16)
    resizeGrip:SetPoint("BOTTOMRIGHT", mainWindow, "BOTTOMRIGHT", -3, 3)
    resizeGrip:EnableMouse(true)
    local gripLine
    for gripLine = 1, 3 do
        local line = resizeGrip:CreateTexture(nil, "OVERLAY")
        line:SetTexture("Interface\\Buttons\\WHITE8x8")
        line:SetWidth(7 - gripLine)
        line:SetHeight(1)
        line:SetPoint("BOTTOMRIGHT", resizeGrip, "BOTTOMRIGHT", -2, 2 + (gripLine * 3))
        line:SetVertexColor(0.8, 0.7, 0.45, 1)
    end
    resizeGrip:SetScript("OnMouseDown", function()
        mainWindow:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainWindow:StopMovingOrSizing()
        local width, height = ClampWindowSize(mainWindow:GetWidth(), mainWindow:GetHeight())
        mainWindow:SetWidth(width)
        mainWindow:SetHeight(height)
        bfwEquipDB.windowWidth = width
        bfwEquipDB.windowHeight = height
    end)

    local function UpdateWindowLayout(width, height)
        if not dropdownButton then
            return
        end

        local contentWidth = math.max(180, width - 36)
        UIDropDownMenu_SetWidth(contentWidth, dropdownButton)
            UIDropDownMenu_SetWidth(math.max(180, contentWidth - 74), saveScopeDropdown)
        if statusText then
            statusText:SetWidth(contentWidth)
        end
        if nameInput then
            nameInput:SetWidth(math.max(120, contentWidth - 80))
        end
        RefreshUI()
    end

    mainWindow:SetScript("OnSizeChanged", function(_, width, height)
        UpdateWindowLayout(width, height)
    end)

    StaticPopupDialogs["BFWEQUIP_CONFIRM_DELETE"] = {
        text = "Delete gear set \"%s\"?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            if selectedSet then
                DeleteSet(selectedSet)
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1
    }

    mainWindow:SetWidth(initialWidth)
    mainWindow:SetHeight(initialHeight)
    bfwEquipDB.windowWidth = initialWidth
    bfwEquipDB.windowHeight = initialHeight
    UpdateWindowLayout(initialWidth, initialHeight)
    mainWindow:Hide()
    RefreshUI()
end

frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    EnsureDatabase()
    RefreshUI()
end)
EnsureDatabase()
CreateMainWindow()

SLASH_BFWEQUIP1 = "/bfwequip"
SLASH_BFWEQUIP2 = "/bfwe"
SlashCmdList["BFWEQUIP"] = HandleSlashCommand
