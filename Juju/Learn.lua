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
    -- keep a name for mobs not in the shipped data
    if not J.NPCS[npcID] and not m.name and UnitGUID("target") == guid then
        local n = UnitName("target")
        if n and not J.Secret(n) then m.name = n; m.level = UnitLevel("target") end
    end
end

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
    if GetTime() - lastGather < 3 then return end                   -- skinning etc., not a drop
    if IsFishingLoot and IsFishingLoot() then return end
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local itemID = link and not J.Secret(link) and tonumber(link:match("item:(%d+)"))
        for _, guid in ipairs(slotSources(slot)) do
            local npcID = J.NpcID(guid)
            if npcID then
                countKill(guid, npcID)
                if itemID then
                    local seen = looted[guid]
                    if not seen then seen = {}; looted[guid] = seen end
                    if not seen[itemID] then
                        seen[itemID] = true
                        local m = mob(npcID)
                        m.items[itemID] = (m.items[itemID] or 0) + 1
                        if not J.ITEMS[itemID] then
                            local name = link:match("%[(.-)%]")
                            if name then J.db.itemNames[itemID] = name end
                        end
                    end
                end
            end
        end
    end
end
L.LOOT_READY = L.LOOT_OPENED

function L:LOOT_CLOSED() lootReadAt = nil end

function L:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if unit == "player" and isGather(spellID) then lastGather = GetTime() end
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
    if npcID then countKill(guid, npcID) end
end

function L:UNIT_HEALTH(unit)
    if unit == "target" then checkTargetDead() end
end

function L:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("LOOT_READY")
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_CLOSED")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_HEALTH", "target")   -- target died -> a kill (no combat log)
    f:SetScript("OnEvent", function(_, event, ...)
        local h = L[event]
        if h then
            local ok, err = pcall(h, L, ...)
            if not ok and not L.err then L.err = true; J.Print("feil ved læring: " .. tostring(err)) end
        end
    end)
end
