----------------------------------------------------------------------
-- Juju — sharing kill/drop counts with other Juju players in-game
--
-- No program needed: addon messages (invisible) to guild, group/raid and the
-- Juju channel (joined with a click in the Juju search window).
--
--   H;id:serial,id:serial,...   "this is what I have"            (broadcast, every ~5 min)
--   R;id                        "send me that one"               (whisper to whoever has it)
--   D;id;serial;i;n;chunk       a piece of one record            (whisper back)
--   V;version                   "my community pack is version"   (broadcast)
--   P;version                   "send me that pack"              (whisper)
--   Q;version;i;n;chunk         a piece of the signed pack       (whisper back)
--   C;corpseGUID;item,item      "I saw this corpse" (group only, see Learn.lua)
--
-- ";" separates fields: "|" is the game's escape character in chat text.
-- The community pack (Pack.lua) is signed by GitHub, so anyone may pass it on:
-- a pack that doesn't match the signature is thrown away.
--
-- Records are your own counts and what you received from others (so data
-- spreads further than who happens to be online together). Everything
-- received is checked like on GitHub (J.ParseBody). One player can bring in at
-- most 30 new players per day; at most 1000 are kept.
--
-- Forever: the first refusal of a kind (answer 4 = not allowed, 7 = no such
-- channel) closes that kind for the session, so a refused line is never
-- repeated. Nothing is sent in combat; at most 2 messages per second.
----------------------------------------------------------------------
local _, J = ...
J.Sync = {}
local S = J.Sync

local PREFIX = "JUJU1"
S.CHANNEL = "JujuData"
local SEND_GAP = 0.5            -- seconds between messages
local HELLO_EVERY = 300
local CHUNK = 200
local MAX_CHUNKS = 250          -- ~50 KB per record
local MAX_PEERS = 1000
local NEW_PER_SENDER_DAY = 30
local OWN_BUMP = 1800           -- your advertised version moves on at most every 30 min
local MAX_QUEUE = 400

local queue, refused, inbox, asked, served = {}, {}, {}, {}, {}
local stats = { sent = 0, got = 0, new = 0 }
local sinceSend, sinceHello, nextHello = 0, 0, 20

local function shortName(name)
    if not name or J.Secret(name) then return nil end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end

local function isMe(sender)
    local me = UnitName("player")
    return sender == nil or shortName(sender) == me
end

local function enabled() return J.db and J.db.autoShare end

----------------------------------------------------------------------
-- Sending (queued, throttled, never in combat)
----------------------------------------------------------------------
local function push(kind, target, text)
    if refused[kind] or #queue >= MAX_QUEUE then return end
    queue[#queue + 1] = { kind = kind, target = target, text = text }
end

local function channelId()
    local id = GetChannelName and GetChannelName(S.CHANNEL)
    if J.Secret(id) or type(id) ~= "number" or id <= 0 then return nil end
    return id
end

local function sendOne()
    local m = table.remove(queue, 1)
    if not m or refused[m.kind] then return end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, m.kind, m.target)
    if not ok then refused[m.kind] = "error"; return end
    if J.Secret(res) then return end
    stats.sent = stats.sent + 1
    -- a whisper to someone who just logged off is no reason to stop whispering
    if m.kind ~= "WHISPER" and (res == 4 or (res == 7 and m.kind ~= "CHANNEL")
        or (res == 7 and m.kind == "CHANNEL" and channelId())) then
        refused[m.kind] = "refused (" .. tostring(res) .. ")"
        for i = #queue, 1, -1 do if queue[i].kind == m.kind then table.remove(queue, i) end end
    end
end

-- where a broadcast goes right now
local function broadcastTargets()
    local out = {}
    if IsInGuild and IsInGuild() and not refused.GUILD then out[#out + 1] = { "GUILD" } end
    if IsInRaid and IsInRaid() then
        if not refused.RAID then out[#out + 1] = { "RAID" } end
    elseif IsInGroup and IsInGroup() then
        if not refused.PARTY then out[#out + 1] = { "PARTY" } end
    end
    local ch = channelId()
    if ch and not refused.CHANNEL then out[#out + 1] = { "CHANNEL", ch } end
    return out
end

----------------------------------------------------------------------
-- Records
----------------------------------------------------------------------
local function ownKills()
    local n = 0
    for _, m in pairs(J.db.mobs) do n = n + (m.kills or 0) end
    return n
end

-- the version of your own record to advertise (a new one at most every 30 min)
local function ownSerial()
    if ownKills() == 0 then return nil end
    if not J.db.ownSerial or (J.db.ownDirty and time() - J.db.ownSerial >= OWN_BUMP) then
        J.OwnRecord()
    end
    return J.db.ownSerial
end

local function recordBody(id)
    if id == J.db.id then
        local s = J.db.ownSerial
        local snap = s and J.db.exports[s]
        if snap then return s, (J.BodyOf(snap)) end
        return nil
    end
    local p = J.db.peers[id]
    if p then return p.serial, (J.BodyOf(p.mobs)) end
end

function S:Hello()
    if not enabled() then return end
    local targets = broadcastTargets()
    if #targets == 0 then return end
    local entries = {}
    local mine = ownSerial()
    if mine then entries[#entries + 1] = J.db.id .. ":" .. mine end
    -- newest received first: they're the ones others most likely miss
    local peers = {}
    for id, p in pairs(J.db.peers) do peers[#peers + 1] = { id = id, serial = p.serial, t = p.t or 0 } end
    table.sort(peers, function(a, b) return a.t > b.t end)
    for i = 1, math.min(#peers, 40) do entries[#entries + 1] = peers[i].id .. ":" .. peers[i].serial end
    local packVersion, packSig = J.Pack.Current()
    if packSig and packVersion > 0 then
        for _, t in ipairs(targets) do push(t[1], t[2], "V;" .. packVersion) end
    end
    if #entries == 0 then return end
    -- up to 9 entries per message (fits the 255-byte limit)
    for i = 1, #entries, 9 do
        local text = "H;" .. table.concat(entries, ",", i, math.min(i + 8, #entries))
        for _, t in ipairs(targets) do push(t[1], t[2], text) end
    end
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
local function today() return date("%Y%m%d") end

local function mayAddNew(sender)
    local l = J.db.peerLimit[sender]
    if not l or l.day ~= today() then l = { day = today(), n = 0 }; J.db.peerLimit[sender] = l end
    return l.n < NEW_PER_SENDER_DAY, l
end

local function storePeer(id, serial, mobs, sender)
    local cur = J.db.peers[id]
    if cur and cur.serial >= serial then return false end
    if not cur then
        local ok, l = mayAddNew(sender)
        if not ok then return false end
        local count, oldestId, oldestT = 0, nil, math.huge
        for pid, p in pairs(J.db.peers) do
            count = count + 1
            if (p.t or 0) < oldestT then oldestId, oldestT = pid, p.t or 0 end
        end
        if count >= MAX_PEERS and oldestId then J.db.peers[oldestId] = nil end
        l.n = l.n + 1
        stats.new = stats.new + 1
    end
    J.db.peers[id] = { serial = serial, mobs = mobs, from = sender, t = time() }
    J.PeersChanged()
    return true
end

local function onHello(sender, list)
    local requests = 0
    for id, serial in list:gmatch("([0-9a-f]+):(%d+)") do
        serial = tonumber(serial)
        if #id >= 4 and #id <= 32 and id ~= J.db.id and requests < 3 then
            local have = J.db.peers[id]
            local inShared = J.SHARED_CONTRIB and J.SHARED_CONTRIB[id]
            local newer = (not have or have.serial < serial) and not (inShared and inShared >= serial)
            if newer and (not asked[id] or GetTime() - asked[id] > 60) then
                if have or mayAddNew(sender) then
                    asked[id] = GetTime()
                    push("WHISPER", sender, "R;" .. id)
                    requests = requests + 1
                end
            end
        end
    end
end

local function onRequest(sender, id)
    local key = sender .. "|" .. id
    if served[key] and GetTime() - served[key] < 60 then return end   -- asked twice: once is enough
    local serial, body = recordBody(id)
    if not serial or not body or body == "" then return end
    local n = math.ceil(#body / CHUNK)
    if n > MAX_CHUNKS or #queue + n > MAX_QUEUE then return end
    served[key] = GetTime()
    for i = 1, n do
        push("WHISPER", sender, ("D;%s;%d;%d;%d;%s"):format(id, serial, i, n, body:sub((i - 1) * CHUNK + 1, i * CHUNK)))
    end
end

local function onData(sender, id, serial, i, n, chunk)
    if n < 1 or n > MAX_CHUNKS or i < 1 or i > n then return end
    -- only data we asked for (in the last 2 minutes): nobody can push records in uninvited
    if not asked[id] or GetTime() - asked[id] > 120 then return end
    local key = sender .. "|" .. id .. "|" .. serial
    local box = inbox[key]
    if not box then box = { n = n, got = 0, parts = {}, t = GetTime() }; inbox[key] = box end
    if box.n ~= n or box.parts[i] then return end
    box.parts[i], box.got = chunk, box.got + 1
    if box.got < n then return end
    inbox[key] = nil
    local mobs = J.ParseBody(table.concat(box.parts))
    asked[id] = nil
    if mobs and storePeer(id, serial, mobs, sender) then
        stats.got = stats.got + 1
        if J.Target and J.Target.Refresh then J.Target:Refresh() end
    end
end

----------------------------------------------------------------------
-- The signed community pack: whoever has a newer one hands it over
----------------------------------------------------------------------
local PACK_MAX_CHUNKS = 2500           -- ~500 KB
local PACK_WAIT = 1800                 -- a transfer may take a while at 2 msgs/s
local packAsk, packIn, packOut         -- { version, sender, t } / inbox / { target, chunks, i }

-- "\n" and "|" can't travel in chat text: "~" and "^" stand in for them
local function packEncode(wire) return (wire:gsub("\n", "~"):gsub("|", "^")) end
local function packDecode(text) return (text:gsub("~", "\n"):gsub("%^", "|")) end

local function onPackVersion(sender, version)
    local have = J.Pack.Current()
    if version <= have or packIn then return end
    if packAsk and GetTime() - packAsk.t < 300 then return end   -- one ask per 5 min
    packAsk = { version = version, sender = sender, t = GetTime() }
    push("WHISPER", sender, "P;" .. version)
end

local function onPackRequest(sender, version)
    if packOut then return end                        -- one hand-over at a time
    local have, wire = J.Pack.Outgoing()
    if not have or have ~= version then return end
    wire = packEncode(wire)
    local n = math.ceil(#wire / CHUNK)
    if n > PACK_MAX_CHUNKS then return end
    packOut = { target = sender, version = version, wire = wire, n = n, i = 1, t = GetTime() }
end

-- feed the hand-over into the queue a little at a time (shares it with other traffic)
local function packTick()
    if not packOut then return end
    if GetTime() - packOut.t > PACK_WAIT then packOut = nil; return end
    while packOut.i <= packOut.n and #queue < 40 do
        local i = packOut.i
        push("WHISPER", packOut.target, ("Q;%d;%d;%d;%s"):format(packOut.version, i, packOut.n,
            packOut.wire:sub((i - 1) * CHUNK + 1, i * CHUNK)))
        packOut.i = i + 1
    end
    if packOut.i > packOut.n then packOut = nil end
end

local function onPackData(sender, version, i, n, chunk)
    -- only the pack we asked this very player for
    if not (packAsk and packAsk.sender == sender and packAsk.version == version) then return end
    if n < 1 or n > PACK_MAX_CHUNKS or i < 1 or i > n then return end
    if not packIn then packIn = { version = version, n = n, got = 0, parts = {}, t = GetTime() } end
    if packIn.n ~= n or packIn.parts[i] then return end
    packIn.parts[i], packIn.got = chunk, packIn.got + 1
    if packIn.got < n then return end
    local wire = packDecode(table.concat(packIn.parts))
    packIn, packAsk = nil, nil
    local ok, why = J.Pack.Accept(wire)
    if ok then
        stats.pack = version
        J.Print(("new community data received (version %d, signature OK)."):format(version))
        if J.Target and J.Target.Refresh then J.Target:Refresh() end
    else
        stats.packRejected = (stats.packRejected or 0) + 1
        stats.packWhy = why
    end
end

-- group-only claims of corpses (no double counting in groups, see Learn.lua)
function S:Claim(guid, items)
    if not enabled() then return end
    local kind = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY") or nil
    if not kind or refused[kind] then return false end
    local list = {}
    for id in pairs(items or {}) do list[#list + 1] = id end
    table.sort(list)
    local head = "C;" .. guid .. ";"
    local per = math.max(1, math.floor((240 - #head) / 7))
    if #list == 0 then push(kind, nil, head); return true end
    for i = 1, #list, per do push(kind, nil, head .. table.concat(list, ",", i, math.min(i + per - 1, #list))) end
    return true
end

function S:OnMessage(prefix, text, kind, sender)
    if prefix ~= PREFIX or not enabled() then return end
    if J.Secret(text) or J.Secret(sender) or type(text) ~= "string" or isMe(sender) then return end
    local cmd, rest = text:match("^([HRDVPQC]);(.*)$")
    if cmd == "H" then
        onHello(sender, rest)
    elseif cmd == "R" and kind == "WHISPER" then
        local id = rest:match("^([0-9a-f]+)$")
        if id and #id >= 4 and #id <= 32 then onRequest(sender, id) end
    elseif cmd == "D" and kind == "WHISPER" then
        local id, serial, i, n, chunk = rest:match("^([0-9a-f]+);(%d+);(%d+);(%d+);([0-9:=,/]*)$")
        if id and #id >= 4 and #id <= 32 and #serial <= 12 then
            onData(sender, id, tonumber(serial), tonumber(i), tonumber(n), chunk)
        end
    elseif cmd == "V" then
        local v = rest:match("^(%d+)$")
        if v and #v <= 12 then onPackVersion(sender, tonumber(v)) end
    elseif cmd == "P" and kind == "WHISPER" then
        local v = rest:match("^(%d+)$")
        if v and #v <= 12 then onPackRequest(sender, tonumber(v)) end
    elseif cmd == "Q" and kind == "WHISPER" then
        local v, i, n, chunk = rest:match("^(%d+);(%d+);(%d+);([%w%^:,=#!~]*)$")
        if v and #v <= 12 then onPackData(sender, tonumber(v), tonumber(i), tonumber(n), chunk) end
    elseif cmd == "C" and (kind == "PARTY" or kind == "RAID") and J.Learn and J.Learn.OnClaim then
        local guid, list = rest:match("^(Creature%-[%w%-]+);([0-9,]*)$")
        if guid and #guid <= 80 then
            local items = {}
            for id in list:gmatch("%d+") do if #id <= 8 then items[tonumber(id)] = true end end
            J.Learn:OnClaim(shortName(sender), guid, items)
        end
    end
end

----------------------------------------------------------------------
-- Juju channel (joined with a click: the game wants a click for it)
----------------------------------------------------------------------
local function hideChannel()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if type(frame) == "table" then
            if type(frame.RemoveChannel) == "function" then pcall(frame.RemoveChannel, frame, S.CHANNEL)
            elseif type(ChatFrame_RemoveChannel) == "function" then pcall(ChatFrame_RemoveChannel, frame, S.CHANNEL) end
        end
    end
end

function S:JoinChannel()
    J.db.sync.channel = true
    refused.CHANNEL = nil
    if not channelId() then
        local join = JoinPermanentChannel or JoinChannelByName
        if type(join) == "function" then pcall(join, S.CHANNEL) end
    end
    C_Timer.After(2, function() hideChannel(); nextHello = 3 end)
end

function S:LeaveChannel()
    J.db.sync.channel = false            -- the player said OFF: stays off after login too
    hideChannel()
    if channelId() and type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, S.CHANNEL) end
end

function S:InChannel() return channelId() ~= nil end

function S:Status()
    local n = 0
    for _ in pairs(J.db.peers) do n = n + 1 end
    local open = {}
    for _, t in ipairs(broadcastTargets()) do open[#open + 1] = t[1] == "CHANNEL" and "Juju channel" or t[1]:lower() end
    local closed = {}
    for k, why in pairs(refused) do closed[#closed + 1] = k:lower() .. " " .. tostring(why) end
    stats.packVersion = (J.Pack.Current())
    return n, open, closed, stats
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
function S:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local ok, err = pcall(S.OnMessage, S, ...)
            if not ok and not S.err then S.err = true; J.Print("error in sharing: " .. tostring(err)) end
        else
            nextHello = math.min(nextHello, sinceHello + 10)     -- new group/guild: say hello soon
        end
    end)
    f:SetScript("OnUpdate", function(_, dt)
        sinceSend, sinceHello = sinceSend + dt, sinceHello + dt
        if InCombatLockdown() then return end
        packTick()
        if sinceSend >= SEND_GAP and #queue > 0 then sinceSend = 0; sendOne() end
        if sinceHello >= nextHello then
            sinceHello, nextHello = 0, HELLO_EVERY + math.random(0, 60)
            S:Hello()
        end
        for key, box in pairs(inbox) do                      -- give up on half records
            if GetTime() - box.t > 120 then inbox[key] = nil end
        end
        if packIn and GetTime() - packIn.t > PACK_WAIT then packIn, packAsk = nil, nil end
    end)
    -- the game rejoins a permanent channel at login: keep it out of the chat windows
    -- Default ON: join by ourselves a little after login, unless the player
    -- switched it OFF. If the game ever blocks that (Core.lua sees the
    -- ADDON_ACTION_BLOCKED for us while S.autoJoining), it is never tried
    -- automatically again: the button (a click) still works.
    C_Timer.After(10, function()
        if not (J.db.autoShare and J.db.sync.channel) then return end
        if channelId() then hideChannel(); return end           -- the game rejoined it for us
        if J.db.sync.autoJoinBlocked then return end
        S.autoJoining = true
        S:JoinChannel()
        C_Timer.After(3, function() S.autoJoining = nil end)
    end)
end
