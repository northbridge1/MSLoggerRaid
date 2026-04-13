-- MSLoggerRaid - 3.3.5 (WotLK 3.3.5a)
local ADDON_NAME = "MSLoggerRaid"
local MSLR = CreateFrame("Frame", "MSLoggerRaidFrame", UIParent)
tinsert(UISpecialFrames, "MSLoggerRaidFrame")
MSLR:SetClampedToScreen(true)

-- Estado
local isRecording = false
local msData = {}             -- [playerName] = msText
local classByName = {}        -- [playerName] = classToken (e.g. "WARRIOR")
local lastRosterScan = 0
local rowButtons = {}

-- Constantes UI
local PAD, GAP = 32, 12
local WINDOW_WIDTH = 330
local WINDOW_HEIGHT = 616
local MIN_WINDOW_HEIGHT = 360
local MAX_WINDOW_HEIGHT = 798 -- 25 lineas visibles en la lista
local BTN_H = 24
local ROW_H = 22
local ROW_PAD_X = 6
local NAME_COL_W = 118

-- Tema visual alineado con RaidWarningHelper
local THEME_OUTER_BG = { 0.06, 0.07, 0.10, 1.00 }
local THEME_OUTER_BORDER = { 0.44, 0.44, 0.50, 1.00 }
local THEME_PANEL_BG = { 0.11, 0.12, 0.16, 1.00 }
local THEME_PANEL_BORDER = { 0.46, 0.46, 0.52, 1.00 }
local THEME_HEADER_BG = { 0.09, 0.10, 0.14, 1.00 }
local THEME_HEADER_BORDER = { 0.42, 0.42, 0.48, 1.00 }
local THEME_ROW_BG_A = { 0.11, 0.12, 0.16, 1.00 }
local THEME_ROW_BG_B = { 0.14, 0.15, 0.19, 1.00 }
local THEME_ROW_BORDER = { 0.34, 0.34, 0.40, 1.00 }
local THEME_ACCENT = { 1.00, 0.82, 0.10, 1.00 }
local THEME_TEXT_GOLD = { 0.94, 0.84, 0.55, 1.00 }
local THEME_TEXT_MUTED = { 0.72, 0.74, 0.80, 1.00 }

local function ClampColor(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function BrightenColor(c, amount, alpha)
    return {
        ClampColor((c[1] or 0) + amount),
        ClampColor((c[2] or 0) + amount),
        ClampColor((c[3] or 0) + amount),
        alpha or c[4] or 1,
    }
end

local function ApplyThemeBackdrop(frame, bg, border, edgeSize, inset)
    edgeSize = edgeSize or 12
    inset = inset or 3
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edgeSize,
        insets = { left = inset, right = inset, top = inset, bottom = inset }
    })
    bg = bg or THEME_PANEL_BG
    border = border or THEME_PANEL_BORDER
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

local function ApplyButtonVisual(btn, state)
    if not btn then return end

    local bg = { 0.15, 0.16, 0.20, 1.00 }
    local border = { 0.48, 0.48, 0.54, 1.00 }
    if not btn:IsEnabled() then
        bg = { 0.10, 0.11, 0.14, 1.00 }
        border = { 0.30, 0.30, 0.36, 1.00 }
    elseif state == "hover" then
        bg = BrightenColor(bg, 0.03, 1.00)
        border = THEME_ACCENT
    elseif state == "pushed" then
        bg = BrightenColor(bg, -0.02, 1.00)
    end

    btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if btn.SetBackdropBorderColor then
        btn:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end
end

local function SkinButton(btn)
    if not btn then return end
    btn:SetNormalFontObject("GameFontNormal")
    btn:SetHighlightFontObject("GameFontHighlight")
    btn:SetDisabledFontObject("GameFontDisable")
    local l, m, r = _G[btn:GetName() and (btn:GetName() .. "Left") or ""], _G[btn:GetName() and (btn:GetName() .. "Middle") or ""], _G[btn:GetName() and (btn:GetName() .. "Right") or ""]
    if l then l:Hide() end
    if m then m:Hide() end
    if r then r:Hide() end
    ApplyThemeBackdrop(btn, { 0.15, 0.16, 0.20, 1.00 }, { 0.48, 0.48, 0.54, 1.00 }, 12, 3)
    ApplyButtonVisual(btn)
    btn:SetHeight(BTN_H)
    btn:HookScript("OnEnter", function(self) ApplyButtonVisual(self, "hover") end)
    btn:HookScript("OnLeave", function(self) ApplyButtonVisual(self) end)
    btn:HookScript("OnMouseDown", function(self) ApplyButtonVisual(self, "pushed") end)
    btn:HookScript("OnMouseUp", function(self)
        if MouseIsOver and MouseIsOver(self) then
            ApplyButtonVisual(self, "hover")
        else
            ApplyButtonVisual(self)
        end
    end)
    btn:HookScript("OnShow", function(self) ApplyButtonVisual(self) end)
    if btn.HookScript then
        btn:HookScript("OnEnable", function(self) ApplyButtonVisual(self) end)
        btn:HookScript("OnDisable", function(self) ApplyButtonVisual(self) end)
    end
end

-- Utils
local function ShortName(name)
    if not name then return "?" end
    return (name:match("^[^-]+") or name)
end

local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isMSMessage(msg)
    return (msg and (msg:match("^%s*[Mm][Ss][%s:,-]") or msg:match("^%s*[Mm][Ss]$"))) ~= nil
end

local function normalizeMS(msg)
    if not msg then return "" end
    return trim((msg:gsub("^%s*[Mm][Ss][%s:,-]*", "")))
end

local function tableIsEmpty(t)
    return not t or next(t) == nil
end

local function clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function syncSaved()
    MSLR_Saved = MSLR_Saved or { data = {}, windowHeight = WINDOW_HEIGHT }
    local d = {}
    for k, v in pairs(msData) do d[k] = v end
    MSLR_Saved.data = d
    MSLR_Saved.windowHeight = math.floor(MSLR:GetHeight() + 0.5)
end

local function addOrUpdate(name, ms)
    name = ShortName(name)
    ms = trim(ms)
    if name == "" or ms == "" then return end
    msData[name] = ms
    syncSaved()
end

local function removeByName(name)
    name = ShortName(name)
    if not msData[name] then return end
    msData[name] = nil
    syncSaved()
end

local function clearAll()
    for k in pairs(msData) do msData[k] = nil end
    syncSaved()
end

local function getSortedNames()
    local names = {}
    for n in pairs(msData) do table.insert(names, n) end
    table.sort(names, function(a, b)
        local al, bl = a:lower(), b:lower()
        if al == bl then return a < b end
        return al < bl
    end)
    return names
end

-- Colores por clase (solo para la ventana)
local function ColorWrap(hex, text)
    return string.format("|c%s%s|r", hex, text)
end

local function GetClassTokenFromRoster(name)
    name = ShortName(name)
    local num = GetNumRaidMembers() or 0
    for i = 1, num do
        local n, _, _, _, _, classFileName = GetRaidRosterInfo(i)
        if n and ShortName(n) == name and classFileName then
            return classFileName
        end
    end
    return nil
end

local function GetClassToken(name)
    local n = ShortName(name)
    if classByName[n] then return classByName[n] end
    local tok = GetClassTokenFromRoster(n)
    if tok then
        classByName[n] = tok
        return tok
    end
    return nil
end

local function NormalizeTypedName(name)
    name = trim(name)
    if name == "" then return "" end
    name = ShortName(name)
    name = name:gsub("%s+", "")
    if name == "" then return "" end

    local lowerName = string.lower(name)
    local num = GetNumRaidMembers() or 0
    for i = 1, num do
        local rosterName = GetRaidRosterInfo(i)
        if rosterName then
            rosterName = ShortName(rosterName)
            if rosterName ~= "" and string.lower(rosterName) == lowerName then
                return rosterName
            end
        end
    end

    local first = string.sub(lowerName, 1, 1)
    local rest = string.sub(lowerName, 2)
    return string.upper(first) .. rest
end

local function SetClassByGUID(guid, name)
    if not guid or not name then return end
    local _, classFileName = GetPlayerInfoByGUID(guid)
    if classFileName then
        classByName[ShortName(name)] = classFileName
    end
end

local function ColorizeName(name)
    local tok = GetClassToken(name)
    if tok and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tok] then
        local c = RAID_CLASS_COLORS[tok]
        local hex = c.colorStr or string.format("ff%02x%02x%02x",
            math.floor((c.r or 1) * 255),
            math.floor((c.g or 1) * 255),
            math.floor((c.b or 1) * 255))
        return ColorWrap(hex, ShortName(name))
    end
    return ShortName(name)
end

-- Centro seguro
local function AnchorFrameTopLeft()
    local left = MSLR:GetLeft()
    local top = MSLR:GetTop()
    if not left or not top then return end
    MSLR:ClearAllPoints()
    MSLR:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function CenterFrame()
    MSLR:SetUserPlaced(false)
    MSLR:ClearAllPoints()
    MSLR:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    AnchorFrameTopLeft()
    MSLR:Show()
end

local function IsOffscreen()
    local l, r, t, b = MSLR:GetLeft(), MSLR:GetRight(), MSLR:GetTop(), MSLR:GetBottom()
    if not l or not r or not t or not b then return true end
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    if not pw or not ph then return false end
    if l < 0 or b < 0 or r > pw or t > ph then return true end
    return false
end

-- EditBox con marco
local function CreateBoxedEdit(parent, width, height)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    ApplyThemeBackdrop(box, THEME_HEADER_BG, THEME_PANEL_BORDER, 12, 3)

    local edit = CreateFrame("EditBox", nil, box)
    edit:SetAutoFocus(false)
    edit:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
    edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)
    edit:SetTextColor(0.95, 0.95, 0.95)
    edit:SetShadowColor(0, 0, 0, 0)
    edit:SetJustifyH("LEFT")
    return box, edit
end

------------------------------------------------------------------
-- UI
------------------------------------------------------------------
MSLR:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
MSLR:SetPoint("CENTER")
MSLR:SetMovable(true)
MSLR:EnableMouse(true)
MSLR:SetScale(0.77)

ApplyThemeBackdrop(MSLR, THEME_OUTER_BG, THEME_OUTER_BORDER, 16, 4)
MSLR:SetAlpha(1)

local drag = CreateFrame("Frame", nil, MSLR)
drag:SetPoint("TOPLEFT", MSLR, "TOPLEFT", 0, 0)
drag:SetPoint("TOPRIGHT", MSLR, "TOPRIGHT", -34, 0)
drag:SetHeight(28)
drag:SetFrameLevel(MSLR:GetFrameLevel() + 1)
drag:EnableMouse(true)
drag:RegisterForDrag("LeftButton")
drag:SetScript("OnDragStart", function() MSLR:StartMoving() end)
drag:SetScript("OnDragStop", function()
    MSLR:StopMovingOrSizing()
    AnchorFrameTopLeft()
    syncSaved()
end)

local title = MSLR:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", MSLR, "TOP", 0, -12)
title:SetWidth(WINDOW_WIDTH - 64)
title:SetJustifyH("CENTER")
title:SetText("MS Logger")
title:SetTextColor(THEME_ACCENT[1], THEME_ACCENT[2], THEME_ACCENT[3])
if title.SetScale then title:SetScale(0.70) end

local close = CreateFrame("Button", nil, MSLR, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", MSLR, "TOPRIGHT", -5, -5)

local header = CreateFrame("Frame", nil, MSLR)
header:SetPoint("TOPLEFT", MSLR, "TOPLEFT", PAD, -42)
header:SetPoint("TOPRIGHT", MSLR, "TOPRIGHT", -PAD, -42)
header:SetHeight(140)
header:SetFrameLevel(MSLR:GetFrameLevel() + 10)
header:SetAlpha(1)

local inputsPanel = CreateFrame("Frame", nil, header)
inputsPanel:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
inputsPanel:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
inputsPanel:SetHeight(72)
inputsPanel:SetFrameLevel(header:GetFrameLevel())
ApplyThemeBackdrop(inputsPanel, THEME_PANEL_BG, THEME_PANEL_BORDER, 12, 3)
inputsPanel:SetAlpha(1)

local listPanel = CreateFrame("Frame", nil, MSLR)
listPanel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
listPanel:SetPoint("BOTTOMRIGHT", MSLR, "BOTTOMRIGHT", -PAD, PAD)
ApplyThemeBackdrop(listPanel, THEME_PANEL_BG, THEME_PANEL_BORDER, 12, 3)
listPanel:SetAlpha(1)

local inputs = CreateFrame("Frame", nil, inputsPanel)
inputs:SetPoint("TOPLEFT", inputsPanel, "TOPLEFT", 10, -8)
inputs:SetPoint("TOPRIGHT", inputsPanel, "TOPRIGHT", -10, -8)
inputs:SetHeight(60)
inputs:SetFrameLevel(inputsPanel:GetFrameLevel() + 1)

local totalInnerW = WINDOW_WIDTH - 2 * PAD - 20
local COL_W = math.floor((totalInnerW - GAP) / 2)

local leftCol = CreateFrame("Frame", nil, inputs)
leftCol:SetPoint("TOPLEFT", inputs, "TOPLEFT", 0, 0)
leftCol:SetSize(COL_W, inputs:GetHeight())
leftCol:SetFrameLevel(inputs:GetFrameLevel() + 1)

local labelName = leftCol:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
labelName:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, 0)
labelName:SetText("Name:")
labelName:SetTextColor(THEME_TEXT_GOLD[1], THEME_TEXT_GOLD[2], THEME_TEXT_GOLD[3])
local nameBox, nameEdit = CreateBoxedEdit(leftCol, COL_W, 28)
nameBox:SetPoint("TOPLEFT", labelName, "BOTTOMLEFT", 0, -4)

local rightCol = CreateFrame("Frame", nil, inputs)
rightCol:SetPoint("TOPRIGHT", inputs, "TOPRIGHT", 0, 0)
rightCol:SetSize(COL_W, inputs:GetHeight())
rightCol:SetFrameLevel(inputs:GetFrameLevel() + 1)

local labelSpec = rightCol:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
labelSpec:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
labelSpec:SetText("Spec:")
labelSpec:SetTextColor(THEME_TEXT_GOLD[1], THEME_TEXT_GOLD[2], THEME_TEXT_GOLD[3])
local specBox, specEdit = CreateBoxedEdit(rightCol, COL_W, 28)
specBox:SetPoint("TOPLEFT", labelSpec, "BOTTOMLEFT", 0, -4)

local buttonsRow1 = CreateFrame("Frame", nil, header)
buttonsRow1:SetPoint("TOPLEFT", inputsPanel, "BOTTOMLEFT", 0, -6)
buttonsRow1:SetPoint("TOPRIGHT", inputsPanel, "BOTTOMRIGHT", 0, -6)
buttonsRow1:SetHeight(BTN_H)
buttonsRow1:SetFrameLevel(header:GetFrameLevel() + 1)

local btnW4 = math.floor((WINDOW_WIDTH - 2 * PAD - 3 * GAP) / 4)
local btnClear = CreateFrame("Button", nil, buttonsRow1, "UIPanelButtonTemplate")
btnClear:SetSize(btnW4, BTN_H)
btnClear:SetPoint("LEFT", buttonsRow1, "LEFT", 0, 0)
btnClear:SetText("Clear")

local btnChat = CreateFrame("Button", nil, buttonsRow1, "UIPanelButtonTemplate")
btnChat:SetSize(btnW4, BTN_H)
btnChat:SetPoint("LEFT", btnClear, "RIGHT", GAP, 0)
btnChat:SetText("Chat")

local btnAdd = CreateFrame("Button", nil, buttonsRow1, "UIPanelButtonTemplate")
btnAdd:SetSize(btnW4, BTN_H)
btnAdd:SetPoint("LEFT", btnChat, "RIGHT", GAP, 0)
btnAdd:SetText("Add")
btnAdd:Disable()

local btnDel = CreateFrame("Button", nil, buttonsRow1, "UIPanelButtonTemplate")
btnDel:SetSize(btnW4, BTN_H)
btnDel:SetPoint("LEFT", btnAdd, "RIGHT", GAP, 0)
btnDel:SetText("Del")
SkinButton(btnClear)
SkinButton(btnChat)
SkinButton(btnAdd)
SkinButton(btnDel)

local buttonsRow2 = CreateFrame("Frame", nil, header)
buttonsRow2:SetPoint("TOPLEFT", buttonsRow1, "BOTTOMLEFT", 0, -8)
buttonsRow2:SetPoint("TOPRIGHT", buttonsRow1, "BOTTOMRIGHT", 0, -8)
buttonsRow2:SetHeight(BTN_H)
buttonsRow2:SetFrameLevel(header:GetFrameLevel() + 1)

local btnW3 = math.floor((WINDOW_WIDTH - 2 * PAD - 2 * GAP) / 3)
local btnStart = CreateFrame("Button", nil, buttonsRow2, "UIPanelButtonTemplate")
btnStart:SetSize(btnW3, BTN_H)
btnStart:SetPoint("LEFT", buttonsRow2, "LEFT", 0, 0)
btnStart:SetText("Start")

local btnStop = CreateFrame("Button", nil, buttonsRow2, "UIPanelButtonTemplate")
btnStop:SetSize(btnW3, BTN_H)
btnStop:SetPoint("LEFT", btnStart, "RIGHT", GAP, 0)
btnStop:SetText("Stop")

local btnAlert = CreateFrame("Button", nil, buttonsRow2, "UIPanelButtonTemplate")
btnAlert:SetSize(btnW3, BTN_H)
btnAlert:SetPoint("LEFT", btnStop, "RIGHT", GAP, 0)
btnAlert:SetText("Alert")
SkinButton(btnStart)
SkinButton(btnStop)
SkinButton(btnAlert)

-- Scroll
local scroll = CreateFrame("ScrollFrame", "MSLR_Scroll", MSLR, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -8, 8)
scroll:SetFrameLevel(MSLR:GetFrameLevel() + 1)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

local scrollBar = _G[scroll:GetName() .. "ScrollBar"]
local scrollUpButton = _G[scroll:GetName() .. "ScrollBarScrollUpButton"]
local scrollDownButton = _G[scroll:GetName() .. "ScrollBarScrollDownButton"]

local function RepositionScrollBar()
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 13, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 13, 16)
    end

    if scrollUpButton and scrollBar then
        scrollUpButton:ClearAllPoints()
        scrollUpButton:SetPoint("BOTTOM", scrollBar, "TOP", 0, -1)
    end

    if scrollDownButton and scrollBar then
        scrollDownButton:ClearAllPoints()
        scrollDownButton:SetPoint("TOP", scrollBar, "BOTTOM", 0, 1)
    end
end

RepositionScrollBar()

local function UpdateScrollBarVisibility()
    local range = scroll:GetVerticalScrollRange() or 0
    local visible = range > 0

    if scrollBar then
        if visible then scrollBar:Show() else scrollBar:Hide() end
    end
    if scrollUpButton then
        if visible then scrollUpButton:Show() else scrollUpButton:Hide() end
    end
    if scrollDownButton then
        if visible then scrollDownButton:Show() else scrollDownButton:Hide() end
    end

    if not visible then
        scroll:SetVerticalScroll(0)
    end
end

-- Fuente +6 px
local listFont = CreateFont("MSLR_ListFont")
do
    local f, s, m = GameFontHighlightSmall:GetFont()
    listFont:SetFont(f, (s or 12) + 6, m)
end
nameEdit:SetFontObject(MSLR_ListFont)
specEdit:SetFontObject(MSLR_ListFont)

local function updateAddState()
    local n = trim(nameEdit:GetText() or "")
    local s = trim(specEdit:GetText() or "")
    if n ~= "" and s ~= "" then
        btnAdd:Enable()
    else
        btnAdd:Disable()
    end
end

local function NormalizeNameEdit()
    local raw = nameEdit:GetText() or ""
    local normalized = NormalizeTypedName(raw)
    if normalized ~= "" and normalized ~= raw then
        nameEdit:SetText(normalized)
        if nameEdit.SetCursorPosition then
            nameEdit:SetCursorPosition(string.len(normalized))
        end
    end
end

local function FillInputsFromRow(name)
    local short = ShortName(name)
    local ms = msData[short] or ""
    nameEdit:SetText(short)
    specEdit:SetText(ms)
    updateAddState()
    nameEdit:ClearFocus()
    specEdit:ClearFocus()
end

local function ApplyRowVisual(btn, index, hovered)
    if not btn then return end

    local bg = (math.fmod(index or 1, 2) == 0) and THEME_ROW_BG_B or THEME_ROW_BG_A
    local border = THEME_ROW_BORDER
    local borderAlpha = THEME_ROW_BORDER[4] or 1

    if hovered then
        bg = BrightenColor(bg, 0.05, bg[4] or 1.00)
        border = THEME_TEXT_GOLD
        borderAlpha = 1.00
    end

    btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if btn.SetBackdropBorderColor then
        btn:SetBackdropBorderColor(border[1], border[2], border[3], borderAlpha)
    end
end

local function EnsureRowButton(index)
    if rowButtons[index] then return rowButtons[index] end

    local btn = CreateFrame("Button", nil, content)
    btn:SetHeight(ROW_H)
    btn:SetFrameLevel(content:GetFrameLevel() + 2)
    btn:EnableMouse(true)
    ApplyThemeBackdrop(btn, (math.fmod(index, 2) == 0) and THEME_ROW_BG_B or THEME_ROW_BG_A, THEME_ROW_BORDER, 10, 2)

    local nameText = btn:CreateFontString(nil, "ARTWORK", "MSLR_ListFont")
    nameText:SetPoint("LEFT", btn, "LEFT", ROW_PAD_X + 4, 0)
    nameText:SetWidth(NAME_COL_W)
    nameText:SetJustifyH("LEFT")
    btn.nameText = nameText

    local specText = btn:CreateFontString(nil, "ARTWORK", "MSLR_ListFont")
    specText:SetPoint("LEFT", nameText, "RIGHT", 8, 0)
    specText:SetPoint("RIGHT", btn, "RIGHT", -(ROW_PAD_X + 4), 0)
    specText:SetJustifyH("LEFT")
    specText:SetTextColor(THEME_TEXT_GOLD[1], THEME_TEXT_GOLD[2], THEME_TEXT_GOLD[3])
    btn.specText = specText

    btn:SetScript("OnClick", function(self)
        if self.rowName then
            FillInputsFromRow(self.rowName)
        end
    end)
    btn:SetScript("OnEnter", function(self)
        ApplyRowVisual(self, self.rowIndex or index, true)
    end)
    btn:SetScript("OnLeave", function(self)
        ApplyRowVisual(self, self.rowIndex or index, nil)
    end)

    rowButtons[index] = btn
    return btn
end

local function UpdateRowWidths()
    local width = scroll:GetWidth()
    if width < 40 then width = 40 end

    local nameCol = NAME_COL_W
    if width < 180 then
        nameCol = math.floor(width * 0.42)
        if nameCol < 80 then nameCol = 80 end
    end

    for i = 1, #rowButtons do
        rowButtons[i]:SetWidth(width)
        rowButtons[i].nameText:SetWidth(nameCol)
    end
end

local function RefreshRowVisual(index, name)
    local btn = EnsureRowButton(index)
    btn.rowName = name
    btn.rowIndex = index
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * ROW_H))
    btn:Show()
    ApplyRowVisual(btn, index, nil)

    btn.nameText:SetText(ColorizeName(name))
    btn.specText:SetText(msData[name] or "")
end

local function refreshList()
    local names = getSortedNames()
    for i, name in ipairs(names) do
        RefreshRowVisual(i, name)
    end

    for i = #names + 1, #rowButtons do
        rowButtons[i]:Hide()
        rowButtons[i].rowName = nil
    end

    UpdateRowWidths()

    local height = #names * ROW_H
    if height < 10 then height = 10 end
    content:SetWidth(math.max(40, scroll:GetWidth()))
    content:SetHeight(height)
    UpdateScrollBarVisibility()
end
MSLR.refreshList = refreshList

scroll:SetScript("OnShow", UpdateScrollBarVisibility)
scroll:SetScript("OnSizeChanged", UpdateScrollBarVisibility)
if scrollBar then
    scrollBar:HookScript("OnShow", UpdateScrollBarVisibility)
    scrollBar:HookScript("OnHide", UpdateScrollBarVisibility)
end

nameEdit:SetScript("OnTextChanged", updateAddState)
specEdit:SetScript("OnTextChanged", updateAddState)
nameEdit:SetScript("OnEditFocusLost", function()
    NormalizeNameEdit()
    updateAddState()
end)
nameEdit:SetScript("OnEnterPressed", function()
    NormalizeNameEdit()
    specEdit:SetFocus()
end)
nameEdit:SetScript("OnTabPressed", function(self)
    NormalizeNameEdit()
    specEdit:SetFocus()
end)
specEdit:SetScript("OnTabPressed", function(self) nameEdit:SetFocus() end)
specEdit:SetScript("OnEnterPressed", function()
    NormalizeNameEdit()
    if btnAdd:IsEnabled() then
        btnAdd:Click()
    else
        specEdit:ClearFocus()
    end
end)

-- Grip de altura
local resizeGrip = CreateFrame("Button", nil, MSLR)
resizeGrip:SetSize(20, 20)
resizeGrip:SetPoint("BOTTOMRIGHT", MSLR, "BOTTOMRIGHT", 0, 0)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetFrameLevel(MSLR:GetFrameLevel() + 20)

local resizing = false
local resizeStartY = 0
local resizeStartHeight = WINDOW_HEIGHT

local function StopResize()
    if not resizing then return end
    resizing = false
    resizeGrip:SetScript("OnUpdate", nil)
    syncSaved()
end

resizeGrip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    AnchorFrameTopLeft()
    resizing = true
    local scale = MSLR:GetEffectiveScale() or 1
    local _, cursorY = GetCursorPosition()
    resizeStartY = cursorY / scale
    resizeStartHeight = MSLR:GetHeight()
    self:SetScript("OnUpdate", function()
        local currentScale = MSLR:GetEffectiveScale() or 1
        local _, nowY = GetCursorPosition()
        nowY = nowY / currentScale
        local newHeight = resizeStartHeight + (resizeStartY - nowY)
        newHeight = math.floor(clamp(newHeight, MIN_WINDOW_HEIGHT, MAX_WINDOW_HEIGHT) + 0.5)
        MSLR:SetHeight(newHeight)
        UpdateRowWidths()
        refreshList()
    end)
end)
resizeGrip:SetScript("OnMouseUp", StopResize)
MSLR:HookScript("OnHide", StopResize)

-- Confirmación propia (sin StaticPopup)
local confirmFrame, confirmText, confirmYes, confirmNo, confirmExtra, confirmCallback

local function LayoutConfirmFrame(showExtra)
    if not confirmFrame then return end

    confirmText:ClearAllPoints()
    confirmYes:ClearAllPoints()
    confirmNo:ClearAllPoints()

    if showExtra then
        confirmFrame:SetSize(326, 108)
        confirmText:SetPoint("TOP", 0, -16)
        confirmText:SetWidth(286)

        confirmYes:SetSize(90, 22)
        confirmExtra:SetSize(90, 22)
        confirmNo:SetSize(90, 22)

        confirmYes:SetPoint("BOTTOMLEFT", confirmFrame, "BOTTOMLEFT", 16, 12)
        confirmExtra:SetPoint("BOTTOM", confirmFrame, "BOTTOM", 0, 12)
        confirmNo:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOMRIGHT", -16, 12)
        confirmExtra:Show()
    else
        confirmFrame:SetSize(272, 90)
        confirmText:SetPoint("TOP", 0, -14)
        confirmText:SetWidth(232)

        confirmYes:SetSize(88, 22)
        confirmNo:SetSize(88, 22)

        confirmYes:SetPoint("BOTTOM", confirmFrame, "BOTTOM", -50, 12)
        confirmNo:SetPoint("BOTTOM", confirmFrame, "BOTTOM", 50, 12)
        if confirmExtra then confirmExtra:Hide() end
    end
end

local function EnsureConfirmFrame()
    if confirmFrame then return end
    confirmFrame = CreateFrame("Frame", "MSLR_ConfirmFrame", UIParent)
    confirmFrame:SetPoint("CENTER")
    confirmFrame:SetFrameStrata("DIALOG")
    ApplyThemeBackdrop(confirmFrame, THEME_OUTER_BG, THEME_OUTER_BORDER, 16, 4)
    confirmFrame:Hide()

    confirmText = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    confirmText:SetJustifyH("CENTER")
    confirmText:SetJustifyV("MIDDLE")
    confirmText:SetTextColor(THEME_TEXT_GOLD[1], THEME_TEXT_GOLD[2], THEME_TEXT_GOLD[3])

    confirmYes = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    confirmYes:SetText(YES)

    confirmNo = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    confirmNo:SetText(NO)

    confirmExtra = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    confirmExtra:SetText("Borrar")
    confirmExtra:Hide()

    SkinButton(confirmYes)
    SkinButton(confirmNo)
    SkinButton(confirmExtra)

    confirmYes:SetScript("OnClick", function()
        confirmFrame:Hide()
        if confirmCallback then pcall(confirmCallback) end
    end)
    confirmNo:SetScript("OnClick", function() confirmFrame:Hide() end)
    confirmExtra:SetScript("OnClick", function()
        clearAll()
        if MSLR.refreshList then MSLR.refreshList() end
        confirmFrame:Hide()
    end)

    confirmFrame:SetScript("OnHide", function()
        if confirmExtra then confirmExtra:Hide() end
    end)

    LayoutConfirmFrame(false)
    tinsert(UISpecialFrames, "MSLR_ConfirmFrame")
end

local function ShowConfirm(message, onAccept, showExtra)
    EnsureConfirmFrame()
    confirmCallback = onAccept
    confirmText:SetText(message or "")
    LayoutConfirmFrame(showExtra)
    confirmFrame:Show()
end

-- Botones
btnAdd:SetScript("OnClick", function()
    NormalizeNameEdit()
    local n = NormalizeTypedName(nameEdit:GetText() or "")
    local s = trim(specEdit:GetText() or "")
    if n ~= "" and s ~= "" then
        nameEdit:SetText(n)
        addOrUpdate(n, s)
        nameEdit:SetText("")
        specEdit:SetText("")
        updateAddState()
        refreshList()
    end
end)

btnDel:SetScript("OnClick", function()
    NormalizeNameEdit()
    local n = NormalizeTypedName(nameEdit:GetText() or "")
    if n ~= "" then
        nameEdit:SetText(n)
        removeByName(n)
        nameEdit:SetText("")
        specEdit:SetText("")
        updateAddState()
        refreshList()
    end
end)

-- CHAT: nombre sin color
btnChat:SetScript("OnClick", function()
    local names = getSortedNames()
    if #names == 0 then return end
    for _, name in ipairs(names) do
        local plain = ShortName(name)
        SendChatMessage(string.format("%s: %s", plain, msData[name]), "RAID")
    end
end)

-- ALERT: nombre sin color (texto plano)
local function sendRWChunk(text)
    if text and text ~= "" then
        SendChatMessage(text, "RAID_WARNING")
    end
end

btnAlert:SetScript("OnClick", function()
    local names = getSortedNames()
    if #names == 0 then return end
    local chunk = ""
    for _, name in ipairs(names) do
        local plain = ShortName(name)
        local piece = string.format("%s: %s", plain, msData[name])
        local sep = (chunk == "") and "" or " / "
        local test = chunk .. sep .. piece
        if string.len(test) > 240 then
            sendRWChunk(chunk)
            chunk = piece
        else
            chunk = test
        end
    end
    sendRWChunk(chunk)
end)

local function StartRecording()
    if not isRecording then
        isRecording = true
        MSLR:RegisterEvent("CHAT_MSG_RAID")
        MSLR:RegisterEvent("RAID_ROSTER_UPDATE")
        UIErrorsFrame:AddMessage("|cff00ff00MS Logger: Registering MS in raid chat.|r")
        btnStart:Disable()
        btnStop:Enable()
    end
end

local function StopRecording()
    if isRecording then
        isRecording = false
        MSLR:UnregisterEvent("CHAT_MSG_RAID")
        MSLR:UnregisterEvent("RAID_ROSTER_UPDATE")
        UIErrorsFrame:AddMessage("|cffff5555MS Logger: Recording stopped.|r")
        btnStart:Enable()
        btnStop:Disable()
    end
end

btnStart:SetScript("OnClick", StartRecording)
btnStop:SetScript("OnClick", StopRecording)
btnStop:Disable()

-- Escaneo de roster para refrescar clases
local function ScanRoster()
    local now = GetTime()
    if (now - lastRosterScan) < 0.5 then return end
    lastRosterScan = now
    local num = GetNumRaidMembers() or 0
    for i = 1, num do
        local n, _, _, _, _, classFileName = GetRaidRosterInfo(i)
        if n and classFileName then
            classByName[ShortName(n)] = classFileName
        end
    end
    if MSLR.refreshList then MSLR.refreshList() end
end

------------------------------------------------------------------
-- Eventos
------------------------------------------------------------------
MSLR:RegisterEvent("ADDON_LOADED")
MSLR:RegisterEvent("PLAYER_LOGIN")
MSLR:RegisterEvent("PLAYER_LOGOUT")

MSLR:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            MSLR_Saved = MSLR_Saved or { data = {}, windowHeight = WINDOW_HEIGHT }
            MSLR_Saved.data = MSLR_Saved.data or {}
            for k in pairs(msData) do msData[k] = nil end
            for k, v in pairs(MSLR_Saved.data) do msData[k] = v end
            local savedHeight = tonumber(MSLR_Saved.windowHeight) or WINDOW_HEIGHT
            MSLR:SetHeight(clamp(savedHeight, MIN_WINDOW_HEIGHT, MAX_WINDOW_HEIGHT))
        end

    elseif event == "PLAYER_LOGIN" then
        if not tableIsEmpty(msData) then
            ShowConfirm("Se han encontrado registros de la sesión anterior.\n¿Quieres mantenerlos?", function() end, true)
        end
        MSLR:Hide()
        isRecording = false
        if MSLR.refreshList then MSLR.refreshList() end
        btnStart:Enable()
        btnStop:Disable()

    elseif event == "PLAYER_LOGOUT" then
        syncSaved()

    elseif event == "CHAT_MSG_RAID" then
        if not isRecording then return end
        local msg, sender, _, _, _, _, _, _, _, _, _, guid = ...
        msg = trim(msg or "")
        if msg == "" then return end
        if not isMSMessage(msg) then return end
        if guid and sender then SetClassByGUID(guid, sender) end
        local msText = normalizeMS(msg)
        if msText == "" then return end
        addOrUpdate(sender, msText)
        if MSLR.refreshList then MSLR.refreshList() end

    elseif event == "RAID_ROSTER_UPDATE" then
        ScanRoster()
    end
end)

-- Auto-centrado si está fuera al mostrar
MSLR:SetScript("OnShow", function(self)
    if IsOffscreen() then
        CenterFrame()
    else
        AnchorFrameTopLeft()
    end
    UpdateRowWidths()
    refreshList()
end)

MSLR:HookScript("OnSizeChanged", function(self)
    self:SetWidth(WINDOW_WIDTH)
    UpdateRowWidths()
    refreshList()
end)

-- Confirmación Clear usando frame propio
btnClear:SetScript("OnClick", function()
    ShowConfirm("Clear all records?", function()
        clearAll()
        if MSLR.refreshList then MSLR.refreshList() end
    end)
end)

-- Blur al clicar fuera (quitar foco de los EditBox)
WorldFrame:HookScript("OnMouseDown", function()
    if MSLR:IsShown() and not MouseIsOver(MSLR) then
        if nameEdit and nameEdit.ClearFocus then nameEdit:ClearFocus() end
        if specEdit and specEdit.ClearFocus then specEdit:ClearFocus() end
    end
end)

-- Slash
SLASH_MSLR1 = "/msr"
SlashCmdList["MSLR"] = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "reset" or msg == "center" or msg == "centrar" then
        CenterFrame()
        UIErrorsFrame:AddMessage("|cff00ff00MS Logger: ventana centrada.|r")
        return
    end
    if MSLR:IsShown() then
        MSLR:Hide()
    else
        MSLR:Show()
    end
end
