----------------------------------------------------------------------
-- Juju — core: saved variables, drop index, shared helpers, slash
--
-- Two sources of drop chances:
--   * Wowhead %   — shipped in DropData.lua (from QuestieDB)
--   * own %       — counted by Learn.lua from the mobs you kill and loot
--                   (JujuDB.mobs[npcID] = { kills, items = {[itemID]=n} })
----------------------------------------------------------------------
local ADDON, J = ...
_G.Juju = J
J.PREFIX = "|cff7fd4ffJuju|r"
-- own % is shown (and replaces "?") from this many kills of a mob
J.MIN_KILLS = 10

local C_Item = C_Item
local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local getItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local requestItem = C_Item and C_Item.RequestLoadItemDataByID

function J.Secret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) or false
end
function J.Print(msg) print(J.PREFIX .. " " .. msg) end

----------------------------------------------------------------------
-- Items / mobs
----------------------------------------------------------------------
-- name from the client cache, else the shipped (English) name
function J.ItemName(id)
    local name = getItemInfo and getItemInfo(id)
    if name and not J.Secret(name) then return name end
    if requestItem then pcall(requestItem, id) end
    local raw = J.ITEMS[id]
    if raw then return raw:match("^([^|]*)") end
    local own = J.db and J.db.itemNames[id]
    return own or ("item:" .. id)
end

function J.ItemQuality(id)
    if not getItemInfo then return nil end
    local _, _, q = getItemInfo(id)
    if type(q) == "number" and not J.Secret(q) then return q end
end

function J.ItemIcon(id)
    return (getItemIcon and getItemIcon(id)) or 134400
end

function J.QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- name, minLevel, maxLevel, rank, uiMapID
function J.Mob(npcID)
    local raw = J.NPCS[npcID]
    if raw then
        local name, lo, hi, rank, map = raw:match("^([^|]*)|(%d+)|(%d+)|(%d+)|(%d+)$")
        if name then return name, tonumber(lo), tonumber(hi), tonumber(rank), tonumber(map) end
    end
    local own = J.db and J.db.mobs[npcID]
    if own and own.name then return own.name, own.level or 0, own.level or 0, 0, own.map or 0 end
    return "Mob " .. npcID, 0, 0, 0, 0
end

local RANKS = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
function J.RankText(rank) return RANKS[rank] end

function J.ZoneName(uiMap)
    if not uiMap or uiMap == 0 or not (C_Map and C_Map.GetMapInfo) then return "" end
    local info = C_Map.GetMapInfo(uiMap)
    return info and info.name or ""
end

-- npcID from a creature GUID ("Creature-0-xxxx-xxxx-xxxx-npcID-spawn")
function J.NpcID(guid)
    if not guid or J.Secret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

----------------------------------------------------------------------
-- Drop lists
----------------------------------------------------------------------
-- item -> { {npc, pct|nil}, ... } parsed from J.ITEMS on demand
local itemCache = {}
function J.ItemDrops(itemID)
    local c = itemCache[itemID]
    if c then return c end
    c = {}
    local raw = J.ITEMS[itemID]
    if raw then
        local list = raw:match("|(.*)$") or ""
        for entry in list:gmatch("[^,]+") do
            local npc, pct = entry:match("^(%d+):?([%d.]*)$")
            if npc then c[#c + 1] = { npc = tonumber(npc), pct = tonumber(pct) } end
        end
    end
    itemCache[itemID] = c
    return c
end

-- npc -> { [itemID] = pct|false }  (reverse index, built in the background)
J.npcIndex = nil
local building

local function addToIndex(index, itemID, raw)
    local list = raw:match("|(.*)$") or ""
    for entry in list:gmatch("[^,]+") do
        local npc, pct = entry:match("^(%d+):?([%d.]*)$")
        if npc then
            npc = tonumber(npc)
            local t = index[npc]
            if not t then t = {}; index[npc] = t end
            t[itemID] = tonumber(pct) or false
        end
    end
end

-- finish now (used if a list is needed before the background build is done)
function J.EnsureIndex()
    if J.npcIndex then return J.npcIndex end
    if building then
        while coroutine.status(building) ~= "dead" do coroutine.resume(building, true) end
        return J.npcIndex
    end
    local index = {}
    for itemID, raw in pairs(J.ITEMS) do addToIndex(index, itemID, raw) end
    J.npcIndex = index
    return index
end

local function startIndexBuild()
    building = coroutine.create(function()
        local index, n = {}, 0
        for itemID, raw in pairs(J.ITEMS) do
            addToIndex(index, itemID, raw)
            n = n + 1
            if n % 300 == 0 then
                local rush = coroutine.yield()
                if rush then n = 1 end      -- keep going without pausing
            end
        end
        J.npcIndex = index
    end)
    local ticker
    ticker = C_Timer.NewTicker(0.02, function()
        if J.npcIndex or coroutine.status(building) == "dead" then
            ticker:Cancel()
            building = nil
            if J.Target and J.Target.Refresh then J.Target:Refresh() end
            return
        end
        local ok, err = coroutine.resume(building)
        if not ok then ticker:Cancel(); building = nil; J.Print("feil ved lasting av drop-data: " .. tostring(err)) end
    end)
end

----------------------------------------------------------------------
-- Kill/drop counts: yours + the Juju community (SharedData.lua)
--
-- SharedData.lua is built from data players send in (tools/merge_submissions.py).
-- If YOUR earlier export is part of it, that part is taken out again and your
-- current counts are used instead, so your own kills never count twice.
----------------------------------------------------------------------
local sharedCache = {}
-- call after J.SHARED changes (e.g. data received in-game later)
function J.ResetSharedCache() sharedCache = {} end

-- npc -> kills, { [itemID] = n }, players   (community only)
local function sharedFor(npcID)
    local c = sharedCache[npcID]
    if c then return c.kills, c.items, c.players end
    c = { kills = 0, items = {}, players = 0 }
    local raw = J.SHARED and J.SHARED[npcID]
    if raw then
        local k, pl, list = raw:match("^(%d+)|(%d+)|(.*)$")
        if k then
            c.kills, c.players = tonumber(k), tonumber(pl)
            for item, n in list:gmatch("(%d+):(%d+)") do c.items[tonumber(item)] = tonumber(n) end
        end
    end
    sharedCache[npcID] = c
    return c.kills, c.items, c.players
end

-- the snapshot of your own counts that SharedData already contains (or nil)
local function includedSnapshot()
    local serial = J.SHARED_CONTRIB and J.db.id and J.SHARED_CONTRIB[J.db.id]
    return serial and J.db.exports[serial] or nil
end

-- Combined counts for one mob: kills, { [itemID] = n }, players
function J.Stats(npcID)
    local sk, sitems, players = sharedFor(npcID)
    local kills, items = sk, {}
    for id, n in pairs(sitems) do items[id] = n end
    local snap = includedSnapshot()
    local old = snap and snap[npcID]
    if old then                                   -- take your already-sent counts out
        kills = kills - (old.kills or 0)
        for id, n in pairs(old.items or {}) do items[id] = (items[id] or 0) - n end
    end
    local own = J.db.mobs[npcID]
    if own then                                   -- and add your current counts
        kills = kills + (own.kills or 0)
        for id, n in pairs(own.items) do items[id] = (items[id] or 0) + n end
        if own.kills and own.kills > 0 and not old then players = players + 1 end
    end
    if kills < 0 then kills = 0 end
    for id, n in pairs(items) do
        if n <= 0 then items[id] = nil elseif n > kills then items[id] = kills end
    end
    return kills, items, players
end

-- every npc the community has data for that dropped this item
local function sharedNpcsWith(itemID)
    local out = {}
    for npc, raw in pairs(J.SHARED or {}) do
        if raw:find("[|,]" .. itemID .. ":") then out[#out + 1] = npc end
    end
    return out
end

-- Everything known for one mob, best first:
-- { {item, pct (Wowhead)|nil, own = Juju %|nil, ownN = drops, kills, players}, ... }
function J.MobDrops(npcID)
    local index = J.EnsureIndex()
    local out, seen = {}, {}
    local kills, items, players = J.Stats(npcID)
    for itemID, pct in pairs(index[npcID] or {}) do
        seen[itemID] = true
        out[#out + 1] = { item = itemID, pct = pct or nil }
    end
    for itemID in pairs(items) do
        if not seen[itemID] then out[#out + 1] = { item = itemID } end
    end
    for _, e in ipairs(out) do
        local n = items[e.item]
        if n and kills > 0 then e.own, e.ownN = n * 100 / kills, n end
        e.kills, e.players = kills, players
    end
    table.sort(out, function(a, b)
        local pa, pb = a.pct or a.own or -1, b.pct or b.own or -1
        if pa ~= pb then return pa > pb end
        return a.item < b.item
    end)
    return out, kills, players
end

-- Every mob known to drop an item, best first (Wowhead % or Juju %).
function J.ItemSources(itemID)
    local out, seen = {}, {}
    for _, d in ipairs(J.ItemDrops(itemID)) do
        seen[d.npc] = true
        out[#out + 1] = { npc = d.npc, pct = d.pct }
    end
    for npc, m in pairs(J.db.mobs) do
        if m.items[itemID] and not seen[npc] then seen[npc] = true; out[#out + 1] = { npc = npc } end
    end
    for _, npc in ipairs(sharedNpcsWith(itemID)) do
        if not seen[npc] then seen[npc] = true; out[#out + 1] = { npc = npc } end
    end
    for _, e in ipairs(out) do
        local kills, items, players = J.Stats(e.npc)
        local n = items[itemID]
        if n and kills > 0 then e.own, e.ownN, e.kills, e.players = n * 100 / kills, n, kills, players end
    end
    table.sort(out, function(a, b)
        local pa, pb = a.pct or a.own or -1, b.pct or b.own or -1
        if pa ~= pb then return pa > pb end
        return a.npc < b.npc
    end)
    return out
end

----------------------------------------------------------------------
-- Export: your counts as one line of text to send in (GitHub / Discord)
-- Format: JUJU1;<id>;<serial>;<npc>:<kills>:<item>=<n>,<item>=<n>/<npc>:...
-- A snapshot is kept, so once SharedData includes this export your own
-- counts aren't added twice (see J.Stats). Only the last 3 are kept.
----------------------------------------------------------------------
function J.Export()
    local serial = time()
    local parts, snap = {}, {}
    local npcs = {}
    for npc in pairs(J.db.mobs) do npcs[#npcs + 1] = npc end
    table.sort(npcs)
    for _, npc in ipairs(npcs) do
        local m = J.db.mobs[npc]
        if m.kills and m.kills > 0 then
            local ids, list = {}, {}
            for id in pairs(m.items) do ids[#ids + 1] = id end
            table.sort(ids)
            local copy = {}
            for _, id in ipairs(ids) do
                local n = math.min(m.items[id], m.kills)
                list[#list + 1] = id .. "=" .. n
                copy[id] = n
            end
            parts[#parts + 1] = npc .. ":" .. m.kills .. ":" .. table.concat(list, ",")
            snap[npc] = { kills = m.kills, items = copy }
        end
    end
    J.db.exports[serial] = snap
    -- keep the 3 newest, and ALWAYS the one SharedData includes (else your
    -- own kills would count twice)
    local keep = J.SHARED_CONTRIB and J.SHARED_CONTRIB[J.db.id]
    local serials = {}
    for s in pairs(J.db.exports) do
        if s ~= keep then serials[#serials + 1] = s end
    end
    table.sort(serials)
    for i = 1, #serials - 3 do J.db.exports[serials[i]] = nil end
    return ("JUJU1;%s;%d;%s"):format(J.db.id, serial, table.concat(parts, "/")), #parts
end

function J.Pct(p)
    if not p then return "?" end
    if p >= 10 then return ("%d%%"):format(math.floor(p + 0.5)) end
    if p >= 1 then return ("%.1f%%"):format(p) end
    return ("%.2f%%"):format(p)
end

----------------------------------------------------------------------
-- Saved variables + boot
----------------------------------------------------------------------
local function defaults(db)
    db.version = 1
    db.mobs = type(db.mobs) == "table" and db.mobs or {}            -- own loot stats
    db.itemNames = type(db.itemNames) == "table" and db.itemNames or {}
    db.target = type(db.target) == "table" and db.target or {}
    if db.target.enabled == nil then db.target.enabled = true end
    if type(db.target.maxRows) ~= "number" then db.target.maxRows = 15 end
    db.search = type(db.search) == "table" and db.search or {}
    db.button = type(db.button) == "table" and db.button or {}
    if type(db.button.angle) ~= "number" then db.button.angle = 170 end
    -- anonymous install id: lets the merge keep only your newest export and
    -- lets Juju avoid counting your own kills twice. Not tied to your name.
    if type(db.id) ~= "string" or not db.id:match("^%x+$") then
        local t = {}
        for i = 1, 12 do t[i] = ("%x"):format(math.random(0, 15)) end
        db.id = table.concat(t)
    end
    db.exports = type(db.exports) == "table" and db.exports or {}
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- diagnosis: which protected function did the game stop, and in what situation
boot:RegisterEvent("ADDON_ACTION_BLOCKED")
boot:RegisterEvent("ADDON_ACTION_FORBIDDEN")
local queued = false
boot:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == ADDON then
            J.Print(("|cffff4040diagnose:|r %s – funksjon: |cffffff00%s|r (i kamp: %s, target: %s, loot åpen: %s)"):format(
                event, tostring(arg2), tostring(InCombatLockdown() and true or false),
                tostring(UnitExists("target") and true or false),
                tostring(LootFrame and LootFrame:IsShown() and true or false)))
            if debugstack then print(debugstack(2, 6, 0)) end
        end
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON then
        JujuDB = type(JujuDB) == "table" and JujuDB or {}
        defaults(JujuDB)
        J.db = JujuDB
    elseif event == "PLAYER_LOGIN" then
        if not J.db then return end
        for _, mod in ipairs({ J.Learn, J.Target, J.Search }) do
            if mod and mod.Init then
                local ok, err = pcall(mod.Init, mod)
                if not ok then J.Print("feil ved oppstart: " .. tostring(err)) end
            end
        end
        startIndexBuild()
    elseif event == "GET_ITEM_INFO_RECEIVED" and J.db and not queued then
        queued = true                     -- names/colours arrive one by one: redraw once
        C_Timer.After(0.4, function()
            queued = false
            if J.Target and J.Target.Refresh then J.Target:Refresh() end
            if J.Search and J.Search.Update then J.Search:Update() end
        end)
    end
end)

SLASH_JUJU1 = "/juju"
SlashCmdList.JUJU = function(msg)
    if not J.db then return end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "target" or msg == "liste" then
        J.db.target.enabled = not J.db.target.enabled
        J.Print("drop-liste ved target: " .. (J.db.target.enabled and "på" or "av"))
        J.Target:Refresh()
    elseif msg == "flytt" or msg == "reset" then
        J.db.target.pos = nil
        J.Print("drop-listen er satt tilbake under target-rammen (gjelder etter /reload).")
    elseif msg == "eksport" or msg == "export" then
        J.Search:ShowExport()
    elseif msg == "knapp" then
        J.db.button.hide = not J.db.button.hide
        J.Search:UpdateButton()
    elseif msg == "" or msg == "søk" or msg == "sok" then
        J.Search:Toggle()
    else
        J.Search:Toggle(msg)              -- /juju linen  -> search for it
    end
end
