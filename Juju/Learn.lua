----------------------------------------------------------------------
-- Juju — learning drop chances from your own kills
--
-- Every corpse you loot counts once for its mob type (npcID), and every
-- item in it counts once ("dropped in N of K kills"). Kills you make but
-- don't loot are counted when your target dies (it must be yours, not
-- tapped by someone else), so empty corpses lower the % as they should.
-- Loot from skinning, mining, herbs, pick pocket, fishing is NOT a drop
-- and is skipped.
----------------------------------------------------------------------
local _, J = ...
J.Learn = {}
local L = J.Learn

local MAX_SEEN = 2000
local counted = {}     -- [corpseGUID] = true   (this session: kill already counted)
local looted = {}      -- [corpseGUID] = { [itemID] = true } items already counted
local nCounted = 0
local lastGather = 0   -- GetTime() of the last skinning/mining/herb/pickpocket cast
local lastSkin = 0     -- GetTime() of the last Skinning cast (its loot teaches J.IsSkinning)
local skinned = {}     -- [corpseGUID] = true: this corpse's skinning already counted
-- The game doesn't tell which mob skinning loot came from, and right-clicking a
-- corpse to skin it doesn't make it your target. So the corpse is noted when the
-- skinning cast starts: the dead mob under the mouse, else your dead target,
-- else the mob name the cast was aimed at.
local skinCast         -- { guid, name, t }
local lootReadAt

local GATHER = { "Skinning$", "Mining$", "Herb Gathering$", "^Pick Pocket$", "^Fishing$", "^Disenchant$" }

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function isGather(spellID)
    if not spellID or J.Secret(spellID) then return false end
    local name = spellName(spellID)
    if not name or J.Secret(name) then return false end
    for _, pat in ipairs(GATHER) do
        if name:find(pat) then return true end
    end
    return false
end

local function isSkinning(spellID)
    if not spellID or J.Secret(spellID) then return false end
    local name = spellName(spellID)
    return name ~= nil and not J.Secret(name) and name:find("Skinning$") ~= nil
end

-- GUID of a dead creature on this unit, or nil
local function deadCreature(unit)
    if not UnitExists or not UnitExists(unit) then return nil end
    local guid = UnitGUID(unit)
    if not guid or J.Secret(guid) or not J.NpcID(guid) then return nil end
    local dead = UnitIsDead(unit)
    if J.Secret(dead) or not dead then return nil end
    return guid
end

-- mob name -> npcID (first match in the shipped data, else a mob you learned)
local byName
local function npcByName(name)
    if not name then return nil end
    if not byName then
        byName = {}
        for id, raw in pairs(J.NPCS) do
            local n = raw:match("^([^|]*)")
            if n and (not byName[n] or id < byName[n]) then byName[n] = id end
        end
    end
    if byName[name] then return byName[name] end
    for id, m in pairs(J.db.mobs) do
        if m.name == name and id < J.SKIN_OFFSET then return id end
    end
end

local function mob(npcID)
    local m = J.db.mobs[npcID]
    if not m then
        m = { kills = 0, items = {} }
        J.db.mobs[npcID] = m
    end
    return m
end

local function forgetOld()
    if nCounted < MAX_SEEN then return end
    counted, looted, nCounted = {}, {}, 0       -- only guards against double counting
end

-- one kill of this corpse (once per corpse)
local function countKill(guid, npcID)
    if counted[guid] then return end
    counted[guid] = true
    nCounted = nCounted + 1
    forgetOld()
    local m = mob(npcID)
    m.kills = m.kills + 1
    J.db.ownDirty = true                 -- your record for sharing gets a new version
    -- keep a name for mobs not in the shipped data
    if not J.NPCS[npcID] and not m.name and UnitGUID("target") == guid then
        local n = UnitName("target")
        if n and not J.Secret(n) then m.name = n; m.level = UnitLevel("target") end
    end
end

-- count items seen on a corpse (each item once per corpse)
local function countItems(guid, npcID, items, links)
    local seen = looted[guid]
    if not seen then seen = {}; looted[guid] = seen end
    for itemID in pairs(items) do
        if not seen[itemID] then
            seen[itemID] = true
            local m = mob(npcID)
            m.items[itemID] = (m.items[itemID] or 0) + 1
            J.db.ownDirty = true
            local link = links and links[itemID]
            if link and not J.ITEMS[itemID] then
                local name = link:match("%[(.-)%]")
                if name then J.db.itemNames[itemID] = name end
            end
        end
    end
end

----------------------------------------------------------------------
-- Groups: one corpse, one count
--
-- Alone, a corpse is counted right away. In a group every member who sees
-- the corpse (it died as their target, or they opened it) tells the group
-- "I saw it" with the items they saw. When the fight is over everyone picks
-- the same winner: the alphabetically first name of those who saw it. Only
-- the winner counts the kill, with ALL items anyone saw (who looted first
-- saw the most). If the group can't be told (the game refuses), counting
-- falls back to the old way.
----------------------------------------------------------------------
local pending = {}     -- [guid] = { npc, items = {}, links = {}, last = GetTime() }
local claims = {}      -- [guid] = { names = {}, items = {}, t }
local winner = {}      -- [guid] = name, decided
local winnerT = {}     -- [guid] = when decided (to forget later)
local lastCombatEnd = 0
local SETTLE, AFTER_COMBAT, FORGET = 6, 5, 600

local function myName() return (UnitName("player") or ""):lower() end
local function inGroup() return (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) end

local function commit(guid, npcID, items, links)
    countKill(guid, npcID)
    countItems(guid, npcID, items, links)
end

-- one observation of a corpse: died as your target ({}), or opened (its items)
function L:Observe(guid, npcID, items, links)
    if not inGroup() then commit(guid, npcID, items, links); return end
    if winner[guid] then
        if winner[guid] == myName() then countItems(guid, npcID, items, links)   -- late loot, I'm the counter
        elseif J.Sync then J.Sync:Claim(guid, items) end                          -- tell the counter
        return
    end
    local p = pending[guid]
    if not p then p = { npc = npcID, items = {}, links = {} }; pending[guid] = p end
    for id in pairs(items) do p.items[id] = true end
    for id, l in pairs(links or {}) do p.links[id] = l end
    p.last = GetTime()
    if not (J.Sync and J.Sync:Claim(guid, items)) then
        pending[guid] = nil                          -- can't reach the group: count as before
        commit(guid, npcID, items, links)
    end
end

function L:OnClaim(sender, guid, items)
    if not sender then return end
    local c = claims[guid]
    if not c then c = { names = {}, items = {}, t = GetTime() }; claims[guid] = c end
    c.names[sender:lower()] = true
    for id in pairs(items) do c.items[id] = true end
    -- I already counted this corpse: add what the others saw
    if winner[guid] == myName() then
        local npcID = J.NpcID(guid)
        if npcID then countItems(guid, npcID, items) end
    end
end

local function settle()
    local now = GetTime()
    if InCombatLockdown() or now - lastCombatEnd < AFTER_COMBAT then return end
    for guid, p in pairs(pending) do
        if now - p.last >= SETTLE then
            local me = myName()
            local first = me
            local c = claims[guid]
            if c then for name in pairs(c.names) do if name < first then first = name end end end
            winner[guid], winnerT[guid] = first, now
            if first == me then
                local all = {}
                for id in pairs(p.items) do all[id] = true end
                if c then for id in pairs(c.items) do all[id] = true end end
                commit(guid, p.npc, all, p.links)
            end
            pending[guid] = nil
        end
    end
    for guid, c in pairs(claims) do if now - c.t > FORGET then claims[guid] = nil end end
    for guid, t in pairs(winnerT) do if now - t > FORGET then winner[guid], winnerT[guid] = nil, nil end end
end
L.Settle = settle

----------------------------------------------------------------------
-- Loot
----------------------------------------------------------------------
-- sources of one loot slot: { guid, ... } (GetLootSourceInfo) or the dead target
local function slotSources(slot)
    local out = {}
    if type(GetLootSourceInfo) == "function" then
        local info = { GetLootSourceInfo(slot) }
        for i = 1, #info, 2 do
            local g = info[i]
            if type(g) == "string" and not J.Secret(g) then out[#out + 1] = g end
        end
    end
    if #out == 0 then
        local g = UnitGUID("target")
        if g and not J.Secret(g) and UnitIsDead("target") then out[1] = g end
    end
    return out
end

function L:LOOT_OPENED()
    if lootReadAt and GetTime() - lootReadAt < 1 then return end   -- LOOT_READY already read it
    lootReadAt = GetTime()
    if GetTime() - lastSkin < 3 then                                -- skinning: its own statistics
        local corpses = {}
        for slot = 1, (GetNumLootItems() or 0) do
            local link = GetLootSlotLink(slot)
            local id = link and not J.Secret(link) and tonumber(link:match("item:(%d+)"))
            if id then J.db.skinItems[id] = true end
            for _, guid in ipairs(slotSources(slot)) do
                local npcID = J.NpcID(guid)
                if npcID then
                    local c = corpses[guid]
                    if not c then c = { npc = npcID, items = {} }; corpses[guid] = c end
                    if id then c.items[id] = true end
                end
            end
        end
        -- the game named no creature: use the corpse noted when the skinning started
        if next(corpses) == nil and skinCast and GetTime() - skinCast.t < 10 then
            local npcID = skinCast.guid and J.NpcID(skinCast.guid) or npcByName(skinCast.name)
            if npcID then
                local c = { npc = npcID, items = {} }
                for slot = 1, (GetNumLootItems() or 0) do
                    local link = GetLootSlotLink(slot)
                    local id = link and not J.Secret(link) and tonumber(link:match("item:(%d+)"))
                    if id then c.items[id] = true end
                end
                -- no GUID: one skin per cast (the cast can only skin one corpse)
                corpses[skinCast.guid or ("cast:" .. skinCast.t)] = c
            end
        end
        skinCast = nil
        -- one skin per corpse (only one player can skin it: no group check needed)
        for guid, c in pairs(corpses) do
            if not skinned[guid] then
                skinned[guid] = true
                local m = mob(J.SKIN_OFFSET + c.npc)
                m.kills = m.kills + 1
                for id in pairs(c.items) do m.items[id] = (m.items[id] or 0) + 1 end
                J.db.ownDirty = true
            end
        end
        return
    end
    if GetTime() - lastGather < 3 then return end                   -- mining etc., not a drop
    if IsFishingLoot and IsFishingLoot() then return end
    local corpses = {}   -- [guid] = { npc, items = {}, links = {} }
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local itemID = link and not J.Secret(link) and tonumber(link:match("item:(%d+)"))
        for _, guid in ipairs(slotSources(slot)) do
            local npcID = J.NpcID(guid)
            if npcID then
                local c = corpses[guid]
                if not c then c = { npc = npcID, items = {}, links = {} }; corpses[guid] = c end
                if itemID then c.items[itemID] = true; c.links[itemID] = link end
            end
        end
    end
    for guid, c in pairs(corpses) do L:Observe(guid, c.npc, c.items, c.links) end
end
L.LOOT_READY = L.LOOT_OPENED

function L:LOOT_CLOSED() lootReadAt = nil end

function L:UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)
    if unit ~= "player" or not isSkinning(spellID) then return end
    local name = (type(target) == "string" and not J.Secret(target) and target ~= "") and target or nil
    skinCast = { guid = deadCreature("mouseover") or deadCreature("target"), name = name, t = GetTime() }
end

function L:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if unit == "player" and isGather(spellID) then
        lastGather = GetTime()
        local name = spellID and not J.Secret(spellID) and spellName(spellID)
        if name and not J.Secret(name) and name:find("Skinning$") then lastSkin = GetTime() end
    end
end

----------------------------------------------------------------------
-- Kills without loot: your target dies and it was yours (not tapped by
-- someone else). The combat log is NOT used: this client forbids addons to
-- register COMBAT_LOG_EVENT_UNFILTERED ("Juju has been blocked from an
-- action only available to the Blizzard UI" at login).
----------------------------------------------------------------------
local function checkTargetDead()
    local guid = UnitGUID("target")
    if not guid or J.Secret(guid) then return end
    local dead = UnitIsDead("target")
    if J.Secret(dead) or not dead then return end
    if UnitIsTapDenied then
        local denied = UnitIsTapDenied("target")
        if J.Secret(denied) or denied then return end
    end
    if UnitIsPlayer("target") then return end
    local npcID = J.NpcID(guid)
    if npcID then L:Observe(guid, npcID, {}) end
end

function L:PLAYER_REGEN_ENABLED() lastCombatEnd = GetTime() end

function L:UNIT_HEALTH(unit)
    if unit == "target" then checkTargetDead() end
end

function L:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("LOOT_READY")
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_CLOSED")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")      -- which corpse is being skinned
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_HEALTH", "target")   -- target died -> a kill (no combat log)
    f:RegisterEvent("PLAYER_REGEN_ENABLED")            -- fight over: group corpses can be settled
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        local ok, err = pcall(settle)
        if not ok and not L.err then L.err = true; J.Print("feil ved læring: " .. tostring(err)) end
    end)
    f:SetScript("OnEvent", function(_, event, ...)
        local h = L[event]
        if h then
            local ok, err = pcall(h, L, ...)
            if not ok and not L.err then L.err = true; J.Print("feil ved læring: " .. tostring(err)) end
        end
    end)
end
