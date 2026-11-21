----------------------------------------------------------------------
-- Juju — drop list for the mob you target
-- Shown when you click a mob, hidden as soon as you're in combat, and back
-- when the fight is over (if you still have a mob targeted).
----------------------------------------------------------------------
local _, J = ...
J.Target = {}
local T = J.Target

local WIDTH, ROW_H, TOP, FOOT = 270, 16, 34, 18
local frame, rows = nil, {}

local function text(parent, font, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    t:SetJustifyH(justify or "LEFT")
    t:SetWordWrap(false)
    return t
end

local function getRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, frame)
    r:SetSize(WIDTH - 16, ROW_H)
    r:SetPoint("TOPLEFT", 8, -TOP - (i - 1) * ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = text(r)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetWidth(WIDTH - 110)
    r.pct = text(r, "GameFontNormalSmall", "RIGHT")
    r.pct:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r:EnableMouse(true)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function() frame:StartMoving() end)
    r:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
    r:SetScript("OnEnter", function(self)
        if not self.e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.e.item)
        else GameTooltip:SetHyperlink("item:" .. self.e.item) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Wowhead:", J.Pct(self.e.pct), 1, 0.82, 0, 1, 1, 1)
        if self.e.kills and self.e.kills > 0 then
            GameTooltip:AddDoubleLine("Juju-data:", ("%s (%d av %d kills)"):format(J.Pct(self.e.own or 0),
                self.e.ownN or 0, self.e.kills), 1, 0.82, 0, 1, 1, 1)
            if (self.e.players or 0) > 1 then
                GameTooltip:AddDoubleLine(" ", ("fra %d spillere"):format(self.e.players), 1, 1, 1, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function create()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "JujuTargetDrops", UIParent, template)
    frame:SetSize(WIDTH, TOP + FOOT + ROW_H)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        J.db.target.pos = { point, rel, x, y }
        if not hoverMob() and not self:IsMouseOver() then self:Hide(); shownGuid = nil end
    end)
    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.8)
        frame:SetBackdropBorderColor(0.4, 0.7, 0.9, 1)
    end
    -- NEVER anchor to TargetFrame: it's a protected frame, and a frame anchored
    -- to it becomes restricted in combat, so hiding it when a fight starts was
    -- blocked ("Juju has been blocked from an action only available to the
    -- Blizzard UI"). Place it under TargetFrame once, but anchored to UIParent.
    local pos = J.db.target.pos
    local left = TargetFrame and TargetFrame.GetLeft and TargetFrame:GetLeft()
    local bottom = TargetFrame and TargetFrame.GetBottom and TargetFrame:GetBottom()
    if type(pos) == "table" and pos[1] then
        frame:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    elseif left and bottom then
        local s = TargetFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * s + 12, bottom * s + 6)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 260, -140)
    end
    frame.title = text(frame, "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 8, -7)
    frame.title:SetWidth(WIDTH - 16)
    frame.sub = text(frame, "GameFontDisableSmall")
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -1)
    frame.foot = text(frame, "GameFontDisableSmall")
    frame.foot:SetPoint("BOTTOMLEFT", 8, 5)
    frame.foot:SetWidth(WIDTH - 16)
    frame:Hide()
end

-- The list follows the mouse: it shows for the mob under the cursor and goes
-- away when the cursor leaves it. A short grace keeps it up while you move
-- the mouse onto the list itself (to drag it or read an item tooltip).
local UNIT = "mouseover"
local GRACE = 0.3
local shownGuid, goneFor, pollAcc = nil, 0, 0

-- the mob under the cursor: npcID, guid (or nil)
local function hoverMob()
    if not UnitExists(UNIT) or UnitIsPlayer(UNIT) then return nil end
    local guid = UnitGUID(UNIT)
    if not guid or J.Secret(guid) then return nil end
    local npcID = J.NpcID(guid)
    if npcID then return npcID, guid end
end

function T:Refresh()
    if not frame then return end
    local npcID, guid = hoverMob()
    if not (J.db.target.enabled and npcID) or InCombatLockdown() or UnitAffectingCombat("player") then
        frame:Hide(); shownGuid = nil; return
    end
    shownGuid, goneFor = guid, 0
    local all, kills, players = J.MobDrops(npcID)
    -- no "?" lines: a drop is listed when its chance is known – Wowhead %, or
    -- your own % once you have killed enough of this mob for it to mean something
    local enough = kills >= J.MIN_KILLS
    local list, hidden = {}, 0
    for _, e in ipairs(all) do
        if not enough then e.own = nil end                 -- 1 kill = "100 %": too early
        if e.pct or e.own then list[#list + 1] = e else hidden = hidden + 1 end
    end
    if #list == 0 then frame:Hide(); return end     -- nothing known: stay out of the way
    -- (shownGuid stays set: this mob has nothing to show, don't recompute every poll)

    local name, lo, hi, rank = J.Mob(npcID)
    local uname = UnitName(UNIT)
    if uname and not J.Secret(uname) then name = uname end
    local lvl = (lo > 0 and hi > lo) and (lo .. "-" .. hi) or (lo > 0 and tostring(lo) or "")
    local rankText = J.RankText(rank)
    frame.title:SetText(name)
    frame.sub:SetText(("%s%s"):format(lvl ~= "" and ("Level " .. lvl) or "", rankText and ("  " .. rankText) or ""))

    local maxRows = J.db.target.maxRows or 15
    local shown = math.min(#list, maxRows)
    for i = 1, shown do
        local e = list[i]
        local r = getRow(i)
        r.e = e
        r.icon:SetTexture(J.ItemIcon(e.item))
        r.name:SetText(J.ItemName(e.item))
        r.name:SetTextColor(J.QualityColor(J.ItemQuality(e.item)))
        local p
        if e.pct then
            p = J.Pct(e.pct)
            if e.own then p = p .. (" |cff80ff80(%s)|r"):format(J.Pct(e.own)) end
        else
            p = ("|cff80ff80%s|r"):format(J.Pct(e.own))
        end
        r.pct:SetText(p)
        r:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide(); rows[i].e = nil end
    local parts = {}
    if #list > shown then parts[#parts + 1] = ("+%d til"):format(#list - shown) end
    if hidden > 0 then
        parts[#parts + 1] = enough and ("%d uten %%"):format(hidden)
            or ("%d skjult til %d/%d kills"):format(hidden, kills, J.MIN_KILLS)
    end
    if kills > 0 and enough then
        parts[#parts + 1] = ("|cff80ff80grønn|r = Juju %% (%d kills%s)"):format(kills,
            (players or 0) > 1 and (", " .. players .. " spillere") or "")
    end
    frame.foot:SetText(#parts > 0 and table.concat(parts, " · ") or "% fra Wowhead")
    frame:SetHeight(TOP + FOOT + shown * ROW_H + 4)
    frame:Show()
end

function T:Init()
    create()
    local f = CreateFrame("Frame")
    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")     -- the cursor moved onto a unit
    f:RegisterEvent("PLAYER_REGEN_DISABLED")     -- you attack / get attacked: hide
    f:RegisterEvent("PLAYER_ENTER_COMBAT")       -- auto-attack started: hide at once
    f:RegisterEvent("PLAYER_REGEN_ENABLED")      -- fight over: show again if still hovering
    local function refresh()
        local ok, err = pcall(T.Refresh, T)
        if not ok and not T.err then T.err = true; J.Print("feil i drop-liste: " .. tostring(err)) end
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTER_COMBAT" then
            frame:Hide(); shownGuid = nil
        else
            refresh()
        end
    end)
    -- the game has no "mouse left the unit" event: check a few times a second
    f:SetScript("OnUpdate", function(_, dt)
        pollAcc = pollAcc + dt
        if pollAcc < 0.1 then return end
        local step = pollAcc
        pollAcc = 0
        local _, guid = hoverMob()
        if guid then
            goneFor = 0
            if guid ~= shownGuid then refresh() end      -- moved straight onto another mob
        elseif frame:IsShown() then
            if frame:IsMouseOver() then goneFor = 0; return end  -- reading/dragging the list
            goneFor = goneFor + step
            if goneFor >= GRACE then frame:Hide(); shownGuid = nil end
        else
            shownGuid = nil
        end
    end)
end
