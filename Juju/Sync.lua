----------------------------------------------------------------------
-- Juju — sharing kill/drop counts with other Juju players in-game
--
-- No program needed: addon messages (invisible) to guild, group/raid and the
-- Juju channel (joined with a click in the Juju search window).
--
--   H|id:serial,id:serial,...   "this is what I have"   (broadcast, every ~5 min)
--   R|id                        "send me that one"      (whisper to whoever has it)
--   D|id|serial|i|n|chunk       a piece of one record   (whisper back)
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
    if not ok then refused[m.kind] = "feil"; return end
    if J.Secret(res) then return end
    stats.sent = stats.sent + 1
    -- a whisper to someone who just logged off is no reason to stop whispering
    if m.kind ~= "WHISPER" and (res == 4 or (res == 7 and m.kind ~= "CHANNEL")
        or (res == 7 and m.kind == "CHANNEL" and channelId())) then
        refused[m.kind] = "avvist (" .. tostring(res) .. ")"
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
    if #entries == 0 then return end
    -- up to 9 entries per message (fits the 255-byte limit)
    for i = 1, #entries, 9 do
        local text = "H|" .. table.concat(entries, ",", i, math.min(i + 8, #entries))
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
                    push("WHISPER", sender, "R|" .. id)
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
        push("WHISPER", sender, ("D|%s|%d|%d|%d|%s"):format(id, serial, i, n, body:sub((i - 1) * CHUNK + 1, i * CHUNK)))
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

function S:OnMessage(prefix, text, kind, sender)
    if prefix ~= PREFIX or not enabled() then return end
    if J.Secret(text) or J.Secret(sender) or type(text) ~= "string" or isMe(sender) then return end
    local cmd, rest = text:match("^([HRD])|(.*)$")
    if cmd == "H" then
        onHello(sender, rest)
    elseif cmd == "R" and kind == "WHISPER" then
        local id = rest:match("^([0-9a-f]+)$")
        if id and #id >= 4 and #id <= 32 then onRequest(sender, id) end
    elseif cmd == "D" and kind == "WHISPER" then
        local id, serial, i, n, chunk = rest:match("^([0-9a-f]+)|(%d+)|(%d+)|(%d+)|([0-9:=,/]*)$")
        if id and #id >= 4 and #id <= 32 and #serial <= 12 then
            onData(sender, id, tonumber(serial), tonumber(i), tonumber(n), chunk)
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
    J.db.sync.channel = nil
    hideChannel()
    if channelId() and type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, S.CHANNEL) end
end

function S:InChannel() return channelId() ~= nil end

function S:Status()
    local n = 0
    for _ in pairs(J.db.peers) do n = n + 1 end
    local open = {}
    for _, t in ipairs(broadcastTargets()) do open[#open + 1] = t[1] == "CHANNEL" and "Juju-kanal" or t[1]:lower() end
    local closed = {}
    for k, why in pairs(refused) do closed[#closed + 1] = k:lower() .. " " .. tostring(why) end
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
            if not ok and not S.err then S.err = true; J.Print("feil i deling: " .. tostring(err)) end
        else
            nextHello = math.min(nextHello, sinceHello + 10)     -- new group/guild: say hello soon
        end
    end)
    f:SetScript("OnUpdate", function(_, dt)
        sinceSend, sinceHello = sinceSend + dt, sinceHello + dt
        if InCombatLockdown() then return end
        if sinceSend >= SEND_GAP and #queue > 0 then sinceSend = 0; sendOne() end
        if sinceHello >= nextHello then
            sinceHello, nextHello = 0, HELLO_EVERY + math.random(0, 60)
            S:Hello()
        end
        for key, box in pairs(inbox) do                      -- give up on half records
            if GetTime() - box.t > 120 then inbox[key] = nil end
        end
    end)
    -- the game rejoins a permanent channel at login: keep it out of the chat windows
    if J.db.sync.channel then C_Timer.After(5, function() if channelId() then hideChannel() end end) end
end
