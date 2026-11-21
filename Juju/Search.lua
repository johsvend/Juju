----------------------------------------------------------------------
-- Juju — search an item, see which mobs are best to farm for it
-- Type part of an item name -> matching items. Click one -> every mob that
-- drops it, best drop chance first, with level, zone and your own %.
-- Also the minimap button (left: search, right: drop list on/off).
----------------------------------------------------------------------
local _, J = ...
J.Search = {}
local S = J.Search

local W, H, ROW = 470, 470, 18
local MAX_ITEMS = 60
local frame, box, scroll, child, back, header
local rows = {}
local mode, query, selItem = "items", "", nil
local mmButton

local function text(parent, font, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    t:SetJustifyH(justify or "LEFT")
    t:SetWordWrap(false)
    return t
end

local function getRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r:SetSize(W - 56, ROW)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r:RegisterForDrag("LeftButton")              -- drag a row = move the window
    r:SetScript("OnDragStart", function() frame:StartMoving() end)
    r:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.a = text(r, "GameFontHighlightSmall")           -- name
    r.a:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.a:SetWidth(190)
    r.b = text(r, "GameFontDisableSmall")             -- level / zone
    r.b:SetPoint("LEFT", r.a, "RIGHT", 6, 0)
    r.b:SetWidth(140)
    r.c = text(r, "GameFontNormalSmall", "RIGHT")     -- %
    r.c:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r:SetScript("OnClick", function(self)
        if mode == "items" and self.item then
            selItem, mode = self.item, "mobs"
            scroll:SetVerticalScroll(0)
            S:Update()
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.item and not self.npc then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item then
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item)
            else GameTooltip:SetHyperlink("item:" .. self.item) end
            GameTooltip:AddLine("Klikk: vis mobs som dropper dette", 0.5, 1, 0.5)
        else
            local e = self.e
            local name, lo, hi, rank, map = J.Mob(self.npc)
            GameTooltip:AddLine(name, 1, 1, 1)
            local lvl = hi > lo and (lo .. "-" .. hi) or tostring(lo)
            GameTooltip:AddLine(("Level %s %s"):format(lvl, J.RankText(rank) or ""), 0.8, 0.8, 0.8)
            local z = J.ZoneName(map)
            if z ~= "" then GameTooltip:AddLine(z, 0.8, 0.8, 0.8) end
            GameTooltip:AddDoubleLine("Wowhead:", J.Pct(e.pct), 1, 0.82, 0, 1, 1, 1)
            if e.kills then
                GameTooltip:AddDoubleLine("Juju-data:", ("%s (%d av %d kills)"):format(J.Pct(e.own), e.ownN, e.kills),
                    1, 0.82, 0, 1, 1, 1)
                if (e.players or 0) > 1 then
                    GameTooltip:AddDoubleLine(" ", ("fra %d spillere"):format(e.players), 1, 1, 1, 0.7, 0.7, 0.7)
                end
            end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

-- items whose name contains the query (shipped data + items you looted)
local function findItems(q)
    local out = {}
    if #q < 2 then return out end
    q = q:lower()
    local seen = {}
    local function consider(id, name)
        if not seen[id] and name and name:lower():find(q, 1, true) then
            seen[id] = true
            out[#out + 1] = { id = id, name = name, n = #J.ItemDrops(id) }
        end
    end
    for id, raw in pairs(J.ITEMS) do consider(id, raw:match("^([^|]*)")) end
    for id, name in pairs(J.db.itemNames) do consider(id, name) end
    table.sort(out, function(a, b)
        local ea, eb = a.name:lower() == q, b.name:lower() == q     -- exact match first
        if ea ~= eb then return ea end
        if #a.name ~= #b.name then return #a.name < #b.name end
        return a.name < b.name
    end)
    return out
end

function S:Update()
    if not (frame and frame:IsShown()) then return end
    local n = 0
    if mode == "items" then
        back:Hide()
        local found = findItems(query)
        if #query < 2 then
            header:SetText("Skriv minst 2 bokstaver av et item-navn (f.eks. «linen», «runecloth»).")
        else
            header:SetText(("%d item(s) funnet%s – klikk for beste mobs."):format(#found,
                #found > MAX_ITEMS and (", viser " .. MAX_ITEMS) or ""))
        end
        for i = 1, math.min(#found, MAX_ITEMS) do
            local it = found[i]
            n = n + 1
            local r = getRow(n)
            r.item, r.npc, r.e = it.id, nil, nil
            r.icon:SetTexture(J.ItemIcon(it.id)); r.icon:Show()
            r.a:SetText(J.ItemName(it.id))
            r.a:SetTextColor(J.QualityColor(J.ItemQuality(it.id)))
            r.b:SetText(("%d mobs"):format(it.n))
            r.c:SetText("›")
            r:Show()
        end
    else
        back:Show()
        local list = J.ItemSources(selItem)
        header:SetText(("Beste mobs for |cffffffff%s|r (%d) – høyest drop-sjanse først:"):format(J.ItemName(selItem), #list))
        for _, e in ipairs(list) do
            n = n + 1
            local r = getRow(n)
            r.item, r.npc, r.e = nil, e.npc, e
            local name, lo, hi, rank, map = J.Mob(e.npc)
            r.icon:Hide()
            local rk = J.RankText(rank)
            r.a:SetText(name .. (rk and (" |cffff8040(" .. rk .. ")|r") or ""))
            r.a:SetTextColor(1, 1, 1)
            local lvl = hi > lo and (lo .. "-" .. hi) or (lo > 0 and tostring(lo) or "?")
            local z = J.ZoneName(map)
            r.b:SetText(("Lvl %s%s"):format(lvl, z ~= "" and (" · " .. z) or ""))
            local p = e.pct and J.Pct(e.pct) or "|cff808080?|r"
            if e.own then p = p .. (" |cff80ff80(%s)|r"):format(J.Pct(e.own)) end
            r.c:SetText(p)
            r:Show()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].item, rows[i].npc, rows[i].e = nil, nil, nil end
    child:SetHeight(math.max(10, n * ROW))
end

local function create()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "JujuSearch", UIParent, template)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    frame:Hide()
    tinsert(UISpecialFrames, "JujuSearch")

    local title = text(frame, "GameFontNormalLarge", "CENTER")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Juju – hvor farmer jeg dette?")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    box = CreateFrame("EditBox", "JujuSearchBox", frame, "InputBoxTemplate")
    box:SetSize(260, 20)
    box:SetPoint("TOPLEFT", 24, -42)
    box:SetAutoFocus(false)
    box:SetScript("OnTextChanged", function(self)
        local q = self:GetText() or ""
        if q ~= query then
            query, mode = q, "items"
            scroll:SetVerticalScroll(0)
            S:Update()
        end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    back:SetSize(90, 20)
    back:SetPoint("LEFT", box, "RIGHT", 10, 0)
    back:SetText("« Tilbake")
    back:SetScript("OnClick", function() mode = "items"; S:Update() end)

    header = text(frame, "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 18, -70)
    header:SetWidth(W - 36)

    scroll = CreateFrame("ScrollFrame", "JujuSearchScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -88)
    scroll:SetPoint("BOTTOMRIGHT", -32, 30)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(W - 56, 10)
    scroll:SetScrollChild(child)

    local foot = text(frame, "GameFontDisableSmall")
    foot:SetPoint("BOTTOMLEFT", 18, 12)
    foot:SetText("% = Wowhead · |cff80ff80grønn|r = Juju (dine + delte kills) · ? = ukjent %")

    local export = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    export:SetSize(120, 20)
    export:SetPoint("LEFT", back, "RIGHT", 6, 0)
    export:SetText("Del mine data")
    export:SetScript("OnClick", function() S:ShowExport() end)

    -- shift-click an item into the box
    if type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if box:IsVisible() and box:HasFocus() and type(link) == "string" then
                local id = tonumber(link:match("item:(%d+)"))
                if id then
                    query = ""
                    box:SetText(J.ItemName(id))
                    selItem, mode = id, "mobs"
                    S:Update()
                end
            end
        end)
    end
    frame:SetScript("OnShow", function() S:Update() end)
end

function S:Toggle(q)
    if not frame then create() end
    if q and q ~= "" then
        frame:Show()
        box:SetText(q)          -- OnTextChanged runs the search
        return
    end
    if frame:IsShown() then frame:Hide() else frame:Show(); box:SetFocus() end
end

----------------------------------------------------------------------
-- Export window: your counts as text to copy (Ctrl+C) and send in
----------------------------------------------------------------------
local exportFrame
function S:ShowExport()
    if not exportFrame then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local f = CreateFrame("Frame", "JujuExport", UIParent, template)
        f:SetSize(520, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
        tinsert(UISpecialFrames, "JujuExport")
        local title = text(f, "GameFontNormalLarge", "CENTER")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Del Juju-dataene dine")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        f.info = text(f, "GameFontHighlightSmall")
        f.info:SetPoint("TOPLEFT", 18, -40)
        f.info:SetWidth(484)
        f.info:SetWordWrap(true)
        local sc = CreateFrame("ScrollFrame", "JujuExportScroll", f, "UIPanelScrollFrameTemplate")
        sc:SetPoint("TOPLEFT", 16, -92)
        sc:SetPoint("BOTTOMRIGHT", -34, 16)
        local eb = CreateFrame("EditBox", nil, sc)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(460)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        -- read-only: typing puts the export back
        eb:SetScript("OnTextChanged", function(self, user)
            if user and f.text then self:SetText(f.text); self:HighlightText() end
        end)
        sc:SetScrollChild(eb)
        f.edit = eb
        exportFrame = f
    end
    local txt, n = J.Export()
    exportFrame.text = txt
    exportFrame.info:SetText(("%d mobs med data. Trykk |cffffff00Ctrl+C|r for å kopiere, og lim teksten inn i "
        .. "|cffffff00«Send inn Juju-data»|r på GitHub eller i Discord-kanalen. Bare mob-ID, kills og "
        .. "item-tellinger deles – ingen navn."):format(n))
    exportFrame:Show()
    exportFrame.edit:SetText(txt)
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

----------------------------------------------------------------------
-- Minimap button
----------------------------------------------------------------------
local function placeButton()
    local a = math.rad(J.db.button.angle)
    local r = Minimap:GetWidth() / 2 + 10
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function S:UpdateButton()
    if mmButton then mmButton:SetShown(not J.db.button.hide) end
end

function S:Init()
    mmButton = CreateFrame("Button", "JujuMinimapButton", Minimap)
    mmButton:SetSize(31, 31)
    mmButton:SetFrameStrata("MEDIUM")
    mmButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mmButton:RegisterForDrag("LeftButton")
    mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = mmButton:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = mmButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = mmButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    mmButton:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            J.db.target.enabled = not J.db.target.enabled
            J.Print("drop-liste ved target: " .. (J.db.target.enabled and "på" or "av"))
            J.Target:Refresh()
        else
            S:Toggle()
        end
    end)
    mmButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            J.db.button.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            placeButton()
        end)
    end)
    mmButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Juju")
        GameTooltip:AddLine("Venstreklikk: søk etter item → beste mobs", 1, 1, 1)
        GameTooltip:AddLine("Høyreklikk: drop-liste ved target på/av", 1, 1, 1)
        GameTooltip:AddLine("Dra: flytt knappen", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    placeButton()
    S:UpdateButton()
end
