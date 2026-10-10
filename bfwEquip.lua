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
local mainWindow
local RefreshUI
local SetUIStatus
local ToggleMainWindow

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
    if RefreshUI then
        RefreshUI(savedName)
    end
    if SetUIStatus then
        SetUIStatus("Saved " .. savedName .. ".")
    end

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
    if SetUIStatus then
        SetUIStatus("Equipping " .. savedName .. "...")
    end
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
        Print("Commands: /bfwequip (open UI), save <name>, list, equip <name>, delete <name>, close.")
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
    else
        Print("Unknown command. Use /bfwequip help.")
    end
end

local selectedSet
local listOffset = 1
local listRows = {}
local visibleRows = 8
local statusText
local selectedText
local nameInput
local listContainer

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(height)
    button:SetText(text)
    return button
end

SetUIStatus = function(message)
    if statusText then
        statusText:SetText(message or "")
    end
end

RefreshUI = function(preferredSelection)
    if not listContainer then
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

    local maxOffset = math.max(1, table.getn(names) - visibleRows + 1)
    if listOffset > maxOffset then
        listOffset = maxOffset
    end

    local index
    for index = 1, visibleRows do
        local row = listRows[index]
        local setName = names[listOffset + index - 1]
        if row then
            if setName then
                row:SetText(setName)
                row.setName = setName
                row:Show()
                if setName == selectedSet then
                    row:SetBackdropColor(0.35, 0.27, 0.08, 0.9)
                    row:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    row:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
                    row:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
                end
            else
                row.setName = nil
                row:Hide()
            end
        end
    end

    if selectedText then
        if selectedSet then
            selectedText:SetText("Selected: " .. selectedSet)
        else
            selectedText:SetText("No saved sets yet.")
        end
    end
end

local function ScrollSetList(delta)
    local names = {}
    local name
    for name in pairs(bfwEquipDB.sets) do
        if type(name) == "string" then
            table.insert(names, name)
        end
    end
    local maxOffset = math.max(1, table.getn(names) - visibleRows + 1)
    listOffset = math.max(1, math.min(maxOffset, listOffset - delta))
    RefreshUI()
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

local function CreateMainWindow()
    mainWindow = CreateFrame("Frame", "bfwEquipMainWindow", UIParent)
    mainWindow:SetWidth(360)
    mainWindow:SetHeight(370)
    mainWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainWindow:SetFrameStrata("DIALOG")
    mainWindow:SetMovable(true)
    mainWindow:EnableMouse(true)
    mainWindow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1
    })
    mainWindow:SetBackdropColor(0.04, 0.04, 0.04, 0.96)
    mainWindow:SetBackdropBorderColor(0.55, 0.45, 0.22, 1)

    local titleBar = CreateFrame("Frame", nil, mainWindow)
    titleBar:SetPoint("TOPLEFT", mainWindow, "TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", mainWindow, "TOPRIGHT", -8, -8)
    titleBar:SetHeight(30)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        mainWindow:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        mainWindow:StopMovingOrSizing()
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    title:SetText("bfwEquip")

    local closeButton = CreateButton(mainWindow, "X", 24, 22)
    closeButton:SetPoint("TOPRIGHT", mainWindow, "TOPRIGHT", -10, -10)
    closeButton:SetScript("OnClick", function()
        mainWindow:Hide()
    end)

    local listTitle = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", mainWindow, "TOPLEFT", 18, -50)
    listTitle:SetText("Saved gear sets (mouse wheel to scroll)")

    listContainer = CreateFrame("Frame", nil, mainWindow)
    listContainer:SetPoint("TOPLEFT", mainWindow, "TOPLEFT", 18, -72)
    listContainer:SetWidth(324)
    listContainer:SetHeight(194)
    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", function(_, delta)
        ScrollSetList(delta)
    end)

    local index
    for index = 1, visibleRows do
        local row = CreateFrame("Button", nil, listContainer, "UIPanelButtonTemplate")
        row:SetWidth(320)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 2, -((index - 1) * 24))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            ScrollSetList(delta)
        end)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1
        })
        row:SetScript("OnClick", function(self)
            selectedSet = self.setName
            RefreshUI()
        end)
        listRows[index] = row
    end

    selectedText = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selectedText:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 2, -8)
    selectedText:SetWidth(320)
    selectedText:SetJustifyH("LEFT")

    local nameLabel = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", selectedText, "BOTTOMLEFT", 0, -18)
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
        if name ~= "" then
            SaveSet(name)
            self:ClearFocus()
        else
            SetUIStatus("Enter a name for the new set.")
        end
    end)
    nameInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local saveButton = CreateButton(mainWindow, "Save Current", 100, 26)
    saveButton:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -12)
    saveButton:SetScript("OnClick", function()
        local name = Trim(nameInput:GetText() or "")
        if name == "" then
            SetUIStatus("Enter a name before saving.")
            nameInput:SetFocus()
            return
        end
        SaveSet(name)
        nameInput:SetText("")
    end)

    local equipButton = CreateButton(mainWindow, "Equip Selected", 115, 26)
    equipButton:SetPoint("LEFT", saveButton, "RIGHT", 8, 0)
    equipButton:SetScript("OnClick", function()
        if not selectedSet then
            SetUIStatus("Select a saved set first.")
            return
        end
        BeginEquip(selectedSet)
    end)

    local deleteButton = CreateButton(mainWindow, "Delete", 76, 26)
    deleteButton:SetPoint("LEFT", equipButton, "RIGHT", 8, 0)
    deleteButton:SetScript("OnClick", function()
        if not selectedSet then
            SetUIStatus("Select a saved set first.")
            return
        end
        StaticPopup_Show("BFWEQUIP_CONFIRM_DELETE", selectedSet)
    end)

    statusText = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", mainWindow, "BOTTOMLEFT", 18, 12)
    statusText:SetWidth(324)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Choose a set or enter a name to save your gear.")

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
