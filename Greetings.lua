local addonName, ns = ...

-- Defaults
local defaults = {
    enabled = true,
    partyMessage = "hi",
    raidMessage = "hi",
    greetInParty = true,
    greetInRaid = true,
    delay = 2,
    minimapAngle = 220,
}

-- State tracking
local wasInGroup = false
local wasInRaid = false
local pendingGreet = false
local pendingGreetOnEnterWorld = false
local lastGreetTime = 0
local GREET_COOLDOWN = 10

------------------------------------------------------------
-- Saved variables
------------------------------------------------------------
local function EnsureDB()
    if not GreetingsDB then
        GreetingsDB = {}
    end
    for k, v in pairs(defaults) do
        if GreetingsDB[k] == nil then
            GreetingsDB[k] = v
        end
    end
end

------------------------------------------------------------
-- Core logic
------------------------------------------------------------
local function GetPartyChatType()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    return "PARTY"
end

local function GetRaidChatType()
    if IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    return "RAID"
end

local function DoGreet()
    if not GreetingsDB.enabled then return end
    if GetNumGroupMembers() <= 1 then return end

    local now = GetTime()
    if (now - lastGreetTime) < GREET_COOLDOWN then return end

    if IsInRaid() and GreetingsDB.greetInRaid then
        local msg = GreetingsDB.raidMessage
        if msg and msg ~= "" then
            SendChatMessage(msg, GetRaidChatType())
            lastGreetTime = now
        end
    elseif IsInGroup() and GreetingsDB.greetInParty then
        local msg = GreetingsDB.partyMessage
        if msg and msg ~= "" then
            SendChatMessage(msg, GetPartyChatType())
            lastGreetTime = now
        end
    end
end

------------------------------------------------------------
-- Minimap button
------------------------------------------------------------
local minimapBtn

local minimapShapes = {
    ["ROUND"]                = {true,  true,  true,  true },
    ["SQUARE"]               = {false, false, false, false},
    ["CORNER-TOPLEFT"]       = {true,  false, false, false},
    ["CORNER-TOPRIGHT"]      = {false, false, true,  false},
    ["CORNER-BOTTOMLEFT"]    = {false, true,  false, false},
    ["CORNER-BOTTOMRIGHT"]   = {false, false, false, true },
    ["SIDE-LEFT"]            = {true,  true,  false, false},
    ["SIDE-RIGHT"]           = {false, false, true,  true },
    ["SIDE-TOP"]             = {true,  false, true,  false},
    ["SIDE-BOTTOM"]          = {false, true,  false, true },
    ["TRICORNER-TOPLEFT"]    = {true,  true,  true,  false},
    ["TRICORNER-TOPRIGHT"]   = {true,  false, true,  true },
    ["TRICORNER-BOTTOMLEFT"] = {true,  true,  false, true },
    ["TRICORNER-BOTTOMRIGHT"]= {false, true,  true,  true },
}

local function UpdateMinimapPosition(angle)
    local rad = math.rad(angle)
    local x, y, q = math.cos(rad), math.sin(rad), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local w = (Minimap:GetWidth()  / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    if minimapShapes[shape] and minimapShapes[shape][q] then
        x, y = x * w, y * h
    else
        local diagW = math.sqrt(2 * w * w) - 10
        local diagH = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    minimapBtn = CreateFrame("Button", "GreetingsMinimapButton", Minimap)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetSize(31, 31)
    minimapBtn:SetFrameLevel(8)
    minimapBtn:EnableMouse(true)
    minimapBtn:RegisterForDrag("LeftButton")
    minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = minimapBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    local overlay = minimapBtn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Native drag handling — WoW engine fires OnDragStop on mouse release automatically
    minimapBtn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.deg(math.atan2((cy / scale) - my, (cx / scale) - mx))
            GreetingsDB.minimapAngle = angle
            UpdateMinimapPosition(angle)
        end)
    end)

    minimapBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    minimapBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            ToggleConfigPanel()
        elseif button == "RightButton" then
            GreetingsDB.enabled = not GreetingsDB.enabled
            print("|cff00ccffGreetings|r " .. (GreetingsDB.enabled and "enabled." or "disabled."))
            if GameTooltip:IsOwned(self) then
                UpdateMinimapTooltip(self)
            end
        end
    end)

    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        UpdateMinimapTooltip(self)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Defer one frame so UI mods (e.g. ElvUI) finish overriding GetMinimapShape first
    C_Timer.After(0, function() UpdateMinimapPosition(GreetingsDB.minimapAngle) end)
end

function UpdateMinimapTooltip(self)
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Greetings", 0, 0.8, 1)
    GameTooltip:AddLine(GreetingsDB.enabled and "|cff00ff00Enabled|r" or "|cffff4444Disabled|r")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffff00Left-click|r to configure")
    GameTooltip:AddLine("|cffffff00Right-click|r to toggle on/off")
    GameTooltip:AddLine("|cffffff00Drag|r to move")
end

------------------------------------------------------------
-- Config panel
------------------------------------------------------------
function ToggleConfigPanel()
    if ns.configFrame then
        ns.configFrame:SetShown(not ns.configFrame:IsShown())
        return
    end

    local f = CreateFrame("Frame", "GreetingsConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(360, 340)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f.TitleBg:SetHeight(30)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 10, -6)
    f.title:SetText("Greetings Settings")

    local yOff = -40

    local enableCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 16, yOff)
    enableCB.Text:SetText("Enabled")
    enableCB:SetChecked(GreetingsDB.enabled)
    enableCB:SetScript("OnClick", function(self)
        GreetingsDB.enabled = self:GetChecked()
    end)
    yOff = yOff - 30

    local partyCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    partyCB:SetPoint("TOPLEFT", 16, yOff)
    partyCB.Text:SetText("Greet in Party/Dungeon groups")
    partyCB:SetChecked(GreetingsDB.greetInParty)
    partyCB:SetScript("OnClick", function(self)
        GreetingsDB.greetInParty = self:GetChecked()
    end)
    yOff = yOff - 30

    local raidCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    raidCB:SetPoint("TOPLEFT", 16, yOff)
    raidCB.Text:SetText("Greet in Raid groups")
    raidCB:SetChecked(GreetingsDB.greetInRaid)
    raidCB:SetScript("OnClick", function(self)
        GreetingsDB.greetInRaid = self:GetChecked()
    end)
    yOff = yOff - 40

    local partyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyLabel:SetPoint("TOPLEFT", 16, yOff)
    partyLabel:SetText("Party message:")
    yOff = yOff - 22

    local partyBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    partyBox:SetPoint("TOPLEFT", 20, yOff)
    partyBox:SetSize(310, 24)
    partyBox:SetAutoFocus(false)
    partyBox:SetText(GreetingsDB.partyMessage)
    partyBox:SetScript("OnEnterPressed", function(self)
        GreetingsDB.partyMessage = self:GetText()
        self:ClearFocus()
        print("|cff00ccffGreetings|r party message set to: " .. GreetingsDB.partyMessage)
    end)
    partyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yOff = yOff - 34

    local raidLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", 16, yOff)
    raidLabel:SetText("Raid message:")
    yOff = yOff - 22

    local raidBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    raidBox:SetPoint("TOPLEFT", 20, yOff)
    raidBox:SetSize(310, 24)
    raidBox:SetAutoFocus(false)
    raidBox:SetText(GreetingsDB.raidMessage)
    raidBox:SetScript("OnEnterPressed", function(self)
        GreetingsDB.raidMessage = self:GetText()
        self:ClearFocus()
        print("|cff00ccffGreetings|r raid message set to: " .. GreetingsDB.raidMessage)
    end)
    raidBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yOff = yOff - 34

    local delayLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    delayLabel:SetPoint("TOPLEFT", 16, yOff)
    delayLabel:SetText("Delay (seconds):")

    local delayBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    delayBox:SetPoint("LEFT", delayLabel, "RIGHT", 10, 0)
    delayBox:SetSize(50, 24)
    delayBox:SetAutoFocus(false)
    delayBox:SetText(tostring(GreetingsDB.delay))
    delayBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val >= 0 and val <= 30 then
            GreetingsDB.delay = val
            print("|cff00ccffGreetings|r delay set to " .. val .. "s")
        else
            self:SetText(tostring(GreetingsDB.delay))
            print("|cff00ccffGreetings|r delay must be 0-30 seconds.")
        end
        self:ClearFocus()
    end)
    delayBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yOff = yOff - 40

    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", 16, yOff)
    resetBtn:SetSize(120, 26)
    resetBtn:SetText("Reset to Default")
    resetBtn:SetScript("OnClick", function()
        for k, v in pairs(defaults) do
            GreetingsDB[k] = v
        end
        partyBox:SetText(defaults.partyMessage)
        raidBox:SetText(defaults.raidMessage)
        delayBox:SetText(tostring(defaults.delay))
        enableCB:SetChecked(defaults.enabled)
        partyCB:SetChecked(defaults.greetInParty)
        raidCB:SetChecked(defaults.greetInRaid)
        print("|cff00ccffGreetings|r settings reset to defaults.")
    end)

    local testBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    testBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
    testBtn:SetSize(80, 26)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function()
        if IsInGroup() or IsInRaid() then
            DoGreet()
            print("|cff00ccffGreetings|r test message sent!")
        else
            print("|cff00ccffGreetings|r you need to be in a group to test.")
        end
    end)

    ns.configFrame = f
end

------------------------------------------------------------
-- Event frame
------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        wasInGroup = IsInGroup()
        wasInRaid = IsInRaid()
        CreateMinimapButton()
        print("|cff00ccffGreetings|r loaded. Type |cff00ff00/greet|r to configure.")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if minimapBtn then
            UpdateMinimapPosition(GreetingsDB.minimapAngle)
        end
        if pendingGreetOnEnterWorld and not pendingGreet then
            pendingGreetOnEnterWorld = false
            pendingGreet = true
            C_Timer.After(GreetingsDB.delay, function()
                pendingGreet = false
                DoGreet()
            end)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        local inGroup = IsInGroup()
        local inRaid = IsInRaid()

        local justJoinedGroup = (not wasInGroup) and inGroup
        local justJoinedRaid = (not wasInRaid) and inRaid

        if justJoinedGroup or justJoinedRaid then
            if not pendingGreet then
                if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
                    pendingGreetOnEnterWorld = true
                else
                    pendingGreet = true
                    C_Timer.After(GreetingsDB.delay, function()
                        pendingGreet = false
                        DoGreet()
                    end)
                end
            end
        end

        wasInGroup = inGroup
        wasInRaid = inRaid
    end
end)

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
SLASH_GREETINGS1 = "/greet"
SLASH_GREETINGS2 = "/greetings"
SlashCmdList["GREETINGS"] = function(input)
    input = (input or ""):trim()
    local lower = input:lower()

    if lower == "on" then
        GreetingsDB.enabled = true
        print("|cff00ccffGreetings|r enabled.")
    elseif lower == "off" then
        GreetingsDB.enabled = false
        print("|cff00ccffGreetings|r disabled.")
    elseif lower == "test" then
        if IsInGroup() or IsInRaid() then
            DoGreet()
        else
            print("|cff00ccffGreetings|r you need to be in a group to test.")
        end
    elseif lower == "" or lower == "config" then
        ToggleConfigPanel()
    else
        GreetingsDB.partyMessage = input
        GreetingsDB.raidMessage = input
        print("|cff00ccffGreetings|r message set to: " .. input)
    end
end
